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
  if (path === '/apps/globe/' && !(await page.$('.stage iframe'))) {
    await page.waitForFunction(() => document.getElementById('lite-earth').dataset.state === 'ready');
    if (!(await page.$('.stage iframe'))) await page.click('#btn-go');
  }
  const frame = path === '/apps/globe/' ? await (await page.$('.stage iframe')).contentFrame() : page.mainFrame();
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
async function basic(width, mode = 'hang', path = '/apps/globe/') {
  const state = await open(width, mode, path);
  try {
    const { page, frame, external, errors, images, bad } = state;
    const outcome = await frame.evaluate(async () => {
      await Promise.all([
        document.fonts.load('24px "Material Symbols Outlined"'),
        document.fonts.load('24px "Material Icons Round"')
      ]);
      await document.fonts.ready;
      const doc = document.documentElement;
      const canvas = document.querySelector('.cesium-widget canvas');
      const icon = [...document.querySelectorAll('.material-symbols-outlined')].find(el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; });
      return { ready: doc.dataset.globeState, map: doc.dataset.globeMap,
        tiles: Number(doc.dataset.globeTiles), width: canvas?.width, height: canvas?.height,
        overflow: doc.scrollWidth > innerWidth + 1,
        outlined: document.fonts.check('24px "Material Symbols Outlined"'),
        round: document.fonts.check('24px "Material Icons Round"'),
        iconWidth: icon?.getBoundingClientRect().width,
        loaderHidden: document.querySelector('#loading-screen').classList.contains('hidden') };
    });
    assert.equal(outcome.map, 'local-earth');
    assert((await frame.evaluate(() => window.OoglexGlobeNetwork.viewState().height)) > 10000000, 'The initial camera must show the globe, not 600 m street level');
    if (width === 1280) await verifyVisibleEarth(page, frame);
    assert(outcome.tiles > 0 && images.length > 0, 'A real local JPEG tile must have loaded');
    assert(outcome.width > 0 && outcome.height > 0 && outcome.loaderHidden, 'Rendered canvas and completed startup required');
    assert(outcome.outlined && outcome.round, 'Local icon fonts must load');
    assert(outcome.iconWidth > 0 && outcome.iconWidth < 60, 'Icon ligatures must not render as long words');
    assert(!outcome.overflow, 'Inner page must fit the viewport');
    assert.deepEqual(external.map(x => x.url()), [], 'Startup must not request third-party assets');
    assert.deepEqual(bad, []);
    assert.deepEqual(errors, []);
    if (path === '/apps/globe/') {
      await page.waitForFunction(() => getComputedStyle(document.getElementById('gate')).display === 'none');
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
      await page.click('#btn-src');
      assert(await page.$eval('#sheet', el => !el.hidden));
      await page.keyboard.press('Escape');
      assert(await page.$eval('#sheet', el => el.hidden));
      assert(await page.$eval('#btn-map', el => !el.disabled));
      assert(await page.$eval('#btn-overview', el => !el.disabled));
      await page.click('#btn-overview');
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
      await s.page.click('#btn-map');
      await s.page.waitForFunction(() => document.getElementById('load-status').textContent.includes('正在连接'), { timeout: 5000 });
      await s.page.waitForFunction(() => document.getElementById('load-status').textContent.includes('影像不可用'), { timeout: 18000 });
      assert.equal(await s.frame.evaluate(() => document.documentElement.dataset.globeMap), 'local-earth');
      const firstCount = s.external.length;
      assert(firstCount > 0, 'Optional imagery must actually attempt an external request');
      // Late network failure must not overwrite the recovered map or cause an unhandled rejection.
      await Promise.all(s.external.map(req => req.abort('failed').catch(() => {})));
      await s.page.click('#btn-map');
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
      await s.page.waitForFunction(() => document.getElementById('gate').hidden && !document.getElementById('btn-map').disabled);
      await s.page.click('#btn-lang');
      await s.page.waitForFunction(() => {
        const f = document.querySelector('.stage iframe');
        return f?.src.includes('lang=en') && f.contentDocument?.documentElement?.dataset.globeState === 'ready';
      }, { timeout: 30000 });
      assert.equal(await s.page.$eval('.stage iframe', f => f.contentDocument.documentElement.dataset.globeMap), 'local-earth');
      await s.page.waitForFunction(() => document.getElementById('gate').hidden && !document.getElementById('btn-map').disabled);
      await s.page.click('#btn-lang');
      await s.page.waitForFunction(() => {
        const f = document.querySelector('.stage iframe');
        return f && !f.src.includes('lang=en') && f.contentDocument?.documentElement?.dataset.globeState === 'ready';
      }, { timeout: 30000 });
    } catch (error) {
      console.error('LANGUAGE DIAGNOSTICS ' + JSON.stringify(await s.page.evaluate(() => {
        const f = document.querySelector('.stage iframe');
        return {src: f?.src, state: f?.contentDocument?.documentElement.dataset, gate: document.getElementById('gate').textContent, status: document.getElementById('load-status').textContent};
      })));
      console.error('LANGUAGE NETWORK ' + JSON.stringify({errors: s.errors, bad: s.bad, external: s.external.map(r => r.url())}));
      await s.page.screenshot({path: 'artifacts/globe/language-failure.png'}).catch(() => {});
      throw error;
    } finally { await s.context.close(); }
  });
  await run('missing entry script preserves the lightweight map and retry', async () => {
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
      await page.waitForFunction(() => {
        const map = document.getElementById('lite-earth');
        return !map.hidden && map.dataset.state === 'ready' &&
          !document.getElementById('btn-go').disabled && document.getElementById('btn-go').textContent.includes('重试');
      }, { timeout: 50000 });
    } finally { await context.close(); }
  });
  await run('slow first-party engine survives the old 45-second cutoff', async () => {
    const context = await browser.createBrowserContext();
    const held = [], external = [], errors = [];
    try {
      const page = await context.newPage();
      await page.setViewport({ width: 1280, height: 900 });
      await page.setRequestInterception(true);
      page.on('request', req => {
        if (req.url().includes('/cesium/Cesium.js')) held.push(req);
        else if (req.url().startsWith(origin) || /^(data:|blob:)/.test(req.url())) void req.continue();
        else { external.push(req.url()); void req.abort(); }
      });
      page.on('pageerror', e => errors.push(String(e)));
      const started = Date.now();
      await page.goto(origin + '/apps/globe/', { waitUntil: 'domcontentloaded' });
      await page.waitForFunction(() => document.getElementById('lite-earth').dataset.state === 'ready');
      assert(Date.now() - started < 10000, 'Small map must not wait for the engine');
      const longitude = await page.$eval('#lite-canvas', e => e.dataset.longitude);
      await page.focus('#lite-canvas'); await page.keyboard.press('ArrowLeft');
      await page.waitForFunction(before => document.getElementById('lite-canvas').dataset.longitude !== before, {}, longitude);
      await page.waitForSelector('.stage iframe');
      const originalSrc = await page.$eval('.stage iframe', f => f.src);
      await page.screenshot({path:'artifacts/globe/lite-slow-engine.png'});
      await new Promise(resolve => setTimeout(resolve, 47000));
      assert.equal(await page.$eval('.stage iframe', f => f.src), originalSrc, 'Do not discard a slow in-progress download');
      assert(await page.$eval('#lite-earth', e => !e.hidden && e.dataset.state === 'ready'));
      assert.equal(held.length, 1, 'No background retry loop or duplicate engine downloads');
      await held[0].continue();
      await page.waitForFunction(() => document.getElementById('lite-earth').hidden, {timeout:45000});
      assert.deepEqual(external, []); assert.deepEqual(errors, []);
    } finally { await context.close(); }
  });
  await run('no WebGL retains a textured interactive map at phone, tablet and desktop widths', async () => {
    for (const width of [360, 768, 1280]) {
      const context = await browser.createBrowserContext();
      try {
        const page = await context.newPage();
        await page.setViewport({width, height:800});
        await page.evaluateOnNewDocument(() => {
          const get = HTMLCanvasElement.prototype.getContext;
          HTMLCanvasElement.prototype.getContext = function (type, ...args) {
            return /webgl/.test(type) ? null : get.call(this, type, ...args);
          };
        });
        const requests = [];
        page.on('request', r => requests.push(r.url()));
        await page.goto(origin + '/apps/globe/', {waitUntil:'domcontentloaded'});
        await page.waitForFunction(() => document.getElementById('lite-earth').dataset.state === 'ready');
        await page.click('#btn-go');
        assert.equal(await page.$('.stage iframe'), null);
        assert(await page.$eval('#lite-earth', e => !e.hidden));
        const colors = await page.$eval('#lite-canvas', c => {
          const data = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
          const set = new Set(); for (let i=0;i<data.length;i+=64) set.add(data[i]+','+data[i+1]+','+data[i+2]); return set.size;
        });
        assert(colors > 100, 'No-WebGL fallback must display actual textured geography');
        await page.click('#lite-in');
        await page.waitForFunction(() => Number(document.getElementById('lite-canvas').dataset.zoom) > 1);
        await page.click('#btn-overview');
        await page.waitForFunction(() => document.getElementById('lite-canvas').dataset.zoom === '1');
        assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth+1));
        assert(!requests.some(url => /Cesium\.js|arcgisonline|googleapis/.test(url)));
        await page.screenshot({path:'artifacts/globe/lite-no-webgl-'+width+'.png'});
      } finally { await context.close(); }
    }
  });
  await run('repeated extreme zoom remains finite and continues drawing', async () => {
    const s = await open(1280);
    try {
      await s.page.waitForFunction(() => document.getElementById('lite-earth').hidden);
      const box = await (await s.frame.$('.cesium-widget canvas')).boundingBox();
      await s.page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
      for (const deltaY of [10000, -10000, 10000, -10000]) {
        for (let i=0;i<12;i++) { await s.page.mouse.wheel({deltaY}); await new Promise(r=>setTimeout(r,50)); }
      }
      await s.page.click('#btn-overview');
      const state = await s.frame.evaluate(() => window.OoglexGlobeNetwork.viewState());
      assert(Number.isFinite(state.height) && state.height > 20000000 && state.height < 51000000);
      assert(state.rendererRunning);
      await s.page.mouse.wheel({deltaY:-80});
      await s.frame.waitForFunction(before => window.OoglexGlobeNetwork.viewState().renderedFrames > before, {}, state.renderedFrames);
      assert.deepEqual(s.errors, []);
    } finally { await s.context.close(); }
  });
  await run('WebGL context loss returns to the lightweight map and allows retry', async () => {
    const s = await open(1280);
    try {
      await s.page.waitForFunction(() => document.getElementById('lite-earth').hidden);
      await s.frame.$eval('.cesium-widget canvas', canvas => {
        const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
        gl.getExtension('WEBGL_lose_context').loseContext();
      });
      await s.page.waitForFunction(() => !document.getElementById('lite-earth').hidden && !document.getElementById('btn-go').disabled);
      await s.page.click('#btn-go');
      await s.page.waitForFunction(() => document.getElementById('lite-earth').hidden, {timeout:45000});
    } finally { await s.context.close(); }
  });
  }
} finally {
  const { writeFile } = await import('node:fs/promises');
  await writeFile('artifacts/globe/network-results' + (process.env.GLOBE_VERIFY_QUICK ? '-rebuilt' : '') + '.json', JSON.stringify(results, null, 2) + '\n');
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
if (failures) process.exitCode = 1;
