// 《铁冠之争》网页导出冒烟测试（TECH.md 第七节；结构沿用 games/emberfall3d/tools/smoke_web.js）。
// 在 1280 / 768 / 360 三个宽度下打开 play/：
//   1.1  引擎启动（IC_READY）、兼容渲染器、控制台无报错、页面无横向溢出、加载画面消失；
//   1.2  电脑：点击画面后按住 W 走动（IC_MOVED）、Esc 打开 / 关闭暂停菜单（IC_PAUSE）；
//        手机 / 平板：左半屏真实触屏拖动走动（IC_MOVED）、右半屏拖动转视角（IC_LOOK）、点「菜单」打开暂停菜单；
//        再打开 ?test=1 灰盒测试场，走几步截图。
//   1.3  测试场出生点对准灰盒 NPC（IC_TARGET）：电脑按 E、手机 / 平板点右下角交互按钮，要求和 NPC 说话（IC_INTERACT kind=npc），截图。
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

async function waitLog(logs, prefix, tries = 40) {
  for (let i = 0; i < tries; i++) {
    const hit = logs.find(l => l.startsWith(prefix));
    if (hit) return hit;
    await new Promise(r => setTimeout(r, 250));
  }
  return '';
}

// 用 Chrome 调试协议发真实的触屏拖动（Playwright 的 touchscreen 只有点按）
async function touchDrag(cdp, id, x0, y0, dx, dy, ms) {
  const steps = 12;
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: x0, y: y0, id }] });
  for (let i = 1; i <= steps; i++) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x0 + dx * i / steps, y: y0 + dy * i / steps, id }] });
    await new Promise(r => setTimeout(r, 30));
  }
  await new Promise(r => setTimeout(r, ms));
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}

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
    const ready = await waitLog(logs, 'IC_READY', 240);
    const bootSec = ((Date.now() - t0) / 1000).toFixed(1);
    await page.waitForTimeout(1200);
    await page.screenshot({ path: path.join(outDir, `ic-${name}.png`) });
    const overlayGone = await page.evaluate(() => !document.getElementById('wl-loading'));
    const compat = !!ready && ready.includes('renderer=gl_compatibility') && ready.includes('web=true') && ready.includes('scene=frostford');
    const dpr = await page.evaluate(() => devicePixelRatio);
    let moved = '', look = 'n/a', pauseOpen = '', pauseClose = 'n/a';
    if (!mobile) {
      await page.mouse.click(w / 2, h / 2);             // 点击画面（尝试锁定指针）
      await page.keyboard.down('w');
      moved = await waitLog(logs, 'IC_MOVED', 16);
      await page.keyboard.up('w');
      await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-walk.png`) });
      await page.keyboard.press('Escape');
      pauseOpen = await waitLog(logs, 'IC_PAUSE open=true', 12);
      await page.waitForTimeout(400);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-pause.png`) });
      await page.keyboard.press('Escape');
      pauseClose = await waitLog(logs, 'IC_PAUSE open=false', 12);
    } else {
      const cdp = await ctx.newCDPSession(page);
      await touchDrag(cdp, 1, w * 0.22, h * 0.72, 0, -50, 1500);   // 左半屏：向上拖 = 向前走
      moved = await waitLog(logs, 'IC_MOVED', 12);
      await touchDrag(cdp, 2, w * 0.7, h * 0.45, 120, 0, 200);     // 右半屏：向右拖 = 转视角
      look = await waitLog(logs, 'IC_LOOK', 12);
      await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(outDir, `ic-${name}-walk.png`) });
      const ms = logs.find(l => l.startsWith('IC_MENU_SCREEN'));
      if (ms) {
        const [, mx, my] = ms.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
        await page.touchscreen.tap(mx / dpr, my / dpr);
        pauseOpen = await waitLog(logs, 'IC_PAUSE open=true', 12);
        await page.waitForTimeout(400);
        await page.screenshot({ path: path.join(outDir, `ic-${name}-pause.png`) });
      }
    }
    // 灰盒测试场
    logs.length = 0;
    await page.goto(url + (url.includes('?') ? '&' : '?') + 'test=1');
    const range = await waitLog(logs, 'IC_READY', 240);
    const target = await waitLog(logs, 'IC_TARGET name=灰盒路人', 16);
    await page.waitForTimeout(500);
    let talk = '';
    if (!mobile) {
      await page.keyboard.press('e');
    } else {
      const us = await waitLog(logs, 'IC_USE_SCREEN', 8);
      if (us) {
        const [, ux, uy] = us.match(/x=(-?\d+) y=(-?\d+)/).map(Number);
        await page.touchscreen.tap(ux / dpr, uy / dpr);
      }
    }
    talk = await waitLog(logs, 'IC_INTERACT kind=npc', 12);
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(outDir, `ic-${name}-talk.png`) });
    if (!mobile) {
      await page.keyboard.down('w');
      await page.waitForTimeout(900);
      await page.keyboard.up('w');
    } else {
      const cdp = await ctx.newCDPSession(page);
      await touchDrag(cdp, 3, w * 0.22, h * 0.72, 0, -40, 700);
    }
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(outDir, `ic-${name}-range.png`) });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
    const ok = compat && overlayGone && !!moved && !!look && !!pauseOpen && !!pauseClose && range.includes('scene=test_range') && !!target && !!talk && errs.length === 0 && overflow <= 0;
    if (!ok) failed++;
    console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${w}x${h} | ${ready || '未启动'} | 加载画面${overlayGone ? '已消失' : '仍在'} | 走动：${moved || '没有移动'} | 转视角：${look || '没有转'} | 暂停：${pauseOpen || '没打开'} / ${pauseClose || '没关闭'} | 测试场：${range ? 'ok' : '未启动'} | 交互：${target ? '对准 NPC' : '没对准'}，${talk || '没说上话'} | 启动 ${bootSec}s | 溢出 ${overflow}px | 报错 ${errs.length}${errs.length ? '：' + errs.slice(0, 3).join(' || ') : ''}`);
    await ctx.close();
  }
  await browser.close();
  process.exit(failed ? 1 : 0);
})();
