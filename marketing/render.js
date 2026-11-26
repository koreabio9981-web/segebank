// 홍보 이미지 만들기: node marketing/render.js
// promo.html 을 16:9(1372x768), 1:1(1080x1080) PNG로 저장합니다. (Playwright 필요)
const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 2 });
  const file = 'file://' + path.join(__dirname, 'promo.html');
  for (const [size, w, h, out] of [['169', 1372, 768, 'promo_16x9.png'], ['11', 1080, 1080, 'promo_1x1.png']]) {
    await page.setViewportSize({ width: w, height: h });
    await page.goto(`${file}?size=${size}`);
    await page.waitForTimeout(300);
    await page.locator('.canvas').screenshot({ path: path.join(__dirname, out) });
    console.log('saved', out);
  }
  await browser.close();
})();
