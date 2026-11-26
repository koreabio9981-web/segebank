-- 소개뱅크 통합 DB 스키마 초안 (PostgreSQL 16) — docs/dev/TECH_SPEC.md 4장
-- 금액 BIGINT(원), 비율 NUMERIC(7,4), 모든 업무 표 tenant_id + RLS, 원장 표는 추가 전용
CREATE EXTENSION IF NOT EXISTS ltree;
CREATE EXTENSION IF NOT EXISTS citext;

-- ========== 사이트(분양) ==========
CREATE TABLE tenants (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL, biz_no VARCHAR(12),
  plan VARCHAR(20) NOT NULL DEFAULT 'BASIC',
  features JSONB NOT NULL DEFAULT '{"mlm":false,"seller":true,"member_shop":false,"points":false}',
  status VARCHAR(10) NOT NULL DEFAULT 'SETUP' CHECK (status IN ('SETUP','OPEN','SUSPENDED','CLOSED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE settings (
  tenant_id BIGINT NOT NULL REFERENCES tenants(id), key TEXT NOT NULL, value JSONB NOT NULL,
  updated_by BIGINT, updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (tenant_id, key)
);

-- ========== 사용자·동의·감사 ==========
CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  login_id CITEXT NOT NULL, password_hash TEXT NOT NULL,
  name TEXT NOT NULL, phone VARCHAR(20), email CITEXT, birth DATE,
  ci CHAR(88), di CHAR(64),                       -- 본인확인 결과
  roles TEXT[] NOT NULL DEFAULT '{member}',       -- member / distributor / seller / admin / platform_admin(분양 전체)
  mfa_secret_enc BYTEA,
  status VARCHAR(10) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','LOCKED','SUSPENDED','LEFT')),
  failed_logins SMALLINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), left_at TIMESTAMPTZ,
  UNIQUE (tenant_id, login_id)
);
CREATE UNIQUE INDEX users_ci_uq ON users (tenant_id, ci) WHERE ci IS NOT NULL AND status <> 'LEFT';
CREATE TABLE terms_versions (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  kind VARCHAR(20) NOT NULL,    -- SERVICE/DISTRIBUTOR/SELLER/PRIVACY/PRIVACY_COLLECT/MARKETING/BONUS_RULES
  version VARCHAR(10) NOT NULL, body TEXT NOT NULL, effective_from TIMESTAMPTZ NOT NULL,
  UNIQUE (tenant_id, kind, version)
);
CREATE TABLE consents (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  user_id BIGINT NOT NULL REFERENCES users(id), terms_id BIGINT NOT NULL REFERENCES terms_versions(id),
  agreed BOOLEAN NOT NULL, ip INET, user_agent TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  actor_id BIGINT, action VARCHAR(60) NOT NULL, target_type VARCHAR(30), target_id BIGINT,
  before JSONB, after JSONB, ip INET, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE policy_unlocks (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  kind VARCHAR(30) NOT NULL CHECK (kind IN ('MEMBERSHIP_MODE2','MARKETPLACE_PV','MARKETPLACE_POINTS','MEMBER_TRANSFER')),
  evidence_file TEXT, registration_no VARCHAR(40),
  approved_by BIGINT NOT NULL REFERENCES users(id), effective_from TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========== 판매원(조직) ==========
CREATE TABLE members (
  user_id BIGINT PRIMARY KEY REFERENCES users(id), tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  distributor_no VARCHAR(20),                     -- 판매원 등록번호 (NULL = 일반 회원)
  registered_at TIMESTAMPTZ,
  referrer_id BIGINT REFERENCES members(user_id), -- 추천인 (직추천·롤업 기준)
  referrer_path LTREE,                            -- 추천 경로
  placement_parent BIGINT REFERENCES members(user_id), -- 후원인 (바이너리 좌·우 배치 기준)
  placement_side CHAR(1) CHECK (placement_side IN ('L','R')),
  placement_path LTREE,                           -- 후원(바이너리) 경로
  rank VARCHAR(12) NOT NULL DEFAULT 'MEMBER' CHECK (rank IN ('MEMBER','SILVER','GOLD','PLATINUM','DIAMOND')),
  cum_weak_pv BIGINT NOT NULL DEFAULT 0,
  bank_name VARCHAR(30), bank_account_enc BYTEA, bank_holder TEXT, bank_verified_at TIMESTAMPTZ,
  disqualify_checked JSONB, left_at TIMESTAMPTZ,
  UNIQUE (tenant_id, distributor_no),
  UNIQUE (placement_parent, placement_side)
);
CREATE INDEX members_referrer_path_gist ON members USING GIST (referrer_path);
CREATE INDEX members_placement_path_gist ON members USING GIST (placement_path);
CREATE TABLE rank_history (                       -- 월별 직급·수당 자격 이력 (직급 하락 없음, 소멸·압축 판단용)
  user_id BIGINT NOT NULL REFERENCES members(user_id), month DATE NOT NULL,
  rank VARCHAR(12) NOT NULL CHECK (rank IN ('MEMBER','SILVER','GOLD','PLATINUM','DIAMOND')),
  cum_weak_pv BIGINT NOT NULL, qualifying_pv BIGINT NOT NULL,   -- 본인 + 개인몰 소비자 PV
  qualified BOOLEAN NOT NULL, detail JSONB, PRIMARY KEY (user_id, month)
);
CREATE TABLE distributor_tax_ids (                -- 주민등록번호: 수당 지급 대상만, 첫 지급 전 1회, 별도 표·암호화
  user_id BIGINT PRIMARY KEY REFERENCES members(user_id), tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  rrn_enc BYTEA NOT NULL, key_id TEXT NOT NULL, collected_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE sensitive_access_logs (              -- 주민번호·계좌번호 열람 기록
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  actor_id BIGINT NOT NULL, subject_user_id BIGINT NOT NULL, field VARCHAR(20) NOT NULL, purpose TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========== 판매자 ==========
CREATE TABLE sellers (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  user_id BIGINT NOT NULL REFERENCES users(id),
  company TEXT NOT NULL, ceo TEXT NOT NULL, biz_no VARCHAR(12) NOT NULL, mail_order_no TEXT NOT NULL,
  phone VARCHAR(20), email CITEXT,
  bank_name VARCHAR(30), bank_account_enc BYTEA, bank_holder TEXT,
  default_sales_mode VARCHAR(12) NOT NULL DEFAULT 'CONSIGN' CHECK (default_sales_mode IN ('DIRECT_BUY','CONSIGN','MARKETPLACE')),
  commission_rate NUMERIC(7,4), settle_cycle VARCHAR(10) NOT NULL DEFAULT 'SEMIMONTHLY',
  status VARCHAR(10) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPROVED','REJECTED','SUSPENDED')),
  reason TEXT, applied_at TIMESTAMPTZ NOT NULL DEFAULT now(), decided_at TIMESTAMPTZ, decided_by BIGINT,
  UNIQUE (tenant_id, biz_no), UNIQUE (tenant_id, user_id)
);
CREATE TABLE seller_documents (
  id BIGSERIAL PRIMARY KEY, seller_id BIGINT NOT NULL REFERENCES sellers(id),
  kind VARCHAR(20) NOT NULL, file_key TEXT NOT NULL, uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========== 상품 ==========
CREATE TABLE categories (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  name TEXT NOT NULL, sort INT NOT NULL DEFAULT 0, UNIQUE (tenant_id, name)
);
CREATE TABLE products (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  seller_id BIGINT REFERENCES sellers(id),        -- NULL = 본사 직접 상품
  seller_code VARCHAR(50), category_id BIGINT NOT NULL REFERENCES categories(id),
  name VARCHAR(60) NOT NULL, price BIGINT NOT NULL CHECK (price > 0), list_price BIGINT,
  stock INT NOT NULL DEFAULT 0, ship_fee BIGINT NOT NULL DEFAULT 0, description TEXT, notice_info JSONB,
  sales_mode VARCHAR(12) NOT NULL DEFAULT 'CONSIGN' CHECK (sales_mode IN ('DIRECT_BUY','CONSIGN','MARKETPLACE')),
  pv BIGINT NOT NULL DEFAULT 0,                  -- 시스템 계산: 공급가(부가세 제외) × pv_ratio(0.70). 판매자 입력 불가, 관리자 예외만
  pv_override BOOLEAN NOT NULL DEFAULT false, pv_eligible BOOLEAN NOT NULL DEFAULT true,
  point_payable BOOLEAN NOT NULL DEFAULT false, mutual_aid BOOLEAN NOT NULL DEFAULT true,
  status VARCHAR(12) NOT NULL DEFAULT 'ON_SALE' CHECK (status IN ('ON_SALE','SOLD_OUT','HIDDEN','BLOCKED','REVIEW')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (seller_id, seller_code)
);
CREATE TABLE product_options (
  id BIGSERIAL PRIMARY KEY, product_id BIGINT NOT NULL REFERENCES products(id),
  name TEXT NOT NULL, value TEXT NOT NULL, extra_price BIGINT NOT NULL DEFAULT 0, stock INT
);
CREATE TABLE product_images (
  id BIGSERIAL PRIMARY KEY, product_id BIGINT NOT NULL REFERENCES products(id), file_key TEXT NOT NULL, sort INT NOT NULL DEFAULT 0
);
CREATE TABLE bulk_jobs (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  seller_id BIGINT NOT NULL REFERENCES sellers(id), file_key TEXT NOT NULL, file_hash CHAR(64) NOT NULL,
  status VARCHAR(10) NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','CHECKING','CHECKED','COMMITTED','FAILED')),
  total INT, ok_count INT, err_count INT, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE bulk_job_rows (
  job_id BIGINT NOT NULL REFERENCES bulk_jobs(id), line_no INT NOT NULL,
  data JSONB NOT NULL, errors TEXT[] NOT NULL DEFAULT '{}', product_id BIGINT REFERENCES products(id),
  PRIMARY KEY (job_id, line_no)
);

-- ========== 분양몰 ==========
CREATE TABLE storefronts (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  type VARCHAR(10) NOT NULL CHECK (type IN ('MEMBER','SELLER')),
  owner_user_id BIGINT REFERENCES users(id), seller_id BIGINT REFERENCES sellers(id),
  slug VARCHAR(20) NOT NULL CHECK (slug ~ '^[a-z0-9]([a-z0-9-]{1,18})[a-z0-9]$'),
  title VARCHAR(50) NOT NULL, intro VARCHAR(200), theme JSONB NOT NULL DEFAULT '{}',
  product_mode VARCHAR(6) NOT NULL DEFAULT 'ALL' CHECK (product_mode IN ('ALL','PICK')),
  status VARCHAR(10) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('PENDING','OPEN','SUSPENDED','CLOSED')),
  slug_changed_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, slug)
);
CREATE TABLE storefront_products (
  storefront_id BIGINT NOT NULL REFERENCES storefronts(id), product_id BIGINT NOT NULL REFERENCES products(id),
  visible BOOLEAN NOT NULL DEFAULT true, featured BOOLEAN NOT NULL DEFAULT false, sort INT NOT NULL DEFAULT 0,
  PRIMARY KEY (storefront_id, product_id)
);
CREATE TABLE domains (
  host VARCHAR(253) PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  storefront_id BIGINT REFERENCES storefronts(id), verify_token VARCHAR(64),
  status VARCHAR(12) NOT NULL DEFAULT 'VERIFYING' CHECK (status IN ('VERIFYING','SSL_PENDING','ACTIVE','FAILED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========== 주문·결제·배송 ==========
CREATE TABLE carts (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  user_id BIGINT REFERENCES users(id), guest_token VARCHAR(64),
  product_id BIGINT NOT NULL REFERENCES products(id), option_id BIGINT REFERENCES product_options(id),
  qty INT NOT NULL CHECK (qty > 0), added_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE orders (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  order_no VARCHAR(20) NOT NULL, buyer_id BIGINT REFERENCES users(id),
  guest_name TEXT, guest_phone VARCHAR(20), guest_pw_hash TEXT,  -- 비회원 주문(조회용 비밀번호)
  storefront_id BIGINT REFERENCES storefronts(id),-- 어느 분양몰에서 팔렸나
  ref_member_id BIGINT REFERENCES members(user_id),-- 실적 귀속: 비회원·소비자 구매는 개인몰 주인 PV로 귀속(기준서 v0.3.1)
  items_total BIGINT NOT NULL, ship_total BIGINT NOT NULL, paid_cash BIGINT NOT NULL DEFAULT 0, paid_points BIGINT NOT NULL DEFAULT 0,
  receiver JSONB NOT NULL, status VARCHAR(12) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PAID','PARTIAL','CANCELLED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE (tenant_id, order_no)
);
CREATE TABLE order_items (
  id BIGSERIAL PRIMARY KEY, order_id BIGINT NOT NULL REFERENCES orders(id),
  product_id BIGINT NOT NULL REFERENCES products(id), seller_id BIGINT REFERENCES sellers(id),
  name_snapshot VARCHAR(60) NOT NULL, option_snapshot TEXT, price BIGINT NOT NULL, qty INT NOT NULL,
  sales_mode VARCHAR(12) NOT NULL, supply_amount BIGINT NOT NULL,   -- 할인 후 실결제 공급가(부가세 제외)
  pv BIGINT NOT NULL,                             -- supply_amount × pv_ratio (할인 후 기준)
  pv_eligible BOOLEAN NOT NULL, mutual_aid BOOLEAN NOT NULL, paid_points BIGINT NOT NULL DEFAULT 0,
  status VARCHAR(16) NOT NULL DEFAULT 'PAID' CHECK (status IN ('PAID','PREPARING','SHIPPING','DELIVERED','CONFIRMED','CANCELLED','RETURN_REQUESTED','RETURNED')),
  courier VARCHAR(20), tracking_no VARCHAR(40), delivered_at TIMESTAMPTZ, confirmed_at TIMESTAMPTZ
);
CREATE INDEX order_items_confirmed_idx ON order_items (confirmed_at) WHERE status = 'CONFIRMED';
CREATE TABLE payments (
  id BIGSERIAL PRIMARY KEY, order_id BIGINT NOT NULL REFERENCES orders(id),
  provider VARCHAR(20) NOT NULL, method VARCHAR(20) NOT NULL, amount BIGINT NOT NULL,
  pg_tid VARCHAR(100), status VARCHAR(12) NOT NULL CHECK (status IN ('READY','APPROVED','CANCELLED','PARTIAL_CANCELLED','FAILED')),
  raw JSONB, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE refunds (
  id BIGSERIAL PRIMARY KEY, order_item_id BIGINT NOT NULL REFERENCES order_items(id),
  cash BIGINT NOT NULL DEFAULT 0, points BIGINT NOT NULL DEFAULT 0, reason TEXT, pg_tid VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE mutual_aid_records (
  id BIGSERIAL PRIMARY KEY, order_id BIGINT NOT NULL REFERENCES orders(id),
  covered_amount BIGINT NOT NULL,                 -- 공제 대상 금액 = order_items 중 mutual_aid 상품 합계
  aid_no VARCHAR(40), status VARCHAR(12) NOT NULL CHECK (status IN ('REQUESTED','ISSUED','CANCELLED','FAILED')),
  attempts SMALLINT NOT NULL DEFAULT 0, raw JSONB, updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========== 판매자 정산 ==========
CREATE TABLE settlements (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  seller_id BIGINT NOT NULL REFERENCES sellers(id), period_from DATE NOT NULL, period_to DATE NOT NULL,
  gross BIGINT NOT NULL, commission BIGINT NOT NULL, adjustments BIGINT NOT NULL DEFAULT 0, net BIGINT NOT NULL,
  status VARCHAR(10) NOT NULL DEFAULT 'CALCULATED' CHECK (status IN ('CALCULATED','CONFIRMED','PAID')),
  UNIQUE (seller_id, period_from)
);
CREATE TABLE settlement_items (
  settlement_id BIGINT NOT NULL REFERENCES settlements(id), order_item_id BIGINT NOT NULL REFERENCES order_items(id),
  amount BIGINT NOT NULL, commission BIGINT NOT NULL, PRIMARY KEY (settlement_id, order_item_id)
);

-- ========== 유료회원·포인트 ==========
CREATE TABLE membership_plans (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  code VARCHAR(20) NOT NULL, version INT NOT NULL, name TEXT NOT NULL,
  price BIGINT NOT NULL, points BIGINT NOT NULL, bonus_rate NUMERIC(7,4) NOT NULL DEFAULT 0 CHECK (bonus_rate <= 0.10),
  member_discount NUMERIC(7,4), charge_valid_months INT NOT NULL DEFAULT 60, bonus_valid_months INT NOT NULL DEFAULT 12,
  grant_rank VARCHAR(12), effective_from TIMESTAMPTZ NOT NULL,
  status VARCHAR(10) NOT NULL DEFAULT 'SCHEDULED' CHECK (status IN ('SCHEDULED','ACTIVE','RETIRED')),
  UNIQUE (tenant_id, code, version)
);
CREATE TABLE memberships (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  user_id BIGINT NOT NULL REFERENCES users(id), plan_id BIGINT NOT NULL REFERENCES membership_plans(id),
  charge_order_id BIGINT REFERENCES orders(id),
  status VARCHAR(10) NOT NULL CHECK (status IN ('ACTIVE','REFUNDED')), started_at TIMESTAMPTZ NOT NULL DEFAULT now(), ended_at TIMESTAMPTZ
);
CREATE TABLE point_lots (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  user_id BIGINT NOT NULL REFERENCES users(id),
  kind VARCHAR(8) NOT NULL CHECK (kind IN ('CHARGE','BONUS','REWARD')),
  amount BIGINT NOT NULL CHECK (amount > 0), remaining BIGINT NOT NULL CHECK (remaining >= 0),
  refundable BOOLEAN NOT NULL, source_order_id BIGINT REFERENCES orders(id),
  expires_at TIMESTAMPTZ NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (remaining <= amount), CHECK (refundable = (kind = 'CHARGE'))
);
CREATE TABLE point_tx (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  lot_id BIGINT NOT NULL REFERENCES point_lots(id), user_id BIGINT NOT NULL REFERENCES users(id),
  kind VARCHAR(8) NOT NULL CHECK (kind IN ('ISSUE','USE','RESTORE','REFUND','EXPIRE','ADJUST')),
  amount BIGINT NOT NULL, order_id BIGINT REFERENCES orders(id), memo TEXT, created_by BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========== 수당 ==========
CREATE TABLE bonus_plans (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  version VARCHAR(10) NOT NULL, rules JSONB NOT NULL,      -- BONUS_RULES_V0.3 부록 A 형식
  effective_from DATE NOT NULL, notified_at TIMESTAMPTZ, approved_by BIGINT,
  status VARCHAR(10) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','SCHEDULED','ACTIVE','RETIRED')),
  UNIQUE (tenant_id, version),
  CHECK (notified_at IS NULL OR effective_from >= (notified_at + INTERVAL '3 months')::date)
);
CREATE TABLE bonus_runs (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  plan_id BIGINT NOT NULL REFERENCES bonus_plans(id), kind VARCHAR(8) NOT NULL CHECK (kind IN ('WEEKLY','MONTHLY')),
  period_from DATE NOT NULL, period_to DATE NOT NULL,
  net_sales BIGINT, payout_before BIGINT, ratio_before NUMERIC(7,4), scale NUMERIC(7,4), payout_after BIGINT,
  status VARCHAR(10) NOT NULL DEFAULT 'CALCULATED' CHECK (status IN ('CALCULATED','REVIEWED','CONFIRMED','PAID')),
  reviewed_by BIGINT, confirmed_by BIGINT, confirmed_at TIMESTAMPTZ,
  UNIQUE (tenant_id, kind, period_from)
);
CREATE TABLE bonus_items (
  id BIGSERIAL PRIMARY KEY, run_id BIGINT NOT NULL REFERENCES bonus_runs(id),
  user_id BIGINT NOT NULL REFERENCES members(user_id),
  type VARCHAR(10) NOT NULL CHECK (type IN ('DIRECT','BINARY','ROLLUP','RANK_POOL','CLAWBACK')),
  source_order_item BIGINT REFERENCES order_items(id), generation SMALLINT,
  pv BIGINT, amount_before BIGINT NOT NULL, amount BIGINT NOT NULL, clawback_of BIGINT REFERENCES bonus_items(id)
);
CREATE INDEX bonus_items_user_idx ON bonus_items (user_id, run_id);
CREATE TABLE binary_volume (
  user_id BIGINT NOT NULL REFERENCES members(user_id), period_from DATE NOT NULL,
  left_new BIGINT NOT NULL DEFAULT 0, right_new BIGINT NOT NULL DEFAULT 0,
  left_carry BIGINT NOT NULL DEFAULT 0, right_carry BIGINT NOT NULL DEFAULT 0,
  matched BIGINT NOT NULL DEFAULT 0, paid BIGINT NOT NULL DEFAULT 0, capped BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (user_id, period_from)
);
CREATE TABLE binary_carry_lots (                   -- 이월 실적 묶음: 먼저 쌓인 것부터 소멸(6개월), 자격 없음 3개월 연속 시 전부 소멸
  id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES members(user_id),
  side CHAR(1) NOT NULL CHECK (side IN ('L','R')), origin_period DATE NOT NULL,
  amount BIGINT NOT NULL CHECK (amount >= 0), remaining BIGINT NOT NULL CHECK (remaining >= 0),
  expires_on DATE NOT NULL, flushed_at TIMESTAMPTZ, flush_reason VARCHAR(20)
);
CREATE INDEX binary_carry_lots_open ON binary_carry_lots (user_id, side, origin_period) WHERE remaining > 0;

-- ========== 수당 지갑·출금 ==========
CREATE TABLE earnings_ledger (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  user_id BIGINT NOT NULL REFERENCES members(user_id),
  kind VARCHAR(12) NOT NULL CHECK (kind IN ('BONUS','CLAWBACK','WITHHOLDING','PAYOUT','PAYOUT_FAIL','ADJUST')),
  amount BIGINT NOT NULL, ref_type VARCHAR(20), ref_id BIGINT, memo TEXT, created_by BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX earnings_ledger_user_idx ON earnings_ledger (user_id, created_at);
CREATE TABLE payout_batches (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  kind VARCHAR(10) NOT NULL CHECK (kind IN ('BONUS','SETTLEMENT')), total BIGINT NOT NULL, count INT NOT NULL,
  approved_by_1 BIGINT, approved_by_2 BIGINT, file_key TEXT,
  status VARCHAR(10) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','APPROVED','SENT','DONE','PARTIAL')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (approved_by_2 IS NULL OR approved_by_1 <> approved_by_2)
);
CREATE TABLE payout_items (                       -- 지급일 자동 지급(기준서 제12조): 신청 없이 확정 수당을 배치로 이체
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  batch_id BIGINT NOT NULL REFERENCES payout_batches(id), user_id BIGINT NOT NULL REFERENCES members(user_id),
  gross BIGINT NOT NULL, withholding BIGINT NOT NULL, net BIGINT NOT NULL CHECK (net >= 0),
  status VARCHAR(10) NOT NULL DEFAULT 'READY' CHECK (status IN ('READY','HELD','PAID','FAILED','CARRIED')),
  hold_reason VARCHAR(30),                        -- NO_TAX_ID / NO_BANK / BELOW_MIN / BANK_FAIL
  processed_at TIMESTAMPTZ
);

-- ========== 게시판·알림 ==========
CREATE TABLE notices (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  audience VARCHAR(12) NOT NULL DEFAULT 'ALL' CHECK (audience IN ('ALL','MEMBER','DISTRIBUTOR','SELLER')),
  title TEXT NOT NULL, body TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE inquiries (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  user_id BIGINT REFERENCES users(id), target VARCHAR(8) NOT NULL CHECK (target IN ('ADMIN','SELLER')),
  seller_id BIGINT REFERENCES sellers(id), product_id BIGINT REFERENCES products(id),
  title TEXT NOT NULL, body TEXT, answer TEXT, status VARCHAR(10) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','ANSWERED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE notifications (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  user_id BIGINT REFERENCES users(id), channel VARCHAR(10) NOT NULL CHECK (channel IN ('ALIMTALK','SMS','EMAIL','PUSH')),
  template VARCHAR(40) NOT NULL, payload JSONB, legal BOOLEAN NOT NULL DEFAULT false,  -- 법정 통지(규정 변경 등)
  status VARCHAR(10) NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','SENT','FAILED','FALLBACK')),
  sent_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========== 35% 감시 뷰 ==========
CREATE VIEW bonus_cap_yearly AS
SELECT r.tenant_id, date_trunc('year', r.period_from)::date AS year,
       SUM(r.payout_after) AS payout, SUM(r.net_sales) AS net_sales,
       CASE WHEN SUM(r.net_sales) > 0 THEN SUM(r.payout_after)::numeric / SUM(r.net_sales) END AS ratio
FROM bonus_runs r WHERE r.status IN ('CONFIRMED','PAID') GROUP BY 1, 2;

-- ========== 행 단위 보안 (예: 모든 tenant 표에 같은 정책) ==========
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['settings','users','terms_versions','consents','audit_logs','policy_unlocks','members','sellers',
    'categories','products','bulk_jobs','storefronts','domains','carts','orders','settlements','membership_plans',
    'point_lots','point_tx','bonus_plans','bonus_runs','earnings_ledger','payout_batches','payout_items','notices','inquiries','notifications','distributor_tax_ids','sensitive_access_logs','memberships']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY tenant_isolation ON %I USING (tenant_id = current_setting(''app.tenant_id'', true)::bigint)', t);
  END LOOP;
END $$;
