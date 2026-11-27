-- 004_orders_settlement: docs/dev/schema.sql 에서 분리
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
  paid_bonus_points BIGINT NOT NULL DEFAULT 0,      -- 수당 포인트 결제액(원천징수 별도 기록)
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
