/* 中文化覆盖率闸门
 * ---------------------------------------------------------------------------
 * 「面板里还有英文」以前只能靠人肉截图发现 —— 打开某个平时不看的面板，就冒出一个
 * 没翻的标签。这条闸门把它变成确定性断言：
 *
 *   1. 读构建产物 apps/globe/app/index.html —— 作者写死的界面文案都在里面；
 *   2. 用真正的 DOMParser 解析（不是正则），按元素逐个收集可翻译文案：
 *      文本节点 + title / aria-label / placeholder / alt；
 *   3. 跳过图标连字（Material Symbols 用 `arrow_forward` 这样的**内容**当图标）、
 *      署名子树（许可要求原样保留）、脚本与样式；
 *   4. 把每条文案交给页面里活着的 i18n 层问一句「查得到中文吗」；
 *   5. 查不到、又不在 ALLOW（确有理由保持英文的专名/读数）里的，就是漏翻。
 *
 * 之所以要 3)：DICT 是**白名单**，绝不做子串替换 —— 否则图标连字会被翻成乱码文字。
 * 之所以要 4)：翻译规则里有锚定正则（组合串），只查字典会漏判。
 *
 * 常见的真实漏翻成因（都栽过）：
 *   · CSS 有 text-transform:uppercase —— 截图上是 MODELS，DOM 里其实是 Models，
 *     字典按截图写成大写就永远命中不了；
 *   · 组合串（「... / MAPPED PROXIMITY」）只把里面的单词加进字典没用，
 *     必须整串入典或写锚定正则。
 *
 * 用法：node scripts/globe/verify-i18n-coverage.mjs
 * （自带静态服务器，和 verify-network.mjs 一样，不依赖外部起的 http.server）
 */
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { resolve, extname, sep } from 'node:path';
import { launchGlobeBrowser } from './browser.mjs';

const REPO = resolve('.');
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.jpg': 'image/jpeg', '.png': 'image/png',
  '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.wasm': 'application/wasm',
  '.xml': 'application/xml' };
const server = createServer(async (req, res) => {
  try {
    let file = resolve(REPO, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname));
    if (!file.startsWith(REPO + sep)) { res.writeHead(403).end(); return; }
    if ((await stat(file)).isDirectory()) file = resolve(file, 'index.html');
    res.writeHead(200, { 'Content-Type': mime[extname(file)] || 'application/octet-stream' });
    res.end(await readFile(file));
  } catch { res.writeHead(404).end('Not found'); }
});
await new Promise(done => server.listen(0, '127.0.0.1', done));
const BASE = 'http://127.0.0.1:' + server.address().port;

/* 确有理由保持英文的文案。**只列真正命中的那几条** —— 不预先堆一堆「可能用得上」的
 * 缩写：白名单越宽，闸门越弱（将来真冒出一个没翻的 `KM` 会被静默放过）。
 * 构建产物换了之后若有新的英文文案，闸门会红 —— 那时逐条决定「翻」还是「入白名单
 * 并写明理由」，正是想要的行为。 */
const ALLOW = new Set([
  // 数据源专名：出处标识，翻译会让人查不到源头，也可能踩署名要求
  'OpenSky', 'adsb.lol', 'AISStream', 'OpenStreetMap',
  // Open-Meteo 天气数据的出处标签（旁边那句连接词已翻成「天气数据来自 …」）
  'OPEN-METEO',
  // 视觉预设名。CRT 在中文技术语境里就写 CRT（「显像管」反而更难认）；
  // 同组的 NVG→夜视、FLIR→热成像都翻了，唯独这条保持原样是刻意的。
  'CRT',
]);

/* 这些子树里的文字是许可要求的署名，与 i18n-zh.js 的 SKIP_SELECTORS 保持一致。 */
const SKIP = [
  '#cesium-credits', '.cesium-widget-credits', '.cesium-credit-lightbox',
  '.cesium-credit-lightbox-overlay', '[data-no-translate]',
];
/* 图标是用**元素内容**当连字名渲染的，内容绝不能翻。 */
const ICON = ['.material-symbols-outlined', '.pp-icon', '.btn-icon', '.dock-label-icon', '.first-run-arrow'];

