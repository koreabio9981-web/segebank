# 소개뱅크 분양 기능 설계서 (v1.0, 설계만, 개발 전)

> **분양**: 소개뱅크 시스템 위에 **별도의 사이트(쇼핑몰)를 만들어 다른 사람에게 주는 기능**입니다.
> 분양 대상 3가지를 모두 지원하는 것으로 설계합니다. 주소 방식은 7장에서 비교하고 추천합니다.

관련 문서:
- [계획서](PLAN.md)
- [모바일 웹 설계](MOBILE_WEB_DESIGN.md)
- [전체 시스템 설계](SEGEBANK_DESIGN.md)
- [수당규정서 작성법](BONUS_PLAN_GUIDE.md)

---

## 1. 최종 결론

| 항목 | 결정 |
|---|---|
| 분양 종류 | **A. 회원 개인몰** · **B. 판매자 독립몰** · **C. 솔루션 분양(다른 회사)** |
| 시스템 방식 | 프로그램 하나로 여러 사이트를 운영하는 **멀티 사이트 구조**. 접속 주소를 보고 어느 사이트인지 구분 |
| 핵심 원칙 | **처음부터 모든 데이터에 "사이트 번호(tenant_id)"를 넣어 설계**. 나중에 C를 추가할 때 다시 만들지 않아도 됨 |
| 주소 | 기본은 **하위 주소**(`kim01.segebank.co.kr`) 자동 발급. 원하면 **자기 도메인 연결**(2단계, 승인·유료) |
| 오픈 순서 | **1단계 A** → 2단계 B → 3단계 C |
| 모바일 | 개인몰 만들기·관리·공유를 **휴대폰에서 모두** 가능하게. 분양 사이트마다 홈 화면 설치(PWA) 지원 |

### 판단 근거

1. **A를 먼저 하는 이유**: 회원 추천 구조와 바로 연결되어 효과가 가장 크고, 상품·주문·정산을 본사 것을 그대로 쓰므로 만들기 가장 쉽습니다.
2. **C를 마지막에 하는 이유**: 다른 회사의 회원·상품·관리자를 완전히 분리해야 해서 보안과 계약 검토가 가장 많이 필요합니다.
3. **처음부터 tenant_id를 넣는 이유**: 나중에 넣으려면 모든 표와 모든 조회를 고쳐야 해서 비용이 몇 배로 듭니다. 처음에는 소개뱅크 하나(1번 사이트)만 있어도 칸을 만들어 둡니다.

---

## 2. 분양 종류 비교

| 항목 | A. 회원 개인몰 | B. 판매자 독립몰 | C. 솔루션 분양 |
|---|---|---|---|
| 받는 사람 | 소개뱅크 회원(판매원) | 승인된 입점 판매자 | 다른 회사 |
| 예시 주소 | `kim01.segebank.co.kr` | `greenfood.segebank.co.kr` | `abcmall.com` |
| 상품 | 본사·입점 판매자 상품 중 **골라서 진열** | **자기 상품만** | 그 회사가 직접 등록 |
| 회원 | 소개뱅크 회원과 **공통** (가입하면 개인몰 주인이 추천인) | 소개뱅크 회원과 공통 | **완전히 별도** |
| 주문·결제·배송 | 소개뱅크가 처리 | 소개뱅크가 처리, 배송은 판매자 | 그 회사가 처리(자기 PG 계약) |
| 정산 | 개인몰 주인: **실적·PV**(수당 규정에 따름) | 판매자 정산(수수료 차감) | 소개뱅크는 **이용료만** 받음 |
| 디자인 | 기본 틀 3개 중 선택 + 로고·배너·소개글 | 틀 선택 + 색·로고·배너·메뉴 | 전체 꾸미기 |
| 관리 화면 | 오피스 > **내 쇼핑몰** | 판매자센터 > **독립몰 관리** | 그 회사 전용 **관리자** |
| 개설 | 신청 → 자동 개설(또는 관리자 승인, 설정 선택) | 신청 → 관리자 승인 | 계약 → 본사가 개설 |
| 비용(예) | 무료 또는 월 이용료 | 월 이용료 또는 수수료 인상 | 개설비 + 월 이용료 |
| 난이도 | 낮음 | 중간 | 높음 |

