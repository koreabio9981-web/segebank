# 소개뱅크 개발 설계서 (Technical Spec v1.0)

> 기준 문서(최신이 우선):
> - 수당: [기준서 v0.3](../BONUS_RULES_V0.3.md) + [v0.4 변경안(일간 정산)](../BONUS_RULES_V0.4.md) · [일간 정산 설계](../DAILY_SETTLEMENT_DESIGN.md)
> - 판매 방식: [판매 방식](../SALES_MODEL_DESIGN.md)
> - 유료회원: [유료회원 v1.1](../PAID_MEMBERSHIP_DESIGN.md)
> - 분양: [분양](../MALL_FRANCHISE_DESIGN.md)
> - 다단계 의무: [다단계 의무](../MLM_COMPLIANCE.md)
> - 외부 연동: [외부 연동](../INTEGRATIONS.md)
> - 약관: [약관](../terms/README.md)
>
> 이 문서와 [`schema.sql`](schema.sql)이 개발의 **단일 기준**입니다. 이전 설계 문서의 표 정의와 다르면 이 문서를 따릅니다.

---

## 1. 결론

| 항목 | 결정 |
|---|---|
| 구조 | **모듈형 단일 앱**(Next.js 하나 + PostgreSQL 하나). 처음부터 서비스를 쪼개지 않음 |
| 언어 | TypeScript 전체(화면·API·작업·수당 엔진) |
| 핵심 원칙 | ① 돈은 **원장(ledger)**으로만 움직임 ② 수당 계산은 **순수 함수 + 규칙 데이터** ③ 모든 표에 **tenant_id** ④ 주문 당시 값은 **스냅샷**으로 고정 |
| 배포 | 기존 CodePipeline → EC2(PM2). 저장소 `buildspec.yml`·`appspec.yml` 재사용 |
| 수당 검증 | 엑셀·웹 시뮬레이터와 같은 입력 → **같은 결과**(자동 테스트) |

---

## 2. 전체 구조

```text
[휴대폰·PC 브라우저]  sogaebank.com · *.sogaebank.com(개인몰) · 판매자센터 · 관리자
        │ HTTPS (ALB, 와일드카드 인증서)
        ▼
[Next.js 앱 (EC2 × 2, PM2)]
  ├─ 화면: app/(mall) app/(office) app/(seller) app/(admin) app/(shop)  ← 주소(host)로 사이트 결정
  ├─ API: app/api/**  (Route Handlers)
  ├─ 도메인 모듈: src/modules/*   (업무 규칙)
  ├─ 작업 실행기: worker (pg-boss)  ← 같은 코드, 별도 PM2 프로세스
        │
        ├─ PostgreSQL 16 (RDS, Multi-AZ 2단계)  ← RLS로 tenant 분리
        ├─ S3 (공개: 상품 이미지 / 비공개: 사업자 서류) + CloudFront
        └─ 외부: PG · 본인확인 · 펌뱅킹 · 공제조합 · 알림톡/문자 · SES · 택배 · 세금계산서
```

### 2-1. 저장소 구조

```text
segebank/
├─ app/                       # Next.js (App Router)
│  ├─ (mall)/  (office)/  (seller)/  (admin)/  (shop)/   # 영역별 화면
│  └─ api/                    # REST API
├─ src/
│  ├─ modules/                # 업무 모듈 (아래 3장)
│  │   └─ <module>/  service.ts  repo.ts  schema.ts(zod)  policy.ts  *.test.ts
│  ├─ bonus-engine/           # 수당 순수 함수 (DB 모름)
│  ├─ lib/  db.ts tenant.ts auth.ts ledger.ts money.ts audit.ts
│  └─ integrations/           # pg/ identity/ banking/ mutual-aid/ messaging/ ...
├─ worker/                    # pg-boss 작업 정의
├─ db/migrations/             # 번호 순 SQL 마이그레이션 (docs/dev/schema.sql 기반)
├─ tests/e2e/                 # Playwright (시안 흐름 재사용)
├─ simulation/                # 엑셀·웹·Access 시뮬레이터 (수당 검증 기준)
├─ mockup/  docs/  infra/  scripts/  mailserver/   # 기존
```

