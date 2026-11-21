# 회사 메일 서버 직접 설치 가이드 (Docker 없음)

메일 전용 EC2(Ubuntu 24.04)에 **Ubuntu 기본 패키지로 직접 설치**합니다. 운영 환경에서 Docker를 쓰지 않는 조건에 맞춘 방식이며, 설치 파일은 `mailserver-native/`에 있습니다.

## 구성

| 역할 | 프로그램 (설치 방법) | 포트 | 설정 위치 |
|---|---|---|---|
| 메일 수신·발송 | Postfix 3.8 (apt) | 25, 465, 587 | `/etc/postfix/` |
| 메일함·IMAP | Dovecot 2.3 + Sieve (apt) | 993 | `/etc/dovecot/dovecot.conf`, 메일 `/var/vmail/` |
| 스팸 필터 | Rspamd 3.8 + Redis (apt) | 127.0.0.1:11332 | `/etc/rspamd/local.d/` |
| 웹메일 | Roundcube 1.6 + PHP 8.3 FPM (apt) | 443 (Nginx) | `/etc/roundcube/config.inc.php` |
| 고객 발송 메일러 | listmonk 6.2 (공식 바이너리) + PostgreSQL 16 (apt) | 127.0.0.1:9000 | `/opt/listmonk/` |
| HTTPS | Nginx + certbot (apt) | 80, 443 | `/etc/nginx/sites-available/mail.conf` |
| 무차별 대입 차단 | Fail2ban (apt) | — | `/etc/fail2ban/jail.d/mail.local` |
| 발송 대행 | Amazon SES (Postfix가 587로 중계) | — | `/etc/postfix/sasl_passwd` |

- 메일 계정은 리눅스 계정이 아닌 **가상 계정**입니다. 모든 메일은 `vmail` 사용자(5000번) 소유로 `/var/vmail/<도메인>/<아이디>/Maildir`에 저장됩니다.
- listmonk를 뺀 모든 프로그램은 Ubuntu 보안 업데이트(unattended-upgrades)로 자동 패치됩니다.

## 파일 구성

```
mailserver-native/
├── .env.example            # 설정값 견본
├── templates/              # Dovecot, Nginx, Rspamd, Fail2ban, listmonk 설정 견본
└── scripts/
    ├── 00_base.sh          # OS 기본 설정 (CloudShell/첫 부팅이 자동 실행)
    ├── install.sh          # 전체 설치·설정 (여러 번 실행해도 안전)
    ├── mailuser.sh         # 계정·별칭 관리
    ├── status.sh           # 상태 점검
    ├── check_dns.sh        # DNS 점검
    └── backup.sh           # 매일 백업 (선택: S3)
```

## 설치 절차

### 1단계: 서버 만들기 (CloudShell)

[AWS_AUTO_DEPLOY.md](AWS_AUTO_DEPLOY.md)의 CloudShell 원스톱 설치를 따릅니다. 스크립트가 서버를 만들고 `mailserver-native/`를 `/opt/mail`에 복사한 뒤 `00_base.sh`까지 실행합니다.

### 2단계: 설정값 입력

```bash
# EC2 → 인스턴스 → 연결 → Session Manager (또는 ssh -i mail-key.pem ubuntu@<IP>)
cd /opt/mail
sudo cp .env.example .env && sudo chmod 600 .env
sudo nano .env
```

| 항목 | 값 |
|---|---|
| `DOMAIN` | 회사 도메인 (CloudShell이 미리 채움) |
| `ACME_EMAIL` | 인증서 만료 알림 받을 외부 메일 주소 |
| `SES_SMTP_USER`, `SES_SMTP_PASS` | SES SMTP 자격 증명 |
| `LISTMONK_ADMIN_PASSWORD` | 메일러 관리자 비밀번호 (12자 이상) |
| `LISTMONK_DB_PASSWORD` | `auto` 그대로 두기 (영문·숫자로 자동 생성) |

비밀번호에 `$`, `` ` ``, `"`, `\` 같은 특수문자가 있으면 값 전체를 작은따옴표로 감쌉니다. 예: `SES_SMTP_PASS='abc$def'`

### 3단계: 설치 (약 10분)

```bash
sudo ./scripts/install.sh
```

| 단계 | 하는 일 |
|---|---|
| 1 | `mail`·`webmail`·`news` A 레코드가 이 서버를 가리키는지 확인 |
| 2 | 패키지 설치 (Apache는 설치되지 않도록 Nginx·PHP-FPM 먼저) |
| 3 | 메일 저장 계정 `vmail`, `/var/vmail` |
| 4 | Let's Encrypt 인증서 2개 발급 (`mail.`, `webmail.`+`news.`), 갱신 시 자동 반영 |
| 5 | Dovecot 설정 + 검사 (`doveconf -n`), 스팸은 Junk 폴더로 자동 이동 |
| 6 | Postfix 설정 + 검사 (`postfix check`), SES 중계, 465/587은 로그인 사용자만 자기 주소로 발송 |
| 7 | Rspamd 설정 + 검사 (`rspamadm configtest`) |
| 8 | Roundcube 설정 + 검사 (`php -l`), Nginx 설정 + 검사 (`nginx -t`) |
| 9 | PostgreSQL DB, listmonk 설치·서비스 등록 |
| 10 | Fail2ban, 전체 서비스 시작 |
| 11 | 첫 계정 `info@` 생성 (비밀번호 입력), `postmaster@`·`abuse@`·`dmarc@` → `info@` 전달 |

마지막에 `status.sh` 결과가 나옵니다. 모든 항목이 `[OK]`면 완료입니다.

