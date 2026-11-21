#!/bin/bash
# 메일 서버 시작: 사전 점검 → 인증서 발급 → 전체 실행 → 첫 계정 생성
# 사용법: ./scripts/02_start.sh
. "$(dirname "$0")/common.sh"
load_env
cd "$MAIL_DIR"

echo "▶ 1/4 DNS 사전 점검"
MY_IP="$(public_ip)"
[ -n "$MY_IP" ] && echo "  이 서버 공인 IP: $MY_IP" || warn "공인 IP 를 확인하지 못했습니다(EC2 가 아니거나 메타데이터 차단)."
for h in mail webmail news; do
  got="$(dig +short A "$h.$DOMAIN" | tail -1)"
  if [ -z "$got" ]; then
    die "$h.$DOMAIN 의 A 레코드가 없습니다. Route 53 에 Elastic IP 로 등록 후 다시 실행하세요."
  elif [ -n "$MY_IP" ] && [ "$got" != "$MY_IP" ]; then
    die "$h.$DOMAIN → $got 인데 이 서버는 $MY_IP 입니다. DNS 값을 확인하세요."
  fi
  ok "$h.$DOMAIN → $got"
done

echo "▶ 2/4 HTTPS 인증서 발급 (최대 3분)"
docker compose pull -q
docker compose up -d caddy
CERT="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/mail.$DOMAIN/mail.$DOMAIN.crt"
for i in $(seq 1 36); do
  if docker compose exec -T caddy test -f "$CERT"; then ok "인증서 발급 완료"; break; fi
  [ "$i" -eq 36 ] && die "인증서 발급 실패. 'docker compose logs caddy' 확인 (80/443 포트 개방, DNS 반영 여부)."
  sleep 5
done

echo "▶ 3/4 전체 서비스 실행"
# 메일 서버는 계정이 하나도 없으면 시작을 기다리므로, 실행 직후 바로 계정을 만듭니다.
mkdir -p data/dms/config
docker compose up -d

echo "▶ 4/4 메일 계정"
sleep 5
if [ -z "$(docker exec mailserver setup email list 2>/dev/null | grep '@' || true)" ]; then
  echo "  첫 계정 info@$DOMAIN 을 만듭니다."
  ask_password
  docker exec mailserver setup email add "info@$DOMAIN" "$PW"
  unset PW
  dms alias add "postmaster@$DOMAIN" "info@$DOMAIN"
  dms alias add "dmarc@$DOMAIN" "info@$DOMAIN"
  dms alias add "abuse@$DOMAIN" "info@$DOMAIN"
  ok "info@$DOMAIN 생성, postmaster/dmarc/abuse 는 info 로 전달"
else
  ok "기존 계정 유지"
fi

echo
docker compose ps
echo
echo "웹메일 : https://webmail.$DOMAIN   (아이디: info@$DOMAIN)"
echo "메일러 : https://news.$DOMAIN/admin (아이디: $LISTMONK_ADMIN_USER)"
echo "다음   : ./scripts/check_dns.sh 로 DNS 점검"
