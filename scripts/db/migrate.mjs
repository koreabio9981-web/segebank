#!/usr/bin/env node
// 소개뱅크 DB 마이그레이션 실행기 (의존성: pg)
// 사용: node scripts/db/migrate.mjs up | down | redo | reset | status | seed
// 접속: DATABASE_ADMIN_URL (테이블 소유자 권한). 앱은 DATABASE_URL(sogaebank_app 구성원)로 접속합니다.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const dir = path.join(root, 'db/migrations');

export function listMigrations() {
  return fs.readdirSync(dir).filter((f) => f.endsWith('.up.sql')).map((f) => f.replace('.up.sql', '')).sort();
}

async function ensureTable(c) {
  await c.query('CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())');
}
async function applied(c) {
  return (await c.query('SELECT name FROM schema_migrations ORDER BY name')).rows.map((r) => r.name);
}
async function runFile(c, name, kind) {
  const sql = fs.readFileSync(path.join(dir, `${name}.${kind}.sql`), 'utf8');
  await c.query('BEGIN');
  try {
    await c.query(sql);
    if (kind === 'up') await c.query('INSERT INTO schema_migrations(name) VALUES ($1)', [name]);
    else await c.query('DELETE FROM schema_migrations WHERE name = $1', [name]);
    await c.query('COMMIT');
  } catch (e) {
    await c.query('ROLLBACK');
    throw new Error(`${name}.${kind}.sql 실패: ${e.message}`);
  }
}

export async function migrate(command, url = process.env.DATABASE_ADMIN_URL, log = console.log) {
  if (!url) throw new Error('DATABASE_ADMIN_URL 이 필요합니다 (.env.example 참고)');
  const c = new pg.Client({ connectionString: url });
  await c.connect();
  try {
    await ensureTable(c);
    const all = listMigrations();
    const done = await applied(c);
    if (command === 'up') {
      const pending = all.filter((m) => !done.includes(m));
      for (const m of pending) { await runFile(c, m, 'up'); log(`↑ ${m}`); }
      if (!pending.length) log('적용할 마이그레이션 없음');
    } else if (command === 'down') {
      const last = done.at(-1);
      if (!last) return log('되돌릴 마이그레이션 없음');
      await runFile(c, last, 'down'); log(`↓ ${last}`);
    } else if (command === 'reset') {
      for (const m of [...done].reverse()) { await runFile(c, m, 'down'); log(`↓ ${m}`); }
    } else if (command === 'redo') {
      const last = done.at(-1);
      if (last) { await runFile(c, last, 'down'); log(`↓ ${last}`); await runFile(c, last, 'up'); log(`↑ ${last}`); }
    } else if (command === 'status') {
      for (const m of all) log(`${done.includes(m) ? '✔' : '·'} ${m}`);
    } else if (command === 'seed') {
      await c.query(fs.readFileSync(path.join(root, 'db/seed.sql'), 'utf8')); log('시드 적용');
    } else {
      throw new Error(`알 수 없는 명령: ${command}`);
    }
  } finally {
    await c.end();
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  migrate(process.argv[2] || 'status').catch((e) => { console.error(e.message); process.exit(1); });
}
