#!/bin/bash
# DNS·메일 설정 점검 (어디서든 실행 가능, dig 필요)
# 사용법: ./scripts/check_dns.sh            (.env 의 DOMAIN 사용)
#         ./scripts/check_dns.sh example.com
. "$(dirname "$0")/common.sh"

if [ -n "${1:-}" ]; then DOMAIN="$1"; else load_env; fi
command -v dig >/dev/null || die "dig 가 필요합니다: sudo apt install -y dnsutils"
FAILS=0
bad() { fail "$*"; FAILS=$((FAILS+1)); }
txt() { dig +short TXT "$1" | tr -d '"'; }

echo "== $DOMAIN 점검 =="

ip="$(dig +short A "mail.$DOMAIN" | tail -1)"
[ -n "$ip" ] && ok "A     mail.$DOMAIN → $ip" || bad "A     mail.$DOMAIN 없음"

mx="$(dig +short MX "$DOMAIN")"
echo "$mx" | grep -q "mail.$DOMAIN" && ok "MX    $mx" || bad "MX    mail.$DOMAIN 를 가리키지 않음 (현재: ${mx:-없음})"

if [ -n "$ip" ]; then
  ptr="$(dig +short -x "$ip")"
  [ "$ptr" = "mail.$DOMAIN." ] && ok "PTR   $ip → $ptr" || bad "PTR   역방향 DNS 가 mail.$DOMAIN 이 아님 (현재: ${ptr:-없음}) → EC2 탄력적 IP 에서 설정"
fi

spf="$(txt "$DOMAIN" | grep '^v=spf1' || true)"
if [ -z "$spf" ]; then bad "SPF   없음"
elif echo "$spf" | grep -q "include:amazonses.com"; then ok "SPF   $spf"
else bad "SPF   include:amazonses.com 누락 ($spf)"; fi

dmarc="$(txt "_dmarc.$DOMAIN" | grep '^v=DMARC1' || true)"
[ -n "$dmarc" ] && ok "DMARC $dmarc" || bad "DMARC _dmarc.$DOMAIN 없음"

for sub in "$DOMAIN" "news.$DOMAIN"; do
  # SES Easy DKIM 은 <토큰>._domainkey 형태 CNAME 3개. 토큰을 모르므로 SES 콘솔 상태도 함께 확인
  echo "  [안내] $sub 의 SES DKIM 은 SES 콘솔 → 자격 증명 → '$sub' 에서 'DKIM: 성공' 인지 확인"
done

nspf="$(txt "news.$DOMAIN" | grep '^v=spf1' || true)"
[ -n "$nspf" ] && ok "SPF   news.$DOMAIN $nspf" || warn "SPF   news.$DOMAIN 없음 (SES 사용자 지정 MAIL FROM 을 쓰면 bounce.news 쪽에 있으면 됨)"

for h in webmail news; do
  [ -n "$(dig +short A "$h.$DOMAIN")" ] && ok "A     $h.$DOMAIN" || bad "A     $h.$DOMAIN 없음"
done

echo
if [ "$FAILS" -eq 0 ]; then echo "모든 필수 항목 통과"; else echo "필수 항목 $FAILS 개 실패 → docs/MAIL_SERVER_SETUP.md 의 DNS 표 참고"; exit 1; fi
