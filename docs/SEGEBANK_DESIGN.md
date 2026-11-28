# 소개뱅크 전체 설계서 (v0.2, 시안 단계)

> ⚠ **부분 대체됨 (2026-11-26)**: 아래 항목은 최신 문서를 따릅니다.
> - 데이터 모델·API·일정 → [개발 설계서](dev/TECH_SPEC.md) · [schema.sql](dev/schema.sql) · [스프린트 계획](dev/SPRINT_PLAN.md)
> - 판매 방식(오픈마켓만 → 직매입·위탁·중개) → [판매 방식](SALES_MODEL_DESIGN.md)
> - 수당("규정 수령 후") → [기준서 v0.3](BONUS_RULES_V0.3.md)
> - 출금 신청·"출금 수수료 3.3%" → **지급일 자동 지급, 3.3%는 원천징수**
> - 직급 "일반/실버/골드" → 판매원·실버·골드·플래티넘·다이아몬드

> 이 설계는 참고 사이트(smart79)의 **화면 구성과 메뉴 흐름**을 분석해 만들었습니다. 이름, 디자인, 문구는 새로 만들었습니다.
> 아래 **[제외 범위]** 기능은 법률 검토 전까지 설계와 구현에서 뺐습니다.

---

## 1. 결론

| 항목 | 결정 |
|---|---|
| 서비스 구성 | **4개 영역**: 소개뱅크 몰(쇼핑몰), 회원 오피스, 판매자센터, 관리자 |
| 판매 방식 | 여러 판매자가 입점해서 **웹에서 직접** 상품·주문·배송을 관리하는 오픈마켓 |
| 판매자 입점 | 판매자 신청 → **관리자 승인** → 상품 등록 가능 (반려 시 사유 표시, 다시 신청 가능) |
| 상품 등록 | **개별 등록**(화면 입력) + **일괄 등록**(엑셀/CSV 업로드, 줄마다 검사, 정상 줄만 등록) |
| 추천 기술 | Next.js(화면+API 한 프로젝트) + PostgreSQL + AWS S3 → 기존 EC2·PM2·CodePipeline에 그대로 배포 |
| 시안 | `mockup/index.html`: 서버 없이 브라우저로 열고, 화면끼리 데이터가 이어짐 |

### 제외 범위 (법률 검토 전까지)

1. 포인트를 **암호화폐(코인)로 바꾸는 출금**: 원화 계좌 출금만 둡니다.
2. 패키지를 보유하면 수익을 나눠 주는 **수익 배분형 상품**(참고 사이트의 '포도송이'): 유사수신행위법 위험이 있습니다.
3. **주민등록번호 수집**: ~~법적 근거가 확인될 때만~~ → **수당 지급 대상 판매원에 한해** 원천징수·지급명세서용으로 첫 지급 전 1회 수집, 암호화 보관([개인정보처리방침](terms/PRIVACY_POLICY.md) 3조).
4. **수당 계산 규칙**: 화면 틀만 만들고, 실제 비율은 등록된 수당 규정을 받은 뒤 구현합니다. 방문판매법상 수당 총액 한도가 있으며, 최신 기준은 확인이 필요합니다.

---

## 2. 전체 구조

```text
                    ┌──────────────── 사용자 ────────────────┐
                    │ 고객/회원        판매자          관리자   │
                    └────┬──────────────┬──────────────┬──────┘
                         ▼              ▼              ▼
                     /  (몰)       /seller        /admin        /office (회원 오피스)
                    ┌───────────────────────────────────────────┐
                    │  Next.js 앱 (화면 + API)  ─ EC2 + PM2       │
                    │  ├ 인증: 역할 member / seller / admin        │
                    │  ├ 업무 모듈: 회원·조직 / 상품 / 주문 / 정산    │
                    │  └ 작업 대기열(pg-boss): 일괄 등록, 정산 계산   │
                    └───────┬───────────────┬───────────────┬───┘
                            ▼               ▼               ▼
                     PostgreSQL(RDS)    S3(이미지·서류·    결제대행사(PG)
                                         업로드 파일)       · 문자/메일
```