---

## 3. 모듈과 책임

| 모듈 | 책임 | 주요 표 | 단계 |
|---|---|---|---|
| tenant | 주소 → 사이트·분양몰 결정, 설정 | tenants, storefronts, domains, settings | P0 |
| auth | 로그인, 세션, 역할, 2단계 인증(관리자) | users, sessions | P0 |
| consent | 약관 버전, 동의 이력 | terms_versions, consents | P0 |
| audit | 관리자 작업 기록 | audit_logs | P0 |
| catalog | 카테고리, 상품, 옵션, 이미지, 판매 방식 | categories, products, product_* | P1 |
| order | 장바구니, 주문, 주문상품 상태 | carts, orders, order_items | P1 |
| payment | PG 결제·취소·부분취소 | payments, refunds | P1 |
| member | 회원, 판매원 등록, **추천인(referrer)·후원인(placement)** 지정, 직급·자격 이력 | members, rank_history | P1 |
| seller | 입점 신청·심사, 판매자 정보 | sellers, seller_documents | P2 |
| bulk | 상품 일괄 등록 | bulk_jobs, bulk_job_rows | P2 |
| fulfillment | 발주, 송장, 배송 조회, 반품 | shipments, returns | P2 |
| settlement | 판매자 정산 | settlements, settlement_items | P2 |
| bonus | 수당 정산 실행(엔진 호출), 비례 삭감, 회수 | bonus_plans, bonus_runs, bonus_items, binary_volume | P3 |
| wallet | 수당 포인트 원장(**출금 가능 / 정산 대기**), 실시간 예상 수당, **회원 출금 신청**, 영업일 이체 배치, 주민번호 보관 | earnings_ledger, bonus_estimates, withdrawals, payout_batches, payout_items, distributor_tax_ids | P3 |
| mutual-aid | 공제번호 발급·해지 | mutual_aid_records | P3 |
| compliance | 35% 감시, 규정 변경 통지, 정보 공개 | (뷰), notifications | P3 |
| points | 유료회원, 포인트 묶음·거래, 환불 | membership_plans, memberships, point_lots, point_tx | P4 |
| storefront | 개인몰 개설·꾸미기·진열 | storefronts, storefront_products | P4 |
| notify | 문자·알림톡·메일 발송과 기록 | notifications | P1 |
| cms | 공지, 문의 | notices, inquiries | P1 |

**규칙**:
- 모듈끼리는 서로의 `service`만 호출하고, 다른 모듈의 표를 직접 수정하지 않습니다.
- 돈이 바뀌는 작업은 `lib/ledger.ts`의 트랜잭션 함수로만 처리합니다.

---

## 4. 데이터 모델

전체 정의: [`schema.sql`](schema.sql) (PostgreSQL 16, 실행 가능한 DDL 초안)

### 4-1. 설계 규칙

1. 모든 업무 표에 `tenant_id`가 있고, RLS 정책 `tenant_id = current_setting('app.tenant_id')`를 겁니다.
2. 금액은 `BIGINT`(원 단위 정수)로 저장합니다. 비율은 `NUMERIC(7,4)`입니다. 부동소수점은 쓰지 않습니다.
3. 주문상품(`order_items`)에 가격, PV, 판매 방식, 판매자, 포인트 가능 여부를 **스냅샷**으로 저장합니다.
4. 조직 나무는 `ltree` 경로로 저장합니다. **용어를 고정합니다**:
   - **추천인 = `referrer_id`·`referrer_path`**: 직추천 수당과 롤업에 씁니다.
   - **후원인 = `placement_parent`·`placement_side`·`placement_path`**: 바이너리 좌·우 배치에 씁니다.
   - 코드와 화면에서 'sponsor'라는 말은 쓰지 않습니다.
