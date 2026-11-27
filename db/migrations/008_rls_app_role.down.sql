-- 008 되돌리기
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['settings','users','terms_versions','consents','audit_logs','policy_unlocks','members','sellers',
    'categories','products','bulk_jobs','storefronts','domains','carts','orders','settlements','membership_plans',
    'point_lots','point_tx','bonus_plans','bonus_runs','earnings_ledger','payout_batches','payout_items','withdrawals','bonus_estimates','notices','inquiries','notifications','distributor_tax_ids','sensitive_access_logs','memberships']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %I', t);
    EXECUTE format('ALTER TABLE %I DISABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sogaebank_app') THEN
    REVOKE ALL ON ALL TABLES IN SCHEMA public FROM sogaebank_app;
    REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM sogaebank_app;
    REVOKE ALL ON SCHEMA public FROM sogaebank_app;
  END IF;
END $$;