### 2-1. 역할과 권한

| 역할 | 할 수 있는 일 | 들어갈 수 있는 곳 |
|---|---|---|
| 비회원 | 상품 보기 | 몰 |
| 회원(member) | 구매, 수당·조직 확인, 출금 신청 | 몰, 오피스 |
| 판매자(seller) | **승인 후** 상품·주문·정산 관리 | 판매자센터 (승인 전에는 신청 화면만) |
| 관리자(admin) | 전체 관리, 판매자 승인 | 관리자 |

한 사람이 회원과 판매자를 함께 할 수 있습니다. 판매자 정보는 `users`에 붙는 별도 `sellers` 표로 관리합니다.

---

## 3. 화면 목록 (시안 파일과 1:1 대응)

### 3-1. 소개뱅크 몰 — `mockup/mall.html`

| ID | 화면 | 주요 기능 |
|---|---|---|
| MALL-01 | 홈 | 배너, 추천 상품 |
| MALL-02 | 카테고리 / 검색 | 정렬(추천·가격·신상품) |
| MALL-03 | 상품 상세 | 가격·할인율·PV·재고, 장바구니/바로 구매/찜, **판매자 정보 표시**, 판매자에게 문의 |
| MALL-04 | 장바구니 | 수량 변경, 배송비(5만 원 이상 무료, 시안 기준) |
| MALL-05 | 주문·결제 | 배송지, 결제 수단(PG), 적립 예정 PV |
| MALL-06 | 주문 완료 | 주문번호 |
| MALL-07 | 마이페이지 | 주문 내역(구매 확정), 찜, 배송지, 내 문의 |
| MALL-08 | 고객센터 | 공지, 자주 묻는 질문 |

### 3-2. 회원 오피스 — `mockup/office.html` (참고 사이트 메뉴 구조를 따름)

| ID | 화면 | 참고 사이트 메뉴 | 비고 |
|---|---|---|---|
| OFF-01 | 오피스 홈 | 메인 카드 메뉴 | 추천 코드 복사, 총매출, 수당, 출금 가능액, 하위 회원, PV |
| OFF-02 | 매출 내역 | 매출내역 | 몰 구매가 자동 반영(별도 매출 신청 없음) |
| OFF-03 | 수당 내역 | 보너스내역 | 종류별 필터 |
| OFF-04 | 일자별 수당 | 일자별 합계 | 월 선택 |
| OFF-05 | 출금 신청 | 출금신청(교환) | **원화 계좌**, 최소 금액·단위·수수료 |
| OFF-06 | 출금 내역 | 출금내역 | |
| OFF-07 | 추천 계보도 | 추천 계보도 | **가로 조직도**, 회원 찾기 |
| OFF-08 | 마이팀 정보 | 마이팀 | 하위 회원 목록 |
| OFF-09~12 | 개인정보 보기/수정, 비밀번호, 금융정보 | 같은 이름 | 주민번호는 수당 지급 대상자만(암호화) |
| OFF-13~14 | 공지, 1:1 문의 | | |

### 3-3. 판매자센터 — `mockup/seller.html`

| ID | 화면 | 주요 기능 |
|---|---|---|
| SEL-01 | 입점 신청 | 상호, 대표자, 사업자번호, 통신판매업 신고번호, 연락처, 정산 계좌, 서류 2종, 약관 동의 |
| SEL-02 | 심사 중 / 반려 / 정지 | 상태 안내, 반려 사유, 다시 신청 |
| SEL-03 | 판매자 홈 | 판매중 상품, 신규 주문, 배송 준비, 판매액, 품절, 문의 |
| SEL-04 | 상품 목록 | 검색, 재고 수정, 숨기기 |
| SEL-05 | **상품 개별 등록** | 기본 정보, 옵션, 이미지, 상세 설명, 상품 고시 정보 |
| SEL-06 | **상품 일괄 등록** | 양식 내려받기 → 업로드 → 줄별 검사 → 정상 줄 등록 → 오류 줄 내려받기 |
| SEL-07 | 주문·배송 관리 | 발주 확인 → 송장 입력(배송중) |
| SEL-08 | 정산 내역 | 판매액, 수수료, 정산액 |
| SEL-09~11 | 상품 문의, 판매자 정보, 판매자 공지 | |

