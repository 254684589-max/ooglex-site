/* EMBERFALL 余烬陷落 —— Ooglex 原创 2.5D 暗黑风动作角色扮演游戏
 * 纯 Canvas 2D + 原生 JavaScript，无外部依赖、无外部素材：画面、音效全部由代码生成。
 * 结构：工具 → 音效 → 数据（物品/怪物/技能）→ 角色属性 → 地图生成 → 寻路 → 实体更新 → 战斗与掉落
 *       → 渲染 → 输入 → 界面 → 存档 → 主循环
 */
'use strict';
(function () {

// ===================== 工具 =====================
const $ = id => document.getElementById(id);
const rand = Math.random;
const ri = (a, b) => a + Math.floor(rand() * (b - a + 1));
const pick = a => a[Math.floor(rand() * a.length)];
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
let UID = 1;
const SAVE_KEY = 'ooglex.emberfall.v1';
const COARSE = !!(window.matchMedia && matchMedia('(pointer: coarse)').matches);
const REDUCED = !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);

// ===================== 音效（WebAudio 合成） =====================
const Snd = {
  c: null, on: true, nb: null,
  init() {
    if (this.c) { if (this.c.state === 'suspended') this.c.resume(); return; }
    try {
      this.c = new (window.AudioContext || window.webkitAudioContext)();
      const len = this.c.sampleRate; this.nb = this.c.createBuffer(1, len, len);
      const d = this.nb.getChannelData(0); for (let i = 0; i < len; i++) d[i] = rand() * 2 - 1;
    } catch (e) { this.c = null; }
  },
  tone(f, d, type, v, slide, delay) {
    if (!this.on || !this.c) return;
    const c = this.c, t = c.currentTime + (delay || 0), o = c.createOscillator(), g = c.createGain();
    o.type = type || 'sine'; o.frequency.setValueAtTime(f, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(20, f * slide), t + d);
    g.gain.setValueAtTime(v || .12, t); g.gain.exponentialRampToValueAtTime(.0008, t + d);
    o.connect(g); g.connect(c.destination); o.start(t); o.stop(t + d + .03);
  },
  noise(d, v, freq, q) {
    if (!this.on || !this.c) return;
    const c = this.c, t = c.currentTime, s = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain();
    s.buffer = this.nb; f.type = 'bandpass'; f.frequency.value = freq || 1000; f.Q.value = q || 1;
    g.gain.setValueAtTime(v || .2, t); g.gain.exponentialRampToValueAtTime(.0008, t + d);
    s.connect(f); f.connect(g); g.connect(c.destination); s.start(t, rand() * .5); s.stop(t + d + .03);
  },
  play(n) {
    switch (n) {
      case 'swing': this.noise(.12, .07, 2600, .8); break;
      case 'hit': this.noise(.1, .22, 700); this.tone(120, .1, 'square', .04, .5); break;
      case 'crit': this.noise(.14, .28, 500); this.tone(90, .18, 'sawtooth', .07, .4); break;
      case 'fire': this.noise(.35, .1, 500, .7); this.tone(260, .28, 'sawtooth', .03, .35); break;
      case 'boom': this.noise(.45, .26, 260, .6); break;
      case 'ice': this.noise(.6, .14, 5000, 2); this.tone(1200, .4, 'sine', .04, .5); break;
      case 'whirl': this.noise(.35, .12, 1800, .6); break;
      case 'blink': this.tone(900, .25, 'sine', .07, .25); break;
      case 'gold': this.tone(1500, .07, 'triangle', .07); this.tone(2000, .09, 'triangle', .05, 0, .06); break;
      case 'pick': this.tone(620, .08, 'triangle', .09); break;
      case 'magic': this.tone(700, .12, 'triangle', .08); this.tone(1050, .15, 'triangle', .06, 0, .07); break;
      case 'rare': this.tone(660, .15, 'triangle', .08); this.tone(990, .2, 'triangle', .07, 0, .09); this.tone(1320, .25, 'triangle', .06, 0, .18); break;
      case 'legend': [523, 659, 784, 1046].forEach((f, i) => this.tone(f, .5, 'triangle', .07, 0, i * .09)); break;
      case 'lvl': [392, 523, 659, 784].forEach((f, i) => this.tone(f, .35, 'square', .04, 0, i * .08)); break;
      case 'die': this.tone(180, .45, 'sawtooth', .05, .35); this.noise(.3, .08, 400); break;
      case 'hurt': this.tone(95, .18, 'square', .06, .6); break;
      case 'potion': this.tone(420, .18, 'sine', .1, 1.9); break;
      case 'portal': this.tone(260, .7, 'sine', .08, 3); break;
      case 'chest': this.noise(.25, .14, 380); this.tone(220, .2, 'triangle', .05, 1.5); break;
      case 'barrel': this.noise(.2, .2, 300, .5); break;
      case 'shrine': [330, 440, 554, 660].forEach((f, i) => this.tone(f, .6, 'sine', .05, 0, i * .12)); break;
      case 'arrow': this.noise(.12, .06, 3500, 3); break;
      case 'bolt': this.tone(500, .25, 'sawtooth', .03, .5); break;
      case 'boss': this.tone(70, 1.2, 'sawtooth', .08, .6); this.tone(105, 1.2, 'sawtooth', .05, .6); break;
      case 'click': this.tone(800, .04, 'triangle', .04); break;
    }
  }
};

// ===================== 数据：物品 =====================
const BASES = {
  dagger: { n: '匕首', g: '匕', slot: 'weapon', w: 'dagger', dmg: [1, 4], spd: 1.3, lvl: 1 },
  sword: { n: '短剑', g: '剑', slot: 'weapon', w: 'sword', dmg: [2, 6], spd: 1.15, lvl: 1 },
  mace: { n: '钉头锤', g: '锤', slot: 'weapon', w: 'mace', dmg: [3, 8], spd: 1.0, lvl: 3 },
  axe: { n: '战斧', g: '斧', slot: 'weapon', w: 'axe', dmg: [4, 11], spd: .9, lvl: 5 },
  lsword: { n: '长剑', g: '剑', slot: 'weapon', w: 'sword', dmg: [6, 13], spd: 1.05, lvl: 9 },
  gsword: { n: '巨剑', g: '剑', slot: 'weapon', w: 'gsword', dmg: [10, 22], spd: .8, lvl: 14 },
  maul: { n: '战锤', g: '锤', slot: 'weapon', w: 'mace', dmg: [14, 28], spd: .75, lvl: 20 },
  staff: { n: '橡木法杖', g: '杖', slot: 'weapon', w: 'staff', dmg: [2, 5], spd: 1.0, lvl: 1, imp: { spellp: 15 } },
  wstaff: { n: '符文法杖', g: '杖', slot: 'weapon', w: 'staff', dmg: [4, 9], spd: 1.0, lvl: 10, imp: { spellp: 30 } },
  buckler: { n: '小圆盾', g: '盾', slot: 'off', arm: 3, lvl: 1 },
  kite: { n: '鸢盾', g: '盾', slot: 'off', arm: 8, lvl: 7 },
  tower: { n: '塔盾', g: '盾', slot: 'off', arm: 15, lvl: 15 },
  cap: { n: '皮帽', g: '盔', slot: 'helm', arm: 2, lvl: 1 },
  helm: { n: '铁盔', g: '盔', slot: 'helm', arm: 5, lvl: 5 },
  ghelm: { n: '巨盔', g: '盔', slot: 'helm', arm: 9, lvl: 12 },
  cloth: { n: '亚麻布衣', g: '甲', slot: 'body', arm: 3, lvl: 1, col: '#6b5b45' },
  leather: { n: '皮甲', g: '甲', slot: 'body', arm: 6, lvl: 2, col: '#6e4a2c' },
  chain: { n: '锁子甲', g: '甲', slot: 'body', arm: 12, lvl: 7, col: '#858a92' },
  plate: { n: '板甲', g: '甲', slot: 'body', arm: 20, lvl: 13, col: '#b6bac2' },
  gloves: { n: '皮手套', g: '手', slot: 'hands', arm: 1, lvl: 1 },
  gaunt: { n: '铁护手', g: '手', slot: 'hands', arm: 3, lvl: 8 },
  boots: { n: '皮靴', g: '靴', slot: 'feet', arm: 1, lvl: 1 },
  gboots: { n: '铁靴', g: '靴', slot: 'feet', arm: 4, lvl: 9 },
  ring: { n: '戒指', g: '戒', slot: 'ring', lvl: 1, magicOnly: true },
  amulet: { n: '护符', g: '符', slot: 'neck', lvl: 4, magicOnly: true },
};
const SLOTS = [['weapon', '武器'], ['off', '副手'], ['helm', '头盔'], ['body', '护甲'], ['hands', '手套'], ['feet', '靴子'], ['ring', '戒指'], ['neck', '护符']];
const ALL = '*';
const AFF = {
  str: { t: '+{v} 力量', a: 1, b: .5, pre: '强壮的', s: ALL },
  vit: { t: '+{v} 体能', a: 1, b: .5, pre: '坚韧的', s: ALL },
  mag: { t: '+{v} 魔力', a: 1, b: .5, pre: '睿智的', s: ALL },
  life: { t: '+{v} 生命', a: 4, b: 2, pre: '活力的', s: ALL },
  mana: { t: '+{v} 法力', a: 3, b: 1.5, pre: '蓝焰的', s: ALL },
  dmgp: { t: '+{v}% 伤害', a: 5, b: 1.5, pre: '锋利的', s: ['weapon', 'ring', 'neck', 'hands'] },
  spellp: { t: '+{v}% 法术伤害', a: 5, b: 1.5, pre: '秘法的', s: ['weapon', 'ring', 'neck', 'helm', 'off'] },
  armp: { t: '+{v}% 护甲', a: 10, b: 2, pre: '坚固的', s: ['off', 'helm', 'body', 'hands', 'feet'] },
  ias: { t: '+{v}% 攻击速度', a: 5, b: .5, pre: '迅捷的', s: ['weapon', 'hands', 'ring'], max: 30 },
  ls: { t: '{v}% 生命偷取', a: 1, b: .15, pre: '饮血的', s: ['weapon', 'ring', 'neck'], max: 8 },
  ms: { t: '+{v}% 移动速度', a: 5, b: .5, pre: '疾行的', s: ['feet'], max: 30 },
  regen: { t: '每秒回复 {v} 生命', a: 1, b: .2, pre: '再生的', s: ['body', 'ring', 'neck', 'helm'] },
  crit: { t: '+{v}% 暴击几率', a: 2, b: .2, pre: '致命的', s: ['weapon', 'hands', 'ring', 'neck'], max: 15 },
  gf: { t: '+{v}% 金币掉落', a: 10, b: 2, pre: '贪婪的', s: ['ring', 'neck', 'hands', 'helm'] },
  mf: { t: '+{v}% 魔法物品掉率', a: 5, b: 1, pre: '幸运的', s: ['ring', 'neck', 'helm', 'feet'] },
  light: { t: '+{v} 照明范围', a: 1, b: .05, pre: '明亮的', s: ['helm', 'ring', 'neck'], max: 3 },
};
const UNIQ = [
  { n: '灰烬之誓', b: 'lsword', aff: { dmgp: [40, 60], ls: [4, 6], str: [5, 10], ias: [10, 15] } },
  { n: '守夜人之冠', b: 'helm', aff: { light: [2, 3], vit: [8, 12], life: [20, 35], armp: [30, 50] } },
  { n: '巡礼者之靴', b: 'boots', aff: { ms: [25, 30], regen: [3, 5], vit: [5, 8] } },
  { n: '院长的指环', b: 'ring', aff: { mag: [10, 15], spellp: [20, 30], mana: [20, 30] } },
  { n: '碎誓护符', b: 'amulet', aff: { str: [6, 10], vit: [6, 10], mag: [6, 10], crit: [5, 8] } },
  { n: '铁心', b: 'plate', aff: { armp: [60, 90], life: [40, 60], regen: [4, 6] } },
  { n: '剥皮者之怒', b: 'axe', aff: { dmgp: [60, 90], crit: [8, 12], ls: [3, 5] } },
  { n: '星火法杖', b: 'wstaff', aff: { spellp: [50, 70], mag: [10, 20], mana: [30, 50] } },
  { n: '贪婪之手', b: 'gloves', aff: { gf: [80, 120], mf: [30, 50], ias: [10, 15] } },
  { n: '守誓者壁垒', b: 'kite', aff: { armp: [80, 120], vit: [10, 15], life: [20, 30] } },
  { n: '暮光短刃', b: 'dagger', aff: { ias: [20, 30], crit: [10, 15], dmgp: [30, 45] } },
];
const RARE_A = ['血鸦', '灰烬', '恶兆', '骨语', '暮光', '裂魂', '铁誓', '焚心', '噬影', '霜痕', '亡歌', '猩红', '渊火', '荆冠'];
const RARE_B = ['之牙', '之誓', '之拥', '之冠', '之咒', '之痕', '之心', '之怒', '之啸', '之眼', '之刺', '之吻'];
const RNAME = ['普通', '魔法', '稀有', '传奇'];

function rollAff(k, ilvl) {
  const a = AFF[k]; const hi = a.a + ilvl * a.b;
  let v = ri(Math.max(1, Math.round(hi * .5)), Math.max(1, Math.round(hi)));
  if (a.max) v = Math.min(v, a.max);
  return v;
}
function rollRarity(mul) {
  const r = rand();
  if (r < .012 * mul) return 3;
  if (r < .09 * mul) return 2;
  if (r < .36 * Math.min(mul, 2)) return 1;
  return 0;
}
function baseStats(it, b, ilvl) {
  if (b.dmg) { const m = 1 + ilvl * .025; it.dmg = [Math.max(1, Math.round(b.dmg[0] * m)), Math.max(2, Math.round(b.dmg[1] * m))]; it.spd = b.spd; }
  if (b.arm) it.arm = Math.max(1, Math.round(b.arm * (1 + ilvl * .03)));
  if (b.imp) for (const k in b.imp) it.aff[k] = b.imp[k];
}
function genItem(ilvl, opt) {
  opt = opt || {};
  let rar = opt.rar != null ? opt.rar : rollRarity(opt.mul || 1);
  if (rar === 3) {
    const cands = UNIQ.filter(u => BASES[u.b].lvl <= ilvl + 4);
    if (cands.length) {
      const u = pick(cands), b = BASES[u.b], it = { id: UID++, b: u.b, r: 3, ilvl, aff: {}, n: u.n };
      baseStats(it, b, ilvl);
      const sc = 1 + ilvl / 40;
      for (const k in u.aff) { let v = Math.round(ri(u.aff[k][0], u.aff[k][1]) * (['ias', 'ls', 'ms', 'crit', 'light'].includes(k) ? 1 : sc)); it.aff[k] = (it.aff[k] || 0) + v; }
      it.req = Math.max(1, Math.min(40, Math.max(b.lvl, Math.floor(ilvl * .6))));
      return it;
    }
    rar = 2;
  }
  const keys = opt.base ? [opt.base] : Object.keys(BASES).filter(k => BASES[k].lvl <= ilvl + 1 && (!opt.slot || BASES[k].slot === opt.slot));
  const bk = pick(keys), b = BASES[bk];
  if (b.magicOnly && rar === 0) rar = 1;
  const it = { id: UID++, b: bk, r: rar, ilvl, aff: {}, n: b.n };
  baseStats(it, b, ilvl);
  const nA = rar === 1 ? ri(1, 2) : rar === 2 ? ri(3, 4) : 0;
  const pool = Object.keys(AFF).filter(k => AFF[k].s === ALL || AFF[k].s.includes(b.slot));
  const added = [];
  for (let i = 0; i < nA && pool.length; i++) {
    const k = pool.splice(Math.floor(rand() * pool.length), 1)[0];
    it.aff[k] = (it.aff[k] || 0) + rollAff(k, ilvl); added.push(k);
  }
  if (rar === 1) it.n = AFF[added[0]].pre + b.n;
  if (rar === 2) it.n = pick(RARE_A) + pick(RARE_B);
  it.req = rar === 0 ? b.lvl : Math.max(b.lvl, Math.floor(ilvl * .6));
  return it;
}
function itemValue(it) { return Math.round((12 + it.ilvl * 5) * [1, 2.5, 5, 10][it.r] + (it.arm || 0) * 2 + (it.dmg ? it.dmg[1] * 2 : 0)); }
function sellValue(it) { return Math.max(1, Math.floor(itemValue(it) / 4)); }

// ===================== 数据：怪物、技能 =====================
const MT = {
  zombie: { n: '腐尸', hp: 20, dmg: [2, 5], spd: 1.0, cd: 1.7, range: .9, xp: 12, size: 1, kind: 'melee', aggro: 6, look: 'zombie' },
  skel: { n: '骸骨战士', hp: 15, dmg: [1, 5], spd: 1.9, cd: 1.2, range: .9, xp: 11, size: .95, kind: 'melee', aggro: 8, look: 'skel' },
  imp: { n: '火坑小鬼', hp: 8, dmg: [1, 3], spd: 2.8, cd: .9, range: .8, xp: 7, size: .7, kind: 'melee', aggro: 9, look: 'imp' },
  archer: { n: '骸骨弓手', hp: 11, dmg: [2, 4], spd: 1.7, cd: 1.9, range: 6.5, xp: 13, size: .95, kind: 'ranged', proj: 'arrow', aggro: 9, look: 'archer' },
  ghoul: { n: '食尸鬼', hp: 30, dmg: [3, 7], spd: 2.2, cd: 1.3, range: 1, xp: 22, size: 1.05, kind: 'melee', aggro: 7, look: 'ghoul' },
  cultist: { n: '邪教术士', hp: 20, dmg: [3, 6], spd: 1.6, cd: 2.3, range: 7, xp: 26, size: 1, kind: 'ranged', proj: 'bolt', aggro: 9, look: 'cultist', blink: true },
  hound: { n: '熔渊猎犬', hp: 24, dmg: [3, 6], spd: 3.3, cd: 1.0, range: .9, xp: 24, size: .9, kind: 'melee', aggro: 10, look: 'hound' },
  knight: { n: '堕落骑士', hp: 45, dmg: [5, 11], spd: 1.8, cd: 1.4, range: 1.1, xp: 42, size: 1.15, kind: 'melee', aggro: 8, look: 'knight' },
  mog: { n: '腐肉监工 · 莫格', hp: 200, dmg: [6, 13], spd: 1.9, cd: 1.3, range: 1.3, xp: 350, size: 1.6, kind: 'melee', aggro: 7, look: 'mog', boss: true },
  abbot: { n: '堕落院长 · 摩登', hp: 520, dmg: [7, 13], spd: 1.7, cd: 2, range: 8, xp: 900, size: 1.35, kind: 'ranged', proj: 'bolt', aggro: 10, look: 'abbot', boss: true },
};
const CHAMP = { fast: '迅捷的', stone: '石肤的', fury: '狂怒的', vamp: '嗜血的', fire: '焚烧的' };
function poolFor(f) {
  if (f <= 1) return ['zombie', 'skel', 'imp', 'skel'];
  if (f === 2) return ['zombie', 'skel', 'imp', 'archer'];
  if (f <= 4) return ['skel', 'archer', 'ghoul', 'cultist', 'zombie'];
  if (f <= 6) return ['imp', 'cultist', 'hound', 'knight', 'ghoul'];
  return ['skel', 'archer', 'ghoul', 'cultist', 'hound', 'knight', 'imp'];
}
const SK = [
  { id: 'fireball', n: '火球术', k: '1', lvl: 1, mp: 5, cd: .4, g: '火', c: 'fire', d: '发射一枚火球，命中后爆炸，波及周围敌人。伤害受「魔力」和「法术伤害」加成。' },
  { id: 'whirl', n: '旋风斩', k: '2', lvl: 3, mp: 9, cd: .8, g: '旋', c: 'whirl', d: '挥舞武器横扫周围所有敌人，造成 130% 武器伤害。' },
  { id: 'nova', n: '冰霜新星', k: '3', lvl: 6, mp: 14, cd: 3, g: '冰', c: 'nova', d: '向四周释放寒冰，伤害并减速敌人 3 秒。' },
  { id: 'blink', n: '暗影闪现', k: '4', lvl: 10, mp: 10, cd: 4, g: '闪', c: 'blink', d: '瞬间传送到目标位置（最远 7 格，需要视线）。' },
];

// ===================== 地图常量与主题 =====================
const TW = 64, TH = 32, WALL_H = 44;
const T_VOID = 0, T_FLOOR = 1, T_WALL = 2, T_DOWN = 3, T_UP = 4, T_TREE = 6;
const THEMES = {
  town: { n: '烬原镇', fa: [58, 55, 40], wt: '#6e5a44', wl: '#4c3b2c', wr: '#3a2d22', dark: .42 },
  crypt: { n: '修道院地窖', fa: [56, 52, 48], wt: '#5f5850', wl: '#433c36', wr: '#332e2a', dark: .9 },
  catacomb: { n: '白骨墓穴', fa: [45, 52, 46], wt: '#56604f', wl: '#3c4339', wr: '#2e342c', dark: .92 },
  inferno: { n: '熔渊', fa: [60, 36, 32], wt: '#5e3027', wl: '#44231c', wr: '#341a15', dark: .88, lava: true },
  abyss: { n: '无尽深渊', fa: [44, 36, 58], wt: '#4a3a62', wl: '#342848', wr: '#271e37', dark: .92, lava: true },
};
function themeFor(f) { return f <= 2 ? 'crypt' : f <= 4 ? 'catacomb' : f <= 6 ? 'inferno' : 'abyss'; }
function floorName(f) { if (f === 0) return '烬原镇'; const th = THEMES[themeFor(f)]; return `${th.n} · 第 ${f} 层`; }
function isBossFloor(f) { return f === 3 || f === 6 || (f > 6 && f % 5 === 0); }

// ===================== 游戏状态 =====================
let hero = null;          // 持久化的角色数据
const S = {};             // 计算后的角色属性
let P = null;             // 玩家实体
let M = null;             // 当前地图
let town = null;
let maps = {};
let state = 'title';      // title / play / dead
let paused = false;
let time = 0, shake = 0, saveTimer = 0;
let hover = null, lastHit = null;
let bigMap = false;
let shopStock = { smith: [], alch: [] };

function newHero() {
  return {
    v: 1, lvl: 1, xp: 0, str: 15, vit: 15, mag: 15, pts: 0, gold: 60, hp: 999, mp: 999,
    pots: { hp: 3, mp: 2, tp: 1 }, inv: [], eq: {}, maxFloor: 0, q: { q1: 0, q2: 0, q3: 0 }, kills: 0, deaths: 0, won: false, buff: null
  };
}
function xpNeed(l) { return Math.floor(90 * Math.pow(l, 1.65)); }

function calcStats() {
  const a = { str: 0, vit: 0, mag: 0, life: 0, mana: 0, dmgp: 0, spellp: 0, armp: 0, ias: 0, ls: 0, ms: 0, regen: 0, crit: 0, gf: 0, mf: 0, light: 0 };
  let arm = 0, wdmg = [1, 3], wspd = 1.1;
  for (const k in hero.eq) {
    const it = hero.eq[k]; if (!it) continue;
    if (it.arm) arm += it.arm;
    if (it.dmg) { wdmg = it.dmg; wspd = it.spd; }
    for (const x in it.aff) a[x] = (a[x] || 0) + it.aff[x];
  }
  const bf = hero.buff && hero.buff.t > 0 ? hero.buff.k : null;
  S.str = hero.str + a.str; S.vit = hero.vit + a.vit; S.mag = hero.mag + a.mag;
  S.maxHp = Math.round(30 + S.vit * 2 + hero.lvl * 4 + a.life);
  S.maxMp = Math.round(10 + S.mag * 1.5 + hero.lvl * 1.5 + a.mana);
  const mul = (1 + S.str / 100) * (1 + a.dmgp / 100) * (bf === 'might' ? 1.5 : 1);
  S.dmg = [Math.max(1, Math.round(wdmg[0] * mul)), Math.max(1, Math.round(wdmg[1] * mul))];
  S.aps = wspd * (1 + a.ias / 100) * (bf === 'swift' ? 1.25 : 1);
  S.spell = (1 + S.mag / 40) * (1 + a.spellp / 100) * (bf === 'arcane' ? 1.3 : 1);
  S.arm = Math.round((arm + hero.lvl) * (1 + a.armp / 100) * (bf === 'guard' ? 1.5 : 1));
  S.ls = a.ls; S.crit = 5 + a.crit;
  S.ms = 4.3 * (1 + a.ms / 100) * (bf === 'swift' ? 1.2 : 1);
  S.regen = .4 + a.regen + hero.lvl * .05;
  S.mregen = (1.2 + S.mag * .06) * (bf === 'arcane' ? 3 : 1);
  S.gf = a.gf; S.mf = a.mf; S.light = 6 + a.light;
  hero.hp = Math.min(hero.hp, S.maxHp); hero.mp = Math.min(hero.mp, S.maxMp);
}
function drAgainst(lvl) { return clamp(S.arm / (S.arm + 40 + lvl * 18), 0, .75); }

// ===================== 地图 =====================
function mkMap(w, h, theme, floor) {
  return {
    w, h, theme, floor, t: new Uint8Array(w * h), deco: new Uint8Array(w * h), solid: new Uint8Array(w * h),
    seen: new Uint8Array(w * h), vis: new Uint8Array(w * h), mons: [], npcs: [], items: [], props: [], proj: [], fx: [], corpses: [],
    up: null, down: null, start: null, bossRoom: null, bossDead: false,
    g: new Float32Array(w * h), from: new Int32Array(w * h), stamp: new Uint32Array(w * h), sid: 0
  };
}
function tileAt(m, x, y) { x = Math.floor(x); y = Math.floor(y); if (x < 0 || y < 0 || x >= m.w || y >= m.h) return T_VOID; return m.t[y * m.w + x]; }
function walkT(t) { return t === T_FLOOR || t === T_DOWN || t === T_UP; }
function canWalkTile(m, X, Y) { if (X < 0 || Y < 0 || X >= m.w || Y >= m.h) return false; const i = Y * m.w + X; return walkT(m.t[i]) && !m.solid[i]; }
function canWalk(m, x, y) { return canWalkTile(m, Math.floor(x), Math.floor(y)); }
function opaque(m, X, Y) { const t = tileAt(m, X, Y); return t === T_WALL || t === T_TREE || t === T_VOID; }
function fits(m, x, y, r) { return canWalk(m, x - r, y - r) && canWalk(m, x + r, y - r) && canWalk(m, x - r, y + r) && canWalk(m, x + r, y + r); }
function losClear(m, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay, d = Math.hypot(dx, dy), n = Math.ceil(d * 3);
  for (let s = 1; s < n; s++) { if (opaque(m, Math.floor(ax + dx * s / n), Math.floor(ay + dy * s / n))) return false; }
  return true;
}
function walkLine(m, ax, ay, bx, by, r) {
  const dx = bx - ax, dy = by - ay, d = Math.hypot(dx, dy), n = Math.ceil(d * 4);
  for (let s = 1; s <= n; s++) { if (!fits(m, ax + dx * s / n, ay + dy * s / n, r)) return false; }
  return true;
}
function nearFree(m, x, y, avoidStairs) {
  const X = Math.floor(x), Y = Math.floor(y);
  for (let rad = 1; rad < 6; rad++)
    for (let dy = -rad; dy <= rad; dy++) for (let dx = -rad; dx <= rad; dx++) {
      const tx = X + dx, ty = Y + dy;
      if (!canWalkTile(m, tx, ty)) continue;
      const t = m.t[ty * m.w + tx];
      if (avoidStairs && (t === T_DOWN || t === T_UP)) continue;
      return { x: tx + .5, y: ty + .5 };
    }
  return { x: X + .5, y: Y + .5 };
}
function finishWalls(m) {
  const { w, h, t } = m;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (t[y * w + x] !== T_VOID) continue;
    let nb = false;
    for (let dy = -1; dy <= 1 && !nb; dy++) for (let dx = -1; dx <= 1; dx++) {
      const X = x + dx, Y = y + dy;
      if (X >= 0 && Y >= 0 && X < w && Y < h && walkT(t[Y * w + X])) { nb = true; break; }
    }
    if (nb) t[y * w + x] = T_WALL;
  }
}

