/* 霓虹都市 Neon City —— 原创俯视角开放城市驾驶游戏 */
(() => {
'use strict';

/* ===================== 基础 ===================== */
const cv = document.getElementById('cv');
const ctx = cv.getContext('2d');
const W = 960, H = 540;
const TILE = 64, GW = 64, GH = 64, WORLD = TILE * GW;
const ROAD = 0, SIDE = 1, BLDG = 2, GRASS = 3, SAND = 4, WATER = 5;
const TAU = Math.PI * 2;

let seed = 20260611;
function rnd() {
  seed |= 0; seed = seed + 0x6D2B79F5 | 0;
  let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
  t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
  return ((t ^ t >>> 14) >>> 0) / 4294967296;
}
const R = (a, b) => a + rnd() * (b - a);
const RI = (a, b) => Math.floor(R(a, b + 1));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const dist = (x1, y1, x2, y2) => Math.hypot(x2 - x1, y2 - y1);
function angDiff(a, b) { let d = (b - a) % TAU; if (d > Math.PI) d -= TAU; if (d < -Math.PI) d += TAU; return d; }

const NEON = ['#ff4fd8', '#29e6ff', '#ffe14d', '#b06bff', '#4dff9d', '#ff8a4d'];
const PASTEL = ['#e06a8a', '#5fb8e0', '#e0c75f', '#8a6ae0', '#5fe09a', '#e0855f', '#d8d8e8', '#7a8aa0'];

/* ===================== 城市生成 ===================== */
const tiles = new Uint8Array(GW * GH);
const buildings = [], trees = [], lamps = [];

for (let ty = 0; ty < GH; ty++) for (let tx = 0; tx < GW; tx++) {
  let t;
  if (tx >= GW - 4) t = WATER;
  else if (tx >= GW - 7) t = SAND;
  else if (tx % 9 < 2 || ty % 9 < 2) t = ROAD;
  else {
    const bx = tx % 9, by = ty % 9;
    t = (bx === 2 || bx === 8 || by === 2 || by === 8) ? SIDE : GRASS;
  }
  tiles[ty * GW + tx] = t;
}

const LAYOUTS = [
  [[0, 0, 5, 5]],
  [[0, 0, 2, 5], [3, 0, 2, 5]],
  [[0, 0, 5, 2], [0, 3, 5, 2]],
  [[0, 0, 2, 2], [3, 0, 2, 2], [0, 3, 2, 2], [3, 3, 2, 2]],
  [[0, 0, 2, 5], [3, 0, 2, 2], [3, 3, 2, 2]],
];
for (let bY = 0; bY * 9 + 8 < GH; bY++) for (let bX = 0; bX * 9 + 8 < GW - 7; bX++) {
  const x0 = bX * 9, y0 = bY * 9, ix = x0 + 3, iy = y0 + 3;
  if (rnd() < 0.16) {              // 公园
    for (let i = 0; i < 5; i++)
      trees.push({ x: (ix + R(0.5, 4.5)) * TILE, y: (iy + R(0.5, 4.5)) * TILE, s: R(0.8, 1.3) });
  } else {
    const lay = LAYOUTS[RI(0, LAYOUTS.length - 1)];
    for (const [rx, ry, rw, rh] of lay) {
      for (let r = 0; r < rh; r++) for (let c = 0; c < rw; c++)
        tiles[(iy + ry + r) * GW + (ix + rx + c)] = BLDG;
      buildings.push({
        x: (ix + rx) * TILE, y: (iy + ry) * TILE, w: rw * TILE, h: rh * TILE,
        c: NEON[RI(0, NEON.length - 1)], ht: R(50, 150), win: RI(1, 1e9)
      });
    }
  }
  lamps.push({ x: (x0 + 2) * TILE + 10, y: (y0 + 2) * TILE + 10 });
  if (rnd() < 0.7) trees.push({ x: (x0 + 2) * TILE + R(60, 380), y: (y0 + 2) * TILE + 14, s: R(0.7, 1) });
  if (rnd() < 0.7) trees.push({ x: (x0 + 2) * TILE + 14, y: (y0 + 2) * TILE + R(60, 380), s: R(0.7, 1) });
}
for (let i = 0; i < 70; i++) {       // 海滩棕榈
  const x = R((GW - 6.8) * TILE, (GW - 4.2) * TILE), y = R(20, WORLD - 20);
  trees.push({ x, y, s: R(0.9, 1.5) });
}

function tileAt(px, py) {
  const tx = clamp(Math.floor(px / TILE), 0, GW - 1);
  const ty = clamp(Math.floor(py / TILE), 0, GH - 1);
  return tiles[ty * GW + tx];
}
const solidCar = (px, py) => { const t = tileAt(px, py); return t === BLDG || t === WATER; };
const solidFoot = solidCar;

/* ===================== 音频 ===================== */
let AC = null, musicOn = true, musicTimer = null, barIdx = 0, nextBar = 0;
let noiseBuf = null, delayNode = null;
let engineOsc = null, engineGain = null, sirenTimer = null;

function initAudio() {
  if (AC) return;
  try { AC = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { return; }
  noiseBuf = AC.createBuffer(1, AC.sampleRate, AC.sampleRate);
  const d = noiseBuf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  delayNode = AC.createDelay(); delayNode.delayTime.value = 0.27;
  const fb = AC.createGain(); fb.gain.value = 0.32;
  delayNode.connect(fb); fb.connect(delayNode); delayNode.connect(AC.destination);
  engineOsc = AC.createOscillator(); engineOsc.type = 'sawtooth';
  engineGain = AC.createGain(); engineGain.gain.value = 0;
  const ef = AC.createBiquadFilter(); ef.type = 'lowpass'; ef.frequency.value = 400;
  engineOsc.connect(ef); ef.connect(engineGain); engineGain.connect(AC.destination);
  engineOsc.start();
  startMusic();
  sirenTimer = setInterval(() => {
    if (wanted > 0 && state === 'play') { tone(660, 660, 0.3, 'triangle', 0.05); setTimeout(() => tone(520, 520, 0.3, 'triangle', 0.05), 330); }
  }, 700);
}
function tone(f0, f1, dur, type, vol, when) {
  if (!AC) return;
  const t0 = when || AC.currentTime;
  const o = AC.createOscillator(), g = AC.createGain();
  o.type = type;
  o.frequency.setValueAtTime(f0, t0);
  o.frequency.exponentialRampToValueAtTime(Math.max(f1, 1), t0 + dur);
  g.gain.setValueAtTime(vol, t0);
  g.gain.exponentialRampToValueAtTime(0.001, t0 + dur);
  o.connect(g); g.connect(AC.destination);
  o.start(t0); o.stop(t0 + dur + 0.02);
}
function noise(dur, vol, freq, when, type) {
  if (!AC) return;
  const t0 = when || AC.currentTime;
  const s = AC.createBufferSource(); s.buffer = noiseBuf;
  const f = AC.createBiquadFilter(); f.type = type || 'bandpass'; f.frequency.value = freq; f.Q.value = 0.8;
  const g = AC.createGain();
  g.gain.setValueAtTime(vol, t0);
  g.gain.exponentialRampToValueAtTime(0.001, t0 + dur);
  s.connect(f); f.connect(g); g.connect(AC.destination);
  s.start(t0); s.stop(t0 + dur + 0.02);
}
const sThud = () => { tone(120, 40, 0.18, 'square', 0.2); noise(0.15, 0.18, 300); };
const sBoom = () => { tone(90, 25, 0.8, 'sawtooth', 0.3); noise(0.8, 0.3, 150, 0, 'lowpass'); };
const sCash = () => { tone(880, 880, 0.08, 'square', 0.1); setTimeout(() => tone(1175, 1175, 0.2, 'square', 0.1), 80); };
const sPick = () => tone(523, 1047, 0.18, 'square', 0.1);
const sHorn = () => { tone(330, 330, 0.35, 'square', 0.12); tone(415, 415, 0.35, 'square', 0.12); };
const sBust = () => { [392, 330, 262].forEach((f, i) => setTimeout(() => tone(f, f, 0.3, 'triangle', 0.15), i * 200)); };

/* —— 原创合成器配乐（小调进行 + 琶音 + 鼓机）—— */
const n2f = m => 440 * Math.pow(2, (m - 69) / 12);
const PROG = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]; // Am F C G
const BPM = 104, BEAT = 60 / BPM, BAR = BEAT * 4;
function startMusic() {
  if (musicTimer || !AC) return;
  nextBar = AC.currentTime + 0.15;
  musicTimer = setInterval(() => {
    while (nextBar < AC.currentTime + 0.35) {
      if (musicOn && state === 'play') playBar(nextBar);
      nextBar += BAR;
    }
  }, 120);
}
function playBar(t0) {
  const ch = PROG[barIdx % 4]; barIdx++;
  for (let b = 0; b < 4; b++) {
    tone(150, 40, 0.16, 'sine', 0.32, t0 + b * BEAT);                    // 底鼓
    noise(0.07, 0.05, 8000, t0 + b * BEAT + BEAT / 2, 'highpass');       // 镲
    if (b === 1 || b === 3) noise(0.16, 0.1, 1800, t0 + b * BEAT);       // 军鼓
  }
  for (let i = 0; i < 8; i++) {                                           // 贝斯八分音
    const m = ch[0] - 24 + (i % 4 === 3 ? 12 : 0);
    tone(n2f(m), n2f(m), BEAT * 0.42, 'sawtooth', 0.09, t0 + i * BEAT / 2);
  }
  ch.forEach(m => {                                                       // 和声铺底
    const o = AC.createOscillator(), g = AC.createGain(), f = AC.createBiquadFilter();
    o.type = 'sawtooth'; o.frequency.value = n2f(m); o.detune.value = R(-7, 7);
    f.type = 'lowpass'; f.frequency.value = 900;
    g.gain.setValueAtTime(0.001, t0);
    g.gain.linearRampToValueAtTime(0.035, t0 + 0.3);
    g.gain.linearRampToValueAtTime(0.001, t0 + BAR);
    o.connect(f); f.connect(g); g.connect(AC.destination);
    o.start(t0); o.stop(t0 + BAR + 0.05);
  });
  const seq = [0, 1, 2, 1, 2, 0, 1, 2];                                   // 琶音（带回声）
  for (let i = 0; i < 8; i++) {
    const o = AC.createOscillator(), g = AC.createGain();
    o.type = 'square'; o.frequency.value = n2f(ch[seq[i]] + 12);
    const tt = t0 + i * BEAT / 2;
    g.gain.setValueAtTime(0.045, tt);
    g.gain.exponentialRampToValueAtTime(0.001, tt + 0.18);
    o.connect(g); g.connect(AC.destination); g.connect(delayNode);
    o.start(tt); o.stop(tt + 0.25);
  }
}

/* ===================== 实体 ===================== */
const KINDS = {
  sport:  { acc: 330, max: 380, c: () => NEON[RI(0, NEON.length - 1)] },
  sedan:  { acc: 240, max: 300, c: () => PASTEL[RI(0, PASTEL.length - 1)] },
  taxi:   { acc: 250, max: 310, c: () => '#f5c518' },
  police: { acc: 310, max: 360, c: () => '#f0f0f5' },
};
function mkCar(x, y, a, kind) {
  return { x, y, a, vx: 0, vy: 0, f: 0, kind, c: KINDS[kind].c(), health: 100,
           ai: null, dir: 0, decided: '', wreck: false, fire: 0, stuck: 0, blink: 0 };
}
const cars = [];
const laneOf = (dir, base) => (dir === 0 || dir === 3) ? base + 1.5 * TILE : base + 0.5 * TILE;

function randRoadPos() {
  for (let i = 0; i < 60; i++) {
    const tx = RI(0, GW - 9), ty = RI(0, GH - 1);
    if (tileAt(tx * TILE + 2, ty * TILE + 2) === ROAD) return { x: tx * TILE + TILE / 2, y: ty * TILE + TILE / 2 };
  }
  return { x: TILE / 2, y: TILE / 2 };
}
function spawnTraffic() {
  const p = randRoadPos();
  const tx = Math.floor(p.x / TILE), ty = Math.floor(p.y / TILE);
  const vert = tx % 9 < 2 && !(ty % 9 < 2);
  const dir = vert ? (rnd() < 0.5 ? 1 : 3) : (rnd() < 0.5 ? 0 : 2);
  const kinds = ['sedan', 'sedan', 'taxi', 'sport'];
  const c = mkCar(p.x, p.y, dir * Math.PI / 2, kinds[RI(0, 3)]);
  c.ai = 'traffic'; c.dir = dir;
  if (vert) c.x = Math.floor(tx / 9) * 9 * TILE + laneOf(dir === 1 ? 1 : 3, 0);
  else c.y = Math.floor(ty / 9) * 9 * TILE + laneOf(dir === 0 ? 0 : 2, 0);
  cars.push(c);
  return c;
}
for (let i = 0; i < 22; i++) spawnTraffic();
for (let i = 0; i < 16; i++) {                       // 路边停着的车
  const p = randRoadPos();
  const c = mkCar(p.x, p.y, RI(0, 3) * Math.PI / 2, rnd() < 0.4 ? 'sport' : 'sedan');
  cars.push(c);
}

const peds = [];
function spawnPed() {
  for (let i = 0; i < 40; i++) {
    const x = R(0, (GW - 7) * TILE), y = R(0, WORLD);
    if (tileAt(x, y) === SIDE) {
      peds.push({ x, y, a: R(0, TAU), state: 'walk', t: 0, c: PASTEL[RI(0, PASTEL.length - 1)], vx: 0, vy: 0 });
      return;
    }
  }
}
for (let i = 0; i < 55; i++) spawnPed();

/* ===================== 玩家 / 任务 / 状态 ===================== */
let state = 'title';
const player = { x: 29.5 * TILE, y: 29.2 * TILE, a: 0, car: null, anim: 0 };
let cash = 0, best = +(localStorage.getItem('neoncity_best') || 0);
let wanted = 0, lastCrime = -99, gameT = 0, shake = 0, bustFlash = 0;
let parts = [], skids = [], msgs = [];
let job = null, rainAmt = 0, rainTarget = 0;
const drops = Array.from({ length: 130 }, () => ({ x: Math.random() * W, y: Math.random() * H, v: 500 + Math.random() * 300 }));

function msg(t) { msgs.push({ t, life: 3 }); if (msgs.length > 3) msgs.shift(); }
function crime(n) { wanted = clamp(wanted + n, 0, 5); lastCrime = gameT; }

function newJob(pickup) {
  const px = player.car ? player.car.x : player.x, py = player.car ? player.car.y : player.y;
  for (let i = 0; i < 80; i++) {
    const p = randRoadPos();
    const d = dist(px, py, p.x, p.y);
    if (d > 700 && d < 2600) {
      if (pickup) job = { phase: 'pickup', x: p.x, y: p.y };
      else { job.phase = 'deliver'; job.x = p.x; job.y = p.y; job.tLeft = d / 170 + 12; job.pay = Math.round(d / 10) * 10; }
      return;
    }
  }
}
newJob(true);

function burst(x, y, color, n, spd, up) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * TAU, v = (spd || 160) * (0.4 + Math.random() * 0.6);
    parts.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - (up || 60),
                 life: 0.4 + Math.random() * 0.5, c: color, r: 3 + Math.random() * 4 });
  }
}

