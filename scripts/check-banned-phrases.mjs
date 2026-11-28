#!/usr/bin/env node
// 화면 문구에 수익 보장·과장 표현이 들어가지 않았는지 검사 (후원수당 기준서 v1.0 제16조)
import fs from 'node:fs';
import path from 'node:path';
const BANNED = ['수익 보장', '원금 보장', '확정 수익', '고수익 보장', '월 수익 보장', '무조건 수익', '추천만 해도 수익'];
const ROOTS = ['app', 'src'];
let bad = 0;
function walk(d) {
  if (!fs.existsSync(d)) return;
  for (const f of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, f.name);
    if (f.isDirectory()) walk(p);
    else if (/\.(tsx?|mdx?)$/.test(f.name) && !p.includes('check-banned')) {
      const t = fs.readFileSync(p, 'utf8');
      for (const w of BANNED) if (t.includes(w) && !t.includes(`'${w}'`)) { console.error(`금지 문구 "${w}": ${p}`); bad++; }
    }
  }
}
ROOTS.forEach(walk);
if (bad) process.exit(1);
console.log('금지 문구 검사 통과');