---

## 3. 전체 구조

```text
                 ┌──────────────── 플랫폼 본사 (최고 관리자) ────────────────┐
                 │ 분양 사이트 개설·정지, 요금, 도메인·보안 인증서, 전체 모니터링 │
                 └─────────────┬──────────────────────────────┬─────────────┘
                               ▼                              ▼
              사이트 1: 소개뱅크 (tenant_id=1)        사이트 2,3…: C 분양 업체
              ├─ 소개뱅크 몰  segebank.co.kr           ├─ 업체 몰    abcmall.com
              ├─ 오피스 / 판매자센터 / 관리자           ├─ 업체 관리자 (회원·상품·주문 따로)
              ├─ A 회원 개인몰  kim01.segebank.co.kr   └─ (원하면 업체 안에서도 A·B 분양 가능)
              └─ B 판매자 독립몰 greenfood.segebank.co.kr

   접속 주소 → [사이트 찾기] → tenant_id + storefront_id 결정 → 같은 프로그램이 다른 화면·데이터를 보여 줌
```

### 3-1. 주소로 사이트 찾는 순서

1. 들어온 주소(예: `kim01.segebank.co.kr`)를 읽습니다.
2. `domains` 표에서 찾습니다. 자기 도메인이 연결돼 있으면 여기서 찾아집니다.
3. 없으면 하위 주소 규칙(`*.segebank.co.kr`)으로 `storefronts.slug = 'kim01'`을 찾습니다.
4. 정지되었거나 없는 사이트면 안내 화면을 보여 줍니다.
5. 결과(tenant_id, storefront_id, 디자인 설정)를 1분 동안 저장해 두고 다시 씁니다.

```js
// 예시: 요청마다 어느 사이트인지 결정
async function resolveSite(host) {
  const cached = cache.get(host); if (cached) return cached;
  let site = await db.oneOrNone(
    `SELECT d.tenant_id, d.storefront_id FROM domains d WHERE d.host=$1 AND d.status='ACTIVE'`, [host]);
  if (!site) {
    const m = host.match(/^([a-z0-9-]{3,20})\.segebank\.co\.kr$/);
    if (m) site = await db.oneOrNone(
      `SELECT tenant_id, id AS storefront_id FROM storefronts WHERE slug=$1 AND status='OPEN'`, [m[1]]);
  }
  if (!site && host === 'segebank.co.kr') site = { tenant_id: 1, storefront_id: null };
  cache.set(host, site, 60);
  return site; // null이면 "없는 사이트" 화면
}
```

---

## 4. A. 회원 개인몰 상세

### 4-1. 흐름

```text
오피스 > 내 쇼핑몰 만들기
  → 주소 정하기 (kim01, 중복·금칙어 검사)
  → 몰 이름·소개글·프로필 사진
  → 디자인 틀 선택 (3종)
  → 진열할 상품 고르기 (전체 자동 진열 / 직접 고르기)
  → 개설 (자동 또는 관리자 승인)
  → 공유: 링크·QR·카카오톡
```

### 4-2. 규칙

| 항목 | 규칙 |
|---|---|
| 개설 자격 | 판매원 등록 완료 + 본인인증 + (선택) 직급 [ ] 이상 |
| 주소 | 영문 소문자·숫자·하이픈 3~20자. 금칙어(admin, www, mail, 욕설, 다른 브랜드명) 차단. 변경은 30일에 1번 |
| 가격 | **본사 판매가 그대로**. 개인몰 주인이 가격을 바꿀 수 없음(가격 질서·법 문제 방지) |
| 주문 | 결제·배송·고객센터는 소개뱅크가 처리. 주문에 `storefront_id` 기록 |
| 추천 연결 | 개인몰에서 가입한 사람은 추천인이 개인몰 주인으로 **자동 지정**(수정 불가). 비회원 구매도 개인몰 실적으로 기록 |
| 실적·수당 | 개인몰 매출은 주인의 판매 실적. 수당은 **수당규정서에 정한 대로만** 지급(별도 "몰 수당"을 만들면 35% 한도 계산에 포함) |
| 화면 하단 표시 | "운영: 소개뱅크(사업자 정보) / 이 몰은 소개뱅크 회원 ○○○의 추천몰입니다" (전자상거래법 표시 의무 확인 필요) |
| 정지 | 회원 정지·탈퇴 시 자동 정지. 허위·과장 광고 신고 시 관리자가 정지 |

