import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawn, execFileSync } from 'node:child_process';

const ROOT = process.cwd();
const PORT = 8877;
const APP_PATH = '/apps/global-cams/app.js';
const CONFIG_PATH = '/apps/global-cams/config.js';
const widths = [360, 768, 1280];

function findChrome() {
  for (const name of ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser']) {
    try {
      const p = execFileSync('which', [name], { encoding: 'utf8' }).trim();
      if (p) return p;
    } catch {}
  }
  return '';
}

function mime(file) {
  const ext = path.extname(file).toLowerCase();
  return ({
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.mjs': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.css': 'text/css; charset=utf-8'
  })[ext] || 'application/octet-stream';
}

const preamble = `
window.__gcSmokeErrors = [];
window.addEventListener('error', e => window.__gcSmokeErrors.push(String(e.message || e.error || 'error')));
window.addEventListener('unhandledrejection', e => window.__gcSmokeErrors.push(String(e.reason || 'unhandled rejection')));
`;

const probe = `
setTimeout(() => {
  const rect = sel => {
    const n = document.querySelector(sel);
    if (!n) return null;
    const r = n.getBoundingClientRect();
    return {left:r.left,top:r.top,right:r.right,bottom:r.bottom,width:r.width,height:r.height};
  };
  const within = r => !!r && r.left >= -1 && r.top >= -1 && r.right <= innerWidth + 1 && r.bottom <= innerHeight + 1;
  const controls = ['#loadNearby','#search','#zoomIn','#zoomOut','#resetGlobe','#fullscreen'];
  const result = {
    width: innerWidth,
    height: innerHeight,
    docWidth: document.documentElement.scrollWidth,
    bodyWidth: document.body.scrollWidth,
    rows: document.querySelectorAll('.cam-row').length,
    filters: document.querySelectorAll('.filter-btn').length,
    activeFilters: document.querySelectorAll('.filter-btn.active').length,
    version: (document.querySelector('.brand')?.textContent || '').trim(),
    errors: window.__gcSmokeErrors || [],
    sidebar: rect('.sidebar'),
    stage: rect('.stage'),
    viewer: rect('#viewer'),
    playlist: rect('#playlist'),
    controlsInsideViewport: controls.every(s => within(rect(s)))
  };
  const pre = document.createElement('pre');
  pre.id = 'gc-smoke-result';
  pre.textContent = btoa(unescape(encodeURIComponent(JSON.stringify(result))));
  document.body.appendChild(pre);
}, 1500);
`;

const server = http.createServer((req, res) => {
  const pathname = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
  if (pathname === CONFIG_PATH) {
    res.writeHead(200, {'Content-Type':'text/javascript; charset=utf-8','Cache-Control':'no-store'});
    res.end('window.OOGLEX_GLOBAL_CAMS = Object.freeze({apiBase:""});');
    return;
  }

  let filePath = path.join(ROOT, pathname === '/' ? 'index.html' : pathname.replace(/^\//, ''));
  if (pathname.endsWith('/')) filePath = path.join(ROOT, pathname.replace(/^\//, ''), 'index.html');
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403); res.end('forbidden'); return;
  }
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    res.writeHead(404); res.end('not found'); return;
  }

  let body = fs.readFileSync(filePath);
  if (pathname === APP_PATH) {
    body = Buffer.from(preamble + '\n' + body.toString('utf8') + '\n' + probe);
  }
  res.writeHead(200, {'Content-Type': mime(filePath), 'Cache-Control':'no-store'});
  res.end(body);
});

function runChrome(chrome, width) {
  return new Promise((resolve, reject) => {
    const height = width <= 480 ? 800 : width <= 800 ? 900 : 820;
    const args = [
      '--headless=new','--no-sandbox','--disable-gpu','--disable-dev-shm-usage',
      '--hide-scrollbars','--virtual-time-budget=4000',
      '--window-size=' + width + ',' + height,
      '--dump-dom',
      'http://127.0.0.1:' + PORT + '/apps/global-cams/?smoke=' + width
    ];
    const p = spawn(chrome, args, { stdio: ['ignore','pipe','pipe'] });
    let out = '', err = '';
    p.stdout.on('data', d => out += d);
    p.stderr.on('data', d => err += d);
    p.on('error', reject);
    p.on('close', code => code === 0 ? resolve(out) : reject(new Error('Chrome ' + width + ' exited ' + code + ': ' + err.slice(-500))));
  });
}

function parseResult(dom) {
  const m = dom.match(/<pre id="gc-smoke-result">([^<]+)<\/pre>/);
  if (!m) throw new Error('smoke probe result missing');
  return JSON.parse(decodeURIComponent(escape(Buffer.from(m[1], 'base64').toString('binary'))));
}

const chrome = findChrome();
if (!chrome) {
  console.error('Chrome/Chromium not available');
  process.exit(2);
}

await new Promise(resolve => server.listen(PORT, '127.0.0.1', resolve));
const failures = [];

try {
  for (const width of widths) {
    const dom = await runChrome(chrome, width);
    const r = parseResult(dom);
    const desktop = width > 820;

    if (!r.version.includes('V0.6')) failures.push(width + ': V0.6 label missing');
    if (!dom.includes('id="modeLive"') || !dom.includes('id="modeWindow"')) failures.push(width + ': LIVE/WINDOW mode controls missing');
    if (r.filters !== 4 || r.activeFilters !== 1) failures.push(width + ': media filter controls invalid');
    if (r.rows < 1) failures.push(width + ': playlist did not render demo rows');
    if (r.errors.length) failures.push(width + ': browser errors: ' + r.errors.join(' | '));
    if (r.docWidth > r.width + 1 || r.bodyWidth > r.width + 1) failures.push(width + ': horizontal overflow');
    if (!r.controlsInsideViewport) failures.push(width + ': key controls outside viewport');
    if (!r.sidebar || !r.stage || r.sidebar.width < 1 || r.stage.width < 1) failures.push(width + ': missing sidebar/stage geometry');
    if (!r.viewer || !r.playlist || r.viewer.height < 1 || r.playlist.height < 1) failures.push(width + ': viewer/playlist not visible');

    if (r.sidebar && r.stage) {
      if (desktop && Math.abs(r.sidebar.right - r.stage.left) > 2) failures.push(width + ': desktop sidebar/stage not side-by-side');
      if (!desktop && Math.abs(r.stage.bottom - r.sidebar.top) > 2) failures.push(width + ': mobile stage/sidebar not stacked');
    }

    console.log('Global Cams smoke', width, {
      rows: r.rows,
      docWidth: r.docWidth,
      sidebar: r.sidebar && [Math.round(r.sidebar.width), Math.round(r.sidebar.height)],
      stage: r.stage && [Math.round(r.stage.width), Math.round(r.stage.height)]
    });
  }
} finally {
  server.close();
}

if (failures.length) {
  console.error('Global Cams responsive smoke failed:');
  failures.forEach(x => console.error(' - ' + x));
  process.exit(1);
}
console.log('Global Cams responsive smoke passed at 360 / 768 / 1280.');
