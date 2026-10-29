// Real Chrome + HTMLAudioElement. Fixture audio/catalog remain in this HTTP server only.
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import os from 'node:os';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';

const root = process.cwd(), results = [], errors = [];
let browserVersion = '';
const out = process.env.MUSIC_TEST_OUTPUT || path.join(os.tmpdir(), 'ooglex-music-smoke');
fs.mkdirSync(out, { recursive: true });
const tracks = Array.from({ length: 12 }, (_, i) => ({ id: 't' + i, title: 'Test ' + i, artist: 'Test artist', src: '/apps/music-player/media/fixture/' + i + '.wav', durationSec: 2 }));
const catalog = { albums: [{ id: 'test', title: 'Test playlist', artist: 'Test artist', released: true, tracks }] };
const wav = Buffer.alloc(44 + 16000 * 2 * 2);
wav.write('RIFF'); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
wav.writeUInt32LE(16000, 24); wav.writeUInt32LE(32000, 28); wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
wav.write('data', 36); wav.writeUInt32LE(wav.length - 44, 40);
for (let i = 44; i < wav.length; i += 2) wav.writeInt16LE(Math.round(Math.sin((i - 44) / 2 * Math.PI * 440 / 8000) * 1000), i);
let failures = false;
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost'), file = url.pathname;
  if (file.endsWith('/data/catalog.json')) { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(catalog)); return; }
  if (file.endsWith('/data/global.json')) { res.setHeader('Content-Type', 'application/json'); res.end('{"api":"","genres":[]}'); return; }
  if (file.startsWith('/apps/music-player/media/fixture/')) {
    if (failures) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': 'audio/wav', 'Content-Length': wav.length, 'Cache-Control': 'no-store' }); res.end(wav); return;
  }
  let filename = path.join(root, decodeURIComponent(file));
  if (!filename.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
  try {
    if (fs.statSync(filename).isDirectory()) filename = path.join(filename, 'index.html');
    const ext = path.extname(filename); res.setHeader('Content-Type', ({ '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html' })[ext] || 'application/octet-stream');
    res.end(fs.readFileSync(filename));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const base = 'http://127.0.0.1:' + server.address().port;
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'ooglex-chrome-'));
const chrome = spawn(process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', '--remote-debugging-port=0', '--user-data-dir=' + profile,
  '--no-first-run', '--no-default-browser-check', '--mute-audio', 'about:blank'
], { stdio: ['ignore', 'ignore', 'pipe'] });
let socket;
const wait = ms => new Promise(r => setTimeout(r, ms));
try {
  const endpoint = await new Promise((resolve, reject) => {
    let log = ''; const timer = setTimeout(() => reject(Error('Chrome startup timeout: ' + log.slice(-1000))), 20000);
    chrome.stderr.on('data', chunk => { log += chunk; const m = /DevTools listening on (ws:\/\/[^\s]+)/.exec(log); if (m) { clearTimeout(timer); resolve(m[1]); } });
    chrome.on('error', reject);
  });
  socket = new WebSocket(endpoint); await new Promise((r, reject) => { socket.onopen = r; socket.onerror = reject; });
  let id = 0, session, pending = new Map();
  socket.onmessage = ({ data }) => { const m = JSON.parse(data); if (m.id) { const p = pending.get(m.id); pending.delete(m.id); if (m.error) p.reject(Error(JSON.stringify(m.error))); else p.resolve(m.result); }
    else if (m.method === 'Runtime.exceptionThrown') errors.push(m.params.exceptionDetails.text + ': ' + (m.params.exceptionDetails.exception?.description || ''));
  };
  const send = (method, params = {}, sid = session) => new Promise((resolve, reject) => { const mid = ++id; pending.set(mid, { resolve, reject }); socket.send(JSON.stringify({ id: mid, method, params, ...(sid ? { sessionId: sid } : {}) })); });
  const target = await send('Target.createTarget', { url: 'about:blank' });
  session = (await send('Target.attachToTarget', { targetId: target.targetId, flatten: true })).sessionId;
  await send('Runtime.enable'); await send('Page.enable'); await send('Network.enable');
  const evaluate = async (expression, gesture = false) => {
    const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true, userGesture: gesture });
    if (r.exceptionDetails) throw Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
    return r.result.value;
  };
  const until = async (expression, timeout = 6000) => { const start = Date.now(); while (!(await evaluate(expression))) { if (Date.now() - start > timeout) throw Error('Timeout: ' + expression); await wait(30); } };
  const record = name => { results.push({ name, status: 'PASS' }); console.log('PASS', name); };
  await send('Page.navigate', { url: base + '/apps/music-player/#/album/test' });
  await until('document.querySelectorAll(".track").length === 12');
  assert.equal(await evaluate('document.querySelector("audio").paused && !document.querySelector("audio").src'), true);
  record('首次打开不自动播放');
  await evaluate('document.querySelector(".play-all").click()', true);
  await until('document.querySelector("audio").currentTime > 0');
  await until('document.querySelector("#now-title").textContent === "Test 1"');
  record('真实音频自然 ended 自动播放下一首（未合成 ended）');
  await until('document.querySelector("audio").readyState >= 3 && !document.querySelector("audio").paused');
  assert.equal(await evaluate('navigator.mediaSession.playbackState'), 'playing');
  await evaluate('document.querySelector("#play").click()', true);
  await until('navigator.mediaSession.playbackState === "paused"');
  await evaluate('document.querySelector("audio").play()', true);
  await until('navigator.mediaSession.playbackState === "playing"');
  await evaluate('document.querySelector("#play").click()', true);
  record('网页 Media Session metadata/playbackState 与实际暂停及恢复同步');
  await evaluate('document.querySelectorAll(".track")[11].click()', true);
  await until('document.querySelector("audio").readyState >= 3');
  await evaluate('document.querySelector("audio").currentTime = 1.85');
  await until('document.querySelector("audio").ended');
  assert.equal(await evaluate('document.querySelector("#now-title").textContent'), 'Test 11'); record('顺序末尾停止');
  await evaluate('document.querySelector("#repeat").click(); document.querySelectorAll(".track")[11].click()', true);
  await until('!document.querySelector("audio").paused'); await evaluate('document.querySelector("audio").currentTime = 1.85');
  await until('document.querySelector("#now-title").textContent === "Test 0"'); record('列表循环末尾回第一首');
  await evaluate('document.querySelector("#repeat").click()', true);
  await until('document.querySelector("audio").currentTime > .1');
  await evaluate('window.__plays=0; document.querySelector("audio").addEventListener("playing",()=>window.__plays++); document.querySelector("audio").currentTime=1.85');
  await until('window.__plays > 0 && document.querySelector("audio").currentTime < 1');
  assert.equal(await evaluate('document.querySelector("#now-title").textContent'), 'Test 0'); record('单曲循环真实重播');
  await evaluate('document.querySelector("#repeat").click(); document.querySelector("#shuffle").click(); document.querySelector("#next").click()', true);
  await until('document.querySelector("#now-title").textContent !== "Test 0"');
  await evaluate('document.querySelector("#prev").click()', true);
  await until('document.querySelector("#now-title").textContent === "Test 0"'); record('随机切歌和返回历史');
  await evaluate('document.querySelector("#shuffle").click(); for (let i=1;i<=10;i++) document.querySelector("#next").click()', true);
  await until('document.querySelector("audio").readyState >= 3 && !document.querySelector("audio").paused');
  assert.equal(await evaluate('document.querySelector("#now-title").textContent'), 'Test 10');
  assert.equal(await evaluate('document.querySelectorAll("audio").length'), 1);
  assert.equal(await evaluate('document.querySelector("#notice").hidden'), true); record('连续快速切换十首，仅一个 audio，无误报或未处理异常');
  await evaluate('document.querySelector("#play").click()', true);
  for (const width of [360, 768, 1280]) {
    await send('Emulation.setDeviceMetricsOverride', { width, height: 844, deviceScaleFactor: 1, mobile: width < 500 });
    await wait(60);
    assert.equal(await evaluate('document.documentElement.scrollWidth <= innerWidth'), true);
    const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true });
    fs.writeFileSync(path.join(out, 'width-' + width + '.png'), Buffer.from(shot.data, 'base64'));
  }
  record('360/768/1280px 无横向溢出，保留原 UI');
  await send('Network.emulateNetworkConditions', { offline: true, latency: 0, downloadThroughput: 0, uploadThroughput: 0 });
  await evaluate('document.querySelectorAll(".track")[3].click()', true);
  await until('/网络已中断/.test(document.querySelector("#notice").textContent)');
  assert.equal(await evaluate('document.querySelector("#now-title").textContent'), 'Test 3');
  await send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
  await until('!document.querySelector("audio").paused && document.querySelector("audio").currentTime > 0');
  assert.equal(await evaluate('document.querySelector("#now-title").textContent'), 'Test 3');
  record('真实浏览器断网等待、联网后恢复原曲');
  await evaluate('document.querySelector("#play").click()', true);
  await evaluate('window.__audioCount = document.querySelectorAll("audio").length; const s=document.createElement("script"); s.src="/apps/music-player/js/player.js?duplicate"; document.body.append(s)');
  await wait(100);
  await evaluate('document.querySelector("#next").click()', true);
  await until('document.querySelector("#now-title").textContent === "Test 4"');
  assert.equal(await evaluate('document.querySelectorAll("audio").length'), 1);
  record('重复脚本加载不重复绑定切歌或创建播放器');
  await evaluate('document.querySelector("#play").click()', true);
  await evaluate('document.querySelector("#now-fav").click()', true);
  assert.equal(await evaluate('JSON.parse(localStorage.getItem("ooglex.music-player.favorites")).length'), 1);
  await evaluate('document.querySelector("#now-fav").click()', true);
  assert.equal(await evaluate('JSON.parse(localStorage.getItem("ooglex.music-player.favorites")).length'), 0);
  record('收藏添加/取消仍使用既有存储键');
  failures = true;
  await evaluate('document.querySelectorAll(".track")[9].click()', true);
  await until('document.querySelector("audio").paused && /没有可播放/.test(document.querySelector("#notice").textContent)');
  record('真实 HTTP 404 音频有界跳过并停止');
  assert.deepEqual(errors, []); record('页面无未处理 JavaScript 异常');
  browserVersion = (await send('Browser.getVersion')).product;
  console.log(JSON.stringify({ browser: browserVersion, results }, null, 2));
} finally {
  fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify({ browser: browserVersion, results, errors }, null, 2));
  socket?.close(); chrome.kill('SIGTERM'); server.close();
}