const html = readFileSync(resolve(REPO, 'apps/globe/app/index.html'), 'utf8');
const browser = await launchGlobeBrowser();
let failed = 0;
try {
  // ——— 1) 在一个空白页里用真 DOMParser 抽取候选文案
  const parser = await browser.newPage();
  await parser.goto('about:blank');
  const candidates = await parser.evaluate((src, skip, icon) => {
    const doc = new DOMParser().parseFromString(src, 'text/html');
    doc.querySelectorAll('script,style,template,noscript').forEach(n => n.remove());
    const ATTRS = ['title', 'aria-label', 'placeholder', 'alt'];
    const skipped = (el) => {
      for (let e = el; e; e = e.parentElement) {
        for (const s of skip.concat(icon)) { try { if (e.matches(s)) return true; } catch (_) {} }
      }
      return false;
    };
    const out = new Map();           // 文案 -> 第一次出现的位置，报错时好定位
    const where = (el) => {
      const bits = [];
      for (let e = el; e && bits.length < 3; e = e.parentElement) {
        bits.unshift(e.id ? '#' + e.id : e.tagName.toLowerCase() + (e.className && typeof e.className === 'string' ? '.' + e.className.trim().split(/\s+/)[0] : ''));
      }
      return bits.join(' > ');
    };
    const add = (text, el, kind) => {
      const k = String(text || '').replace(/\s+/g, ' ').trim();
      if (!k || k.length > 200) return;
      if (!/[A-Za-z]{2}/.test(k)) return;                  // 没有字母 —— 纯数字/符号，不是文案
      if (/^[a-z][a-z0-9_]*$/.test(k) && !k.includes(' ')) return;  // 图标连字形状（arrow_forward）
      if (!out.has(k)) out.set(k, kind + ' @ ' + where(el));
    };
    const tw = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
    let n;
    while ((n = tw.nextNode())) {
      if (n.nodeType === 3) {
        const el = n.parentElement;
        if (el && !skipped(el)) add(n.nodeValue, el, 'text');
      } else {
        if (skipped(n)) continue;
        for (const a of ATTRS) if (n.hasAttribute(a)) add(n.getAttribute(a), n, a);
      }
    }
    return [...out].map(([text, at]) => ({ text, at }));
  }, html, SKIP, ICON);
  await parser.close();
  console.log(`从构建产物里抽出 ${candidates.length} 条界面文案`);

  // ——— 2) 打开应用，让活着的 i18n 层逐条回答
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });
  await page.setRequestInterception(true);
  page.on('request', r => {
    const u = r.url();
    if (u.startsWith('http') && !u.includes('127.0.0.1')) return r.abort();  // 按大陆无外网跑
    r.continue();
  });
  await page.goto(`${BASE}/apps/globe/`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  if (!(await page.$('.stage iframe'))) {
    await page.waitForSelector('#btn-go', { timeout: 20000 });
    await page.click('#btn-go');
  }
  let frame = null;
  for (let i = 0; i < 200 && !frame; i++) {
    frame = page.frames().find(f => f.url().includes('/apps/globe/app/')) || null;
    if (!frame) await new Promise(r => setTimeout(r, 250));
  }
  if (!frame) throw new Error('应用 iframe 没出现');
  await frame.waitForFunction(() => !!window.OoglexGlobeI18n, { timeout: 60000 });
  const dictSize = await frame.evaluate(() => window.OoglexGlobeI18n.size);
  const missing = await frame.evaluate(
    (list) => list.filter(c => {
      const hit = window.OoglexGlobeI18n.translate(c.text);
      return hit === null || hit === undefined || hit === c.text;
    }),
    candidates);
  await page.close();

  const real = missing.filter(m => !ALLOW.has(m.text));
  console.log('命中 ALLOW 的：' + JSON.stringify(missing.filter(m => ALLOW.has(m.text)).map(m => m.text)));
  console.log(`字典 ${dictSize} 条；查不到 ${missing.length} 条，其中 ${real.length} 条不在 ALLOW 白名单里`);
  if (real.length) {
    failed = 1;
    console.log('\n漏翻（按出现位置）:');
    for (const m of real) console.log(`  ✗ ${JSON.stringify(m.text)}\n      ${m.at}`);
    console.log(`\n共 ${real.length} 条。把它们加进 scripts/globe/i18n-zh.js 的 DICT，`);
    console.log('或者——确有理由保持英文的话——加进本文件的 ALLOW 并写明理由。');
  } else {
    console.log('✓ 作者写死的界面文案全部有中文');
  }
} finally {
  await browser.close();
  server.close();
}
process.exit(failed);
