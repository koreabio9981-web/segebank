-- 006_bonus_wallet: docs/dev/schema.sql 에서 분리
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
  plan_id BIGINT NOT NULL REFERENCES bonus_plans(id),
  kind VARCHAR(16) NOT NULL CHECK (kind IN ('DAILY','MONTHLY_TRUEUP')),   -- 기준서 v0.4: 일간 정산 + 월말 확정
  reserve_rate NUMERIC(7,4) NOT NULL DEFAULT 0.10,
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
CREATE TABLE bonus_estimates (                    -- 실시간 예상 수당(결제 즉시 표시, 잔액 아님)
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  order_item_id BIGINT NOT NULL REFERENCES order_items(id), user_id BIGINT NOT NULL REFERENCES members(user_id),
  type VARCHAR(10) NOT NULL CHECK (type IN ('DIRECT','BINARY','ROLLUP','RANK_POOL')), amount_est BIGINT NOT NULL,
  status VARCHAR(18) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','CONFIRMED_PENDING','SETTLED','VOID')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX bonus_estimates_user_open ON bonus_estimates (user_id) WHERE status IN ('PENDING','CONFIRMED_PENDING');
CREATE TABLE qualification_daily (                -- 직전 30일 PV(본인 + 개인몰 소비자) 자격
  user_id BIGINT NOT NULL REFERENCES members(user_id), day DATE NOT NULL,
  rolling_pv BIGINT NOT NULL, qualified BOOLEAN NOT NULL, PRIMARY KEY (user_id, day)
);
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
  bucket VARCHAR(10) NOT NULL CHECK (bucket IN ('AVAILABLE','RESERVED')),   -- 출금 가능 / 정산 대기(유보)
  kind VARCHAR(16) NOT NULL CHECK (kind IN ('DAILY_ACCRUAL','RESERVE_RELEASE','SCALING_ADJ','CARRY_ADJ','CLAWBACK',
        'WITHDRAW_HOLD','WITHDRAW_PAID','WITHDRAW_FAIL','WITHHOLDING','SPEND','SPEND_REFUND','ADJUST')),  -- SPEND: 수당 포인트로 상품 결제
  amount BIGINT NOT NULL, ref_type VARCHAR(20), ref_id BIGINT, memo TEXT, created_by BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX earnings_ledger_user_idx ON earnings_ledger (user_id, created_at);
CREATE VIEW earnings_balances AS                  -- 지갑 화면용 잔액(원장 합계)
SELECT user_id,
       COALESCE(SUM(amount) FILTER (WHERE bucket = 'AVAILABLE'), 0) AS available,
       COALESCE(SUM(amount) FILTER (WHERE bucket = 'RESERVED'), 0)  AS reserved
FROM earnings_ledger GROUP BY user_id;
CREATE TABLE payout_batches (
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  kind VARCHAR(10) NOT NULL CHECK (kind IN ('BONUS','SETTLEMENT')), total BIGINT NOT NULL, count INT NOT NULL,
  approved_by_1 BIGINT, approved_by_2 BIGINT, file_key TEXT,
  status VARCHAR(10) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','APPROVED','SENT','DONE','PARTIAL')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (approved_by_2 IS NULL OR approved_by_1 <> approved_by_2)
);
CREATE TABLE withdrawals (                        -- 회원 출금 신청(기준서 v0.4 제12조)
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  user_id BIGINT NOT NULL REFERENCES members(user_id),
  amount BIGINT NOT NULL CHECK (amount >= 10000 AND amount % 1000 = 0),
  withholding BIGINT NOT NULL, net BIGINT NOT NULL,
  status VARCHAR(10) NOT NULL DEFAULT 'REQUESTED' CHECK (status IN ('REQUESTED','HELD','IN_BATCH','PAID','FAILED','CANCELLED')),
  hold_reason VARCHAR(30), auto_approved BOOLEAN NOT NULL DEFAULT false,
  source VARCHAR(16) NOT NULL DEFAULT 'MEMBER' CHECK (source IN ('MEMBER','AUTO_MONTHEND')),  -- 월말 잔액 자동 출금
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(), processed_at TIMESTAMPTZ
);
CREATE TABLE payout_items (                       -- 출금 신청 1건 = 1항목, 영업일 배치 이체
  id BIGSERIAL PRIMARY KEY, tenant_id BIGINT NOT NULL REFERENCES tenants(id),
  batch_id BIGINT NOT NULL REFERENCES payout_batches(id), user_id BIGINT NOT NULL REFERENCES members(user_id),
  withdrawal_id BIGINT REFERENCES withdrawals(id),
  gross BIGINT NOT NULL, withholding BIGINT NOT NULL, net BIGINT NOT NULL CHECK (net >= 0),
  status VARCHAR(10) NOT NULL DEFAULT 'READY' CHECK (status IN ('READY','HELD','PAID','FAILED','CARRIED')),
  hold_reason VARCHAR(30),                        -- NO_TAX_ID / NO_BANK / NEGATIVE_BALANCE / BANK_FAIL
  processed_at TIMESTAMPTZ
);