// ----- 城镇（手工布局） -----
function genTown() {
  const w = 36, h = 36, m = mkMap(w, h, 'town', 0);
  for (let i = 0; i < w * h; i++) m.t[i] = T_FLOOR;
  const set = (x, y, v) => { if (x >= 0 && y >= 0 && x < w && y < h) m.t[y * w + x] = v; };
  const rect = (x0, y0, x1, y1, v) => { for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) set(x, y, v); };
  // 小路
  for (let y = 9; y < 33; y++) { m.deco[y * w + 17] = 1; m.deco[y * w + 18] = 1; }
  for (let x = 5; x < 31; x++) { m.deco[19 * w + x] = 1; m.deco[20 * w + x] = 1; }
  // 外围树林
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const e = Math.min(x, y, w - 1 - x, h - 1 - y);
    if (e < 2 || (e < 4 && rand() < .45 && !m.deco[y * w + x])) set(x, y, T_TREE);
  }
  // 修道院废墟（北）
  rect(12, 2, 23, 2, T_WALL); rect(12, 2, 12, 8, T_WALL); rect(23, 2, 23, 8, T_WALL);
  rect(12, 8, 15, 8, T_WALL); rect(20, 8, 23, 8, T_WALL);
  rect(13, 3, 22, 7, T_FLOOR);
  set(15, 5, T_WALL); set(20, 5, T_WALL);
  set(17, 4, T_DOWN); set(18, 4, T_DOWN);
  // 房屋
  rect(6, 12, 9, 14, T_WALL);    // 铁匠铺
  rect(26, 12, 29, 14, T_WALL);  // 药剂屋
  rect(6, 24, 9, 27, T_WALL);
  rect(25, 25, 28, 28, T_WALL);
  rect(12, 27, 14, 29, T_WALL);
  m.down = { x: 17.5, y: 4.5 };
  // 装饰与道具
  const fire = { type: 'fire', x: 20.5, y: 17.5 }; m.props.push(fire); m.solid[17 * w + 20] = 1;
  m.props.push({ type: 'well', x: 14.5, y: 22.5 }); m.solid[22 * w + 14] = 1;
  m.props.push({ type: 'wp', x: 21.5, y: 22.5 }); m.solid[22 * w + 21] = 1;
  m.props.push({ type: 'anvil', x: 10.5, y: 15.5 }); m.solid[15 * w + 10] = 1;
  m.props.push({ type: 'torch', x: 12.5, y: 8.5, face: 'L', wall: true });
  m.props.push({ type: 'torch', x: 23.5, y: 8.5, face: 'R', wall: true });
  m.props.push({ type: 'torch', x: 9.5, y: 13.5, face: 'R', wall: true });
  m.props.push({ type: 'torch', x: 26.5, y: 13.5, face: 'L', wall: true });
  for (let i = 0; i < 60; i++) { const x = ri(3, 32), y = ri(3, 32); if (m.t[y * w + x] === T_FLOOR && !m.deco[y * w + x]) m.deco[y * w + x] = pick([5, 5, 6]); }
  m.npcs.push({ kind: 'npc', id: 'elin', n: '老祭司 伊莲', g: '伊', x: 19.2, y: 18.6, face: 2.4, walk: 0, r: .3, look: 'priest' });
  m.npcs.push({ kind: 'npc', id: 'gren', n: '铁匠 格伦', g: '格', x: 10.6, y: 16.6, face: .6, walk: 0, r: .3, look: 'smith' });
  m.npcs.push({ kind: 'npc', id: 'mara', n: '药剂师 玛拉', g: '玛', x: 25.4, y: 15.8, face: 2.2, walk: 0, r: .3, look: 'alch' });
  m.portalSpot = { x: 23.5, y: 19.5 };
  finishWalls(m);
  m.seen.fill(1); m.vis.fill(1);
  return m;
}

// ----- 地下城（随机房间 + 走廊） -----
function genDungeon(f) {
  const w = 58, h = 58, m = mkMap(w, h, themeFor(f), f), rooms = [];
  const tryRoom = (rw, rh) => {
    for (let k = 0; k < 200; k++) {
      const x = ri(2, w - rw - 3), y = ri(2, h - rh - 3);
      if (rooms.every(r => x > r.x + r.w + 1 || x + rw + 1 < r.x || y > r.y + r.h + 1 || y + rh + 1 < r.y)) {
        const r = { x, y, w: rw, h: rh, cx: x + (rw >> 1), cy: y + (rh >> 1) }; rooms.push(r); return r;
      }
    }
    return null;
  };
  if (isBossFloor(f)) m.bossRoom = tryRoom(13, 13);
  const boss = !!m.bossRoom;
  const n = 11 + Math.min(5, f >> 1);
  for (let k = 0; k < n * 4 && rooms.length < n; k++) tryRoom(ri(5, 10), ri(5, 10));
  for (const r of rooms) for (let y = r.y; y < r.y + r.h; y++) for (let x = r.x; x < r.x + r.w; x++) m.t[y * w + x] = T_FLOOR;
  const conn = [rooms[0]], rest = rooms.slice(1);
  while (rest.length) {
    let bi = 0, bc = conn[0], bd = 1e9;
    for (let i = 0; i < rest.length; i++) for (const c of conn) {
      const d = Math.abs(rest[i].cx - c.cx) + Math.abs(rest[i].cy - c.cy);
      if (d < bd) { bd = d; bi = i; bc = c; }
    }
    const r = rest.splice(bi, 1)[0]; corridor(m, r, bc); conn.push(r);
  }
  for (let k = 0; k < 3; k++) { const a = pick(rooms), b = pick(rooms); if (a !== b && a !== m.bossRoom && b !== m.bossRoom) corridor(m, a, b); }
  finishWalls(m);
  // 起点：Boss 层取离 Boss 房最远的房间
  let start = rooms[0];
  if (m.bossRoom) { let bd = -1; for (const r of rooms) { if (r === m.bossRoom) continue; const d = Math.abs(r.cx - m.bossRoom.cx) + Math.abs(r.cy - m.bossRoom.cy); if (d > bd) { bd = d; start = r; } } }
  m.start = start;
  m.up = { x: start.cx + .5, y: start.cy + .5 }; m.t[start.cy * w + start.cx] = T_UP;
  const dmap = bfs(m, start.cx, start.cy);
  if (!boss) {
    let best = null, bd = -1;
    for (const r of rooms) { if (r === start) continue; const d = dmap[r.cy * w + r.cx]; if (d > bd) { bd = d; best = r; } }
    best = best || start;
    m.down = { x: best.cx + .5, y: best.cy + .5 }; m.t[best.cy * w + best.cx] = T_DOWN;
  }
  // 装饰
  for (let i = 0; i < w * h; i++) if (m.t[i] === T_FLOOR) { const r = rand(); if (r < .035) m.deco[i] = 2; else if (r < .08) m.deco[i] = 3; else if (THEMES[m.theme].lava && r < .1) m.deco[i] = 4; }
  // 火把
  for (let y = 1; y < h - 1; y++) for (let x = 1; x < w - 1; x++) {
    if (m.t[y * w + x] !== T_WALL || rand() > .07) continue;
    let face = null;
    if (walkT(m.t[(y + 1) * w + x])) face = 'L'; else if (walkT(m.t[y * w + x + 1])) face = 'R';
    if (!face) continue;
    if (m.props.some(p => p.type === 'torch' && Math.abs(p.x - x) + Math.abs(p.y - y) < 6)) continue;
    m.props.push({ type: 'torch', x: x + .5, y: y + .5, face, wall: true });
  }
  // 房间内容
  const pool = poolFor(f);
  let shrine = rand() < .75;
  for (const r of rooms) {
    if (r === start) continue;
    const spot = () => { for (let k = 0; k < 30; k++) { const x = ri(r.x + 1, r.x + r.w - 2), y = ri(r.y + 1, r.y + r.h - 2); if (m.t[y * w + x] === T_FLOOR && !m.solid[y * w + x] && !m.props.some(p => Math.floor(p.x) === x && Math.floor(p.y) === y)) return { x: x + .5, y: y + .5 }; } return null; };
    if (r !== m.bossRoom) {
      const nb = ri(0, 3); for (let i = 0; i < nb; i++) { const s = spot(); if (s) m.props.push({ type: 'barrel', x: s.x, y: s.y }); }
      if (rand() < .2) { const s = spot(); if (s) m.props.push({ type: 'chest', x: s.x, y: s.y, open: false }); }
      if (shrine && rand() < .3) { const s = spot(); if (s) { m.props.push({ type: 'shrine', x: s.x, y: s.y, used: false }); shrine = false; } }
      if (rand() < .72) {
        const champ = rand() < .12 ? pick(Object.keys(CHAMP)) : null;
        const mixed = rand() < .3, k0 = pick(pool);
        const cnt = champ ? ri(2, 3) : ri(2, 4) + (f > 3 ? 1 : 0);
        for (let i = 0; i < cnt; i++) { const s = spot(); if (s) spawnMon(m, mixed ? pick(pool) : k0, s.x, s.y, champ); }
      }
    } else {
      const bx = r.cx + .5, by = r.cy + .5;
      let bk = f === 3 ? 'mog' : f === 6 ? 'abbot' : pick(['mog', 'abbot']);
      const b = spawnMon(m, bk, bx, by, null);
      if (f > 6) b.name = '深渊化身 · ' + (bk === 'mog' ? '屠戮者' : '焚誓者');
      const guard = bk === 'mog' ? 'zombie' : 'skel';
      for (let i = 0; i < 4; i++) { const s = spot(); if (s) spawnMon(m, f > 6 ? pick(pool) : guard, s.x, s.y, null); }
      m.props.push({ type: 'torch', x: r.x - .5, y: r.cy + .5, face: 'R', wall: true });
    }
  }
  return m;
}
function corridor(m, a, b) {
  let x = a.cx, y = a.cy; const tx = b.cx, ty = b.cy;
  const dig = (x, y) => { for (let dy = 0; dy < 2; dy++) for (let dx = 0; dx < 2; dx++) { const X = x + dx, Y = y + dy; if (X > 0 && Y > 0 && X < m.w - 1 && Y < m.h - 1) m.t[Y * m.w + X] = T_FLOOR; } };
  if (rand() < .5) { while (x !== tx) { dig(x, y); x += Math.sign(tx - x); } while (y !== ty) { dig(x, y); y += Math.sign(ty - y); } }
  else { while (y !== ty) { dig(x, y); y += Math.sign(ty - y); } while (x !== tx) { dig(x, y); x += Math.sign(tx - x); } }
  dig(x, y);
}
function bfs(m, sx, sy) {
  const d = new Int32Array(m.w * m.h).fill(-1), q = [sy * m.w + sx]; d[q[0]] = 0;
  for (let h = 0; h < q.length; h++) {
    const i = q[h], x = i % m.w, y = (i / m.w) | 0;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const X = x + dx, Y = y + dy; if (!canWalkTile(m, X, Y)) continue;
      const j = Y * m.w + X; if (d[j] >= 0) continue; d[j] = d[i] + 1; q.push(j);
    }
  }
  return d;
}

function spawnMon(m, key, x, y, champ) {
  const d = MT[key], f = Math.max(1, m.floor), k = f - 1;
  const hpM = d.boss ? 1 + .35 * k : 1 + .4 * k + .03 * k * k, dmM = 1 + .3 * k;
  const e = {
    kind: 'mon', key, d, x, y, r: .3 * (d.size || 1), face: rand() * 6.28, walk: 0, atkT: 0, atkDur: .55, atkHit: false,
    cd: rand(), hit: 0, slow: 0, path: null, pi: 0, pathT: 0, state: 'idle', lvl: f * 2 + (d.boss ? 3 : 0), champ,
    name: (champ ? CHAMP[champ] : '') + d.n, spd: d.spd, home: { x, y }, wanderT: rand() * 3, t: rand() * 10, phase: 1,
    tA: 2, tS: 6, tN: 8, tB: 0, tC: 4, charge: 0
  };
  let hp = d.hp * hpM;
  if (champ) { hp *= 2.6; if (champ === 'fast') e.spd *= 1.45; }
  e.hp = e.max = Math.round(hp);
  const cm = champ ? 1.35 : 1;
  e.dmg = [Math.max(1, Math.round(d.dmg[0] * dmM * cm)), Math.max(1, Math.round(d.dmg[1] * dmM * cm))];
  e.xp = Math.round(d.xp * (1 + .45 * k) * (champ ? 3 : 1));
  m.mons.push(e);
  return e;
}

// ----- 视野 -----
function computeVis(m) {
  if (m.theme === 'town') return;
  m.vis.fill(0);
  const R = S.light + 2, px = P.x, py = P.y, X0 = Math.floor(px), Y0 = Math.floor(py);
  for (let y = Y0 - R; y <= Y0 + R; y++) for (let x = X0 - R; x <= X0 + R; x++) {
    if (x < 0 || y < 0 || x >= m.w || y >= m.h) continue;
    const dx = x + .5 - px, dy = y + .5 - py, d = Math.hypot(dx, dy); if (d > R) continue;
    const n = Math.ceil(d * 3); let ok = true;
    for (let s = 1; s < n; s++) { const cx = Math.floor(px + dx * s / n), cy = Math.floor(py + dy * s / n); if (cx === x && cy === y) break; if (opaque(m, cx, cy)) { ok = false; break; } }
    if (ok) { const i = y * m.w + x; m.vis[i] = 1; m.seen[i] = 1; }
  }
  // 与可见地面相邻的墙也可见（避免墙体缺口）
  for (let y = Math.max(1, Y0 - R); y <= Math.min(m.h - 2, Y0 + R); y++) for (let x = Math.max(1, X0 - R); x <= Math.min(m.w - 2, X0 + R); x++) {
    const i = y * m.w + x; if (m.t[i] !== T_WALL || m.vis[i]) continue;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const j = (y + dy) * m.w + x + dx; if (m.vis[j] && walkT(m.t[j])) { m.vis[i] = 1; m.seen[i] = 1; } }
  }
}

// ===================== 寻路（A*，8 方向） =====================
function findPath(m, sx, sy, tx, ty, maxN) {
  maxN = maxN || 3000;
  let X = Math.floor(tx), Y = Math.floor(ty);
  if (!canWalkTile(m, X, Y)) {
    let best = null, bd = 1e9;
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) if (canWalkTile(m, X + dx, Y + dy)) { const d = Math.hypot(X + dx + .5 - tx, Y + dy + .5 - ty); if (d < bd) { bd = d; best = [X + dx, Y + dy]; } }
    if (!best) return null; X = best[0]; Y = best[1];
  }
  const w = m.w, S0 = Math.floor(sy) * w + Math.floor(sx), G = Y * w + X;
  if (S0 === G) return [{ x: tx, y: ty }];
  const sid = ++m.sid, g = m.g, from = m.from, st = m.stamp;
  const heap = [], hf = [];
  const push = (i, f) => { heap.push(i); hf.push(f); let c = heap.length - 1; while (c > 0) { const p = (c - 1) >> 1; if (hf[p] <= hf[c]) break; [heap[p], heap[c]] = [heap[c], heap[p]]; [hf[p], hf[c]] = [hf[c], hf[p]]; c = p; } };
  const pop = () => { const top = heap[0], lh = heap.pop(), lf = hf.pop(); if (heap.length) { heap[0] = lh; hf[0] = lf; let c = 0; for (;;) { const l = c * 2 + 1, r = l + 1; let s = c; if (l < heap.length && hf[l] < hf[s]) s = l; if (r < heap.length && hf[r] < hf[s]) s = r; if (s === c) break; [heap[s], heap[c]] = [heap[c], heap[s]]; [hf[s], hf[c]] = [hf[c], hf[s]]; c = s; } } return top; };
  const hx = (i) => { const dx = Math.abs(i % w - X), dy = Math.abs(((i / w) | 0) - Y); return (dx + dy) + (1.414 - 2) * Math.min(dx, dy); };
  st[S0] = sid; g[S0] = 0; from[S0] = -1; push(S0, hx(S0));
  let n = 0, found = false;
  while (heap.length && n++ < maxN) {
    const i = pop(); if (i === G) { found = true; break; }
    const x = i % w, y = (i / w) | 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      if (!dx && !dy) continue;
      const nx = x + dx, ny = y + dy; if (!canWalkTile(m, nx, ny)) continue;
      if (dx && dy && (!canWalkTile(m, x + dx, y) || !canWalkTile(m, x, y + dy))) continue;
      const j = ny * w + nx, ng = g[i] + (dx && dy ? 1.414 : 1);
      if (st[j] === sid && g[j] <= ng) continue;
      st[j] = sid; g[j] = ng; from[j] = i; push(j, ng + hx(j));
    }
  }
  if (!found) return null;
  const pts = []; let c = G;
  while (c !== S0 && c >= 0) { pts.push({ x: c % w + .5, y: ((c / w) | 0) + .5 }); c = from[c]; }
  pts.reverse();
  if (canWalkTile(m, Math.floor(tx), Math.floor(ty)) && pts.length) pts[pts.length - 1] = { x: tx, y: ty };
  return pts;
}

// ===================== 实体移动 =====================
function moveBy(e, dx, dy) {
  const r = e.r * .9;
  if (fits(M, e.x + dx, e.y, r)) e.x += dx;
  if (fits(M, e.x, e.y + dy, r)) e.y += dy;
}
function faceTo(e, tx, ty) { const dx = tx - e.x, dy = ty - e.y; e.face = Math.atan2((dx + dy) * .5, dx - dy); }
function stepPath(e, spd, dt) {
  if (!e.path || e.pi >= e.path.length) return false;
  // 路径平滑：能直接走到下一个点就跳过当前点
  while (e.pi < e.path.length - 1 && walkLine(M, e.x, e.y, e.path[e.pi + 1].x, e.path[e.pi + 1].y, e.r * .9)) e.pi++;
  const p = e.path[e.pi], dx = p.x - e.x, dy = p.y - e.y, d = Math.hypot(dx, dy), s = spd * dt;
  faceTo(e, p.x, p.y);
  if (d <= s) { e.x = p.x; e.y = p.y; e.pi++; }
  else moveBy(e, dx / d * s, dy / d * s);
  e.walk += dt * spd * 3.2;
  return true;
}
function setPath(e, tx, ty) { const p = findPath(M, e.x, e.y, tx, ty); e.path = p; e.pi = 0; return !!p; }