/* ===================== 输入 ===================== */
const keys = {};
function tryEnterExit() {
  if (player.car) {
    const c = player.car;
    player.car = null;
    player.x = c.x + Math.cos(c.a + Math.PI / 2) * 40;
    player.y = c.y + Math.sin(c.a + Math.PI / 2) * 40;
    if (solidFoot(player.x, player.y)) { player.x = c.x; player.y = c.y - 40; }
    sPick();
  } else {
    let bestC = null, bd = 70;
    for (const c of cars) {
      if (c.wreck) continue;
      const d = dist(player.x, player.y, c.x, c.y);
      if (d < bd) { bd = d; bestC = c; }
    }
    if (bestC) {
      player.car = bestC; bestC.ai = null; sPick();
      msg(bestC.kind === 'police' ? '🚓 你开走了警车！' : '🚗 上车！油门走起');
    }
  }
}
addEventListener('keydown', e => {
  if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Space'].includes(e.code)) e.preventDefault();
  if (state === 'title') { state = 'play'; initAudio(); return; }
  if (e.repeat) return;
  initAudio();
  if (e.code === 'ArrowLeft' || e.code === 'KeyA') keys.left = true;
  if (e.code === 'ArrowRight' || e.code === 'KeyD') keys.right = true;
  if (e.code === 'ArrowUp' || e.code === 'KeyW') keys.up = true;
  if (e.code === 'ArrowDown' || e.code === 'KeyS') keys.down = true;
  if (e.code === 'Space') keys.hand = true;
  if (e.code === 'KeyE' || e.code === 'KeyF' || e.code === 'Enter') tryEnterExit();
  if (e.code === 'KeyH') { sHorn(); scareNearby(); }
  if (e.code === 'KeyM') { musicOn = !musicOn; msg(musicOn ? '🎵 音乐开' : '🔇 音乐关'); }
});
addEventListener('keyup', e => {
  if (e.code === 'ArrowLeft' || e.code === 'KeyA') keys.left = false;
  if (e.code === 'ArrowRight' || e.code === 'KeyD') keys.right = false;
  if (e.code === 'ArrowUp' || e.code === 'KeyW') keys.up = false;
  if (e.code === 'ArrowDown' || e.code === 'KeyS') keys.down = false;
  if (e.code === 'Space') keys.hand = false;
});
cv.addEventListener('pointerdown', () => { if (state === 'title') { state = 'play'; initAudio(); } });