### 3-4. 관리자 — `mockup/admin.html`

| ID | 화면 | 주요 기능 |
|---|---|---|
| ADM-01 | 대시보드 | 가입·매출·**승인 대기**·출금 대기·주문·문의, 월 매출 |
| ADM-02 | **판매자 입점 승인** | 대기 목록, 상세·서류 보기, **승인 / 반려(사유 필수)**, 처리 이력 |
| ADM-03 | 판매자 목록 | 상태별 검색, 판매 정지/해제(정지하면 판매중 상품도 판매중지) |
| ADM-04 | 판매자 정산 | 기간 선택, 계산, 확정 |
| ADM-05 | 전체 상품 | 판매자별 필터, 판매 중지/재개 |
| ADM-06 | 카테고리 | 추가 |
| ADM-07 | 전체 주문 | 기간·상태 검색 |
| ADM-08 | 회원 관리 | 직급 변경, 정지 |
| ADM-09 | 추천 계보도 | 기준 회원 선택 |
| ADM-10 | 수당 정산 | 계산·확정 (규칙은 규정 수령 후) |
| ADM-11 | 출금 승인 | 지급 / 반려 |
| ADM-12~13 | 공지(대상: 전체/회원/판매자), 문의 관리 | |
| ADM-14 | 운영 설정 | 판매 수수료, 입점 승인 방식(수동/자동), 상품 검수 여부, 출금 수수료·최소액 |

---

## 4. 판매자 입점 승인 설계

### 4-1. 상태 흐름

```text
 (신규) ──신청──▶ PENDING(승인대기) ──승인──▶ APPROVED(승인) ──정지──▶ SUSPENDED(정지)
                      │                         ▲                      │
                      └──반려(사유)──▶ REJECTED(반려) ──보완 후 재신청──┘   └──해제──▶ APPROVED
```

| 상태 | 판매자센터 | 몰 노출 |
|---|---|---|
| PENDING | 심사 중 화면만 | - |
| REJECTED | 반려 사유 + 재신청 버튼 | - |
| APPROVED | 전체 메뉴 | 상품 노출 |
| SUSPENDED | 정지 안내만 | **모든 상품 숨김** |

### 4-2. 관리자 심사 체크리스트

1. 사업자등록번호가 실제로 있고 계속 사업 중인지 확인합니다. 국세청 사업자 상태 조회 API(공공데이터포털)를 쓸 수 있으며, 사용 조건은 확인이 필요합니다.
2. 통신판매업 신고번호가 신고증 사본과 일치하는지 봅니다.
3. 정산 계좌의 예금주가 상호 또는 대표자와 같은지 봅니다.
4. 취급 상품이 판매 금지·인허가 필요 품목인지 봅니다(건강기능식품, 의료기기 등).

### 4-3. 처리 규칙

- 승인과 반려는 **누가, 언제, 무엇을** 했는지 `audit_logs`에 남깁니다.
- 반려할 때는 사유가 필수이고, 판매자에게 그대로 보입니다.
- 결과는 문자나 메일로 알립니다.
- 운영 설정에서 '자동 승인'을 고르면 서류 검사만 통과하면 바로 APPROVED가 됩니다. 기본값은 수동 승인입니다.

---

## 5. 상품 일괄 등록 설계

### 5-1. 흐름

```text
양식 내려받기 → 엑셀에서 작성 → 업로드(.xlsx/.csv) → [서버] 파일 저장(S3) + 작업 생성
   → [작업 대기열] 줄마다 검사 → 결과 화면(정상 n / 오류 m) → "정상 n건 등록"
   → 상품 생성 → 오류 줄만 엑셀로 내려받기 → 고쳐서 다시 업로드
```

