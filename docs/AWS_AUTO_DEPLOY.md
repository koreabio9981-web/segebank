# AWS 메일 서버 자동 구축 (CloudFormation)

`infra/mail-server.yaml` 템플릿 하나로 메일 서버에 필요한 AWS 자원을 한 번에 만듭니다.
[MAIL_SERVER_SETUP.md](MAIL_SERVER_SETUP.md)의 **1단계(EC2 준비)와 2단계(DNS) 대부분**을 대신합니다.

## 가장 쉬운 방법: CloudShell 원스톱 설치 (권장)

AWS 콘솔 안의 터미널(CloudShell)에서 스크립트 하나로 **서버 생성 → DNS → 역방향 DNS → 메일 서버 파일 설치**까지 끝냅니다.
내 PC에 AWS CLI를 설치할 필요가 없습니다.

1. GitHub 저장소 화면 → **Code → Download ZIP** 으로 내 PC에 저장
2. AWS 콘솔 오른쪽 위 리전을 **서울**로 → 상단 검색창 옆 **CloudShell 아이콘(>_)** 클릭
3. CloudShell 오른쪽 위 **작업 → 파일 업로드** → ZIP 선택
4. 아래 명령 실행 (폴더 이름은 `ls` 로 확인)

```bash
unzip -q segebank-*.zip && cd segebank-*/
bash infra/cloudshell_setup.sh
```

5. 질문에 답하기: 도메인, 키 페어 이름(없으면 자동 생성), 내 PC IP, 알림 이메일, 서버 크기(t3.small 권장) → `yes`
6. 키 페어를 새로 만든 경우 **작업 → 파일 다운로드** 로 `/home/cloudshell-user/mail-key.pem` 을 내 PC에 저장
7. 끝나면 화면에 나온 "남은 일"대로 서버에 접속해 `.env` 입력 → `./scripts/02_start.sh`

스크립트가 자동으로 판단하는 것:

| 항목 | 동작 |
|---|---|
| Route 53 호스팅 영역, 기본 VPC·서브넷 | 자동 조회 |
| 루트 도메인에 MX·SPF 가 이미 있음 | DNS 자동 생성 끔 (기존 메일 보호), 직접 수정 안내 |
| SES 도메인이 이미 인증됨 | 새로 만들지 않고 기존 것에 반송 알림 연결 |
| 같은 이름의 메일 서버 EC2 가 이미 있음 | 중복 경고 |
| 서버에 설치 파일 복사 | S3 → Session Manager (SSH·저장소 공개 불필요) |

아래는 같은 작업을 단계별로 직접 하는 방법입니다.

## 자동으로 만들어지는 것

| 구분 | 자원 | 설명 |
|---|---|---|
| 서버 | EC2 (Ubuntu 24.04, t3.medium, gp3 30GB 암호화) | 종료 방지, IMDSv2, 첫 부팅 시 Docker 등 초기 설정 자동 실행 |
| 네트워크 | 보안 그룹, Elastic IP | 22번은 지정한 IP만, 메일·웹 포트 개방 |
| 권한 | IAM 역할 | S3 백업 업로드, Session Manager(키 없이 콘솔 접속) |
| 백업 | S3 버킷(30일 보관), AWS Backup(매일 03:00, 7일) | 스택을 지워도 S3 버킷은 남음 |
| 감시 | CloudWatch 경보 3개, 월 예산 알림 | 하드웨어 장애 시 자동 복구, OS 멈춤 시 자동 재부팅, CPU 과부하·비용 초과 메일 |
| 메일러 | SES 구성 세트 + SNS 주제 | 반송·스팸신고 → listmonk 자동 차단 |
| DNS (선택) | A(mail·webmail·news), MX, SPF, DMARC | `CreateDnsRecords=true` |
| SES (선택) | 도메인 2개 인증, DKIM, MAIL FROM 레코드 | `CreateSesIdentities=true` |

CloudFormation으로 못 하는 작업은 `infra/post_deploy.sh`가 처리합니다: 역방향 DNS 설정, 기존 SES 자격 증명에 구성 세트 연결, listmonk 웹훅 구독.

## 전제 조건

1. 내 PC에 AWS CLI v2 설치 + `aws configure` 완료 (관리자 권한 IAM 사용자, 리전 `ap-northeast-2`)
2. 도메인이 Route 53 호스팅 영역에 있음
3. EC2 키 페어를 미리 생성 (EC2 → 키 페어 → 생성 → `.pem` 보관)
4. **이미 콘솔에서 EC2·Elastic IP를 수동으로 만들었다면** 중복 비용이 나오지 않도록 정리하거나, 이 템플릿 대신 기존 방식을 계속 쓰세요.

## 파라미터 값 찾기

| 파라미터 | 찾는 곳 |
|---|---|
| `HostedZoneId` | Route 53 → 호스팅 영역 → 도메인 → "호스팅 영역 ID" (Z로 시작) |
| `VpcId`, `SubnetId` | VPC 콘솔 → "기본 VPC: 예" 인 VPC, 그 VPC의 서브넷 아무거나 (기본 VPC 서브넷은 퍼블릭) |
| `KeyPairName` | EC2 → 키 페어 → 이름 |
| `SshAllowedCidr` | `curl -s https://checkip.amazonaws.com` 결과 뒤에 `/32` |
| `CreateDnsRecords` | Route 53에 루트 도메인 MX 또는 `v=spf1` TXT가 **이미 있으면 false** (충돌 시 생성 실패) |
| `CreateSesIdentities` | SES 콘솔에서 이미 도메인 인증을 했으면 **false** |

