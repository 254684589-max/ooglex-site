import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = process.cwd();
const PORT = 8877;
const APP_PATH = '/apps/global-cams/app.js';
const CONFIG_PATH = '/apps/global-cams/config.js';
const widths = [360, 768, 1280];

function findChrome() {
  const candidates = [
    '/opt/google/chrome/chrome',
    'google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser'
  ];
  for (const name of candidates) {
    if (name.startsWith('/') && fs.existsSync(name)) return name;
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
    '.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8',
    '.mjs':'text/javascript; charset=utf-8','.json':'application/json; charset=utf-8',
    '.jpg':'image/jpeg','.jpeg':'image/jpeg','.png':'image/png','.svg':'image/svg+xml',
    '.css':'text/css; charset=utf-8','.webm':'video/webm','.mp4':'video/mp4'
  })[ext] || 'application/octet-stream';
}

const preamble = `
window.__gcSmokeErrors = [];
window.addEventListener('error', e => window.__gcSmokeErrors.push(String(e.message || e.error || 'error')));
window.addEventListener('unhandledrejection', e => window.__gcSmokeErrors.push(String(e.reason || 'unhandled rejection')));
`;

const probe = `
function __gcRect(sel) {
  const n = document.querySelector(sel);
  if (!n) return null;
  const r = n.getBoundingClientRect();
  return {left:r.left,top:r.top,right:r.right,bottom:r.bottom,width:r.width,height:r.height};
}
function __gcCenterGiants(viewer) {
  const vr = viewer.getBoundingClientRect();
  const cx = vr.left + vr.width / 2;
  const cy = vr.top + vr.height / 2;
  const bad = [];
  viewer.querySelectorAll('*').forEach(el => {
    if (el.tagName === 'VIDEO') return;
    if (el.classList.contains('viewer-shield')) return;
    if (el.classList.contains('viewer-progress') || el.classList.contains('viewer-progress-bar')) return;
    const r = el.getBoundingClientRect();
    if (r.width < 72 || r.height < 72) return;
    if (r.left <= cx && r.right >= cx && r.top <= cy && r.bottom >= cy) bad.push(el.className || el.tagName);
  });
  return bad;
}
function __gcSwipe(viewer) {
  const r = viewer.getBoundingClientRect();
  const x = r.left + r.width / 2;
  const y0 = r.top + r.height * 0.78;
  const y1 = r.top + r.height * 0.18;
  const fire = (type, y) => {
    const t = new Touch({
      identifier: 1, target: viewer, clientX: x, clientY: y, pageX: x, pageY: y,
      screenX: x, screenY: y, radiusX: 1, radiusY: 1, rotationAngle: 0, force: 1
    });
    viewer.dispatchEvent(new TouchEvent(type, {
      bubbles: true, cancelable: true,
      touches: type === 'touchend' ? [] : [t],
      targetTouches: type === 'touchend' ? [] : [t],
      changedTouches: [t]
    }));
  };
  fire('touchstart', y0);
  fire('touchmove', (y0 + y1) / 2);
  fire('touchend', y1);
}
function __gcVideoState(video) {
  if (!video) return null;
  const overlay = getComputedStyle(video, '::-webkit-media-controls-overlay-play-button');
  const toggle = document.querySelector('#viewer [data-viewer-action="toggle"]');
  const tr = toggle ? toggle.getBoundingClientRect() : null;
  return {
    controls: video.controls,
    controlsAttr: video.hasAttribute('controls'),
    posterOk: String(video.getAttribute('poster') || '').indexOf('data:image/gif;base64,R0lGODlhAQAB') === 0,
    x5Playsinline: video.hasAttribute('x5-playsinline'),
    x5Type: video.getAttribute('x5-video-player-type') || '',
    pointerEvents: getComputedStyle(video).pointerEvents,
    paused: video.paused,
    src: video.currentSrc || video.src || '',
    overlayDisplay: overlay.display || '',
    overlayWidth: overlay.width || '',
    overlayOpacity: overlay.opacity || '',
    overlayVisibility: overlay.visibility || '',
    muted: video.muted,
    readyState: video.readyState,
    error: video.error ? String(video.error.code) : '',
    giants: __gcCenterGiants(document.querySelector('#viewer')),
    progress: !!document.querySelector('#viewer .viewer-progress'),
    toggleH: tr ? Math.round(tr.height) : 0,
    toggleW: tr ? Math.round(tr.width) : 0
  };
}
function __gcReleaseVideo() {
  const video = document.querySelector('#viewer video');
  if (!video) return;
  try { video.pause(); } catch (e) {}
  video.removeAttribute('src');
  try { video.load(); } catch (e) {}
}
function __gcPublish(result) {
  const pre = document.createElement('pre');
  pre.id = 'gc-smoke-result';
  pre.textContent = btoa(unescape(encodeURIComponent(JSON.stringify(result))));
  document.body.appendChild(pre);
  __gcReleaseVideo();
}
(function __gcWaitRows(attempt) {
  const row = document.querySelector('.window-row');
  if (!row) {
    if (attempt < 80) {
      setTimeout(() => __gcWaitRows(attempt + 1), 100);
      return;
    }
  }
  const viewer = document.querySelector('#viewer');
  if (row) row.click();
  const first = document.querySelector('#viewer video');
  const firstSrc = first ? (first.currentSrc || first.src || '') : '';
  let swipe = 'none';
  try {
    if (innerWidth <= 820) {
      __gcSwipe(viewer);
      const after = document.querySelector('#viewer video');
      const afterSrc = after ? (after.currentSrc || after.src || '') : '';
      if (afterSrc && afterSrc !== firstSrc) swipe = 'touch';
    }
  } catch (err) {
    swipe = 'none';
  }
  if (swipe !== 'touch') {
    const next = document.querySelector('#viewer [data-viewer-action="next"]');
    if (next) {
      next.click();
      swipe = 'button';
    }
  }
  window.scrollTo(0, 0);
  const playing = __gcVideoState(document.querySelector('#viewer video'));
  const srcChanged = !!(playing && playing.src && firstSrc && playing.src !== firstSrc);
  setTimeout(() => {
    window.scrollTo(0, 0);
    const shield = document.querySelector('#viewer .viewer-shield');
    if (shield) shield.click();
    const revealed = __gcVideoState(document.querySelector('#viewer video'));
    const within = r => !!r && r.left >= -1 && r.top >= -1 && r.right <= innerWidth + 1 && r.bottom <= innerHeight + 1;
    const controls = innerWidth > 820 ? ['#search','#zoomIn','#zoomOut','#resetGlobe','#fullscreen'] : ['#expandViewer','#openSource'];
    const result = {
      width: innerWidth,
      height: innerHeight,
      docWidth: document.documentElement.scrollWidth,
      bodyWidth: document.body.scrollWidth,
      rows: document.querySelectorAll('.window-row').length,
      version: (document.querySelector('.brand')?.textContent || '').trim(),
      windowOnly: (document.querySelector('.window-only')?.textContent || '').trim(),
      liveControls: document.querySelectorAll('#modeLive,#loadNearby,#mediaFilters').length,
      sortTabs: document.querySelectorAll('.sort-btn').length,
      activeSortTabs: document.querySelectorAll('.sort-btn.active').length,
      errors: window.__gcSmokeErrors || [],
      sidebar: __gcRect('.sidebar'),
      stage: __gcRect('.stage'),
      viewer: __gcRect('#viewer'),
      playlist: __gcRect('#playlist'),
      controlsInsideViewport: controls.every(s => within(__gcRect(s))),
      videoCount: document.querySelectorAll('#viewer video').length,
      swipe,
      srcChanged,
      playing,
      revealed,
      chromeOn: viewer.classList.contains('is-chrome'),
      immersive: viewer.classList.contains('is-immersive')
    };
    __gcPublish(result);
  }, 700);
})(0);
`;