### 5-2. 양식 (시안과 같음)

| 열 | 필수 | 규칙 |
|---|---|---|
| 상품명 | ● | 60자 이내 |
| 카테고리 | ● | 등록된 카테고리 이름과 정확히 일치 |
| 판매가 | ● | 숫자(원), 0보다 큼. `32,000`처럼 쉼표 허용 |
| 정가 | | 비우면 판매가. 판매가보다 낮으면 오류 |
| 재고 | ● | 숫자. 0이면 품절로 등록 |
| PV | | 숫자. 관리자 정책으로 상한 설정 가능 |
| 옵션 | | `색상:빨강/파랑;크기:S/M` |
| 대표이미지URL | | http(s) 주소. 비우면 등록 후 따로 올림 |
| 배송비 | | 숫자. 비우면 0원 |
| 상세설명 | | 자유 입력 |
| (판매자상품코드) | | **실서비스 추가 권장**. 같은 코드면 새로 만들지 않고 수정(가격·재고 일괄 변경에 사용) |

### 5-3. 제한과 처리

- 한 번에 최대 **1,000줄**, 파일 크기 **5MB**까지 받습니다.
- 줄 검사는 **작업 대기열**에서 처리해 화면이 멈추지 않게 합니다. 진행률은 화면에서 2초마다 확인합니다.
- **정상 줄만 등록**합니다. 전부 아니면 전부 취소하는 방식보다 판매자가 덜 번거롭습니다.
- 같은 파일을 두 번 올려 상품이 두 번 생기는 것을 막기 위해, 파일 해시값(내용으로 만든 고유값)이 같으면 경고합니다.
- 엑셀은 `exceljs`, CSV는 `csv-parse`로 읽습니다. 한글이 깨지지 않도록 UTF-8과 CP949를 모두 지원합니다.

---

## 6. 데이터 구조 (PostgreSQL)

