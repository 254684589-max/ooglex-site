// 网页导出冒烟测试（TECH.md 第六节）：打开 play/，在 1280 / 768 / 360 三个宽度下检查
// 引擎启动（EF_READY）、章节包加载（EF_PACK_OK）、导航烘焙耗时（EF_NAV_*）、点击 / 触屏点木桩后命中（EF_HIT）、
// 点地面后主角到达（EF_ARRIVED）、走楼梯进入随机地下城第 1 层（EF_FLOOR，P2）、
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
    // 走楼梯下到地窖第 1 层（P2）：主角到达后游戏会再报一次楼梯的屏幕坐标；在屏幕内就点过去，
    // 不在屏幕内（手机竖屏视野窄）就改用 ?floor=1 直接进第 1 层，至少验证网页上能搭出整层地下城
    let floorLog, floorHow = '';
    const stairLogs = () => logs.filter(l => l.startsWith('EF_STAIRS_SCREEN'));
    for (let i = 0; i < 12 && stairLogs().length < 2; i++) await page.waitForTimeout(250);
    const yMax = h * (mobile ? 0.6 : 0.7);
    for (let hop = 0; hop < 4 && !floorLog; hop++) {
      const st = stairLogs().pop();
      if (!st) break;
      const sx = +/x=(-?\d+)/.exec(st)[1], sy = +/y=(-?\d+)/.exec(st)[1];
      const inside = sx > 20 && sx < w - 20 && sy > 120 && sy < yMax;
      // 楼梯在屏幕外：先朝它的方向走一段（到达后游戏会再报一次楼梯坐标）
      const px = inside ? sx : Math.min(w - 30, Math.max(30, Math.round(w / 2 + (sx - w / 2) * 0.6)));
      const py = inside ? sy : Math.min(yMax - 10, Math.max(130, Math.round(h / 2 + (sy - h / 2) * 0.6)));
      const n0 = stairLogs().length;
      if (mobile) await page.touchscreen.tap(px, py); else await page.mouse.click(px, py);
      if (inside) {
        floorHow = `点楼梯（第 ${hop + 1} 次点击）`;
        for (let i = 0; i < 60 && !floorLog; i++) { await page.waitForTimeout(250); floorLog = logs.find(l => l.startsWith('EF_FLOOR n=1')); }
      } else {
        for (let i = 0; i < 40 && stairLogs().length <= n0 && !floorLog; i++) { await page.waitForTimeout(250); floorLog = logs.find(l => l.startsWith('EF_FLOOR n=1')); }
        if (floorLog) floorHow = '朝楼梯走时踩到楼梯';
      }
    }
    if (!floorLog) {
      floorHow = (floorHow ? floorHow + '失败' : '走不到楼梯') + `，改用 ?floor=1 [${stairLogs().pop() || '无楼梯坐标'}]`;
      await page.goto(url + (url.includes('?') ? '&' : '?') + 'floor=1', { waitUntil: 'load' });
      for (let i = 0; i < 120 && !floorLog; i++) { await page.waitForTimeout(250); floorLog = logs.find(l => l.startsWith('EF_FLOOR n=1')); }
    }
    await page.waitForTimeout(1200);
    await page.screenshot({ path: path.join(outDir, `ef3d-${name}-floor1.png`) });
    // 角色面板（P3）：按 C 打开截图，再按 Esc 关闭
    await page.keyboard.press('c');
    await page.waitForTimeout(500);
    await page.screenshot({ path: path.join(outDir, `ef3d-${name}-char.png`) });
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    const nav = logs.filter(l => l.startsWith('EF_NAV')).join(' | ');
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
    const ok = !!ready && !!pack && pack.startsWith('EF_PACK_OK') && !!hit && !!arrived && !!floorLog && errs.length === 0 && overflow <= 0;
    if (!ok) failed++;
    console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${w}x${h} | ${ready || '未启动'} | ${pack || '无章节包日志'} | ${nav || '无导航日志'} | ${hit || '点木桩后没有命中'} | ${arrived || '点地面后未到达'} | ${floorHow}：${floorLog || '没有进入第 1 层'} | 启动 ${((Date.now() - t0) / 1000).toFixed(1)}s | 溢出 ${overflow}px | 报错 ${errs.length}${errs.length ? '：' + errs.slice(0, 3).join(' || ') : ''}`);
    await ctx.close();
  }
  await browser.close();
  process.exit(failed ? 1 : 0);
})();
