const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const OUT = process.argv[2]; const conv = fs.readFileSync(__dirname + '/dom2svg.js', 'utf8');
const ROOT = 'file:///home/user/segebank/mockup/';
const only = process.argv[3];
(async () => {
  const b = await chromium.launch();
  const list = [];
  async function prep(p){
    await p.addStyleTag({ content: `.side{position:absolute!important;bottom:auto!important;height:${await p.evaluate(()=>Math.max(document.documentElement.scrollHeight, document.body.scrollHeight))}px!important}` });
  }
  async function cap(p, name, label){
    if (only && !name.startsWith(only)) return;
    await p.waitForTimeout(350); await prep(p);
    const svg = await p.evaluate(([c, n]) => { eval(c); return window.__dom2svg(n); }, [conv, label]);
    fs.writeFileSync(path.join(OUT, name + '.svg'), svg);
    await p.screenshot({ path: path.join(OUT, name + '.png'), fullPage: true });
    list.push([name, label]);
  }
  const desk = await b.newContext({ viewport: { width: 1440, height: 900 } });
  let p = await desk.newPage();
  await p.goto(ROOT + 'index.html'); await cap(p, '00_시안목록', '00 시안 목록');
  // 몰
  await p.goto(ROOT + 'mall.html'); await p.evaluate(() => localStorage.clear()); await p.reload();
  await cap(p, '10_몰_01_홈', '몰 / 홈');
  const nos = await p.evaluate(() => DB.products.filter(x => x.status !== '품절' && x.stock).map(x => x.no));
  const go = async (h, n, l) => { await p.evaluate(h => location.hash = h, h); await cap(p, n, l); };
  await go('p/' + nos[0], '10_몰_02_상품상세', '몰 / 상품 상세');
  await p.evaluate(n => { DB.cart = [[n[0], 1], [n[1], 2]]; save(); }, nos);
  await go('cart', '10_몰_03_장바구니', '몰 / 장바구니');
  await go('checkout', '10_몰_04_주문결제', '몰 / 주문·결제');
  await p.evaluate(() => order()); await cap(p, '10_몰_05_주문완료', '몰 / 주문 완료');
  await go('mypage', '10_몰_06_마이페이지', '몰 / 마이페이지');
  await p.close();
  for (const [f, pre, lab] of [['office.html','20_오피스','오피스'],['seller.html','30_판매자센터','판매자센터'],['admin.html','40_관리자','관리자']]) {
    p = await desk.newPage(); await p.goto(ROOT + f);
    const items = await p.$$eval('.side a[href^="#"]', as => as.map(a => [a.getAttribute('href').slice(1), a.textContent.trim()]));
    let i = 1;
    for (const [h, t] of items) { await p.evaluate(h => location.hash = h, h); await cap(p, `${pre}_${String(i++).padStart(2,'0')}_${t.replace(/[\s·:\/]+/g,'')}`, `${lab} / ${t}`); }
    await p.close();
  }
  const mob = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true });
  p = await mob.newPage();
  const ms = [['', '01_시작'], ['shop', '02_손님화면'], ['items', '03_진열상품'], ['manage', '04_관리'], ['stats', '05_실적'], ['done', '06_개설완료']];
  for (const [h, t] of ms) { await p.goto(ROOT + 'myshop.html' + (h ? '#' + h : '')); await cap(p, `50_개인몰_${t}`, `개인몰(휴대폰) / ${t.slice(3)}`); }
  for (const [f, h, t] of [['mall.html','','60_몰모바일_01_홈'],['mall.html','mypage','60_몰모바일_02_마이페이지'],['office.html','','61_오피스모바일_01_홈'],['office.html','wallet','61_오피스모바일_02_지갑']]) {
    await p.goto(ROOT + f + (h ? '#' + h : '')); await cap(p, t, t.replace(/^\d+_/, '').replace(/_\d+_/, ' / '));
  }
  fs.writeFileSync(path.join(OUT, 'list.json'), JSON.stringify(list, null, 1));
  await b.close();
})();
