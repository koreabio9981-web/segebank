#!/bin/bash
# CloudFormation 스택 생성/업데이트
# 사용법: ./infra/deploy.sh            (infra/params.env 사용)
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PARAMS="$DIR/params.env"
[ -f "$PARAMS" ] || { echo "infra/params.env 가 없습니다: cp infra/params.env.example infra/params.env"; exit 1; }
command -v aws >/dev/null || { echo "AWS CLI 가 필요합니다 (aws --version)"; exit 1; }

# 주석·빈 줄 제거 후 KEY=VALUE 읽기
OVERRIDES=()
while IFS= read -r line; do
  line="${line%%#*}"; line="$(echo "$line" | xargs)"
  [ -z "$line" ] && continue
  key="${line%%=*}"; val="${line#*=}"
  case "$key" in
    STACK_NAME) STACK_NAME="$val" ;;
    REGION)     REGION="$val" ;;
    *)          OVERRIDES+=("$key=$val") ;;
  esac
done < "$PARAMS"
: "${STACK_NAME:?params.env 에 STACK_NAME 필요}" "${REGION:?params.env 에 REGION 필요}"

grep -qE '^DomainName=example\.com' "$PARAMS" && { echo "DomainName 을 회사 도메인으로 바꾸세요."; exit 1; }

echo "▶ 계정 확인: $(aws sts get-caller-identity --query Arn --output text)"
echo "▶ 템플릿 검사"
aws cloudformation validate-template --region "$REGION" \
  --template-body "file://$DIR/mail-server.yaml" >/dev/null

echo "▶ 배포: $STACK_NAME ($REGION)  — 보통 5~10분"
aws cloudformation deploy --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --template-file "$DIR/mail-server.yaml" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides "${OVERRIDES[@]}"

echo
aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output table
echo
echo "다음: ./infra/post_deploy.sh ptr   (역방향 DNS 설정)"
echo "알림 메일함에서 'AWS Notification - Subscription Confirmation' 메일의 링크를 눌러 승인하세요."
