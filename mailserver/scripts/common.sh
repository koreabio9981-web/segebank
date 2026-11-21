#!/bin/bash
# 공통 설정: 다른 스크립트가 이 파일을 불러옴
set -euo pipefail

MAIL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$MAIL_DIR/.env"

ok()   { echo -e "  \033[32m[OK]\033[0m   $*"; }
warn() { echo -e "  \033[33m[주의]\033[0m $*"; }
fail() { echo -e "  \033[31m[실패]\033[0m $*"; }
die()  { echo -e "\033[31m오류: $*\033[0m" >&2; exit 1; }

load_env() {
  [ -f "$ENV_FILE" ] || die ".env 가 없습니다. 먼저: cp .env.example .env && chmod 600 .env 후 값을 채우세요."
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  [ -n "${DOMAIN:-}" ] && [ "$DOMAIN" != "example.com" ] || die ".env 의 DOMAIN 을 회사 도메인으로 바꾸세요."
  if grep -q "CHANGE_ME" "$ENV_FILE"; then
    die ".env 에 CHANGE_ME 로 남은 값이 있습니다: $(grep -o '^[A-Z_]*=CHANGE_ME' "$ENV_FILE" | cut -d= -f1 | tr '\n' ' ')"
  fi
}

# EC2 메타데이터(IMDSv2)로 이 서버의 공인 IP 확인
public_ip() {
  local token
  token=$(curl -s -m 3 -X PUT "http://169.254.169.254/latest/api/token" \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true)
  if [ -n "$token" ]; then
    curl -s -m 3 -H "X-aws-ec2-metadata-token: $token" \
      http://169.254.169.254/latest/meta-data/public-ipv4 || true
  fi
}

dms() {
  if [ -t 0 ]; then docker exec -it mailserver setup "$@"; else docker exec mailserver setup "$@"; fi
}

# 비밀번호를 두 번 입력받아 변수 PW 에 저장
ask_password() {
  local p2
  while true; do
    read -rsp "  비밀번호(10자 이상): " PW; echo
    read -rsp "  비밀번호 확인: " p2; echo
    [ "${#PW}" -ge 10 ] || { warn "10자 이상 입력하세요."; continue; }
    [ "$PW" = "$p2" ] && break
    warn "두 값이 다릅니다. 다시 입력하세요."
  done
}
