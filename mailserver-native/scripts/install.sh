#!/bin/bash
# 메일 서버 설치 (Docker 없이 Ubuntu 24.04 패키지로 직접 설치)
#   Postfix(수신·발송) + Dovecot(IMAP) + Rspamd(스팸) + Roundcube(웹메일)
#   + listmonk(메일러) + PostgreSQL + Nginx + certbot + Fail2ban
# 사용법: sudo ./scripts/install.sh      (여러 번 실행해도 안전 — 설정만 다시 맞춤)
#         SKIP_DNS_CHECK=1 sudo -E ./scripts/install.sh   (DNS 반영 전 테스트용, 인증서 발급은 실패함)
. "$(dirname "$0")/common.sh"
need_root
load_env
export DEBIAN_FRONTEND=noninteractive
D="$DOMAIN"
LE=/etc/letsencrypt/live

step "1/11 DNS 점검"
if [ "${SKIP_DNS_CHECK:-0}" != 1 ]; then
  MY_IP="$(public_ip)"
  for h in mail webmail news; do
    got="$(dig +short A "$h.$D" @8.8.8.8 | tail -1)"
    [ -n "$got" ] || die "$h.$D A 레코드가 없습니다. Route 53 에 이 서버 IP(${MY_IP:-?})로 등록하세요."
    [ -z "$MY_IP" ] || [ "$got" = "$MY_IP" ] || die "$h.$D → $got 인데 이 서버는 $MY_IP 입니다."
    ok "$h.$D → $got"
  done
else
  warn "DNS 점검 건너뜀"
fi

step "2/11 패키지 설치 (5~10분)"
debconf-set-selections <<SEL
postfix postfix/main_mailer_type select Internet Site
postfix postfix/mailname string mail.$D
roundcube-core roundcube/dbconfig-install boolean true
roundcube-core roundcube/database-type select sqlite3
roundcube-core roundcube/reconfigure-webserver multiselect
roundcube-core roundcube/restart-webserver boolean false
SEL
apt-get update -y
# 웹서버를 먼저 설치해 Apache 가 딸려 오지 않게 함
apt-get install -y --no-install-recommends nginx php8.3-fpm
apt-get install -y --no-install-recommends \
  postfix dovecot-core dovecot-imapd dovecot-lmtpd dovecot-sieve \
  rspamd redis-server postgresql certbot python3-certbot-nginx \
  fail2ban python3-systemd rsyslog sqlite3 openssl \
  roundcube-core roundcube-sqlite3 roundcube-plugins \
  php8.3-intl php8.3-mbstring php8.3-sqlite3 php8.3-xml php8.3-zip php8.3-gd php8.3-curl
systemctl disable --now apache2 2>/dev/null || true
ok "패키지 설치 완료"

step "3/11 메일 저장소 계정(vmail)"
getent group vmail >/dev/null || groupadd -g 5000 vmail
id vmail >/dev/null 2>&1 || useradd -u 5000 -g vmail -s /usr/sbin/nologin -d /var/vmail -M vmail
mkdir -p /var/vmail && chown vmail:vmail /var/vmail && chmod 770 /var/vmail
ok "/var/vmail"

step "4/11 HTTPS 인증서"
mkdir -p /var/www/certbot
rm -f /etc/nginx/sites-enabled/default
if [ ! -f "$LE/mail.$D/fullchain.pem" ] || [ ! -f "$LE/webmail.$D/fullchain.pem" ]; then
  render "$TPL/nginx-http.conf" DOMAIN="$D" > /etc/nginx/sites-available/mail.conf
  ln -sf /etc/nginx/sites-available/mail.conf /etc/nginx/sites-enabled/mail.conf
  nginx -t && systemctl enable --now nginx && systemctl reload nginx
  certbot certonly --webroot -w /var/www/certbot --non-interactive --agree-tos -m "$ACME_EMAIL" \
    --cert-name "mail.$D" -d "mail.$D"
  certbot certonly --webroot -w /var/www/certbot --non-interactive --agree-tos -m "$ACME_EMAIL" \
    --cert-name "webmail.$D" -d "webmail.$D" -d "news.$D"