// ===================== 日志与飘字 =====================
function log(txt, col) {
  const el = $('log'), d = document.createElement('div');
  d.textContent = txt; d.style.color = col || '#e9dcc6'; el.appendChild(d);
  while (el.children.length > 5) el.removeChild(el.firstChild);
  setTimeout(() => { d.style.opacity = '0'; }, 3200); setTimeout(() => { if (d.parentNode) d.parentNode.removeChild(d); }, 4000);
}
function ftext(x, y, txt, col, big) { M.fx.push({ type: 'txt', x, y, txt: String(txt), col, t: 1.1, big: !!big }); }
function burst(x, y, col, n, spd, up) {
  if (REDUCED) n = Math.ceil(n / 3);
  for (let i = 0; i < n; i++) { const a = rand() * 6.28, s = (spd || 2) * (.3 + rand()); M.fx.push({ type: 'p', x, y, z: 14 + rand() * 12, vx: Math.cos(a) * s, vy: Math.sin(a) * s, vz: (up || 40) * (.5 + rand()), col, t: .5 + rand() * .5, sz: 1.5 + rand() * 2 }); }
}

// ===================== 玩家 =====================
function mkPlayer(x, y) { return { kind: 'player', x, y, r: .28, face: .8, walk: 0, atkT: 0, atkDur: .5, atkHit: false, atkTgt: null, target: null, path: null, pi: 0, cds: {}, holdT: 0, flash: 0, stairLock: true, lastTile: -1, casting: 0 }; }

function updPlayer(dt) {
  calcStats();
  if (hero.buff && hero.buff.t > 0) { hero.buff.t -= dt; if (hero.buff.t <= 0) { hero.buff = null; log('神殿祝福消失了', '#a8987f'); } }
  hero.hp = Math.min(S.maxHp, hero.hp + S.regen * dt);
  hero.mp = Math.min(S.maxMp, hero.mp + S.mregen * dt);
  for (const k in P.cds) P.cds[k] = Math.max(0, P.cds[k] - dt);
  if (P.flash > 0) P.flash -= dt;
  if (P.casting > 0) P.casting -= dt;
  // 普攻动作
  if (P.atkT > 0) {
    P.atkT -= dt;
    if (!P.atkHit && P.atkT <= P.atkDur * .5) { P.atkHit = true; resolveMelee(P.atkTgt); }
    return;
  }
  // 键盘移动（WASD / 方向键，屏幕方向）
  let kx = 0, ky = 0;
  if (keys.w || keys.arrowup) { kx -= 1; ky -= 1; }
  if (keys.s || keys.arrowdown) { kx += 1; ky += 1; }
  if (keys.a || keys.arrowleft) { kx -= 1; ky += 1; }
  if (keys.d || keys.arrowright) { kx += 1; ky -= 1; }
  if (kx || ky) {
    const l = Math.hypot(kx, ky), s = S.ms * dt;
    P.target = null; P.path = null;
    moveBy(P, kx / l * s, ky / l * s); faceTo(P, P.x + kx, P.y + ky); P.walk += dt * S.ms * 3.2;
  } else if (P.target) {
    const t = P.target;
    if (t.dead || (t.kind === 'item' && !M.items.includes(t)) || (t.kind === 'mon' && !M.mons.includes(t))) { P.target = null; }
    else {
      const range = t.kind === 'mon' ? .75 + t.r + P.r : 1.5;
      if (dist(P, t) <= range && (t.kind !== 'mon' || losClear(M, P.x, P.y, t.x, t.y))) { P.path = null; act(t); }
      else {
        P.holdT -= dt;
        if (P.holdT <= 0 || !P.path) { setPath(P, t.x, t.y); P.holdT = .3; }
        if (!stepPath(P, S.ms, dt)) { if (!P.path) P.target = null; }
      }
    }
  } else if (mouse.down && mouse.mode === 'move') {
    P.holdT -= dt;
    if (P.holdT <= 0) { setPath(P, mouse.wx, mouse.wy); P.holdT = .15; }
    stepPath(P, S.ms, dt);
  } else if (P.path) {
    if (!stepPath(P, S.ms, dt)) P.path = null;
  }
  // 楼梯 / 传送门
  const ti = Math.floor(P.y) * M.w + Math.floor(P.x);
  const tt = M.t[ti];
  if (tt !== T_DOWN && tt !== T_UP) P.stairLock = false;
  else if (!P.stairLock) { P.stairLock = true; useStairs(tt); return; }
  if (ti !== P.lastTile) { P.lastTile = ti; computeVis(M); }
}

function act(t) {
  if (t.kind === 'mon') {
    P.atkDur = 1 / S.aps; P.atkT = P.atkDur; P.atkHit = false; P.atkTgt = t; faceTo(P, t.x, t.y); Snd.play('swing');
    if (!(mouse.down && mouse.target === t)) P.target = null;
    return;
  }
  P.target = null;
  if (t.kind === 'item') pickUp(t);
  else if (t.kind === 'npc') { faceTo(t, P.x, P.y); talk(t); }
  else if (t.kind === 'prop') useProp(t.p);
}

function resolveMelee(t) {
  if (!t || t.dead || !M.mons.includes(t)) return;
  if (dist(P, t) > .75 + t.r + P.r + .5) return;
  let d = ri(S.dmg[0], S.dmg[1]); const crit = rand() * 100 < S.crit; if (crit) d *= 2;
  hurtMon(t, d, crit, 'phys');
  if (S.ls > 0) healHero(d * S.ls / 100);
  // 击退
  const dx = t.x - P.x, dy = t.y - P.y, l = Math.hypot(dx, dy) || 1;
  if (!t.d.boss) moveBy(t, dx / l * .12, dy / l * .12);
}
function healHero(v) { hero.hp = Math.min(S.maxHp, hero.hp + v); }

function hurtMon(e, amt, crit, type) {
  if (e.dead) return;
  if (e.champ === 'stone') amt *= .6;
  amt = Math.max(1, Math.round(amt));
  e.hp -= amt; e.hit = .15; if (e.state === 'idle') alertPack(e);
  e.state = 'chase';
  lastHit = { e, t: 3 };
  ftext(e.x, e.y, crit ? amt + '!' : amt, crit ? '#ffd24a' : type === 'fire' ? '#ff9a4a' : type === 'cold' ? '#9ad8ff' : '#f2e8d8', crit);
  burst(e.x, e.y, e.d.look === 'skel' || e.d.look === 'archer' ? '#d8d2bf' : '#8a1410', crit ? 10 : 5, 2);
  Snd.play(crit ? 'crit' : 'hit');
  if (crit) shake = Math.max(shake, 4);
  if (e.hp <= 0) killMon(e);
}
function alertPack(e) { for (const o of M.mons) if (o.state === 'idle' && dist(o, e) < 5) o.state = 'chase'; }

function hurtHero(amt, lvl, src) {
  if (state !== 'play') return;
  amt = Math.max(1, Math.round(amt * (1 - drAgainst(lvl || 1))));
  hero.hp -= amt; P.flash = .15; shake = Math.max(shake, 3);
  ftext(P.x, P.y, amt, '#ff5a44');
  if (src && src.champ === 'vamp') src.hp = Math.min(src.max, src.hp + amt);
  if (rand() < .5) Snd.play('hurt');
  if (hero.hp <= 0) die();
}

function killMon(e) {
  e.dead = true;
  M.mons.splice(M.mons.indexOf(e), 1);
  M.corpses.push({ x: e.x, y: e.y, look: e.d.look, size: e.d.size || 1, face: e.face, t: 0, champ: e.champ });
  if (M.corpses.length > 90) M.corpses.shift();
  burst(e.x, e.y, '#6a0c08', 12, 2.5);
  Snd.play('die');
  hero.kills++;
  // 经验（等级差距过大时衰减）
  const diff = hero.lvl - e.lvl;
  const xp = Math.round(e.xp * (diff > 5 ? Math.max(.1, 1 - (diff - 5) * .15) : 1));
  gainXp(xp);
  if (e.champ === 'fire') { M.fx.push({ type: 'ring', x: e.x, y: e.y, rad: 0, max: 2.2, spd: 6, dmg: e.dmg[1], lvl: e.lvl, hit: false, col: '#ff7a2a' }); }
  dropLoot(e);
  if (e.d.boss) bossDown(e);
}

function gainXp(v) {
  if (hero.lvl >= 50) return;
  hero.xp += v;
  while (hero.xp >= xpNeed(hero.lvl) && hero.lvl < 50) {
    hero.xp -= xpNeed(hero.lvl); hero.lvl++; hero.pts += 5;
    calcStats(); hero.hp = S.maxHp; hero.mp = S.maxMp;
    log(`升级！你现在是 ${hero.lvl} 级，获得 5 点属性点（按 C 分配）`, '#ffd24a');
    const sk = SK.find(s => s.lvl === hero.lvl); if (sk) log(`学会新技能：${sk.n}（按键 ${sk.k}）`, '#ffd24a');
    M.fx.push({ type: 'lvl', x: P.x, y: P.y, t: 1.4 });
    Snd.play('lvl'); saveGame();
  }
}

// ===================== 掉落 =====================
function dropItemAt(it, x, y) {
  const a = rand() * 6.28, r = .3 + rand() * .7;
  let px = x + Math.cos(a) * r, py = y + Math.sin(a) * r;
  if (!canWalk(M, px, py)) { px = x; py = y; }
  M.items.push({ kind: 'item', it, x: px, y: py, t: 0 });
  if (it.r === 3) Snd.play('legend'); else if (it.r === 2) Snd.play('rare');
}
function dropGold(x, y, amt) { dropItemAt({ gold: Math.max(1, Math.round(amt)), n: '金币', r: 0 }, x, y); }
function dropLoot(e) {
  const f = Math.max(1, M.floor), mf = 1 + S.mf / 100, gf = 1 + S.gf / 100;
  const ilvl = f * 2 + (e.d.boss ? 3 : e.champ ? 1 : 0);
  if (e.d.boss) {
    dropGold(e.x, e.y, ri(f * 40, f * 80) * gf);
    dropItemAt(genItem(ilvl, { rar: rand() < .45 ? 3 : 2 }), e.x, e.y);
    dropItemAt(genItem(ilvl, { rar: 2 }), e.x, e.y);
    dropItemAt(genItem(ilvl, { mul: mf * 3 }), e.x, e.y);
    dropItemAt(genItem(ilvl, { mul: mf * 3 }), e.x, e.y);
    dropItemAt({ pot: 'hp', n: '生命药水', r: 0 }, e.x, e.y);
    return;
  }
  if (rand() < .42) dropGold(e.x, e.y, ri(f * 3, f * 9) * gf * (e.champ ? 3 : 1));
  if (rand() < .08) dropItemAt(rand() < .7 ? { pot: 'hp', n: '生命药水', r: 0 } : { pot: 'mp', n: '法力药水', r: 0 }, e.x, e.y);
  if (rand() < .015) dropItemAt({ pot: 'tp', n: '回城卷轴', r: 0 }, e.x, e.y);
  const n = e.champ ? (rand() < .7 ? 2 : 1) : (rand() < .11 ? 1 : 0);
  for (let i = 0; i < n; i++) dropItemAt(genItem(ilvl, { mul: mf * (e.champ ? 2.5 : 1) }), e.x, e.y);
}
function pickUp(gi) {
  const it = gi.it;
  if (it.gold) { hero.gold += it.gold; log(`拾取 ${it.gold} 金币`, '#c9a35a'); Snd.play('gold'); }
  else if (it.pot) { hero.pots[it.pot]++; log(`拾取 ${it.n}`, '#e9dcc6'); Snd.play('pick'); }
  else {
    if (hero.inv.length >= 40) { log('背包已满', '#e0604a'); return; }
    hero.inv.push(it); log(`拾取 ${it.n}`, ['#e9e3d6', '#7c8cff', '#f3d34a', '#e8843a'][it.r]); Snd.play(it.r ? 'magic' : 'pick');
    refreshPanel();
  }
  M.items.splice(M.items.indexOf(gi), 1);
}

// ===================== 道具（宝箱/木桶/神殿/传送石/传送门） =====================
const SHRINES = [
  { k: 'might', n: '力量神殿', d: '伤害 +50%' },
  { k: 'guard', n: '守护神殿', d: '护甲 +50%' },
  { k: 'swift', n: '迅捷神殿', d: '攻击速度 +25%、移动速度 +20%' },
  { k: 'arcane', n: '秘法神殿', d: '法力回复 ×3、法术伤害 +30%' },
];
function useProp(p) {
  const f = Math.max(1, M.floor);
  if (p.type === 'chest' && !p.open) {
    p.open = true; Snd.play('chest');
    dropGold(p.x, p.y, ri(f * 8, f * 20) * (1 + S.gf / 100));
    const n = ri(1, 2); for (let i = 0; i < n; i++) dropItemAt(genItem(f * 2 + 1, { mul: (1 + S.mf / 100) * 2 }), p.x, p.y);
    if (rand() < .5) dropItemAt({ pot: pick(['hp', 'hp', 'mp']), n: '药水', r: 0 }, p.x, p.y);
    fixPotNames();
  } else if (p.type === 'barrel' && !p.broken) {
    p.broken = true; Snd.play('barrel'); burst(p.x, p.y, '#7a5230', 10, 2.5);
    const r = rand();
    if (r < .3) dropGold(p.x, p.y, ri(f * 2, f * 6));
    else if (r < .42) dropItemAt({ pot: 'hp', n: '生命药水', r: 0 }, p.x, p.y);
    else if (r < .47) dropItemAt(genItem(f * 2, {}), p.x, p.y);
    else if (r < .55) { for (let i = 0; i < ri(1, 2); i++) { const s = nearFree(M, p.x, p.y, true); spawnMon(M, 'imp', s.x, s.y, null).state = 'chase'; } log('木桶里窜出了火坑小鬼！', '#e0604a'); }
    M.props.splice(M.props.indexOf(p), 1);
  } else if (p.type === 'shrine' && !p.used) {
    p.used = true; const s = pick(SHRINES); hero.buff = { k: s.k, t: 90 };
    healHero(S.maxHp); hero.mp = S.maxMp; Snd.play('shrine');
    log(`${s.n}：${s.d}，持续 90 秒`, '#9ad8ff');
    M.fx.push({ type: 'lvl', x: P.x, y: P.y, t: 1.2, col: '#6ac8ff' });
  } else if (p.type === 'wp') openWaypoint();
  else if (p.type === 'portal') usePortal(p);
  else if (p.type === 'well') { healHero(S.maxHp); log('井水清凉，你的伤口愈合了', '#9ad8ff'); Snd.play('potion'); }
  else if (p.type === 'fire') log('篝火噼啪作响。', '#a8987f');
}
function fixPotNames() { for (const gi of M.items) if (gi.it.pot && gi.it.n === '药水') gi.it.n = gi.it.pot === 'hp' ? '生命药水' : '法力药水'; }

// ===================== 楼层切换 =====================
function enterMap(m, x, y) {
  M = m; P.x = x; P.y = y; P.path = null; P.target = null; P.atkT = 0; P.stairLock = true; P.lastTile = -1;
  lastHit = null; hover = null;
  if (m === town) refreshShops();
  computeVis(M);
  updateLoc();
  saveGame();
}
function goFloor(f, via) {
  if (f <= 0) { const s = nearFree(town, town.down.x, town.down.y + 2, true); enterMap(town, s.x, s.y); log('你回到了烬原镇', '#c9a35a'); return; }
  const fresh = !maps[f];
  const m = maps[f] || (maps[f] = genDungeon(f));
  if (f > hero.maxFloor) hero.maxFloor = f;
  if (hero.q.q1 === 1 && f >= 2) { hero.q.q1 = 2; log('任务更新：回镇上告诉伊莲地窖的情况', '#ffd24a'); }
  let at = via === 'up' && m.down ? m.down : m.up;
  const s = nearFree(m, at.x, at.y, true);
  enterMap(m, s.x, s.y);
  log(floorName(f), '#c9a35a');
  if (fresh && m.bossRoom) log('空气里弥漫着腐臭与焦灼……这一层有强大的存在', '#e0604a');
}
function useStairs(t) {
  if (M === town) { if (t === T_DOWN) goFloor(1, 'down'); return; }
  if (t === T_DOWN) goFloor(M.floor + 1, 'down');
  else if (t === T_UP) goFloor(M.floor - 1, 'up');
}
let tp = null; // {map, x, y}
function castTownPortal() {
  if (M === town) { log('你已经在镇上了', '#a8987f'); return; }
  if (hero.pots.tp <= 0) { log('没有回城卷轴（可以在药剂师玛拉处购买）', '#e0604a'); return; }
  hero.pots.tp--; Snd.play('portal');
  for (const m of [M, town]) m.props = m.props.filter(p => p.type !== 'portal');
  const s = nearFree(M, P.x + .8, P.y + .8, true);
  M.props.push({ type: 'portal', x: s.x, y: s.y, to: 'town' });
  town.props.push({ type: 'portal', x: town.portalSpot.x, y: town.portalSpot.y, to: 'dungeon' });
  tp = { map: M, x: s.x, y: s.y };
  log('一道蓝色的传送门打开了', '#7fd6ff');
}
function usePortal(p) {
  Snd.play('portal');
  if (p.to === 'town') { const s = nearFree(town, town.portalSpot.x + 1, town.portalSpot.y + 1, true); enterMap(town, s.x, s.y); }
  else if (tp) {
    const m = tp.map; town.props = town.props.filter(q => q.type !== 'portal'); m.props = m.props.filter(q => q.type !== 'portal');
    const s = nearFree(m, tp.x, tp.y, true); tp = null; enterMap(m, s.x, s.y); log(floorName(m.floor), '#c9a35a');
  }
}

// ===================== 技能 =====================
function castSkill(i, tx, ty) {
  if (state !== 'play' || paused) return;
  const sk = SK[i]; if (!sk) return;
  if (hero.lvl < sk.lvl) { log(`${sk.n} 需要 ${sk.lvl} 级`, '#a8987f'); return; }
  if (M === town) { log('镇上不能施法', '#a8987f'); return; }
  if ((P.cds[sk.id] || 0) > 0 || P.atkT > 0) return;
  if (hero.mp < sk.mp) { log('法力不足', '#7c8cff'); return; }
  if (tx == null) { const a = autoAim(sk.id === 'blink' ? 5 : 8); tx = a.x; ty = a.y; }
  if (sk.id === 'blink') {
    let dx = tx - P.x, dy = ty - P.y; const d = Math.hypot(dx, dy); if (d > 7) { dx *= 7 / d; dy *= 7 / d; }
    let nx = P.x + dx, ny = P.y + dy;
    for (let k = 0; k < 10 && !(fits(M, nx, ny, P.r) && losClear(M, P.x, P.y, nx, ny)); k++) { nx -= dx * .1; ny -= dy * .1; }
    if (!fits(M, nx, ny, P.r)) { log('无法闪现到那里', '#a8987f'); return; }
    burst(P.x, P.y, '#b58aff', 14, 2); P.x = nx; P.y = ny; burst(P.x, P.y, '#b58aff', 14, 2); Snd.play('blink');
    P.path = null; P.target = null; computeVis(M);
  } else if (sk.id === 'fireball') {
    faceTo(P, tx, ty);
    const dx = tx - P.x, dy = ty - P.y, l = Math.hypot(dx, dy) || 1;
    M.proj.push({ x: P.x + dx / l * .4, y: P.y + dy / l * .4, vx: dx / l * 9, vy: dy / l * 9, own: 'p', kind: 'fire', life: 1.2, r: .25, dmg: (4 + hero.lvl * 1.6) * S.spell });
    Snd.play('fire');
  } else if (sk.id === 'whirl') {
    let n = 0;
    for (const e of M.mons.slice()) if (dist(e, P) < 1.9 + e.r) { let d = ri(S.dmg[0], S.dmg[1]) * 1.3; const c = rand() * 100 < S.crit; if (c) d *= 2; hurtMon(e, d, c, 'phys'); if (S.ls) healHero(d * S.ls / 100); n++; }
    M.fx.push({ type: 'whirl', x: P.x, y: P.y, t: .35 }); Snd.play('whirl');
  } else if (sk.id === 'nova') {
    M.fx.push({ type: 'nova', x: P.x, y: P.y, t: .5 }); Snd.play('ice');
    for (const e of M.mons.slice()) if (dist(e, P) < 4 && losClear(M, P.x, P.y, e.x, e.y)) { e.slow = 3; hurtMon(e, (6 + hero.lvl * 2) * S.spell * (.85 + rand() * .3), false, 'cold'); }
  }
  hero.mp -= sk.mp; P.cds[sk.id] = sk.cd; P.casting = .25;
}
function autoAim(fallback) {
  let best = null, bd = 9;
  for (const e of M.mons) { if (!M.vis[Math.floor(e.y) * M.w + Math.floor(e.x)]) continue; const d = dist(e, P); if (d < bd && losClear(M, P.x, P.y, e.x, e.y)) { bd = d; best = e; } }
  if (best) return { x: best.x, y: best.y };
  const a = P.face; // 屏幕朝向转回世界方向
  const sx = Math.cos(a), sy = Math.sin(a) * 2;
  const wx = (sx + sy) / 2, wy = (sy - sx) / 2, l = Math.hypot(wx, wy) || 1;
  return { x: P.x + wx / l * fallback, y: P.y + wy / l * fallback };
}
function drinkPotion(k) {
  if (state !== 'play' || paused) return;
  if (hero.pots[k] <= 0) { log(k === 'hp' ? '没有生命药水了' : '没有法力药水了', '#e0604a'); return; }
  if (k === 'hp' && hero.hp >= S.maxHp) return;
  if (k === 'mp' && hero.mp >= S.maxMp) return;
  hero.pots[k]--; Snd.play('potion');
  if (k === 'hp') { const v = Math.round(S.maxHp * .45 + 10); healHero(v); ftext(P.x, P.y, '+' + v, '#6fd46f'); }
  else { const v = Math.round(S.maxMp * .5 + 5); hero.mp = Math.min(S.maxMp, hero.mp + v); ftext(P.x, P.y, '+' + v, '#6a9aff'); }
}