const SMOKE_VIDEO = path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures', 'gc-smoke-color.mp4');

const server = http.createServer((req, res) => {
  const pathname = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
  if (pathname === '/__gc_smoke_video.mp4') {
    const buf = fs.readFileSync(SMOKE_VIDEO);
    const match = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range || '');
    if (match) {
      const start = Number(match[1]);
      const end = match[2] ? Number(match[2]) : buf.length - 1;
      res.writeHead(206, {
        'Content-Type': 'video/mp4',
        'Content-Range': 'bytes ' + start + '-' + end + '/' + buf.length,
        'Content-Length': String(end - start + 1),
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-store'
      });
      res.end(buf.subarray(start, end + 1));
      return;
    }
    res.writeHead(200, {
      'Content-Type': 'video/mp4',
      'Content-Length': String(buf.length),
      'Accept-Ranges': 'bytes',
      'Cache-Control': 'no-store'
    });
    res.end(buf);
    return;
  }
  if (pathname === CONFIG_PATH) {
    res.writeHead(200, {'Content-Type':'text/javascript; charset=utf-8','Cache-Control':'no-store'});
    res.end('window.OOGLEX_GLOBAL_CAMS = Object.freeze({windowCdnBase:""});');
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
  if (pathname === '/apps/global-cams/windows.json') {
    const data = JSON.parse(body.toString('utf8'));
    data.forEach((item, i) => {
      item.video_url = 'http://127.0.0.1:' + PORT + '/__gc_smoke_video.mp4?i=' + i;
    });
    body = Buffer.from(JSON.stringify(data));
  }
  if (pathname === APP_PATH) {
    body = Buffer.from(preamble + '\n' + body.toString('utf8') + '\n' + probe);
  }
  res.writeHead(200, {'Content-Type': mime(filePath), 'Cache-Control':'no-store'});
  res.end(body);
});

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function cdpValue(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const timer = setTimeout(() => {
      try { ws.close(); } catch {}
      reject(new Error('cdp evaluate stalled'));
    }, 4000);
    ws.addEventListener('open', () => {
      ws.send(JSON.stringify({
        id: 1,
        method: 'Runtime.evaluate',
        params: {
          expression: "document.getElementById('gc-smoke-result') && document.getElementById('gc-smoke-result').textContent",
          returnByValue: true
        }
      }));
    });
    ws.addEventListener('message', event => {
      let msg;
      try { msg = JSON.parse(String(event.data)); } catch { return; }
      if (msg.id !== 1) return;
      clearTimeout(timer);
      try { ws.close(); } catch {}
      const value = msg.result && msg.result.result ? msg.result.result.value : '';
      resolve(value || '');
    });
    ws.addEventListener('error', () => {
      clearTimeout(timer);
      reject(new Error('cdp websocket failed'));
    });
  });
}

