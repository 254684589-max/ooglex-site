/* 万象算集 · 计算器大全  —— 数据驱动引擎（分类 + 搜索 + 可无限扩展） */
(() => {
'use strict';
const $ = id => document.getElementById(id);
const fmt = (n, d = 2) => Number(n).toLocaleString('zh-CN', { maximumFractionDigits: d });
const bad = '<p style="color:#f08a7a">请检查输入是否完整、有效</p>';

/* ===================== 山水雾霭背景 ===================== */
const bg = $('bg'), bc = bg.getContext('2d');
let bw = 0, bh = 0;
function resize() { bw = bg.width = innerWidth; bh = bg.height = innerHeight; }
addEventListener('resize', resize); resize();
function mountain(yBase, amp, step, seedK) {
  bc.beginPath();
  bc.moveTo(-50, bh);
  for (let x = -50; x <= bw + 50; x += step) {
    const y = yBase
      + Math.sin(x * 0.004 + seedK) * amp
      + Math.sin(x * 0.011 + seedK * 2.7) * amp * 0.4;
    bc.lineTo(x, y);
  }
  bc.lineTo(bw + 50, bh);
  bc.closePath();
  bc.fill();
}
function drawBg(t) {
  const g = bc.createLinearGradient(0, 0, 0, bh);
  g.addColorStop(0, '#11303a'); g.addColorStop(0.55, '#0e2530'); g.addColorStop(1, '#0a1a20');
  bc.fillStyle = g; bc.fillRect(0, 0, bw, bh);
  bc.fillStyle = 'rgba(230,245,240,0.75)';                 // 月
  bc.beginPath(); bc.arc(bw * 0.78, bh * 0.18, 34, 0, 6.29); bc.fill();
  bc.fillStyle = 'rgba(26,60,66,0.55)';  mountain(bh * 0.52, 60, 14, 1.3);
  bc.fillStyle = 'rgba(20,48,54,0.75)';  mountain(bh * 0.64, 75, 12, 4.1);
  bc.fillStyle = 'rgba(14,36,42,0.95)';  mountain(bh * 0.78, 90, 10, 7.9);
  for (let i = 0; i < 3; i++) {                             // 流动雾霭
    const mx = ((t * 0.012 * (i + 1) + i * 500) % (bw + 700)) - 350;
    const my = bh * (0.55 + i * 0.12);
    const mg = bc.createRadialGradient(mx, my, 10, mx, my, 260);
    mg.addColorStop(0, 'rgba(190,225,220,0.10)'); mg.addColorStop(1, 'rgba(190,225,220,0)');
    bc.fillStyle = mg;
    bc.beginPath(); bc.ellipse(mx, my, 320, 70, 0, 0, 6.29); bc.fill();
  }
}
(function loop(t) { drawBg(t || 0); requestAnimationFrame(loop); })();

/* ===================== 分类 ===================== */
const CATS = [
  { id: 'finance', icon: '💰', name: '金融理财' },
  { id: 'health',  icon: '❤️', name: '健康身体' },
  { id: 'math',    icon: '🔢', name: '数学几何' },
  { id: 'convert', icon: '🔄', name: '单位换算' },
  { id: 'physics', icon: '⚛️', name: '物理' },
  { id: 'chem',    icon: '🧪', name: '化学' },
  { id: 'daily',   icon: '📅', name: '日常生活' },
  { id: 'tools',   icon: '🧰', name: '实用工具' },
];
const catName = id => (CATS.find(c => c.id === id) || {}).name || '';

const CALCS = [];
const reg = c => CALCS.push(c);

/* ===================== 表单渲染 ===================== */
function renderField(f) {
  const id = 'in_' + f.id;
  let ctrl;
  if (f.type === 'select') {
    ctrl = `<select id="${id}">` + f.options.map(o => {
      const v = (o && o.v !== undefined) ? o.v : o;
      const t = (o && o.t !== undefined) ? o.t : o;
      const sel = (f.value !== undefined && String(f.value) === String(v)) ? ' selected' : '';
      return `<option value="${v}"${sel}>${t}</option>`;
    }).join('') + `</select>`;
  } else if (f.type === 'textarea') {
    return `<div class="field full"><label>${f.label}</label><textarea id="${id}" rows="${f.rows || 4}" placeholder="${f.ph || ''}">${f.value || ''}</textarea></div>`;
  } else {
    const t = f.type || 'number';
    let a = `type="${t}" id="${id}"`;
    if (f.value !== undefined) a += ` value="${f.value}"`;
    if (f.step !== undefined) a += ` step="${f.step}"`;
    if (f.min !== undefined) a += ` min="${f.min}"`;
    if (f.max !== undefined) a += ` max="${f.max}"`;
    if (f.ph) a += ` placeholder="${f.ph}"`;
    ctrl = `<input ${a}>`;
  }
  return `<div class="field${f.full ? ' full' : ''}" id="wrap_${f.id}"><label>${f.label}</label>${ctrl}</div>`;
}
function renderForm(c) {
  return `<div class="form">${c.inputs.map(renderField).join('')}</div>`
    + `<button class="calcBtn">${c.btn || '计 算'}</button>`
    + (c.hint ? `<p class="hint">${c.hint}</p>` : '');
}
const val = {
  n: id => parseFloat($('in_' + id).value),
  s: id => $('in_' + id).value,
  b: id => $('in_' + id).checked,
};

/* ===================== 视图框架 ===================== */
let curCat = null;
function tilesCat() {
  return CATS.map(c => {
    const n = CALCS.filter(x => x.cat === c.id).length;
    return `<div class="tile" data-cat="${c.id}"><span class="ic">${c.icon}</span><h3>${c.name}</h3><p class="cnt">${n} 个计算器 →</p></div>`;
  }).join('');
}
function tilesCalc(list) {
  return list.map(c => `<div class="tile" data-calc="${CALCS.indexOf(c)}"><span class="ic">${c.icon}</span><h3>${c.name}</h3><p>${c.desc}</p></div>`).join('')
    || `<p style="color:var(--dim)">没有匹配的计算器，换个关键词试试～</p>`;
}
function renderHome() {
  $('panel').style.display = 'none';
  const h = $('home'); h.style.display = 'grid';
  const q = ($('q').value || '').trim().toLowerCase();
  if (q) {
    curCat = null;
    $('crumb').innerHTML = `搜索“${q}” 的结果`;
    const list = CALCS.filter(c => (c.name + c.desc + (c.kw || '')).toLowerCase().includes(q));
    h.innerHTML = tilesCalc(list);
  } else if (curCat) {
    $('crumb').innerHTML = `<a data-home="1">← 算集首页</a> &nbsp;›&nbsp; <b style="color:var(--text)">${catName(curCat)}</b>`;
    h.innerHTML = tilesCalc(CALCS.filter(c => c.cat === curCat));
  } else {
    $('crumb').innerHTML = `共 <b style="color:var(--jade)">${CALCS.length}</b> 个计算器 · 分为 ${CATS.length} 大类，点分类进入或直接搜索`;
    h.innerHTML = tilesCat();
  }
}
function open(idx) {
  const c = CALCS[idx];
  $('home').style.display = 'none';
  const p = $('panel'); p.style.display = 'block';
  const body = c.custom ? c.body : renderForm(c);
  p.innerHTML = `<button class="backBtn">← 返回列表</button>
    <h2>${c.icon} ${c.name}</h2><p class="sub">${c.desc}</p>${body}
    <div class="out" id="out"></div>`;
  p.querySelector('.backBtn').addEventListener('click', () => { p.style.display = 'none'; renderHome(); window.scrollTo({ top: 0 }); });
  c.init && c.init();
  const btn = p.querySelector('.calcBtn');
  if (btn && c.run) btn.addEventListener('click', () => {
    const r = c.run(val);
    if (r != null) { $('out').innerHTML = r; $('out').style.display = 'block'; }
  });
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

/* ==================================================================== */
/* ===========================  计 算 器 库  ========================== */
/* ==================================================================== */

/* ---------------------- 💰 金融理财 ---------------------- */
reg({ cat: 'finance', icon: '🏠', name: '房贷计算器', desc: '等额本息 / 等额本金，月供与总利息一目了然', kw: '贷款 按揭 mortgage 房子',
  inputs: [
    { id: 'amt', label: '贷款总额（万元）', value: 100 },
    { id: 'rate', label: '年利率（%）', value: 3.6, step: 0.05 },
    { id: 'years', label: '贷款年限', type: 'select', options: [5, 10, 15, 20, 25, 30], value: 30 },
    { id: 'type', label: '还款方式', type: 'select', options: [{ v: 'bx', t: '等额本息' }, { v: 'bj', t: '等额本金' }] },
  ],
  run: v => {
    const P = v.n('amt') * 10000, r = v.n('rate') / 100 / 12, n = v.n('years') * 12;
    if (!(P > 0 && r >= 0 && n > 0)) return bad;
    if (v.s('type') === 'bx') {
      const m = r === 0 ? P / n : P * r * Math.pow(1 + r, n) / (Math.pow(1 + r, n) - 1);
      return `每月月供：<span class="big">¥ ${fmt(m)}</span><br>支付利息总额：<b>¥ ${fmt(m * n - P)}</b><br>还款总额：<b>¥ ${fmt(m * n)}</b>`;
    }
    const first = P / n + P * r, last = P / n + (P / n) * r, ti = P * r * (n + 1) / 2;
    return `首月月供：<span class="big">¥ ${fmt(first)}</span>（此后逐月递减）<br>末月月供：<b>¥ ${fmt(last)}</b> · 每月递减约 ¥ ${fmt(P / n * r)}<br>支付利息总额：<b>¥ ${fmt(ti)}</b><br>还款总额：<b>¥ ${fmt(P + ti)}</b>`;
  } });

reg({ cat: 'finance', icon: '💳', name: '通用贷款计算器', desc: '车贷/消费贷等额本息，按月计算月供与利息', kw: '车贷 分期 loan',
  inputs: [
    { id: 'amt', label: '贷款金额（元）', value: 100000 },
    { id: 'rate', label: '年利率（%）', value: 5, step: 0.1 },
    { id: 'months', label: '期限（月）', value: 36 },
  ],
  run: v => {
    const P = v.n('amt'), r = v.n('rate') / 100 / 12, n = v.n('months');
    if (!(P > 0 && n > 0)) return bad;
    const m = r === 0 ? P / n : P * r * Math.pow(1 + r, n) / (Math.pow(1 + r, n) - 1);
    return `每月还款：<span class="big">¥ ${fmt(m)}</span><br>总利息：<b>¥ ${fmt(m * n - P)}</b> · 总还款 <b>¥ ${fmt(m * n)}</b>`;
  } });

reg({ cat: 'finance', icon: '📈', name: '复利计算器', desc: '本金加定投，看时间如何滚出雪球', kw: '投资 定投 利滚利',
  inputs: [
    { id: 'P', label: '初始本金（元）', value: 10000 },
    { id: 'm', label: '每月追加（元）', value: 1000 },
    { id: 'r', label: '预期年化收益率（%）', value: 4, step: 0.1 },
    { id: 'y', label: '投资年数', value: 10 },
  ],
  run: v => {
    const P = v.n('P') || 0, m = v.n('m') || 0, i = v.n('r') / 100 / 12, n = v.n('y') * 12;
    if (!(n > 0)) return bad;
    const fv = i === 0 ? P + m * n : P * Math.pow(1 + i, n) + m * (Math.pow(1 + i, n) - 1) / i;
    const invest = P + m * n;
    return `到期总额：<span class="big">¥ ${fmt(fv)}</span><br>累计投入：<b>¥ ${fmt(invest)}</b><br>利息收益：<b>¥ ${fmt(fv - invest)}</b>（收益率 ${fmt((fv / invest - 1) * 100, 1)}%）`;
  } });

reg({ cat: 'finance', icon: '💵', name: '单利计算器', desc: '本金按固定年利率的简单利息', kw: '利息 存款',
  inputs: [
    { id: 'P', label: '本金（元）', value: 10000 },
    { id: 'r', label: '年利率（%）', value: 3, step: 0.1 },
    { id: 't', label: '年数', value: 5 },
  ],
  run: v => {
    const P = v.n('P'), r = v.n('r') / 100, t = v.n('t');
    if (!(P > 0 && t > 0)) return bad;
    const it = P * r * t;
    return `利息：<span class="big">¥ ${fmt(it)}</span><br>本息合计：<b>¥ ${fmt(P + it)}</b>`;
  } });

reg({ cat: 'finance', icon: '🧾', name: '个税估算器', desc: '按年度综合所得税率表估算（简化版）', kw: '工资 税 个人所得税',
  inputs: [
    { id: 's', label: '税前月薪（元）', value: 15000 },
    { id: 'i', label: '每月社保公积金（元）', value: 2000 },
    { id: 'd', label: '每月专项附加扣除（元）', value: 1500 },
  ],
  hint: '注：按 5000 元/月基本减除与年度综合所得税率表估算，未含年终奖单独计税等情形，结果仅供参考。',
  run: v => {
    const s = v.n('s'), ii = v.n('i') || 0, dd = v.n('d') || 0;
    const annual = (s - ii - dd - 5000) * 12;
    if (isNaN(annual)) return bad;
    const taxable = Math.max(0, annual);
    const B = [[36000, 0.03, 0], [144000, 0.1, 2520], [300000, 0.2, 16920], [420000, 0.25, 31920], [660000, 0.3, 52920], [960000, 0.35, 85920], [Infinity, 0.45, 181920]];
    let tax = 0;
    for (const [cap, rate, ded] of B) if (taxable <= cap) { tax = taxable * rate - ded; break; }
    return `应纳税所得额（年）：<b>¥ ${fmt(taxable)}</b><br>全年个税约：<span class="big">¥ ${fmt(tax)}</span><br>平均每月：<b>¥ ${fmt(tax / 12)}</b> · 税后月入约 <b>¥ ${fmt(s - ii - tax / 12)}</b>`;
  } });

reg({ cat: 'finance', icon: '🎯', name: '储蓄目标计算器', desc: '定存 + 每月存入，多久能攒到目标金额', kw: '攒钱 存钱 目标',
  inputs: [
    { id: 'target', label: '目标金额（元）', value: 100000 },
    { id: 'cur', label: '当前已有（元）', value: 0 },
    { id: 'm', label: '每月存入（元）', value: 2000 },
    { id: 'rate', label: '预期年化（%）', value: 3, step: 0.1 },
  ],
  run: v => {
    const target = v.n('target'), P = v.n('cur') || 0, m = v.n('m') || 0, i = v.n('rate') / 100 / 12;
    if (!(target > 0 && m >= 0)) return bad;
    if (P >= target) return `你已经达成目标啦 🎉`;
    let bal = P, months = 0;
    while (bal < target && months < 1200) { bal = bal * (1 + i) + m; months++; }
    if (months >= 1200) return `按当前投入，100 年内难以达成，试试提高每月存入或收益率。`;
    return `预计需要：<span class="big">${months} 个月</span>（约 ${fmt(months / 12, 1)} 年）<br>到时本息合计：<b>¥ ${fmt(bal)}</b> · 累计存入本金 <b>¥ ${fmt(P + m * months)}</b>`;
  } });

reg({ cat: 'finance', icon: '📊', name: '投资回报率 ROI', desc: '算总回报率，填了年数还给年化收益率', kw: '收益 回报 annualized',
  inputs: [
    { id: 'cost', label: '投入成本（元）', value: 10000 },
    { id: 'ret', label: '最终回收（元）', value: 13000 },
    { id: 'years', label: '投资年数（选填）', value: '', min: 0 },
  ],
  run: v => {
    const c = v.n('cost'), r = v.n('ret');
    if (!(c > 0) || isNaN(r)) return bad;
    const roi = (r - c) / c * 100, y = v.n('years');
    let out = `净收益：<span class="big">¥ ${fmt(r - c)}</span><br>总回报率 ROI：<b>${fmt(roi, 2)}%</b>`;
    if (y > 0) out += `<br>年化收益率：<b>${fmt((Math.pow(r / c, 1 / y) - 1) * 100, 2)}%</b>`;
    return out;
  } });

reg({ cat: 'finance', icon: '📉', name: '通货膨胀计算器', desc: '看看今天的钱，若干年后还值多少', kw: '购买力 贬值 inflation',
  inputs: [
    { id: 'amt', label: '金额（元）', value: 10000 },
    { id: 'rate', label: '年通胀率（%）', value: 3, step: 0.1 },
    { id: 'years', label: '年数', value: 10 },
  ],
  run: v => {
    const a = v.n('amt'), r = v.n('rate') / 100, n = v.n('years');
    if (isNaN(a) || isNaN(r) || !(n >= 0)) return bad;
    return `今天的 ¥${fmt(a)}，${n} 年后……<br>要保持同样购买力需要 <span class="big">¥ ${fmt(a * Math.pow(1 + r, n))}</span><br>而这笔钱届时实际购买力仅相当于今天的 <b>¥ ${fmt(a / Math.pow(1 + r, n))}</b>`;
  } });

reg({ cat: 'finance', icon: '🏷️', name: '折扣计算器', desc: '打折后到底多少钱、省了多少', kw: '打折 优惠 省钱 discount',
  inputs: [
    { id: 'price', label: '原价（元）', value: 199 },
    { id: 'off', label: '折扣（%，如立减 30% 填 30）', value: 30 },
  ],
  run: v => {
    const p = v.n('price'), o = v.n('off');
    if (!(p > 0) || isNaN(o)) return bad;
    const now = p * (1 - o / 100);
    return `现价：<span class="big">¥ ${fmt(now)}</span><br>已省：<b>¥ ${fmt(p - now)}</b> · 相当于打 <b>${fmt((1 - o / 100) * 10, 1)} 折</b>`;
  } });

reg({ cat: 'finance', icon: '🍽️', name: '小费计算器', desc: '账单加小费，还能按人数平摊', kw: '小费 tip 服务费',
  inputs: [
    { id: 'bill', label: '账单金额（元）', value: 200 },
    { id: 'pct', label: '小费比例（%）', value: 10 },
    { id: 'ppl', label: '分账人数', value: 1 },
  ],
  run: v => {
    const b = v.n('bill'), p = v.n('pct'), ppl = v.n('ppl') || 1;
    if (!(b > 0)) return bad;
    const tip = b * p / 100, total = b + tip;
    return `小费：<span class="big">¥ ${fmt(tip)}</span><br>合计：<b>¥ ${fmt(total)}</b>${ppl > 1 ? ` · 每人 <b>¥ ${fmt(total / ppl)}</b>` : ''}`;
  } });

reg({ cat: 'finance', icon: '🧮', name: '含税价 / 税额', desc: '由不含税金额与税率算出税额与含税价', kw: '增值税 vat 税率',
  inputs: [
    { id: 'amt', label: '不含税金额（元）', value: 1000 },
    { id: 'rate', label: '税率（%）', value: 13, step: 0.5 },
  ],
  run: v => {
    const a = v.n('amt'), r = v.n('rate') / 100;
    if (!(a >= 0)) return bad;
    const tax = a * r;
    return `税额：<span class="big">¥ ${fmt(tax)}</span><br>含税价：<b>¥ ${fmt(a + tax)}</b>`;
  } });

/* ---------------------- ❤️ 健康身体 ---------------------- */
reg({ cat: 'health', icon: '⚖️', name: 'BMI 计算器', desc: '身体质量指数，了解体重是否健康', kw: '体重 胖瘦 身高',
  inputs: [
    { id: 'h', label: '身高（厘米）', value: 170 },
    { id: 'w', label: '体重（公斤）', value: 65 },
  ],
  run: v => {
    const h = v.n('h') / 100, w = v.n('w');
    if (!(h > 0 && w > 0)) return bad;
    const bmi = w / h / h;
    const lv = bmi < 18.5 ? '偏瘦 🍃' : bmi < 24 ? '正常 ✅' : bmi < 28 ? '超重 ⚠️' : '肥胖 ❗';
    return `你的 BMI：<span class="big">${fmt(bmi, 1)}</span> —— <b>${lv}</b><br>该身高的健康体重区间：<b>${fmt(18.5 * h * h, 1)} ~ ${fmt(24 * h * h, 1)} kg</b><br><span class="sub">（按中国成人标准：18.5 ~ 24 为正常）</span>`;
  } });

reg({ cat: 'health', icon: '🔥', name: '热量计算器', desc: '基础代谢与每日消耗，减脂增肌心里有数', kw: 'bmr tdee 卡路里 热量',
  inputs: [
    { id: 'g', label: '性别', type: 'select', options: [{ v: 'm', t: '男' }, { v: 'f', t: '女' }] },
    { id: 'a', label: '年龄', value: 28 },
    { id: 'h', label: '身高（厘米）', value: 170 },
    { id: 'w', label: '体重（公斤）', value: 65 },
    { id: 'act', label: '日常活动量', type: 'select', full: true, value: '1.55', options: [
      { v: '1.2', t: '久坐少动（办公室为主）' }, { v: '1.375', t: '轻度活动（每周运动 1-3 次）' },
      { v: '1.55', t: '中度活动（每周运动 3-5 次）' }, { v: '1.725', t: '高度活动（每周运动 6-7 次）' },
      { v: '1.9', t: '超高强度（体力劳动/专业训练）' }] },
  ],
  run: v => {
    const g = v.s('g'), a = v.n('a'), h = v.n('h'), w = v.n('w'), act = v.n('act');
    if (!(a > 0 && h > 0 && w > 0)) return bad;
    const bmr = 10 * w + 6.25 * h - 5 * a + (g === 'm' ? 5 : -161);
    const tdee = bmr * act;
    return `基础代谢（BMR）：<span class="big">${fmt(bmr, 0)} 千卡/天</span><br>每日总消耗（TDEE）：<b>${fmt(tdee, 0)} 千卡/天</b><br>温和减脂参考：<b>${fmt(tdee - 400, 0)}</b> · 增肌参考：<b>${fmt(tdee + 300, 0)} 千卡/天</b>`;
  } });

reg({ cat: 'health', icon: '📐', name: '体脂率估算', desc: '按身高体重年龄估算体脂百分比', kw: '体脂 肥肉 bodyfat',
  inputs: [
    { id: 'sex', label: '性别', type: 'select', options: [{ v: 'm', t: '男' }, { v: 'f', t: '女' }] },
    { id: 'age', label: '年龄', value: 28 },
    { id: 'h', label: '身高（厘米）', value: 170 },
    { id: 'w', label: '体重（公斤）', value: 65 },
  ],
  run: v => {
    const h = v.n('h') / 100, w = v.n('w'), a = v.n('age'), s = v.s('sex') === 'm' ? 1 : 0;
    if (!(h > 0 && w > 0 && a > 0)) return bad;
    const bmi = w / h / h, bf = 1.2 * bmi + 0.23 * a - 10.8 * s - 5.4;
    return `体脂率（估算）：<span class="big">${fmt(bf, 1)}%</span><br><span class="sub">基于 Deurenberg 公式，仅供参考，精确测量请用体脂仪 / InBody</span>`;
  } });

reg({ cat: 'health', icon: '🎯', name: '理想体重', desc: 'Devine 公式，按身高性别给参考体重', kw: '标准体重 理想',
  inputs: [
    { id: 'sex', label: '性别', type: 'select', options: [{ v: 'm', t: '男' }, { v: 'f', t: '女' }] },
    { id: 'h', label: '身高（厘米）', value: 170 },
  ],
  run: v => {
    const inch = v.n('h') / 2.54;
    if (!(inch > 0)) return bad;
    const ideal = (v.s('sex') === 'm' ? 50 : 45.5) + 2.3 * (inch - 60);
    return `理想体重（Devine）：<span class="big">${fmt(ideal, 1)} kg</span><br><span class="sub">健康区间约 ${fmt(ideal * 0.9, 1)} ~ ${fmt(ideal * 1.1, 1)} kg</span>`;
  } });

reg({ cat: 'health', icon: '💧', name: '每日饮水量', desc: '按体重估算每天该喝多少水', kw: '喝水 水 hydration',
  inputs: [{ id: 'w', label: '体重（公斤）', value: 65 }],
  run: v => {
    const w = v.n('w');
    if (!(w > 0)) return bad;
    const ml = w * 35;
    return `建议每日饮水：<span class="big">${fmt(ml, 0)} 毫升</span>（约 ${fmt(ml / 1000, 2)} 升）<br><span class="sub">约合 ${fmt(ml / 250, 1)} 杯（每杯 250ml）· 运动 / 高温需适当增加</span>`;
  } });

reg({ cat: 'health', icon: '💓', name: '目标心率区间', desc: '按年龄（可选静息心率）给出运动心率区', kw: '心率 跑步 燃脂 karvonen',
  inputs: [
    { id: 'age', label: '年龄', value: 28 },
    { id: 'rest', label: '静息心率（选填，次/分）', value: '' },
  ],
  run: v => {
    const a = v.n('age');
    if (!(a > 0)) return bad;
    const max = 220 - a, rest = v.n('rest');
    const zone = (lo, hi) => rest > 0
      ? `${fmt((max - rest) * lo + rest, 0)} ~ ${fmt((max - rest) * hi + rest, 0)}`
      : `${fmt(max * lo, 0)} ~ ${fmt(max * hi, 0)}`;
    return `最大心率：<span class="big">${max} 次/分</span><br><table>
      <tr><td>热身 (50-60%)</td><td>${zone(.5, .6)}</td></tr>
      <tr><td>燃脂 (60-70%)</td><td>${zone(.6, .7)}</td></tr>
      <tr><td>有氧 (70-80%)</td><td>${zone(.7, .8)}</td></tr>
      <tr><td>无氧 (80-90%)</td><td>${zone(.8, .9)}</td></tr></table>`;
  } });

reg({ cat: 'health', icon: '❤️', name: '最大心率', desc: '两种常用公式估算你的最大心率', kw: '心率 上限',
  inputs: [{ id: 'age', label: '年龄', value: 28 }],
  run: v => {
    const a = v.n('age');
    if (!(a > 0)) return bad;
    return `经典公式 (220−年龄)：<span class="big">${220 - a} 次/分</span><br>Tanaka 公式 (208−0.7×年龄)：<b>${fmt(208 - 0.7 * a, 0)} 次/分</b>`;
  } });

reg({ cat: 'health', icon: '🤰', name: '预产期计算器', desc: '由末次月经推算预产期与当前孕周', kw: '怀孕 孕期 due date',
  inputs: [{ id: 'lmp', label: '末次月经首日', type: 'date' }],
  init() { if (!$('in_lmp').value) $('in_lmp').value = new Date().toISOString().slice(0, 10); },
  run: v => {
    const d = new Date(v.s('lmp') + 'T00:00:00');
    if (isNaN(d)) return bad;
    const due = new Date(d.getTime() + 280 * 864e5), now = new Date();
    const days = Math.floor((now - d) / 864e5), wk = Math.floor(days / 7), dd = days % 7;
    return `预产期：<span class="big">${due.getFullYear()}-${String(due.getMonth() + 1).padStart(2, '0')}-${String(due.getDate()).padStart(2, '0')}</span><br>${days >= 0 && days < 300 ? `当前孕周：<b>${wk} 周 ${dd} 天</b><br>` : ''}<span class="sub">按 40 周（280 天）推算，实际以医生诊断为准</span>`;
  } });

reg({ cat: 'health', icon: '🌸', name: '排卵期计算器', desc: '由末次月经与周期推算排卵日与易孕期', kw: '经期 月经 排卵 备孕',
  inputs: [
    { id: 'lmp', label: '末次月经首日', type: 'date' },
    { id: 'cyc', label: '月经周期（天）', value: 28 },
  ],
  init() { if (!$('in_lmp').value) $('in_lmp').value = new Date().toISOString().slice(0, 10); },
  run: v => {
    const d = new Date(v.s('lmp') + 'T00:00:00'), cyc = v.n('cyc');
    if (isNaN(d) || !(cyc >= 20 && cyc <= 45)) return bad;
    const next = new Date(d.getTime() + cyc * 864e5), ov = new Date(next.getTime() - 14 * 864e5);
    const f = x => `${x.getMonth() + 1}月${x.getDate()}日`;
    const s = new Date(ov.getTime() - 5 * 864e5), e = new Date(ov.getTime() + 4 * 864e5);
    return `预计下次月经：<b>${f(next)}</b><br>排卵日：<span class="big">${f(ov)}</span><br>易孕期：<b>${f(s)} ~ ${f(e)}</b><br><span class="sub">仅为经期推算，非避孕 / 助孕依据</span>`;
  } });

reg({ cat: 'health', icon: '🍺', name: '酒精代谢估算', desc: 'Widmark 公式估算血液酒精浓度', kw: '喝酒 酒驾 bac 血液',
  inputs: [
    { id: 'sex', label: '性别', type: 'select', options: [{ v: 'm', t: '男' }, { v: 'f', t: '女' }] },
    { id: 'w', label: '体重（公斤）', value: 65 },
    { id: 'ml', label: '饮酒量（毫升）', value: 500 },
    { id: 'abv', label: '酒精度（%）', value: 5, step: 0.5 },
    { id: 'hr', label: '饮酒后经过（小时）', value: 1 },
  ],
  run: v => {
    const w = v.n('w'), ml = v.n('ml'), abv = v.n('abv') / 100, hr = v.n('hr') || 0, r = v.s('sex') === 'm' ? 0.68 : 0.55;
    if (!(w > 0 && ml > 0)) return bad;
    const g = ml * abv * 0.789;
    let bac = Math.max(0, (g / (w * 1000 * r)) * 100 - 0.015 * hr);
    const mg = bac * 1000;
    const st = mg === 0 ? '已基本代谢完 ✅' : mg < 20 ? '低于酒驾线' : mg < 80 ? '⚠️ 已达 / 接近酒驾（≥20mg/100ml）' : '❗ 醉驾级别（≥80mg/100ml）';
    return `血液酒精浓度（估算）：<span class="big">${fmt(mg, 1)} mg/100ml</span><br>状态：<b>${st}</b><br><span class="sub">Widmark 公式估算，个体差异大 —— 喝酒不开车，本结果不可作为能否驾驶的依据</span>`;
  } });

reg({ cat: 'health', icon: '🍗', name: '每日蛋白质需求', desc: '按体重与目标估算每天该吃多少蛋白', kw: '蛋白 增肌 健身 protein',
  inputs: [
    { id: 'w', label: '体重（公斤）', value: 65 },
    { id: 'goal', label: '目标', type: 'select', options: [
      { v: '0.9', t: '日常维持' }, { v: '1.4', t: '健身 / 减脂' }, { v: '1.8', t: '增肌' }, { v: '2.0', t: '高强度训练' }] },
  ],
  run: v => {
    const w = v.n('w'), f = v.n('goal');
    if (!(w > 0)) return bad;
    return `每日蛋白质建议：<span class="big">${fmt(w * f, 0)} 克</span><br><span class="sub">约相当于 ${fmt(w * f / 25, 0)} 份掌心大小的瘦肉 / 鱼 / 蛋（每份≈25g 蛋白）</span>`;
  } });

reg({ cat: 'health', icon: '🏃', name: '配速计算器', desc: '距离 + 时间 = 配速；预估全马半马完赛', kw: '跑步 马拉松 pace 时速',
  inputs: [
    { id: 'd', label: '距离（公里）', value: 5, step: 0.1 },
    { id: 't', label: '用时（分钟）', value: 30 },
  ],
  run: v => {
    const d = v.n('d'), t = v.n('t');
    if (!(d > 0 && t > 0)) return bad;
    const pace = t / d, pm = Math.floor(pace), ps = Math.round((pace - pm) * 60);
    const fmtT = min => { const h = Math.floor(min / 60), m = Math.round(min % 60); return h ? `${h} 小时 ${m} 分` : `${m} 分`; };
    return `配速：<span class="big">${pm}'${String(ps).padStart(2, '0')}" / 公里</span> · 时速 <b>${fmt(d / t * 60, 1)} km/h</b><br>照此配速 —— 10 公里约 <b>${fmtT(pace * 10)}</b> · 半马约 <b>${fmtT(pace * 21.0975)}</b> · 全马约 <b>${fmtT(pace * 42.195)}</b>`;
  } });

/* ---------------------- 🔢 数学几何 ---------------------- */
reg({ cat: 'math', icon: '％', name: '百分比计算器', desc: '占比、求值、涨跌幅，三种常用算法', kw: '百分之 占比 涨跌',
  inputs: [
    { id: 'mode', label: '模式', type: 'select', full: true, options: [
      { v: 'of', t: 'A 的 x% 是多少' }, { v: 'is', t: 'A 是 B 的百分之几' }, { v: 'chg', t: '从 A 变到 B，涨跌幅是多少' }] },
    { id: 'a', label: 'A', value: 200 },
    { id: 'b', label: 'B 或 x', value: 15 },
  ],
  run: v => {
    const a = v.n('a'), b = v.n('b'), m = v.s('mode');
    if (isNaN(a) || isNaN(b)) return bad;
    if (m === 'of') return `${a} 的 ${b}% = <span class="big">${fmt(a * b / 100, 4)}</span>`;
    if (m === 'is') return b === 0 ? bad : `${a} 是 ${b} 的 <span class="big">${fmt(a / b * 100, 2)}%</span>`;
    if (a === 0) return bad;
    const c = (b - a) / a * 100;
    return `从 ${a} 到 ${b}：<span class="big">${c >= 0 ? '上涨' : '下跌'} ${fmt(Math.abs(c), 2)}%</span>`;
  } });

reg({ cat: 'math', icon: '📊', name: '平均数 / 统计', desc: '一组数字的均值、中位数、极值、标准差', kw: '平均 中位数 标准差 求和',
  inputs: [{ id: 'nums', label: '一组数字（空格 / 逗号分隔）', type: 'text', full: true, value: '85, 92, 78, 90, 88' }],
  run: v => {
    const arr = v.s('nums').split(/[\s,，、]+/).map(Number).filter(x => !isNaN(x));
    if (arr.length < 1) return bad;
    const sum = arr.reduce((a, b) => a + b, 0), mean = sum / arr.length;
    const sorted = [...arr].sort((a, b) => a - b);
    const mid = sorted.length % 2 ? sorted[(sorted.length - 1) / 2] : (sorted[sorted.length / 2 - 1] + sorted[sorted.length / 2]) / 2;
    const variance = arr.reduce((a, b) => a + (b - mean) ** 2, 0) / arr.length;
    return `<table>
      <tr><td>数量</td><td>${arr.length}</td></tr>
      <tr><td>总和</td><td>${fmt(sum, 4)}</td></tr>
      <tr><td>平均数</td><td>${fmt(mean, 4)}</td></tr>
      <tr><td>中位数</td><td>${fmt(mid, 4)}</td></tr>
      <tr><td>最大 / 最小</td><td>${fmt(Math.max(...arr), 4)} / ${fmt(Math.min(...arr), 4)}</td></tr>
      <tr><td>标准差（总体）</td><td>${fmt(Math.sqrt(variance), 4)}</td></tr></table>`;
  } });

reg({ cat: 'math', icon: '➗', name: '最大公约 / 最小公倍', desc: '求两个整数的 GCD 与 LCM', kw: 'gcd lcm 约数 倍数',
  inputs: [
    { id: 'a', label: '整数 A', value: 24 },
    { id: 'b', label: '整数 B', value: 36 },
  ],
  run: v => {
    let a = Math.abs(Math.round(v.n('a'))), b = Math.abs(Math.round(v.n('b')));
    if (!(a > 0 && b > 0)) return bad;
    const g = (x, y) => y ? g(y, x % y) : x, gg = g(a, b);
    return `最大公约数 GCD：<span class="big">${gg}</span><br>最小公倍数 LCM：<b>${fmt(a / gg * b, 0)}</b>`;
  } });

reg({ cat: 'math', icon: '𝑥', name: '一元二次方程', desc: '解 ax² + bx + c = 0，实根 / 复根都给', kw: '方程 求根 判别式',
  inputs: [
    { id: 'a', label: 'a', value: 1 },
    { id: 'b', label: 'b', value: -3 },
    { id: 'c', label: 'c', value: 2 },
  ],
  run: v => {
    const a = v.n('a'), b = v.n('b'), c = v.n('c');
    if (isNaN(a) || isNaN(b) || isNaN(c)) return bad;
    if (a === 0) return `a = 0，为一次方程：x = ${b !== 0 ? fmt(-c / b, 4) : '无解或恒等'}`;
    const d = b * b - 4 * a * c;
    if (d > 0) return `判别式 Δ = ${fmt(d, 4)} > 0，两个实根：<br><span class="big">x₁ = ${fmt((-b + Math.sqrt(d)) / (2 * a), 4)}</span><br><span class="big">x₂ = ${fmt((-b - Math.sqrt(d)) / (2 * a), 4)}</span>`;
    if (d === 0) return `判别式 Δ = 0，重根：<span class="big">x = ${fmt(-b / (2 * a), 4)}</span>`;
    return `判别式 Δ = ${fmt(d, 4)} < 0，共轭复根：<br><span class="big">x = ${fmt(-b / (2 * a), 4)} ± ${fmt(Math.sqrt(-d) / (2 * a), 4)}i</span>`;
  } });

reg({ cat: 'math', icon: '📐', name: '三角形计算器', desc: '已知三边，求周长、面积与三个内角', kw: '三角形 海伦 面积 内角',
  inputs: [
    { id: 'a', label: '边 a', value: 3 },
    { id: 'b', label: '边 b', value: 4 },
    { id: 'c', label: '边 c', value: 5 },
  ],
  run: v => {
    const a = v.n('a'), b = v.n('b'), c = v.n('c');
    if (!(a > 0 && b > 0 && c > 0)) return bad;
    if (a + b <= c || a + c <= b || b + c <= a) return `这三条边无法构成三角形（任意两边之和须大于第三边）`;
    const s = (a + b + c) / 2, area = Math.sqrt(s * (s - a) * (s - b) * (s - c));
    const ang = (x, y, z) => Math.acos((y * y + z * z - x * x) / (2 * y * z)) * 180 / Math.PI;
    return `周长：<b>${fmt(a + b + c, 3)}</b> · 面积：<span class="big">${fmt(area, 3)}</span><br>三个内角：<b>${fmt(ang(a, b, c), 1)}° · ${fmt(ang(b, a, c), 1)}° · ${fmt(ang(c, a, b), 1)}°</b>`;
  } });

reg({ cat: 'math', icon: '⭕', name: '圆的计算器', desc: '由半径求直径、周长、面积', kw: '圆 半径 周长 面积 π',
  inputs: [{ id: 'r', label: '半径', value: 5 }],
  run: v => {
    const r = v.n('r');
    if (!(r > 0)) return bad;
    return `<table>
      <tr><td>直径</td><td>${fmt(2 * r, 4)}</td></tr>
      <tr><td>周长</td><td>${fmt(2 * Math.PI * r, 4)}</td></tr>
      <tr><td>面积</td><td>${fmt(Math.PI * r * r, 4)}</td></tr></table>`;
  } });

reg({ cat: 'math', icon: '❗', name: '阶乘计算器', desc: '求 n! （n ≤ 170）', kw: '阶乘 factorial',
  inputs: [{ id: 'n', label: '非负整数 n（≤170）', value: 10 }],
  run: v => {
    const n = Math.round(v.n('n'));
    if (!(n >= 0)) return bad;
    if (n > 170) return `n 太大，结果超出可表示范围（请 ≤ 170）`;
    let r = 1; for (let i = 2; i <= n; i++) r *= i;
    return `${n}! = <span class="big">${n > 18 ? r.toExponential(6) : r.toLocaleString('en-US')}</span>`;
  } });

reg({ cat: 'math', icon: '🎰', name: '排列组合', desc: '从 n 个里取 r 个的排列数与组合数', kw: '排列 组合 概率 permutation combination',
  inputs: [
    { id: 'n', label: '总数 n', value: 10 },
    { id: 'r', label: '选取 r', value: 3 },
  ],
  run: v => {
    const n = Math.round(v.n('n')), r = Math.round(v.n('r'));
    if (!(n >= 0 && r >= 0 && r <= n)) return bad;
    let p = 1; for (let i = 0; i < r; i++) p *= (n - i);
    let cf = 1; for (let i = 1; i <= r; i++) cf *= i;
    return `排列 A(${n}, ${r}) = <span class="big">${fmt(p, 0)}</span><br>组合 C(${n}, ${r}) = <b>${fmt(p / cf, 0)}</b>`;
  } });

reg({ cat: 'math', icon: '∶', name: '比例求解', desc: '已知 a∶b = c∶x，求 x', kw: '比例 正比 求解',
  inputs: [
    { id: 'a', label: 'a', value: 2 },
    { id: 'b', label: 'b', value: 3 },
    { id: 'c', label: 'c', value: 8 },
  ],
  run: v => {
    const a = v.n('a'), b = v.n('b'), c = v.n('c');
    if (isNaN(a) || isNaN(b) || isNaN(c) || a === 0) return bad;
    return `已知 a∶b = c∶x，其中 a=${a}, b=${b}, c=${c}<br>x = <span class="big">${fmt(b * c / a, 4)}</span>`;
  } });

reg({ cat: 'math', icon: '🔍', name: '质数判断', desc: '判断一个数是否为质数，并给最小因子', kw: '质数 素数 因子 prime',
  inputs: [{ id: 'n', label: '正整数', value: 97 }],
  run: v => {
    const n = Math.round(v.n('n'));
    if (!(n >= 1)) return bad;
    if (n === 1) return `1 既不是质数也不是合数`;
    for (let i = 2; i * i <= n; i++) if (n % i === 0) return `${n} 不是质数，最小因子是 <span class="big">${i}</span>（= ${i} × ${n / i}）`;
    return `<span class="big">${n}</span> 是质数 ✅`;
  } });

reg({ cat: 'math', icon: '㏒', name: '对数计算器', desc: '任意底数的对数，附 ln 与 lg', kw: '对数 log ln 幂',
  inputs: [
    { id: 'x', label: '真数', value: 1000 },
    { id: 'base', label: '底数', value: 10 },
  ],
  run: v => {
    const x = v.n('x'), b = v.n('base');
    if (!(x > 0 && b > 0 && b !== 1)) return bad;
    return `log<sub>${fmt(b, 4)}</sub>(${fmt(x, 4)}) = <span class="big">${fmt(Math.log(x) / Math.log(b), 6)}</span><br><span class="sub">ln(${fmt(x, 2)}) = ${fmt(Math.log(x), 6)} · lg = ${fmt(Math.log10(x), 6)}</span>`;
  } });

reg({ cat: 'math', icon: '🔢', name: '等差数列求和', desc: '由首项、公差、项数求末项与总和', kw: '数列 等差 求和',
  inputs: [
    { id: 'a1', label: '首项', value: 1 },
    { id: 'd', label: '公差', value: 2 },
    { id: 'n', label: '项数', value: 10 },
  ],
  run: v => {
    const a1 = v.n('a1'), d = v.n('d'), n = Math.round(v.n('n'));
    if (isNaN(a1) || isNaN(d) || !(n > 0)) return bad;
    const an = a1 + (n - 1) * d;
    return `第 ${n} 项：<span class="big">${fmt(an, 4)}</span><br>前 ${n} 项和：<b>${fmt(n * (a1 + an) / 2, 4)}</b>`;
  } });

/* ---------------------- 🔄 单位换算（同一引擎，自动生成多个计算器） ---------------------- */
const UNITS = {
  length:   { icon: '📏', name: '长度', u: { '纳米': 1e-9, '微米': 1e-6, '毫米': 1e-3, '厘米': 1e-2, '分米': 0.1, '米': 1, '千米': 1000, '市里': 500, '英寸': 0.0254, '英尺': 0.3048, '码': 0.9144, '英里': 1609.344, '海里': 1852 } },
  weight:   { icon: '⚖️', name: '重量', u: { '毫克': 1e-6, '克': 1e-3, '千克': 1, '吨': 1000, '市斤': 0.5, '两': 0.05, '钱': 0.005, '磅': 0.45359237, '盎司': 0.0283495, '克拉': 0.0002 } },
  area:     { icon: '⬛', name: '面积', u: { '平方毫米': 1e-6, '平方厘米': 1e-4, '平方米': 1, '平方千米': 1e6, '公顷': 1e4, '亩': 2000 / 3, '平方英尺': 0.092903, '平方码': 0.836127, '英亩': 4046.856 } },
  volume:   { icon: '🧴', name: '体积', u: { '毫升': 1e-3, '升': 1, '立方厘米': 1e-3, '立方米': 1000, '加仑(美)': 3.78541, '夸脱(美)': 0.946353, '品脱(美)': 0.473176, '液盎司(美)': 0.0295735 } },
  speed:    { icon: '🚀', name: '速度', u: { '米每秒': 1, '千米每小时': 1 / 3.6, '英里每小时': 0.44704, '节': 0.514444, '马赫(海平面)': 343 } },
  temp:     { icon: '🌡️', name: '温度', temp: true },
  data:     { icon: '💾', name: '数据存储', u: { '比特': 0.125, '字节': 1, 'KB': 1024, 'MB': 1048576, 'GB': 1073741824, 'TB': 1099511627776, 'PB': 1125899906842624 } },
  time:     { icon: '⏱️', name: '时间', u: { '毫秒': 1e-3, '秒': 1, '分钟': 60, '小时': 3600, '天': 86400, '周': 604800, '月(30天)': 2592000, '年(365天)': 31536000 } },
  pressure: { icon: '🌀', name: '压强', u: { '帕斯卡': 1, '千帕': 1000, '兆帕': 1e6, '巴': 1e5, '标准大气压': 101325, '毫米汞柱': 133.322, 'psi': 6894.76 } },
  energy:   { icon: '⚡', name: '能量', u: { '焦耳': 1, '千焦': 1000, '卡路里': 4.184, '千卡': 4184, '瓦时': 3600, '千瓦时': 3.6e6, '英热单位': 1055.06 } },
  power:    { icon: '🔌', name: '功率', u: { '瓦特': 1, '千瓦': 1000, '兆瓦': 1e6, '马力(公制)': 735.499, '马力(英制)': 745.7 } },
};
Object.keys(UNITS).forEach(key => {
  const d = UNITS[key];
  if (d.temp) {
    reg({ cat: 'convert', icon: d.icon, name: '温度换算', desc: '摄氏度 · 华氏度 · 开尔文 互转', kw: '温度 摄氏 华氏 开尔文',
      inputs: [
        { id: 'v', label: '数值', value: 25 },
        { id: 'from', label: '原单位', type: 'select', options: ['摄氏度 ℃', '华氏度 ℉', '开尔文 K'] },
      ],
      run: v => {
        const x = v.n('v'), from = v.s('from');
        if (isNaN(x)) return bad;
        const c = from[0] === '摄' ? x : from[0] === '华' ? (x - 32) * 5 / 9 : x - 273.15;
        return `<table>
          <tr><td>摄氏度 ℃</td><td>${fmt(c, 2)}</td></tr>
          <tr><td>华氏度 ℉</td><td>${fmt(c * 9 / 5 + 32, 2)}</td></tr>
          <tr><td>开尔文 K</td><td>${fmt(c + 273.15, 2)}</td></tr></table>`;
      } });
  } else {
    const names = Object.keys(d.u);
    reg({ cat: 'convert', icon: d.icon, name: d.name + '换算', desc: names.slice(0, 5).join(' · ') + ' 等 ' + names.length + ' 种单位', kw: d.name + ' 换算 单位 转换',
      inputs: [
        { id: 'v', label: '数值', value: 1 },
        { id: 'from', label: '原单位', type: 'select', options: names },
      ],
      run: v => {
        const x = v.n('v'), from = v.s('from');
        if (isNaN(x)) return bad;
        const baseV = x * d.u[from];
        return '<table>' + names.map(n => `<tr><td>${n}</td><td>${fmt(baseV / d.u[n], 6)}</td></tr>`).join('') + '</table>';
      } });
  }
});

/* ---------------------- ⚛️ 物理 ---------------------- */
reg({ cat: 'physics', icon: '🚗', name: '速度 · 距离 · 时间', desc: '已知任意两项，求第三项', kw: '速度 距离 时间 匀速',
  inputs: [
    { id: 'solve', label: '求解目标', type: 'select', full: true, options: [{ v: 'v', t: '求速度' }, { v: 'd', t: '求距离' }, { v: 't', t: '求时间' }] },
    { id: 'd', label: '距离（米）', value: 100 },
    { id: 't', label: '时间（秒）', value: 10 },
    { id: 'v', label: '速度（米/秒）', value: 10 },
  ],
  run: v => {
    const s = v.s('solve'), d = v.n('d'), t = v.n('t'), sp = v.n('v');
    if (s === 'v') { if (!(t > 0)) return bad; return `速度 = <span class="big">${fmt(d / t, 3)} 米/秒</span>（${fmt(d / t * 3.6, 2)} km/h）`; }
    if (s === 'd') return `距离 = <span class="big">${fmt(sp * t, 3)} 米</span>`;
    if (!(sp > 0)) return bad; return `时间 = <span class="big">${fmt(d / sp, 3)} 秒</span>`;
  } });

reg({ cat: 'physics', icon: '🍎', name: '牛顿第二定律', desc: 'F = m·a，由质量与加速度求力', kw: '力 质量 加速度 牛顿',
  inputs: [
    { id: 'm', label: '质量（千克）', value: 2 },
    { id: 'a', label: '加速度（米/秒²）', value: 9.8, step: 0.1 },
  ],
  run: v => { const m = v.n('m'), a = v.n('a'); if (isNaN(m) || isNaN(a)) return bad; return `力 F = m·a = <span class="big">${fmt(m * a, 3)} 牛顿</span>`; } });

reg({ cat: 'physics', icon: '💨', name: '动能计算器', desc: 'KE = ½mv²', kw: '动能 能量 速度',
  inputs: [
    { id: 'm', label: '质量（千克）', value: 2 },
    { id: 'v', label: '速度（米/秒）', value: 10 },
  ],
  run: v => { const m = v.n('m'), sp = v.n('v'); if (isNaN(m) || isNaN(sp)) return bad; return `动能 = ½mv² = <span class="big">${fmt(0.5 * m * sp * sp, 3)} 焦耳</span>`; } });

reg({ cat: 'physics', icon: '⛰️', name: '重力势能', desc: 'PE = mgh', kw: '势能 高度 重力',
  inputs: [
    { id: 'm', label: '质量（千克）', value: 2 },
    { id: 'h', label: '高度（米）', value: 10 },
    { id: 'g', label: '重力加速度 g', value: 9.8, step: 0.01 },
  ],
  run: v => { const m = v.n('m'), h = v.n('h'), g = v.n('g'); if (isNaN(m) || isNaN(h) || isNaN(g)) return bad; return `重力势能 = mgh = <span class="big">${fmt(m * g * h, 3)} 焦耳</span>`; } });

reg({ cat: 'physics', icon: '🔋', name: '欧姆定律', desc: 'V = I·R，已知两项求第三项', kw: '电压 电流 电阻 欧姆',
  inputs: [
    { id: 'solve', label: '求解目标', type: 'select', full: true, options: [{ v: 'V', t: '求电压 V' }, { v: 'I', t: '求电流 I' }, { v: 'R', t: '求电阻 R' }] },
    { id: 'V', label: '电压（伏特）', value: 12 },
    { id: 'I', label: '电流（安培）', value: 2 },
    { id: 'R', label: '电阻（欧姆）', value: 6 },
  ],
  run: v => {
    const s = v.s('solve'), V = v.n('V'), I = v.n('I'), R = v.n('R');
    if (s === 'V') return `电压 V = I·R = <span class="big">${fmt(I * R, 3)} 伏特</span>`;
    if (s === 'I') { if (R === 0) return bad; return `电流 I = V/R = <span class="big">${fmt(V / R, 4)} 安培</span>`; }
    if (I === 0) return bad; return `电阻 R = V/I = <span class="big">${fmt(V / I, 4)} 欧姆</span>`;
  } });

reg({ cat: 'physics', icon: '🧊', name: '密度计算器', desc: 'ρ = m/V', kw: '密度 质量 体积',
  inputs: [
    { id: 'm', label: '质量（千克）', value: 1 },
    { id: 'v', label: '体积（立方米）', value: 0.001, step: 0.0001 },
  ],
  run: v => { const m = v.n('m'), vol = v.n('v'); if (vol === 0 || isNaN(m)) return bad; return `密度 = m/V = <span class="big">${fmt(m / vol, 3)} kg/m³</span>（${fmt(m / vol / 1000, 4)} g/cm³）`; } });

reg({ cat: 'physics', icon: '🌀', name: '压强计算器', desc: 'P = F/A', kw: '压强 压力 面积',
  inputs: [
    { id: 'f', label: '压力（牛顿）', value: 100 },
    { id: 'a', label: '受力面积（平方米）', value: 0.5, step: 0.01 },
  ],
  run: v => { const f = v.n('f'), a = v.n('a'); if (!(a > 0)) return bad; return `压强 = F/A = <span class="big">${fmt(f / a, 3)} 帕斯卡</span>（${fmt(f / a / 1000, 4)} kPa）`; } });

reg({ cat: 'physics', icon: '⚙️', name: '功率计算器', desc: 'P = W/t', kw: '功率 功 时间',
  inputs: [
    { id: 'w', label: '做功 / 能量（焦耳）', value: 1000 },
    { id: 't', label: '时间（秒）', value: 10 },
  ],
  run: v => { const w = v.n('w'), t = v.n('t'); if (!(t > 0)) return bad; return `功率 = W/t = <span class="big">${fmt(w / t, 3)} 瓦特</span>（${fmt(w / t / 1000, 4)} kW）`; } });

reg({ cat: 'physics', icon: '🪂', name: '自由落体', desc: '由下落时间求高度与落地速度', kw: '自由落体 下落 重力',
  inputs: [
    { id: 't', label: '下落时间（秒）', value: 3 },
    { id: 'g', label: '重力加速度 g', value: 9.8, step: 0.01 },
  ],
  run: v => { const t = v.n('t'), g = v.n('g'); if (!(t >= 0)) return bad; return `下落高度 = ½gt² = <span class="big">${fmt(0.5 * g * t * t, 3)} 米</span><br>落地速度 = gt = <b>${fmt(g * t, 3)} 米/秒</b>（${fmt(g * t * 3.6, 2)} km/h）`; } });

/* ---------------------- 🧪 化学 ---------------------- */
reg({ cat: 'chem', icon: '🧪', name: '摩尔浓度', desc: 'c = n/V，由物质的量与体积求浓度', kw: '浓度 摩尔 溶液',
  inputs: [
    { id: 'n', label: '溶质物质的量（摩尔）', value: 0.5, step: 0.01 },
    { id: 'v', label: '溶液体积（升）', value: 1, step: 0.1 },
  ],
  run: v => { const n = v.n('n'), vol = v.n('v'); if (!(vol > 0)) return bad; return `摩尔浓度 = n/V = <span class="big">${fmt(n / vol, 4)} mol/L</span>`; } });

reg({ cat: 'chem', icon: '💧', name: '溶液稀释', desc: 'C₁V₁ = C₂V₂，求稀释后总体积', kw: '稀释 浓度 加水',
  inputs: [
    { id: 'c1', label: '初始浓度 C₁', value: 2, step: 0.1 },
    { id: 'v1', label: '初始体积 V₁（mL）', value: 50 },
    { id: 'c2', label: '目标浓度 C₂', value: 0.5, step: 0.1 },
  ],
  run: v => {
    const c1 = v.n('c1'), v1 = v.n('v1'), c2 = v.n('c2');
    if (!(c1 > 0 && v1 > 0 && c2 > 0)) return bad;
    if (c2 > c1) return `目标浓度不能高于初始浓度（稀释只会变稀）`;
    const v2 = c1 * v1 / c2;
    return `稀释后总体积 V₂ = <span class="big">${fmt(v2, 2)} mL</span><br>需加溶剂（水）：<b>${fmt(v2 - v1, 2)} mL</b>`;
  } });

reg({ cat: 'chem', icon: '🎈', name: '理想气体定律', desc: 'PV = nRT，已知三项求第四项', kw: '理想气体 pv nrt 气体',
  inputs: [
    { id: 'solve', label: '求解目标', type: 'select', full: true, options: [{ v: 'P', t: '求压强 P' }, { v: 'V', t: '求体积 V' }, { v: 'n', t: '求物质的量 n' }, { v: 'T', t: '求温度 T' }] },
    { id: 'P', label: '压强（帕）', value: 101325 },
    { id: 'V', label: '体积（立方米）', value: 0.0224, step: 0.0001 },
    { id: 'n', label: '物质的量（摩尔）', value: 1 },
    { id: 'T', label: '温度（开尔文）', value: 273.15 },
  ],
  run: v => {
    const R = 8.314, s = v.s('solve'), P = v.n('P'), V = v.n('V'), n = v.n('n'), T = v.n('T');
    if (s === 'P') { if (!(V > 0)) return bad; return `P = nRT/V = <span class="big">${fmt(n * R * T / V, 2)} 帕</span>`; }
    if (s === 'V') { if (!(P > 0)) return bad; return `V = nRT/P = <span class="big">${fmt(n * R * T / P, 6)} m³</span>`; }
    if (s === 'n') { if (!(R * T > 0)) return bad; return `n = PV/RT = <span class="big">${fmt(P * V / (R * T), 4)} mol</span>`; }
    if (!(n * R > 0)) return bad; return `T = PV/nR = <span class="big">${fmt(P * V / (n * R), 2)} K</span>`;
  } });

reg({ cat: 'chem', icon: '🧫', name: 'pH ↔ [H⁺]', desc: '酸碱度与氢离子浓度互算', kw: 'ph 酸碱 氢离子',
  inputs: [
    { id: 'mode', label: '模式', type: 'select', full: true, options: [{ v: 'toph', t: '由 [H⁺] 求 pH' }, { v: 'toh', t: '由 pH 求 [H⁺]' }] },
    { id: 'x', label: '数值（[H⁺] mol/L 或 pH）', value: 0.001, step: 'any' },
  ],
  run: v => {
    const m = v.s('mode'), x = v.n('x');
    if (isNaN(x)) return bad;
    if (m === 'toph') { if (!(x > 0)) return bad; const ph = -Math.log10(x); return `pH = <span class="big">${fmt(ph, 3)}</span> · pOH = <b>${fmt(14 - ph, 3)}</b> · ${ph < 7 ? '酸性' : ph > 7 ? '碱性' : '中性'}`; }
    return `[H⁺] = <span class="big">${Math.pow(10, -x).toExponential(3)} mol/L</span> · [OH⁻] = <b>${Math.pow(10, -(14 - x)).toExponential(3)}</b>`;
  } });

reg({ cat: 'chem', icon: '⚗️', name: '质量 ↔ 摩尔', desc: '用摩尔质量在质量与物质的量间换算', kw: '摩尔质量 物质的量 mol',
  inputs: [
    { id: 'M', label: '摩尔质量 M（g/mol）', value: 18 },
    { id: 'dir', label: '方向', type: 'select', full: true, options: [{ v: 'm2n', t: '质量 → 物质的量' }, { v: 'n2m', t: '物质的量 → 质量' }] },
    { id: 'x', label: '数值（克 或 摩尔）', value: 36 },
  ],
  run: v => {
    const M = v.n('M'), x = v.n('x');
    if (!(M > 0) || isNaN(x)) return bad;
    return v.s('dir') === 'm2n'
      ? `物质的量 = m/M = <span class="big">${fmt(x / M, 4)} mol</span>`
      : `质量 = n·M = <span class="big">${fmt(x * M, 4)} g</span>`;
  } });

/* ---------------------- 📅 日常生活 ---------------------- */
reg({ cat: 'daily', icon: '🎂', name: '年龄计算器', desc: '周岁、生肖、星座、距下个生日还有几天', kw: '年龄 生肖 星座 生日',
  inputs: [{ id: 'd', label: '出生日期', type: 'date', value: '2000-01-01' }],
  run: v => {
    const d = new Date(v.s('d') + 'T00:00:00');
    if (isNaN(d)) return bad;
    const now = new Date();
    let age = now.getFullYear() - d.getFullYear();
    if (!(now.getMonth() > d.getMonth() || (now.getMonth() === d.getMonth() && now.getDate() >= d.getDate()))) age--;
    const days = Math.floor((now - d) / 864e5);
    let nb = new Date(now.getFullYear(), d.getMonth(), d.getDate());
    if (nb < now) nb = new Date(now.getFullYear() + 1, d.getMonth(), d.getDate());
    const toBday = Math.ceil((nb - now) / 864e5);
    const sx = '猴鸡狗猪鼠牛虎兔龙蛇马羊'[d.getFullYear() % 12];
    const CONS = [[120, '摩羯♑'], [219, '水瓶♒'], [321, '双鱼♓'], [420, '白羊♈'], [521, '金牛♉'], [622, '双子♊'], [723, '巨蟹♋'], [823, '狮子♌'], [923, '处女♍'], [1024, '天秤♎'], [1123, '天蝎♏'], [1222, '射手♐'], [1232, '摩羯♑']];
    const md = (d.getMonth() + 1) * 100 + d.getDate();
    let cons = '摩羯♑'; for (const [cap, n] of CONS) if (md < cap) { cons = n; break; }
    return `周岁：<span class="big">${age} 岁</span><br>已来到这个世界：<b>${fmt(days, 0)} 天</b>（约 ${fmt(days / 7, 0)} 周）<br>生肖：<b>${sx}</b> · 星座：<b>${cons}</b><br>距下一个生日还有：<b>${toBday} 天</b> 🎉`;
  } });

reg({ cat: 'daily', icon: '📅', name: '日期计算器', desc: '两个日期相隔多少天？N 天后是哪天？', kw: '日期 天数 间隔',
  custom: true,
  body: `<label>模式</label>
    <select id="dMode"><option value="diff">计算两个日期的间隔</option><option value="add">从某天加减 N 天</option></select>
    <div class="form" style="margin-top:12px">
      <div class="field"><label>起始日期</label><input id="d1" type="date"></div>
      <div class="field" id="dWrap2"><label>结束日期</label><input id="d2" type="date"></div>
    </div>
    <div id="dWrapN" style="display:none;margin-top:12px"><label>天数（负数表示往前推）</label><input id="dN" type="number" value="100"></div>
    <button class="calcBtn">计 算</button>`,
  init() {
    const today = new Date().toISOString().slice(0, 10);
    $('d1').value = today; $('d2').value = today;
    $('dMode').addEventListener('change', () => {
      const add = $('dMode').value === 'add';
      $('dWrap2').style.display = add ? 'none' : 'block';
      $('dWrapN').style.display = add ? 'block' : 'none';
    });
  },
  run() {
    const d1 = new Date($('d1').value + 'T00:00:00');
    if (isNaN(d1)) return bad;
    if ($('dMode').value === 'diff') {
      const d2 = new Date($('d2').value + 'T00:00:00');
      if (isNaN(d2)) return bad;
      const days = Math.round(Math.abs(d2 - d1) / 864e5);
      return `两个日期相隔：<span class="big">${fmt(days, 0)} 天</span><br>约合 <b>${fmt(days / 7, 1)} 周</b> · <b>${fmt(days / 30.44, 1)} 个月</b> · <b>${fmt(days / 365.25, 2)} 年</b>`;
    }
    const n = parseFloat($('dN').value) || 0;
    const r = new Date(d1.getTime() + n * 864e5);
    const wd = '日一二三四五六'[r.getDay()];
    return `${$('d1').value} ${n >= 0 ? '往后' : '往前'} ${Math.abs(n)} 天是：<br><span class="big">${r.getFullYear()}-${String(r.getMonth() + 1).padStart(2, '0')}-${String(r.getDate()).padStart(2, '0')}</span>（星期${wd}）`;
  } });

reg({ cat: 'daily', icon: '⏳', name: '倒数日 / 纪念日', desc: '距离某个日子还有 / 已过去多少天', kw: '倒数 倒计时 纪念日',
  inputs: [{ id: 'target', label: '目标日期', type: 'date' }],
  init() { if (!$('in_target').value) { const d = new Date(); d.setDate(d.getDate() + 100); $('in_target').value = d.toISOString().slice(0, 10); } },
  run: v => {
    const d = new Date(v.s('target') + 'T00:00:00');
    if (isNaN(d)) return bad;
    const now = new Date(); now.setHours(0, 0, 0, 0);
    const days = Math.round((d - now) / 864e5);
    if (days > 0) return `距离 <b>${v.s('target')}</b> 还有：<span class="big">${days} 天</span>（约 ${fmt(days / 7, 1)} 周 · ${fmt(days / 30.44, 1)} 个月）`;
    if (days < 0) return `<b>${v.s('target')}</b> 已过去 <span class="big">${-days} 天</span>`;
    return `就是<span class="big">今天</span>！🎉`;
  } });

reg({ cat: 'daily', icon: '⛽', name: '油费计算器', desc: '按里程、油耗、油价算这趟路的油钱', kw: '油费 油耗 加油 里程',
  inputs: [
    { id: 'dist', label: '行驶距离（公里）', value: 100 },
    { id: 'fe', label: '油耗（升 / 百公里）', value: 7, step: 0.1 },
    { id: 'price', label: '油价（元 / 升）', value: 7.8, step: 0.1 },
  ],
  run: v => {
    const dist = v.n('dist'), fe = v.n('fe'), p = v.n('price');
    if (!(dist > 0 && fe > 0 && p > 0)) return bad;
    const liters = dist * fe / 100, cost = liters * p;
    return `预计耗油：<b>${fmt(liters, 2)} 升</b><br>油费：<span class="big">¥ ${fmt(cost)}</span> · 每公里 <b>¥ ${fmt(cost / dist, 2)}</b>`;
  } });

reg({ cat: 'daily', icon: '🧾', name: 'AA 分账计算器', desc: '总金额按人数平摊，可加服务费', kw: 'aa 分账 平摊 聚餐',
  inputs: [
    { id: 'total', label: '总金额（元）', value: 600 },
    { id: 'ppl', label: '人数', value: 5 },
    { id: 'tip', label: '额外服务费（%）', value: 0 },
  ],
  run: v => {
    const t = v.n('total'), ppl = v.n('ppl'), tip = v.n('tip') || 0;
    if (!(t > 0 && ppl > 0)) return bad;
    const grand = t * (1 + tip / 100);
    return `合计（含服务费）：<b>¥ ${fmt(grand)}</b><br>每人应付：<span class="big">¥ ${fmt(grand / ppl)}</span>`;
  } });

/* ---------------------- 🧰 实用工具 ---------------------- */
reg({ cat: 'tools', icon: '🧮', name: '科学计算器', desc: '加减乘除、三角、对数、幂运算，支持角度/弧度', kw: '科学 计算 三角 对数',
  custom: true,
  body: `
    <div class="sciDisp"><div class="expr" id="sExpr">&nbsp;</div><div class="val" id="sVal">0</div></div>
    <div style="margin-bottom:10px"><label style="display:inline">角度制
      <input type="checkbox" id="sDeg" checked style="width:auto;vertical-align:middle"></label></div>
    <div class="keys" id="sKeys"></div>`,
  init() {
    const KEYS = [
      ['C', 'danger'], ['(', ''], [')', ''], ['⌫', 'danger'], ['÷', 'op'],
      ['sin', 'op'], ['7', ''], ['8', ''], ['9', ''], ['×', 'op'],
      ['cos', 'op'], ['4', ''], ['5', ''], ['6', ''], ['−', 'op'],
      ['tan', 'op'], ['1', ''], ['2', ''], ['3', ''], ['+', 'op'],
      ['√', 'op'], ['0', ''], ['.', ''], ['π', 'op'], ['=', 'eq'],
      ['ln', 'op'], ['log', 'op'], ['x²', 'op'], ['xʸ', 'op'], ['e', 'op'],
    ];
    $('sKeys').innerHTML = KEYS.map(([k, cls]) => `<button class="${cls}" data-k="${k}">${k}</button>`).join('');
    let disp = '', expr = '';
    const upd = () => { $('sExpr').innerHTML = disp || '&nbsp;'; };
    const push = (d, e) => { disp += d; expr += e; upd(); };
    $('sKeys').addEventListener('click', ev => {
      const k = ev.target.dataset && ev.target.dataset.k;
      if (!k) return;
      if (k === 'C') { disp = ''; expr = ''; $('sVal').textContent = '0'; upd(); return; }
      if (k === '⌫') {
        disp = disp.replace(/(sin\(|cos\(|tan\(|ln\(|log\(|√\(|[\s\S])$/, '');
        expr = expr.replace(/(S\(|C\(|T\(|L\(|G\(|Q\(|\*\*2|\*\*|[\s\S])$/, '');
        upd(); return;
      }
      if (k === '=') {
        if (!expr) return;
        if (!/^[0-9+\-*/().SCTLGQPE ]*$/.test(expr)) { $('sVal').textContent = '出错了'; return; }
        try {
          const deg = $('sDeg').checked;
          const f = new Function('S', 'C', 'T', 'L', 'G', 'Q', 'P', 'E', 'return (' + expr + ')');
          const r = f(
            x => Math.sin(deg ? x * Math.PI / 180 : x),
            x => Math.cos(deg ? x * Math.PI / 180 : x),
            x => Math.tan(deg ? x * Math.PI / 180 : x),
            Math.log, Math.log10, Math.sqrt, Math.PI, Math.E);
          $('sVal').textContent = (typeof r === 'number' && isFinite(r)) ? +r.toPrecision(12) : '出错了';
        } catch (e) { $('sVal').textContent = '出错了'; }
        return;
      }
      const map = {
        '÷': ['÷', '/'], '×': ['×', '*'], '−': ['−', '-'], '+': ['+', '+'],
        'sin': ['sin(', 'S('], 'cos': ['cos(', 'C('], 'tan': ['tan(', 'T('],
        'ln': ['ln(', 'L('], 'log': ['log(', 'G('], '√': ['√(', 'Q('],
        'π': ['π', 'P'], 'e': ['e', 'E'], 'x²': ['²', '**2'], 'xʸ': ['^', '**'],
      };
      const [d, e] = map[k] || [k, k];
      push(d, e);
    });
  } });

reg({ cat: 'tools', icon: '🔐', name: '密码生成器', desc: '一键生成高强度随机密码', kw: '密码 随机 password 生成',
  inputs: [
    { id: 'len', label: '长度', value: 16, min: 4, max: 64 },
    { id: 'set', label: '包含字符', type: 'select', value: 'aA1!', options: [
      { v: 'aA1', t: '字母 + 数字' }, { v: 'aA1!', t: '字母 + 数字 + 符号' }, { v: 'a1', t: '小写字母 + 数字' }] },
  ],
  btn: '生 成',
  run: v => {
    const L = Math.min(64, Math.max(4, v.n('len') || 16));
    const sets = { a: 'abcdefghijkmnpqrstuvwxyz', A: 'ABCDEFGHJKLMNPQRSTUVWXYZ', 1: '23456789', '!': '!@#$%^&*?-_+' };
    const sel = v.s('set');
    let pool = '';
    if (sel.includes('a')) pool += sets.a;
    if (sel.includes('A')) pool += sets.A;
    if (sel.includes('1')) pool += sets[1];
    if (sel.includes('!')) pool += sets['!'];
    const buf = new Uint32Array(L);
    crypto.getRandomValues(buf);
    let pw = '';
    for (let i = 0; i < L; i++) pw += pool[buf[i] % pool.length];
    return `你的新密码：<br><span class="big" style="word-break:break-all">${pw}</span><br><span class="sub">已避开易混淆字符（0/O、1/l 等），请妥善保存。</span>`;
  } });

reg({ cat: 'tools', icon: '🎲', name: '随机决定器', desc: '抽数字、抛硬币、帮纠结的你做决定', kw: '随机 抛硬币 抽签 决定',
  custom: true,
  body: `<label>模式</label>
    <select id="zMode">
      <option value="num">抽一个随机数</option>
      <option value="coin">抛硬币</option>
      <option value="pick">从选项里帮我选（用顿号或逗号分隔）</option>
    </select>
    <div class="form" id="zNumWrap" style="margin-top:12px">
      <div class="field"><label>最小值</label><input id="z1" type="number" value="1"></div>
      <div class="field"><label>最大值</label><input id="z2" type="number" value="100"></div>
    </div>
    <div id="zPickWrap" style="display:none;margin-top:12px"><label>选项</label><input id="zOpts" type="text" placeholder="火锅、烧烤、面条、饺子"></div>
    <button class="calcBtn">来！</button>`,
  init() {
    $('zMode').addEventListener('change', () => {
      $('zNumWrap').style.display = $('zMode').value === 'num' ? 'flex' : 'none';
      $('zPickWrap').style.display = $('zMode').value === 'pick' ? 'block' : 'none';
    });
  },
  run() {
    const m = $('zMode').value;
    if (m === 'coin') return `<span class="big">${Math.random() < 0.5 ? '🪙 正面' : '🪙 反面'}</span>`;
    if (m === 'pick') {
      const opts = $('zOpts').value.split(/[、,，;；\s]+/).filter(Boolean);
      if (opts.length < 2) return '<p>请至少输入两个选项</p>';
      return `命运的选择是：<span class="big">${opts[Math.floor(Math.random() * opts.length)]}</span>`;
    }
    const a = Math.ceil(parseFloat($('z1').value)), b = Math.floor(parseFloat($('z2').value));
    if (isNaN(a) || isNaN(b) || a > b) return '<p>请检查范围</p>';
    return `<span class="big">${a + Math.floor(Math.random() * (b - a + 1))}</span>`;
  } });

reg({ cat: 'tools', icon: '🔠', name: '进制转换器', desc: '二 / 八 / 十 / 十六进制互转', kw: '进制 二进制 十六进制 hex binary',
  inputs: [
    { id: 'val', label: '数值', type: 'text', value: '255' },
    { id: 'from', label: '当前进制', type: 'select', options: [{ v: '10', t: '十进制' }, { v: '2', t: '二进制' }, { v: '8', t: '八进制' }, { v: '16', t: '十六进制' }] },
  ],
  run: v => {
    const s = v.s('val').trim(), from = parseInt(v.s('from'));
    const dec = parseInt(s, from);
    if (isNaN(dec)) return `“${s}” 不是有效的 ${from} 进制数`;
    return `<table>
      <tr><td>十进制</td><td>${dec}</td></tr>
      <tr><td>二进制</td><td>${dec.toString(2)}</td></tr>
      <tr><td>八进制</td><td>${dec.toString(8)}</td></tr>
      <tr><td>十六进制</td><td>${dec.toString(16).toUpperCase()}</td></tr></table>`;
  } });

reg({ cat: 'tools', icon: 'Ⅻ', name: '罗马数字转换', desc: '阿拉伯数字与罗马数字互转（1-3999）', kw: '罗马 数字 roman',
  inputs: [{ id: 'val', label: '阿拉伯数字(1-3999) 或 罗马数字', type: 'text', value: '2024' }],
  run: v => {
    const s = v.s('val').trim().toUpperCase();
    if (/^[0-9]+$/.test(s)) {
      let n = parseInt(s);
      if (!(n >= 1 && n <= 3999)) return `请输入 1 ~ 3999 的整数`;
      const map = [[1000, 'M'], [900, 'CM'], [500, 'D'], [400, 'CD'], [100, 'C'], [90, 'XC'], [50, 'L'], [40, 'XL'], [10, 'X'], [9, 'IX'], [5, 'V'], [4, 'IV'], [1, 'I']];
      let r = '';
      for (const [val, sym] of map) while (n >= val) { r += sym; n -= val; }
      return `罗马数字：<span class="big">${r}</span>`;
    }
    if (/^[IVXLCDM]+$/.test(s)) {
      const val = { I: 1, V: 5, X: 10, L: 50, C: 100, D: 500, M: 1000 };
      let n = 0;
      for (let i = 0; i < s.length; i++) { const c = val[s[i]], nx = val[s[i + 1]] || 0; n += c < nx ? -c : c; }
      return `阿拉伯数字：<span class="big">${n}</span>`;
    }
    return `请输入有效的阿拉伯数字或罗马数字`;
  } });

reg({ cat: 'tools', icon: '📝', name: '文本字数统计', desc: '字符、中文字、单词、行数一键统计', kw: '字数 统计 字符 word count',
  inputs: [{ id: 'txt', label: '粘贴文本', type: 'textarea', rows: 6, ph: '在此输入或粘贴文本…' }],
  btn: '统 计',
  run: v => {
    const t = v.s('txt') || '';
    const cn = (t.match(/[一-龥]/g) || []).length;
    const words = (t.trim().match(/[A-Za-z0-9]+/g) || []).length;
    return `<table>
      <tr><td>字符数（含空格）</td><td>${t.length}</td></tr>
      <tr><td>字符数（不含空格）</td><td>${t.replace(/\s/g, '').length}</td></tr>
      <tr><td>中文字数</td><td>${cn}</td></tr>
      <tr><td>英文单词 / 数字串</td><td>${words}</td></tr>
      <tr><td>行数</td><td>${t ? t.split(/\n/).length : 0}</td></tr></table>`;
  } });

/* ===================== 启动 ===================== */
$('home').addEventListener('click', e => {
  const t = e.target.closest('.tile');
  if (!t) return;
  if (t.dataset.cat) { curCat = t.dataset.cat; $('q').value = ''; renderHome(); window.scrollTo({ top: 0, behavior: 'smooth' }); }
  else if (t.dataset.calc) open(+t.dataset.calc);
});
$('crumb').addEventListener('click', e => { if (e.target.dataset.home) { curCat = null; $('q').value = ''; renderHome(); } });
let tmr; $('q').addEventListener('input', () => { clearTimeout(tmr); tmr = setTimeout(renderHome, 120); });
renderHome();
})();
