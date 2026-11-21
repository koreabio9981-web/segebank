# 회사 메일 서버 구축 가이드 (AWS EC2 + Amazon SES)

문의 메일을 받고(`info@회사도메인`) 고객에게 메일을 보내는(메일러) 자체 메일 서버를 만드는 절차입니다.
설정 파일은 이 저장소의 `mailserver/` 폴더에 있습니다.

## 전체 구조

```
[고객·문의자] ──메일──▶ MX: mail.<도메인>  (EC2: docker-mailserver) ──▶ 메일함
                                                    │
직원 (웹메일 / Outlook) ──답장──▶ mailserver ──중계(587)──▶ Amazon SES ──▶ 고객
                                                                  ▲
listmonk 메일러 (news.<도메인>) ──대량 발송(587)─────────────────────┘
          ▲
SES 반송·스팸신고 ──▶ SNS ──▶ listmonk 웹훅 (해당 주소 자동 차단)
```

| 주소 | 용도 |
|---|---|
| `mail.<도메인>` | 메일 수신(MX), 직원 메일 프로그램(IMAP 993, SMTP 465/587) |
| `https://webmail.<도메인>` | 웹메일 (Roundcube) |
| `https://news.<도메인>/admin` | 고객 발송 메일러 (listmonk) |
| `news.<도메인>` | 마케팅 발송 전용 도메인 (평판 분리) |

> EC2 에서 25번 포트로 직접 보내지 않으므로 **AWS "25번 포트 발송 제한 해제" 신청은 필요 없습니다.**

## 파일 구성

```
mailserver/
├── .env.example          # 설정값 견본 → .env 로 복사해서 사용
├── docker-compose.yml    # 메일서버·웹메일·메일러·DB·HTTPS
├── Caddyfile             # HTTPS 인증서 자동 발급 + 웹 연결
└── scripts/
    ├── 01_server_init.sh # EC2 초기 설정 (1회)
    ├── 02_start.sh       # 점검 → 인증서 → 실행 → 첫 계정
    ├── add_account.sh    # 계정·별칭 추가/삭제/비밀번호 변경
    ├── check_dns.sh      # DNS 설정 점검
    └── backup.sh         # 매일 백업 (선택: S3)
```

---

## 0단계: SES 신청 먼저 (승인 1~3일)

1. **SES 콘솔(서울 리전) → 자격 증명 → 자격 증명 생성 → 도메인**
   - `회사도메인` 과 `news.회사도메인` 두 개를 만듭니다.
   - "Easy DKIM" 선택 → 표시되는 **CNAME 3개**를 Route 53 에 등록 (Route 53 사용 시 자동 등록 버튼)
   - "사용자 지정 MAIL FROM 도메인": `bounce.회사도메인`, `bounce.news.회사도메인` → 표시되는 MX·TXT 등록
2. **SES → SMTP 설정 → SMTP 자격 증명 생성** → 사용자 이름·비밀번호를 `.env` 에 입력할 값으로 보관
3. **SES → 계정 대시보드 → 프로덕션 액세스 요청** (샌드박스 해제). 예시 문구:

   ```
   용도: 회사 문의 답장과, 수신 동의한 고객에게 보내는 소식지·안내 메일.
   수신자 확보: 회원가입/구독 페이지에서 명시적 동의(이중 확인) 후 등록, 구매 목록 사용 안 함.
   반송·신고 처리: SES 알림 → SNS → listmonk 로 자동 수신, 반송·신고 주소는 즉시 발송 제외.
   수신 거부: 모든 메일 하단 수신거부 링크 + List-Unsubscribe(원클릭) 헤더.
   예상 발송량: 하루 최대 약 2,000통, 월 약 5만 통.
   ```

## 1단계: EC2 준비

| 항목 | 값 |
|---|---|
| 리전 | 서울 ap-northeast-2 |
| AMI | Ubuntu Server 24.04 LTS |
| 유형 | t3.medium (메모리 4GB) |
| 디스크 | gp3 30GB 이상 |
| 보안 그룹 | 22(내 IP만), 25, 80, 443, 465, 587, 993 |
| 고정 IP | Elastic IP 연결 |
| 역방향 DNS | 탄력적 IP → 작업 → 역방향 DNS 업데이트 → `mail.회사도메인` (A 레코드 먼저 등록) |

## 2단계: DNS 레코드 (Route 53)

`example.com` 을 회사 도메인으로 바꿔 등록합니다.

