import { Pool, type PoolClient } from 'pg';

// 앱 접속 풀: sogaebank_app 역할 구성원으로 접속해야 RLS(사이트별 데이터 분리)가 적용됩니다.
let pool: Pool | undefined;
export function getPool(): Pool {
  if (!pool) {
    if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL 이 설정되지 않았습니다');
    pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 10 });
  }
  return pool;
}

/** 한 트랜잭션 안에서 tenant를 설정하고 작업을 실행합니다. 모든 업무 쿼리는 이 함수를 거칩니다. */
export async function withTenant<T>(tenantId: number, fn: (c: PoolClient) => Promise<T>, p: Pool = getPool()): Promise<T> {
  if (!Number.isInteger(tenantId) || tenantId <= 0) throw new Error('잘못된 tenant');
  const c = await p.connect();
  try {
    await c.query('BEGIN');
    await c.query("SELECT set_config('app.tenant_id', $1, true)", [String(tenantId)]);
    const result = await fn(c);
    await c.query('COMMIT');
    return result;
  } catch (e) {
    await c.query('ROLLBACK');
    throw e;
  } finally {
    c.release();
  }
}