```sql
-- 사용자와 역할
CREATE TABLE users (
  id            BIGSERIAL PRIMARY KEY,
  login_id      VARCHAR(30) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,                 -- bcrypt/argon2
  name          VARCHAR(50) NOT NULL,
  phone         VARCHAR(20), email VARCHAR(100),
  roles         TEXT[] NOT NULL DEFAULT '{member}',   -- member / seller / admin
  status        VARCHAR(10) NOT NULL DEFAULT 'ACTIVE', -- ACTIVE / SUSPENDED / LEFT
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 회원(오피스): 추천 관계와 직급
CREATE TABLE members (
  user_id    BIGINT PRIMARY KEY REFERENCES users(id),
  sponsor_id BIGINT REFERENCES members(user_id),  -- 추천인
  grade      VARCHAR(20) NOT NULL DEFAULT '일반',
  path       TEXT NOT NULL                        -- 조직 경로 예: '1/5/23' (하위 조회를 빠르게)
);

-- 판매자와 입점 심사
CREATE TABLE sellers (
  id              BIGSERIAL PRIMARY KEY,
  user_id         BIGINT UNIQUE NOT NULL REFERENCES users(id),
  company         VARCHAR(100) NOT NULL,
  ceo             VARCHAR(50)  NOT NULL,
  biz_no          VARCHAR(12)  NOT NULL UNIQUE,   -- 000-00-00000
  mail_order_no   VARCHAR(50)  NOT NULL,          -- 통신판매업 신고번호
  phone VARCHAR(20), email VARCHAR(100),
  bank_name VARCHAR(30), bank_account VARCHAR(40), bank_holder VARCHAR(50),
  commission_rate NUMERIC(5,2),                   -- 비우면 기본 수수료
  status          VARCHAR(10) NOT NULL DEFAULT 'PENDING', -- PENDING/APPROVED/REJECTED/SUSPENDED
  reject_reason   TEXT,
  applied_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at      TIMESTAMPTZ,
  decided_by      BIGINT REFERENCES users(id)
);
CREATE TABLE seller_documents (
  id BIGSERIAL PRIMARY KEY, seller_id BIGINT REFERENCES sellers(id),
  kind VARCHAR(20) NOT NULL,                      -- BIZ_REG / MAIL_ORDER / BANKBOOK
  file_key TEXT NOT NULL, uploaded_at TIMESTAMPTZ DEFAULT now()
);

-- 상품
CREATE TABLE categories (id SERIAL PRIMARY KEY, name VARCHAR(30) UNIQUE NOT NULL, sort INT DEFAULT 0);
CREATE TABLE products (
  id          BIGSERIAL PRIMARY KEY,
  seller_id   BIGINT NOT NULL REFERENCES sellers(id),
  seller_code VARCHAR(50),                        -- 판매자상품코드 (일괄 수정용)
  category_id INT NOT NULL REFERENCES categories(id),
  name        VARCHAR(60) NOT NULL,
  price       INT NOT NULL CHECK (price > 0),
  list_price  INT,
  stock       INT NOT NULL DEFAULT 0,
  pv          INT NOT NULL DEFAULT 0,
  ship_fee    INT NOT NULL DEFAULT 0,
  description TEXT,
  status      VARCHAR(12) NOT NULL DEFAULT 'ON_SALE', -- ON_SALE/SOLD_OUT/HIDDEN/BLOCKED/REVIEW
  created_at  TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (seller_id, seller_code)
);
CREATE TABLE product_options (id BIGSERIAL PRIMARY KEY, product_id BIGINT REFERENCES products(id), name VARCHAR(50), value VARCHAR(50), extra_price INT DEFAULT 0, stock INT);
CREATE TABLE product_images  (id BIGSERIAL PRIMARY KEY, product_id BIGINT REFERENCES products(id), file_key TEXT, sort INT DEFAULT 0);

-- 일괄 등록 작업
CREATE TABLE bulk_jobs (
  id BIGSERIAL PRIMARY KEY, seller_id BIGINT REFERENCES sellers(id),
  file_key TEXT NOT NULL, file_hash CHAR(64) NOT NULL,
  status VARCHAR(10) NOT NULL DEFAULT 'QUEUED',   -- QUEUED/CHECKING/CHECKED/COMMITTED/FAILED
  total INT, ok_count INT, err_count INT, created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE bulk_job_rows (
  job_id BIGINT REFERENCES bulk_jobs(id), line_no INT,
  data JSONB NOT NULL, errors TEXT[], product_id BIGINT,
  PRIMARY KEY (job_id, line_no)
);

-- 주문: 한 주문에 여러 판매자 상품이 섞일 수 있어 배송·정산은 주문상품 단위
CREATE TABLE orders (
  id BIGSERIAL PRIMARY KEY, order_no VARCHAR(20) UNIQUE NOT NULL, buyer_id BIGINT REFERENCES users(id),
  total INT NOT NULL, ship_total INT NOT NULL, pay_method VARCHAR(20), pg_tid VARCHAR(100),
  status VARCHAR(12) NOT NULL,                    -- PAID/CANCELLED/PARTIAL
  receiver JSONB, created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE order_items (
  id BIGSERIAL PRIMARY KEY, order_id BIGINT REFERENCES orders(id),
  product_id BIGINT REFERENCES products(id), seller_id BIGINT REFERENCES sellers(id),
  name_snapshot VARCHAR(60), price INT, qty INT, pv INT,
  status VARCHAR(12) NOT NULL,                    -- PAID/PREPARING/SHIPPING/DELIVERED/CONFIRMED/CANCELLED/RETURNED
  courier VARCHAR(20), tracking_no VARCHAR(30), confirmed_at TIMESTAMPTZ
);

-- 판매자 정산 (구매확정된 order_items 기준)
CREATE TABLE settlements (
  id BIGSERIAL PRIMARY KEY, seller_id BIGINT REFERENCES sellers(id),
  period_from DATE, period_to DATE, gross INT, commission INT, net INT,
  status VARCHAR(10) DEFAULT 'CALCULATED',        -- CALCULATED/CONFIRMED/PAID
  UNIQUE (seller_id, period_from)
);

-- 회원 포인트·수당·출금 (금액이 바뀌는 모든 일은 원장에 한 줄씩 기록)
CREATE TABLE point_ledger (
  id BIGSERIAL PRIMARY KEY, user_id BIGINT REFERENCES users(id),
  kind VARCHAR(20) NOT NULL,                      -- BONUS / WITHDRAW / WITHDRAW_FEE / REFUND / ADJUST
  amount INT NOT NULL,                            -- +적립 / -차감
  ref_type VARCHAR(20), ref_id BIGINT, memo TEXT, created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE bonuses (id BIGSERIAL PRIMARY KEY, user_id BIGINT, period DATE, type VARCHAR(20), from_user BIGINT, amount INT, status VARCHAR(10));
CREATE TABLE withdrawals (id BIGSERIAL PRIMARY KEY, user_id BIGINT, amount INT, fee INT, bank JSONB, status VARCHAR(10), requested_at TIMESTAMPTZ DEFAULT now(), processed_at TIMESTAMPTZ, processed_by BIGINT);

-- 게시판·감사 기록
CREATE TABLE notices   (id BIGSERIAL PRIMARY KEY, title TEXT, body TEXT, audience VARCHAR(10), created_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE inquiries (id BIGSERIAL PRIMARY KEY, user_id BIGINT, target VARCHAR(10), seller_id BIGINT, product_id BIGINT, title TEXT, body TEXT, answer TEXT, status VARCHAR(10), created_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE audit_logs(id BIGSERIAL PRIMARY KEY, actor_id BIGINT, action VARCHAR(50), target_type VARCHAR(20), target_id BIGINT, detail JSONB, created_at TIMESTAMPTZ DEFAULT now());
```

