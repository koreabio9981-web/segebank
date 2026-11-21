# 소개뱅크 운영 서버에 메일 서버 함께 설치하기 (공용 서버 모드)

메일 전용 EC2를 따로 만들지 않고, 운영 중인 소개뱅크 서버(Amazon Linux 2023, Node 앱 3000번 포트, PM2)에 메일 서버를 함께 설치하는 절차입니다.

> **권장안은 별도 EC2입니다.** 공용 모드는 월 약 $40을 아끼는 대신, 메일 서버에 공격이나 과부하가 생기면 소개뱅크까지 영향을 받을 수 있습니다. 아래의 보호 장치로 위험을 줄였지만 없애지는 못합니다.

## 구조

```
                         ┌──────────── 소개뱅크 EC2 (Amazon Linux 2023) ────────────┐
고객 ── https://www.도메인 ──▶ Nginx(80/443) ──▶ Node 앱 :3000 (PM2)    ← 기존 그대로
직원 ── https://webmail.도메인 ─▶ Nginx ──▶ 127.0.0.1:8081 Roundcube   ┐
관리자 ─ https://news.도메인 ───▶ Nginx ──▶ 127.0.0.1:8082 listmonk    │ Docker
문의자 ── 메일(25) ─────────────────────▶ docker-mailserver           │ (메모리 상한
직원 PC ─ IMAP 993 / SMTP 465·587 ──────▶ docker-mailserver           ┘  합계 약 2.4GB)
                         └──────────────────────────────┬───────────────────────────┘
                              보내는 메일 → Amazon SES(587) → 고객
```

## 별도 EC2 방식과 무엇이 다른가

| 항목 | 별도 EC2 (`docker-compose.yml`) | 공용 모드 (`docker-compose.shared.yml`) |
|---|---|---|
| 운영체제 | Ubuntu 24.04 | Amazon Linux 2023 (기존 서버) |
| HTTPS 인증서 | Caddy가 자동 발급 | 서버의 Nginx + certbot |
| 웹메일·메일러 포트 | 컨테이너 내부 연결만 | `127.0.0.1:8081`, `8082` (외부 차단) |
| 소개뱅크 보호 | 해당 없음 | 메모리·CPU 상한, 메모리 부족 시 메일 컨테이너 먼저 정리 |
| 시작 스크립트 | `02_start.sh` | `shared_start.sh` |
| SES 반송 알림 설정 | CloudFormation 템플릿 | `infra/ses_feedback_setup.sh` |
| 서버 이름(hostname) | `mail.도메인`으로 변경 | **변경 안 함** |

## 필요한 조건

| 항목 | 기준 | 확인 방법 |
|---|---|---|
| 운영체제 | Amazon Linux 2023 | `shared_precheck.sh` |
| 여유 메모리 | 2.5GB 이상 (1.5~2.5GB는 스왑 필수, 1.5GB 미만은 사양 상향 필요) | `free -h` |
| 여유 디스크 | 15GB 이상 | `df -h /` |
| 포트 25, 465, 587, 993 | 사용하는 프로그램이 없어야 함 | `shared_precheck.sh` |
| 포트 80, 443 | 비어 있거나 Nginx가 사용 중 | `shared_precheck.sh` |
| 고정 IP | Elastic IP 연결 | EC2 콘솔 |

## 단계별 절차

### 0단계: 백업 (필수)

EC2 콘솔 → 소개뱅크 인스턴스 → **작업 → 이미지 및 템플릿 → 이미지 생성**(AMI)
문제가 생기면 이 이미지로 즉시 되돌릴 수 있습니다. "재부팅 안 함"을 체크하면 서비스가 중단되지 않습니다.

### 1단계: 파일 복사와 사전 점검

```bash
# 내 PC → 서버 (소개뱅크 배포 폴더와 섞이지 않게 /opt/mail 사용)
scp -i <소개뱅크키>.pem -r mailserver ec2-user@<서버IP>:/tmp/
ssh -i <소개뱅크키>.pem ec2-user@<서버IP>

sudo mkdir -p /opt/mail && sudo cp -r /tmp/mailserver/. /opt/mail/ && sudo chown -R ec2-user:ec2-user /opt/mail
cd /opt/mail
./scripts/shared_precheck.sh        # 아무것도 바꾸지 않는 점검
```

`[불가]` 항목이 하나라도 있으면 해결하기 전에는 진행하지 마세요.

> CodeDeploy는 `/home/ec2-user/segebank`를 덮어씁니다. 메일 파일과 `.env`는 반드시 `/opt/mail`에 두세요.

### 2단계: 보안 그룹 포트 추가

EC2 → 소개뱅크 인스턴스 → 보안 그룹 → 인바운드 규칙 편집 → 아래 항목 추가

| 포트 | 소스 | 용도 |
|---|---|---|
| 25 | 0.0.0.0/0 | 메일 수신 |
| 465, 587 | 0.0.0.0/0 | 직원 메일 프로그램 발송 |
| 993 | 0.0.0.0/0 | 직원 메일 프로그램 수신 |
| 80, 443 | 0.0.0.0/0 | 이미 있으면 생략 |

### 3단계: DNS 레코드

| 종류 | 이름 | 값 |
|---|---|---|
| A | `mail`, `webmail`, `news` | 소개뱅크 서버 Elastic IP |
| MX | (루트) | `10 mail.도메인` |
| TXT | (루트) | `"v=spf1 include:amazonses.com -all"` (기존 SPF가 있으면 `include:amazonses.com`만 추가) |
| TXT | `_dmarc`, `_dmarc.news` | `"v=DMARC1; p=none; rua=mailto:dmarc@도메인"` |

SES DKIM과 MAIL FROM 레코드는 SES 콘솔에 표시된 값으로 등록합니다(이미 했으면 생략).

