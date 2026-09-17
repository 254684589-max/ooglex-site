import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, stat, mkdir } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { launchGlobeBrowser } from './browser.mjs';

const root = resolve('.');
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.jpg': 'image/jpeg', '.png': 'image/png',
  '.svg': 'image/svg+xml', '.otf': 'font/otf', '.wasm': 'application/wasm', '.xml': 'application/xml' };
const server = createServer(async (req, res) => {
  try {
    let file = resolve(root, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname));
    if (!file.startsWith(root + sep)) { res.writeHead(403).end(); return; }
    if ((await stat(file)).isDirectory()) file = resolve(file, 'index.html');
    const data = await readFile(file);
    res.writeHead(200, { 'Content-Type': mime[extname(file)] || 'application/octet-stream' });
    res.end(data);
  } catch { res.writeHead(404).end('Not found'); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = 'http://127.0.0.1:' + server.address().port;
await mkdir('artifacts/globe', { recursive: true });
const browser = await launchGlobeBrowser();
const results = [];
let failures = 0;
async function run(name, fn) {
  try { await fn(); console.log('PASS ' + name); results.push({ name, status: 'pass' }); }
  catch (error) { failures++; console.error('FAIL ' + name + ': ' + error.stack); results.push({ name, status: 'fail', error: error.message }); }
}
async function open(width, mode = 'hang', path = '/apps/globe/') {
  const context = await browser.createBrowserContext();
  const page = await context.newPage();
  await page.setViewport({ width, height: width === 360 ? 800 : 950 });
  const external = [], errors = [], images = [], bad = [];
  await page.setRequestInterception(true);
  page.on('request', req => {
    if (req.url().startsWith(origin) || /^(data:|blob:)/.test(req.url())) { void req.continue(); return; }
    external.push(req);
    if (mode === 'fail') void req.abort('failed');
    // In hang mode leave the request unanswered: a block is not always a fast HTTP error.
  });
  page.on('pageerror', error => errors.push(error.stack || String(error)));
  page.on('response', response => {
    if (response.url().includes('/NaturalEarthII/') && response.url().includes('.jpg') && response.status() === 200) images.push(response.url());
    if (response.url().startsWith(origin) && response.status() >= 400 && !response.url().includes('/api/')) bad.push(response.url());
  });
  try {
  await page.goto(origin + path, { waitUntil: 'domcontentloaded', timeout: 30000 });
  // 包装页在窄屏或省流量模式下先显示「进入卡」，由用户确认后才加载应用。
  if (path === '/apps/globe/' && !(await page.$('.stage iframe'))) {
    await page.waitForSelector('#btn-go', { timeout: 15000 });
    await page.click('#btn-go');
  }
  // 按 URL 解析应用 frame，而不是靠 DOM 层级 —— 包装页改版不该让测试失效。
  let frame = path === '/apps/globe/' ? await appFrameOf(page) : page.mainFrame();
  await frame.waitForFunction(() => document.documentElement.dataset.globeState === 'ready', { timeout: 30000 });
  return { context, page, frame, external, errors, images, bad };
  } catch (error) {
    console.error('STARTUP DIAGNOSTICS ' + JSON.stringify({width, path, errors, bad, images: images.length, external: external.map(req => req.url())}));
    await page.screenshot({path: 'artifacts/globe/startup-failure-' + width + '.png'}).catch(() => {});
    await context.close();
    throw error;
  }
}
async function verifyVisibleEarth(page, frame) {
  // Sample the rendered center, not HTTP responses: a 600 m view of low-res land is one solid color.
  const canvas = await frame.$('.cesium-widget canvas');
  const screenshot = await canvas.screenshot({ type: 'png', encoding: 'base64' });
  const stats = await page.evaluate(async src => {
    const img = new Image(); img.src = src; await img.decode();
    const buffer = document.createElement('canvas');
    buffer.width = img.width; buffer.height = img.height;
    const ctx = buffer.getContext('2d'); ctx.drawImage(img, 0, 0);
    const { data } = ctx.getImageData(0, 0, img.width, img.height);
    const colors = new Set(); let samples = 0, blue = 0, land = 0;
    for (let y = Math.floor(img.height * .3); y < img.height * .7; y += 3) {
      for (let x = Math.floor(img.width * .38); x < img.width * .62; x += 3) {
        const i = (y * img.width + x) * 4, r = data[i], g = data[i+1], b = data[i+2];
        colors.add((r >> 4) * 256 + (g >> 4) * 16 + (b >> 4)); samples++;
        if (b > r * 1.15 && b > g * 1.05 && b > 35) blue++;
        if (g > b * 1.08 && g > 40) land++;
      }
    }
    /* 边缘能量 = 相邻像素亮度差的均值。颜色数分不出「有细节」和「一团糊」——
       糊掉的渐变同样有上百种颜色（实测 500 km 高度一片糊也有 88 色）。
       概览视角下本地底图**是能给出细节的**（本函数只在 1280px 跑，实测 2.0–3.2），
       所以这里可以拿锐度当回归闸门：底图掉了或渲染坏了，它会掉到 0 附近。
       阈值取 >1，离实测下沿还有一倍余量，不至于被单帧抖动误伤。 */
    let sum = 0, pairs = 0;
    const lum = i => 0.299 * data[i] + 0.587 * data[i+1] + 0.114 * data[i+2];
    for (let y = Math.floor(img.height * .3); y < img.height * .7; y += 1) {
      for (let x = Math.floor(img.width * .38); x < img.width * .62 - 1; x += 1) {
        const i = (y * img.width + x) * 4;
        sum += Math.abs(lum(i) - lum(i + 4)); pairs += 1;
      }
    }
    return { colors: colors.size, oceanFraction: blue / samples, landFraction: land / samples,
      edge: pairs ? Number((sum / pairs).toFixed(2)) : 0 };
  }, 'data:image/png;base64,' + screenshot);
  console.log('EARTH PIXELS ' + JSON.stringify(stats));
  // The camera is deliberately centred over the Pacific, so the sampled centre
  // can contain ocean only.  Texture diversity plus a meaningful ocean share is
  // enough to distinguish a rendered globe from the old solid-green close-up.
  const visible = stats.colors > 35 && stats.oceanFraction > .03 && stats.edge > 1;
  if (process.env.GLOBE_VERIFY_PREVIEW || !visible) {
    console.log('GLOBE_PREVIEW ' + await page.screenshot({ type: 'jpeg', quality: 35, encoding: 'base64' }));
  }
  assert(visible, '概览视角的画面中心必须有大陆与海洋的纹理，不能是一片纯色，也不能糊成一团：'
    + JSON.stringify(stats));
}

/** 按 URL 解析**完整应用**所在的 frame（第二层 iframe）。
 *  页面层级：包装页 → apps/globe/lite/（轻量地球）→ 内层 iframe 才是完整应用，
 *  而 globeState / globeMap 都设在完整应用的根元素上。只穿一层会永远等不到 ready。 */
async function appFrameOf(page, mustInclude) {
  for (let i = 0; i < 160; i += 1) {
    const f = page.frames().find(fr => fr.url().includes('/apps/globe/app/')
      && (!mustInclude || fr.url().includes(mustInclude)));
    if (f) return f;
    await new Promise(r => setTimeout(r, 250));
  }
  throw new Error('The full application frame never appeared' + (mustInclude ? ' for ' + mustInclude : ''));
}

async function basic(width, mode = 'hang', path = '/apps/globe/') {
  const state = await open(width, mode, path);
  try {
    const { page, frame, external, errors, images, bad } = state;
    const outcome = await frame.evaluate(async () => {
      // 只剩 Material Symbols Outlined：Material Icons Round 全产物 0 处使用，
      // 已连同它的 @font-face 一起删除（省 391KB）。
      await document.fonts.load('24px "Material Symbols Outlined"');
      await document.fonts.ready;
      const doc = document.documentElement;
      const canvas = document.querySelector('.cesium-widget canvas');
      const icon = [...document.querySelectorAll('.material-symbols-outlined')].find(el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; });
      return { ready: doc.dataset.globeState, map: doc.dataset.globeMap,
        tiles: Number(doc.dataset.globeTiles), width: canvas?.width, height: canvas?.height,
        overflow: doc.scrollWidth > innerWidth + 1,
        outlined: document.fonts.check('24px "Material Symbols Outlined"'),
        iconWidth: icon?.getBoundingClientRect().width,
        loaderHidden: document.querySelector('#loading-screen').classList.contains('hidden') };
    });
    assert.equal(outcome.map, 'local-earth');
    assert((await frame.evaluate(() => window.OoglexGlobeNetwork.viewState().height)) > 10000000, 'The initial camera must show the globe, not 600 m street level');
    if (width === 1280) await verifyVisibleEarth(page, frame);
    assert(outcome.tiles > 0 && images.length > 0, 'A real local JPEG tile must have loaded');
    assert(outcome.width > 0 && outcome.height > 0 && outcome.loaderHidden, 'Rendered canvas and completed startup required');
    // 只断言 Material Symbols Outlined：Material Icons Round 全产物 0 处使用，
    // 已连同 @font-face 一起删除（省 391KB），不能再要求它加载。
    assert(outcome.outlined, 'Local icon font (Material Symbols Outlined) must load');
    assert(outcome.iconWidth > 0 && outcome.iconWidth < 60, 'Icon ligatures must not render as long words');
    assert(!outcome.overflow, 'Inner page must fit the viewport');
    assert.deepEqual(external.map(x => x.url()), [], 'Startup must not request third-party assets');
    assert.deepEqual(bad, []);
    assert.deepEqual(errors, []);
    if (path === '/apps/globe/') {
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
      // 数据来源面板用 hidden 属性开合（包装页已回到单栏单层结构，
      // 不再有「全球视角 / 返回基础地球」那条第二工具栏）。
      await page.click('#btn-src');
      assert(await page.$eval('#sheet', el => !el.hidden), 'Data-source sheet must open');
      await page.keyboard.press('Escape');
      assert(await page.$eval('#sheet', el => el.hidden), 'Escape must close the data-source sheet');
      assert(!(await page.$('#hd')) && !(await page.$('#overview')),
        'The second toolbar (#hd / #overview) must stay removed');
    }
    await page.screenshot({ path: 'artifacts/globe/' + width + '-' + mode + (path.endsWith('/app/') ? '-direct' : '') + '.png' });
  } finally { await state.context.close(); }
}
try {
  for (const width of (process.env.GLOBE_VERIFY_QUICK ? [1280] : [360, 768, 1280])) await run('same-origin startup, all third parties stalled, ' + width, () => basic(width));
  if (!process.env.GLOBE_VERIFY_QUICK && !failures) {
  await run('direct inner URL, third parties fail', () => basic(1280, 'fail', '/apps/globe/app/'));
  // 包装页已回到单栏单层结构，「切换高清影像」按钮不再存在（切底图走应用自身的
  // 底图菜单），所以原先针对该按钮的超时/重试用例已随功能一起撤掉。
  // 换成守住一件更要紧、而且刚刚被改坏过的事：**滚轮导航**。
  //
  // 背景：曾经为了掩盖「基础地球放大后发糊」，在相机守卫里设了
  // maximumMovementRatio=0.12（Cesium 默认 1.0）、minimumZoomDistance=1200，
  // 还让 height<250 就弹回 22000 公里全球视角。结果滚轮几乎不动、永远贴不到地面 ——
  // 用户的原话是「滚轮不是前进或者后退，而是页面放大缩小」。
  await run('mouse wheel dollies the camera instead of crawling or snapping back', async () => {
    const s = await open(1280);
    try {
      // 在**应用 frame 内**往画布派发 wheel。page.mouse.wheel() 的 CDP 合成滚轮
      // 虽然能到达画布（实测 canvas 收到了 wheel 事件），却驱动不了 Cesium 的
      // 相机控制器；frame 内派发可以。所以这里测的是「事件到了之后相机是否动」，
      // 也正是被改坏过的那一环。
      const roll = (notches, deltaY) => s.frame.evaluate(async (n, d) => {
        const c = document.querySelector('.cesium-widget canvas');
        const b = c.getBoundingClientRect();
        for (let i = 0; i < n; i += 1) {
          c.dispatchEvent(new WheelEvent('wheel', { deltaY: d, bubbles: true, cancelable: true,
            clientX: b.left + b.width / 2, clientY: b.top + b.height / 2 }));
          await new Promise(r => setTimeout(r, 30));
        }
        await new Promise(r => setTimeout(r, 500));
        return window.OoglexGlobeNetwork.viewState().height;
      }, notches, deltaY);

      const start = await s.frame.evaluate(() => window.OoglexGlobeNetwork.viewState().height);
      assert(start > 1000000, '初始应为全球视角，实测 ' + Math.round(start) + ' m');

      // 持续前滚必须把高度压下一个数量级以上。
      // 曾经 maximumMovementRatio=0.12（默认 1.0）让滚轮几乎不动，这条就是守它的。
      const near = await roll(220, -240);
      // 阈值按「能否明确区分出 0.12 限速」来定，而不是追求某个好看的数字：
      // 限速下 220 格几乎不动（总幅度约 1.3 倍），恢复默认后实测约 6.7 倍。
      // 取 4 倍，两种状态之间留足余量，也不受机器快慢影响。
      assert(near < start / 4,
        '滚轮前进太弱：' + Math.round(start) + ' m → ' + Math.round(near) + ' m');
      // 曾经 height<250 就弹回 22000 公里；不能再出现「越滚越远」。
      assert(near < start * 0.9, '相机被守卫弹回了全球视角');

      // 后退只需证明方向有效：限速回归由上面那条「前进 4 倍」守住，
      // 这里不再对速度设严阈值，免得受机器快慢影响。
      const far = await roll(80, 240);
      assert(far > near * 1.1,
        '滚轮后退无效：' + Math.round(near) + ' m → ' + Math.round(far) + ' m');
      assert.deepEqual(s.errors, []);
    } finally { await s.context.close(); }
  });
  // 基础底图是 Cesium 自带的 NaturalEarthII，maximumLevel 只有 2：低空一片纯色。
  // 曾经用户看到的就是「一颗没有纹理的淡绿色球」（ALT 626M，旧金山街道高度）。
  // 现在缩放下限跟着底图走（本地 500 km，真实影像放开），这条闸门守住它。
  await run('basic basemap never leaves the user on a featureless sphere', async () => {
    const s = await open(1280);
    try {
      const probe = () => s.frame.evaluate(async () => {
        const c = document.querySelector('.cesium-widget canvas');
        const b = c.getBoundingClientRect();
        for (let i = 0; i < 40; i += 1) {
          c.dispatchEvent(new WheelEvent('wheel', { deltaY: -240, bubbles: true, cancelable: true,
            clientX: b.left + b.width / 2, clientY: b.top + b.height / 2 }));
          await new Promise(r => setTimeout(r, 25));
        }
        await new Promise(r => setTimeout(r, 1400));
        const off = document.createElement('canvas');
        off.width = 200; off.height = 200;
        const g = off.getContext('2d');
        g.drawImage(c, c.width / 2 - 100, c.height / 2 - 100, 200, 200, 0, 0, 200, 200);
        const d = g.getImageData(0, 0, 200, 200).data;
        const set = new Set();
        for (let i = 0; i < d.length; i += 4) set.add((d[i] >> 3 << 10) | (d[i + 1] >> 3 << 5) | (d[i + 2] >> 3));
        return { h: Math.round(window.OoglexGlobeNetwork.viewState().height), colors: set.size,
          map: window.OoglexGlobeNetwork.viewState().map };
      });
      let last = null;
      for (let i = 0; i < 14; i += 1) {
        last = await probe();
        if (last.h < 600000) break;
      }
      // 一路滚到底也不能低于下限（留 10% 余量吸收单帧抖动）
      assert(last.h > 450000,
        '相机降到了基础底图无法显示的高度：' + Math.round(last.h) + ' m（下限 500 km）');
      /* 触底后再滚几轮，画面必须始终**有内容** —— 不能是一片纯色。
       * 这里刻意只判「有没有内容」，不判「清不清晰」：本地底图是 Cesium 自带的
       * NaturalEarthII，maximumLevel 只有 2，实测（390px，屏幕真实像素的边缘能量）
       *     22000 km → 1.42    3000 km → 0.69    1000 km → 0.25    500 km → 0.14
       * 也就是说 8000 km 以下就没有清晰可言了。要「永不发糊」，下限得抬到
       * 8000 公里往上 —— 那等于禁止放大，比发糊糟得多。
       * 糊是数据的性质，**一片纯色才是坏了**，闸门守后者。想要细节就在应用的
       * 底图菜单里切高清影像（触到下限时会自动试一次）。 */
      for (let i = 0; i < 3; i += 1) {
        const now = await probe();
        assert(now.colors >= 20,
          '基础底图在 ' + Math.round(now.h) + ' m 只有 ' + now.colors + ' 种颜色，等于一片纯色');
      }
      assert.deepEqual(s.errors, []);
    } finally { await s.context.close(); }
  });
  // minimumZoomDistance 只约束用户输入，不约束程序化的 flyTo/setView。
  // 应用自带的场景会直接把相机飞到几百米高 —— 用户看到的「一片纯绿色球」
  // （ALT 626M，旧金山金门大桥）正是这条路。这条闸门专门守它。
  await run('a scene flight below the local floor is lifted, not left featureless', async () => {
    const s = await open(1280);
    try {
      const ok = await s.frame.evaluate(() => window.OoglexGlobeNetwork.setView(-122.4889, 37.8115, 626));
      assert(ok, 'setView 测试钩子不可用');
      await new Promise(r => setTimeout(r, 2500));
      const after = await s.frame.evaluate(() => {
        const v = window.OoglexGlobeNetwork.viewState();
        const t = document.getElementById('ooglex-globe-toast');
        return { h: v.height, shown: !!(t && t.dataset.show !== undefined), text: (t && t.textContent) || '' };
      });
      assert(after.h > 450000,
        '场景把相机留在了基础底图无法显示的高度：' + Math.round(after.h) + ' m');
      assert(after.shown && /[\u4e00-\u9fa5]/.test(after.text),
        '抬回高度时必须给出中文说明，实际：' + JSON.stringify(after.text));
      // 画面必须有内容，不能是一片纯色（同上：只判有无内容，不判锐度）
      await new Promise(r => setTimeout(r, 2500));
      const colors = await s.frame.evaluate(() => {
        const c = document.querySelector('.cesium-widget canvas');
        const off = document.createElement('canvas');
        off.width = 200; off.height = 200;
        const g = off.getContext('2d');
        g.drawImage(c, c.width / 2 - 100, c.height / 2 - 100, 200, 200, 0, 0, 200, 200);
        const d = g.getImageData(0, 0, 200, 200).data;
        const set = new Set();
        for (let i = 0; i < d.length; i += 4) set.add((d[i] >> 3 << 10) | (d[i + 1] >> 3 << 5) | (d[i + 2] >> 3));
        return set.size;
      });
      assert(colors >= 20, '抬回后画面仍是一片纯色（只有 ' + colors + ' 种颜色）');
    } finally { await s.context.close(); }
  });
  /* 手机上默认的 tactical HUD 是桌面驾驶舱：390px 下实测有 4 处文字冲出视口
   * （TOP SECRET // SI-TK // NOFORN 等，最远到 x=459，超出 69px）。
   * 现在窄屏自动切上游自带的 minimal，这条闸门守两件事：
   *   a) 没有文字冲出视口；
   *   b) 没有文字被裁掉半个字 —— 中文标签比原来的英文短，但**字宽大得多**，
   *      上游给标签定的 max-width 装不下：实测 `.location-toolbar-label`
   *      需要 45px 只给 36.8px，「定位」被 ellipsis 吃成「定亻」，用户截图里
   *      就是「定1」。b) 这一条必须同时看两种裁法：元素自己溢出
   *      （scrollWidth > clientWidth），以及被某一层祖先的 overflow:hidden 切掉
   *      （元素自己的 scrollWidth 完全正常 —— 第一版只查了前者，正好漏掉它）。
   *      也不能只看叶子节点：真正被裁的往往是「图标 + 文字」那一层。 */
  await run('narrow screens must not clip or overflow UI text', async () => {
    for (const width of [360, 390]) {
      const s = await open(width);
      try {
        await new Promise(r => setTimeout(r, 3000));
        const r = await s.frame.evaluate(() => {
          const over = [], cut = [];
          const skip = (t) => {
            if (/Data attribution|Natural Earth|Cesium/i.test(t)) return true;   // 署名原文，另有闸门
            // 图标是 Material Symbols 的**连字名**当内容（arrow_forward 这类），
            // 字体把整串合成一个字形，scrollWidth 会比 clientWidth 大几个像素
            // （实测 3px）—— 那是字体度量，不是被裁。
            return /^[a-z][a-z0-9_]*$/.test(t);
          };
          document.querySelectorAll('body *').forEach((e) => {
            const t = (e.textContent || '').trim();
            if (!t || t.length > 40 || skip(t)) return;
            const cs = getComputedStyle(e);
            if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) === 0) return;
            const b = e.getBoundingClientRect();
            if (b.width < 4 || b.height < 4) return;
            if (b.bottom < 0 || b.top > innerHeight) return;
            if (b.right > innerWidth + 2 || b.left < -2) {
              over.push(t.slice(0, 24) + '@' + Math.round(b.left) + '..' + Math.round(b.right));
              return;
            }
            let short = e.scrollWidth - e.clientWidth, by = 'self';
            for (let a = e.parentElement; a; a = a.parentElement) {
              const acs = getComputedStyle(a);
              if (acs.overflowX === 'visible' && acs.overflowY === 'visible') continue;
              const ar = a.getBoundingClientRect();
              const shown = Math.min(b.right, ar.right) - Math.max(b.left, ar.left);
              const lost = Math.round(b.width - Math.max(0, shown));
              if (lost > short) { short = lost; by = a.id ? '#' + a.id : a.tagName.toLowerCase(); }
            }
            if (short > 2) cut.push(t.slice(0, 24) + ' 少' + short + 'px(' + by + ')');
          });
          return { hud: document.getElementById('hud-layout-select')?.value,
            over: over.slice(0, 6), cut: cut.slice(0, 6), overN: over.length, cutN: cut.length };
        });
        if (width === 390) assert.equal(r.hud, 'minimal', '窄屏应自动切到 minimal HUD，实际 ' + r.hud);
        assert.equal(r.overN, 0, width + 'px 下有 ' + r.overN + ' 处文字冲出视口：' + JSON.stringify(r.over));
        assert.equal(r.cutN, 0, width + 'px 下有 ' + r.cutN + ' 处文字被裁：' + JSON.stringify(r.cut));
      } finally { await s.context.close(); }
    }
  });
  await run('language switch preserves local startup', async () => {
    const s = await open(1280);
    try {
      // 包装页的「中 / EN」是给 iframe 换 ?lang=en 再重载，中文化层自行短路；
      // 刻意不做「撤销翻译」的簿记 —— 重载可靠得多。
      await s.page.click('#btn-lang');
      await s.page.waitForFunction(
        () => document.querySelector('.stage iframe')?.src.includes('lang=en'), { timeout: 30000 });
      const en = await appFrameOf(s.page, 'lang=en');
      await en.waitForFunction(() => document.documentElement.dataset.globeState === 'ready', { timeout: 30000 });
      assert.equal(await en.evaluate(() => document.documentElement.dataset.globeMap), 'local-earth',
        '切到英文后仍必须是本地基础底图，不能偷偷去请求外网影像');
      await s.page.click('#btn-lang');
      await s.page.waitForFunction(() => {
        const f = document.querySelector('.stage iframe');
        return f && !f.src.includes('lang=en');
      }, { timeout: 30000 });
      assert.deepEqual(s.errors, []);
    } catch (error) {
      console.error('LANGUAGE DIAGNOSTICS ' + JSON.stringify(await s.page.evaluate(() => {
        const f = document.querySelector('.stage iframe');
        return { src: f?.src, state: f?.contentDocument?.documentElement?.dataset };
      }).catch(() => ({}))));
      await s.page.screenshot({ path: 'artifacts/globe/language-failure.png' }).catch(() => {});
      throw error;
    } finally { await s.context.close(); }
  });
  await run('missing entry script fails loudly instead of an endless loader', async () => {
    const context = await browser.createBrowserContext();
    try {
      const page = await context.newPage();
      await page.setViewport({ width: 1280, height: 800 });
      await page.setRequestInterception(true);
      page.on('request', req => {
        if (/\/assets\/index-.*\.js/.test(req.url())) void req.abort();
        else if (req.url().startsWith(origin) || /^(data:|blob:)/.test(req.url())) void req.continue();
        else void req.abort();
      });
      await page.goto(origin + '/apps/globe/', { waitUntil: 'domcontentloaded' });
      if (!(await page.$('.stage iframe'))) {
        await page.waitForSelector('#btn-go', { timeout: 15000 });
        await page.click('#btn-go');
      }
      // 入口脚本取不到时，iframe 会加载但应用永远不 ready。要求包装页别把用户
      // 留在一个没有任何说明的空壳里：整页文案必须出现可读的中文状态。
      await page.waitForFunction(() => {
        const t = document.body.textContent || '';
        return /加载|不可用|失败|无法/.test(t);
      }, { timeout: 50000 });
      const shown = await page.evaluate(() => (document.body.textContent || '').replace(/\s+/g, ' ').slice(0, 120));
      assert(/[\u4e00-\u9fa5]/.test(shown), '入口脚本失败时应有中文可读状态，实际：' + shown);
    } finally { await context.close(); }
  });
  }
} finally {
  const { writeFile } = await import('node:fs/promises');
  await writeFile('artifacts/globe/network-results' + (process.env.GLOBE_VERIFY_QUICK ? '-rebuilt' : '') + '.json', JSON.stringify(results, null, 2) + '\n');
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
if (failures) process.exitCode = 1;
