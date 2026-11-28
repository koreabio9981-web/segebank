-- 003_catalog_storefront: docs/dev/schema.sql 에서 분리
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
