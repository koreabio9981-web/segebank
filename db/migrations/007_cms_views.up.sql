-- 007_cms_views: docs/dev/schema.sql 에서 분리
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
FROM bonus_runs r WHERE r.kind = 'DAILY' AND r.status IN ('CONFIRMED','PAID') GROUP BY 1, 2;
