# 개발 환경 안내 (S1: INF-1 · INF-2)

## 필요한 것
- Node.js 20 이상, npm
- Docker(로컬 PostgreSQL 16) 또는 직접 설치한 PostgreSQL 16

## 처음 실행
```bash
npm ci
cp .env.example .env.local          # 값 수정
docker compose up -d                # 로컬 DB
export DATABASE_ADMIN_URL=postgres://postgres:postgres@localhost:5432/sogaebank
npm run db:migrate                  # 001~008 적용
npm run db:seed                     # 개발용 시드(운영 금지)
npm run dev                         # http://localhost:3000
```

앱이 쓰는 DB 계정은 `sogaebank_app` 역할의 구성원이어야 합니다. 그래야 사이트별 데이터 분리(RLS)가 적용됩니다.
```sql
CREATE ROLE sogaebank_web LOGIN PASSWORD '...' IN ROLE sogaebank_app;
```

## 명령
| 명령 | 내용 |
|---|---|
| `npm run build` | 운영 빌드 |
| `npm run lint` | ESLint + 금지 문구(수익 보장 등) 검사 |
| `npm run typecheck` | 타입 검사 |
| `npm test` | 테스트. `TEST_DATABASE_ADMIN_URL`이 없으면 DB 테스트는 건너뜀 |
| `npm run db:migrate` / `db:rollback` / `db:redo` | 마이그레이션 적용 / 마지막 1개 되돌리기 / 다시 적용 |
| `node scripts/db/migrate.mjs status` | 적용 상태 |

## DB 테스트
```bash
createdb sogaebank_test
TEST_DATABASE_ADMIN_URL=postgres://postgres:postgres@localhost:5432/sogaebank_test npm test
```
검증 항목:
1. 001~008을 모두 적용하면 표 48개와 RLS 정책이 생긴다
2. 전부 되돌린 뒤 다시 적용할 수 있다
3. 앱 역할은 자기 사이트 데이터만 보고, 사이트를 정하지 않으면 아무것도 보이지 않는다
4. 로그인 ID는 사이트 안에서만 고유하다(대소문자 무시)

## 규칙
- 스키마를 바꿀 때는 **새 번호의 up/down 파일**을 추가합니다. 이미 적용된 파일은 고치지 않습니다. `docs/dev/schema.sql`도 같이 맞춥니다(참고용 전체본).
- 업무 쿼리는 반드시 `withTenant(tenantId, fn)`(`src/lib/db.ts`) 안에서 실행합니다.
- RLS 정책은 `NULLIF(current_setting('app.tenant_id', true), '')`를 씁니다. 연결이 재사용되면 설정값이 빈 문자열로 남기 때문이며, 테스트로 발견했습니다.
