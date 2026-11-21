#!/bin/bash
# 메일 서버 상태 점검 (서비스, 포트, 인증서, 대기열, 자원)
. "$(dirname "$0")/common.sh"
set +e
set -a; . "$ENV_FILE" 2>/dev/null; set +a
FAILS=0
echo "== 서비스 =="
PHP_V="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)"
for s in postfix dovecot rspamd redis-server nginx "php${PHP_V}-fpm" postgresql listmonk fail2ban; do
  if systemctl is-active --quiet "$s"; then ok "$s"; else fail "$s (journalctl -u $s -n 50)"; FAILS=$((FAILS+1)); fi
done
echo "== 포트 =="
for p in 25 465 587 993 80 443; do
  ss -Hltn "sport = :$p" | grep -q . && ok "$p 열림" || { fail "$p 닫힘"; FAILS=$((FAILS+1)); }
done
ss -Hltn "sport = :9000" | grep -q 127.0.0.1 && ok "9000 (listmonk, 내부 전용)" || warn "9000 listmonk 확인 필요"
ss -Hltn "sport = :11332" | grep -q 127.0.0.1 && ok "11332 (rspamd milter, 내부 전용)" || warn "11332 rspamd 확인 필요"
echo "== 인증서 =="
for c in "mail.${DOMAIN:-}" "webmail.${DOMAIN:-}"; do
  f="/etc/letsencrypt/live/$c/fullchain.pem"
  [ -f "$f" ] && ok "$c 만료: $(openssl x509 -enddate -noout -in "$f" | cut -d= -f2)" || warn "$c 인증서 없음"
done
echo "== 메일 대기열 =="
q="$(postqueue -j 2>/dev/null | wc -l)"
[ "$q" -eq 0 ] && ok "대기 0통" || warn "대기 ${q}통 → postqueue -p 로 원인 확인"
echo "== 자원 =="
free -h | awk 'NR<=2 {print "  "$0}'
df -h / /var/vmail 2>/dev/null | awk '{print "  "$0}' | uniq
echo
[ "$FAILS" -eq 0 ] && echo "정상" || { echo "문제 $FAILS 건"; exit 1; }
