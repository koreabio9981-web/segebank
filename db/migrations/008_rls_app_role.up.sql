-- 008_rls_app_role: 사이트별 데이터 분리(RLS) + 앱 접속 역할
-- 앱은 반드시 sogaebank_app 역할(또는 그 구성원)로 접속해야 RLS가 적용됩니다. (테이블 소유자·슈퍼유저는 RLS를 우회)
-- ========== 행 단위 보안 (예: 모든 tenant 표에 같은 정책) ==========
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['settings','users','terms_versions','consents','audit_logs','policy_unlocks','members','sellers',
    'categories','products','bulk_jobs','storefronts','domains','carts','orders','settlements','membership_plans',
    'point_lots','point_tx','bonus_plans','bonus_runs','earnings_ledger','payout_batches','payout_items','withdrawals','bonus_estimates','notices','inquiries','notifications','distributor_tax_ids','sensitive_access_logs','memberships']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY tenant_isolation ON %I USING (tenant_id = NULLIF(current_setting(''app.tenant_id'', true), '''')::bigint)', t);
  END LOOP;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sogaebank_app') THEN
    CREATE ROLE sogaebank_app NOLOGIN NOBYPASSRLS;
  END IF;
END $$;
GRANT USAGE ON SCHEMA public TO sogaebank_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO sogaebank_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO sogaebank_app;