### 4단계: 마무리

1. `./scripts/check_dns.sh`로 DNS 점검
2. 메일러 설정, SES 반송 알림 연결, 송수신 테스트: [MAIL_SERVER_SETUP.md](MAIL_SERVER_SETUP.md)의 4·5단계와 같습니다(listmonk 화면 설정은 동일).
3. 백업 등록

```bash
sudo crontab -e
30 3 * * * /opt/mail/scripts/backup.sh >> /opt/mail/backups/backup.log 2>&1
```

## 계정 관리

```bash
sudo ./scripts/mailuser.sh add cs@회사도메인                 # 계정 추가
sudo ./scripts/mailuser.sh passwd cs@회사도메인              # 비밀번호 변경
sudo ./scripts/mailuser.sh alias sales@회사도메인 cs@회사도메인  # sales@ 로 온 메일을 cs@ 로
sudo ./scripts/mailuser.sh list
sudo ./scripts/mailuser.sh del cs@회사도메인                 # 메일함 파일은 보존
```

별칭을 받는 계정은 그 별칭 주소로 메일을 보낼 수도 있습니다(예: `info@` 계정이 `postmaster@`로 발송). 다른 주소로는 보낼 수 없습니다.

## 직원 메일 프로그램 설정 (Outlook, 휴대폰 등)

| 항목 | 값 |
|---|---|
| 받는 메일 (IMAP) | `mail.회사도메인`, 포트 993, SSL/TLS |
| 보내는 메일 (SMTP) | `mail.회사도메인`, 포트 465 SSL/TLS (또는 587 STARTTLS) |
| 아이디 | 전체 메일 주소 (`info@회사도메인`) |

## 운영

| 작업 | 방법 |
|---|---|
| 상태 점검 | `sudo ./scripts/status.sh` |
| 보안 업데이트 | 자동 (unattended-upgrades). 월 1회 `sudo apt upgrade`로 확인 |
| listmonk 업그레이드 | 릴리스 노트 확인 → `.env`의 `LISTMONK_VERSION` 변경 → `sudo ./scripts/install.sh` |
| 설정 다시 맞추기 | `sudo ./scripts/install.sh` (계정·메일은 유지) |
| 메일 로그 | `journalctl -u postfix -u dovecot --since today` |
| 메일러 로그 | `journalctl -u listmonk -n 100` |
| 대기 중인 메일 | `sudo postqueue -p`, 즉시 재시도 `sudo postqueue -f` |
| 차단된 IP 확인·해제 | `sudo fail2ban-client status postfix-sasl`, `sudo fail2ban-client unban <IP>` |

## 문제 해결

| 증상 | 확인 순서 |
|---|---|
| install.sh 1단계 A 레코드 오류 | `dig +short A mail.도메인` → Route 53 값 → 반영 대기 |
| 인증서 발급 실패 | 보안 그룹 80 포트 → DNS 반영 → `sudo tail -50 /var/log/letsencrypt/letsencrypt.log` |
| 메일이 안 들어옴 | `check_dns.sh` → 보안 그룹 25 → `journalctl -u postfix -n 50` |
| 답장이 안 나감 | `sudo postqueue -p`에서 오류 확인 → `/etc/postfix/sasl_passwd` 값 → SES 샌드박스 여부 |
| 웹메일 로그인 실패 | 아이디는 전체 주소 → `mailuser.sh passwd` → `/var/log/roundcube/errors.log` |
| 메일러 접속 안 됨 | `systemctl status listmonk` → `journalctl -u listmonk -n 50` |
| 스팸이 받은편지함으로 옴 | Rspamd가 점수 6 이상만 Junk로 보냄 → `/etc/rspamd/local.d/actions.conf`의 `add_header` 값 조정 |
| 첫 메일이 몇 분 늦게 옴 | Rspamd 그레이리스팅(의심 메일을 잠시 보류) → 정상 동작, 다시 보내면 통과 |

## 검증 결과 (개발 환경)

Ubuntu 24.04에서 실제 패키지를 설치해 `install.sh`를 실행하고 다음을 확인했습니다. 실제 EC2·DNS·SES 환경에서의 실행은 아직입니다.

| 항목 | 결과 |
|---|---|
| `doveconf -n`, `postfix check`, `rspamadm configtest`, `nginx -t`, `php -l` | 통과 |
| 25번으로 `info@` 수신, 별칭 `postmaster@` 수신 | Maildir에 도착 |
| 없는 주소 수신 | 550으로 거부 |
| IMAP 993 로그인, 폴더 (INBOX, Drafts, Sent, Junk, Trash, Archive) | 정상, 틀린 비밀번호 거부 |
| 465 인증 발송, 587 STARTTLS 인증 | SES 중계 대기열에 들어감 |
| 남의 주소 사칭 발송, 인증 없는 발송 | 553/거부 |
| 스팸 테스트 메일 (GTUBE) | Rspamd가 554로 거부 |
| listmonk DB 설치, 관리자 생성, 화면 응답 | 정상 (HTTP 200) |

## 소개뱅크 동일 서버에 Docker 없이 설치하는 경우

소개뱅크 서버는 Amazon Linux 2023입니다. 이 방식의 스크립트는 Ubuntu 패키지 기준이라 **그대로 쓸 수 없습니다.** Amazon Linux 2023 기본 저장소에는 Rspamd와 Roundcube 패키지가 없는 것으로 알고 있어(추가 확인 필요) 소스 빌드나 수동 설치가 필요하고, 그만큼 운영 부담이 커집니다. Docker를 쓰지 않는다면 **별도 메일 서버(Ubuntu)를 권장**합니다.
