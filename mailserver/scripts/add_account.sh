#!/bin/bash
# 메일 계정·별칭 관리
# 사용법:
#   ./scripts/add_account.sh add cs@example.com          계정 추가(비밀번호 입력)
#   ./scripts/add_account.sh passwd cs@example.com       비밀번호 변경
#   ./scripts/add_account.sh del cs@example.com          계정 삭제
#   ./scripts/add_account.sh alias sales@example.com cs@example.com   별칭(전달) 추가
#   ./scripts/add_account.sh list                        목록
. "$(dirname "$0")/common.sh"

case "${1:-}" in
  add)    ask_password; docker exec mailserver setup email add "${2:?주소}" "$PW" && ok "$2 생성" ;;
  passwd) ask_password; docker exec mailserver setup email update "${2:?주소}" "$PW" && ok "$2 변경" ;;
  del)    dms email del "${2:?주소}" ;;
  alias)  dms alias add "${2:?별칭}" "${3:?받을 주소}" ;;
  list)   dms email list; echo; dms alias list ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