7. **PV**는 `공급가(부가세 제외, 할인 후 실결제) × pv_ratio(0.70)`로 시스템이 계산합니다. 판매자는 PV를 입력할 수 없습니다(일괄 등록 양식의 PV 열 삭제). 관리자 예외는 `pv_override`로 표시하고 감사 기록을 남깁니다.
8. **비회원·소비자 구매**는 `orders.ref_member_id`(개인몰 주인)의 PV로 귀속됩니다. 귀속 규칙은 기준서 v0.3.1을 따릅니다.
5. 원장 표(`point_tx`, `earnings_ledger`)는 **추가만** 합니다. 수정·삭제는 하지 않고, 정정할 때는 반대 금액 행을 추가합니다.
6. 개인정보 중 주민등록번호와 계좌번호는 애플리케이션에서 암호화합니다(AWS KMS 데이터 키, AES-256-GCM). `*_enc BYTEA`에 저장합니다.

### 4-2. 핵심 상태 흐름

```text
판매자   PENDING → APPROVED ⇄ SUSPENDED ;  PENDING → REJECTED → PENDING(재신청)
주문상품 PAID → PREPARING → SHIPPING → DELIVERED → CONFIRMED
                └→ CANCELLED          └→ RETURN_REQUESTED → RETURNED
수당정산 DAILY: 매일 00:30 자동 CONFIRMED(이상치는 관리자 알림) · MONTHLY_TRUEUP: CALCULATED → REVIEWED → CONFIRMED(3일 반영)
수당포인트 결제 → 예상(bonus_estimates) → 구매확정 → 일간 정산: AVAILABLE 90% + RESERVED 10% → 월말 확정: RESERVED 해제/조정
출금     REQUESTED → (HELD: 주민번호·계좌·마이너스) → IN_BATCH(영업일 16:00) → PAID ; FAILED(잔액 복원)
포인트   ISSUE / USE / RESTORE / REFUND / EXPIRE / ADJUST (point_tx 종류)
공제     REQUESTED → ISSUED → CANCELLED ;  FAILED(재시도)
```

**구매 확정(CONFIRMED)이 모든 실적의 출발점**입니다. 이때 다음이 일어납니다.
1. PV 기록
2. 바이너리 실적 반영
3. 판매자 정산 대상 편입
4. 35% 기준 금액 편입

---

## 5. API (주요, REST)

| 영역 | 메서드 · 경로 | 권한 |
|---|---|---|
| 인증 | `POST /api/auth/login` · `/logout` · `/identity/verify`(본인확인 콜백) | 공개 |
| 동의 | `GET /api/terms/current` · `POST /api/consents` | 로그인 |
| 상품 | `GET /api/products` · `/products/:id` · `/categories` | 공개 |
| 장바구니·주문 | `GET/POST/PATCH /api/cart` · `POST /api/orders` · `POST /api/orders/:id/cancel` · `POST /api/order-items/:id/confirm` · `/return` | 회원(비회원 주문은 주문번호+전화) |
| 결제 | `POST /api/payments/prepare` · `/confirm` · `POST /api/payments/webhook` | 회원 · PG 서명 |
| 회원 | `GET/PATCH /api/me` · `POST /api/distributor/register` · `GET /api/distributor/card` | 회원 |
| 오피스 | `GET /api/office/summary` · `/sales` · `/bonuses?type=&from=&to=` · `/tree/sponsor?root=&depth=` · `/tree/binary?root=&depth=` · `/binary/volume` · `/rank` | 판매원 |
| 지갑·출금 | `GET /api/wallet`(출금 가능·정산 대기·쇼핑 전용·예상) · `GET /api/wallet/ledger` · `POST /api/withdrawals` · `GET /api/withdrawals` · `PUT /api/me/bank-account` · `PUT /api/me/tax-id` | 판매원(출금·계좌는 재인증) |
| 포인트 | `POST /api/memberships/checkout` · `GET /api/points` · `POST /api/points/refund` | 회원 |
| 개인몰 | `POST /api/storefronts` · `PATCH /api/storefronts/me` · `PUT /api/storefronts/me/products` · `GET /api/storefronts/check-slug?slug=` | 판매원 |
| 판매자 | `POST /api/seller/apply` · `GET /api/seller/me` · `CRUD /api/seller/products` · `GET /api/seller/products/bulk/template` · `POST /api/seller/products/bulk` · `GET /bulk/:id` · `POST /bulk/:id/commit` · `GET /bulk/:id/errors` · `PATCH /api/seller/order-items/:id`(발주·송장) · `GET /api/seller/settlements` | 판매자(승인) |
| 관리자 | `/api/admin/sellers*`(승인·반려·정지) · `/products*` · `/orders*` · `/members*` · `/bonus-runs`(계산·검토·확정) · `/bonus-plans`(버전·예약·통지) · `/bonus-runs/daily`·`/bonus-runs/trueup`(월말 확정) · `/withdrawals`·`/payout-batches`(자동 승인 규칙·2인 승인·결과) · `/settlements` · `/policy-unlocks` · `/settings` · `/compliance/cap`(35% 현황) · `/notices` · `/inquiries` | 관리자(2단계 인증) |

