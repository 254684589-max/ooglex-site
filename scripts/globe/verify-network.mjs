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
  // 页面层级：包装页 → apps/globe/lite/（轻量地球，即时首屏）→ 内层 iframe 才是
  // 完整应用。globeState 由 network-policy.js 设在**完整应用**的根元素上，
  // 所以只穿一层（拿到 lite 页）会永远等不到 ready —— 这个坑踩过，别改回去。
  // 按 URL 解析 frame，比逐层 DOM 穿透更稳，也不受包装页改版影响。
  const appFrame = async () => page.frames().find(f => f.url().includes('/apps/globe/app/'));
  let frame = path === '/apps/globe/' ? await appFrame() : page.mainFrame();
  if (path === '/apps/globe/') {
    for (let i = 0; i < 120 && !frame; i += 1) {
      await new Promise(r => setTimeout(r, 250));
      frame = await appFrame();
    }
    assert(frame, 'The full application frame (/apps/globe/app/) never appeared');
  }
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
    return { colors: colors.size, oceanFraction: blue / samples, landFraction: land / samples };
  }, 'data:image/png;base64,' + screenshot);
  console.log('EARTH PIXELS ' + JSON.stringify(stats));
  // The camera is deliberately centred over the Pacific, so the sampled centre
  // can contain ocean only.  Texture diversity plus a meaningful ocean share is
  // enough to distinguish a rendered globe from the old solid-green close-up.
  const visible = stats.colors > 35 && stats.oceanFraction > .03;
  if (process.env.GLOBE_VERIFY_PREVIEW || !visible) {
    console.log('GLOBE_PREVIEW ' + await page.screenshot({ type: 'jpeg', quality: 35, encoding: 'base64' }));
  }
  assert(visible, 'The center must contain textured continents and oceans, not a uniform green surface');
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
      // 包装页已重写：轻量地球本身就是即时首屏，没有「进入卡」了。
      await page.waitForFunction(() => !document.getElementById('hd').disabled);
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
      await page.click('#sources');
      // 新版包装页用 .open 类 + aria-hidden 开合，不是 hidden 属性
      assert(await page.$eval('#sheet', el => el.classList.contains('open') && el.getAttribute('aria-hidden') === 'false'),
        'Data-source sheet must open');
      await page.keyboard.press('Escape');
      assert(await page.$eval('#sheet', el => !el.classList.contains('open') && el.getAttribute('aria-hidden') === 'true'),
        'Escape must close the data-source sheet');
      assert(await page.$eval('#hd', el => !el.disabled));
      assert(await page.$eval('#overview', el => !el.disabled));
      await page.click('#overview');
      assert((await frame.evaluate(() => window.OoglexGlobeNetwork.viewState().height)) > 20000000);
    }
    await page.screenshot({ path: 'artifacts/globe/' + width + '-' + mode + (path.endsWith('/app/') ? '-direct' : '') + '.png' });
  } finally { await state.context.close(); }
}
try {
  for (const width of (process.env.GLOBE_VERIFY_QUICK ? [1280] : [360, 768, 1280])) await run('same-origin startup, all third parties stalled, ' + width, () => basic(width));
  if (!process.env.GLOBE_VERIFY_QUICK && !failures) {
  await run('direct inner URL, third parties fail', () => basic(1280, 'fail', '/apps/globe/app/'));
  await run('remote imagery timeout, retry and late completion isolation', async () => {
    const s = await open(1280);
    try {
      // 必须先等 #hd 可用再点：完整应用就绪前按钮是 disabled 的，
      // 直接点会落空，于是状态永远停在原处、后面那条 18s 等待必然超时。
      // 实测高清影像失败到「影像不可用」约 8.1 秒，18s 的余量本身是够的。
      await s.page.waitForFunction(() => !document.getElementById('hd')?.disabled, { timeout: 60000 });
      await s.page.click('#hd');
      await s.page.waitForFunction(() => document.getElementById('load-status').textContent.includes('正在连接'), { timeout: 5000 });
      await s.page.waitForFunction(() => document.getElementById('load-status').textContent.includes('影像不可用'), { timeout: 18000 });
      assert.equal(await s.frame.evaluate(() => document.documentElement.dataset.globeMap), 'local-earth');
      const firstCount = s.external.length;
      assert(firstCount > 0, 'Optional imagery must actually attempt an external request');
      // Late network failure must not overwrite the recovered map or cause an unhandled rejection.
      await Promise.all(s.external.map(req => req.abort('failed').catch(() => {})));
      // 必须先等 #hd 可用再点：完整应用就绪前按钮是 disabled 的，
      // 直接点会落空，于是状态永远停在原处、后面那条 18s 等待必然超时。
      // 实测高清影像失败到「影像不可用」约 8.1 秒，18s 的余量本身是够的。
      await s.page.waitForFunction(() => !document.getElementById('hd')?.disabled, { timeout: 60000 });
      await s.page.click('#hd');
      await s.page.waitForFunction(() => document.getElementById('load-status').textContent.includes('正在连接'), { timeout: 5000 });
      await s.page.waitForFunction(() => document.getElementById('load-status').textContent.includes('影像不可用'), { timeout: 18000 });
      assert(s.external.length > firstCount, 'Retry must not reuse a cached failure');
      assert.equal(await s.frame.evaluate(() => document.documentElement.dataset.globeMap), 'local-earth');
      assert.deepEqual(s.errors, []);
    } finally { await s.context.close(); }
  });
  await run('language switch preserves local startup', async () => {
    const s = await open(1280);
    try {
      await s.page.waitForFunction(() => !document.getElementById('hd').disabled);
      await s.page.click('#lang');
      await s.page.waitForFunction(() => document.getElementById('globe')?.src.includes('lang=en'), { timeout: 30000 });
      const en = await appFrameOf(s.page, 'lang=en');
      await en.waitForFunction(() => document.documentElement.dataset.globeState === 'ready', { timeout: 30000 });
      assert.equal(await en.evaluate(() => document.documentElement.dataset.globeMap), 'local-earth');
      await s.page.waitForFunction(() => !document.getElementById('hd').disabled);
      await s.page.click('#lang');
      await s.page.waitForFunction(() => {
        const f = document.getElementById('globe');
        return f && !f.src.includes('lang=en');
      }, { timeout: 30000 });
    } catch (error) {
      console.error('LANGUAGE DIAGNOSTICS ' + JSON.stringify(await s.page.evaluate(() => {
        const f = document.querySelector('.stage iframe');
        return {src: f?.src, state: f?.contentDocument?.documentElement.dataset, gate: document.getElementById('load-status')?.textContent, status: document.getElementById('load-status').textContent};
      })));
      console.error('LANGUAGE NETWORK ' + JSON.stringify({errors: s.errors, bad: s.bad, external: s.external.map(r => r.url())}));
      await s.page.screenshot({path: 'artifacts/globe/language-failure.png'}).catch(() => {});
      throw error;
    } finally { await s.context.close(); }
  });
  await run('missing entry script shows retry instead of an endless loader', async () => {
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
      // 包装页重写后，轻量地球本身就是可用首屏：入口脚本失败时用户手里仍有一个
      // 能用的基础地球，不存在需要防的「无尽加载」，包装页也不再有重试按钮
      // （文案表里没有「重新加载」）。因此改为断言新的预期行为。
      await page.waitForFunction(() => {
        const lite = document.getElementById('globe');
        const ld = lite && lite.contentDocument;
        return !!(ld && ld.querySelector('canvas'));
      }, { timeout: 50000 });
      const status = await page.$eval('#load-status', el => el.textContent || '');
      assert(!status.includes('正在连接'), '入口脚本失败后状态不应停在「正在连接」，实际：' + status);
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