// ===================== 怪物 AI =====================
function updMon(e, dt) {
  e.t += dt;
  if (e.hit > 0) e.hit -= dt;
  if (e.slow > 0) e.slow -= dt;
  e.cd -= dt;
  const spd = e.spd * (e.slow > 0 ? .5 : 1) * (e.enraged ? 1.35 : 1);
  const d = dist(e, P);
  if (e.state === 'idle') {
    const vis = M.vis[Math.floor(e.y) * M.w + Math.floor(e.x)];
    if (d < e.d.aggro && vis && losClear(M, e.x, e.y, P.x, P.y)) {
      e.state = 'chase'; alertPack(e);
      if (e.d.boss && !e.shouted) { e.shouted = true; bossShout(e); }
    } else {
      e.wanderT -= dt;
      if (e.wanderT <= 0) { e.wanderT = 2 + rand() * 4; const tx = e.home.x + (rand() - .5) * 3, ty = e.home.y + (rand() - .5) * 3; if (canWalk(M, tx, ty)) { e.path = [{ x: tx, y: ty }]; e.pi = 0; } }
      if (e.path && e.pi < e.path.length) { const p = e.path[e.pi]; if (walkLine(M, e.x, e.y, p.x, p.y, e.r)) stepPath(e, spd * .4, dt); else e.path = null; }
      return;
    }
  }
  if (e.atkT > 0) {
    e.atkT -= dt;
    if (!e.atkHit && e.atkT <= e.atkDur * .45) {
      e.atkHit = true;
      if (dist(e, P) <= e.d.range + P.r + e.r + .35) { let dm = ri(e.dmg[0], e.dmg[1]); if (e.champ === 'fire') dm *= 1.25; hurtHero(dm, e.lvl, e); }
    }
    return;
  }
  if (d > 22) { e.state = 'idle'; e.path = null; return; }
  if (e.d.boss && bossAI(e, dt, d, spd)) return;
  const los = losClear(M, e.x, e.y, P.x, P.y);
  if (e.d.kind === 'melee') {
    if (d <= e.d.range + P.r + e.r && los) {
      faceTo(e, P.x, P.y);
      if (e.cd <= 0) { e.atkDur = e.d.boss ? .7 : .55; e.atkT = e.atkDur; e.atkHit = false; e.cd = e.d.cd * (e.champ === 'fury' ? .6 : 1) * (e.enraged ? .7 : 1); }
    } else chase(e, spd, dt, los);
  } else {
    if (d <= e.d.range && los) {
      faceTo(e, P.x, P.y);
      if (e.cd <= 0) { shoot(e, P.x, P.y, e.d.proj); e.cd = e.d.cd * (e.champ === 'fury' ? .6 : 1); }
      if (e.d.blink && d < 2.2 && e.tB <= 0) { blinkAway(e); e.tB = 5; }
      else if (d < 3 && e.d.proj === 'arrow') { const dx = e.x - P.x, dy = e.y - P.y, l = Math.hypot(dx, dy) || 1; moveBy(e, dx / l * spd * dt, dy / l * spd * dt); e.walk += dt * spd * 3; }
      e.tB -= dt;
    } else chase(e, spd, dt, los);
  }
}
function chase(e, spd, dt, los) {
  if (los && walkLine(M, e.x, e.y, P.x, P.y, e.r)) {
    const dx = P.x - e.x, dy = P.y - e.y, l = Math.hypot(dx, dy) || 1;
    faceTo(e, P.x, P.y); moveBy(e, dx / l * spd * dt, dy / l * spd * dt); e.walk += dt * spd * 3.2; e.path = null;
  } else {
    e.pathT -= dt;
    if (e.pathT <= 0 || !e.path) { e.path = findPath(M, e.x, e.y, P.x, P.y, 1500); e.pi = 0; e.pathT = .5 + rand() * .5; }
    if (!stepPath(e, spd, dt)) e.path = null;
  }
}
function shoot(e, tx, ty, kind, ang) {
  const dx = tx - e.x, dy = ty - e.y; let a = Math.atan2(dy, dx) + (ang || 0);
  const sp = kind === 'arrow' ? 8 : 5.5;
  M.proj.push({ x: e.x, y: e.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, own: 'm', kind, life: 2.2, r: .22, dmg: ri(e.dmg[0], e.dmg[1]), lvl: e.lvl, src: e });
  Snd.play(kind === 'arrow' ? 'arrow' : 'bolt');
}
function blinkAway(e) {
  for (let k = 0; k < 20; k++) {
    const a = rand() * 6.28, r = 3 + rand() * 3, x = e.x + Math.cos(a) * r, y = e.y + Math.sin(a) * r;
    if (fits(M, x, y, e.r) && (!M.bossRoom || !e.d.boss || inRoom(M.bossRoom, x, y))) { burst(e.x, e.y, '#8a4aff', 10, 2); e.x = x; e.y = y; burst(x, y, '#8a4aff', 10, 2); return; }
  }
}
function inRoom(r, x, y) { return x > r.x && y > r.y && x < r.x + r.w && y < r.y + r.h; }

// ----- Boss -----
function bossShout(e) {
  Snd.play('boss');
  if (e.key === 'mog') log('「监工要你干活——用你的骨头来干！」', '#e8843a');
  else log('「流浪者……火焰选中的，究竟是我，还是你？」', '#e8843a');
}
function bossAI(e, dt, d, spd) {
  if (e.key === 'mog') {
    if (!e.enraged && e.hp < e.max * .5) { e.enraged = true; log('莫格暴怒了！', '#e0604a'); Snd.play('boss'); }
    if (e.charge > 0) {
      e.charge -= dt; const s = spd * 3.2 * dt; moveBy(e, e.cx * s, e.cy * s); e.walk += dt * 20;
      if (!e.chHit && dist(e, P) < e.r + P.r + .3) { e.chHit = true; hurtHero(e.dmg[1] * 1.4, e.lvl, e); shake = 8; }
      return true;
    }
    e.tC -= dt;
    if (e.tC <= 0 && d > 2.5 && d < 8 && losClear(M, e.x, e.y, P.x, P.y)) {
      const dx = P.x - e.x, dy = P.y - e.y, l = Math.hypot(dx, dy); e.cx = dx / l; e.cy = dy / l; e.charge = .6; e.chHit = false; e.tC = 6; faceTo(e, P.x, P.y);
      log('莫格冲了过来！', '#e0604a'); return true;
    }
    return false;
  }
  // 摩登院长
  if (e.phase === 1 && e.hp < e.max * .5) {
    e.phase = 2; e.spd *= 1.2; e.d = Object.assign({}, e.d, { size: 1.7 }); e.r = .3 * 1.7;
    e.name = '灰烬之王的容器 · 摩登'; log('余烬之心在摩登胸口燃烧——他正在变成别的东西！', '#e8843a'); Snd.play('boss'); shake = 10;
    M.fx.push({ type: 'ring', x: e.x, y: e.y, rad: 0, max: 6, spd: 5, dmg: e.dmg[1], lvl: e.lvl, hit: false, col: '#ff7a2a' });
  }
  e.tA -= dt; e.tS -= dt; e.tN -= dt; e.tB -= dt;
  const los = losClear(M, e.x, e.y, P.x, P.y);
  faceTo(e, P.x, P.y);
  if (e.tA <= 0 && los) {
    const n = e.phase === 2 ? 5 : 3; for (let i = 0; i < n; i++) shoot(e, P.x, P.y, 'bolt', (i - (n - 1) / 2) * .22);
    e.tA = e.phase === 2 ? 1.6 : 2.3;
  }
  if (e.tN <= 0) { M.fx.push({ type: 'ring', x: e.x, y: e.y, rad: 0, max: 7, spd: 4.5, dmg: e.dmg[1] * 1.2, lvl: e.lvl, hit: false, col: '#ff7a2a' }); e.tN = e.phase === 2 ? 6 : 10; Snd.play('boom'); }
  if (e.tS <= 0) {
    const adds = M.mons.filter(o => !o.d.boss).length;
    if (adds < 8) for (let i = 0; i < 2; i++) { const s = nearFree(M, e.x + (rand() - .5) * 4, e.y + (rand() - .5) * 4, true); const o = spawnMon(M, e.phase === 2 ? 'imp' : 'skel', s.x, s.y, null); o.state = 'chase'; burst(s.x, s.y, '#8a4aff', 8, 2); }
    e.tS = 13;
  }
  if (d < 2.4 && e.tB <= 0) { blinkAway(e); e.tB = 5; return true; }
  if (d > 6 || !los) chase(e, spd, dt, los);
  else if (d < 3.5) { const dx = e.x - P.x, dy = e.y - P.y, l = Math.hypot(dx, dy) || 1; moveBy(e, dx / l * spd * .6 * dt, dy / l * spd * .6 * dt); e.walk += dt * spd * 2; }
  return true;
}
function bossDown(e) {
  shake = 12;
  const r = M.bossRoom; M.bossDead = true;
  const cx = r ? r.cx : Math.floor(e.x), cy = r ? r.cy : Math.floor(e.y);
  M.t[cy * M.w + cx] = T_DOWN; M.down = { x: cx + .5, y: cy + .5 };
  if (e.key === 'mog' && M.floor === 3) {
    if (hero.q.q2 < 2) { hero.q.q2 = 2; log('你在莫格的屠宰间里找到了被锁住的托比——他还活着！托比逃回了镇上。', '#ffd24a'); }
  } else if (e.key === 'abbot' && M.floor === 6) {
    if (hero.q.q3 < 2) { hero.q.q3 = 2; setTimeout(epilogue, 1600); }
  } else log('深渊化身倒下了。更深处的裂隙打开了。', '#ffd24a');
  log('通往下一层的阶梯出现了', '#c9a35a');
  saveGame();
}

// ===================== 更新：弹道与特效 =====================
function updProj(dt) {
  for (let i = M.proj.length - 1; i >= 0; i--) {
    const p = M.proj[i]; p.life -= dt;
    const nx = p.x + p.vx * dt, ny = p.y + p.vy * dt;
    let dead = p.life <= 0;
    if (!dead && opaque(M, Math.floor(nx), Math.floor(ny))) dead = true;
    if (!dead) {
      p.x = nx; p.y = ny;
      if (p.own === 'p') {
        for (const e of M.mons) if (Math.hypot(e.x - p.x, e.y - p.y) < e.r + p.r) { dead = true; break; }
      } else if (Math.hypot(P.x - p.x, P.y - p.y) < P.r + p.r) { dead = true; hurtHero(p.dmg, p.lvl, p.src); if (p.kind === 'bolt') burst(p.x, p.y, '#b35aff', 6, 2); }
      if (p.kind === 'fire' && rand() < .6) M.fx.push({ type: 'p', x: p.x, y: p.y, z: 16, vx: (rand() - .5), vy: (rand() - .5), vz: 10, col: rand() < .5 ? '#ffb040' : '#ff5a20', t: .35, sz: 2.5 });
    }
    if (dead) {
      if (p.own === 'p' && p.kind === 'fire') {
        for (const e of M.mons.slice()) { const d = Math.hypot(e.x - p.x, e.y - p.y); if (d < 1.3 + e.r) hurtMon(e, p.dmg * (d < e.r + p.r + .1 ? 1 : .5) * (.85 + rand() * .3), false, 'fire'); }
        M.fx.push({ type: 'boom', x: p.x, y: p.y, t: .35 }); burst(p.x, p.y, '#ff8a30', 12, 3); Snd.play('boom');
      }
      M.proj.splice(i, 1);
    }
  }
}
function updFx(dt) {
  for (let i = M.fx.length - 1; i >= 0; i--) {
    const f = M.fx[i];
    if (f.type === 'ring') {
      f.rad += f.spd * dt;
      if (!f.hit && Math.abs(dist(f, P) - f.rad) < .4 && losClear(M, f.x, f.y, P.x, P.y)) { f.hit = true; hurtHero(f.dmg, f.lvl); }
      if (f.rad >= f.max) M.fx.splice(i, 1);
      continue;
    }
    f.t -= dt;
    if (f.type === 'p') { f.x += f.vx * dt; f.y += f.vy * dt; f.z += f.vz * dt; f.vz -= 120 * dt; if (f.z < 0) { f.z = 0; f.vz = 0; f.vx *= .5; f.vy *= .5; } }
    if (f.t <= 0) M.fx.splice(i, 1);
  }
  if (M.fx.length > 500) M.fx.splice(0, M.fx.length - 500);
}
function separate() {
  const ms = M.mons;
  for (let i = 0; i < ms.length; i++) {
    const a = ms[i]; if (a.state === 'idle') continue;
    for (let j = 0; j < ms.length; j++) {
      if (i === j) continue; const b = ms[j];
      const dx = a.x - b.x, dy = a.y - b.y, d = Math.hypot(dx, dy), md = a.r + b.r;
      if (d < md && d > 0.0001) { const push = (md - d) * .5; moveBy(a, dx / d * push, dy / d * push); }
    }
    const dx = a.x - P.x, dy = a.y - P.y, d = Math.hypot(dx, dy), md = a.r + P.r;
    if (d < md && d > 0.0001) moveBy(a, dx / d * (md - d), dy / d * (md - d));
  }
}

// ===================== 渲染 =====================
const cv = $('game'), ctx = cv.getContext('2d');
const lc = document.createElement('canvas'), lx = lc.getContext('2d'); const LS = .3;
let W = 0, H = 0, DPR = 1, Z = 1, camX = 0, camY = 0;
function resize() {
  DPR = Math.min(2, window.devicePixelRatio || 1); W = cv.clientWidth || window.innerWidth; H = cv.clientHeight || window.innerHeight;
  cv.width = Math.round(W * DPR); cv.height = Math.round(H * DPR);
  Z = clamp(Math.min(W, H * 1.4) / 1100, .62, 1.15);
  lc.width = Math.ceil(W * LS); lc.height = Math.ceil(H * LS);
}
function sx(x, y) { return (x - y) * TW / 2 * Z + camX; }
function sy(x, y) { return (x + y) * TH / 2 * Z + camY; }
function s2w(px, py) { const a = (px - camX) / (TW / 2 * Z), b = (py - camY) / (TH / 2 * Z); return [(a + b) / 2, (b - a) / 2]; }
function hash(x, y) { let h = x * 374761393 + y * 668265263; h = (h ^ (h >> 13)) * 1274126177; return ((h ^ (h >> 16)) >>> 0) / 4294967295; }
function rgb(c, k) { return `rgb(${Math.round(c[0] * k)},${Math.round(c[1] * k)},${Math.round(c[2] * k)})`; }

function diamond(x, y, fill) {
  ctx.beginPath();
  ctx.moveTo(sx(x, y), sy(x, y)); ctx.lineTo(sx(x + 1, y), sy(x + 1, y)); ctx.lineTo(sx(x + 1, y + 1), sy(x + 1, y + 1)); ctx.lineTo(sx(x, y + 1), sy(x, y + 1));
  ctx.closePath(); ctx.fillStyle = fill; ctx.fill();
}
function drawFloor(x, y, i) {
  const th = THEMES[M.theme], hv = hash(x, y), t = M.t[i];
  let k = .88 + hv * .22;
  if (M.theme === 'town') {
    const dc = M.deco[i];
    diamond(x, y, dc === 1 ? rgb([88, 74, 56], k) : rgb([46 + hv * 10, 56 + hv * 10, 34], k));
    if (dc === 5 || dc === 6) { const cx = sx(x + .5, y + .5), cy = sy(x + .5, y + .5); ctx.strokeStyle = dc === 5 ? '#4a5a2a' : '#6a5a3a'; ctx.lineWidth = 1.2 * Z; ctx.beginPath(); for (let j = 0; j < 4; j++) { const ox = (hash(x + j, y) - .5) * 30 * Z, oy = (hash(x, y + j) - .5) * 12 * Z; ctx.moveTo(cx + ox, cy + oy); ctx.lineTo(cx + ox + 1.5 * Z, cy + oy - 5 * Z); } ctx.stroke(); }
  } else {
    diamond(x, y, rgb(th.fa, k));
    const dc = M.deco[i], cx = sx(x + .5, y + .5), cy = sy(x + .5, y + .5);
    // 石板缝
    if (hv > .55) { ctx.strokeStyle = 'rgba(0,0,0,.25)'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(sx(x + .5, y), sy(x + .5, y)); ctx.lineTo(sx(x + .5, y + 1), sy(x + .5, y + 1)); ctx.stroke(); }
    if (dc === 2) { ctx.strokeStyle = '#cfc6b0'; ctx.lineWidth = 2 * Z; ctx.beginPath(); ctx.moveTo(cx - 8 * Z, cy); ctx.lineTo(cx + 6 * Z, cy + 3 * Z); ctx.moveTo(cx - 2 * Z, cy - 4 * Z); ctx.lineTo(cx + 2 * Z, cy + 5 * Z); ctx.stroke(); ctx.fillStyle = '#d8d0ba'; ctx.beginPath(); ctx.arc(cx + 9 * Z, cy - 2 * Z, 3.2 * Z, 0, 6.3); ctx.fill(); }
    else if (dc === 3) { ctx.strokeStyle = 'rgba(0,0,0,.35)'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(cx - 12 * Z, cy - 2 * Z); ctx.lineTo(cx - 3 * Z, cy + 2 * Z); ctx.lineTo(cx + 6 * Z, cy - 1 * Z); ctx.stroke(); }
    else if (dc === 4) { const g = .6 + .4 * Math.sin(time * 2 + x + y); ctx.strokeStyle = M.theme === 'abyss' ? `rgba(180,90,255,${g})` : `rgba(255,${100 + g * 60 | 0},30,${g})`; ctx.lineWidth = 1.6 * Z; ctx.beginPath(); ctx.moveTo(cx - 14 * Z, cy + 1 * Z); ctx.lineTo(cx - 4 * Z, cy - 2 * Z); ctx.lineTo(cx + 3 * Z, cy + 3 * Z); ctx.lineTo(cx + 13 * Z, cy); ctx.stroke(); }
  }
  if (t === T_DOWN || t === T_UP) {
    const cx = sx(x + .5, y + .5), cy = sy(x + .5, y + .5);
    diamond(x + .1, y + .1, '#0a0706');
    ctx.strokeStyle = t === T_DOWN ? '#6a5a44' : '#8a7a60'; ctx.lineWidth = 2 * Z;
    for (let s = 0; s < 4; s++) { const o = s * .2; ctx.beginPath(); ctx.moveTo(sx(x + .15 + o, y + .15), sy(x + .15 + o, y + .15)); ctx.lineTo(sx(x + .15 + o, y + .85), sy(x + .15 + o, y + .85)); ctx.stroke(); }
    const g = .5 + .5 * Math.sin(time * 3);
    ctx.fillStyle = `rgba(255,200,120,${.15 + g * .15})`; ctx.beginPath(); ctx.ellipse(cx, cy, 20 * Z, 10 * Z, 0, 0, 6.3); ctx.fill();
  }
}
function drawWall(x, y, alpha) {
  const th = THEMES[M.theme], i = y * M.w + x, town = M.theme === 'town';
  const h = (town ? 58 : WALL_H) * Z;
  const ax = sx(x, y), ay = sy(x, y), bx = sx(x + 1, y), by = sy(x + 1, y), cxx = sx(x + 1, y + 1), cyy = sy(x + 1, y + 1), dx = sx(x, y + 1), dy = sy(x, y + 1);
  ctx.globalAlpha = alpha;
  const southOpen = y + 1 >= M.h || M.t[i + M.w] !== T_WALL, eastOpen = x + 1 >= M.w || M.t[i + 1] !== T_WALL;
  const hv = hash(x, y);
  if (southOpen) {
    ctx.beginPath(); ctx.moveTo(dx, dy); ctx.lineTo(cxx, cyy); ctx.lineTo(cxx, cyy - h); ctx.lineTo(dx, dy - h); ctx.closePath(); ctx.fillStyle = th.wl; ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,.28)'; ctx.lineWidth = 1; ctx.beginPath();
    for (let r = 1; r < 4; r++) { const o = h * r / 4; ctx.moveTo(dx, dy - o); ctx.lineTo(cxx, cyy - o); const m = r % 2 ? .35 + hv * .2 : .7; const mx = dx + (cxx - dx) * m, my = dy + (cyy - dy) * m; ctx.moveTo(mx, my - o); ctx.lineTo(mx, my - o + h / 4); }
    ctx.stroke();
  }
  if (eastOpen) {
    ctx.beginPath(); ctx.moveTo(bx, by); ctx.lineTo(cxx, cyy); ctx.lineTo(cxx, cyy - h); ctx.lineTo(bx, by - h); ctx.closePath(); ctx.fillStyle = th.wr; ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,.28)'; ctx.lineWidth = 1; ctx.beginPath();
    for (let r = 1; r < 4; r++) { const o = h * r / 4; ctx.moveTo(bx, by - o); ctx.lineTo(cxx, cyy - o); const m = r % 2 ? .4 + hv * .2 : .75; const mx = bx + (cxx - bx) * m, my = by + (cyy - by) * m; ctx.moveTo(mx, my - o); ctx.lineTo(mx, my - o + h / 4); }
    ctx.stroke();
  }
  ctx.beginPath(); ctx.moveTo(ax, ay - h); ctx.lineTo(bx, by - h); ctx.lineTo(cxx, cyy - h); ctx.lineTo(dx, dy - h); ctx.closePath();
  ctx.fillStyle = town ? (hv > .5 ? '#6a3a2a' : '#5e3424') : th.wt; ctx.fill();
  if (town) { ctx.strokeStyle = 'rgba(0,0,0,.25)'; ctx.beginPath(); ctx.moveTo((ax + bx) / 2, (ay + by) / 2 - h); ctx.lineTo((dx + cxx) / 2, (dy + cyy) / 2 - h); ctx.stroke(); }
  ctx.globalAlpha = 1;
}
function drawTree(x, y) {
  const cx = sx(x + .5, y + .5), cy = sy(x + .5, y + .5), hv = hash(x, y), s = (.8 + hv * .5) * Z;
  ctx.fillStyle = 'rgba(0,0,0,.3)'; ctx.beginPath(); ctx.ellipse(cx, cy, 20 * s, 9 * s, 0, 0, 6.3); ctx.fill();
  ctx.fillStyle = '#3a2a1a'; ctx.fillRect(cx - 3 * s, cy - 22 * s, 6 * s, 22 * s);
  const cols = ['#1f2a18', '#26331c', '#2e3d22'];
  for (let k = 0; k < 3; k++) { ctx.fillStyle = cols[k]; ctx.beginPath(); ctx.moveTo(cx, cy - (70 - k * 12) * s); ctx.lineTo(cx + (24 - k * 3) * s, cy - (22 + k * 10) * s); ctx.lineTo(cx - (24 - k * 3) * s, cy - (22 + k * 10) * s); ctx.closePath(); ctx.fill(); }
}