| 종류 | 이름 | 값 | 용도 |
|---|---|---|---|
| A | `mail` | Elastic IP | 메일 서버 |
| A | `webmail` | Elastic IP | 웹메일 |
| A | `news` | Elastic IP | 메일러 |
| MX | (비움) | `10 mail.example.com` | 메일 수신 |
| TXT | (비움) | `"v=spf1 include:amazonses.com -all"` | 발송 허용 서버 |
| TXT | `_dmarc` | `"v=DMARC1; p=none; rua=mailto:dmarc@example.com"` | 위조 방지 정책 (2~4주 후 `p=quarantine`) |
| TXT | `_dmarc.news` | `"v=DMARC1; p=none; rua=mailto:dmarc@example.com"` | 메일러 도메인 정책 |
| CNAME ×3 | SES 표시값 | SES 표시값 | `example.com` DKIM |
| CNAME ×3 | SES 표시값 | SES 표시값 | `news.example.com` DKIM |
| MX, TXT | `bounce`, `bounce.news` | SES 표시값 | 사용자 지정 MAIL FROM |

> 기존에 다른 메일(예: 호스팅 메일)을 쓰고 있었다면 MX 를 바꾸는 순간 메일이 새 서버로 옵니다. 바꾸기 전에 기존 메일을 백업하세요.

## 3단계: 서버 설치

```bash
# 내 PC → 서버 접속
ssh -i mail-key.pem ubuntu@<Elastic_IP>

# 파일 가져오기 (저장소에서 mailserver 폴더만 /opt/mail 로)
# 비공개 저장소라면 대신 내 PC 에서:  scp -i mail-key.pem -r mailserver ubuntu@<Elastic_IP>:/tmp/  후 /tmp/mailserver 를 복사
sudo git clone https://github.com/koreabio9981-web/segebank.git /tmp/segebank
sudo cp -r /tmp/segebank/mailserver /opt/mail
sudo chown -R ubuntu:ubuntu /opt/mail
cd /opt/mail

# 초기 설정 (도메인 입력) → 끝나면 로그아웃 후 재접속
sudo ./scripts/01_server_init.sh example.com
exit
```

```bash
ssh -i mail-key.pem ubuntu@<Elastic_IP>
cd /opt/mail
cp .env.example .env && chmod 600 .env
nano .env          # DOMAIN, ACME_EMAIL, SES_SMTP_USER/PASS, LISTMONK_* 입력
                   # 비밀번호에 특수문자($ ` " 등)가 있으면 '작은따옴표'로 감싸기

./scripts/02_start.sh        # 점검 → 인증서 → 실행 → info@ 계정 생성
./scripts/check_dns.sh       # DNS 점검
```

계정 추가 예:

```bash
./scripts/add_account.sh add cs@example.com
./scripts/add_account.sh alias sales@example.com cs@example.com   # sales@ 로 온 메일을 cs@ 로
./scripts/add_account.sh list
```

## 4단계: 메일러(listmonk) 설정

`https://news.회사도메인/admin` 접속 (아이디·비밀번호는 `.env` 의 `LISTMONK_ADMIN_*`).

1. **Settings → General**
   - Root URL: `https://news.회사도메인`
   - Default 'from' email: `회사명 <news@news.회사도메인>`
2. **Settings → SMTP** (기본 항목 수정)
   - Host `email-smtp.ap-northeast-2.amazonaws.com`, Port `587`, TLS `STARTTLS`
   - Auth `LOGIN`, Username/Password: SES SMTP 자격 증명
   - "Test connection" 으로 확인
3. **Settings → Privacy**: "Individual subscriber tracking" 은 필요할 때만, "Unsubscribe header" 켜기
4. **Settings → Bounces**: "Enable bounce webhooks" + "Enable SES" 켜기, 동작은 Hard bounce → 차단(blocklist)
5. **SES → 구성 세트 생성(`listmonk`) → 이벤트 대상 → SNS 주제** (반송·불만 선택)
   → SNS 주제 → 구독 생성 → HTTPS → `https://news.회사도메인/webhooks/service/ses` (listmonk 가 자동 확인)
6. **템플릿**: 하단에 회사명·주소·연락처와 `{{ UnsubscribeURL }}` 수신거부 링크 포함
7. **캠페인 제목**: 광고 메일은 맨 앞에 `(광고)` 표기

## 5단계: 테스트

