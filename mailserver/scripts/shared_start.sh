#!/bin/bash
# [공용 서버 모드] 점검 → Nginx 설정 → 인증서 발급 → 메일 서비스 실행 → 첫 계정
# 사용법: ./scripts/shared_start.sh
. "$(dirname "$0")/common.sh"
load_env
cd "$MAIL_DIR"

# 공용 모드 compose 파일을 항상 쓰도록 .env 에 고정
grep -q '^COMPOSE_FILE=' "$ENV_FILE" || echo 'COMPOSE_FILE=docker-compose.shared.yml' >> "$ENV_FILE"
export COMPOSE_FILE=docker-compose.shared.yml
CONF=/etc/nginx/conf.d/mail-$DOMAIN.conf

echo "▶ 1/5 DNS 점검"
MY_IP="$(public_ip)"
for h in mail webmail news; do
  got="$(dig +short A "$h.$DOMAIN" | tail -1)"
  [ -n "$got" ] || die "$h.$DOMAIN A 레코드 없음 → Route 53 에 이 서버 IP($MY_IP)로 등록"
  [ -z "$MY_IP" ] || [ "$got" = "$MY_IP" ] || die "$h.$DOMAIN → $got, 이 서버는 $MY_IP"
  ok "$h.$DOMAIN → $got"
done

echo "▶ 2/5 Nginx 설정 (인증서 발급용)"
if [ ! -f "/etc/letsencrypt/live/mail.$DOMAIN/fullchain.pem" ] || [ ! -f "/etc/letsencrypt/live/webmail.$DOMAIN/fullchain.pem" ]; then
  sed "s/__DOMAIN__/$DOMAIN/g" nginx/mail-http.conf.template | sudo tee "$CONF" >/dev/null
  sudo nginx -t && sudo systemctl reload nginx

  echo "▶ 3/5 인증서 발급"
  sudo certbot certonly --webroot -w /var/www/certbot --non-interactive --agree-tos \
    -m "$ACME_EMAIL" --cert-name "mail.$DOMAIN" -d "mail.$DOMAIN"
  sudo certbot certonly --webroot -w /var/www/certbot --non-interactive --agree-tos \
    -m "$ACME_EMAIL" --cert-name "webmail.$DOMAIN" -d "webmail.$DOMAIN" -d "news.$DOMAIN"
else
  ok "인증서 이미 있음"
fi

echo "▶ 4/5 Nginx HTTPS 설정 + 메일 서비스 실행"
sed "s/__DOMAIN__/$DOMAIN/g" nginx/mail-https.conf.template | sudo tee "$CONF" >/dev/null
if ! sudo nginx -t; then
  die "Nginx 설정 오류. 소개뱅크 영향을 막기 위해 reload 하지 않았습니다. 'sudo rm $CONF' 후 원인 확인"
fi
sudo systemctl reload nginx
mkdir -p data/dms/config
docker compose pull -q
docker compose up -d

echo "▶ 5/5 메일 계정"
sleep 5
if [ -z "$(docker exec mailserver setup email list 2>/dev/null | grep '@' || true)" ]; then
  echo "  첫 계정 info@$DOMAIN 을 만듭니다."
  ask_password
  docker exec mailserver setup email add "info@$DOMAIN" "$PW"; unset PW
  for a in postmaster dmarc abuse; do docker exec mailserver setup alias add "$a@$DOMAIN" "info@$DOMAIN"; done
  ok "info@$DOMAIN 생성 (postmaster/dmarc/abuse → info)"
else
  ok "기존 계정 유지"
fi

echo
docker compose ps
echo
docker stats --no-stream --format "  {{.Name}}\t{{.MemUsage}}"
echo
echo "웹메일 : https://webmail.$DOMAIN"
echo "메일러 : https://news.$DOMAIN/admin"
echo "소개뱅크 정상 확인: curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/"
