-- 005_points: docs/dev/schema.sql 에서 분리
-- ========== 유료회원·포인트 ==========
CREATE TABLE membership_plans (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  code VARCHAR(20) NOT NULL, version INT NOT NULL, name TEXT NOT NULL,
  price BIGINT NOT NULL, points BIGINT NOT NULL, bonus_rate NUMERIC(7,4) NOT NULL DEFAULT 0 CHECK (bonus_rate <= 0.10),
  member_discount NUMERIC(7,4), charge_valid_months INT NOT NULL DEFAULT 60,      -- 충전 포인트: 5년(월 초기화 없음, 환불 가능)
  free_points_expiry VARCHAR(16) NOT NULL DEFAULT 'END_OF_MONTH',  -- 보너스·적립금·이벤트: 지급한 달 말일 소멸
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
