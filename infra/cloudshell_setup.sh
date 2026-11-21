#!/bin/bash
# 메일 전용 서버(별도 EC2) 원스톱 구축 — AWS CloudShell(서울 리전)에서 실행
#
# 하는 일:
#   1) 도메인·VPC·서브넷·키 페어·기존 DNS/SES 상태를 자동 조회해 params.env 생성
#   2) CloudFormation 스택 배포 (EC2, 고정 IP, 방화벽, 백업, 경보, DNS)
#   3) 역방향 DNS(PTR) 설정, SES 구성 세트 연결
#   4) mailserver/ 설치 파일을 S3 → Session Manager 로 서버 /opt/mail 에 설치
#
# 사용법 (CloudShell):
#   저장소 파일 업로드 후 압축 해제 → cd segebank → bash infra/cloudshell_setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
REGION="$AWS_DEFAULT_REGION"
PARAMS="$ROOT/infra/params.env"

c_ok()  { echo -e "  \033[32m✔\033[0m $*"; }
c_inf() { echo -e "  \033[36mℹ\033[0m $*"; }
c_wrn() { echo -e "  \033[33m!\033[0m $*"; }
die()   { echo -e "\033[31m오류: $*\033[0m" >&2; exit 1; }
ask()   { local p="$1" d="${2:-}" v; read -rp "  $p${d:+ [$d]}: " v; echo "${v:-$d}"; }

[ -f infra/mail-server.yaml ] && [ -d mailserver ] || die "저장소 최상위 폴더(segebank)에서 실행하세요."
command -v aws >/dev/null || die "AWS CLI 가 없습니다. AWS 콘솔의 CloudShell 에서 실행하세요."
command -v dig >/dev/null || sudo dnf install -y -q bind-utils >/dev/null 2>&1 || true

echo "== 0. 계정 확인 =="
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)" || die "AWS 인증 실패"
c_ok "계정 $ACCOUNT / 리전 $REGION"

echo "== 1. 도메인 =="
DOMAIN="$(ask '회사 도메인 (예: example.com)')"
DOMAIN="${DOMAIN,,}"; DOMAIN="${DOMAIN%.}"
[[ "$DOMAIN" =~ ^([a-z0-9-]+\.)+[a-z]{2,}$ ]] || die "도메인 형식이 올바르지 않습니다: $DOMAIN"
ZONE_ID="$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN" \
  --query "HostedZones[?Name=='$DOMAIN.' && Config.PrivateZone==\`false\`].Id | [0]" --output text)"
[ "$ZONE_ID" != "None" ] && [ -n "$ZONE_ID" ] || die "Route 53 에 $DOMAIN 공개 호스팅 영역이 없습니다."
ZONE_ID="${ZONE_ID##*/}"
c_ok "호스팅 영역 $ZONE_ID"

# 루트에 MX / SPF 가 이미 있으면 DNS 자동 생성 끔 (충돌 방지)
APEX="$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
  --query "ResourceRecordSets[?Name=='$DOMAIN.' && (Type=='MX' || Type=='TXT')].[Type,ResourceRecords[].Value|join(' ',@)]" --output text)"
CONFLICT=""
echo "$APEX" | grep -q '^MX' && CONFLICT="MX"
echo "$APEX" | grep -q 'v=spf1' && CONFLICT="$CONFLICT SPF"
for h in mail webmail news; do
  aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
    --query "ResourceRecordSets[?Name=='$h.$DOMAIN.'].Type" --output text | grep -q . && CONFLICT="$CONFLICT $h"
done
if [ -n "$CONFLICT" ]; then
  CREATE_DNS=false
  c_wrn "기존 레코드 발견($CONFLICT) → DNS 는 자동 생성하지 않습니다. 배포 후 안내대로 직접 수정하세요."
else
  CREATE_DNS=true
  c_ok "DNS 레코드 자동 생성 (A·MX·SPF·DMARC)"
fi

# SES 자격 증명이 이미 있으면 새로 만들지 않음
if aws sesv2 get-email-identity --email-identity "$DOMAIN" >/dev/null 2>&1; then
  CREATE_SES=false; c_ok "SES $DOMAIN 이미 인증됨 → 기존 것 사용"
  aws sesv2 get-email-identity --email-identity "news.$DOMAIN" >/dev/null 2>&1 \
    || c_wrn "SES 에 news.$DOMAIN 이 없습니다. SES 콘솔에서 추가 인증하세요(고객 발송용)."
else
  CREATE_SES=true; c_inf "SES 자격 증명 없음 → 템플릿이 $DOMAIN, news.$DOMAIN 을 생성"