| 테스트 | 방법 | 기대 결과 |
|---|---|---|
| 수신 | Gmail·네이버에서 `info@` 로 발송 | 웹메일 받은편지함 도착 |
| 답장 | 웹메일에서 Gmail 로 답장 → Gmail "원본 보기" | SPF·DKIM·DMARC 모두 PASS |
| 점수 | mail-tester.com 주소로 발송 | 9/10 이상 |
| 메일러 | 테스트 목록에 내 주소만 넣고 캠페인 발송 | 받은편지함 도착, 수신거부 링크 동작 |
| 반송 처리 | 구독자 `bounce@simulator.amazonses.com` 로 발송 | listmonk Bounces 에 기록, 자동 차단 |

## 6단계: 운영 설정

```bash
# 매일 03:30 백업 + 매주 일요일 04:00 메일서버 재시작(갱신된 인증서 반영)
sudo crontab -e
30 3 * * * /opt/mail/scripts/backup.sh >> /opt/mail/backups/backup.log 2>&1
0 4 * * 0  cd /opt/mail && docker compose restart mailserver >/dev/null 2>&1
```

- S3 백업을 쓰려면 `.env` 에 `BACKUP_S3_BUCKET` 입력 + EC2 에 해당 버킷 쓰기 권한이 있는 IAM 역할 연결
- AWS Backup 으로 EBS 일일 스냅샷도 함께 설정 (이중 백업)
- 업데이트: `.env` 의 `*_VERSION` 변경 → 릴리스 노트 확인 → `docker compose pull && docker compose up -d`

---

## 예상 비용 (서울, 월, 추정 — AWS 요금 계산기로 확인 필요)

| 항목 | 비용 |
|---|---|
| EC2 t3.medium | 약 $38 (1년 약정 시 약 $25) |
| EBS 30GB + 스냅샷 | 약 $4 |
| Elastic IP | 약 $3.6 |
| SES 5만 통 | 약 $5 |
| Route 53 | 약 $1 |
| **합계** | **약 $50** |

## 지켜야 할 규정 (변경 가능, 최신 확인 필요)

| 구분 | 요건 |
|---|---|
| 정보통신망법 제50조 | 사전 수신 동의, 제목 앞 `(광고)`, 발신자 명칭·연락처, 수신거부 방법, 야간(21~08시) 별도 동의, 2년마다 수신동의 확인 안내 |
| Gmail·Yahoo 대량 발송 기준 | SPF·DKIM·DMARC, 원클릭 수신거부, 스팸 신고율 0.3% 미만 |
| SES | 반송률 5% 미만, 신고율 0.1% 미만 유지 |

## 문제 해결

| 증상 | 확인 순서 |
|---|---|
| `02_start.sh` 가 A 레코드 오류 | `dig +short A mail.도메인` → Route 53 값, 반영 대기(최대 수 분) |
| 인증서 발급 실패 | 보안 그룹 80/443 개방 → `docker compose logs caddy` |
| 메일이 안 들어옴 | `./scripts/check_dns.sh` → 보안 그룹 25 → `docker compose logs mailserver` |
| 답장이 안 나감 | `docker exec mailserver postqueue -p` (대기열) → `.env` SES 값 → SES 샌드박스 여부 |
| 스팸함으로 감 | SES 자격 증명 DKIM "성공" 확인 → SPF 에 `include:amazonses.com` → 발송량 천천히 늘리기 |
| 웹메일 로그인 실패 | 아이디는 전체 주소(`info@도메인`) → `./scripts/add_account.sh passwd info@도메인` |
| 메모리 부족 | `free -h` → ClamAV 꺼짐 확인 → 서버 사양 상향 |

## 현장 체크리스트

- [ ] SES 도메인 2개 DKIM 성공, MAIL FROM 성공
- [ ] SES 프로덕션 액세스 승인
- [ ] Elastic IP + 역방향 DNS `mail.도메인`
- [ ] `./scripts/check_dns.sh` 모두 통과
- [ ] 수신·답장·메일러 테스트 통과, mail-tester 9점 이상
- [ ] SES 반송 시뮬레이터 테스트 → listmonk 자동 차단 확인
- [ ] `.env` 권한 600, 보안 그룹 22번 내 IP만
- [ ] 백업 cron + AWS Backup 설정, 복구 테스트 1회
- [ ] 광고 템플릿에 `(광고)`·수신거부·회사 정보 포함
