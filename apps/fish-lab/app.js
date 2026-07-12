/* 声波诱鱼实验室 —— 低频发生器 + 科普 */
(() => {
'use strict';
const $ = id => document.getElementById(id);

/* ===================== 诱鱼音发生器 ===================== */
let AC = null, osc = null, gain = null, lfo = null, lfoGain = null, playing = false, pattern = null;
const PRESETS = [
  { f: 120, label: '120 Hz 低频纯音', note: '多数鱼听觉敏感区', mode: 'tone' },
  { f: 80, label: '80 Hz 进食脉冲', note: '模拟规律的"咚咚"投喂感', mode: 'pulse' },
  { f: 400, label: '400 Hz 中频', note: '部分鱼种可感知', mode: 'tone' },
  { f: 60, label: '60 Hz 低沉震动', note: '接近侧线感知下限', mode: 'tone' },
  { f: 1000, label: '1 kHz 高频对照', note: '多数鱼已较不敏感', mode: 'tone' },
];

function noteFor(f) {
  if (f >= 1500) return '高频，多数鱼类已不敏感';
  if (f >= 600) return '中高频';
  if (f >= 200) return '中频';
  if (f >= 50) return '低频区，多数鱼类听觉最敏感的范围';
  return '极低频，主要靠侧线感知的近场振动';
}
function setFreq(f) {
  f = Math.round(f / 5) * 5;
  $('fNum').textContent = f;
  $('fNote').textContent = noteFor(f);
  $('fSlider').value = f;
  if (osc) osc.frequency.setValueAtTime(f, AC.currentTime);
}
function applyVol() {
  if (!gain || !AC) return;
  const base = playing ? (+$('volSlider').value / 100) * 0.3 : 0;
  if (playing && pattern === 'pulse') {
    // 由 LFO 调制成脉冲；这里把基准电平交给 LFO 处理
    gain.gain.setTargetAtTime(base, AC.currentTime, 0.02);
  } else {
    gain.gain.setTargetAtTime(base, AC.currentTime, 0.02);
  }
}
function buildGraph() {
  AC = new (window.AudioContext || window.webkitAudioContext)();
  osc = AC.createOscillator(); osc.type = 'sine';
  gain = AC.createGain(); gain.gain.value = 0;
  osc.connect(gain); gain.connect(AC.destination);
  osc.start();
  // 脉冲调制用的 LFO
  lfo = AC.createOscillator(); lfo.type = 'square'; lfo.frequency.value = 2;
  lfoGain = AC.createGain(); lfoGain.gain.value = 0;     // 默认不调制
  lfo.connect(lfoGain); lfoGain.connect(gain.gain);
  lfo.start();
}
function start() {
  if (!AC) buildGraph();
  if (AC.state === 'suspended') AC.resume();
  setFreq(+$('fSlider').value);
  playing = true;
  applyVol();
  const b = $('playBtn'); b.textContent = '■ 停止'; b.classList.add('on');
}
function stop() {
  playing = false;
  applyVol();
  const b = $('playBtn'); b.textContent = '▶ 播放'; b.classList.remove('on');
}
function setMode(mode) {
  pattern = mode;
  if (!lfoGain || !AC) return;
  if (mode === 'pulse') { lfo.frequency.setValueAtTime(2.2, AC.currentTime); lfoGain.gain.setValueAtTime(0.12, AC.currentTime); }
  else lfoGain.gain.setValueAtTime(0, AC.currentTime);
}
$('playBtn').addEventListener('click', () => playing ? stop() : start());
$('fSlider').addEventListener('input', () => setFreq(+$('fSlider').value));
$('volSlider').addEventListener('input', applyVol);

$('presets').innerHTML = PRESETS.map((p, i) =>
  `<button class="preset" data-i="${i}"><div class="pf">${p.label}</div><div class="pn">${p.note}</div></button>`).join('');
$('presets').addEventListener('click', e => {
  const b = e.target.closest('.preset');
  if (!b) return;
  const p = PRESETS[+b.dataset.i];
  if (!AC) buildGraph();
  setMode(p.mode);
  setFreq(p.f);
  if (!playing) start();
});

/* ===================== 理论辨析 ===================== */
const THEORIES = [
  { t: '✅ "鱼能听见声音，低频尤其敏感" —— 成立',
    b: '这是有坚实生理学基础的。鱼通过内耳的耳石以及身体两侧的<b>侧线系统</b>感知声音和水流振动，多数硬骨鱼对约 <b>50–1000 Hz 的低频</b>最敏感，侧线还能捕捉 200 Hz 以下的近场颗粒运动。所以本发生器默认放在低频区。' },
  { t: '✅ "用声音训练鱼听声进食" —— 成立（条件反射）',
    b: '水产养殖里很常见：每次投喂前播放固定声音，重复多次后鱼群一听到声音就聚过来，这是经典的<b>巴甫洛夫条件反射</b>。但它依赖长期、固定环境下的训练，野外随机水域里临时放个声音，并不会有同样效果。' },
  { t: '🟡 "播放声音能把野生鱼吸引过来" —— 有证据但有限',
    b: '最有力的证据是 Gordon 等人 2019 年的研究：在退化珊瑚礁播放健康礁石的环境声，聚集的幼鱼数量约为对照的两倍。这说明声学诱集<b>在特定条件下确实有效</b>。但这是针对珊瑚礁鱼群的栖息地选择行为，能否照搬到你常钓的鲫鱼鲤鱼、能否胜过传统饵料打窝，<b>缺乏一致证据</b>。' },
  { t: '🟡 "市售电子诱鱼器很神" —— 普遍被夸大',
    b: '这类产品的独立测评结果参差不齐。核心问题：① 效果高度依赖鱼种、声音特性、水下传声条件；② 很多产品的实际声输出和宣传相去甚远。把它当作"也许有点用的辅助"可以，当成"渔获保证"就会失望。' },
  { t: '❗ "手机喇叭对着水面放就能诱鱼" —— 几乎无效',
    b: '物理硬伤：空气与水的<b>声阻抗相差约 3600 倍</b>，声音从空气打到水面，绝大部分能量被反射回去，真正进入水中的微乎其微。要作用于水下，必须用<b>防水水下扬声器/换能器</b>把声音直接送进水里。这也是本工具反复强调的前提。' },
];
$('theories').innerHTML = THEORIES.map(x =>
  `<details><summary>${x.t}</summary><div class="body">${x.b}</div></details>`).join('');

/* ===================== 背景：水波 + 游向声源的鱼 ===================== */
const bg = $('bg'), c = bg.getContext('2d');
let bw, bh;
function resize() { bw = bg.width = innerWidth; bh = bg.height = innerHeight; }
addEventListener('resize', resize); resize();
const fishes = Array.from({ length: 12 }, () => ({
  x: Math.random() * 2000, y: Math.random() * 2000,
  a: Math.random() * 6.28, s: 0.5 + Math.random() * 0.9, w: Math.random() * 6.28,
  size: 0.8 + Math.random() * 0.9, hue: 170 + Math.random() * 40,
}));
function draw(t) {
  const g = c.createLinearGradient(0, 0, 0, bh);
  g.addColorStop(0, '#073142'); g.addColorStop(1, '#04111a');
  c.fillStyle = g; c.fillRect(0, 0, bw, bh);
  // 水面光纹
  c.globalAlpha = 0.06;
  c.strokeStyle = '#aee8f0'; c.lineWidth = 2;
  for (let i = 0; i < 5; i++) {
    c.beginPath();
    for (let x = 0; x <= bw; x += 12) {
      const y = 40 + i * 26 + Math.sin(x * 0.02 + t * 0.0015 + i) * 6;
      x === 0 ? c.moveTo(x, y) : c.lineTo(x, y);
    }
    c.stroke();
  }
  c.globalAlpha = 1;
  const srcX = bw / 2, srcY = bh * 0.24;
  // 播放时声源涟漪
  if (playing) {
    for (let i = 0; i < 4; i++) {
      const r = ((t * 0.06 + i * 80) % 320);
      c.strokeStyle = `rgba(62,208,216,${0.4 * (1 - r / 320)})`;
      c.lineWidth = 2;
      c.beginPath(); c.arc(srcX, srcY, r, 0, 6.29); c.stroke();
    }
  }
  // 鱼
  for (const f of fishes) {
    if (playing) {
      // 朝声源游（诱鱼彩蛋——现实里要有效得满足上面那些前提哦）
      const want = Math.atan2(srcY - f.y, srcX - f.x);
      let d = want - f.a;
      while (d > Math.PI) d -= 6.28; while (d < -Math.PI) d += 6.28;
      f.a += d * 0.03;
    } else {
      f.a += Math.sin(t * 0.0007 + f.w) * 0.05;
    }
    f.x = (f.x + Math.cos(f.a) * f.s + bw) % bw;
    f.y = (f.y + Math.sin(f.a) * f.s + bh) % bh;
    c.save(); c.translate(f.x, f.y); c.rotate(f.a); c.scale(f.size, f.size);
    c.fillStyle = `hsla(${f.hue},55%,60%,0.55)`;
    c.beginPath(); c.ellipse(0, 0, 11, 4.5, 0, 0, 6.29); c.fill();   // 身体
    const tail = Math.sin(t * 0.02 + f.w) * 3;
    c.beginPath(); c.moveTo(-10, 0); c.lineTo(-17, -4 + tail); c.lineTo(-17, 4 + tail); c.closePath(); c.fill();  // 尾
    c.fillStyle = 'rgba(255,255,255,0.7)';
    c.beginPath(); c.arc(7, -1.2, 1.3, 0, 6.29); c.fill();           // 眼
    c.restore();
  }
  requestAnimationFrame(draw);
}
requestAnimationFrame(draw);
})();
