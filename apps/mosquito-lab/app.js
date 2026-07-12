/* 声波驱蚊实验室 —— 频率发生器 + 科普 */
(() => {
'use strict';
const $ = id => document.getElementById(id);

/* ===================== 频率发生器 ===================== */
let AC = null, osc = null, gain = null, playing = false;
const PRESETS = [
  { f: 18000, label: '18 kHz 超高频', note: '常见"驱蚊"宣传频率' },
  { f: 1000, label: '1 kHz 雄蚊翅振', note: '据说模拟雄蚊（无依据）' },
  { f: 12000, label: '12 kHz 蜻蜓说', note: '宣称模拟天敌蜻蜓' },
  { f: 40000, label: '40 kHz 蝙蝠超声', note: '远超人耳与多数设备上限' },
  { f: 440, label: '440 Hz 标准音', note: '听个响，校准音量用' },
];

function noteFor(f) {
  if (f >= 20000) return '超声波区，人耳几乎听不见，多数扬声器也发不出';
  if (f >= 16000) return '超高频，部分年轻人能听到';
  if (f >= 4000) return '高频尖锐声';
  if (f >= 500) return '中频';
  return '低频嗡鸣';
}
function setFreq(f) {
  f = Math.round(f);
  $('fNum').textContent = f;
  $('fNote').textContent = noteFor(f);
  $('fSlider').value = f;
  if (osc) osc.frequency.setValueAtTime(f, AC.currentTime);
}
function setVol() {
  if (gain && AC) gain.gain.setTargetAtTime(playing ? (+$('volSlider').value / 100) * 0.25 : 0, AC.currentTime, 0.02);
}
function start() {
  if (!AC) {
    AC = new (window.AudioContext || window.webkitAudioContext)();
    osc = AC.createOscillator(); gain = AC.createGain();
    osc.type = 'sine'; gain.gain.value = 0;
    osc.connect(gain); gain.connect(AC.destination);
    osc.start();
  }
  if (AC.state === 'suspended') AC.resume();
  setFreq(+$('fSlider').value);
  playing = true; setVol();
  const b = $('playBtn'); b.textContent = '■ 停止'; b.classList.add('on');
}
function stop() {
  playing = false; setVol();
  const b = $('playBtn'); b.textContent = '▶ 播放'; b.classList.remove('on');
}
$('playBtn').addEventListener('click', () => playing ? stop() : start());
$('fSlider').addEventListener('input', () => setFreq(+$('fSlider').value));
$('volSlider').addEventListener('input', setVol);

$('presets').innerHTML = PRESETS.map((p, i) =>
  `<button class="preset" data-i="${i}"><div class="pf">${p.label}</div><div class="pn">${p.note}</div></button>`).join('');
$('presets').addEventListener('click', e => {
  const b = e.target.closest('.preset');
  if (!b) return;
  setFreq(PRESETS[+b.dataset.i].f);
  if (!playing) start();
});

/* ===================== 理论辟谣 ===================== */
const THEORIES = [
  { t: '🦟 "模拟雄蚊翅膀振动，吓走刚交配过、不想再被打扰的雌蚊"',
    b: '这是最流行的说法。问题在于：受精后的雌蚊行为远比"避开雄蚊"复杂，并不会简单地被一个固定频率赶走；而且蚊子主要靠触角感受近场的空气振动，对远处扬声器发出的声波反应很弱。<b>实验中并未观察到驱赶效果。</b>' },
  { t: '🐉 "模拟蜻蜓等天敌的振翅声，让蚊子因恐惧而逃离"',
    b: '蚊子并没有被证实能通过特定声音识别并躲避天敌。蜻蜓捕食靠的是视觉与飞行围捕，不是发出某种"恐吓频率"。<b>这一理论缺乏实证支持。</b>' },
  { t: '🦇 "蝙蝠超声波（40 kHz 左右）能驱赶蚊子"',
    b: '两个硬伤：其一，普通手机/电脑扬声器根本发不出 40 kHz 的有效声压；其二，即便发出，研究也未发现蚊子会因此远离。<b>FTC 曾对类似宣传的产品提起虚假广告诉讼。</b>' },
  { t: '📱 "手机驱蚊 App 真的有用，下载量很高"',
    b: '下载量高不等于有效。这类 App 大多只是播放一段高频音，独立测评和科学研究都未能证明其能减少叮咬。高评分常源于安慰剂效应——"今晚没被咬"可能只是因为今晚蚊子本来就少。' },
  { t: '🔬 "Cochrane 综述到底说了什么？"',
    b: '2007 年 Enayati 等人在 Cochrane 数据库发表的系统综述，汇总了 10 项野外试验。结论非常明确：<b>电子（超声波）驱蚊器对防止蚊虫叮咬没有效果，不应推荐用于预防蚊媒疾病。</b>这是目前该领域被引用最多的权威结论之一。' },
];
$('theories').innerHTML = THEORIES.map(x =>
  `<details><summary>${x.t}</summary><div class="body">${x.b}</div></details>`).join('');

/* ===================== 背景：飞舞的蚊子 + 声波涟漪 ===================== */
const bg = $('bg'), c = bg.getContext('2d');
let bw, bh;
function resize() { bw = bg.width = innerWidth; bh = bg.height = innerHeight; }
addEventListener('resize', resize); resize();
const skeeters = Array.from({ length: 14 }, () => ({
  x: Math.random() * 2000, y: Math.random() * 2000,
  a: Math.random() * 6.28, s: 0.4 + Math.random() * 0.8, w: Math.random() * 6.28,
}));
function draw(t) {
  const g = c.createLinearGradient(0, 0, 0, bh);
  g.addColorStop(0, '#0a1822'); g.addColorStop(1, '#06101a');
  c.fillStyle = g; c.fillRect(0, 0, bw, bh);
  // 播放时的声波涟漪
  if (playing) {
    const cx = bw / 2, cy = bh * 0.22;
    for (let i = 0; i < 4; i++) {
      const r = ((t * 0.08 + i * 70) % 280);
      c.strokeStyle = `rgba(79,224,192,${0.4 * (1 - r / 280)})`;
      c.lineWidth = 2;
      c.beginPath(); c.arc(cx, cy, r, 0, 6.29); c.stroke();
    }
  }
  // 蚊子
  for (const m of skeeters) {
    m.a += Math.sin(t * 0.001 + m.w) * 0.04;
    let nx = m.x + Math.cos(m.a) * m.s, ny = m.y + Math.sin(m.a) * m.s;
    // 播放时蚊子"假装"被驱散（其实是彩蛋，科学上无效～）
    if (playing) {
      const dx = m.x - bw / 2, dy = m.y - bh * 0.22, d = Math.hypot(dx, dy);
      if (d < 240) { nx += dx / d * 1.5; ny += dy / d * 1.5; }
    }
    m.x = (nx + bw) % bw; m.y = (ny + bh) % bh;
    c.save(); c.translate(m.x % bw, m.y % bh); c.rotate(m.a);
    c.fillStyle = 'rgba(160,200,195,0.5)';
    c.beginPath(); c.ellipse(0, 0, 4, 1.6, 0, 0, 6.29); c.fill();
    c.strokeStyle = 'rgba(160,200,195,0.25)'; c.lineWidth = 0.8;
    const wf = Math.sin(t * 0.05 + m.w) * 2;
    c.beginPath(); c.moveTo(0, 0); c.lineTo(-3, -3 - wf); c.moveTo(0, 0); c.lineTo(-3, 3 + wf); c.stroke();
    c.restore();
  }
  requestAnimationFrame(draw);
}
requestAnimationFrame(draw);
})();