if ('ontouchstart' in window) document.getElementById('touch').classList.add('show');
function bindBtn(id, fn, up) {
  const el = document.getElementById(id);
  el.addEventListener('pointerdown', e => { e.preventDefault(); initAudio(); if (state === 'title') state = 'play'; fn(); });
  if (up) { el.addEventListener('pointerup', up); el.addEventListener('pointerleave', up); }
}
bindBtn('btnL', () => keys.left = true, () => keys.left = false);
bindBtn('btnR', () => keys.right = true, () => keys.right = false);
bindBtn('btnU', () => keys.up = true, () => keys.up = false);
bindBtn('btnD', () => keys.down = true, () => keys.down = false);
bindBtn('btnE', () => tryEnterExit());

function scareNearby() {
  const px = player.car ? player.car.x : player.x, py = player.car ? player.car.y : player.y;
  for (const p of peds) if (dist(px, py, p.x, p.y) < 200 && p.state === 'walk') { p.state = 'flee'; p.t = 1.5; }
}

/* ===================== 车辆物理 ===================== */
function stepCar(c, thr, steer, hand, dt) {
  const K = KINDS[c.kind];
  const hx = Math.cos(c.a), hy = Math.sin(c.a);
  let f = c.vx * hx + c.vy * hy;
  let l = -c.vx * hy + c.vy * hx;
  f += thr * K.acc * dt;
  if (hand) f *= (1 - 1.6 * dt);
  f = clamp(f, -K.max * 0.45, K.max);
  f *= (1 - 0.5 * dt);
  l *= hand ? Math.pow(0.45, dt) : Math.pow(0.0025, dt);
  c.a += steer * 2.6 * dt * clamp(f / 90, -1, 1);
  const hx2 = Math.cos(c.a), hy2 = Math.sin(c.a);
  c.vx = hx2 * f - hy2 * l;
  c.vy = hy2 * f + hx2 * l;
  c.f = f;
  const nx = c.x + c.vx * dt, ny = c.y + c.vy * dt;
  const fx = nx + hx2 * 26, fy = ny + hy2 * 26, bx = nx - hx2 * 26, by = ny - hy2 * 26;
  if (solidCar(fx, fy) || solidCar(bx, by) || nx < 30 || nx > WORLD - 30 || ny < 30 || ny > WORLD - 30) {
    if (Math.abs(f) > 130) {
      c.health -= (Math.abs(f) - 100) * 0.09;
      sThud(); shake = Math.min(12, shake + 6);
      burst(fx, fy, '#ffd84d', 8, 200);
    }
    c.vx *= -0.35; c.vy *= -0.35; c.f *= -0.35;
  } else { c.x = nx; c.y = ny; }
  if (Math.abs(l) > 65 && tileAt(c.x, c.y) === ROAD) {
    skids.push({ x: c.x - hx2 * 18, y: c.y - hy2 * 18, life: 4 });
    if (skids.length > 350) skids.shift();
  }
  if (c.health <= 0 && !c.wreck) explodeCar(c);
}
function explodeCar(c) {
  c.wreck = true; c.fire = 9; c.vx = c.vy = c.f = 0;
  sBoom(); shake = 16;
  burst(c.x, c.y, '#ff8a4d', 30, 320, 120);
  burst(c.x, c.y, '#ffe14d', 20, 250, 100);
  if (player.car === c) {
    player.car = null;
    player.x = c.x + 46; player.y = c.y;
    if (solidFoot(player.x, player.y)) { player.x = c.x - 46; }
    msg('💥 车炸了！快找辆新车');
    crime(1);
  }
}

