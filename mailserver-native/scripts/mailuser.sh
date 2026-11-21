#!/bin/bash
# 메일 계정·별칭 관리 (Docker 없음: Dovecot passwd-file + Postfix texthash)
# 사용법 (sudo):
#   ./scripts/mailuser.sh add cs@example.com             계정 추가 (비밀번호 입력)
#   ./scripts/mailuser.sh passwd cs@example.com          비밀번호 변경
#   ./scripts/mailuser.sh del cs@example.com             계정 삭제 (메일함 파일은 보존)
#   ./scripts/mailuser.sh alias sales@example.com cs@example.com   별칭(전달) 추가·변경
#   ./scripts/mailuser.sh unalias sales@example.com      별칭 삭제
#   ./scripts/mailuser.sh list                           목록
. "$(dirname "$0")/common.sh"
need_root
set -a; . "$ENV_FILE"; set +a
D="$DOMAIN"
USERS=/etc/dovecot/users VMB=/etc/postfix/vmailbox VIRT=/etc/postfix/virtual SLOGIN=/etc/postfix/sender_login
touch "$USERS" "$VMB" "$VIRT" "$SLOGIN"

valid() { [[ "$1" =~ ^[a-z0-9._+-]+@${D//./\\.}$ ]] || die "주소는 소문자 영문/숫자로, @$D 로 끝나야 합니다: $1"; }
exists() { grep -q "^$1:" "$USERS"; }
hashpw() { doveadm pw -s SHA512-CRYPT -p "$1"; }

regen() {
  # 발송 권한: 계정은 자기 주소로, 별칭은 받는 계정이 그 주소로 보낼 수 있음
  {
    cut -d: -f1 "$USERS" | awk 'NF {print $1, $1}'
    awk 'NF && $1 !~ /^#/ {print $1, $2}' "$VIRT"
  } > "$SLOGIN"
  postfix reload >/dev/null 2>&1 || true
}

case "${1:-}" in
  add)
    E="${2:?주소}"; E="${E,,}"; valid "$E"; exists "$E" && die "$E 는 이미 있습니다."
    [ -n "${PW:-}" ] || ask_password
    echo "$E:$(hashpw "$PW")" >> "$USERS"
    L="${E%@*}"; echo "$E $D/$L/" >> "$VMB"
    regen; ok "$E 생성" ;;
  passwd)
    E="${2:?주소}"; E="${E,,}"; exists "$E" || die "$E 가 없습니다."
    [ -n "${PW:-}" ] || ask_password
    H="$(hashpw "$PW")"
    awk -F: -v e="$E" -v h="$H" 'BEGIN{OFS=":"} $1==e {print e, h; next} {print}' "$USERS" > "$USERS.tmp"
    cat "$USERS.tmp" > "$USERS" && rm -f "$USERS.tmp"
    ok "$E 비밀번호 변경" ;;
  del)
    E="${2:?주소}"; E="${E,,}"; exists "$E" || die "$E 가 없습니다."
    sed -i "/^${E//./\\.}:/d" "$USERS"; sed -i "/^${E//./\\.} /d" "$VMB"
    regen; ok "$E 삭제 (메일함 /var/vmail/$D/${E%@*} 은 보존 — 필요 없으면 직접 삭제)" ;;
  alias)
    S="${2:?별칭}"; T="${3:?받을 주소}"; S="${S,,}"; valid "$S"
    exists "$S" && die "$S 는 계정입니다. 별칭으로 쓸 수 없습니다."
    sed -i "/^${S//./\\.} /d" "$VIRT"; echo "$S $T" >> "$VIRT"
    regen; ok "$S → $T" ;;
  unalias)
    S="${2:?별칭}"; sed -i "/^${S//./\\.} /d" "$VIRT"; regen; ok "$S 삭제" ;;
  list)
    echo "[계정]"; cut -d: -f1 "$USERS" | sed 's/^/  /'
    echo "[별칭]"; sed 's/^/  /' "$VIRT" ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