### 4-3. 개인몰 주인이 꾸밀 수 있는 것

| 꾸미기 | 가능 | 불가 |
|---|---|---|
| 몰 이름, 소개글, 프로필 사진, 대표 배너 3장 | ✔ | |
| 디자인 틀(3종), 대표 색 | ✔ | |
| 진열 상품, 진열 순서, "내가 추천하는 상품" 표시 | ✔ | |
| 가격, 상품 설명, 상품 사진 | | ✔ (본사 정보 그대로) |
| 수익 보장 문구 | | ✔ (금지어 자동 검사) |

---

## 5. B. 판매자 독립몰 상세

| 항목 | 규칙 |
|---|---|
| 신청 | 판매자센터 > 독립몰 신청 → 관리자 승인 |
| 상품 | 그 판매자의 상품만 자동 진열. 소개뱅크 몰에도 함께 노출할지 선택 |
| 디자인 | 틀 선택 + 로고, 색, 배너, 상단 메뉴, 공지 |
| 주문·정산 | 기존 판매자센터와 같음. 독립몰 주문은 **수수료율을 따로** 설정 가능(예: 몰 직접 유입 8%) |
| 회원 | 소개뱅크 공통 회원. 구매자는 소개뱅크 계정으로 로그인 |
| 주소 | 하위 주소 기본, 자기 도메인 연결(2단계) |

---

## 6. C. 솔루션 분양 상세

### 6-1. 개설 흐름

```text
분양 신청(상담) → 계약(요금제·사업자 확인) → 본사 최고관리자가 [분양 사이트 생성]
  → 자동 준비: tenant 생성, 업체 관리자 계정, 기본 카테고리·약관 틀, 하위 주소 발급
  → 업체 설정: 사업자 정보, PG(결제) 계약 정보, 디자인, 자기 도메인 연결
  → 본사 점검(체크리스트) → 오픈
```

### 6-2. 분리 원칙 (보안 핵심)

1. 모든 표에 `tenant_id`가 있고, **모든 조회에 자동으로 `tenant_id` 조건**이 붙습니다. 개발자가 빠뜨려도 막히도록 DB의 행 단위 보안 기능(PostgreSQL RLS)을 씁니다.
2. 업체 관리자는 자기 사이트 데이터만 볼 수 있습니다. 본사 최고관리자만 전체를 볼 수 있고, 볼 때마다 기록이 남습니다.
3. 결제는 **업체 자기 이름으로 PG와 계약**합니다. 소개뱅크가 대금을 거치지 않게 해서 전자금융 규제 위험을 줄입니다.
4. 업체별로 회원 아이디가 겹쳐도 됩니다(`tenant_id + login_id`로 구분).

### 6-3. 요금제 (예시, 실제 금액은 결정 필요)

| 요금제 | 포함 | 월 이용료(예) |
|---|---|---|
| 기본 | 몰 + 관리자, 하위 주소, 상품 1,000개 | [ ]원 |
| 표준 | + 자기 도메인, 판매자 입점(B) | [ ]원 |
| 프리미엄 | + 회원 개인몰(A), 추천·조직 기능, 전용 지원 | [ ]원 |

### 6-4. 계약·법적 주의 (확인 필요)

- 분양받은 업체가 쇼핑몰을 운영하는 **사업자**이고, 통신판매업 신고·약관·개인정보 책임을 집니다.
- 업체가 **추천·조직 기능(다단계 구조)**을 쓰려면 방문판매법 등록 증빙을 받고 나서 기능을 켭니다.
- 소개뱅크는 **개인정보 처리를 위탁받는 자(수탁자)**가 됩니다. 위탁 계약서와 보안 조치가 필요합니다.
- 계약서에 이용 정지 조건(불법 영업, 미납), 데이터 반환·삭제를 넣습니다.

---

## 7. 주소 방식 비교 (추천: 하위 주소 기본 + 자기 도메인은 2단계)

