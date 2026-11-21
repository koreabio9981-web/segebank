#!/bin/bash
# 공통 함수: 다른 스크립트가 불러씀
set -euo pipefail
MAIL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$MAIL_DIR/.env"
TPL="$MAIL_DIR/templates"

ok()   { echo -e "  \033[32m[OK]\033[0m   $*"; }
warn() { echo -e "  \033[33m[주의]\033[0m $*"; }
fail() { echo -e "  \033[31m[실패]\033[0m $*"; }
step() { echo -e "\n\033[1m▶ $*\033[0m"; }
die()  { echo -e "\033[31m오류: $*\033[0m" >&2; exit 1; }

need_root() { [ "$(id -u)" -eq 0 ] || die "sudo 로 실행하세요."; }

load_env() {
  [ -f "$ENV_FILE" ] || die ".env 가 없습니다: cp .env.example .env && chmod 600 .env 후 값 입력"
  set -a; . "$ENV_FILE"; set +a
  [ -n "${DOMAIN:-}" ] && [ "$DOMAIN" != "example.com" ] || die ".env 의 DOMAIN 을 회사 도메인으로 바꾸세요."
  if grep -q "CHANGE_ME" "$ENV_FILE"; then
    die ".env 에 CHANGE_ME 가 남아 있습니다: $(grep -o '^[A-Z_]*=CHANGE_ME' "$ENV_FILE" | cut -d= -f1 | tr '\n' ' ')"
  fi
}

# 템플릿의 __키__ 를 값으로 바꿔 출력: render 파일 KEY=값 ...
render() {
  local f="$1"; shift
  local out; out="$(cat "$f")"
  local kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    out="${out//"__${k}__"/"$v"}"   # 따옴표로 감싸야 값의 \ 와 & 가 그대로 들어감
  done
  printf '%s\n' "$out"
}

public_ip() {
  local t
  t=$(curl -s -m 3 -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true)
  [ -n "$t" ] && curl -s -m 3 -H "X-aws-ec2-metadata-token: $t" http://169.254.169.254/latest/meta-data/public-ipv4 || true
}

ask_password() {
  local p2
  while true; do
    read -rsp "  비밀번호(10자 이상): " PW; echo
    read -rsp "  비밀번호 확인: " p2; echo
    [ "${#PW}" -ge 10 ] || { warn "10자 이상 입력하세요."; continue; }
    [ "$PW" = "$p2" ] && break
    warn "두 값이 다릅니다."
  done
}