// ----- 角色绘制 -----
function weaponShape(kind, len, col) {
  ctx.lineCap = 'round';
  if (kind === 'staff') { ctx.strokeStyle = '#6a4a2a'; ctx.lineWidth = 2.6 * Z; ctx.beginPath(); ctx.moveTo(0, 6 * Z); ctx.lineTo(0, -len * 1.4); ctx.stroke(); ctx.fillStyle = col || '#8fd0ff'; ctx.beginPath(); ctx.arc(0, -len * 1.4 - 3 * Z, 3.4 * Z, 0, 6.3); ctx.fill(); return; }
  if (kind === 'bow') { ctx.strokeStyle = '#8a6a3a'; ctx.lineWidth = 2 * Z; ctx.beginPath(); ctx.arc(0, -len * .5, len * .6, -1.2, 1.2); ctx.stroke(); ctx.strokeStyle = '#ddd'; ctx.lineWidth = .8; ctx.beginPath(); ctx.moveTo(Math.cos(-1.2) * len * .6, -len * .5 + Math.sin(-1.2) * len * .6); ctx.lineTo(Math.cos(1.2) * len * .6, -len * .5 + Math.sin(1.2) * len * .6); ctx.stroke(); return; }
  ctx.strokeStyle = '#4a3420'; ctx.lineWidth = 2.4 * Z; ctx.beginPath(); ctx.moveTo(0, 3 * Z); ctx.lineTo(0, -len * .35); ctx.stroke();
  if (kind === 'axe') { ctx.strokeStyle = '#5a3a20'; ctx.beginPath(); ctx.moveTo(0, -len * .35); ctx.lineTo(0, -len); ctx.stroke(); ctx.fillStyle = col || '#b8bcc4'; ctx.beginPath(); ctx.moveTo(0, -len * .95); ctx.quadraticCurveTo(9 * Z, -len * .85, 8 * Z, -len * .6); ctx.lineTo(0, -len * .7); ctx.fill(); return; }
  if (kind === 'mace') { ctx.strokeStyle = '#5a3a20'; ctx.beginPath(); ctx.moveTo(0, -len * .35); ctx.lineTo(0, -len * .85); ctx.stroke(); ctx.fillStyle = col || '#8a8f96'; ctx.beginPath(); ctx.arc(0, -len * .92, 4.2 * Z, 0, 6.3); ctx.fill(); return; }
  if (kind === 'cleaver') { ctx.fillStyle = '#9aa0a8'; ctx.fillRect(-1 * Z, -len, 10 * Z, len * .65); ctx.fillStyle = '#6a1a10'; ctx.fillRect(4 * Z, -len * .5, 5 * Z, 4 * Z); return; }
  // 剑类
  ctx.strokeStyle = '#8a6a3a'; ctx.lineWidth = 2 * Z; ctx.beginPath(); ctx.moveTo(-4 * Z, -len * .35); ctx.lineTo(4 * Z, -len * .35); ctx.stroke();
  ctx.strokeStyle = col || '#d8dce4'; ctx.lineWidth = (kind === 'gsword' ? 3.6 : kind === 'dagger' ? 2 : 2.8) * Z;
  ctx.beginPath(); ctx.moveTo(0, -len * .35); ctx.lineTo(0, -len * (kind === 'dagger' ? .7 : 1)); ctx.stroke();
}
function drawMan(px, py, o) {
  const s = (o.s || 1) * Z, fx = Math.cos(o.face) >= 0 ? 1 : -1, back = Math.sin(o.face) < -.25;
  const wl = o.walk || 0, sw = Math.sin(wl) * (o.moving ? 1 : 0), bob = o.moving ? Math.abs(Math.cos(wl)) * 1.5 * s : Math.sin(time * 2) * .6 * s;
  const W_ = c => o.flash ? '#fff2e6' : c;
  ctx.save(); ctx.translate(px, py); ctx.scale(fx, 1);
  // 影子
  ctx.fillStyle = 'rgba(0,0,0,.4)'; ctx.beginPath(); ctx.ellipse(0, 0, 11 * s, 5 * s, 0, 0, 6.3); ctx.fill();
  if (o.float) ctx.translate(0, -6 * s - Math.sin(time * 2) * 2 * s);
  ctx.lineCap = 'round';
  const hy = o.hunch ? 3 * s : 0;
  // 腿
  if (!o.robe) {
    ctx.strokeStyle = W_(o.legs); ctx.lineWidth = (o.thin ? 2.4 : 4.4) * s;
    ctx.beginPath(); ctx.moveTo(-3 * s, -14 * s - bob); ctx.lineTo(-3 * s + sw * 6 * s, 0); ctx.moveTo(3 * s, -14 * s - bob); ctx.lineTo(3 * s - sw * 6 * s, 0); ctx.stroke();
  }
  ctx.translate(0, -bob);
  // 披风
  if (o.cape && !back) { ctx.fillStyle = W_(o.cape); ctx.beginPath(); ctx.moveTo(-6 * s, -30 * s); ctx.lineTo(-11 * s - sw * 2 * s, -6 * s); ctx.lineTo(-2 * s, -8 * s); ctx.closePath(); ctx.fill(); }
  if (o.cape && back) { ctx.fillStyle = W_(o.cape); ctx.beginPath(); ctx.moveTo(-8 * s, -31 * s); ctx.lineTo(8 * s, -31 * s); ctx.lineTo(10 * s, -6 * s); ctx.lineTo(-10 * s, -6 * s); ctx.closePath(); ctx.fill(); }
  // 盾（背面时在后）
  const drawShield = () => { if (!o.shield) return; ctx.fillStyle = W_(o.shield); ctx.strokeStyle = '#2a1a0a'; ctx.lineWidth = 1.2 * s; ctx.beginPath(); ctx.ellipse(-8 * s, -21 * s, 5 * s, 8 * s, 0, 0, 6.3); ctx.fill(); ctx.stroke(); ctx.fillStyle = '#c9a35a'; ctx.beginPath(); ctx.arc(-8 * s, -21 * s, 1.5 * s, 0, 6.3); ctx.fill(); };
  // 武器手臂
  const atk = o.atk || 0; // 0..1
  const ang = atk > 0 ? (-2.2 + atk * 3.6) : (o.armsFwd ? 1.45 : .45 + Math.sin(wl) * .15 * (o.moving ? 1 : 0));
  const drawWeaponArm = () => {
    ctx.save(); ctx.translate(5 * s + hy, -27 * s); ctx.rotate(ang);
    ctx.strokeStyle = W_(o.arm || o.body); ctx.lineWidth = (o.thin ? 2.2 : 3.8) * s; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(0, 11 * s); ctx.stroke();
    if (o.weapon) { ctx.translate(0, 11 * s); ctx.rotate(-1.35); weaponShape(o.weapon, 20 * s * (o.wlen || 1), o.wcol); }
    ctx.restore();
  };
  if (back) { drawWeaponArm(); }
  else drawShield();
  // 躯干
  if (o.robe) {
    ctx.fillStyle = W_(o.body); ctx.beginPath(); ctx.moveTo(-6 * s + hy, -31 * s); ctx.lineTo(6 * s + hy, -31 * s); ctx.lineTo(10 * s, -1 * s); ctx.lineTo(-10 * s, -1 * s); ctx.closePath(); ctx.fill();
    if (o.trim) { ctx.strokeStyle = W_(o.trim); ctx.lineWidth = 1.6 * s; ctx.beginPath(); ctx.moveTo(-10 * s, -2 * s); ctx.lineTo(10 * s, -2 * s); ctx.moveTo(hy, -30 * s); ctx.lineTo(0, -2 * s); ctx.stroke(); }
  } else if (o.thin) {
    ctx.strokeStyle = W_(o.body); ctx.lineWidth = 2 * s; ctx.beginPath(); ctx.moveTo(hy, -32 * s); ctx.lineTo(0, -14 * s); for (let r = 0; r < 3; r++) { ctx.moveTo(-4 * s + hy, (-29 + r * 4) * s); ctx.lineTo(4 * s + hy, (-29 + r * 4) * s); } ctx.stroke();
  } else if (o.fat) {
    ctx.fillStyle = W_(o.body); ctx.beginPath(); ctx.ellipse(0, -20 * s, 12 * s, 13 * s, 0, 0, 6.3); ctx.fill();
    ctx.fillStyle = W_(o.apron || '#5a4a3a'); ctx.fillRect(-8 * s, -22 * s, 16 * s, 16 * s);
    ctx.fillStyle = 'rgba(120,10,5,.8)'; ctx.fillRect(-4 * s, -16 * s, 5 * s, 4 * s); ctx.fillRect(2 * s, -11 * s, 4 * s, 3 * s);
  } else {
    ctx.fillStyle = W_(o.body); ctx.beginPath(); ctx.moveTo(-7 * s + hy, -31 * s); ctx.lineTo(7 * s + hy, -31 * s); ctx.lineTo(6 * s, -13 * s); ctx.lineTo(-6 * s, -13 * s); ctx.closePath(); ctx.fill();
    if (o.belt) { ctx.fillStyle = W_(o.belt); ctx.fillRect(-6 * s, -16 * s, 12 * s, 2.4 * s); }
  }
  // 头
  const hx = hy * 1.4, hyy = o.fat ? -36 * s : -37 * s;
  ctx.fillStyle = W_(o.skin); ctx.beginPath(); ctx.arc(hx, hyy, (o.head || 5.6) * s, 0, 6.3); ctx.fill();
  if (o.skull && !back) { ctx.fillStyle = '#111'; ctx.beginPath(); ctx.arc(hx + 1 * s, hyy - .5 * s, 1.3 * s, 0, 6.3); ctx.arc(hx + 4 * s, hyy - .5 * s, 1.3 * s, 0, 6.3); ctx.fill(); }
  if (o.eyes && !back) { ctx.fillStyle = o.eyes; ctx.beginPath(); ctx.arc(hx + 1.5 * s, hyy - .5 * s, 1.1 * s, 0, 6.3); ctx.arc(hx + 4.2 * s, hyy - .5 * s, 1.1 * s, 0, 6.3); ctx.fill(); }
  if (o.hood) { ctx.fillStyle = W_(o.hood); ctx.beginPath(); ctx.arc(hx, hyy - .5 * s, 6.8 * s, Math.PI * .95, Math.PI * 2.25); ctx.lineTo(hx - 6 * s, hyy + 5 * s); ctx.closePath(); ctx.fill(); }
  if (o.helm) { ctx.fillStyle = W_(o.helm); ctx.beginPath(); ctx.arc(hx, hyy - .5 * s, 6.2 * s, Math.PI, Math.PI * 2); ctx.fill(); ctx.fillRect(hx - 6.2 * s, hyy - 1 * s, 12.4 * s, 2 * s); if (o.plume) { ctx.fillStyle = o.plume; ctx.beginPath(); ctx.moveTo(hx, hyy - 6 * s); ctx.quadraticCurveTo(hx - 8 * s, hyy - 12 * s, hx - 11 * s, hyy - 4 * s); ctx.lineTo(hx - 2 * s, hyy - 5 * s); ctx.fill(); } }
  if (o.horns) { ctx.strokeStyle = '#2a1a10'; ctx.lineWidth = 1.8 * s; ctx.beginPath(); ctx.moveTo(hx - 3 * s, hyy - 4 * s); ctx.quadraticCurveTo(hx - 7 * s, hyy - 9 * s, hx - 5 * s, hyy - 12 * s); ctx.moveTo(hx + 3 * s, hyy - 4 * s); ctx.quadraticCurveTo(hx + 7 * s, hyy - 9 * s, hx + 5 * s, hyy - 12 * s); ctx.stroke(); }
  if (o.crown) { ctx.fillStyle = o.crown; ctx.beginPath(); ctx.moveTo(hx - 5 * s, hyy - 4 * s); ctx.lineTo(hx - 3 * s, hyy - 14 * s); ctx.lineTo(hx, hyy - 7 * s); ctx.lineTo(hx + 3 * s, hyy - 14 * s); ctx.lineTo(hx + 5 * s, hyy - 4 * s); ctx.closePath(); ctx.fill(); }
  if (o.hair) { ctx.fillStyle = o.hair; ctx.beginPath(); ctx.arc(hx - 1 * s, hyy - 1.5 * s, 5.8 * s, Math.PI * .9, Math.PI * 2.05); ctx.fill(); }
  if (o.tail) { ctx.strokeStyle = W_(o.body); ctx.lineWidth = 1.6 * s; ctx.beginPath(); ctx.moveTo(-5 * s, -15 * s); ctx.quadraticCurveTo(-14 * s, -12 * s + Math.sin(time * 6) * 3 * s, -12 * s, -22 * s); ctx.stroke(); }
  if (!back) drawWeaponArm(); else drawShield();
  if (o.armsFwd) { ctx.strokeStyle = W_(o.arm || o.skin); ctx.lineWidth = 3.4 * s; ctx.beginPath(); ctx.moveTo(-3 * s + hy, -27 * s); ctx.lineTo(9 * s + hy, -24 * s + Math.sin(time * 3) * s); ctx.stroke(); }
  if (o.aura) { ctx.globalCompositeOperation = 'lighter'; const g = ctx.createRadialGradient(0, -20 * s, 2, 0, -20 * s, 26 * s); g.addColorStop(0, o.aura); g.addColorStop(1, 'rgba(0,0,0,0)'); ctx.fillStyle = g; ctx.fillRect(-26 * s, -46 * s, 52 * s, 52 * s); ctx.globalCompositeOperation = 'source-over'; }
  ctx.restore();
}
function drawHound(px, py, o) {
  const s = (o.s || 1) * Z, fx = Math.cos(o.face) >= 0 ? 1 : -1, wl = o.walk || 0, mv = o.moving ? 1 : 0, W_ = c => o.flash ? '#fff2e6' : c;
  ctx.save(); ctx.translate(px, py); ctx.scale(fx, 1);
  ctx.fillStyle = 'rgba(0,0,0,.4)'; ctx.beginPath(); ctx.ellipse(0, 0, 15 * s, 5 * s, 0, 0, 6.3); ctx.fill();
  ctx.strokeStyle = W_('#2a1410'); ctx.lineWidth = 3 * s; ctx.lineCap = 'round'; ctx.beginPath();
  for (const [lx0, ph] of [[-8, 0], [-5, 3.1], [6, 1.5], [9, 4.6]]) { ctx.moveTo(lx0 * s, -10 * s); ctx.lineTo(lx0 * s + Math.sin(wl + ph) * 4 * s * mv, 0); }
  ctx.stroke();
  ctx.fillStyle = W_('#4a1c14'); ctx.beginPath(); ctx.ellipse(0, -13 * s, 13 * s, 6 * s, -.08, 0, 6.3); ctx.fill();
  ctx.beginPath(); ctx.ellipse(13 * s, -18 * s, 6 * s, 4.4 * s, .3, 0, 6.3); ctx.fill();
  ctx.fillStyle = '#ffb020'; ctx.beginPath(); ctx.arc(15 * s, -19.5 * s, 1.3 * s, 0, 6.3); ctx.fill();
  ctx.globalCompositeOperation = 'lighter'; ctx.fillStyle = `rgba(255,${90 + Math.sin(time * 9) * 40 | 0},20,.5)`;
  for (let i = 0; i < 4; i++) { ctx.beginPath(); ctx.arc((-8 + i * 5) * s, (-19 - Math.abs(Math.sin(time * 7 + i)) * 4) * s, 2.4 * s, 0, 6.3); ctx.fill(); }
  ctx.globalCompositeOperation = 'source-over';
  ctx.restore();
}
function lookOf(e) {
  const L = e.d.look, base = { face: e.face, walk: e.walk, moving: e.moving, flash: e.hit > 0, atk: e.atkT > 0 ? 1 - e.atkT / e.atkDur : 0, s: (e.d.size || 1) };
  if (e.champ) base.aura = 'rgba(90,110,255,.35)';
  switch (L) {
    case 'zombie': return Object.assign(base, { body: '#4d5a36', legs: '#2e2a20', skin: '#7f906a', hunch: true, armsFwd: true, arm: '#7f906a', eyes: '#c8e060' });
    case 'skel': return Object.assign(base, { thin: true, body: '#d8d2bf', legs: '#d8d2bf', skin: '#e2dccb', arm: '#d8d2bf', skull: true, weapon: 'sword', wcol: '#8a8a80' });
    case 'archer': return Object.assign(base, { thin: true, body: '#cfc8b2', legs: '#cfc8b2', skin: '#dcd5c2', arm: '#cfc8b2', skull: true, weapon: 'bow', hood: '#3a3028' });
    case 'imp': return Object.assign(base, { body: '#a8321e', legs: '#6a1a10', skin: '#c4442a', horns: true, tail: true, eyes: '#ffd040', arm: '#c4442a' });
    case 'ghoul': return Object.assign(base, { body: '#8a8a7a', legs: '#4a4a3a', skin: '#a8a898', hunch: true, armsFwd: true, arm: '#a8a898', eyes: '#ff4020' });
    case 'cultist': return Object.assign(base, { robe: true, body: '#3a1e4e', trim: '#8a5ab8', skin: '#b89a8a', hood: '#2a1438', weapon: 'staff', wcol: '#c070ff', eyes: '#e090ff' });
    case 'knight': return Object.assign(base, { body: '#2c2c36', legs: '#1e1e26', skin: '#2c2c36', helm: '#3a3a46', eyes: '#ff3020', weapon: 'gsword', wcol: '#8a8a9a', wlen: 1.2, cape: '#5a0e0a', shield: '#2a2a33' });
    case 'mog': return Object.assign(base, { fat: true, body: '#9a6a5a', legs: '#4a3028', skin: '#a87a6a', apron: '#6a5a48', weapon: 'cleaver', wlen: 1.2, head: 6.4, eyes: '#ff3010', aura: e.enraged ? 'rgba(255,40,20,.35)' : base.aura });
    case 'abbot': return Object.assign(base, { robe: true, float: true, body: e.phase === 2 ? '#4a0e08' : '#6a1a14', trim: '#d8a040', skin: '#c8a08a', crown: e.phase === 2 ? '#ff8a2a' : '#d8a040', weapon: 'staff', wcol: '#ff7a2a', wlen: 1.3, eyes: e.phase === 2 ? '#ffb020' : null, aura: e.phase === 2 ? 'rgba(255,110,30,.45)' : 'rgba(255,120,40,.18)' });
  }
  return base;
}
function heroLook() {
  const eq = hero.eq, bw = eq.weapon ? BASES[eq.weapon.b] : null, bb = eq.body ? BASES[eq.body.b] : null;
  const tint = it => it ? ['#b8bcc4', '#8a9aff', '#e8c860', '#f09a50'][it.r] : null;
  return {
    face: P.face, walk: P.walk, moving: !!(P.path || P.target || keys.w || keys.a || keys.s || keys.d || keys.arrowup || keys.arrowdown || keys.arrowleft || keys.arrowright || (mouse.down && mouse.mode === 'move')) && P.atkT <= 0,
    flash: P.flash > 0, atk: P.atkT > 0 ? 1 - P.atkT / P.atkDur : P.casting > 0 ? .9 : 0, s: 1,
    body: bb ? bb.col : '#5a4a38', legs: '#2a2018', skin: '#d0a888', belt: '#3a2614', cape: '#6a1410', hair: eq.helm ? null : '#2a1a10',
    helm: eq.helm ? (eq.helm.b === 'cap' ? '#6a4a2a' : '#8a8f96') : null, plume: eq.helm && eq.helm.r >= 2 ? '#a01a10' : null,
    weapon: bw ? bw.w : null, wcol: tint(eq.weapon), shield: eq.off ? (eq.off.b === 'buckler' ? '#6a4a2a' : '#7a7f86') : null
  };
}
function drawNpc(n) {
  const px = sx(n.x, n.y), py = sy(n.x, n.y);
  const L = { priest: { robe: true, body: '#d8d0c0', trim: '#c9a35a', skin: '#d8b8a0', hood: '#e8e0d0', weapon: 'staff', wcol: '#ffe08a' }, smith: { body: '#5a3a24', legs: '#2a2018', skin: '#c89878', belt: '#1a120a', apron: '#3a2a1a', weapon: 'mace', hair: '#6a4a2a', s: 1.1 }, alch: { robe: true, body: '#2a4a3a', trim: '#8ad0a0', skin: '#e0b8a0', hair: '#8a2a1a' }, boy: { body: '#6a5a3a', legs: '#3a2a1a', skin: '#e0b898', hair: '#4a3020', s: .8 } }[n.look];
  drawMan(px, py, Object.assign({ face: n.face, walk: 0, moving: false }, L));
  ctx.font = `bold ${Math.round(12 * Math.max(Z, .85))}px sans-serif`; ctx.textAlign = 'center';
  const ty = py - 52 * Z * (L.s || 1);
  ctx.fillStyle = 'rgba(0,0,0,.6)'; const tw = ctx.measureText(n.n).width + 10; ctx.fillRect(px - tw / 2, ty - 12, tw, 16);
  ctx.fillStyle = hover && hover.obj === n ? '#ffe08a' : '#c9a35a'; ctx.fillText(n.n, px, ty);
  const mark = npcMark(n); if (mark) { ctx.fillStyle = '#ffd24a'; ctx.font = `bold ${Math.round(18 * Math.max(Z, .85))}px sans-serif`; ctx.fillText(mark, px, ty - 16 - Math.abs(Math.sin(time * 3)) * 4); }
}
function drawProp(p) {
  const px = sx(p.x, p.y), py = sy(p.x, p.y), hl = hover && hover.obj === p;
  if (p.type === 'torch') {
    const ox = p.face === 'L' ? sx(p.x, p.y + .5) : sx(p.x + .5, p.y), oy = (p.face === 'L' ? sy(p.x, p.y + .5) : sy(p.x + .5, p.y)) - 26 * Z;
    ctx.fillStyle = '#3a2a1a'; ctx.fillRect(ox - 1.5 * Z, oy, 3 * Z, 9 * Z);
    const fl = 1 + Math.sin(time * 13 + p.x * 7) * .15 + Math.sin(time * 7 + p.y) * .1;
    ctx.fillStyle = '#ff7a20'; ctx.beginPath(); ctx.ellipse(ox, oy - 3 * Z * fl, 3.4 * Z, 6 * Z * fl, 0, 0, 6.3); ctx.fill();
    ctx.fillStyle = '#ffe08a'; ctx.beginPath(); ctx.ellipse(ox, oy - 1.5 * Z, 1.6 * Z, 3 * Z * fl, 0, 0, 6.3); ctx.fill();
    return;
  }
  ctx.save(); ctx.translate(px, py);
  const z = Z;
  if (p.type === 'barrel') {
    ctx.fillStyle = 'rgba(0,0,0,.35)'; ctx.beginPath(); ctx.ellipse(0, 0, 10 * z, 5 * z, 0, 0, 6.3); ctx.fill();
    ctx.fillStyle = hl ? '#9a6a3a' : '#7a5230'; ctx.fillRect(-8 * z, -22 * z, 16 * z, 22 * z);
    ctx.fillStyle = '#5a3a20'; ctx.beginPath(); ctx.ellipse(0, -22 * z, 8 * z, 3.5 * z, 0, 0, 6.3); ctx.fill();
    ctx.fillStyle = '#3a3a3a'; ctx.fillRect(-8 * z, -18 * z, 16 * z, 2 * z); ctx.fillRect(-8 * z, -6 * z, 16 * z, 2 * z);
  } else if (p.type === 'chest') {
    ctx.fillStyle = 'rgba(0,0,0,.35)'; ctx.beginPath(); ctx.ellipse(0, 0, 14 * z, 6 * z, 0, 0, 6.3); ctx.fill();
    ctx.fillStyle = hl ? '#8a5a2a' : '#6a4220'; ctx.fillRect(-12 * z, -14 * z, 24 * z, 14 * z);
    ctx.fillStyle = p.open ? '#1a0e06' : '#7a4a22'; ctx.beginPath(); ctx.moveTo(-12 * z, -14 * z); ctx.quadraticCurveTo(0, p.open ? -30 * z : -22 * z, 12 * z, -14 * z); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#c9a35a'; ctx.fillRect(-12 * z, -9 * z, 24 * z, 2 * z); ctx.fillRect(-2 * z, -12 * z, 4 * z, 5 * z);
  } else if (p.type === 'shrine') {
    ctx.fillStyle = 'rgba(0,0,0,.35)'; ctx.beginPath(); ctx.ellipse(0, 0, 14 * z, 6 * z, 0, 0, 6.3); ctx.fill();
    ctx.fillStyle = '#4a4540'; ctx.fillRect(-10 * z, -8 * z, 20 * z, 8 * z); ctx.fillStyle = '#5e5850'; ctx.fillRect(-6 * z, -34 * z, 12 * z, 26 * z);
    ctx.fillStyle = p.used ? '#333' : `rgba(110,200,255,${.6 + .4 * Math.sin(time * 3)})`; ctx.beginPath(); ctx.arc(0, -38 * z, 5 * z, 0, 6.3); ctx.fill();
  } else if (p.type === 'wp') {
    ctx.fillStyle = 'rgba(0,0,0,.35)'; ctx.beginPath(); ctx.ellipse(0, 0, 18 * z, 8 * z, 0, 0, 6.3); ctx.fill();
    ctx.fillStyle = '#5a5650'; ctx.beginPath(); ctx.ellipse(0, -4 * z, 16 * z, 7 * z, 0, 0, 6.3); ctx.fill();
    ctx.fillStyle = `rgba(120,200,255,${.5 + .3 * Math.sin(time * 2)})`; ctx.beginPath(); ctx.ellipse(0, -5 * z, 11 * z, 4.6 * z, 0, 0, 6.3); ctx.fill();
    ctx.fillStyle = '#6a665e'; ctx.fillRect(-3 * z, -40 * z, 6 * z, 34 * z);
  } else if (p.type === 'portal') {
    ctx.globalCompositeOperation = 'lighter';
    const g = ctx.createRadialGradient(0, -24 * z, 2, 0, -24 * z, 24 * z); g.addColorStop(0, 'rgba(180,230,255,.95)'); g.addColorStop(.5, 'rgba(60,140,255,.55)'); g.addColorStop(1, 'rgba(20,40,160,0)');
    ctx.fillStyle = g; ctx.beginPath(); ctx.ellipse(0, -24 * z, 13 * z, 24 * z, 0, 0, 6.3); ctx.fill();
    ctx.strokeStyle = 'rgba(160,220,255,.8)'; ctx.lineWidth = 2 * z; ctx.beginPath(); ctx.ellipse(0, -24 * z, 11 * z + Math.sin(time * 5) * z, 22 * z, 0, 0, 6.3); ctx.stroke();
    ctx.globalCompositeOperation = 'source-over';
  } else if (p.type === 'fire') {
    ctx.fillStyle = '#2a2420'; for (let i = 0; i < 6; i++) { const a = i / 6 * 6.28; ctx.beginPath(); ctx.arc(Math.cos(a) * 11 * z, Math.sin(a) * 5 * z, 3.5 * z, 0, 6.3); ctx.fill(); }
    ctx.globalCompositeOperation = 'lighter';
    for (let i = 0; i < 5; i++) { const fl = Math.sin(time * 10 + i * 2); ctx.fillStyle = i % 2 ? 'rgba(255,120,30,.7)' : 'rgba(255,200,80,.6)'; ctx.beginPath(); ctx.ellipse((i - 2) * 3 * z, -8 * z - fl * 2 * z, 4 * z, (10 + fl * 4) * z, 0, 0, 6.3); ctx.fill(); }
    ctx.globalCompositeOperation = 'source-over';
  } else if (p.type === 'well') {
    ctx.fillStyle = '#5a5650'; ctx.beginPath(); ctx.ellipse(0, -6 * z, 16 * z, 8 * z, 0, 0, 6.3); ctx.fill(); ctx.fillStyle = '#10181e'; ctx.beginPath(); ctx.ellipse(0, -8 * z, 11 * z, 5 * z, 0, 0, 6.3); ctx.fill();
    ctx.strokeStyle = '#4a3420'; ctx.lineWidth = 3 * z; ctx.beginPath(); ctx.moveTo(-14 * z, -6 * z); ctx.lineTo(-14 * z, -38 * z); ctx.lineTo(14 * z, -38 * z); ctx.lineTo(14 * z, -6 * z); ctx.stroke();
  } else if (p.type === 'anvil') {
    ctx.fillStyle = '#2a2a2e'; ctx.fillRect(-6 * z, -10 * z, 12 * z, 10 * z); ctx.fillStyle = '#3a3a40'; ctx.fillRect(-12 * z, -16 * z, 22 * z, 6 * z);
  }
  ctx.restore();
}
function drawCorpse(c) {
  const px = sx(c.x, c.y), py = sy(c.x, c.y), s = c.size * Z;
  ctx.fillStyle = 'rgba(70,6,4,.55)'; ctx.beginPath(); ctx.ellipse(px, py, 13 * s, 5.5 * s, 0, 0, 6.3); ctx.fill();
  const col = { zombie: '#3d4a2a', skel: '#b8b2a0', archer: '#b0aa98', imp: '#7a2a18', ghoul: '#6a6a5a', cultist: '#2a1438', hound: '#3a1610', knight: '#22222a', mog: '#7a4a3a', abbot: '#4a0e08' }[c.look] || '#444';
  ctx.fillStyle = col; ctx.beginPath(); ctx.ellipse(px + 2 * s, py - 2 * s, 11 * s, 4 * s, .15, 0, 6.3); ctx.fill();
  ctx.beginPath(); ctx.arc(px - 10 * s, py - 3 * s, 4 * s, 0, 6.3); ctx.fill();
}
function drawProjectile(p) {
  const px = sx(p.x, p.y), py = sy(p.x, p.y) - 16 * Z;
  ctx.globalCompositeOperation = 'lighter';
  if (p.kind === 'fire') { const g = ctx.createRadialGradient(px, py, 1, px, py, 12 * Z); g.addColorStop(0, 'rgba(255,240,180,1)'); g.addColorStop(.4, 'rgba(255,140,40,.9)'); g.addColorStop(1, 'rgba(255,60,0,0)'); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(px, py, 12 * Z, 0, 6.3); ctx.fill(); }
  else if (p.kind === 'bolt') { const g = ctx.createRadialGradient(px, py, 1, px, py, 9 * Z); g.addColorStop(0, 'rgba(255,220,255,1)'); g.addColorStop(.5, p.src && p.src.d.boss ? 'rgba(255,110,30,.9)' : 'rgba(180,80,255,.9)'); g.addColorStop(1, 'rgba(80,0,160,0)'); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(px, py, 9 * Z, 0, 6.3); ctx.fill(); }
  ctx.globalCompositeOperation = 'source-over';
  if (p.kind === 'arrow') { const a = Math.atan2((p.vx + p.vy) * .5, p.vx - p.vy); ctx.save(); ctx.translate(px, py); ctx.rotate(a); ctx.strokeStyle = '#d8c8a0'; ctx.lineWidth = 1.6 * Z; ctx.beginPath(); ctx.moveTo(-9 * Z, 0); ctx.lineTo(7 * Z, 0); ctx.stroke(); ctx.fillStyle = '#aaa'; ctx.beginPath(); ctx.moveTo(9 * Z, 0); ctx.lineTo(5 * Z, -2.5 * Z); ctx.lineTo(5 * Z, 2.5 * Z); ctx.fill(); ctx.restore(); }
}
function drawGroundItem(gi, labels) {
  const px = sx(gi.x, gi.y), py = sy(gi.x, gi.y), it = gi.it;
  gi.t += 1 / 60;
  const drop = Math.max(0, 1 - gi.t * 3) * 20 * Z;
  let col = ['#e9e3d6', '#8a9aff', '#f3d34a', '#e8843a'][it.r || 0];
  if (it.gold) { ctx.fillStyle = '#e8c050'; for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.ellipse(px + (i - 1) * 4 * Z, py - 2 * Z - drop - i, 3.4 * Z, 1.8 * Z, 0, 0, 6.3); ctx.fill(); } col = '#c9a35a'; }
  else if (it.pot) { ctx.fillStyle = it.pot === 'hp' ? '#d0301a' : it.pot === 'mp' ? '#2a5ad0' : '#d8c8a0'; ctx.beginPath(); ctx.arc(px, py - 4 * Z - drop, 4 * Z, 0, 6.3); ctx.fill(); }
  else {
    ctx.save(); ctx.translate(px, py - 3 * Z - drop); ctx.rotate(.9); ctx.fillStyle = col; ctx.fillRect(-7 * Z, -2 * Z, 14 * Z, 4 * Z); ctx.restore();
    if (it.r >= 2) { ctx.globalCompositeOperation = 'lighter'; const g = ctx.createRadialGradient(px, py - 4 * Z, 1, px, py - 4 * Z, 18 * Z); g.addColorStop(0, it.r === 3 ? 'rgba(232,132,58,.6)' : 'rgba(243,211,74,.45)'); g.addColorStop(1, 'rgba(0,0,0,0)'); ctx.fillStyle = g; ctx.fillRect(px - 18 * Z, py - 22 * Z, 36 * Z, 36 * Z); ctx.globalCompositeOperation = 'source-over'; }
  }
  labels.push({ gi, x: px, y: py - 10 * Z, txt: it.gold ? `${it.gold} 金币` : it.n, col });
}
function drawLabels(labels) {
  const fs = Math.round(clamp(12 * Z, 11, 13));
  ctx.font = `${fs}px sans-serif`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  const placed = [];
  labelRects = [];
  for (const l of labels) {
    const w = ctx.measureText(l.txt).width + 10, h = fs + 6;
    let x = l.x - w / 2, y = l.y - h;
    for (let k = 0; k < 8; k++) { if (!placed.some(r => x < r.x + r.w && x + w > r.x && y < r.y + r.h && y + h > r.y)) break; y -= h + 1; }
    placed.push({ x, y, w, h });
    const hl = hover && hover.obj === l.gi;
    ctx.fillStyle = hl ? 'rgba(60,40,20,.92)' : 'rgba(0,0,0,.72)'; ctx.fillRect(x, y, w, h);
    if (hl) { ctx.strokeStyle = '#c9a35a'; ctx.lineWidth = 1; ctx.strokeRect(x + .5, y + .5, w - 1, h - 1); }
    ctx.fillStyle = l.col; ctx.fillText(l.txt, x + w / 2, y + h / 2 + 1);
    labelRects.push({ x, y, w, h, gi: l.gi });
  }
  ctx.textBaseline = 'alphabetic';
}
let labelRects = [];

