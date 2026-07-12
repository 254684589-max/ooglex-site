/* 房值罗盘 —— 住宅价值参考估算（静态参考数据，非实时行情） */
(() => {
'use strict';
const $ = id => document.getElementById(id);

/* ===================== 城市参考均价（万元/㎡，二手房量级参考，静态数据） ===================== */
const CITY_PRICE = {
  '北京':5.8,'上海':6.0,'深圳':6.3,'广州':3.6,
  '杭州':3.4,'南京':2.9,'苏州':2.4,'厦门':4.2,'天津':1.8,'武汉':1.5,'成都':1.7,
  '重庆':1.2,'西安':1.5,'长沙':1.1,'郑州':1.1,'青岛':1.7,'济南':1.4,'合肥':1.5,
  '福州':2.1,'宁波':2.1,'无锡':1.5,'佛山':1.3,'东莞':1.9,'珠海':2.1,'海口':1.5,
  '三亚':2.7,'昆明':1.1,'贵阳':0.9,'南宁':1.0,'太原':1.0,'石家庄':1.1,'哈尔滨':0.8,
  '长春':0.8,'沈阳':0.9,'大连':1.3,'兰州':0.9,'西宁':0.8,'银川':0.7,'乌鲁木齐':0.8,
  '呼和浩特':0.8,'南昌':1.1,'温州':1.9,'泉州':1.1,'烟台':1.0,'徐州':0.9,'常州':1.3,
  '南通':1.4,'嘉兴':1.3,'金华':1.4,'绍兴':1.5,'台州':1.5,'中山':1.1,'惠州':1.0,
  '保定':0.9,'廊坊':0.9,'唐山':0.9,'洛阳':0.8,'襄阳':0.7,'宜昌':0.7,'绵阳':0.8,
  '桂林':0.7,'遵义':0.6,'芜湖':0.9,'湖州':1.2,'潍坊':0.8,'临沂':0.8,'威海':0.9,
};
// 兜底：按行政级别给出量级
const FALLBACK = { 省会:1.1, 地级:0.75, 县镇:0.45 };
const PROVINCES = ['北京','上海','天津','重庆','河北','山西','辽宁','吉林','黑龙江','江苏','浙江','安徽','福建','江西','山东','河南','湖北','湖南','广东','海南','四川','贵州','云南','陕西','甘肃','青海','台湾','内蒙古','广西','西藏','宁夏','新疆','香港','澳门'];
const CAPITALS = ['石家庄','太原','沈阳','长春','哈尔滨','南京','杭州','合肥','福州','南昌','济南','郑州','武汉','长沙','广州','海口','成都','贵阳','昆明','西安','兰州','西宁','呼和浩特','南宁','拉萨','银川','乌鲁木齐'];

/* ===================== 地址解析（关键词启发式） ===================== */
function parseAddr(addr) {
  const r = { city: null, cityPrice: null, level: '', locFactor: 1, locDesc: [], province: '' };
  for (const p of PROVINCES) if (addr.includes(p)) { r.province = p; break; }
  // 找已知城市（取地址中最先出现者）
  let bestIdx = Infinity;
  for (const c of Object.keys(CITY_PRICE)) {
    const i = addr.indexOf(c);
    if (i >= 0 && i < bestIdx) { bestIdx = i; r.city = c; r.cityPrice = CITY_PRICE[c]; }
  }
  if (!r.city) {
    // 未收录城市：按 ××市 / ××县 / ××镇 推断级别
    const m = addr.match(/([一-龥]{2,8}?)市/);
    if (m && CAPITALS.includes(m[1])) { r.city = m[1]; r.cityPrice = FALLBACK.省会; r.level = '（未收录省会，按省会量级）'; }
    else if (m) { r.city = m[1] + '市'; r.cityPrice = FALLBACK.地级; r.level = '（未收录城市，按地级市量级）'; }
    else if (/县|镇|乡|村/.test(addr)) { r.city = '县镇区域'; r.cityPrice = FALLBACK.县镇; r.level = '（按县镇量级）'; }
    else { r.city = '未识别城市'; r.cityPrice = FALLBACK.地级; r.level = '（按一般城市量级）'; }
  }
  // 区位关键词
  const L = [
    [/中心|CBD|内环|一环|核心区|老城区?(?!.*郊)/, 1.25, '城市核心区位 ×1.25'],
    [/新区|高新|经开|开发区|科技城|自贸/, 1.08, '新区/高新区位 ×1.08'],
    [/郊|远郊|县|乡|村/, 0.72, '远郊/县乡区位 ×0.72'],
    [/镇(?!江|海|平)/, 0.8, '乡镇街道区位 ×0.8'],
  ];
  for (const [re, f, d] of L) {
    if (re.test(addr)) { r.locFactor = f; r.locDesc.push(d); break; }
  }
  if (r.locDesc.length === 0) r.locDesc.push('一般城区区位 ×1.0');
  return r;
}

/* ===================== 交互 ===================== */
document.querySelectorAll('.tg').forEach(b => b.addEventListener('click', () => b.classList.toggle('on')));

$('goBtn').addEventListener('click', () => {
  const addr = $('addr').value.trim();
  if (addr.length < 2) { $('addr').focus(); $('addr').placeholder = '请先输入地址哦～'; return; }
  const area = +$('area').value || 89;
  const info = parseAddr(addr);

  const factors = [];
  let f = info.locFactor;
  factors.push([`📍 ${info.city}${info.level} 参考均价`, info.cityPrice.toFixed(2) + ' 万/㎡']);
  factors.push(['🗺️ ' + info.locDesc[0].split(' ×')[0], '×' + info.locFactor]);
  const age = +$('age').value, deco = +$('deco').value, floor = +$('floor').value;
  f *= age * deco * floor;
  factors.push(['🏗️ 房龄系数', '×' + age]);
  factors.push(['🎨 装修系数', '×' + deco]);
  factors.push(['🛗 楼层系数', '×' + floor]);
  document.querySelectorAll('.tg.on').forEach(b => {
    f *= +b.dataset.f;
    factors.push([b.textContent.trim(), '×' + b.dataset.f]);
  });

  const unit = info.cityPrice * 10000 * f;        // 元/㎡ 中值
  const lo = unit * 0.8, hi = unit * 1.2;          // ±20% 区间
  const total = unit * area / 10000;               // 万元

  $('locLine').innerHTML = `识别结果：<b>${info.province ? info.province + ' · ' : ''}${info.city}</b> ｜ ${info.locDesc[0].split(' ×')[0]} ｜ 面积 ${area}㎡`;
  $('unitPrice').textContent = Math.round(unit).toLocaleString();
  $('totalPrice').textContent = total >= 1000 ? (total / 10000).toFixed(2) + ' 亿元' : Math.round(total).toLocaleString() + ' 万元';
  $('totalRange').textContent = `（区间 ${Math.round(total * 0.8)} ~ ${Math.round(total * 1.2)} 万）`;
  $('factors').innerHTML = factors.map(x => `<div><span>${x[0]}</span><span>${x[1]}</span></div>`).join('');
  $('result').style.display = 'block';
  drawGauge(lo, unit, hi);
  $('result').scrollIntoView({ behavior: 'smooth' });
});

/* ===================== 罗盘仪表动画 ===================== */
let animId = null;
function drawGauge(lo, mid, hi) {
  const cv = $('gauge'), c = cv.getContext('2d');
  const W = cv.width, H = cv.height, cx = W / 2, cy = H - 16, R = 120;
  let prog = 0;
  cancelAnimationFrame(animId);
  (function frame() {
    prog = Math.min(1, prog + 0.03);
    c.clearRect(0, 0, W, H);
    // 弧带
    const grad = c.createLinearGradient(cx - R, 0, cx + R, 0);
    grad.addColorStop(0, '#5ad8a0'); grad.addColorStop(0.5, '#f0c060'); grad.addColorStop(1, '#f0796a');
    c.strokeStyle = grad; c.lineWidth = 16; c.lineCap = 'round';
    c.beginPath(); c.arc(cx, cy, R, Math.PI, 0); c.stroke();
    // 刻度文字
    c.fillStyle = '#93a4be'; c.font = '12px sans-serif'; c.textAlign = 'center';
    c.fillText(Math.round(lo).toLocaleString(), cx - R, cy + 14);
    c.fillText(Math.round(hi).toLocaleString(), cx + R, cy + 14);
    c.fillText('元/㎡ 参考区间', cx, cy + 14);
    // 指针（从左摆到中值，带回弹）
    const ease = 1 - Math.pow(1 - prog, 3);
    const ang = Math.PI + ease * (Math.PI / 2) + Math.sin(prog * Math.PI) * 0.06;
    c.save(); c.translate(cx, cy); c.rotate(ang);
    c.strokeStyle = '#e9eef7'; c.lineWidth = 3;
    c.beginPath(); c.moveTo(0, 0); c.lineTo(R - 26, 0); c.stroke();
    c.fillStyle = '#f0c060';
    c.beginPath(); c.arc(0, 0, 7, 0, 6.29); c.fill();
    c.restore();
    if (prog < 1) animId = requestAnimationFrame(frame);
  })();
}

/* ===================== 背景：城市天际线 ===================== */
const bg = $('bg'), bc = bg.getContext('2d');
let bw, bh, blds = [];
function resize() {
  bw = bg.width = innerWidth; bh = bg.height = innerHeight;
  blds = [];
  let x = 0;
  while (x < bw) {
    const w = 30 + Math.random() * 60, h = 60 + Math.random() * bh * 0.3;
    blds.push({ x, w, h, win: Math.random() });
    x += w + 4;
  }
}
addEventListener('resize', resize); resize();
function draw(t) {
  const g = bc.createLinearGradient(0, 0, 0, bh);
  g.addColorStop(0, '#15233a'); g.addColorStop(0.7, '#101622'); g.addColorStop(1, '#0b101a');
  bc.fillStyle = g; bc.fillRect(0, 0, bw, bh);
  bc.fillStyle = 'rgba(233,238,247,0.7)';
  bc.beginPath(); bc.arc(bw * 0.82, bh * 0.16, 26, 0, 6.29); bc.fill();
  for (const b of blds) {
    bc.fillStyle = 'rgba(20,32,52,0.9)';
    bc.fillRect(b.x, bh - b.h, b.w, b.h);
    // 窗灯闪烁
    const rows = Math.floor(b.h / 18), cols = Math.floor(b.w / 14);
    for (let r = 0; r < rows; r++) for (let cc = 0; cc < cols; cc++) {
      const on = Math.sin(t * 0.0004 + b.win * 50 + r * 3.1 + cc * 7.7) > 0.55;
      if (on) {
        bc.fillStyle = 'rgba(240,192,96,0.5)';
        bc.fillRect(b.x + 4 + cc * 14, bh - b.h + 6 + r * 18, 6, 8);
      }
    }
  }
  requestAnimationFrame(draw);
}
requestAnimationFrame(draw);
})();