| 항목 | ① 하위 주소 `kim01.segebank.co.kr` | ② 경로 주소 `segebank.co.kr/shop/kim01` | ③ 자기 도메인 `kimshop.com` |
|---|---|---|---|
| 개설 속도 | 즉시 자동 | 즉시 자동 | 도메인 구입·연결 필요(수 시간~1일) |
| 독립 사이트 느낌 | 좋음 | 약함 | 가장 좋음 |
| 보안 인증서(HTTPS) | 와일드카드 인증서 1장으로 전체 해결 | 추가 없음 | 도메인마다 자동 발급 장치 필요 |
| 추가 비용 | 거의 없음 | 없음 | 인증서 자동 발급 서비스 비용(확인 필요) + 도메인비(받는 사람 부담) |
| 검색 노출 | 사이트별 따로 | 본사 사이트에 묶임 | 사이트별 따로 |
| 홈 화면 설치(PWA) | 사이트별 아이콘 가능 | 본사 아이콘 하나 | 사이트별 아이콘 가능 |
| 추천 | **기본으로 사용** | 사용 안 함 | **2단계, B·C 위주로 승인 후 제공** |

### 7-1. 하위 주소 구성

1. DNS에 `*.segebank.co.kr`을 서버로 연결합니다.
2. AWS 인증서 서비스(ACM)에서 `*.segebank.co.kr` 와일드카드 인증서를 받습니다(무료).
3. 로드밸런서(ALB)가 모든 하위 주소를 같은 서버로 보냅니다.

### 7-2. 자기 도메인 연결 (2단계)

1. 신청자가 자기 도메인에 `CNAME → shops.segebank.co.kr` 설정
2. 소개뱅크가 TXT 기록으로 도메인 소유를 확인
3. 인증서를 자동 발급 → 연결 완료

자동 발급 방법 후보는 Cloudflare for SaaS(Custom Hostnames) 또는 Caddy 서버의 자동 인증서입니다. 비용과 한도는 확인이 필요합니다.

---

## 8. 데이터 구조 추가 (PostgreSQL)

```sql
-- 분양 사이트(C) 단위. 소개뱅크 자신은 id=1
CREATE TABLE tenants (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,                 -- 업체명
  biz_no VARCHAR(12), plan VARCHAR(20) NOT NULL DEFAULT 'BASIC',
  features JSONB NOT NULL DEFAULT '{}',       -- {"referral":false,"seller":true,"member_shop":false}
  status VARCHAR(10) NOT NULL DEFAULT 'SETUP',-- SETUP / OPEN / SUSPENDED / CLOSED
  contract_from DATE, contract_to DATE, created_at TIMESTAMPTZ DEFAULT now()
);

-- 사이트 안의 분양몰(A 회원 개인몰, B 판매자 독립몰)
CREATE TABLE storefronts (
  id BIGSERIAL PRIMARY KEY,
  tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  type VARCHAR(10) NOT NULL,                  -- MEMBER / SELLER
  owner_user_id BIGINT REFERENCES users(id),  -- A: 회원
  seller_id BIGINT REFERENCES sellers(id),    -- B: 판매자
  slug VARCHAR(20) NOT NULL,                  -- 하위 주소 kim01
  title VARCHAR(50) NOT NULL, intro TEXT,
  theme JSONB NOT NULL DEFAULT '{}',          -- {"template":"basic","color":"#2457D6","logo":"…","banners":[…]}
  product_mode VARCHAR(10) DEFAULT 'ALL',     -- ALL(전체 자동) / PICK(직접 선택)
  commission_rate NUMERIC(5,2),               -- B 독립몰 별도 수수료
  status VARCHAR(10) NOT NULL DEFAULT 'PENDING', -- PENDING / OPEN / SUSPENDED / CLOSED
  slug_changed_at TIMESTAMPTZ, created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (tenant_id, slug)
);
CREATE TABLE storefront_products (
  storefront_id BIGINT REFERENCES storefronts(id), product_id BIGINT REFERENCES products(id),
  sort INT DEFAULT 0, featured BOOLEAN DEFAULT false, PRIMARY KEY (storefront_id, product_id)
);

-- 주소(하위 주소 외에 연결한 자기 도메인)
CREATE TABLE domains (
  host VARCHAR(253) PRIMARY KEY,
  tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  storefront_id BIGINT REFERENCES storefronts(id),
  verify_token VARCHAR(64), status VARCHAR(12) DEFAULT 'VERIFYING', -- VERIFYING/SSL_PENDING/ACTIVE/FAILED
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 요금(C, 그리고 유료 A·B)
CREATE TABLE subscriptions (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT, storefront_id BIGINT,
  plan VARCHAR(20), price INT, cycle VARCHAR(10), next_bill_date DATE, status VARCHAR(10)
);

-- 기존 표 변경
ALTER TABLE users     ADD COLUMN tenant_id BIGINT NOT NULL DEFAULT 1 REFERENCES tenants(id);
ALTER TABLE products  ADD COLUMN tenant_id BIGINT NOT NULL DEFAULT 1 REFERENCES tenants(id);
ALTER TABLE orders    ADD COLUMN tenant_id BIGINT NOT NULL DEFAULT 1 REFERENCES tenants(id),
                      ADD COLUMN storefront_id BIGINT REFERENCES storefronts(id);   -- 어느 분양몰에서 팔렸나
-- (sellers, members, categories, notices 등 모든 업무 표에 tenant_id 추가)

-- 행 단위 보안: 접속한 사이트의 데이터만 보이게
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON products USING (tenant_id = current_setting('app.tenant_id')::bigint);
```

