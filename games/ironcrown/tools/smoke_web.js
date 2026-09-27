// 《铁冠之争》网页导出冒烟测试（TECH.md 第七节；结构沿用 games/emberfall3d/tools/smoke_web.js）。
// 阶段 1.1：在 1280 / 768 / 360 三个宽度下打开 play/，检查引擎启动（IC_READY）、使用兼容渲染器、
// 控制台无报错、页面无横向溢出、加载画面已消失，并截图。之后每一步往这里加检查项。
//
// 先在仓库根目录起静态服务器（gzip 传输，模拟线上 CDN）：
//   python3 games/ironcrown/tools/serve_gzip.py . 8765
//   node games/ironcrown/tools/smoke_web.js [截图目录] [地址]
// 需要全局安装的 playwright（云端开发环境自带 /opt/node22/lib/node_modules/playwright 与预装 Chromium）。
const path = require('path');
let pw;
try { pw = require('playwright'); } catch (e) { pw = require('/opt/node22/lib/node_modules/playwright'); }
const outDir = process.argv[2] || '.';
const url = process.argv[3] || 'http://localhost:8765/games/ironcrown/play/';

(async () => {
  // 无头 Chromium 没有 GPU，用 SwiftShader 软件渲染 WebGL 2
  const browser = await pw.chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  let failed = 0;
  for (const [w, h, name, mobile] of [[1280, 720, 'desk', false], [768, 1024, 'tab', true], [360, 740, 'phone', true]]) {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, isMobile: mobile, hasTouch: mobile });
    const page = await ctx.newPage();
    const logs = [], errs = [];
    page.on('console', m => { logs.push(m.text()); if (m.type() === 'error') errs.push(m.text()); });
    page.on('pageerror', e => errs.push('pageerror ' + e.message));
    const t0 = Date.now();
    await page.goto(url);
    let ready;
    for (let i = 0; i < 120 && !ready; i++) { await page.waitForTimeout(500); ready = logs.find(l => l.startsWith('IC_READY')); }
    const bootSec = ((Date.now() - t0) / 1000).toFixed(1);
    await page.waitForTimeout(1500);
    await page.screenshot({ path: path.join(outDir, `ic-${name}.png`) });
    const overlayGone = await page.evaluate(() => !document.getElementById('wl-loading'));
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
    const compat = !!ready && ready.includes('renderer=gl_compatibility') && ready.includes('web=true');
    const ok = compat && overlayGone && errs.length === 0 && overflow <= 0;
    if (!ok) failed++;
    console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${w}x${h} | ${ready || '未启动'} | 加载画面${overlayGone ? '已消失' : '仍在'} | 启动 ${bootSec}s | 溢出 ${overflow}px | 报错 ${errs.length}${errs.length ? '：' + errs.slice(0, 3).join(' || ') : ''}`);
    await ctx.close();
  }
  await browser.close();
  process.exit(failed ? 1 : 0);
})();