/* ===================== 更新 ===================== */
function update(dt) {
  gameT += dt;
  shake = Math.max(0, shake - 40 * dt);
  bustFlash = Math.max(0, bustFlash - dt);

  /* —— 玩家 —— */
  if (player.car) {
    const thr = (keys.up ? 1 : 0) + (keys.down ? -0.8 : 0);
    const steer = (keys.left ? -1 : 0) + (keys.right ? 1 : 0);
    stepCar(player.car, thr, steer, keys.hand, dt);
    player.x = player.car.x; player.y = player.car.y;
    if (engineGain) {
      engineGain.gain.value = 0.045;
      engineOsc.frequency.value = 65 + Math.abs(player.car.f) * 1.15;
    }
  } else {
    if (engineGain) engineGain.gain.value = 0;
    let dx = (keys.right ? 1 : 0) - (keys.left ? 1 : 0);
    let dy = (keys.down ? 1 : 0) - (keys.up ? 1 : 0);
    if (dx || dy) {
      const m = Math.hypot(dx, dy); dx /= m; dy /= m;
      player.a = Math.atan2(dy, dx);
      player.anim += dt * 9;
      const sp = 165;
      const nx = player.x + dx * sp * dt, ny = player.y + dy * sp * dt;
      if (!solidFoot(nx, player.y)) player.x = clamp(nx, 10, WORLD - 10);
      if (!solidFoot(player.x, ny)) player.y = clamp(ny, 10, WORLD - 10);
    }
  }

  /* —— 通缉度衰减 —— */
  if (wanted > 0 && gameT - lastCrime > 11) { wanted--; lastCrime = gameT; if (wanted === 0) msg('😌 警察不追了'); }

  /* —— 交通 AI —— */
  for (const c of cars) {
    if (c.wreck) { c.fire = Math.max(0, c.fire - dt); continue; }
    if (c === player.car) continue;

    if (c.ai === 'traffic') {
      const sp = 86;
      const dirAng = c.dir * Math.PI / 2;
      c.a += angDiff(c.a, dirAng) * Math.min(1, 9 * dt);
      let ahead = false;
      const axp = c.x + Math.cos(dirAng) * 75, ayp = c.y + Math.sin(dirAng) * 75;
      for (const o of cars) if (o !== c && !o.wreck && dist(axp, ayp, o.x, o.y) < 52) { ahead = true; break; }
      if (!ahead && dist(axp, ayp, player.x, player.y) < 46) ahead = true;
      const v = ahead ? 0 : sp;
      const tx = Math.floor(c.x / TILE), ty = Math.floor(c.y / TILE);
      if (tx % 9 < 2 && ty % 9 < 2) {
        const key = Math.floor(tx / 9) + ',' + Math.floor(ty / 9);
        if (c.decided !== key) {
          c.decided = key;
          const r = rnd();
          if (r < 0.55) {} else if (r < 0.78) c.dir = (c.dir + 1) % 4; else c.dir = (c.dir + 3) % 4;
        }
      }
      const fAhead = { x: c.x + Math.cos(dirAng) * 50, y: c.y + Math.sin(dirAng) * 50 };
      if (tileAt(fAhead.x, fAhead.y) !== ROAD) c.dir = (c.dir + 2) % 4;
      if (c.dir === 0 || c.dir === 2) {
        const base = Math.floor(ty / 9) * 9 * TILE;
        const lane = laneOf(c.dir, base);
        c.y += clamp(lane - c.y, -130 * dt, 130 * dt);
        c.x += (c.dir === 0 ? v : -v) * dt;
        c.vx = (c.dir === 0 ? v : -v); c.vy = 0;
      } else {
        const base = Math.floor(tx / 9) * 9 * TILE;
        const lane = laneOf(c.dir, base);
        c.x += clamp(lane - c.x, -130 * dt, 130 * dt);
        c.y += (c.dir === 1 ? v : -v) * dt;
        c.vy = (c.dir === 1 ? v : -v); c.vx = 0;
      }
      c.x = clamp(c.x, 20, WORLD - 20); c.y = clamp(c.y, 20, WORLD - 20);
      if (dist(c.x, c.y, player.x, player.y) > 2800) {
        const p = randRoadPos(); c.x = p.x; c.y = p.y; c.decided = '';
      }
    }

    if (c.ai === 'police') {
      const want = Math.atan2(player.y - c.y, player.x - c.x);
      const d = angDiff(c.a, want);
      if (Math.abs(c.f) < 25) c.stuck += dt; else c.stuck = 0;
      if (c.stuck > 1.4) {
        stepCar(c, -0.8, -Math.sign(d), false, dt);
        if (c.stuck > 2.4) c.stuck = 0;
      } else {
        stepCar(c, dist(c.x, c.y, player.x, player.y) > 90 ? 1 : 0.4, clamp(d * 2.2, -1, 1), false, dt);
      }
      c.blink += dt;
      if (!player.car && wanted > 0 && dist(c.x, c.y, player.x, player.y) < 48 && Math.abs(c.f) < 70) {
        cash = Math.max(0, cash - 300);
        wanted = 0; bustFlash = 1.2; sBust();
        msg('🚨 被捕了！罚款 $300');
        for (const o of cars) if (o.ai === 'police') o.ai = 'gone';
      }
    }
  }
  for (let i = cars.length - 1; i >= 0; i--) {
    const c = cars[i];
    if (c.ai === 'gone' || (c.ai === 'police' && wanted === 0 && c !== player.car)) cars.splice(i, 1);
  }

  /* —— 警察生成 —— */
  const nPolice = cars.filter(c => c.ai === 'police').length;
  if (wanted > 0 && nPolice < Math.min(wanted, 4) && Math.random() < dt * 0.6) {
    for (let i = 0; i < 30; i++) {
      const p = randRoadPos();
      const d = dist(p.x, p.y, player.x, player.y);
      if (d > 650 && d < 1300) {
        const c = mkCar(p.x, p.y, 0, 'police'); c.ai = 'police';
        cars.push(c); break;
      }
    }
  }

  /* —— 车与车碰撞 —— */
  const pc = player.car;
  if (pc && !pc.wreck) {
    for (const o of cars) {
      if (o === pc || o.wreck) continue;
      const d = dist(pc.x, pc.y, o.x, o.y);
      if (d < 48 && d > 0.01) {
        const nx = (o.x - pc.x) / d, ny = (o.y - pc.y) / d;
        const rel = Math.hypot(pc.vx - o.vx, pc.vy - o.vy);
        o.x += nx * (48 - d) * 0.6; o.y += ny * (48 - d) * 0.6;
        pc.x -= nx * (48 - d) * 0.4; pc.y -= ny * (48 - d) * 0.4;
        if (rel > 150) {
          sThud(); shake = Math.min(12, shake + 5);
          burst((pc.x + o.x) / 2, (pc.y + o.y) / 2, '#ffd84d', 8, 200);
          pc.health -= (rel - 120) * 0.05;
          o.health -= (rel - 120) * 0.08;
          pc.vx *= 0.55; pc.vy *= 0.55; pc.f *= 0.55;
          crime(1);
          if (o.health <= 0 && !o.wreck) explodeCar(o);
          if (pc.health <= 0 && !pc.wreck) explodeCar(pc);
        }
      }
    }
  }

  /* —— 行人 —— */
  for (const p of peds) {
    p.t -= dt;
    if (p.state === 'down') {
      p.x += p.vx * dt; p.y += p.vy * dt;
      p.vx *= 0.9; p.vy *= 0.9;
      if (p.t <= 0) p.state = 'walk';
      continue;
    }
    let threat = null, td = 130;
    for (const c of cars) {
      if (c.wreck) continue;
      const sp = Math.hypot(c.vx, c.vy);
      if (sp < 60) continue;
      const d = dist(p.x, p.y, c.x, c.y);
      if (d < td) { td = d; threat = c; }
    }
    if (threat) { p.state = 'flee'; p.t = 1; p.a = Math.atan2(p.y - threat.y, p.x - threat.x); }
    else if (p.state === 'flee' && p.t <= 0) p.state = 'walk';
    const sp = p.state === 'flee' ? 120 : 32;
    if (p.state === 'walk' && Math.random() < dt * 0.4) p.a += R(-1.2, 1.2);
    const nx = p.x + Math.cos(p.a) * sp * dt, ny = p.y + Math.sin(p.a) * sp * dt;
    if (!solidFoot(nx, ny) && tileAt(nx, ny) !== WATER) { p.x = nx; p.y = ny; }
    else p.a += Math.PI / 2;
    for (const c of cars) {
      if (c.wreck) continue;
      const sp2 = Math.hypot(c.vx, c.vy);
      if (sp2 > 110 && dist(p.x, p.y, c.x, c.y) < 26) {
        p.state = 'down'; p.t = 4;
        p.vx = (p.x - c.x) * 8 + c.vx * 0.4; p.vy = (p.y - c.y) * 8 + c.vy * 0.4;
        sThud(); crime(1);
        msg('😵 撞到行人了！警察来了');
        burst(p.x, p.y, '#ffffff', 6, 150);
      }
    }
  }

  /* —— 任务 —— */
  if (job) {
    const px = player.x, py = player.y;
    const d = dist(px, py, job.x, job.y);
    if (job.phase === 'pickup' && d < 70) {
      sPick(); msg('📦 拿到货了！限时送到目的地');
      newJob(false);
    } else if (job.phase === 'deliver') {
      job.tLeft -= dt;
      if (d < 70) {
        cash += job.pay; sCash();
        msg(`💰 送达！+$${job.pay}`);
        burst(job.x, job.y, '#4dff9d', 20, 220, 120);
        if (cash > best) { best = cash; localStorage.setItem('neoncity_best', best); }
        newJob(true);
      } else if (job.tLeft <= 0) {
        msg('⏰ 超时了，订单取消…');
        newJob(true);
      }
    }
  }

  /* —— 粒子 / 烟火 / 胎痕 / 天气 —— */
  for (const c of cars) if (c.wreck && c.fire > 0 && Math.random() < dt * 22) {
    parts.push({ x: c.x + R(-14, 14), y: c.y + R(-8, 8), vx: R(-15, 15), vy: R(-90, -40),
                 life: R(0.4, 0.9), c: Math.random() < 0.5 ? '#ff8a4d' : '#5a5a66', r: R(4, 9) });
  }
  for (const q of parts) { q.life -= dt; q.x += q.vx * dt; q.y += q.vy * dt; q.vy += 60 * dt; }
  parts = parts.filter(q => q.life > 0);
  for (const s of skids) s.life -= dt;
  skids = skids.filter(s => s.life > 0);
  for (const m of msgs) m.life -= dt;
  msgs = msgs.filter(m => m.life > 0);
  if (Math.random() < dt * 0.012) rainTarget = rainTarget > 0 ? 0 : 1;
  rainAmt += clamp(rainTarget - rainAmt, -dt * 0.3, dt * 0.3);
}