### 4단계: 서버 준비 (Docker, Nginx, certbot)

```bash
sudo ./scripts/shared_init_al2023.sh
exit      # 다시 접속해야 docker 권한이 적용됨
```

소개뱅크 앱, PM2, 서버 이름은 건드리지 않습니다. Nginx가 이미 있으면 그대로 쓰고, 설정 파일만 따로 추가합니다.

### 5단계: 설정값 입력과 실행

```bash
ssh -i <소개뱅크키>.pem ec2-user@<서버IP>
cd /opt/mail
cp .env.example .env && chmod 600 .env
nano .env       # DOMAIN, ACME_EMAIL, SES_SMTP_USER/PASS, LISTMONK_* 입력
./scripts/shared_start.sh
```

`shared_start.sh`가 하는 일:

1. DNS가 이 서버를 가리키는지 확인
2. Nginx 설정을 `/etc/nginx/conf.d/mail-<도메인>.conf`라는 별도 파일로 추가
3. 인증서 발급
4. **Nginx 설정 검사(`nginx -t`)를 통과할 때만 반영.** 실패하면 반영하지 않아 소개뱅크에 영향이 없음
5. 메일 컨테이너 실행, `info@` 계정 생성

### 6단계: 소개뱅크 정상 동작 확인

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/    # 200 이면 정상
pm2 status
free -h
docker stats --no-stream
```

### 7단계: SES 반송 알림과 역방향 DNS (내 PC)

```bash
./infra/ses_feedback_setup.sh setup  도메인     # 구성 세트 + SNS 주제, news.도메인 에 연결
./infra/ses_feedback_setup.sh ptr    도메인     # 역방향 DNS → mail.도메인
# listmonk 에서 Settings → SMTP(SES), Bounces → Enable SES 설정 후
./infra/ses_feedback_setup.sh sns    도메인
./infra/ses_feedback_setup.sh status 도메인
```

listmonk 설정과 송수신 테스트는 [MAIL_SERVER_SETUP.md](MAIL_SERVER_SETUP.md)의 4·5단계와 같습니다.

### 8단계: 백업과 운영

```bash
sudo crontab -e
30 3 * * * /opt/mail/scripts/backup.sh >> /opt/mail/backups/backup.log 2>&1
```

인증서 갱신은 certbot이 자동으로 처리하고, 갱신 후 Nginx와 메일 서버에 반영합니다(`shared_init_al2023.sh`가 설정).

## 소개뱅크 보호 장치

| 장치 | 내용 |
|---|---|
| 메모리 상한 | 메일 서버 1.5GB, 메일러 DB 384MB, 웹메일 256MB, 메일러 256MB |
| CPU 상한 | 메일 서버 1코어, 나머지 각 0.5코어 |
| 메모리 부족 시 정리 순서 | 메일 컨테이너를 먼저 정리 (`oom_score_adj: 500`) |
| 내부 포트 | 웹메일·메일러는 `127.0.0.1`에만 열어 외부 직접 접근 차단 |
| Nginx 설정 분리 | 메일용 설정은 별도 파일. 검사 실패 시 반영 안 함 |
| 백신(ClamAV) | 메모리를 많이 써서 꺼 둠 |

## 원래대로 되돌리기

```bash
cd /opt/mail && docker compose down
sudo rm /etc/nginx/conf.d/mail-<도메인>.conf && sudo nginx -t && sudo systemctl reload nginx
```

이후 보안 그룹에서 25, 465, 587, 993 포트를 닫습니다. 문제가 심하면 0단계에서 만든 AMI 이미지로 복구합니다.

## 비용

| 항목 | 월 비용 (추정) |
|---|---|
| 서버 | $0 (사양을 올려야 하면 +$19~38) |
| 디스크 추가 10~20GB | $1~2 |
| 백업 | $1 |
| SES 5만 통 | $5 |
| **합계** | **약 $7~45** |

## 문제 해결

| 증상 | 확인 순서 |
|---|---|
| `shared_precheck.sh`에서 메모리 부족 | 인스턴스를 중지한 뒤 유형을 한 단계 올리고 시작 (데이터 유지, 몇 분간 중단) |
| 80/443을 Nginx가 아닌 프로그램이 사용 | Node가 80을 직접 쓰는 경우 Nginx → 3000 구조로 바꾸거나 별도 EC2 사용 |
| 인증서 발급 실패 | 보안 그룹 80 포트 → DNS 반영 여부 → `sudo tail /var/log/letsencrypt/letsencrypt.log` |
| `nginx -t` 실패 | 출력에 표시된 파일과 줄 확인. 기존 사이트 설정과 `server_name`이 겹치는지 확인 |
| 소개뱅크가 느려짐 | `docker stats`로 메일 컨테이너 사용량 확인 → `docker compose stop listmonk roundcube`로 임시 조치 |
| 메일 서버가 자꾸 재시작 | `docker logs mailserver`에서 메모리 부족 여부 확인 → 메모리 상한 상향 또는 사양 상향 |

## 체크리스트

- [ ] 0단계 AMI 이미지 생성
- [ ] `shared_precheck.sh`에 불가 항목 없음
- [ ] 보안 그룹 25, 465, 587, 993 추가
- [ ] DNS A(mail·webmail·news), MX, SPF, DMARC
- [ ] `shared_start.sh` 완료
- [ ] 소개뱅크 `http://127.0.0.1:3000/` 응답 200
- [ ] 웹메일 로그인, 수신·답장 테스트
- [ ] `ses_feedback_setup.sh status`에서 PTR, DKIM, SNS 확인
- [ ] 백업 cron 등록
- [ ] 1주일 동안 `free -h`와 `docker stats`로 메모리 확인
