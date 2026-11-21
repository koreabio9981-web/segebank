#!/bin/bash
# [공용 서버 모드] CloudFormation 없이 SES 반송·신고 알림과 역방향 DNS 설정 (내 PC 에서 실행, AWS CLI v2)
# 사용법:
#   ./infra/ses_feedback_setup.sh setup  example.com      구성 세트 + SNS 주제 생성, news.<도메인> 에 연결
#   ./infra/ses_feedback_setup.sh ptr    example.com      서버 Elastic IP 의 역방향 DNS → mail.<도메인>
#   ./infra/ses_feedback_setup.sh sns    example.com      listmonk 웹훅 구독 (listmonk Bounces→SES 켠 뒤)
#   ./infra/ses_feedback_setup.sh status example.com
set -euo pipefail
CMD="${1:-}"; DOMAIN="${2:-}"
REGION="${REGION:-ap-northeast-2}"
[ -n "$CMD" ] && [ -n "$DOMAIN" ] || { sed -n '2,7p' "$0"; exit 1; }
NAME="listmonk-$(echo "$DOMAIN" | tr '.' '-')"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
TOPIC_ARN="arn:aws:sns:$REGION:$ACCOUNT:$NAME"
a() { aws --region "$REGION" "$@"; }

case "$CMD" in
  setup)
    echo "▶ SNS 주제 $NAME"
    a sns create-topic --name "$NAME" >/dev/null
    a sns set-topic-attributes --topic-arn "$TOPIC_ARN" --attribute-name Policy --attribute-value "{
      \"Version\":\"2012-10-17\",
      \"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"ses.amazonaws.com\"},
        \"Action\":\"sns:Publish\",\"Resource\":\"$TOPIC_ARN\",
        \"Condition\":{\"StringEquals\":{\"AWS:SourceAccount\":\"$ACCOUNT\"}}}]}"
    echo "▶ SES 구성 세트 $NAME"
    a sesv2 create-configuration-set --configuration-set-name "$NAME" 2>/dev/null || echo "  (이미 있음)"
    a sesv2 create-configuration-set-event-destination --configuration-set-name "$NAME" \
      --event-destination-name bounce-complaint-to-sns \
      --event-destination "{\"Enabled\":true,\"MatchingEventTypes\":[\"BOUNCE\",\"COMPLAINT\"],\"SnsDestination\":{\"TopicArn\":\"$TOPIC_ARN\"}}" \
      2>/dev/null || echo "  (이벤트 대상 이미 있음)"
    echo "▶ news.$DOMAIN 에 연결"
    a sesv2 put-email-identity-configuration-set-attributes \
      --email-identity "news.$DOMAIN" --configuration-set-name "$NAME"
    echo "완료. 다음: 서버 설치 후 ./infra/ses_feedback_setup.sh sns $DOMAIN"
    ;;
  ptr)
    IP="$(dig +short A "mail.$DOMAIN" | tail -1)"
    [ -n "$IP" ] || { echo "mail.$DOMAIN A 레코드가 없습니다."; exit 1; }
    ALLOC="$(a ec2 describe-addresses --public-ips "$IP" --query 'Addresses[0].AllocationId' --output text 2>/dev/null || true)"
    [ -n "$ALLOC" ] && [ "$ALLOC" != "None" ] || { echo "$IP 는 Elastic IP 가 아닙니다. 서버에 Elastic IP 를 연결하세요."; exit 1; }
    a ec2 modify-address-attribute --allocation-id "$ALLOC" --domain-name "mail.$DOMAIN" >/dev/null
    echo "$IP → mail.$DOMAIN 요청 완료 (반영 수 분~수십 분)"
    ;;
  sns)
    URL="https://news.$DOMAIN/webhooks/service/ses"
    curl -s -o /dev/null -w "%{http_code}" "https://news.$DOMAIN/" | grep -qE '^(200|30[0-9])$' \
      || { echo "https://news.$DOMAIN 응답 없음 → 서버에서 shared_start.sh 먼저 실행"; exit 1; }
    a sns subscribe --topic-arn "$TOPIC_ARN" --protocol https --notification-endpoint "$URL" --output text
    echo "listmonk Settings → Bounces 에서 'Enable SES' 가 켜져 있어야 자동 승인됩니다."
    ;;
  status)
    IP="$(dig +short A "mail.$DOMAIN" | tail -1)"
    echo "mail.$DOMAIN → ${IP:-없음},  PTR: $(dig +short -x "${IP:-0.0.0.0}")"
    echo "SES 샌드박스 해제: $(a sesv2 get-account --query ProductionAccessEnabled --output text)"
    for id in "$DOMAIN" "news.$DOMAIN"; do
      echo "SES $id: $(a sesv2 get-email-identity --email-identity "$id" \
        --query '[VerifiedForSendingStatus,DkimAttributes.Status,ConfigurationSetName]' --output text 2>/dev/null || echo 없음)"
    done
    a sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --query 'Subscriptions[].[Endpoint,SubscriptionArn]' --output text 2>/dev/null || echo "SNS 주제 없음 → setup 먼저"
    ;;
  *) sed -n '2,7p' "$0"; exit 1 ;;
esac