function render() {
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  ctx.fillStyle = '#050304'; ctx.fillRect(0, 0, W, H);
  if (!M || !P) return;
  const shx = shake > 0 && !REDUCED ? (rand() - .5) * shake : 0, shy = shake > 0 && !REDUCED ? (rand() - .5) * shake : 0;
  camX = W / 2 - (P.x - P.y) * TW / 2 * Z + shx; camY = H * .46 - (P.x + P.y) * TH / 2 * Z + shy;
  const town = M.theme === 'town';
  // 可见范围
  const [ax] = s2w(0, 0), [bx, by] = s2w(W, 0), [cx0, cy0] = s2w(0, H), [dx0, dy0] = s2w(W, H + 80 * Z);
  const [ax2, ay2] = s2w(0, -80 * Z);
  const x0 = Math.max(0, Math.floor(Math.min(ax, cx0, ax2)) - 2), x1 = Math.min(M.w - 1, Math.ceil(Math.max(bx, dx0)) + 2);
  const y0 = Math.max(0, Math.floor(Math.min(by, ay2)) - 2), y1 = Math.min(M.h - 1, Math.ceil(Math.max(cy0, dy0)) + 2);
  // 1. 地面
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
    const i = y * M.w + x; if (!M.seen[i]) continue; const t = M.t[i];
    if (walkT(t) || t === T_TREE && town) drawFloor(x, y, i);
  }
  // 已探索未可见区域压暗
  if (!town) {
    ctx.fillStyle = 'rgba(0,0,0,.5)';
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) { const i = y * M.w + x; if (M.seen[i] && !M.vis[i] && walkT(M.t[i])) diamond(x, y, 'rgba(0,0,0,.5)'); }
  }
  // 2. 平面物：尸体、地上物品、特效地面层
  for (const c of M.corpses) if (town || M.seen[Math.floor(c.y) * M.w + Math.floor(c.x)]) drawCorpse(c);
  const labels = [];
  for (const gi of M.items) if (town || M.vis[Math.floor(gi.y) * M.w + Math.floor(gi.x)] || M.seen[Math.floor(gi.y) * M.w + Math.floor(gi.x)]) drawGroundItem(gi, labels);
  for (const f of M.fx) {
    if (f.type === 'nova') { const k = 1 - f.t / .5, r = 4 * k; ctx.strokeStyle = `rgba(150,220,255,${1 - k})`; ctx.lineWidth = 6 * Z; ctx.beginPath(); ctx.ellipse(sx(f.x, f.y), sy(f.x, f.y), r * TW / 2 * Z * 1.41, r * TH / 2 * Z * 1.41, 0, 0, 6.3); ctx.stroke(); }
    else if (f.type === 'whirl') { const k = 1 - f.t / .35; ctx.strokeStyle = `rgba(230,220,200,${.8 - k * .8})`; ctx.lineWidth = 4 * Z; ctx.beginPath(); ctx.ellipse(sx(f.x, f.y), sy(f.x, f.y) - 12 * Z, 1.9 * TW / 2 * Z * 1.3, 1.9 * TH / 2 * Z * 1.3, 0, k * 6, k * 6 + 4.5); ctx.stroke(); }
    else if (f.type === 'ring') { ctx.strokeStyle = f.col; ctx.lineWidth = 5 * Z; ctx.globalAlpha = .8; ctx.beginPath(); ctx.ellipse(sx(f.x, f.y), sy(f.x, f.y), f.rad * TW / 2 * Z * 1.41, f.rad * TH / 2 * Z * 1.41, 0, 0, 6.3); ctx.stroke(); ctx.globalAlpha = 1; }
    else if (f.type === 'lvl') { const k = 1 - f.t / 1.4; ctx.strokeStyle = f.col ? f.col : `rgba(255,210,90,${1 - k})`; ctx.globalAlpha = 1 - k; ctx.lineWidth = 3 * Z; for (let j = 0; j < 3; j++) { ctx.beginPath(); ctx.ellipse(sx(f.x, f.y), sy(f.x, f.y) - (k * 50 + j * 12) * Z, 16 * Z, 7 * Z, 0, 0, 6.3); ctx.stroke(); } ctx.globalAlpha = 1; }
  }
  // 3. 需要深度排序的物体
  const dl = [];
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
    const i = y * M.w + x, t = M.t[i];
    if (!M.seen[i]) continue;
    if (t === T_WALL) dl.push({ d: x + y + 1, k: 0, x, y });
    else if (t === T_TREE) dl.push({ d: x + y + 1, k: 5, x, y });
  }
  for (const p of M.props) if (town || M.seen[Math.floor(p.y) * M.w + Math.floor(p.x)]) dl.push({ d: p.wall ? p.x + p.y + .05 : p.x + p.y, k: 1, o: p });
  for (const e of M.mons) if (town || M.vis[Math.floor(e.y) * M.w + Math.floor(e.x)]) dl.push({ d: e.x + e.y, k: 2, o: e });
  for (const n of M.npcs) dl.push({ d: n.x + n.y, k: 3, o: n });
  dl.push({ d: P.x + P.y, k: 4 });
  for (const p of M.proj) dl.push({ d: p.x + p.y, k: 6, o: p });
  dl.sort((a, b) => a.d - b.d);
  const pd = P.x + P.y, psx = sx(P.x, P.y);
  for (const o of dl) {
    if (o.k === 0) {
      let al = 1;
      { const wx = sx(o.x + .5, o.y + .5); if (o.d > pd + .2 && o.d - pd < 4.5 && Math.abs(wx - psx) < TW * 1.3 * Z) al = .32; }
      drawWall(o.x, o.y, al);
    } else if (o.k === 5) drawTree(o.x, o.y);
    else if (o.k === 1) drawProp(o.o);
    else if (o.k === 2) { const e = o.o; e.moving = e.lastX !== undefined && (Math.abs(e.lastX - e.x) + Math.abs(e.lastY - e.y) > .001); e.lastX = e.x; e.lastY = e.y; const L = lookOf(e); if (e.d.look === 'hound') drawHound(sx(e.x, e.y), sy(e.x, e.y), L); else drawMan(sx(e.x, e.y), sy(e.x, e.y), L); if (e.slow > 0) { ctx.fillStyle = 'rgba(120,200,255,.25)'; ctx.beginPath(); ctx.ellipse(sx(e.x, e.y), sy(e.x, e.y) - 18 * Z * (e.d.size || 1), 10 * Z, 20 * Z * (e.d.size || 1), 0, 0, 6.3); ctx.fill(); } }
    else if (o.k === 3) drawNpc(o.o);
    else if (o.k === 4) drawMan(sx(P.x, P.y), sy(P.x, P.y), heroLook());
    else if (o.k === 6) drawProjectile(o.o);
  }
  // 4. 粒子与爆炸
  ctx.globalCompositeOperation = 'lighter';
  for (const f of M.fx) {
    if (f.type === 'p') { ctx.fillStyle = f.col; ctx.globalAlpha = clamp(f.t * 2, 0, 1); ctx.fillRect(sx(f.x, f.y) - f.sz * Z / 2, sy(f.x, f.y) - f.z * Z - f.sz * Z / 2, f.sz * Z, f.sz * Z); }
    else if (f.type === 'boom') { const k = 1 - f.t / .35, px = sx(f.x, f.y), py = sy(f.x, f.y) - 12 * Z, r = (12 + k * 40) * Z; const g = ctx.createRadialGradient(px, py, 1, px, py, r); g.addColorStop(0, `rgba(255,220,140,${1 - k})`); g.addColorStop(1, 'rgba(255,60,0,0)'); ctx.fillStyle = g; ctx.globalAlpha = 1; ctx.beginPath(); ctx.arc(px, py, r, 0, 6.3); ctx.fill(); }
  }
  ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over';
  // 5. 光照
  drawLighting(town);
  // 6. 地面物品标签、飘字（在光照之上，保证可读）
  drawLabels(labels);
  ctx.textAlign = 'center';
  for (const f of M.fx) if (f.type === 'txt') {
    const k = 1 - f.t / 1.1; ctx.globalAlpha = clamp(f.t * 2, 0, 1);
    ctx.font = `bold ${Math.round((f.big ? 20 : 14) * Math.max(Z, .8))}px sans-serif`;
    ctx.fillStyle = '#000'; ctx.fillText(f.txt, sx(f.x, f.y) + 1, sy(f.x, f.y) - (40 + k * 30) * Z + 1);
    ctx.fillStyle = f.col; ctx.fillText(f.txt, sx(f.x, f.y), sy(f.x, f.y) - (40 + k * 30) * Z);
  }
  ctx.globalAlpha = 1;
  // 血量过低时屏幕边缘泛红
  if (hero.hp < S.maxHp * .3) { const g = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * .3, W / 2, H / 2, Math.max(W, H) * .7); g.addColorStop(0, 'rgba(120,0,0,0)'); g.addColorStop(1, `rgba(140,0,0,${.25 + .15 * Math.sin(time * 5)})`); ctx.fillStyle = g; ctx.fillRect(0, 0, W, H); }
  drawMinimap();
}
function drawLighting(town) {
  const th = THEMES[M.theme];
  lx.globalCompositeOperation = 'source-over'; lx.clearRect(0, 0, lc.width, lc.height);
  lx.fillStyle = `rgba(4,2,2,${th.dark})`; lx.fillRect(0, 0, lc.width, lc.height);
  lx.globalCompositeOperation = 'destination-out';
  const L = (x, y, r, a) => { const px = sx(x, y) * LS, py = (sy(x, y) - 16 * Z) * LS, rr = r * TW * .5 * Z * LS * 1.3; if (px < -rr || py < -rr || px > lc.width + rr || py > lc.height + rr) return; const g = lx.createRadialGradient(px, py, 0, px, py, rr); g.addColorStop(0, `rgba(0,0,0,${a})`); g.addColorStop(.55, `rgba(0,0,0,${a * .75})`); g.addColorStop(1, 'rgba(0,0,0,0)'); lx.fillStyle = g; lx.fillRect(px - rr, py - rr, rr * 2, rr * 2); };
  const fl = 1 + Math.sin(time * 9) * .03;
  L(P.x, P.y, (town ? 11 : S.light) * fl, 1);
  const glows = [];
  for (const p of M.props) {
    if (p.type === 'torch') { const f = 1 + Math.sin(time * 11 + p.x * 3) * .06; L(p.x, p.y, 3.4 * f, .85); glows.push([p.x, p.y, 3, 'rgba(255,120,40,.10)']); }
    else if (p.type === 'fire') { L(p.x, p.y, 6 * fl, 1); glows.push([p.x, p.y, 5, 'rgba(255,120,40,.14)']); }
    else if (p.type === 'portal') { L(p.x, p.y, 3, .9); glows.push([p.x, p.y, 3, 'rgba(60,140,255,.14)']); }
    else if (p.type === 'shrine' && !p.used) L(p.x, p.y, 2.2, .7);
    else if (p.type === 'wp') L(p.x, p.y, 2.5, .7);
  }
  for (const p of M.proj) if (p.kind !== 'arrow') { L(p.x, p.y, 2.4, .9); glows.push([p.x, p.y, 2, p.kind === 'fire' ? 'rgba(255,120,30,.18)' : 'rgba(170,80,255,.14)']); }
  for (const f of M.fx) { if (f.type === 'boom') L(f.x, f.y, 4, 1); else if (f.type === 'ring') L(f.x, f.y, f.rad + 1, .5); }
  for (const e of M.mons) if (e.d.look === 'abbot' || e.d.look === 'hound') L(e.x, e.y, 2.5, .6);
  lx.globalCompositeOperation = 'source-over';
  ctx.drawImage(lc, 0, 0, W, H);
  ctx.globalCompositeOperation = 'lighter';
  for (const [x, y, r, c] of glows) { const px = sx(x, y), py = sy(x, y) - 16 * Z, rr = r * TW * .5 * Z; if (px < -rr || py < -rr || px > W + rr || py > H + rr) continue; const g = ctx.createRadialGradient(px, py, 0, px, py, rr); g.addColorStop(0, c); g.addColorStop(1, 'rgba(0,0,0,0)'); ctx.fillStyle = g; ctx.fillRect(px - rr, py - rr, rr * 2, rr * 2); }
  ctx.globalCompositeOperation = 'source-over';
}
function drawMinimap() {
  const big = bigMap, sc = big ? clamp(Math.min(W, H) / 90, 3, 6) : (W < 640 ? 1.6 : 2.2);
  const bw = big ? W : (W < 640 ? 110 : 160), bh = big ? H : (W < 640 ? 80 : 110);
  const ox = big ? 0 : W - bw - 10, oy = big ? 0 : (W < 640 ? 88 : 52);
  ctx.save();
  if (big) { ctx.fillStyle = 'rgba(0,0,0,.55)'; ctx.fillRect(0, 0, W, H); }
  else { ctx.fillStyle = 'rgba(0,0,0,.5)'; ctx.fillRect(ox, oy, bw, bh); ctx.strokeStyle = 'rgba(201,163,90,.35)'; ctx.strokeRect(ox + .5, oy + .5, bw - 1, bh - 1); }
  ctx.beginPath(); ctx.rect(ox, oy, bw, bh); ctx.clip();
  const cx = ox + bw / 2, cy = oy + bh / 2;
  const mp = (x, y) => [cx + (x - y - (P.x - P.y)) * sc, cy + (x + y - (P.x + P.y)) * sc * .5];
  for (let y = 0; y < M.h; y++) for (let x = 0; x < M.w; x++) {
    const i = y * M.w + x; if (!M.seen[i]) continue; const t = M.t[i];
    if (t === T_WALL || (t === T_TREE && M.theme !== 'town')) { const [px, py] = mp(x + .5, y + .5); ctx.fillStyle = big ? 'rgba(200,170,120,.8)' : 'rgba(200,170,120,.7)'; ctx.fillRect(px - sc * .5, py - sc * .25, sc, sc * .5); }
    else if (t === T_DOWN || t === T_UP) { const [px, py] = mp(x + .5, y + .5); ctx.fillStyle = '#ffd24a'; ctx.fillRect(px - 2, py - 2, 4, 4); }
  }
  for (const p of M.props) if (p.type === 'portal' || p.type === 'wp') { const [px, py] = mp(p.x, p.y); ctx.fillStyle = '#6ac8ff'; ctx.fillRect(px - 2, py - 2, 4, 4); }
  for (const n of M.npcs) { const [px, py] = mp(n.x, n.y); ctx.fillStyle = '#c9a35a'; ctx.fillRect(px - 2, py - 2, 4, 4); }
  for (const e of M.mons) if (M.vis[Math.floor(e.y) * M.w + Math.floor(e.x)]) { const [px, py] = mp(e.x, e.y); ctx.fillStyle = e.d.boss ? '#ff8a2a' : '#e0402a'; ctx.fillRect(px - 1.5, py - 1.5, 3, 3); }
  const [px, py] = mp(P.x, P.y); ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(px, py, big ? 4 : 2.5, 0, 6.3); ctx.fill();
  ctx.restore();
  if (big) { ctx.fillStyle = '#c9a35a'; ctx.font = '14px sans-serif'; ctx.textAlign = 'center'; ctx.fillText(`${floorName(M.floor)} · 自动地图（按 Tab 或点「地图」关闭）`, W / 2, H - 160); }
}