async function readSmokeResult(port) {
  const res = await fetch('http://127.0.0.1:' + port + '/json/list');
  if (!res.ok) return '';
  const pages = await res.json();
  for (const page of pages) {
    if (!page || page.type !== 'page' || !page.webSocketDebuggerUrl) continue;
    const value = await cdpValue(page.webSocketDebuggerUrl);
    if (value) return value;
  }
  return '';
}

// 不用 --virtual-time-budget / --dump-dom。视频一开始循环播放，
// 部分 CI 上的 Chrome 会把虚拟时间停住，dump-dom 永远不返回，30 秒后被杀掉。
// 这里用真实时间等页面写下结果，每档最多 45 秒。
function runChrome(chrome, width) {
  return new Promise((resolve, reject) => {
    const height = width <= 480 ? 800 : width <= 800 ? 900 : 820;
    const port = 36000 + width;
    const args = [
      '--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage',
      '--hide-scrollbars', '--no-first-run', '--disable-background-networking',
      '--autoplay-policy=no-user-gesture-required',
      '--remote-debugging-address=127.0.0.1',
      '--remote-debugging-port=' + port,
      '--remote-allow-origins=*',
      '--user-data-dir=' + path.join(os.tmpdir(), 'gc-smoke-chrome-' + width + '-' + process.pid),
      '--window-size=' + width + ',' + height,
      'http://127.0.0.1:' + PORT + '/apps/global-cams/?smoke=' + width
    ];
    const p = spawn(chrome, args, { stdio: ['ignore', 'ignore', 'pipe'], detached: true });
    let err = '';
    let done = false;
    p.stderr.on('data', d => { err = (err + d).slice(-1500); });
    const stop = () => {
      try { process.kill(-p.pid, 'SIGKILL'); } catch { try { p.kill('SIGKILL'); } catch {} }
    };
    const finish = (error, value) => {
      if (done) return;
      done = true;
      clearTimeout(wall);
      stop();
      if (error) reject(error);
      else resolve(value);
    };
    const wall = setTimeout(() => {
      finish(new Error('Chrome ' + width + ' timed out waiting for smoke result. ' + err.trim().slice(-400)));
    }, 45000);
    p.on('error', error => finish(error));
    p.on('exit', code => {
      if (done) return;
      setTimeout(() => {
        if (!done) finish(new Error('Chrome ' + width + ' exited ' + code + ' before smoke result. ' + err.trim().slice(-400)));
      }, 400);
    });
    (async () => {
      const started = Date.now();
      while (!done && Date.now() - started < 44000) {
        try {
          const text = await readSmokeResult(port);
          if (text) {
            finish(null, text);
            return;
          }
        } catch {}
        await sleep(200);
      }
    })().catch(error => finish(error));
  });
}

