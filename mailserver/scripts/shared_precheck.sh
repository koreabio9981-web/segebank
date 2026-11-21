#!/bin/bash
# [공용 서버 모드] 설치 전 점검 (읽기 전용, 아무것도 바꾸지 않음)
# 사용법: ./scripts/shared_precheck.sh
set -uo pipefail
G="\033[32m"; Y="\033[33m"; R="\033[31m"; N="\033[0m"
BLOCK=0
ok()   { echo -e "  ${G}[OK]${N}   $*"; }
warn() { echo -e "  ${Y}[주의]${N} $*"; }
bad()  { echo -e "  ${R}[불가]${N} $*"; BLOCK=$((BLOCK+1)); }

echo "== 1. 운영체제 =="
. /etc/os-release
case "$ID:$VERSION_ID" in
  amzn:2023) ok "$PRETTY_NAME" ;;
  ubuntu:*)  warn "$PRETTY_NAME → Ubuntu 라면 공용 모드 스크립트 대신 수동 조정 필요" ;;
  *)         bad "$PRETTY_NAME (Amazon Linux 2023 기준 스크립트)" ;;
esac

echo "== 2. 메모리 (메일 서비스 상한 합계 약 2.4GB) =="
avail_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
total_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
swap_mb=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)
echo "  전체 ${total_mb}MB / 사용 가능 ${avail_mb}MB / 스왑 ${swap_mb}MB"
if   [ "$avail_mb" -ge 2500 ]; then ok "여유 충분"
elif [ "$avail_mb" -ge 1500 ]; then warn "빠듯함: 스왑 2GB 추가 필수, 사양 상향 권장"
else bad "여유 ${avail_mb}MB → 인스턴스 유형을 한 단계 올린 뒤 설치"; fi

echo "== 3. 디스크 =="
free_gb=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
[ "$free_gb" -ge 15 ] && ok "여유 ${free_gb}GB" || bad "여유 ${free_gb}GB (15GB 이상 필요 → EBS 볼륨 확장)"

echo "== 4. 포트 사용 현황 =="
for p in 25 465 587 993; do
  who=$(sudo ss -Htlnp "sport = :$p" 2>/dev/null | grep -o 'users:(("[^"]*' | cut -d'"' -f2 | head -1)
  [ -z "$who" ] && ok "$p 비어 있음" || bad "$p 를 '$who' 가 사용 중 → 중지 필요"
done
for p in 80 443; do
  who=$(sudo ss -Htlnp "sport = :$p" 2>/dev/null | grep -o 'users:(("[^"]*' | cut -d'"' -f2 | head -1)
  case "$who" in
    "")    ok "$p 비어 있음 (Nginx 를 새로 설치)" ;;
    nginx) ok "$p 는 Nginx 사용 중 → 설정 파일만 추가" ;;
    *)     bad "$p 를 '$who' 가 사용 중 → Nginx 로 바꾸거나 별도 EC2 권장" ;;
  esac
done
for p in 8081 8082; do
  who=$(sudo ss -Htlnp "sport = :$p" 2>/dev/null | grep -o 'users:(("[^"]*' | cut -d'"' -f2 | head -1)
  [ -z "$who" ] && ok "$p 비어 있음 (웹메일/메일러 내부용)" || bad "$p 를 '$who' 가 사용 중 → docker-compose.shared.yml 포트 변경"
done

echo "== 5. 소개뱅크 앱 =="
if command -v pm2 >/dev/null || sudo -u ec2-user bash -lc 'command -v pm2' >/dev/null 2>&1; then
  sudo -u ec2-user bash -lc 'pm2 jlist 2>/dev/null' | grep -o '"name":"[^"]*"' | head -3 | sed 's/^/  실행 중: /' || true
fi
sudo ss -Htlnp "sport = :3000" | grep -q . && ok "3000 포트 서비스 동작" || warn "3000 포트 서비스가 보이지 않음"

echo "== 6. 고정 IP =="
TOKEN=$(curl -s -m 3 -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
IP=$(curl -s -m 3 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
[ -n "$IP" ] && ok "공인 IP $IP (Elastic IP 인지 콘솔에서 확인)" || bad "공인 IP 없음 → Elastic IP 연결 필요"

echo
if [ "$BLOCK" -eq 0 ]; then
  echo -e "${G}설치 가능.${N} 다음: sudo ./scripts/shared_init_al2023.sh"
else
  echo -e "${R}불가 항목 $BLOCK 개.${N} 해결 후 다시 점검하거나 별도 EC2 를 사용하세요."
  exit 1
fi