CLI로 찾기:

```bash
aws route53 list-hosted-zones --query 'HostedZones[].[Name,Id]' --output table
aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[].VpcId' --output text
aws ec2 describe-subnets --filters Name=default-for-az,Values=true --query 'Subnets[].[SubnetId,AvailabilityZone]' --output table
```

## 실행 절차

```bash
# 1) 파라미터 입력
cp infra/params.env.example infra/params.env
nano infra/params.env

# 2) 배포 (5~10분)
./infra/deploy.sh
#  → 알림 메일함의 "Subscription Confirmation" 링크 클릭 (장애 알림 수신 승인)

# 3) 역방향 DNS (A 레코드 반영 후)
./infra/post_deploy.sh ptr

# 4) SES 를 콘솔에서 직접 만든 경우만: 구성 세트 연결
./infra/post_deploy.sh ses

# 5) 서버에 파일 복사 (비공개 저장소인 경우) — 출력된 IP 사용
scp -i mail-key.pem -r mailserver ubuntu@<PublicIp>:/tmp/
ssh -i mail-key.pem ubuntu@<PublicIp>
sudo cp -r /tmp/mailserver/. /opt/mail/ && sudo chown -R ubuntu:ubuntu /opt/mail
sudo /opt/mail/scripts/01_server_init.sh <회사도메인>   # 부팅 시 이미 실행됐다면 생략 가능
exit   # 재접속

# 6) 서버에서 메일 서비스 실행 (MAIL_SERVER_SETUP.md 3단계)
cd /opt/mail && cp .env.example .env && chmod 600 .env && nano .env
#   BACKUP_S3_BUCKET 은 /opt/mail/BACKUP_BUCKET.txt 값 입력
./scripts/02_start.sh

# 7) listmonk 에서 Bounces → Enable SES 켠 뒤 (내 PC)
./infra/post_deploy.sh sns

# 8) 전체 상태 확인
./infra/post_deploy.sh status
```

첫 부팅 설정 기록은 서버의 `/var/log/mail-bootstrap.log`에서 확인합니다.

## 예상 비용

[MAIL_SERVER_SETUP.md](MAIL_SERVER_SETUP.md)의 약 $50/월에 다음이 추가됩니다(추정, 요금 계산기로 확인 필요).

| 항목 | 추가 비용 |
|---|---|
| AWS Backup 스냅샷 7개 (변경분 저장) | 약 $1~3 |
| S3 백업 30일 | 약 $0.5 |
| CloudWatch 경보 3개 | 약 $0.3 |
| SNS·Budgets | 거의 무료 |

## 문제 해결

| 증상 | 원인·해결 |
|---|---|
| `deploy.sh` 에서 `Unable to locate credentials` | `aws configure` 실행 |
| 스택이 `ROLLBACK_COMPLETE` | 콘솔 → CloudFormation → 이벤트 탭의 첫 실패 원인 확인 → `aws cloudformation delete-stack --stack-name company-mail` 후 재배포 |
| `Tried to create resource record set ... but it already exists` | 해당 레코드가 이미 있음 → `CreateDnsRecords=false` 로 하고 수동 등록 |
| `... already exists` (SES) | SES 자격 증명이 이미 있음 → `CreateSesIdentities=false` + `post_deploy.sh ses` |
| SSH 접속 안 됨 | 내 IP 변경 → `params.env` 의 `SshAllowedCidr` 수정 후 `deploy.sh` 재실행 (서버는 유지됨) |
| `post_deploy.sh ptr` 실패 | A 레코드 반영 대기 후 재실행 |
| SNS 구독이 `PendingConfirmation` | listmonk Bounces 설정에서 SES 켜기 → 구독 삭제 후 `post_deploy.sh sns` 재실행 |

## 삭제할 때 주의

1. 종료 방지가 켜져 있으므로 먼저 해제합니다: `aws ec2 modify-instance-attribute --instance-id <ID> --no-disable-api-termination`
2. `aws cloudformation delete-stack --stack-name company-mail`
3. **남는 자원**(데이터 보호용): 디스크(EBS 볼륨), S3 백업 버킷, Backup 보관함의 복구 지점 → 필요 없으면 직접 삭제

## 체크리스트

- [ ] `params.env` 값 입력, `SshAllowedCidr` 가 `/32`
- [ ] 스택 `CREATE_COMPLETE`
- [ ] 장애 알림 구독 승인 메일 클릭
- [ ] `post_deploy.sh status` 에서 PTR = `mail.<도메인>.`
- [ ] SES 두 도메인 DKIM `SUCCESS`, 구성 세트 연결
- [ ] 서버에서 `02_start.sh` 완료
- [ ] SNS 구독이 Confirmed (listmonk 웹훅)
- [ ] AWS Backup 콘솔에 다음 날 복구 지점 생성 확인
