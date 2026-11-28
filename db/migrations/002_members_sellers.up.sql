-- 002_members_sellers: docs/dev/schema.sql 에서 분리
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