fi
[ "$(aws sesv2 get-account --query ProductionAccessEnabled --output text)" = "True" ] \
  && c_ok "SES 샌드박스 해제됨" || c_wrn "SES 가 아직 샌드박스입니다(인증된 주소로만 발송 가능)."

echo "== 2. 네트워크 =="
VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
[ "$VPC_ID" != "None" ] || die "기본 VPC 가 없습니다. VPC 콘솔 → 작업 → 기본 VPC 생성 후 다시 실행"
SUBNET_ID="$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
  "Name=availability-zone,Values=${REGION}a,${REGION}c" --query 'Subnets[0].SubnetId' --output text)"
[ "$SUBNET_ID" != "None" ] || SUBNET_ID="$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" \
  Name=default-for-az,Values=true --query 'Subnets[0].SubnetId' --output text)"
c_ok "VPC $VPC_ID / 서브넷 $SUBNET_ID"

echo "== 3. 키 페어 =="
KEY_NAME="$(ask '키 페어 이름' mail-key)"
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  c_ok "기존 키 페어 $KEY_NAME 사용 (.pem 파일은 처음 만들 때 받은 것)"
else
  aws ec2 create-key-pair --key-name "$KEY_NAME" --key-type ed25519 \
    --query KeyMaterial --output text > "$HOME/$KEY_NAME.pem"
  chmod 400 "$HOME/$KEY_NAME.pem"
  c_ok "새 키 페어 생성 → $HOME/$KEY_NAME.pem"
  c_wrn "CloudShell 오른쪽 위 [작업 → 파일 다운로드] 에서 $HOME/$KEY_NAME.pem 을 꼭 내려받으세요."
fi

echo "== 4. 접속 허용 IP·알림 메일·서버 크기 =="
c_inf "내 PC 브라우저에서 https://checkip.amazonaws.com 을 열면 내 IP 가 보입니다."
MYIP="$(ask '내 PC 공인 IP (SSH 허용)')"
[[ "$MYIP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "IP 형식 오류: $MYIP"
ALERT="$(ask '장애·비용 알림 받을 이메일')"
[[ "$ALERT" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || die "이메일 형식 오류"
TYPE="$(ask '서버 크기 t3.small(월 약 \$19) / t3.medium(월 약 \$38)' t3.small)"
case "$TYPE" in t3.small) BUDGET=40 ;; t3.medium) BUDGET=70 ;; *) die "t3.small 또는 t3.medium" ;; esac

STACK="$(ask 'CloudFormation 스택 이름' company-mail)"
EXIST="$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mail.$DOMAIN" \
  Name=instance-state-name,Values=pending,running,stopped --query 'Reservations[].Instances[].InstanceId' --output text)"
if [ -n "$EXIST" ] && ! aws cloudformation describe-stacks --stack-name "$STACK" >/dev/null 2>&1; then
  c_wrn "이미 mail.$DOMAIN 이름의 EC2 가 있습니다: $EXIST (중복 비용 주의)"
fi

cat > "$PARAMS" <<EOF
STACK_NAME=$STACK
REGION=$REGION
DomainName=$DOMAIN
HostedZoneId=$ZONE_ID
CreateDnsRecords=$CREATE_DNS
CreateSesIdentities=$CREATE_SES
VpcId=$VPC_ID
SubnetId=$SUBNET_ID
InstanceType=$TYPE
DiskSizeGiB=30
KeyPairName=$KEY_NAME
SshAllowedCidr=$MYIP/32
RepoUrl=
RepoBranch=
AlertEmail=$ALERT
MonthlyBudgetUsd=$BUDGET
EOF

echo
echo "== 확인 =="
sed 's/^/  /' "$PARAMS"
echo
[ "$(ask '이 설정으로 서버를 만들까요? (yes 입력)')" = "yes" ] || { echo "취소했습니다. 설정은 $PARAMS 에 저장됨"; exit 0; }

echo "== 5. 배포 (5~10분) =="
bash infra/deploy.sh