---

## 9. 화면 추가 목록

| 영역 | ID | 화면 | 모바일 |
|---|---|---|---|
| 오피스 | OFF-20 | 내 쇼핑몰 만들기(5단계 마법사) | ✔ 주 사용 |
| | OFF-21 | 내 쇼핑몰 관리: 꾸미기, 진열 상품, 공유 | ✔ |
| | OFF-22 | 내 쇼핑몰 실적: 방문, 주문, 가입자 | ✔ |
| 분양몰(손님) | SF-01 | 분양몰 홈: 주인 소개 + 추천 상품 | ✔ |
| | SF-02 | 상품 상세·주문: 소개뱅크 몰과 같은 화면 + 분양몰 머리·꼬리말 | ✔ |
| 판매자센터 | SEL-20 | 독립몰 신청 · 상태 | ✔ |
| | SEL-21 | 독립몰 꾸미기(로고·색·메뉴) | PC 권장 |
| 소개뱅크 관리자 | ADM-20 | 분양몰 목록: A·B, 승인·정지 | 조회만 |
| | ADM-21 | 주소 금칙어, 자동 개설 설정 | |
| | ADM-22 | 분양몰 매출 순위·신고 처리 | |
| 플랫폼 본사 | PLT-01 | 분양 업체(C) 목록·개설·정지 | |
| | PLT-02 | 요금제·청구 | |
| | PLT-03 | 도메인·인증서 상태 | |
| C 업체 관리자 | — | 소개뱅크 관리자 화면과 같음(자기 데이터만) | |

---

## 10. 모바일 화면 설계

### 10-1. 내 쇼핑몰 만들기 (오피스, 휴대폰)

```text
① 주소 정하기
   [ kim01            ].segebank.co.kr
   ✔ 사용할 수 있는 주소입니다
② 몰 이름 [김민수의 건강한 장바구니] / 소개글 [ … ] / 사진 [📷]
③ 디자인 선택  [기본] [따뜻한] [깔끔한]  ← 미리보기 카드 좌우 넘김
④ 진열 방식  (●) 전체 상품 자동  ( ) 내가 고르기
⑤ [ 내 쇼핑몰 열기 ]
   → 완료: "kim01.segebank.co.kr" [링크 복사] [QR] [카카오 공유] [홈 화면에 추가]
```

### 10-2. 분양몰 홈 (손님이 보는 화면)

```text
┌──────────────────────────┐
│ 김민수의 건강한 장바구니 🛒 │ ← 분양몰 이름
├──────────────────────────┤
│ (사진) 안녕하세요, 김민수입니다│
│ 직접 써 본 좋은 상품만 골랐어요│
├──────────────────────────┤
│ ★ 내가 추천하는 상품        │
│ [상품][상품]               │
│ 전체 상품                  │
│ [상품][상품] …             │
├──────────────────────────┤
│ 운영: 소개뱅크(사업자정보)    │
│ 이 몰은 회원 김민수의 추천몰   │ ← 하단 표시
└──────────────────────────┘
```