fi
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/mail-reload.sh <<'HOOK'
#!/bin/bash
systemctl reload nginx postfix dovecot
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/mail-reload.sh
ok "인증서 준비 (자동 갱신 후 nginx·postfix·dovecot 반영)"

step "5/11 Dovecot (IMAP 993, 메일함)"
[ -f /etc/dovecot/dovecot.conf.dist ] || cp /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.dist
render "$TPL/dovecot.conf" DOMAIN="$D" > /etc/dovecot/dovecot.conf
mkdir -p /etc/dovecot/sieve
cp "$TPL/spam-to-junk.sieve" /etc/dovecot/sieve/spam-to-junk.sieve
sievec /etc/dovecot/sieve/spam-to-junk.sieve
touch /etc/dovecot/users && chown root:dovecot /etc/dovecot/users && chmod 640 /etc/dovecot/users
doveconf -n >/dev/null
ok "Dovecot 설정 검사 통과"

step "6/11 Postfix (수신 25, 발송 465/587, SES 중계)"
touch /etc/postfix/vmailbox /etc/postfix/virtual /etc/postfix/sender_login
printf '[%s]:587 %s:%s\n' "$SES_SMTP_HOST" "$SES_SMTP_USER" "$SES_SMTP_PASS" > /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd && postmap /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd.db
P=(
  "myhostname = mail.$D"
  "mydomain = $D"
  'myorigin = $mydomain'
  "mydestination = localhost"
  "mynetworks = 127.0.0.0/8"
  "inet_interfaces = all"
  "inet_protocols = ipv4"
  'smtpd_banner = $myhostname ESMTP'
  "biff = no"
  "append_dot_mydomain = no"
  "recipient_delimiter = +"
  "message_size_limit = 26214400"
  "mailbox_size_limit = 0"
  "virtual_mailbox_domains = $D"
  "virtual_mailbox_maps = texthash:/etc/postfix/vmailbox"
  "virtual_alias_maps = texthash:/etc/postfix/virtual"
  "virtual_transport = lmtp:unix:private/dovecot-lmtp"
  "smtpd_sasl_type = dovecot"
  "smtpd_sasl_path = private/auth"
  "smtpd_sasl_auth_enable = no"
  "smtpd_sender_login_maps = texthash:/etc/postfix/sender_login"
  "smtpd_tls_cert_file = $LE/mail.$D/fullchain.pem"
  "smtpd_tls_key_file = $LE/mail.$D/privkey.pem"
  "smtpd_tls_security_level = may"
  "smtpd_tls_auth_only = yes"
  "smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1"
  "smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1"
  "smtpd_helo_required = yes"
  "disable_vrfy_command = yes"
  "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination"
  "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"
  "relayhost = [$SES_SMTP_HOST]:587"
  "smtp_sasl_auth_enable = yes"
  "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
  "smtp_sasl_security_options = noanonymous"
  "smtp_sasl_tls_security_options = noanonymous"
  "smtp_tls_security_level = encrypt"
  "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
  "smtpd_milters = inet:127.0.0.1:11332"
  'non_smtpd_milters = $smtpd_milters'
  "milter_default_action = accept"
  "milter_protocol = 6"
  "milter_mail_macros = i {mail_addr} {client_addr} {client_name} {auth_authen}"
)
postconf -e "${P[@]}"
# 제출 포트: 로그인한 사용자만, 자기 주소로만 발송
for svc in submission smtps; do
  if [ "$svc" = submission ]; then postconf -M "submission/inet=submission inet n - y - - smtpd"
  else postconf -M "smtps/inet=smtps inet n - y - - smtpd"; fi
  postconf -P "$svc/inet/syslog_name=postfix/$svc" \
              "$svc/inet/smtpd_sasl_auth_enable=yes" \
              "$svc/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject" \
              "$svc/inet/smtpd_sender_restrictions=reject_sender_login_mismatch" \
              "$svc/inet/smtpd_recipient_restrictions=permit_sasl_authenticated,reject"