out() { aws cloudformation describe-stacks --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
IP="$(out PublicIp)"; IID="$(out InstanceId)"; BUCKET="$(out BackupBucketName)"; CS="$(out SesConfigurationSet)"

echo "== 6. SES 구성 세트 연결 =="
if [ "$CREATE_SES" = false ] && aws sesv2 get-email-identity --email-identity "news.$DOMAIN" >/dev/null 2>&1; then
  aws sesv2 put-email-identity-configuration-set-attributes --email-identity "news.$DOMAIN" --configuration-set-name "$CS"
  c_ok "news.$DOMAIN → $CS"
else
  c_inf "템플릿이 처리했거나 news.$DOMAIN 이 없어 건너뜀"
fi

echo "== 7. 역방향 DNS =="
if [ "$CREATE_DNS" = true ]; then
  for _ in $(seq 1 18); do [ "$(dig +short A "mail.$DOMAIN" @8.8.8.8 | tail -1)" = "$IP" ] && break; sleep 10; done
  bash infra/post_deploy.sh ptr || c_wrn "PTR 실패 → DNS 반영 후 'bash infra/post_deploy.sh ptr' 재실행"
else
  c_wrn "mail.$DOMAIN A 레코드를 $IP 로 직접 등록한 뒤 'bash infra/post_deploy.sh ptr' 실행"
fi

echo "== 8. 메일 서버 파일 설치 (Session Manager) =="
tar -czf /tmp/mailserver.tgz -C "$ROOT" mailserver
aws s3 cp /tmp/mailserver.tgz "s3://$BUCKET/bootstrap/mailserver.tgz" --only-show-errors
echo -n "  서버가 Session Manager 에 등록되길 기다리는 중"
for _ in $(seq 1 40); do
  [ "$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$IID" \
       --query 'length(InstanceInformationList)' --output text)" = "1" ] && break
  echo -n "."; sleep 15
done; echo
# 서버에서 실행할 명령 (JSON 으로 만들어 전달: 따옴표 깨짐 방지)
DOMAIN="$DOMAIN" BUCKET="$BUCKET" REGION="$REGION" python3 - > /tmp/ssm-params.json <<'PY'
import json, os
d, b, r = os.environ["DOMAIN"], os.environ["BUCKET"], os.environ["REGION"]
cmds = [
  "for i in $(seq 1 60); do [ -f /var/lib/mail-bootstrap-done ] && break; sleep 10; done",
  "command -v aws >/dev/null || snap install aws-cli --classic",
  "export PATH=$PATH:/snap/bin",
  f"aws s3 cp s3://{b}/bootstrap/mailserver.tgz /tmp/mailserver.tgz --region {r}",
  "mkdir -p /opt/mail && tar -xzf /tmp/mailserver.tgz -C /tmp && cp -rn /tmp/mailserver/. /opt/mail/",
  f"sed -i 's|^DOMAIN=.*|DOMAIN={d}|; s|^BACKUP_S3_BUCKET=.*|BACKUP_S3_BUCKET={b}|' /opt/mail/.env.example",
  "chmod +x /opt/mail/scripts/*.sh && chown -R ubuntu:ubuntu /opt/mail",
  f"/opt/mail/scripts/01_server_init.sh {d}",
]
print(json.dumps({"commands": cmds}))
PY
CMD_ID="$(aws ssm send-command --instance-ids "$IID" --document-name AWS-RunShellScript \
  --comment "install mailserver files" --parameters file:///tmp/ssm-params.json \
  --timeout-seconds 1800 --query Command.CommandId --output text)" \
  || die "명령 전송 실패. 1분 뒤 스크립트를 다시 실행하세요(같은 값을 입력하면 이미 만든 자원은 그대로 재사용)."
echo -n "  설치 중 (약 5분)"
for _ in $(seq 1 80); do
  ST="$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$IID" --query Status --output text 2>/dev/null || echo Pending)"
  case "$ST" in Success) echo; c_ok "설치 완료"; break ;;
    Failed|Cancelled|TimedOut) echo; die "설치 실패($ST): aws ssm get-command-invocation --command-id $CMD_ID --instance-id $IID" ;;
  esac
  echo -n "."; sleep 15
done

echo
echo "================ 완료 ================"
echo "  서버 IP     : $IP"
echo "  접속(SSH)   : ssh -i $KEY_NAME.pem ubuntu@$IP"
echo "  접속(키 없이): EC2 콘솔 → 인스턴스 선택 → 연결 → Session Manager"
echo
echo "  알림 메일함의 'Subscription Confirmation' 링크를 눌러 장애 알림을 승인하세요."
[ "$CREATE_DNS" = false ] && echo "  DNS: mail/webmail/news A → $IP, MX 10 mail.$DOMAIN, SPF 에 include:amazonses.com 추가"
echo
echo "  남은 일 (서버 접속 후):"
echo "    sudo su - ubuntu && cd /opt/mail"
echo "    cp .env.example .env && chmod 600 .env && nano .env   # SES SMTP, 메일러 비밀번호"
echo "    ./scripts/02_start.sh"
