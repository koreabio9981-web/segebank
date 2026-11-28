-- 001_core: docs/dev/schema.sql 에서 분리
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