done
postconf -P "submission/inet/smtpd_tls_security_level=encrypt" "smtps/inet/smtpd_tls_wrappermode=yes"
postfix check
ok "Postfix 설정 검사 통과"

step "7/11 Rspamd (스팸 필터)"
install -m 644 "$TPL/rspamd-worker-proxy.inc"    /etc/rspamd/local.d/worker-proxy.inc
install -m 644 "$TPL/rspamd-milter_headers.conf" /etc/rspamd/local.d/milter_headers.conf
install -m 644 "$TPL/rspamd-redis.conf"          /etc/rspamd/local.d/redis.conf
install -m 644 "$TPL/rspamd-actions.conf"        /etc/rspamd/local.d/actions.conf
rspamadm configtest >/dev/null
systemctl enable --now redis-server rspamd
systemctl restart rspamd
ok "Rspamd 설정 검사 통과"

step "8/11 웹메일 (Roundcube)"
RC_ROOT=/var/lib/roundcube/public_html; [ -d "$RC_ROOT" ] || RC_ROOT=/var/lib/roundcube
PHP_V="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
PHP_SOCK="/run/php/php$PHP_V-fpm.sock"
systemctl enable --now "php$PHP_V-fpm"
RC=/etc/roundcube/config.inc.php
sed -i '/^\/\/ BEGIN mail-install/,/^\/\/ END mail-install/d' "$RC"
cat >> "$RC" <<PHP
// BEGIN mail-install (install.sh 가 관리, 직접 수정 금지)
\$config['imap_host'] = 'ssl://mail.$D:993';
\$config['smtp_host'] = 'ssl://mail.$D:465';
\$config['smtp_user'] = '%u';
\$config['smtp_pass'] = '%p';
\$config['username_domain'] = '$D';
\$config['product_name'] = '$D 웹메일';
\$config['language'] = 'ko_KR';
\$config['skin'] = 'elastic';
\$config['plugins'] = ['archive', 'zipdownload'];
\$config['max_message_size'] = '25M';
\$config['login_rate_limit'] = 5;
// END mail-install
PHP
php -l "$RC" >/dev/null
mkdir -p /var/log/roundcube && touch /var/log/roundcube/errors.log && chown -R www-data:www-data /var/log/roundcube
render "$TPL/nginx-https.conf" DOMAIN="$D" RC_ROOT="$RC_ROOT" PHP_SOCK="$PHP_SOCK" > /etc/nginx/sites-available/mail.conf
ln -sf /etc/nginx/sites-available/mail.conf /etc/nginx/sites-enabled/mail.conf
nginx -t
ok "Roundcube ($RC_ROOT), PHP ($PHP_SOCK)"

step "9/11 메일러 (listmonk $LISTMONK_VERSION + PostgreSQL)"
# listmonk 는 DB 비밀번호의 특수문자를 처리하지 못하므로 영문·숫자만 사용 (auto = 자동 생성 후 .env 에 저장)
if [ "${LISTMONK_DB_PASSWORD:-auto}" = auto ]; then
  LISTMONK_DB_PASSWORD="$(openssl rand -hex 24)"
  sed -i "s|^LISTMONK_DB_PASSWORD=.*|LISTMONK_DB_PASSWORD=$LISTMONK_DB_PASSWORD|" "$ENV_FILE"
fi
[[ "$LISTMONK_DB_PASSWORD" =~ ^[A-Za-z0-9]{16,}$ ]] || die "LISTMONK_DB_PASSWORD 는 영문·숫자 16자 이상이어야 합니다 (또는 auto)."
systemctl enable --now postgresql
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='listmonk'" | grep -q 1; then
  sudo -u postgres psql -qc "ALTER ROLE listmonk WITH LOGIN PASSWORD '$LISTMONK_DB_PASSWORD'"