/* ===================== 绘制 ===================== */
const mini = document.createElement('canvas'); mini.width = mini.height = 160;
{
  const m = mini.getContext('2d');
  const s = 160 / GW;
  const colors = ['#4a4f5c', '#6d7280', '#16102e', '#2e7a4a', '#d8c07a', '#1860b8'];
  for (let ty = 0; ty < GH; ty++) for (let tx = 0; tx < GW; tx++) {
    m.fillStyle = colors[tiles[ty * GW + tx]];
    m.fillRect(tx * s, ty * s, s + 0.5, s + 0.5);
  }
}
function mkGlow(r, g, b) {
  const c = document.createElement('canvas'); c.width = c.height = 128;
  const x = c.getContext('2d');
  const gr = x.createRadialGradient(64, 64, 4, 64, 64, 64);
  gr.addColorStop(0, `rgba(${r},${g},${b},0.55)`);
  gr.addColorStop(1, `rgba(${r},${g},${b},0)`);
  x.fillStyle = gr; x.fillRect(0, 0, 128, 128);
  return c;
}
const glowWarm = mkGlow(255, 215, 140), glowCool = mkGlow(190, 225, 255), glowFire = mkGlow(255, 130, 50);

let camX = player.x - W / 2, camY = player.y - H / 2;