**공통 규칙**
- 입력은 zod 스키마로 검증합니다.
- 응답 형식은 `{data}` / `{error:{code,message}}`로 통일합니다.
- 목록은 커서 방식으로 페이지를 나눕니다.
- 돈과 관련된 POST는 `Idempotency-Key` 헤더가 필수입니다.

---

## 6. 권한

| 기능 | 비회원 | 회원 | 판매원 | 판매자 | 관리자 | 최고관리자 |
|---|---|---|---|---|---|---|
| 상품 보기·구매 | ✔(비회원 주문) | ✔ | ✔ | ✔ | — | — |
| 오피스·개인몰 | | | ✔ | | 조회 | 조회 |
| 판매자센터 | | | | ✔(승인 후) | 조회 | 조회 |
| 판매자 승인·정지 | | | | | ✔ | ✔ |
| 수당 확정·지급 배치 승인 | | | | | ✔(2인) | ✔ |
| 잠금 해제(모드 2 등) | | | | | | ✔(+의견서) |
| 수당 규정 변경 | | | | | 작성 | 승인 |

등록증을 받기 전에는 설정 스위치 `features.mlm=false`로 판매원 등록, 오피스, 개인몰, 수당 관련 API가 403을 돌려줍니다.

---

## 7. 수당 엔진

```text
src/bonus-engine/
  types.ts        # Member, Sale, Rule(JSON v0.3) 타입
  direct.ts       # 직추천
  binary.ts       # 좌·우 실적 누적, 소실적, 이월, 소멸, 월 상한
  rollup.ts       # 롤업(압축)
  rankPool.ts     # 직급 보너스
  scaling.ts      # 33% 비례 삭감
  run.ts          # 기간 입력 → bonus_items 목록 (순수 함수)
  fixtures/       # 시뮬레이터 예제 조직·기대값
```

- **입력**: 기간, 규칙 JSON, 판매원 스냅샷(직급, 자격, 두 나무 경로), 구매 확정 PV 목록, 직전 이월값
- **출력**: `bonus_items[]`, 새 이월값, 기간 지급률, 삭감 계수
- **DB 접근 없음**: 그래서 같은 입력이면 항상 같은 결과가 나오고, 테스트 대상이 됩니다.
- **검증 테스트**:
  1. `simulation/` 개인수당계산 예시(골드, 최종 835,219원)
  2. 월간 시뮬레이션 12개월 합계
  3. 롤업 압축 사례 3개
  4. 소멸·상한·반품 회수

  위 결과가 엑셀과 일치해야 합니다.
- **실행**(기준서 v0.4): **일간 정산** 매일 00:30(전날 구매 확정분), **월말 확정** 매월 1일 03:00 계산 → 관리자 검토 → 3일 반영. 상세는 [일간 정산 설계](../DAILY_SETTLEMENT_DESIGN.md).

---

## 8. 작업(백그라운드) 목록