---

## 7. 주요 API

| 영역 | 메서드·주소 | 설명 | 권한 |
|---|---|---|---|
| 인증 | `POST /api/auth/login` · `POST /api/auth/logout` | 로그인/로그아웃 | 모두 |
| 판매자 | `POST /api/seller/apply` | 입점 신청(서류 업로드 포함) | 로그인 |
| | `GET /api/seller/me` | 내 판매자 상태 | 로그인 |
| | `POST /api/seller/products` · `PATCH /api/seller/products/:id` | 개별 등록·수정 | APPROVED 판매자 |
| | `GET /api/seller/products/bulk/template` | 양식 내려받기 | APPROVED |
| | `POST /api/seller/products/bulk` | 업로드 → `jobId` | APPROVED |
| | `GET /api/seller/products/bulk/:jobId` | 진행률·검사 결과 | 본인 |
| | `POST /api/seller/products/bulk/:jobId/commit` | 정상 줄 등록 | 본인 |
| | `GET /api/seller/products/bulk/:jobId/errors.xlsx` | 오류 줄 내려받기 | 본인 |
| | `PATCH /api/seller/order-items/:id` | 발주 확인, 송장 입력 | 본인 상품 |
| 관리자 | `GET /api/admin/sellers?status=PENDING` | 승인 대기 목록 | admin |
| | `POST /api/admin/sellers/:id/approve` | 승인 | admin |
| | `POST /api/admin/sellers/:id/reject` `{reason}` | 반려 | admin |
| | `POST /api/admin/sellers/:id/suspend` · `/resume` | 정지·해제 | admin |
| 몰 | `GET /api/products` · `GET /api/products/:id` | 목록·상세(APPROVED 판매자 상품만) | 모두 |
| | `POST /api/orders` · `POST /api/payments/confirm` | 주문·결제 확인(PG) | member |
| 오피스 | `GET /api/office/summary` · `/tree?root=` · `/bonuses` | 홈, 계보도, 수당 | member |
| | `POST /api/office/withdrawals` | 출금 신청 | member |

