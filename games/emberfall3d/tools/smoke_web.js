// 网页导出冒烟测试（TECH.md 第六节）：打开 play/，在 1280 / 768 / 360 三个宽度下检查
// 引擎启动（EF_READY）、章节包加载（EF_PACK_OK）、导航烘焙耗时（EF_NAV_*）、点击 / 触屏点木桩后命中（EF_HIT）、
// 点地面后主角到达（EF_ARRIVED）、
// 控制台无报错、页面无横向溢出，并截图。
//
// 先在仓库根目录起静态服务器（用 gzip 压缩传输，模拟线上 CDN；python -m http.server 不压缩，测不出解压类问题）：
//   python3 games/emberfall3d/tools/serve_gzip.py . 8765
//   node games/emberfall3d/tools/smoke_web.js [截图目录] [地址]
// 需要全局安装的 playwright（云端开发环境自带 /opt/node22/lib/node_modules/playwright 与预装 Chromium）。
const path = require('path');
let pw;
try { pw = require('playwright'); } catch (e) { pw = require('/opt/node22/lib/node_modules/playwright'); }
const outDir = process.argv[2] || '.';
const url = process.argv[3] || 'http://localhost:8765/games/emberfall3d/play/';

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
    let ready, pack;
    for (let i = 0; i < 120 && !(ready && pack); i++) {
      await page.waitForTimeout(500);
      ready = logs.find(l => l.startsWith('EF_READY'));
      pack = logs.find(l => l.startsWith('EF_PACK_'));
    }
    // 等整层地下城的导航基准跑完（启动后两帧开始）
    for (let i = 0; i < 40 && !logs.some(l => l.startsWith('EF_NAV_BENCH')); i++) await page.waitForTimeout(250);
    // 点木桩攻击（游戏启动时打出 EF_DUMMY_SCREEN：第一个木桩的屏幕坐标），要求出现命中日志 EF_HIT
    const ds = logs.find(l => l.startsWith('EF_DUMMY_SCREEN'));
    let hit;
    if (ds) {
      const [, dx, dy] = ds.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
      if (mobile) await page.touchscreen.tap(dx, dy); else await page.mouse.click(dx, dy);
      for (let i = 0; i < 16 && !hit; i++) { await page.waitForTimeout(250); hit = logs.find(l => l.startsWith('EF_HIT')); }
      await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(outDir, `ef3d-${name}-hit.png`) });
    }
    // 点地面移动：电脑用鼠标点，手机 / 平板用触屏点（点在摇杆与按钮区域以外）
    const tx = Math.round(w * 0.3), ty = Math.round(h * 0.38);
    if (mobile) await page.touchscreen.tap(tx, ty); else await page.mouse.click(tx, ty);
    let arrived;
    for (let i = 0; i < 40 && !arrived; i++) { await page.waitForTimeout(250); arrived = logs.find(l => l.startsWith('EF_ARRIVED')); }
    await page.waitForTimeout(600);
    await page.screenshot({ path: path.join(outDir, `ef3d-${name}.png`) });
    const nav = logs.filter(l => l.startsWith('EF_NAV')).join(' | ');
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
    const ok = !!ready && !!pack && pack.startsWith('EF_PACK_OK') && !!hit && !!arrived && errs.length === 0 && overflow <= 0;
    if (!ok) failed++;
    console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${w}x${h} | ${ready || '未启动'} | ${pack || '无章节包日志'} | ${nav || '无导航日志'} | ${hit || '点木桩后没有命中'} | ${arrived || '点地面后未到达'} | 启动 ${((Date.now() - t0) / 1000).toFixed(1)}s | 溢出 ${overflow}px | 报错 ${errs.length}${errs.length ? '：' + errs.slice(0, 3).join(' || ') : ''}`);
    await ctx.close();
  }
  await browser.close();
  process.exit(failed ? 1 : 0);
})();