function draw() {
  const px = player.x, py = player.y;
  const lookX = player.car ? player.car.vx * 0.45 : 0;
  const lookY = player.car ? player.car.vy * 0.45 : 0;
  camX += (clamp(px + lookX - W / 2, 0, WORLD - W) - camX) * 0.08;
  camY += (clamp(py + lookY - H / 2, 0, WORLD - H) - camY) * 0.08;

  const phase = (gameT % 120) / 120;
  const dayB = 0.5 + 0.5 * Math.sin(phase * TAU + Math.PI / 2);   // 1=正午 0=午夜
  const night = clamp(1 - dayB * 1.35, 0, 1);

  ctx.save();
  if (shake > 0) ctx.translate(R(-shake, shake), R(-shake, shake));
  ctx.translate(-Math.round(camX), -Math.round(camY));

  /* 地面 */
  const tx0 = Math.max(0, Math.floor(camX / TILE) - 1), tx1 = Math.min(GW - 1, tx0 + Math.ceil(W / TILE) + 2);
  const ty0 = Math.max(0, Math.floor(camY / TILE) - 1), ty1 = Math.min(GH - 1, ty0 + Math.ceil(H / TILE) + 2);
  const GROUND = ['#3a3f4a', '#9aa0ad', '#241b3d', '#46a868', '#eed68e', '#1f7fd4'];
  for (let ty = ty0; ty <= ty1; ty++) for (let tx = tx0; tx <= tx1; tx++) {
    const t = tiles[ty * GW + tx], x = tx * TILE, y = ty * TILE;
    ctx.fillStyle = GROUND[t];
    ctx.fillRect(x, y, TILE, TILE);
    if (t === ROAD) {
      ctx.fillStyle = 'rgba(255,220,80,0.7)';
      const vRoad = tx % 9 === 1 && !(ty % 9 < 2);
      const hRoad = ty % 9 === 1 && !(tx % 9 < 2);
      if (vRoad) for (let i = 0; i < 4; i++) ctx.fillRect(x - 2, y + i * 18 + 4, 4, 10);
      if (hRoad) for (let i = 0; i < 4; i++) ctx.fillRect(x + i * 18 + 4, y - 2, 10, 4);
    } else if (t === SIDE) {
      ctx.strokeStyle = 'rgba(0,0,0,0.12)'; ctx.lineWidth = 1;
      ctx.strokeRect(x + 0.5, y + 0.5, TILE, TILE);
    } else if (t === WATER) {
      ctx.fillStyle = 'rgba(255,255,255,0.18)';
      const wy = y + 20 + Math.sin(gameT * 1.8 + tx * 1.3 + ty) * 8;
      ctx.fillRect(x + 6, wy, TILE - 12, 3);
      const wy2 = y + 44 + Math.cos(gameT * 1.4 + tx + ty * 1.7) * 8;
      ctx.fillRect(x + 12, wy2, TILE - 24, 2);
    } else if (t === SAND && tx === GW - 5) {
      ctx.fillStyle = 'rgba(255,255,255,0.5)';                     // 浪花
      const f = Math.sin(gameT * 1.2) * 10;
      ctx.fillRect(x + TILE - 10 + f, y, 8, TILE);
    } else if (t === GRASS) {
      ctx.fillStyle = 'rgba(0,0,0,0.08)';
      ctx.fillRect(x + (tx * 7 % 40), y + (ty * 11 % 40), 6, 6);
    }
  }

  /* 胎痕 */
  ctx.fillStyle = 'rgba(20,20,25,0.5)';
  for (const s of skids) {
    ctx.globalAlpha = clamp(s.life / 4, 0, 0.5);
    ctx.fillRect(s.x - 3, s.y - 3, 6, 6);
  }
  ctx.globalAlpha = 1;

  /* 任务标记（地面光环） */
  if (job) {
    const pulse = 1 + Math.sin(gameT * 5) * 0.15;
    const col = job.phase === 'pickup' ? '#29e6ff' : '#4dff9d';
    ctx.strokeStyle = col; ctx.lineWidth = 4;
    ctx.beginPath(); ctx.arc(job.x, job.y, 36 * pulse, 0, TAU); ctx.stroke();
    ctx.globalAlpha = 0.25; ctx.fillStyle = col;
    ctx.beginPath(); ctx.arc(job.x, job.y, 36 * pulse, 0, TAU); ctx.fill();
    ctx.globalAlpha = 1;
    ctx.font = '22px sans-serif'; ctx.textAlign = 'center';
    ctx.fillText(job.phase === 'pickup' ? '📦' : '🏁', job.x, job.y + 8);
  }

  /* 行人 */
  for (const p of peds) {
    if (p.x < camX - 40 || p.x > camX + W + 40 || p.y < camY - 40 || p.y > camY + H + 40) continue;
    ctx.save(); ctx.translate(p.x, p.y);
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.beginPath(); ctx.ellipse(0, 3, 9, 5, 0, 0, TAU); ctx.fill();
    ctx.rotate(p.a + Math.PI / 2);
    if (p.state === 'down') ctx.rotate(Math.PI / 2);
    const step = Math.sin(gameT * 12 + p.x) * (p.state === 'down' ? 0 : 4);
    ctx.fillStyle = '#2d2436';
    ctx.fillRect(-4, -2 + step, 3, 6); ctx.fillRect(1, -2 - step, 3, 6);
    ctx.fillStyle = p.c;
    ctx.beginPath(); ctx.ellipse(0, 0, 7, 5, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = '#e8b88a';
    ctx.beginPath(); ctx.arc(0, -1, 3.6, 0, TAU); ctx.fill();
    ctx.restore();
    if (p.state === 'flee') { ctx.fillStyle = '#ffe14d'; ctx.font = 'bold 14px sans-serif'; ctx.fillText('!', p.x, p.y - 14); }
  }

  /* 车辆 */
  for (const c of cars) {
    if (c.x < camX - 80 || c.x > camX + W + 80 || c.y < camY - 80 || c.y > camY + H + 80) continue;
    drawCar(c, night);
  }

  /* 玩家（步行时） */
  if (!player.car) {
    ctx.save(); ctx.translate(player.x, player.y);
    ctx.fillStyle = 'rgba(0,0,0,0.3)';
    ctx.beginPath(); ctx.ellipse(0, 4, 10, 6, 0, 0, TAU); ctx.fill();
    ctx.rotate(player.a + Math.PI / 2);
    const step = Math.sin(player.anim) * 5;
    ctx.fillStyle = '#1f2a44';
    ctx.fillRect(-5, -2 + step, 4, 8); ctx.fillRect(1, -2 - step, 4, 8);
    ctx.fillStyle = '#ff4fd8';                                    // 粉色花衬衫
    ctx.beginPath(); ctx.ellipse(0, 0, 8.5, 6, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = '#29e6ff';
    ctx.fillRect(-8, -2, 3, 4); ctx.fillRect(5, -2, 3, 4);
    ctx.fillStyle = '#e8b88a';
    ctx.beginPath(); ctx.arc(0, -1, 4.2, 0, TAU); ctx.fill();
    ctx.fillStyle = '#3a2a1a';
    ctx.beginPath(); ctx.arc(0, -3, 3.2, 0, Math.PI, true); ctx.fill();
    ctx.restore();
  }

  /* 粒子 */
  for (const q of parts) {
    ctx.globalAlpha = clamp(q.life / 0.6, 0, 1);
    ctx.fillStyle = q.c;
    ctx.fillRect(q.x - q.r / 2, q.y - q.r / 2, q.r, q.r);
  }
  ctx.globalAlpha = 1;

  /* 棕榈树（2.5D） */
  for (const t of trees) {
    if (t.x < camX - 80 || t.x > camX + W + 80 || t.y < camY - 100 || t.y > camY + H + 80) continue;
    const ox = (t.x - camX - W / 2) * 0.05, oy = (t.y - camY - H / 2) * 0.05;
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.beginPath(); ctx.ellipse(t.x + 8, t.y + 6, 16 * t.s, 7 * t.s, 0, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#8a5a3a'; ctx.lineWidth = 5 * t.s;
    ctx.beginPath(); ctx.moveTo(t.x, t.y); ctx.lineTo(t.x + ox, t.y + oy - 26 * t.s); ctx.stroke();
    const cx = t.x + ox, cy = t.y + oy - 26 * t.s;
    ctx.strokeStyle = '#2e9e55'; ctx.lineWidth = 4 * t.s; ctx.lineCap = 'round';
    const sway = Math.sin(gameT * 1.5 + t.x) * 3;
    for (let i = 0; i < 6; i++) {
      const a = i * TAU / 6 + 0.4;
      ctx.beginPath(); ctx.moveTo(cx, cy);
      ctx.quadraticCurveTo(cx + Math.cos(a) * 14 * t.s + sway, cy + Math.sin(a) * 10 * t.s - 8,
                           cx + Math.cos(a) * 24 * t.s + sway, cy + Math.sin(a) * 14 * t.s + 2);
      ctx.stroke();
    }
    ctx.lineCap = 'butt';
  }

  /* 建筑（伪 3D 视差） */
  for (const b of buildings) {
    if (b.x + b.w < camX - 160 || b.x > camX + W + 160 || b.y + b.h < camY - 160 || b.y > camY + H + 160) continue;
    const bcx = b.x + b.w / 2, bcy = b.y + b.h / 2;
    const p = b.ht / 1400;
    const ox = (bcx - camX - W / 2) * p, oy = (bcy - camY - H / 2) * p;
    ctx.fillStyle = '#161028';
    const corners = [[b.x, b.y], [b.x + b.w, b.y], [b.x + b.w, b.y + b.h], [b.x, b.y + b.h]];
    for (let i = 0; i < 4; i++) {                                  // 侧墙
      const [x1, y1] = corners[i], [x2, y2] = corners[(i + 1) % 4];
      ctx.beginPath();
      ctx.moveTo(x1, y1); ctx.lineTo(x2, y2);
      ctx.lineTo(x2 + ox, y2 + oy); ctx.lineTo(x1 + ox, y1 + oy);
      ctx.closePath(); ctx.fill();
    }
    ctx.fillStyle = '#2c2350';                                     // 屋顶
    ctx.fillRect(b.x + ox, b.y + oy, b.w, b.h);
    ctx.strokeStyle = b.c; ctx.lineWidth = 2.5;
    ctx.globalAlpha = 0.4 + night * 0.6;
    ctx.strokeRect(b.x + ox + 2, b.y + oy + 2, b.w - 4, b.h - 4);
    ctx.globalAlpha = 1;
    let s2 = b.win;                                                // 屋顶细节
    const lr = () => { s2 = s2 * 1103515245 + 12345 & 0x7fffffff; return s2 / 0x7fffffff; };
    ctx.fillStyle = night > 0.3 ? 'rgba(255,225,120,0.8)' : 'rgba(0,0,0,0.25)';
    const nw = 2 + (b.w / TILE | 0);
    for (let i = 0; i < nw; i++)
      if (lr() < 0.7) ctx.fillRect(b.x + ox + 10 + lr() * (b.w - 26), b.y + oy + 10 + lr() * (b.h - 26), 7, 7);
  }

  /* 夜幕 + 灯光 */
  if (night > 0.05) {
    ctx.fillStyle = `rgba(12,8,45,${night * 0.55})`;
    ctx.fillRect(camX - 20, camY - 20, W + 40, H + 40);
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = night;
    for (const l of lamps) {
      if (l.x < camX - 100 || l.x > camX + W + 100 || l.y < camY - 100 || l.y > camY + H + 100) continue;
      ctx.drawImage(glowWarm, l.x - 55, l.y - 55, 110, 110);
    }
    for (const c of cars) {
      if (c.x < camX - 200 || c.x > camX + W + 200 || c.y < camY - 200 || c.y > camY + H + 200) continue;
      if (c.wreck) { if (c.fire > 0) ctx.drawImage(glowFire, c.x - 70, c.y - 70, 140, 140); continue; }
      if (c.ai === 'traffic' || c === player.car || c.ai === 'police') {
        const hx = Math.cos(c.a), hy = Math.sin(c.a);
        ctx.drawImage(glowCool, c.x + hx * 55 - 45, c.y + hy * 55 - 45, 90, 90);
        ctx.drawImage(glowCool, c.x + hx * 95 - 35, c.y + hy * 95 - 35, 70, 70);
      }
    }
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
  }
  const dusk = Math.sin(phase * TAU) ;                              // 黄昏粉橙色调
  if (dusk < -0.55) {
    ctx.fillStyle = `rgba(255,90,140,${(-dusk - 0.55) * 0.18})`;
    ctx.fillRect(camX - 20, camY - 20, W + 40, H + 40);
  }

  ctx.restore();

  /* 雨 */
  if (rainAmt > 0.02) {
    ctx.strokeStyle = `rgba(180,210,255,${0.35 * rainAmt})`;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    for (const d of drops) {
      d.y += d.v * 0.016; d.x -= 60 * 0.016;
      if (d.y > H) { d.y = -10; d.x = Math.random() * (W + 100); }
      ctx.moveTo(d.x, d.y); ctx.lineTo(d.x + 2, d.y + 12);
    }
    ctx.stroke();
  }

  /* 目标方向箭头 */
  if (job && state === 'play') {
    const sx = job.x - camX, sy = job.y - camY;
    if (sx < 0 || sx > W || sy < 0 || sy > H) {
      const a = Math.atan2(sy - H / 2, sx - W / 2);
      const ex = W / 2 + Math.cos(a) * (W / 2 - 40), ey = H / 2 + Math.sin(a) * (H / 2 - 40);
      ctx.save(); ctx.translate(clamp(ex, 40, W - 40), clamp(ey, 40, H - 40)); ctx.rotate(a);
      ctx.fillStyle = job.phase === 'pickup' ? '#29e6ff' : '#4dff9d';
      ctx.beginPath(); ctx.moveTo(16, 0); ctx.lineTo(-8, -10); ctx.lineTo(-8, 10); ctx.closePath(); ctx.fill();
      ctx.restore();
    }
  }

  /* HUD */
  ctx.fillStyle = 'rgba(8,6,20,0.55)';
  ctx.fillRect(12, 12, 250, 78);
  ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
  ctx.font = 'bold 20px sans-serif';
  ctx.fillStyle = '#4dff9d';
  ctx.fillText('$ ' + cash, 24, 32);
  ctx.fillStyle = '#9aa0b5'; ctx.font = '13px sans-serif';
  ctx.fillText('最佳 $' + best, 150, 32);
  ctx.font = '18px sans-serif';
  ctx.fillStyle = '#ffd84d';
  ctx.fillText('★'.repeat(wanted) + '☆'.repeat(5 - wanted), 24, 56);
  ctx.fillStyle = '#cfd6ff'; ctx.font = '14px sans-serif';
  if (job) {
    if (job.phase === 'pickup') ctx.fillText('📦 前往取货点', 24, 78);
    else ctx.fillText(`🏁 送货中 · 剩 ${Math.max(0, job.tLeft).toFixed(0)} 秒 · $${job.pay}`, 24, 78);
  }

  ctx.drawImage(mini, W - 172, 12, 160, 160);
  ctx.strokeStyle = 'rgba(255,255,255,0.4)'; ctx.lineWidth = 2;
  ctx.strokeRect(W - 172, 12, 160, 160);
  const ms = 160 / WORLD;
  if (job) {
    ctx.fillStyle = job.phase === 'pickup' ? '#29e6ff' : '#4dff9d';
    ctx.beginPath(); ctx.arc(W - 172 + job.x * ms, 12 + job.y * ms, 4, 0, TAU); ctx.fill();
  }
  for (const c of cars) if (c.ai === 'police') {
    ctx.fillStyle = Math.floor(gameT * 6) % 2 ? '#ff4d4d' : '#4d8aff';
    ctx.beginPath(); ctx.arc(W - 172 + c.x * ms, 12 + c.y * ms, 3, 0, TAU); ctx.fill();
  }
  ctx.fillStyle = '#fff';
  ctx.beginPath(); ctx.arc(W - 172 + player.x * ms, 12 + player.y * ms, 3.5, 0, TAU); ctx.fill();

  if (player.car) {
    const sp = Math.round(Math.abs(player.car.f) * 0.6);
    ctx.textAlign = 'right';
    ctx.font = 'bold 30px sans-serif'; ctx.fillStyle = '#fff';
    ctx.fillText(sp, W - 70, H - 50);
    ctx.font = '14px sans-serif'; ctx.fillStyle = '#9aa0b5';
    ctx.fillText('km/h', W - 30, H - 46);
    const hp = clamp(player.car.health / 100, 0, 1);
    ctx.fillStyle = 'rgba(8,6,20,0.55)'; ctx.fillRect(W - 172, H - 34, 150, 12);
    ctx.fillStyle = hp > 0.4 ? '#4dff9d' : '#ff4d4d';
    ctx.fillRect(W - 170, H - 32, 146 * hp, 8);
  }

  ctx.textAlign = 'center';
  let my = H - 90;
  for (const m of msgs) {
    ctx.globalAlpha = clamp(m.life, 0, 1);
    ctx.font = 'bold 19px sans-serif';
    ctx.fillStyle = '#fff';
    ctx.fillText(m.t, W / 2, my); my -= 28;
  }
  ctx.globalAlpha = 1;

  if (bustFlash > 0) {
    ctx.fillStyle = Math.floor(gameT * 8) % 2 ? `rgba(255,40,40,${bustFlash * 0.2})` : `rgba(40,80,255,${bustFlash * 0.2})`;
    ctx.fillRect(0, 0, W, H);
  }

  /* 标题画面 */
  if (state === 'title') {
    ctx.fillStyle = 'rgba(8,5,22,0.78)';
    ctx.fillRect(0, 0, W, H);
    ctx.textAlign = 'center';
    const g = ctx.createLinearGradient(W / 2 - 220, 0, W / 2 + 220, 0);
    g.addColorStop(0, '#ff4fd8'); g.addColorStop(1, '#29e6ff');
    ctx.fillStyle = g;
    ctx.font = 'bold 64px sans-serif';
    ctx.fillText('霓 虹 都 市', W / 2, H / 2 - 80);
    ctx.font = '20px sans-serif'; ctx.fillStyle = '#cfd6ff';
    ctx.fillText('NEON CITY · 一座 80 年代的海滨之城，任你驰骋', W / 2, H / 2 - 30);
    ctx.font = '16px sans-serif'; ctx.fillStyle = '#9aa0b5';
    ctx.fillText('方向键开车 · E 上下车 · 空格漂移 · 送货赚钱 · 别让通缉星到五颗', W / 2, H / 2 + 10);
    if (Math.floor(performance.now() / 600) % 2 === 0) {
      ctx.font = 'bold 24px sans-serif'; ctx.fillStyle = '#ffd84d';
      ctx.fillText('按任意键 进入城市', W / 2, H / 2 + 70);
    }
  }
}

function drawCar(c, night) {
  ctx.save();
  ctx.translate(c.x, c.y);
  ctx.fillStyle = 'rgba(0,0,0,0.3)';
  ctx.beginPath(); ctx.ellipse(4, 5, 26, 14, c.a, 0, TAU); ctx.fill();
  ctx.rotate(c.a);
  if (c.wreck) {
    ctx.fillStyle = '#2a2a30';
    ctx.fillRect(-23, -11, 46, 22);
    ctx.fillStyle = '#1a1a1e';
    ctx.fillRect(-10, -8, 18, 16);
    ctx.restore();
    return;
  }
  ctx.fillStyle = '#15151c';                                       // 轮子
  ctx.fillRect(-18, -13, 9, 4); ctx.fillRect(9, -13, 9, 4);
  ctx.fillRect(-18, 9, 9, 4); ctx.fillRect(9, 9, 9, 4);
  ctx.fillStyle = c.c;                                             // 车身
  ctx.beginPath();
  ctx.moveTo(-23, -9); ctx.lineTo(16, -10); ctx.quadraticCurveTo(24, -7, 24, 0);
  ctx.quadraticCurveTo(24, 7, 16, 10); ctx.lineTo(-23, 9);
  ctx.quadraticCurveTo(-26, 5, -26, 0); ctx.quadraticCurveTo(-26, -5, -23, -9);
  ctx.closePath(); ctx.fill();
  ctx.fillStyle = 'rgba(15,20,40,0.85)';                           // 挡风玻璃
  ctx.fillRect(2, -7, 9, 14);
  ctx.fillRect(-14, -7, 7, 14);
  if (c.kind === 'taxi') {
    ctx.fillStyle = '#1a1a1e'; ctx.fillRect(-6, -5, 8, 10);
    ctx.fillStyle = '#fff'; ctx.font = 'bold 7px sans-serif';
    ctx.textAlign = 'center'; ctx.fillText('TAXI', -2, 1);
  }
  if (c.kind === 'sport') {
    ctx.fillStyle = 'rgba(255,255,255,0.55)';
    ctx.fillRect(-20, -1.5, 40, 3);
  }
  if (c.kind === 'police') {
    ctx.fillStyle = '#1a2a4a'; ctx.fillRect(-8, -10, 12, 20);
    const on = Math.floor(c.blink * 6) % 2 === 0;
    ctx.fillStyle = on ? '#ff3a3a' : '#7a1a1a'; ctx.fillRect(-5, -6, 5, 5);
    ctx.fillStyle = on ? '#1a3aaa' : '#3a6aff'; ctx.fillRect(-5, 1, 5, 5);
  }
  ctx.fillStyle = night > 0.3 ? '#fff8d0' : '#d8d8c0';             // 车灯
  ctx.fillRect(22, -8, 3, 4); ctx.fillRect(22, 4, 3, 4);
  ctx.fillStyle = (c === player.car && keys.down) ? '#ff2a2a' : '#a02020';
  ctx.fillRect(-26, -7, 3, 4); ctx.fillRect(-26, 3, 3, 4);
  ctx.restore();
}

/* ===================== 主循环 ===================== */
let last = performance.now();
function loop(now) {
  const dt = Math.min(0.033, (now - last) / 1000);
  last = now;
  if (state === 'play') update(dt);
  draw();
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
})();