// ===================== 输入 =====================
const keys = {};
const mouse = { x: 0, y: 0, wx: 0, wy: 0, down: false, mode: null, target: null, id: null };
function pickAt(px, py) {
  const tol = COARSE ? 1.7 : 1;
  for (const r of labelRects) if (px >= r.x - 4 * tol && px <= r.x + r.w + 4 * tol && py >= r.y - 3 * tol && py <= r.y + r.h + 3 * tol) return { type: 'item', obj: r.gi };
  let best = null, bd = 1e9;
  for (const e of M.mons) {
    if (M.theme !== 'town' && !M.vis[Math.floor(e.y) * M.w + Math.floor(e.x)]) continue;
    const s = e.d.size || 1, ex = sx(e.x, e.y), ey = sy(e.x, e.y) - 20 * Z * s, d = Math.hypot(px - ex, (py - ey) * .75);
    if (d < 22 * Z * s * tol && d < bd) { bd = d; best = { type: 'mon', obj: e }; }
  }
  if (best) return best;
  for (const n of M.npcs) { const ex = sx(n.x, n.y), ey = sy(n.x, n.y) - 22 * Z, d = Math.hypot(px - ex, (py - ey) * .7); if (d < 26 * Z * tol && d < bd) { bd = d; best = { type: 'npc', obj: n }; } }
  if (best) return best;
  for (const p of M.props) {
    if (!['chest', 'barrel', 'shrine', 'wp', 'portal', 'well'].includes(p.type) || (p.type === 'chest' && p.open) || (p.type === 'shrine' && p.used)) continue;
    if (M.theme !== 'town' && !M.seen[Math.floor(p.y) * M.w + Math.floor(p.x)]) continue;
    const ex = sx(p.x, p.y), ey = sy(p.x, p.y) - 14 * Z, d = Math.hypot(px - ex, (py - ey) * .8);
    if (d < 24 * Z * tol && d < bd) { bd = d; best = { type: 'prop', obj: p }; }
  }
  return best;
}
function targetEntity(h) {
  if (!h) return null;
  if (h.type === 'item') return h.obj;
  if (h.type === 'mon' || h.type === 'npc') return h.obj;
  if (h.type === 'prop') return { kind: 'prop', p: h.obj, x: h.obj.x, y: h.obj.y };
  return null;
}
function pointerDown(px, py, button, shift) {
  Snd.init();
  if (state !== 'play' || paused) return;
  if (bigMap && !COARSE) { bigMap = false; }
  const [wx, wy] = s2w(px, py); mouse.wx = wx; mouse.wy = wy;
  if (button === 2) { castSkill(0, wx, wy); return; }
  mouse.down = true;
  const h = pickAt(px, py);
  if (h && h.type === 'mon' && (shift || dist(P, h.obj) <= .75 + h.obj.r + P.r)) { mouse.mode = 'attack'; mouse.target = h.obj; P.target = h.obj; P.path = null; return; }
  if (h) { const t = targetEntity(h); mouse.mode = h.type === 'mon' ? 'attack' : 'act'; mouse.target = t; P.target = t; P.path = null; P.holdT = 0; return; }
  if (shift) { mouse.mode = null; faceTo(P, wx, wy); return; }
  mouse.mode = 'move'; mouse.target = null; P.target = null; P.holdT = 0;
  setPath(P, wx, wy);
  M.fx.push({ type: 'p', x: wx, y: wy, z: 0, vx: 0, vy: 0, vz: 0, col: '#c9a35a', t: .3, sz: 4 });
}
cv.addEventListener('contextmenu', e => e.preventDefault());
cv.addEventListener('pointerdown', e => {
  e.preventDefault();
  if (mouse.id !== null && e.pointerType === 'touch' && mouse.id !== e.pointerId) return;
  mouse.id = e.pointerId; mouse.x = e.clientX; mouse.y = e.clientY;
  try { cv.setPointerCapture(e.pointerId); } catch (_) {}
  pointerDown(e.clientX, e.clientY, e.button, e.shiftKey);
});
cv.addEventListener('pointermove', e => {
  if (mouse.id !== null && mouse.id !== e.pointerId) return;
  mouse.x = e.clientX; mouse.y = e.clientY;
  if (M) { const [wx, wy] = s2w(mouse.x, mouse.y); mouse.wx = wx; mouse.wy = wy; }
});
const up = e => { if (mouse.id !== null && e.pointerId !== mouse.id) return; mouse.down = false; mouse.mode = null; mouse.id = null; if (P && P.target && P.target.kind === 'mon' && mouse.target === P.target) { /* 松开后本次攻击打完即停 */ } mouse.target = null; };
cv.addEventListener('pointerup', up); cv.addEventListener('pointercancel', up);
window.addEventListener('keydown', e => {
  const k = e.key.toLowerCase();
  if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
  if (state !== 'play') return;
  Snd.init();
  if (k === 'escape') { e.preventDefault(); if (!$('panel').hidden) closePanel(); else if (bigMap) bigMap = false; else openMenu(); return; }
  if (k === 'tab') { e.preventDefault(); bigMap = !bigMap; return; }
  if (!$('panel').hidden) { if (k === 'i' || k === 'b') { if (panelType === 'inv') closePanel(); else openInv(); } else if (k === 'c') { if (panelType === 'char') closePanel(); else openChar(); } return; }
  if (['w', 'a', 's', 'd', 'arrowup', 'arrowdown', 'arrowleft', 'arrowright'].includes(k)) { keys[k] = true; e.preventDefault(); return; }
  if (e.repeat) return;
  if (k >= '1' && k <= '4') castSkill(+k - 1, mouse.wx, mouse.wy);
  else if (k === 'q') drinkPotion('hp');
  else if (k === 'e') drinkPotion('mp');
  else if (k === 't') castTownPortal();
  else if (k === 'i' || k === 'b') openInv();
  else if (k === 'c') openChar();
  else if (k === 'm') { Snd.on = !Snd.on; log(Snd.on ? '音效：开' : '音效：关', '#a8987f'); }
});
window.addEventListener('keyup', e => { keys[e.key.toLowerCase()] = false; });
window.addEventListener('blur', () => { for (const k in keys) keys[k] = false; mouse.down = false; });

// ===================== 界面 =====================
let panelType = null, selItem = null;
function openPanel(type, title, html) {
  panelType = type; paused = true;
  $('panel-title').textContent = title; $('panel-body').innerHTML = html; $('panel').hidden = false;
  mouse.down = false; for (const k in keys) keys[k] = false;
  const f = $('panel-body').querySelector('button'); if (f && !COARSE) f.focus({ preventScroll: true });
}
function closePanel() { $('panel').hidden = true; panelType = null; selItem = null; paused = false; }
$('panel-x').onclick = closePanel;
function refreshPanel() { if (panelType === 'inv') openInv(true); else if (panelType === 'char') openChar(); else if (panelType === 'shop') openShop(currentShop, true); }

function affLines(it) { return Object.keys(it.aff || {}).map(k => `<div class="ln af">${esc(AFF[k].t.replace('{v}', it.aff[k]))}</div>`).join(''); }
function itemHtml(it, cmp) {
  const b = BASES[it.b];
  let h = `<div class="nm c${it.r}">${esc(it.n)}</div><div class="bs">${esc(RNAME[it.r])} · ${esc(b.n)} · 物品等级 ${it.ilvl}</div>`;
  if (it.dmg) h += `<div class="ln">伤害：${it.dmg[0]} - ${it.dmg[1]} · 攻速 ${it.spd.toFixed(2)}</div>`;
  if (it.arm) h += `<div class="ln">护甲：${it.arm}</div>`;
  h += affLines(it);
  h += `<div class="ln req ${hero.lvl < it.req ? 'bad' : ''}">需要等级：${it.req}</div>`;
  if (cmp && cmp !== it) {
    const d = [];
    if (it.dmg && cmp.dmg) { const a = (it.dmg[0] + it.dmg[1]) * it.spd, bb = (cmp.dmg[0] + cmp.dmg[1]) * cmp.spd; d.push(delta('武器每秒伤害', (a - bb) / 2)); }
    if ((it.arm || 0) !== (cmp.arm || 0)) d.push(delta('护甲', (it.arm || 0) - (cmp.arm || 0)));
    const ks = new Set([...Object.keys(it.aff || {}), ...Object.keys(cmp.aff || {})]);
    for (const k of ks) { const v = (it.aff[k] || 0) - (cmp.aff[k] || 0); if (v) d.push(delta(AFF[k].t.replace('{v}', '').replace('+', '').trim(), v)); }
    if (d.length) h += `<div class="ln" style="margin-top:6px;color:#a8987f">与已装备的「${esc(cmp.n)}」相比：</div>` + d.join('');
  }
  return h;
}
function delta(n, v) { const r = Math.round(v * 10) / 10; return `<div class="ln ${r > 0 ? 'up' : 'down'}">${r > 0 ? '▲ +' : '▼ '}${r} ${esc(n)}</div>`; }
function slotBtn(it, act, sel, extra) {
  if (!it) return `<button class="slot" type="button" data-act="${act}" aria-label="空"></button>`;
  const cant = hero.lvl < it.req ? ' cant' : '';
  return `<button class="slot r${it.r}${sel ? ' sel' : ''}${cant}" type="button" data-act="${act}" title="${esc(it.n)}" aria-label="${esc(RNAME[it.r] + ' ' + it.n)}">${esc(BASES[it.b].g)}${extra || ''}</button>`;
}
function invGrid(sellMode) {
  let h = '<div class="grid-inv">';
  for (let i = 0; i < 40; i++) { const it = hero.inv[i]; h += slotBtn(it, it ? 'inv:' + it.id : 'none', it && selItem === it.id); }
  return h + '</div>';
}
function detailHtml(sellMode) {
  if (!selItem) return `<div class="detail"><div class="ln" style="color:#a8987f">${sellMode ? '点选背包里的物品即可查看售价并出售。' : '点选一件物品查看详情。装备后属性立即生效。'}</div></div>`;
  let it = hero.inv.find(x => x.id === selItem), where = 'inv';
  if (!it) { for (const k in hero.eq) if (hero.eq[k] && hero.eq[k].id === selItem) { it = hero.eq[k]; where = 'eq'; } }
  if (!it) return '<div class="detail"></div>';
  const cmp = where === 'inv' ? hero.eq[BASES[it.b].slot] : null;
  let acts = '';
  if (where === 'inv') acts += `<button class="btn sm" type="button" data-act="equip:${it.id}" ${hero.lvl < it.req ? 'disabled' : ''}>装备</button>`;
  else acts += `<button class="btn sm" type="button" data-act="unequip:${it.id}">卸下</button>`;
  if (sellMode && where === 'inv') acts += `<button class="btn sm" type="button" data-act="sell:${it.id}">出售（${sellValue(it)} 金币）</button>`;
  if (where === 'inv' && M !== town) acts += `<button class="btn sm" type="button" data-act="drop:${it.id}">丢在地上</button>`;
  return `<div class="detail">${itemHtml(it, cmp)}<div class="acts">${acts}</div></div>`;
}
function openInv(keep) {
  if (!keep) selItem = null;
  let h = '<h3>装备</h3><div class="eq">';
  for (const [k, n] of SLOTS) { const it = hero.eq[k]; h += `<div class="cell">${slotBtn(it, it ? 'eq:' + it.id : 'none', it && selItem === it.id)}<div>${n}</div></div>`; }
  h += `</div><h3>背包（${hero.inv.length}/40）· <span class="gold">${hero.gold} 金币</span></h3>` + invGrid(false) + detailHtml(false);
  h += `<p style="margin-top:10px;font-size:12px;color:#7d6f5c">药水与卷轴放在腰带里：生命 ${hero.pots.hp} · 法力 ${hero.pots.mp} · 回城 ${hero.pots.tp}</p>`;
  const st = $('panel-body').scrollTop;
  openPanel('inv', '背包', h);
  if (keep) $('panel-body').scrollTop = st;
}
function equip(id) {
  const i = hero.inv.findIndex(x => x.id === id); if (i < 0) return;
  const it = hero.inv[i]; if (hero.lvl < it.req) return;
  const slot = BASES[it.b].slot, old = hero.eq[slot];
  hero.inv.splice(i, 1); hero.eq[slot] = it; if (old) hero.inv.splice(i, 0, old);
  calcStats(); Snd.play('pick'); selItem = it.id;
}
function unequip(id) {
  for (const k in hero.eq) if (hero.eq[k] && hero.eq[k].id === id) {
    if (hero.inv.length >= 40) { log('背包已满', '#e0604a'); return; }
    hero.inv.push(hero.eq[k]); delete hero.eq[k]; calcStats(); Snd.play('pick');
  }
}
$('panel-body').addEventListener('click', e => {
  const b = e.target.closest('[data-act]'); if (!b) return;
  const [a, v] = b.dataset.act.split(':'); const id = +v;
  Snd.init();
  if (a === 'inv' || a === 'eq') { selItem = id; refreshPanel(); }
  else if (a === 'equip') { equip(id); refreshPanel(); }
  else if (a === 'unequip') { unequip(id); refreshPanel(); }
  else if (a === 'sell') { const i = hero.inv.findIndex(x => x.id === id); if (i >= 0) { const it = hero.inv[i]; hero.gold += sellValue(it); hero.inv.splice(i, 1); selItem = null; Snd.play('gold'); log(`出售 ${it.n}，获得 ${sellValue(it)} 金币`, '#c9a35a'); refreshPanel(); } }
  else if (a === 'drop') { const i = hero.inv.findIndex(x => x.id === id); if (i >= 0) { dropItemAt(hero.inv.splice(i, 1)[0], P.x, P.y); selItem = null; refreshPanel(); } }
  else if (a === 'buy') buy(v);
  else if (a === 'stat') { if (hero.pts > 0) { hero[v]++; hero.pts--; calcStats(); Snd.play('click'); openChar(); } }
  else if (a === 'opt') { const fn = dlgOpts[id]; if (fn) fn(); }
  else if (a === 'wp') { closePanel(); goFloor(id, 'wp'); }
});

function openChar() {
  calcStats();
  const pl = hero.pts > 0;
  const stat = (k, n, tip) => `<div><span>${n} <small style="color:#7d6f5c">${tip}</small></span><span><b>${S[k]}</b>${pl ? `<button class="plus" type="button" data-act="stat:${k}" aria-label="加一点${n}">+</button>` : ''}</span></div>`;
  let h = `<h3>流浪者 · ${hero.lvl} 级</h3>`;
  h += `<p style="font-size:13px;color:#a8987f">经验 ${hero.xp} / ${xpNeed(hero.lvl)} · 击杀 ${hero.kills} · 最深到达 ${hero.maxFloor ? '第 ' + hero.maxFloor + ' 层' : '尚未下地窖'}${pl ? ` · <b style="color:#ffd24a">可分配属性点：${hero.pts}</b>` : ''}</p>`;
  h += '<div class="stats">' + stat('str', '力量', '近战伤害') + stat('vit', '体能', '生命') + stat('mag', '魔力', '法力与法术伤害') +
    `<div><span>生命</span><b>${Math.ceil(hero.hp)} / ${S.maxHp}</b></div><div><span>法力</span><b>${Math.floor(hero.mp)} / ${S.maxMp}</b></div>` +
    `<div><span>武器伤害</span><b>${S.dmg[0]} - ${S.dmg[1]}</b></div><div><span>每秒攻击</span><b>${S.aps.toFixed(2)}</b></div>` +
    `<div><span>火球伤害</span><b>≈ ${Math.round((4 + hero.lvl * 1.6) * S.spell)}</b></div><div><span>护甲</span><b>${S.arm}（减伤 ${Math.round(drAgainst(Math.max(1, hero.maxFloor) * 2) * 100)}%）</b></div>` +
    `<div><span>暴击几率</span><b>${S.crit}%</b></div><div><span>生命偷取</span><b>${S.ls}%</b></div>` +
    `<div><span>移动速度</span><b>${Math.round(S.ms / 4.3 * 100)}%</b></div><div><span>每秒回复</span><b>${S.regen.toFixed(1)} 生命</b></div>` +
    `<div><span>金币加成</span><b>${S.gf}%</b></div><div><span>魔法物品掉率</span><b>${S.mf}%</b></div></div>`;
  if (hero.buff) h += `<p style="margin-top:8px;color:#9ad8ff;font-size:13px">神殿祝福：${esc(SHRINES.find(s => s.k === hero.buff.k).n)}，剩余 ${Math.ceil(hero.buff.t)} 秒</p>`;
  h += '<h3>技能</h3>';
  for (const s of SK) h += `<div class="quest ${hero.lvl < s.lvl ? 'done' : ''}"><b>${s.k} · ${s.n}</b>（${s.mp} 法力${hero.lvl < s.lvl ? ` · ${s.lvl} 级解锁` : ''}）<br>${s.d}</div>`;
  h += '<h3>任务</h3>' + questLog();
  openPanel('char', '角色', h);
}
function questLog() {
  const q = hero.q, out = [];
  const Q = (st, t, d) => out.push(`<div class="quest ${st === 3 ? 'done' : ''}"><b>${t}</b>${st === 3 ? '（已完成）' : st === 2 ? '（可交付）' : ''}<br>${d}</div>`);
  if (q.q1) Q(q.q1, '地窖里的钟声', q.q1 === 1 ? '下到修道院地窖第 2 层，查明发生了什么。' : q.q1 === 2 ? '回镇上把见闻告诉伊莲。' : '你证实了地下的亡灵已经苏醒。');
  if (q.q2) Q(q.q2, '铁匠的学徒', q.q2 === 1 ? '铁匠格伦的学徒托比被抓进了地下第 3 层。击败腐肉监工莫格，救出托比。' : q.q2 === 2 ? '托比得救了，回去找格伦。' : '托比平安回到了铁匠铺。');
  if (q.q3) Q(q.q3, '余烬之心', q.q3 === 1 ? '在第 6 层的封印大厅阻止堕落院长摩登。' : q.q3 === 2 ? '回镇上告诉伊莲封印大厅里发生的事。' : '灰烬之王没有死……他只是换了容器。无尽深渊已开启。');
  return out.length ? out.join('') : '<p style="font-size:13px;color:#a8987f">去镇中央的篝火旁找老祭司伊莲谈谈。</p>';
}