### 예시: 판매자 승인 처리 (Node.js, 트랜잭션)

```js
// POST /api/admin/sellers/:id/approve
export async function approveSeller(db, adminId, sellerId) {
  return db.tx(async (t) => {
    const s = await t.one('SELECT * FROM sellers WHERE id=$1 FOR UPDATE', [sellerId]);
    if (s.status !== 'PENDING') throw new HttpError(409, '승인 대기 상태가 아닙니다');
    await t.none(`UPDATE sellers SET status='APPROVED', decided_at=now(), decided_by=$2, reject_reason=NULL WHERE id=$1`, [sellerId, adminId]);
    await t.none(`UPDATE users SET roles = array_append(roles,'seller') WHERE id=$1 AND NOT ('seller' = ANY(roles))`, [s.user_id]);
    await t.none(`INSERT INTO audit_logs(actor_id,action,target_type,target_id) VALUES($1,'SELLER_APPROVE','seller',$2)`, [adminId, sellerId]);
    await notify(s.user_id, '입점이 승인되었습니다. 지금부터 상품을 등록할 수 있습니다.');
  });
}
```

### 예시: 일괄 등록 한 줄 검사 (시안 `seller.html`의 `validateRow`와 같은 규칙)

```js
export function validateRow(r, categories) {
  const e = [];
  for (const c of ['상품명', '카테고리', '판매가', '재고']) if (!String(r[c] ?? '').trim()) e.push(`${c} 빈칸`);
  if (r.상품명?.length > 60) e.push('상품명 60자 초과');
  if (r.카테고리 && !categories.includes(r.카테고리)) e.push(`없는 카테고리(${r.카테고리})`);
  const num = (v) => (v === '' || v == null ? null : /^\d+$/.test(String(v).replace(/,/g, '')) ? +String(v).replace(/,/g, '') : NaN);
  for (const c of ['판매가', '정가', '재고', 'PV', '배송비']) if (Number.isNaN(num(r[c]))) e.push(`${c} 숫자 아님`);
  if (num(r.판매가) === 0) e.push('판매가 0원');
  if (num(r.정가) && num(r.정가) < num(r.판매가)) e.push('정가가 판매가보다 낮음');
  return e;
}
```

---

## 8. 기술과 설치 항목

| 구분 | 선택 | 이유 |
|---|---|---|
| 화면 + API | **Next.js (React)** 하나의 프로젝트 | 몰은 검색 노출(SEO)이 필요하고, 4개 영역을 한 번에 배포할 수 있음 |
| DB | PostgreSQL 16 (AWS RDS) | 조직 경로·JSON·트랜잭션에 강함 |
| ORM | Prisma 또는 pg-promise | 표 구조를 코드로 관리 |
| 작업 대기열 | pg-boss | 별도 Redis 없이 PostgreSQL로 일괄 등록·정산 작업 처리 |
| 파일 | AWS S3 | 상품 이미지, 사업자 서류(비공개 버킷) |
| 엑셀 | exceljs, csv-parse | 일괄 등록 |
| 결제 | 국내 결제대행사(PG) **오픈마켓(서브몰) 정산 상품** | 판매 대금을 직접 받아 나눠 주면 전자금융업 등록이 필요할 수 있음. PG사와 확인 필요 |
| 배포 | 기존 `appspec.yml`, `buildspec.yml`, PM2 | `npm start` 하나로 실행 |

설치 예시:

```bash
npx create-next-app@latest segebank-app --ts --eslint --app
cd segebank-app
npm i pg-promise pg-boss exceljs csv-parse bcrypt zod @aws-sdk/client-s3
npm i -D vitest playwright
```

---

## 9. 구현 단계 (1인 개발 기준 추정, 확인 필요)

