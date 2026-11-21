#!/bin/bash
# 스택 생성 후 CloudFormation 이 못 하는 작업
# 사용법:
#   ./infra/post_deploy.sh ptr      역방향 DNS(PTR) → mail.<도메인>      (스택 생성 직후)
#   ./infra/post_deploy.sh ses      기존 SES 자격 증명에 구성 세트 연결 (CreateSesIdentities=false 일 때)
#   ./infra/post_deploy.sh sns      SES 반송·신고 알림 → listmonk 웹훅 구독 (listmonk 설정 완료 후)
#   ./infra/post_deploy.sh status   현재 상태 확인
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
STACK_NAME="$(grep -E '^STACK_NAME=' "$DIR/params.env" | cut -d= -f2 | xargs)"
REGION="$(grep -E '^REGION=' "$DIR/params.env" | cut -d= -f2 | xargs)"

out() {
  aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
DOMAIN="$(out DomainName)"

case "${1:-}" in
  ptr)
    ALLOC="$(out EipAllocationId)"; IP="$(out PublicIp)"
    echo "▶ $IP → mail.$DOMAIN"
    if [ "$(dig +short A "mail.$DOMAIN" | tail -1)" != "$IP" ]; then
      echo "mail.$DOMAIN 의 A 레코드가 아직 $IP 가 아닙니다. DNS 반영 후 다시 실행하세요."; exit 1
    fi
    aws ec2 modify-address-attribute --region "$REGION" --allocation-id "$ALLOC" --domain-name "mail.$DOMAIN" >/dev/null
    echo "요청 완료(반영까지 수 분~수십 분). 확인: ./infra/post_deploy.sh status"
    ;;
  ses)
    CS="$(out SesConfigurationSet)"
    aws sesv2 put-email-identity-configuration-set-attributes --region "$REGION" \
      --email-identity "news.$DOMAIN" --configuration-set-name "$CS"
    echo "news.$DOMAIN 발송은 이제 반송·신고가 SNS 로 보고됩니다 (구성 세트: $CS)"
    ;;
  sns)
    TOPIC="$(out SesFeedbackTopicArn)"
    URL="https://news.$DOMAIN/webhooks/service/ses"
    curl -s -o /dev/null -w "%{http_code}" "https://news.$DOMAIN/" | grep -qE '^(200|30[0-9])$' \
      || { echo "https://news.$DOMAIN 이 응답하지 않습니다. 서버에서 02_start.sh 실행 후 다시 시도"; exit 1; }
    aws sns subscribe --region "$REGION" --topic-arn "$TOPIC" --protocol https \
      --notification-endpoint "$URL" --output text
    echo "listmonk Settings → Bounces 에서 'Enable SES' 가 켜져 있어야 자동 승인됩니다."
    echo "확인: ./infra/post_deploy.sh status  (SubscriptionArn 이 PendingConfirmation 이 아니면 성공)"
    ;;
  status)
    IP="$(out PublicIp)"
    echo "IP          : $IP"
    echo "A mail      : $(dig +short A "mail.$DOMAIN" | tail -1)"
    echo "PTR         : $(dig +short -x "$IP")"
    aws ec2 describe-addresses-attribute --region "$REGION" --allocation-ids "$(out EipAllocationId)" \
      --attribute domain-name --query 'Addresses[0].[PtrRecord,PtrRecordUpdate.Status]' --output text 2>/dev/null \
      | sed 's/^/PTR(AWS)    : /' || true
    echo "SES 발송 상태: $(aws sesv2 get-account --region "$REGION" --query 'ProductionAccessEnabled' --output text 2>/dev/null) (True = 샌드박스 해제)"
    for id in "$DOMAIN" "news.$DOMAIN"; do
      echo "SES $id : $(aws sesv2 get-email-identity --region "$REGION" --email-identity "$id" \
        --query '[VerifiedForSendingStatus,DkimAttributes.Status,MailFromAttributes.MailFromDomainStatus,ConfigurationSetName]' \
        --output text 2>/dev/null || echo '없음')"
    done
    echo "SNS 구독   :"
    aws sns list-subscriptions-by-topic --region "$REGION" --topic-arn "$(out SesFeedbackTopicArn)" \
      --query 'Subscriptions[].[Endpoint,SubscriptionArn]' --output text
    ;;
  *) sed -n '2,7p' "$0"; exit 1 ;;
esac