| 작업 | 주기·계기 | 비고 |
|---|---|---|
| bulk.validate / bulk.commit | 업로드 시 | 1,000줄 한도 |
| order.autoConfirm | 매일 04:00 | 배송 완료 7일 경과 자동 구매 확정 |
| bonus.daily | 매일 00:30 | 전날 구매 확정분 정산, 90%/10% 원장 기록, 알림 |
| bonus.monthlyTrueup | 매월 1일 03:00 계산 → 3일 반영 | 그달 지급률 확인, 정산 대기 해제·조정 |
| bonus.estimate | 결제·확정·반품 시 | 실시간 예상 수당 생성·갱신 |
| qualification.daily | 매일 00:10 | 직전 30일 PV 자격 |
| rank.evaluate | 매월 1일 02:00 | 직급 판정, rank_history |
| points.expire / points.notify | 매일 | 30일·7일 전 알림 |
| mutualAid.issue / retry | 결제 완료 시 · 10분 | 3회 실패 시 관리자 알림 |
| payout.batch | 영업일 16:00 | 그날 출금 신청 → 배치(자동 승인 규칙 / 2인 승인) |
| payout.export / payout.result | 배치 승인 시 | 펌뱅킹, 실패 시 잔액 복원 |
| settlement.seller | 월 2회 | 판매자 정산 |
| compliance.capCheck | 매일 | 33% 경고·35% 차단 플래그 |
| ledger.reconcile | 매일 05:00 | 원장 합계 대조, 불일치 시 알림 |
| notify.send | 즉시 | 실패 시 문자 대체 |

---

## 9. 환경과 배포

| 환경 | 용도 | 비고 |
|---|---|---|
| local | 개발 | Docker로 PostgreSQL 실행 |
| staging | 테스트·시연 | PG·본인확인 **테스트 키** |
| production | 운영 | 실키, 관리자 IP 제한 |

- 설정과 비밀값: 저장소에 넣지 않고 AWS Secrets Manager(또는 SSM Parameter Store)에서 읽습니다. `scripts/env.sh` 방식은 그대로 둡니다.
- 배포 순서: 마이그레이션 → 앱 → 작업 실행기. 실패하면 이전 버전으로 되돌립니다(CodeDeploy).
- 백업: RDS 자동 백업(7일 이상) + 매주 스냅샷.

---

## 10. 보안

1. 비밀번호 argon2id. 로그인 5회 실패 시 잠금. 관리자는 2단계 인증(TOTP)
2. 세션: HttpOnly·Secure 쿠키, 관리자 세션 30분
3. 주민등록번호(`distributor_tax_ids` 별도 표)·계좌번호 암호화, 열람 시 `sensitive_access_logs` 기록과 마스킹. 주민번호 미등록자는 지급 보류(HELD)
4. 결제 웹훅 서명 검증, 금액 서버 재확인
5. 파일 업로드: 형식·크기 검사. 비공개 S3 + 짧은 유효기간의 주소
6. 관리자 작업 전부 audit_logs에 기록(누가, 언제, 이전 값, 이후 값)
7. OWASP Top 10 점검(P5), 의존성 취약점 자동 검사

---

## 11. 테스트 전략

| 종류 | 도구 | 대상 | 기준 |
|---|---|---|---|
| 단위 | Vitest | 수당 엔진, 포인트, 원장, 검증 규칙 | 엔진 커버리지 95% 이상 |
| 통합 | Vitest + 테스트 DB | 주문→확정→PV→수당, RLS 분리 | 핵심 흐름 전부 |
| 화면 흐름 | Playwright | 시안의 3가지 흐름 + 결제(테스트 키) | 매 배포 전 |
| 시뮬레이터 대조 | Vitest | 엑셀 결과 고정값 | 1원 단위 일치 |
| 부하 | k6 | 상품 목록, 결제, 월간 정산(판매원 5만 명 가정) | 정산 30분 이내 |

---

## 12. 개발 규칙

- 브랜치: `main`(운영) / `develop` / 기능 브랜치. PR 리뷰 1명 이상, CI 통과 필수
- 커밋 메시지는 무엇을 왜 바꿨는지 쓰고, 마이그레이션은 되돌리기 SQL과 함께 작성합니다.
- 금액 계산은 `lib/money.ts` 함수만 씁니다. 반올림 규칙은 원 미만 버림, 원천징수는 10원 단위 반올림(시뮬레이터와 같음)입니다.
- 화면 문구는 시안 문구를 기준으로 합니다(수익 보장 표현 금지 목록을 린트로 검사).