| 단계 | 내용 | 기간(추정) |
|---|---|---|
| 0 | 시안 확정 (지금) | 1주 |
| 1 | 로그인·역할, DB, 관리자 틀, 카테고리 | 1~2주 |
| 2 | **판매자 입점 신청·승인**, 판매자센터 틀 | 1주 |
| 3 | **상품 개별 등록 + 일괄 등록**, 이미지 업로드 | 2주 |
| 4 | 몰(목록·상세·장바구니·주문), PG 결제 연동 | 2~3주 |
| 5 | 주문·배송(송장), 구매 확정, 판매자 정산 | 2주 |
| 6 | 회원 오피스: 계보도, PV, 출금 신청·승인 | 2주 |
| 7 | 수당 계산 (규정 수령·법률 검토 후) | 규정에 따라 |
| 8 | 보안 점검, 부하 테스트, 오픈 | 1주 |

---

## 10. 예상 비용 (확인 필요: 요금은 자주 바뀜)

| 항목 | 예상 | 비고 |
|---|---|---|
| AWS EC2 (t3.small) | 월 약 2~3만 원 | 서울 리전 기준, 확인 필요 |
| AWS RDS PostgreSQL (db.t4g.micro) | 월 약 2~4만 원 | 백업 용량 별도 |
| S3 + 데이터 전송 | 월 수천 원~ | 이미지 양에 따라 |
| PG 수수료 | 결제액의 약 2~3%대 | 업체·업종별 계약, 확인 필요 |
| 문자 발송 | 건당 10~30원대 | 업체별 상이 |
| 도메인·SSL | 연 2만 원 내외 / 무료(ACM) | |
| 법률 검토 (다단계·전자상거래) | 별도 견적 | **오픈 전 필수 권장** |

---

## 11. 테스트 방법

1. **시안 흐름 테스트(완료)**: Playwright로 신규 판매자 신청 → 관리자 승인 → 일괄 등록(정상 3, 오류 4) → 실제 CSV 업로드(쉼표가 든 값 포함) → 개별 등록 → 몰 노출 → 주문 → 송장 입력 → 판매자 정지 시 상품 숨김까지 확인했습니다. 휴대폰 화면(390px)에서 가로로 넘치지 않는 것도 확인했습니다.
2. **실서비스 단위 테스트**: `validateRow`, 정산 계산, 출금 한도 계산
3. **권한 테스트**: 승인 전 판매자가 상품 API를 부르면 403, 다른 판매자 상품 수정도 403
4. **일괄 등록 테스트**: 1,000줄, 한글 CP949 파일, 빈 줄, 중복 업로드
5. **결제 테스트**: PG 테스트 키로 결제·취소·부분 취소

## 12. 오류가 났을 때 확인 순서

1. 화면 오류 → 브라우저 개발자도구 Console과 Network의 응답 코드
2. API 오류 → `pm2 logs segebank`에서 요청 id로 검색
3. 일괄 등록이 멈춤 → `bulk_jobs.status`, pg-boss 작업 상태 표
4. 결제 불일치 → `orders.pg_tid`로 PG 관리자 화면과 대조
5. 정산 금액 이상 → `point_ledger`와 `settlements` 합계 비교 SQL

## 13. 운영·보안·확장 주의사항

1. **비밀번호**: bcrypt/argon2로 저장하고 로그인 실패 횟수를 제한합니다. 관리자는 2단계 인증을 씁니다.
2. **개인정보**: 계좌번호는 암호화해 저장하고 화면에는 가려서 보여 줍니다. 사업자 서류는 비공개 S3에 두고 짧은 기간만 유효한 주소로 보여 줍니다.
3. **돈 계산**: 포인트와 출금은 반드시 원장(`point_ledger`)으로 처리합니다. 잔액은 원장 합계로 검증합니다.
4. **법률**: 전자상거래법상 판매자 정보 표시, 청약철회 규정. 다단계로 운영하면 방문판매법 등록과 수당 한도. 판매대금 정산은 전자금융거래법. **오픈 전 법률 검토가 필요합니다.**
5. **확장**: 판매자가 늘면 상품 검색을 OpenSearch로 옮기고, 이미지는 CloudFront로 배포합니다.