### 10-3. 내 쇼핑몰 관리 (휴대폰)

```text
오늘 방문 32 · 주문 2 · 새 가입 1
[꾸미기] [진열 상품] [공유하기] [실적 보기]
진열 상품: 상품마다 [보이기 ⬤] [★추천] 끌어서 순서 바꾸기
```

---

## 11. 단계별 계획 (설계 → 개발, 추정)

| 단계 | 내용 | 설계 | 개발(추후) |
|---|---|---|---|
| 0 | **멀티 사이트 기초**(tenant_id, 주소로 사이트 찾기, RLS) | 1주 | 본개발 1단계에 포함 |
| 1 | **A 회원 개인몰**(하위 주소, 만들기·관리·공유, 추천 연결) | 1주 | 2~3주 |
| 2 | **B 판매자 독립몰** + 자기 도메인 연결 | 1주 | 2주 |
| 3 | **C 솔루션 분양**(본사 화면, 요금, 개설 자동화, 계약) | 2주 | 4~6주 |

계획서([PLAN.md](PLAN.md))의 설계 일정에서 **3~4주차에 분양 설계를 함께** 진행합니다.

---

## 12. 예상 비용·자원 (확인 필요)

| 항목 | 예상 | 비고 |
|---|---|---|
| 와일드카드 인증서(ACM) | 무료 | AWS 로드밸런서 사용 시 |
| 로드밸런서(ALB) | 월 약 2~3만 원 + 사용량 | 서울 리전, 확인 필요 |
| 자기 도메인 자동 인증서 | 무료~유료 | Cloudflare for SaaS 등. 요금과 한도 확인 필요 |
| 분양 사이트별 추가 서버 | 없음(같은 서버 공유) | 사이트가 많아지면 서버 증설 |
| 법률 검토 | 별도 | 분양 계약서, 개인정보 위탁, 다단계 기능 허용 조건 |

---

## 13. 발생할 수 있는 문제와 해결

| 문제 | 해결 |
|---|---|
| 다른 사이트 데이터가 섞여 보임 | 모든 조회에 tenant_id + DB 행 단위 보안(RLS) + 자동 테스트 |
| 개인몰 주인이 과장 광고("월 300만 원 보장") | 소개글 금지어 검사, 신고 버튼, 관리자 정지 |
| 같은 주소를 서로 원함 / 유명 브랜드 이름 | 먼저 신청한 사람 우선, 금칙어·상표 목록, 관리자 회수 권한 |
| 개인몰 가격을 마음대로 바꿔 덤핑 | 가격 변경 기능 없음 |
| 자기 도메인 인증서 발급 실패 | 상태 화면에 원인 표시(CNAME 미설정 등), 하위 주소로 계속 운영 |
| C 업체가 무등록 다단계 운영 | 추천·조직 기능은 등록 증빙 확인 후 본사가 켜 줌 |
| 분양몰이 수천 개로 늘어 느려짐 | 사이트 정보 캐시, 이미지 CDN, 서버 자동 증설 |

---

## 14. 결정해야 할 것 (체크리스트)

- [ ] A 회원 개인몰: **자동 개설** / 관리자 승인 후 개설
- [ ] A 개설 자격(직급 조건 여부), 이용료(무료 / 유료)
- [ ] A 개인몰에서 비회원 구매도 주인 실적으로 인정할지
- [ ] B 독립몰 수수료를 따로 둘지(예: 8%)
- [ ] 자기 도메인 연결을 누구에게 줄지(B·C만 / A도 유료로)
- [ ] C 요금제 3종의 금액과 포함 기능
- [ ] 디자인 틀 3종의 분위기
- [ ] 금칙어 목록

## 15. 다음에 바로 할 일

1. 위 체크리스트 중 **A 관련 4개**부터 정해 주세요.
2. 정해 주시면 **A 회원 개인몰의 휴대폰 화면 시안**(만들기 마법사, 분양몰 홈, 관리)을 그림으로 만들겠습니다. 이번에도 개발은 하지 않고 시안만 만듭니다.
