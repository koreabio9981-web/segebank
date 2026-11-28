// DB 마이그레이션·RLS 통합 테스트
// 실행: TEST_DATABASE_ADMIN_URL=postgres://postgres@localhost:5432/sogaebank_test npm test
// 주의: 대상 DB의 소개뱅크 테이블을 모두 지웠다가 다시 만듭니다. 테스트 전용 DB에서만 실행하세요.
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import pg from 'pg';
// @ts-expect-error JS 모듈
import { migrate, listMigrations } from '../../scripts/db/migrate.mjs';
import { withTenant } from '@/lib/db';

const url = process.env.TEST_DATABASE_ADMIN_URL;
const quiet = () => {};
const d = url ? describe : describe.skip;

async function tableCount(c: pg.Client) {
  return Number((await c.query("SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' AND table_name <> 'schema_migrations'")).rows[0].count);
}

d('마이그레이션', () => {
  let admin: pg.Client;
  beforeAll(async () => {
    admin = new pg.Client({ connectionString: url });
    await admin.connect();
    await migrate('reset', url, quiet);
  });
  afterAll(async () => { await admin?.end(); });

  it('전부 적용하면 표 48개와 RLS 정책이 생긴다', async () => {
    await migrate('up', url, quiet);
    const applied = (await admin.query('SELECT name FROM schema_migrations ORDER BY name')).rows.map((r) => r.name);
    expect(applied).toEqual(listMigrations());
    expect(await tableCount(admin)).toBe(48);
    const policies = Number((await admin.query('SELECT count(*) FROM pg_policies')).rows[0].count);
    expect(policies).toBeGreaterThanOrEqual(30);
  });

  it('전부 되돌리고 다시 적용할 수 있다', async () => {
    await migrate('reset', url, quiet);
    expect(await tableCount(admin)).toBe(0);
    await migrate('up', url, quiet);
    expect(await tableCount(admin)).toBe(48);
  });

  it('앱 역할은 자기 사이트(tenant) 데이터만 본다', async () => {
    await admin.query("INSERT INTO tenants(id,name) VALUES (1,'소개뱅크'),(2,'분양업체') ON CONFLICT DO NOTHING");
    await admin.query("INSERT INTO users(tenant_id,login_id,password_hash,name) VALUES (1,'kim01','x','김민수'),(2,'kim01','x','다른회사 김민수')");
    const appPool = new pg.Pool({ connectionString: url, options: '-c role=sogaebank_app' });
    try {
      const t1 = await withTenant(1, async (c) => (await c.query('SELECT name FROM users')).rows.map((r) => r.name), appPool);
      const t2 = await withTenant(2, async (c) => (await c.query('SELECT name FROM users')).rows.map((r) => r.name), appPool);
      expect(t1).toEqual(['김민수']);
      expect(t2).toEqual(['다른회사 김민수']);
      const none = await appPool.query('SELECT count(*) FROM users');
      expect(Number(none.rows[0].count)).toBe(0); // tenant 미설정이면 아무것도 안 보임
    } finally {
      await appPool.end();
    }
  });

  it('같은 로그인 ID는 사이트가 다르면 허용, 같으면 거부', async () => {
    await expect(admin.query("INSERT INTO users(tenant_id,login_id,password_hash,name) VALUES (1,'KIM01','x','중복')")).rejects.toThrow(/duplicate|unique/i);
  });
});