else
  sudo -u postgres psql -qc "CREATE ROLE listmonk WITH LOGIN PASSWORD '$LISTMONK_DB_PASSWORD'"
fi
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='listmonk'" | grep -q 1 \
  || sudo -u postgres createdb -O listmonk listmonk
id listmonk >/dev/null 2>&1 || useradd --system --home /opt/listmonk --shell /usr/sbin/nologin listmonk
mkdir -p /opt/listmonk/uploads
if [ "$(cat /opt/listmonk/VERSION 2>/dev/null)" != "$LISTMONK_VERSION" ]; then
  ARCH="$(dpkg --print-architecture)"
  curl -fsSL "https://github.com/knadh/listmonk/releases/download/v$LISTMONK_VERSION/listmonk_${LISTMONK_VERSION}_linux_${ARCH}.tar.gz" \
    -o /tmp/listmonk.tgz
  tar -xzf /tmp/listmonk.tgz -C /opt/listmonk listmonk
  echo "$LISTMONK_VERSION" > /opt/listmonk/VERSION
fi
toml_esc() { local s="${1//\\/\\\\}"; printf '%s' "${s//\"/\\\"}"; }
render "$TPL/listmonk.toml" LISTMONK_DB_PASSWORD="$LISTMONK_DB_PASSWORD" > /opt/listmonk/config.toml
printf 'LISTMONK_ADMIN_USER="%s"\nLISTMONK_ADMIN_PASSWORD="%s"\n' \
  "$(toml_esc "$LISTMONK_ADMIN_USER")" "$(toml_esc "$LISTMONK_ADMIN_PASSWORD")" > /opt/listmonk/admin.env
chown -R listmonk:listmonk /opt/listmonk
chown root:listmonk /opt/listmonk/config.toml /opt/listmonk/admin.env
chmod 640 /opt/listmonk/config.toml /opt/listmonk/admin.env
install -m 644 "$TPL/listmonk.service" /etc/systemd/system/listmonk.service
systemctl daemon-reload
systemctl enable listmonk
systemctl restart listmonk
for _ in $(seq 1 30); do curl -fs -o /dev/null http://127.0.0.1:9000/ && break; sleep 2; done
curl -fs -o /dev/null http://127.0.0.1:9000/ && ok "listmonk 응답" || warn "listmonk 응답 없음 → journalctl -u listmonk -n 50"

step "10/11 Fail2ban + 서비스 시작"
install -m 644 "$TPL/fail2ban-mail.local" /etc/fail2ban/jail.d/mail.local
systemctl enable --now dovecot postfix nginx fail2ban
systemctl restart dovecot postfix "php$PHP_V-fpm" fail2ban
systemctl reload nginx
ok "서비스 시작"

step "11/11 첫 메일 계정"
if [ ! -s /etc/dovecot/users ]; then
  echo "  첫 계정 info@$D 의 비밀번호를 정하세요."
  ask_password
  PW="$PW" "$MAIL_DIR/scripts/mailuser.sh" add "info@$D"
  unset PW
  for a in postmaster abuse dmarc; do "$MAIL_DIR/scripts/mailuser.sh" alias "$a@$D" "info@$D"; done
else
  ok "기존 계정 유지 ($(wc -l < /etc/dovecot/users)개)"
fi

echo
"$MAIL_DIR/scripts/status.sh" || true
echo
echo "웹메일 : https://webmail.$D   (아이디: info@$D)"
echo "메일러 : https://news.$D/admin (아이디: $LISTMONK_ADMIN_USER)"
echo "메일 프로그램: IMAP mail.$D:993(SSL) / SMTP mail.$D:465(SSL) 또는 587(STARTTLS)"
