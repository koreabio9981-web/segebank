-- 개발용 시드 (운영 DB에 실행 금지)
INSERT INTO tenants (id, name, plan, features, status)
VALUES (1, '소개뱅크', 'PREMIUM', '{"mlm":false,"seller":true,"member_shop":true,"points":true}', 'OPEN')
ON CONFLICT (id) DO NOTHING;
SELECT setval(pg_get_serial_sequence('tenants','id'), GREATEST((SELECT MAX(id) FROM tenants), 1));
INSERT INTO settings (tenant_id, key, value) VALUES
  (1, 'pv_ratio', '0.70'), (1, 'reserve_rate', '0.10'), (1, 'withdrawal_min_krw', '10000')
ON CONFLICT (tenant_id, key) DO NOTHING;
INSERT INTO categories (tenant_id, name, sort) VALUES
  (1,'식품',1),(1,'건강',2),(1,'생활',3),(1,'뷰티',4),(1,'가전',5)
ON CONFLICT (tenant_id, name) DO NOTHING;