// ----- 对话 -----
let dlgOpts = [];
function dialog(npc, text, opts) {
  dlgOpts = opts.map(o => o.fn);
  const paras = (Array.isArray(text) ? text : [text]).map(t => `<p>${esc(t)}</p>`).join('');
  const h = `<div class="npc"><div class="ava">${esc(npc.g)}</div><div class="txt"><div class="who">${esc(npc.n)}</div>${paras}</div></div>` +
    `<div class="opts">${opts.map((o, i) => `<button class="btn${o.main ? ' main' : ''}" type="button" data-act="opt:${i}">${esc(o.t)}</button>`).join('')}</div>`;
  openPanel('dialog', npc.n, h);
}
function npcMark(n) {
  const q = hero.q;
  if (n.id === 'elin') return (q.q1 === 0 || q.q1 === 2 || (q.q3 === 0 && (q.q2 === 3 || hero.maxFloor >= 4)) || q.q3 === 2) ? (q.q1 === 2 || q.q3 === 2 ? '?' : '!') : '';
  if (n.id === 'gren') return (q.q2 === 0 && q.q1 >= 1) ? '!' : q.q2 === 2 ? '?' : '';
  return '';
}
function talk(n) {
  Snd.play('click');
  const q = hero.q, bye = { t: '告辞', fn: closePanel };
  if (n.id === 'elin') {
    calcStats(); hero.hp = S.maxHp; hero.mp = S.maxMp;
    if (q.q1 === 0) return dialog(n, ['又一个旅人……愿圣焰庇佑你。你来得不是时候，孩子。', '一个月前，修道院的钟在午夜自己响了。摩登院长带着修士们下了地窖，再也没有回来。现在每到夜里，地底都会传来呻吟，死去的人从坟里爬出来。', '镇上能拿剑的人都已经下去过了，没有一个回来。如果你愿意，替我去地窖看看——至少告诉我，下面到底发生了什么。'],
      [{ t: '我去地窖看看。', main: true, fn: () => { q.q1 = 1; closePanel(); log('新任务：地窖里的钟声——下到地窖第 2 层', '#ffd24a'); saveGame(); } }, bye]);
    if (q.q1 === 2) return dialog(n, ['亡灵……连修士们的尸骨都站起来了吗？圣焰在上。', '这证实了我最害怕的事：封印松动了。拿着这些药水吧，你会用得上的。'],
      [{ t: '收下药水', main: true, fn: () => { q.q1 = 3; hero.pots.hp += 3; hero.pots.mp += 2; gainXp(120); log('获得 生命药水 ×3、法力药水 ×2', '#ffd24a'); talk(n); } }]);
    if (q.q3 === 0 && (q.q2 === 3 || hero.maxFloor >= 4)) return dialog(n, ['我必须告诉你真相了。', '三十年前，灰烬之王厄鲁斯焚毁了半个王国。修会用七位守誓者的命，把他封进了一枚「余烬之心」，就埋在修道院最深处的封印大厅。', '摩登院长是守护那颗心的最后一人。如果他打破了封印……不，如果他「成为」了封印——孩子，去第 6 层。无论他变成了什么，阻止他。'],
      [{ t: '我会阻止他。', main: true, fn: () => { q.q3 = 1; closePanel(); log('新任务：余烬之心——前往第 6 层封印大厅', '#ffd24a'); saveGame(); } }, bye]);
    if (q.q3 === 2) return dialog(n, ['你回来了……让我看看你。', '……孩子，你的眼睛里有火。', '灰烬之王没有死，他只是换了一个容器。封印大厅下面的裂隙还在呼唤他。去吧，在火焰吞没你之前，把深渊里的东西全部埋葬。这是修会最后的遗物，带上它。'],
      [{ t: '收下遗物', main: true, fn: () => { q.q3 = 3; hero.won = true; const it = genItem(Math.max(14, hero.lvl + 2), { rar: 3 }); hero.inv.length < 40 ? hero.inv.push(it) : dropItemAt(it, P.x, P.y); gainXp(1500); log(`获得传奇物品：${it.n}`, '#e8843a'); log('无尽深渊已开启：第 6 层之下还有更深的楼层', '#ffd24a'); Snd.play('legend'); closePanel(); saveGame(); } }]);
    const lines = q.q3 === 1 ? '封印大厅在第 6 层。愿圣焰为你照亮道路。' : q.q2 === 1 ? '格伦的学徒还困在下面……莫格那头畜生，以前是修道院的屠夫。' : hero.won ? '深渊没有尽头，孩子。但每往下一层，你都让地面上的人多活一天。' : '伤口我已经为你治好了。小心脚下，孩子。';
    return dialog(n, [lines, '（伊莲为你恢复了全部生命与法力）'], [{ t: '关于烬原镇', fn: () => dialog(n, ['烬原镇建在三十年前那场大火的灰烬上，所以叫这个名字。镇上的人大多是守誓者的后代。', '北边的废墟就是圣焰修道院，地窖入口在废墟中间。镇中央的传送石能把你送到你到过的任何一层。'], [{ t: '返回', fn: () => talk(n) }]) }, bye]);
  }
  if (n.id === 'gren') {
    if (q.q2 === 0 && q.q1 >= 1) return dialog(n, ['你要下地窖？……那帮我一个忙。', '我的学徒托比，那傻小子三天前偷了我的锤子，说要下去找他爹。有人在第 3 层听见了他的叫声——还有剁肉的声音。', '以前修道院有个屠夫叫莫格，现在他就在下面，自称「监工」。把托比带回来，我给你打一把最好的家伙。'],
      [{ t: '我会把托比带回来。', main: true, fn: () => { q.q2 = 1; closePanel(); log('新任务：铁匠的学徒——击败第 3 层的莫格', '#ffd24a'); saveGame(); } }, { t: '先看看你的货', fn: () => openShop('smith') }, bye]);
    if (q.q2 === 2) return dialog(n, ['托比回来了！浑身是血，但活着……', '说话算话。这是我这辈子打过最好的一件，拿去吧。'],
      [{ t: '收下报酬', main: true, fn: () => { q.q2 = 3; const it = genItem(Math.max(8, hero.lvl + 2), { rar: 2, slot: 'weapon' }); hero.inv.length < 40 ? hero.inv.push(it) : dropItemAt(it, P.x, P.y); gainXp(400); log(`获得：${it.n}`, '#f3d34a'); spawnToby(); closePanel(); saveGame(); } }]);
    return dialog(n, ['要买兵器护甲，还是要卖点破烂？'], [{ t: '交易', main: true, fn: () => openShop('smith') }, bye]);
  }
  if (n.id === 'mara') return dialog(n, ['药水、卷轴，要什么自己挑。别问配方。'], [{ t: '交易', main: true, fn: () => openShop('alch') }, { t: '关于地下的怪物', fn: () => dialog(n, ['骸骨弓手会躲在远处放箭，别站着不动；邪教术士会瞬移，逼近了打。', '名字发蓝光的是「精英」，更硬也更值钱。木桶里偶尔藏着小鬼，砸之前想清楚。', '要是被围住了，冰霜新星能让它们慢下来。'], [{ t: '返回', fn: () => talk(n) }]) }, bye]);
  if (n.id === 'toby') return dialog(n, [pick(['谢谢你救了我！师父现在不骂我了……至少少骂了一点。', '我在下面看见院长了。他的胸口在发光，像一块烧红的炭。', '莫格的屠宰间里挂满了……我不想说了。'])], [bye]);
}
function spawnToby() { if (!town.npcs.some(n => n.id === 'toby')) town.npcs.push({ kind: 'npc', id: 'toby', n: '学徒 托比', g: '托', x: 12.4, y: 17.2, face: .5, walk: 0, r: .3, look: 'boy' }); }
function epilogue() {
  const n = { n: '封印大厅', g: '烬' };
  dialog(n, ['摩登院长倒下时，胸口的余烬之心裂开了一道缝。', '火光没有熄灭——它顺着你的剑刃爬上手臂，钻进了你的掌心。那一瞬间，你听见一个古老的声音：「容器……终于找到你了。」', '你咬紧牙关，把碎裂的心石塞进行囊。封印大厅的地面开始崩塌，一道通往更深处的裂隙在你脚下张开。', '回到烬原镇，把这一切告诉伊莲——或者，继续向下。'], [{ t: '……', main: true, fn: closePanel }]);
}

// ----- 商店与传送石 -----
let currentShop = null;
function refreshShops() {
  const il = Math.max(2, hero.lvl + 1);
  shopStock.smith = []; for (let i = 0; i < 8; i++) { const it = genItem(il, { rar: rand() < .12 ? 2 : rand() < .45 ? 1 : 0 }); if (BASES[it.b].magicOnly) i--; else shopStock.smith.push(it); }
  shopStock.alch = [];
  for (let i = 0; i < 2; i++) shopStock.alch.push(genItem(il, { rar: rand() < .15 ? 2 : 1, base: pick(['ring', 'amulet']) }));
}
function buy(v) {
  if (v === 'hp' || v === 'mp' || v === 'tp') {
    const price = { hp: 25, mp: 25, tp: 40 }[v]; if (hero.gold < price) { log('金币不足', '#e0604a'); return; }
    hero.gold -= price; hero.pots[v]++; Snd.play('gold'); openShop(currentShop, true); return;
  }
  const list = shopStock[currentShop], i = list.findIndex(x => x.id === +v); if (i < 0) return;
  const it = list[i], price = itemValue(it);
  if (hero.gold < price) { log('金币不足', '#e0604a'); return; }
  if (hero.inv.length >= 40) { log('背包已满', '#e0604a'); return; }
  hero.gold -= price; hero.inv.push(it); list.splice(i, 1); Snd.play('gold'); log(`购买 ${it.n}`, '#c9a35a'); openShop(currentShop, true);
}
function openShop(which, keep) {
  currentShop = which; if (!keep) selItem = null;
  let h = `<p><span class="gold">持有 ${hero.gold} 金币</span></p><h3>${which === 'smith' ? '格伦的货架' : '玛拉的货架'}</h3><div class="shop-list">`;
  if (which === 'alch') {
    for (const [k, n, p, g, c] of [['hp', '生命药水', 25, '血', '#ff5a44'], ['mp', '法力药水', 25, '蓝', '#5a8aff'], ['tp', '回城卷轴', 40, '城', '#7fd6ff']])
      h += `<div class="shop-item"><span class="slot" style="color:${c}">${g}</span><div class="info">${n}<br><small style="color:#7d6f5c">持有 ${hero.pots[k]}</small></div><button class="btn sm" type="button" data-act="buy:${k}">${p} 金币</button></div>`;
  }
  for (const it of shopStock[which]) {
    const price = itemValue(it);
    h += `<div class="shop-item${selItem === 'shop' + it.id ? ' sel' : ''}"><span class="slot r${it.r}">${esc(BASES[it.b].g)}</span><div class="info"><span class="c${it.r}">${esc(it.n)}</span><br><small style="color:#7d6f5c">${esc(BASES[it.b].n)}${it.dmg ? ` · 伤害 ${it.dmg[0]}-${it.dmg[1]}` : ''}${it.arm ? ` · 护甲 ${it.arm}` : ''}${Object.keys(it.aff).length ? ' · ' + Object.keys(it.aff).map(k => AFF[k].t.replace('{v}', it.aff[k])).join('，') : ''} · 需要 ${it.req} 级</small></div><button class="btn sm" type="button" data-act="buy:${it.id}" ${hero.gold < price ? 'disabled' : ''}>${price} 金币</button></div>`;
  }
  h += `</div><h3>出售（背包 ${hero.inv.length}/40）</h3>` + invGrid(true) + detailHtml(true);
  const st = $('panel-body').scrollTop;
  openPanel('shop', which === 'smith' ? '铁匠 格伦' : '药剂师 玛拉', h);
  if (keep) $('panel-body').scrollTop = st;
}
function openWaypoint() {
  if (!hero.maxFloor) { log('传送石沉默着——你还没有到过地下任何一层', '#a8987f'); return; }
  let h = '<p>把手按在冰冷的石头上，选择要前往的楼层：</p><div class="opts">';
  for (let f = 1; f <= hero.maxFloor; f++) h += `<button class="btn" type="button" data-act="wp:${f}">${esc(floorName(f))}${isBossFloor(f) ? ' ☠' : ''}</button>`;
  h += '</div>';
  openPanel('wp', '传送石', h);
}
function openMenu() {
  dlgOpts = [closePanel, () => { saveGame(); log('已保存', '#c9a35a'); closePanel(); }, () => { Snd.on = !Snd.on; openMenu(); }, openHelp, () => { location.href = '../'; },
    () => { if (confirm('确定删除存档并重新开始吗？此操作无法撤销。')) { try { localStorage.removeItem(SAVE_KEY); } catch (e) {} location.reload(); } }];
  const labels = ['继续游戏', '保存游戏', `音效：${Snd.on ? '开' : '关'}（M）`, '操作说明', '返回游戏介绍页', '删除存档，重新开始'];
  openPanel('menu', '菜单', `<div class="opts">${labels.map((l, i) => `<button class="btn${i === 0 ? ' main' : ''}" type="button" data-act="opt:${i}">${esc(l)}</button>`).join('')}</div><p style="margin-top:12px;font-size:12px;color:#7d6f5c">游戏每 30 秒以及切换楼层时自动保存到当前浏览器。</p>`);
}
function helpHtml() {
  return `<h3>电脑</h3><div class="keys">
    <span><kbd>左键</kbd></span><span>点地面移动（按住持续移动）；点怪物攻击；点物品拾取；点人物对话</span>
    <span><kbd>Shift</kbd>+<kbd>左键</kbd></span><span>原地攻击</span>
    <span><kbd>右键</kbd></span><span>向鼠标方向释放火球</span>
    <span><kbd>1</kbd>～<kbd>4</kbd></span><span>向鼠标位置释放技能</span>
    <span><kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd></span><span>键盘移动（可选）</span>
    <span><kbd>Q</kbd> <kbd>E</kbd></span><span>生命药水 · 法力药水</span>
    <span><kbd>T</kbd></span><span>回城卷轴（打开传送门）</span>
    <span><kbd>I</kbd> <kbd>C</kbd> <kbd>Tab</kbd></span><span>背包 · 角色 · 自动地图</span>
    <span><kbd>M</kbd> <kbd>Esc</kbd></span><span>音效开关 · 菜单</span></div>
    <h3>手机 / 平板</h3><div class="keys">
    <span><kbd>点地面</kbd></span><span>移动（按住拖动持续移动）</span>
    <span><kbd>点怪物</kbd></span><span>攻击；按住不放持续攻击</span>
    <span><kbd>技能按钮</kbd></span><span>自动瞄准最近的可见敌人</span>
    <span><kbd>右上角</kbd></span><span>背包 · 角色 · 地图 · 菜单</span></div>
    <h3>小提示</h3><p>打开面板时游戏会暂停。升级后在「角色」里分配属性点。名字发蓝的精英怪掉落更好；金色是稀有、橙色是传奇。在镇上找伊莲可以免费回满血蓝。</p>`;
}
function openHelp() { openPanel('help', '操作说明', helpHtml()); }

// ----- HUD -----
function buildHud() {
  $('skills').innerHTML = SK.map((s, i) => `<button class="sk ${s.c}" id="sk-${i}" type="button" title="${esc(s.n)}（${s.k}）· ${s.mp} 法力"><span class="key">${s.k}</span><b>${s.g}</b><small>${esc(s.n)}</small><span class="cdv"></span></button>`).join('');
  SK.forEach((s, i) => { $('sk-' + i).onclick = () => { Snd.init(); castSkill(i); }; });
  $('p-hp').onclick = () => drinkPotion('hp'); $('p-mp').onclick = () => drinkPotion('mp'); $('p-tp').onclick = () => { if (!paused) castTownPortal(); };
  $('b-inv').onclick = () => { if (panelType === 'inv') closePanel(); else openInv(); };
  $('b-char').onclick = () => { if (panelType === 'char') closePanel(); else openChar(); };
  $('b-map').onclick = () => { bigMap = !bigMap; };
  $('b-menu').onclick = () => { if (panelType === 'menu') closePanel(); else openMenu(); };
}
let hudCache = {};
function setIf(key, val, fn) { if (hudCache[key] !== val) { hudCache[key] = val; fn(val); } }
function updHud() {
  const hp = Math.max(0, Math.ceil(hero.hp)), mp = Math.floor(hero.mp);
  setIf('hp', hp + '/' + S.maxHp, () => { $('orb-hp').querySelector('i').style.height = (hp / S.maxHp * 100) + '%'; $('orb-hp').querySelector('span').textContent = `${hp}/${S.maxHp}`; $('orb-hp').classList.toggle('low', hp < S.maxHp * .3); });
  setIf('mp', mp + '/' + S.maxMp, () => { $('orb-mp').querySelector('i').style.height = (mp / S.maxMp * 100) + '%'; $('orb-mp').querySelector('span').textContent = `${mp}/${S.maxMp}`; });
  setIf('xp', hero.xp + '/' + hero.lvl, () => { $('xp').querySelector('i').style.width = (hero.xp / xpNeed(hero.lvl) * 100) + '%'; $('xp').title = `经验 ${hero.xp} / ${xpNeed(hero.lvl)}（${hero.lvl} 级）`; });
  setIf('pots', `${hero.pots.hp},${hero.pots.mp},${hero.pots.tp}`, () => { $('p-hp').querySelector('.cnt').textContent = hero.pots.hp; $('p-mp').querySelector('.cnt').textContent = hero.pots.mp; $('p-tp').querySelector('.cnt').textContent = hero.pots.tp; });
  setIf('pts', hero.pts, v => { $('pts-badge').hidden = !v; $('pts-badge').textContent = v; });
  SK.forEach((s, i) => {
    const el = $('sk-' + i), cd = P.cds[s.id] || 0;
    setIf('sk' + i, `${hero.lvl >= s.lvl}|${hero.mp >= s.mp}|${cd > 0 ? Math.ceil(cd * 10) : 0}`, () => { el.classList.toggle('locked', hero.lvl < s.lvl); el.classList.toggle('nomana', hero.lvl >= s.lvl && hero.mp < s.mp); el.querySelector('.cdv').style.height = (cd / s.cd * 100) + '%'; });
  });
  // Boss 血条
  const boss = M.mons.find(e => e.d.boss && e.state !== 'idle');
  setIf('boss', boss ? boss.name + Math.ceil(boss.hp) : '', () => { $('bossbar').hidden = !boss; if (boss) { $('bossbar').querySelector('.name').textContent = boss.name; $('bossbar').querySelector('i').style.width = (Math.max(0, boss.hp) / boss.max * 100) + '%'; } });
  // 目标信息
  let tg = null;
  if (hover && hover.type === 'mon') tg = hover.obj; else if (lastHit && lastHit.t > 0 && !lastHit.e.dead) tg = lastHit.e;
  if (tg && tg.d.boss && boss) tg = null;
  setIf('tgt', tg ? tg.name + Math.ceil(tg.hp) : '', () => {
    $('tgt').hidden = !tg; if (!tg) return;
    const nm = $('tgt').querySelector('.name'); nm.textContent = tg.name; nm.className = 'name' + (tg.d.boss ? ' boss' : tg.champ ? ' champ' : '');
    $('tgt').querySelector('i').style.width = (Math.max(0, tg.hp) / tg.max * 100) + '%';
    $('tgt').querySelector('.sub').textContent = `${tg.champ ? '精英 · ' : ''}等级 ${tg.lvl}`;
  });
}
function updateLoc() {
  const el = $('loc'); el.textContent = '';
  const a = document.createElement('div'); a.textContent = floorName(M.floor); el.appendChild(a);
  const s = document.createElement('small'); s.textContent = M === town ? '安全区域' : `最深 ${hero.maxFloor} 层`; el.appendChild(s);
  hudCache = {};
}

// ===================== 死亡与复活 =====================
function die() {
  state = 'dead'; hero.hp = 0; hero.deaths++;
  const lost = Math.floor(hero.gold * .1); hero.gold -= lost;
  $('death-note').textContent = `你在${floorName(M.floor)}倒下了。${lost ? `掉落了 ${lost} 金币。` : ''}伊莲会在镇上为你疗伤，你到过的楼层可以通过传送石返回。`;
  $('death').hidden = false; Snd.play('die'); saveGame();
}
$('d-revive').onclick = () => {
  $('death').hidden = true; state = 'play'; calcStats(); hero.hp = S.maxHp; hero.mp = S.maxMp;
  const s = nearFree(town, 20.5, 19.5, true); enterMap(town, s.x, s.y);
};

// ===================== 存档 =====================
function saveGame() {
  if (!hero) return;
  try { localStorage.setItem(SAVE_KEY, JSON.stringify(Object.assign({}, hero, { savedAt: new Date().toISOString() }))); } catch (e) { /* 无痕模式等情况下无法保存，游戏照常进行 */ }
}
function loadGame() {
  try {
    const raw = localStorage.getItem(SAVE_KEY); if (!raw) return null;
    const h = JSON.parse(raw); if (!h || h.v !== 1 || typeof h.lvl !== 'number') return null;
    const d = newHero(); const out = Object.assign(d, h); out.q = Object.assign(d.q, h.q || {}); out.pots = Object.assign({ hp: 0, mp: 0, tp: 0 }, h.pots || {});
    out.inv = (Array.isArray(h.inv) ? h.inv : []).filter(it => it && BASES[it.b]);
    out.eq = {}; for (const k in (h.eq || {})) if (h.eq[k] && BASES[h.eq[k].b]) out.eq[k] = h.eq[k];
    let mx = 0; for (const it of out.inv.concat(Object.values(out.eq))) mx = Math.max(mx, it.id || 0); UID = mx + 1;
    return out;
  } catch (e) { return null; }
}

// ===================== 启动 =====================
function startGame(h) {
  hero = h; maps = {}; tp = null;
  town = genTown();
  if (hero.q.q2 === 3) spawnToby();
  P = mkPlayer(19.5, 21.5);
  calcStats(); if (hero.hp > S.maxHp || hero.hp <= 0) hero.hp = S.maxHp; if (hero.mp > S.maxMp) hero.mp = S.maxMp;
  $('title').hidden = true; $('hud').hidden = false; state = 'play';
  enterMap(town, 19.5, 21.5);
  if (hero.lvl === 1 && hero.q.q1 === 0) { log('找到篝火旁的老祭司伊莲（头顶有「!」），点击她对话', '#ffd24a'); if (COARSE) log('点地面移动，点怪物攻击，技能按钮会自动瞄准', '#a8987f'); }
  else log('欢迎回来，流浪者', '#c9a35a');
}
function newGame() {
  const h = newHero();
  h.eq.weapon = genItem(1, { rar: 0, base: 'sword' }); h.eq.body = genItem(1, { rar: 0, base: 'cloth' });
  startGame(h);
}
const saved = loadGame();
if (saved) { $('t-continue').hidden = false; $('t-continue').textContent = `继续旅程（${saved.lvl} 级 · 最深第 ${saved.maxFloor} 层）`; }
$('t-continue').onclick = () => { Snd.init(); startGame(loadGame() || newHero()); };
$('t-new').onclick = () => { Snd.init(); if (saved && !confirm('开始新的旅程会覆盖现有存档，确定吗？')) return; newGame(); };
$('t-help').onclick = () => { $('title').hidden = true; openPanel('help', '操作说明', helpHtml() + '<div class="opts"><button class="btn main" type="button" data-act="opt:0">返回标题</button></div>'); dlgOpts = [() => { closePanel(); $('title').hidden = false; }]; };
$('panel-x').addEventListener('click', () => { if (state === 'title') $('title').hidden = false; });
buildHud();
window.addEventListener('resize', resize); resize();

let last = performance.now();
function frame(now) {
  const dt = Math.min(.05, (now - last) / 1000); last = now;
  if (cv.clientWidth !== W || cv.clientHeight !== H || Math.min(2, window.devicePixelRatio || 1) !== DPR) resize();
  if (state === 'play' && !paused && M) {
    time += dt;
    if (mouse.down) { const [wx, wy] = s2w(mouse.x, mouse.y); mouse.wx = wx; mouse.wy = wy; }
    updPlayer(dt);
    if (state === 'play') {
      for (const e of M.mons.slice()) if (!e.dead) updMon(e, dt);
      separate(); updProj(dt); updFx(dt);
    }
    if (shake > 0) shake = Math.max(0, shake - dt * 30);
    if (lastHit) lastHit.t -= dt;
    // 悬停
    if (!COARSE) { hover = pickAt(mouse.x, mouse.y); cv.style.cursor = hover ? 'pointer' : 'default'; }
    saveTimer += dt; if (saveTimer > 30) { saveTimer = 0; saveGame(); }
  } else if (M) time += dt * .2;
  if (M && P && hero) { render(); if (state !== 'title') updHud(); }
  else { ctx.setTransform(DPR, 0, 0, DPR, 0, 0); ctx.fillStyle = '#050304'; ctx.fillRect(0, 0, W, H); }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
document.addEventListener('visibilitychange', () => { if (document.hidden) saveGame(); });
window.addEventListener('pagehide', saveGame);

// 测试钩子（仅用于本地自动化测试，不影响游戏）
window.__EF = { get hero() { return hero; }, get M() { return M; }, get P() { return P; }, get S() { return S; }, goFloor, genItem, castSkill, calcStats, state: () => state, xpNeed, hurtMon };
})();