function parseResult(encoded) {
  if (!encoded) throw new Error('smoke probe result missing');
  return JSON.parse(decodeURIComponent(escape(Buffer.from(encoded, 'base64').toString('binary'))));
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

    if (!r.version.includes('V1.1')) failures.push(width + ': V1.1 label missing');
    if (r.windowOnly !== 'WINDOW ONLY') failures.push(width + ': WINDOW ONLY badge missing');
    if (r.liveControls !== 0) failures.push(width + ': camera controls still rendered');
    if (r.sortTabs !== 3 || r.activeSortTabs !== 1) failures.push(width + ': WINDOW sort tabs invalid');
    if (r.rows < 5) failures.push(width + ': WINDOW playlist did not render seed rows');
    if (r.errors.length) failures.push(width + ': browser errors: ' + r.errors.join(' | '));
    if (r.docWidth > r.width + 1 || r.bodyWidth > r.width + 1) failures.push(width + ': horizontal overflow');
    if (!r.controlsInsideViewport) failures.push(width + ': key controls outside viewport');
    if (!r.sidebar || !r.stage || r.sidebar.width < 1 || r.stage.width < 1) failures.push(width + ': missing sidebar/stage geometry');
    if (!r.viewer || !r.playlist || r.viewer.height < 1 || r.playlist.height < 1) failures.push(width + ': viewer/playlist not visible');
    if (r.videoCount !== 1) failures.push(width + ': expected one viewer video, got ' + r.videoCount);
    const play = r.playing || {};
    const shown = r.revealed || {};
    if (play.controls !== false || shown.controls !== false) failures.push(width + ': native controls turned on while playing or swiping');
    if (play.controlsAttr || shown.controlsAttr) failures.push(width + ': controls attribute present during playback');
    if (!play.posterOk || !shown.posterOk) failures.push(width + ': transparent poster missing, Android default play poster can return');
    if (play.x5Playsinline || shown.x5Playsinline) failures.push(width + ': x5-playsinline re-enabled the native play overlay');
    if (play.x5Type !== 'h5-page') failures.push(width + ': same-layer player type missing');
    if (play.pointerEvents !== 'none') failures.push(width + ': video still receives hits');
    if ((play.giants || []).length || (shown.giants || []).length) failures.push(width + ': center overlay is visible: ' + (play.giants || []).concat(shown.giants || []).join(','));
    if (!play.progress) failures.push(width + ': bottom progress missing');
    if (!r.srcChanged) failures.push(width + ': vertical swipe / next did not change window (' + r.swipe + ')');
    if (play.toggleH > 48 || shown.toggleH > 48) failures.push(width + ': play control is oversized (' + play.toggleH + '/' + shown.toggleH + 'px)');
    if (!desktop && r.immersive && !r.chromeOn) failures.push(width + ': tap did not reveal lightweight controls');
    if (shown.paused) failures.push(width + ': video stayed paused after swipe, so the native play poster can remain');

    if (r.sidebar && r.stage) {
      if (desktop && Math.abs(r.sidebar.right - r.stage.left) > 2) failures.push(width + ': desktop sidebar/stage not side-by-side');
      if (!desktop && Math.abs(r.sidebar.bottom - r.stage.top) > 2) failures.push(width + ': mobile video-first sidebar/stage not stacked');
    }

    console.log('Global WINDOW smoke', width, {
      rows: r.rows,
      docWidth: r.docWidth,
      swipe: r.swipe,
      srcChanged: r.srcChanged,
      paused: r.playing && r.playing.paused,
      pausedAfter: r.revealed && r.revealed.paused,
      chromeOn: r.chromeOn,
      playback: r.revealed && {
        paused: r.revealed.paused,
        muted: r.revealed.muted,
        ready: r.revealed.readyState,
        error: r.revealed.error
      },
      giants: r.playing && r.playing.giants,
      sidebar: r.sidebar && [Math.round(r.sidebar.width), Math.round(r.sidebar.height)],
      stage: r.stage && [Math.round(r.stage.width), Math.round(r.stage.height)]
    });
  }
} finally {
  server.close();
}

if (failures.length) {
  console.error('Global WINDOW responsive smoke failed:');
  failures.forEach(x => console.error(' - ' + x));
  process.exit(1);
}
console.log('Global WINDOW responsive smoke passed at 360 / 768 / 1280.');
