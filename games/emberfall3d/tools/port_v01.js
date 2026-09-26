// 阶段 P1：把 V0.1（games/emberfall/play/game.js）的数据一次性转成大作版的 JSON，
// 并用 V0.1 自己的公式函数算出一份「对照答案」，供 Godot 测试逐项比对（tests/test_runner.gd 的 port 组）。
//
//   node games/emberfall3d/tools/port_v01.js
//
// 输出：
//   godot/data/act1_items.json      物品底材、部位、词缀、传奇、稀有名、品质
//   godot/data/act1_monsters.json   V0.1 怪物表、精英特性、各层怪物池
//   godot/data/act1_rules.json      成长、掉落、商店、技能、神殿等规则常量
//   godot/tests/fixtures/v01_reference.json  V0.1 公式在一组固定输入下的输出
//
// 做法：从 game.js 里按括号配对截出常量字面量与纯函数的源码，放进 node 的 vm 沙箱执行，
// 不手抄数值（手抄容易错）。移植完成后 3D 版的 JSON 就是唯一事实来源，V0.1 冻结，不再反向同步；
// 这个脚本留作「移植时到底对照了什么」的记录，V0.1 不改就不需要再跑。
// 写在函数体里的规则常量（楼层成长、掉落几率、成长公式）写进 godot/data/act1_rules.json（在本脚本里手工整理，
// 每条注明 V0.1 出处），由这里生成的对照答案验证 GDScript 的实现。
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '../../..');
const SRC = path.join(ROOT, 'games/emberfall/play/game.js');
const GODOT = path.resolve(__dirname, '../godot');
const src = fs.readFileSync(SRC, 'utf8');

// 从 start 位置起截出一段括号配对的文本（跳过字符串与模板字符串）
function balanced(from) {
  const open = src[from], close = { '{': '}', '[': ']', '(': ')' }[open];
  let depth = 0, i = from, q = null;
  for (; i < src.length; i++) {
    const c = src[i];
    if (q) { if (c === '\\') { i++; continue; } if (c === q) q = null; continue; }
    if (c === '"' || c === "'" || c === '`') { q = c; continue; }
    if (c === open) depth++;
    else if (c === close && --depth === 0) return src.slice(from, i + 1);
  }
  throw new Error('括号不配对：' + from);
}
function literal(name) {
  const m = new RegExp(`\\nconst ${name} = `).exec(src);
  if (!m) throw new Error('找不到常量 ' + name);
  const at = m.index + m[0].length;
  return vm.runInNewContext('(' + balanced(at) + ')', { ALL: literal.ALL });
}
function fnSource(name) {
  const m = new RegExp(`\\nfunction ${name}\\(`).exec(src);
  if (!m) throw new Error('找不到函数 ' + name);
  const body = src.indexOf('{', m.index + m[0].length - 1);
  return src.slice(m.index + 1, body) + balanced(body);
}

literal.ALL = vm.runInNewContext(/\nconst ALL = ([^;]+);/.exec(src)[1]);
const BASES = literal('BASES'), SLOTS = literal('SLOTS'), AFF = literal('AFF'), UNIQ = literal('UNIQ');
const RARE_A = literal('RARE_A'), RARE_B = literal('RARE_B'), RNAME = literal('RNAME');
const MT = literal('MT'), CHAMP = literal('CHAMP'), SK = literal('SK'), SHRINES = literal('SHRINES');
const THEMES = literal('THEMES');
const themeLook = k => ({ floor_rgb: THEMES[k].fa, wall_hex: THEMES[k].wl, lava: !!THEMES[k].lava });

// ---------- 物品 ----------
const items = {
  _说明: '由 tools/port_v01.js 从 V0.1 games/emberfall/play/game.js 的 BASES / SLOTS / AFF / UNIQ / RARE_A / RARE_B / RNAME 转换（阶段 P1）。之后以本文件为准。',
  slots: SLOTS.map(([id, name]) => ({ id, name })),
  rarities: RNAME,
  bases: Object.fromEntries(Object.entries(BASES).map(([k, b]) => [k, Object.assign(
    { name: b.n, glyph: b.g, slot: b.slot, lvl: b.lvl },
    b.w ? { weapon_kind: b.w } : {}, b.dmg ? { dmg: b.dmg, spd: b.spd } : {}, b.arm ? { arm: b.arm } : {},
    b.imp ? { implicit: b.imp } : {}, b.col ? { color: b.col } : {}, b.magicOnly ? { magic_only: true } : {})])),
  affixes: Object.fromEntries(Object.entries(AFF).map(([k, a]) => [k, Object.assign(
    { text: a.t, base: a.a, per_ilvl: a.b, prefix: a.pre, slots: a.s === '*' ? 'all' : a.s }, a.max ? { max: a.max } : {})])),
  uniques: UNIQ.map(u => ({ name: u.n, base: u.b, affixes: u.aff })),
  rare_names: { first: RARE_A, second: RARE_B },
};

// ---------- 怪物 ----------
const poolFor = vm.runInNewContext('(' + fnSource('poolFor') + ')');
const monsters = {
  _说明: '由 tools/port_v01.js 从 V0.1 的 MT / CHAMP / poolFor 转换（阶段 P1）。与大作版原有的 data/monsters.json（焦骨蛮兵等 4 种）并存，P5 再统一行为实现。',
  monsters: Object.fromEntries(Object.entries(MT).map(([k, d]) => [k, Object.assign(
    { name: d.n, hp: d.hp, dmg: d.dmg, spd: d.spd, cd: d.cd, range: d.range, xp: d.xp, size: d.size, kind: d.kind, aggro: d.aggro, look: d.look },
    d.proj ? { proj: d.proj } : {}, d.boss ? { boss: true } : {}, d.blink ? { blink: true } : {})])),
  champions: Object.fromEntries(Object.entries(CHAMP).map(([k, n]) => [k, { prefix: n }])),
  pools: Object.fromEntries([1, 2, 3, 4, 5, 6, 7].map(f => [String(f), poolFor(f)])),
  _pools说明: '键为楼层；第 7 层起（无尽深渊）都用 "7" 的怪物池。',
};

// ---------- 规则常量（写在函数体里的数字，手工整理，每条注明 V0.1 出处；由下面的对照答案验证实现） ----------
const rules = {
  _说明: '阶段 P1 从 V0.1 game.js 函数体中整理出的规则常量（键名后的「出处」为 V0.1 的函数名）。之后以本文件为准。',
  hero: {
    _出处: 'newHero / gainXp / calcStats / pickUp / die',
    start: { lvl: 1, str: 15, vit: 15, mag: 15, gold: 60, pots: { hp: 3, mp: 2, tp: 1 } },
    level_cap: 50, points_per_level: 5, inventory_cap: 40, death_gold_loss: 0.1,
    xp_need: { base: 90, exp: 1.65 },
    stats: {
      hp: { base: 30, per_vit: 2, per_lvl: 4 }, mp: { base: 10, per_mag: 1.5, per_lvl: 1.5 },
      str_dmg_div: 100, mag_spell_div: 40, base_crit: 5, base_move_speed: 4.3,
      regen: { base: 0.4, per_lvl: 0.05 }, mana_regen: { base: 1.2, per_mag: 0.06 }, base_light: 6,
      unarmed: { dmg: [1, 3], spd: 1.1 },
    },
    armor_dr: { _出处: 'drAgainst', base: 40, per_mlvl: 18, cap: 0.75 },
    kill_xp: { _出处: 'killMon：玩家比怪物高 5 级以上，每多 1 级经验 -15%，最低 10%', free_gap: 5, per_level: 0.15, floor: 0.1 },
    potions: { _出处: 'drinkPotion', hp: { of_max: 0.45, flat: 10 }, mp: { of_max: 0.5, flat: 5 } },
  },
  shrines: { duration_s: 90, list: SHRINES.map(s => ({ id: s.k, name: s.n, desc: s.d })),
    effects: { might: { dmg_mul: 1.5 }, guard: { arm_mul: 1.5 }, swift: { aps_mul: 1.25, move_mul: 1.2 }, arcane: { mana_regen_mul: 3, spell_mul: 1.3 } } },
  skills: SK.map(s => ({ id: s.id, name: s.n, key: s.k, lvl: s.lvl, mp: s.mp, cd: s.cd, glyph: s.g, desc: s.d })),
  skill_formulas: {
    _出处: 'castSkill / updProj',
    fireball: { base: 4, per_lvl: 1.6, speed: 9, life_s: 1.2, splash_radius: 1.3, splash_mul: 0.5, jitter: [0.85, 1.15] },
    whirl: { weapon_mul: 1.3, radius: 1.9 },
    nova: { base: 6, per_lvl: 2, radius: 4, slow_s: 3, slow_mul: 0.5, jitter: [0.85, 1.15] },
    blink: { range: 7, needs_los: true },
  },
  items: {
    _出处: 'rollRarity / baseStats / genItem / itemValue',
    rarity: { legendary: 0.012, rare: 0.09, magic: 0.36, magic_mul_cap: 2 },
    growth: { weapon_dmg_per_ilvl: 0.025, armor_per_ilvl: 0.03, unique_affix_per_ilvl: 1 / 40, unique_flat_affixes: ['ias', 'ls', 'ms', 'crit', 'light'] },
    affix_count: { magic: [1, 2], rare: [3, 4] }, unique_base_lvl_slack: 4, base_lvl_slack: 1,
    req: { ilvl_mul: 0.6, unique_cap: 40 },
    value: { base: 12, per_ilvl: 5, rarity_mul: [1, 2.5, 5, 10], per_arm: 2, per_max_dmg: 2, sell_div: 4 },
  },
  monsters: {
    _出处: 'spawnMon / hurtMon / hurtHero / updMon / killMon',
    hp_growth: { per_floor: 0.4, per_floor_sq: 0.03, boss_per_floor: 0.35 }, dmg_growth_per_floor: 0.3, xp_growth_per_floor: 0.45,
    lvl: { per_floor: 2, boss_bonus: 3 },
    champion: { chance: 0.12, hp_mul: 2.6, dmg_mul: 1.35, xp_mul: 3, fast_speed_mul: 1.45, stone_taken_mul: 0.6, fury_cd_mul: 0.6, fire_dmg_mul: 1.25, fire_death_ring: { radius: 2.2 }, vamp_heal_on_hit: true },
    pack: { chance: 0.72, size: [2, 4], deep_bonus_after_floor: 3, champion_size: [2, 3], mixed_chance: 0.3 },
  },
  floors: {
    _出处: 'themeFor / floorName / isBossFloor / genDungeon',
    themes: {
      crypt: Object.assign({ name: THEMES.crypt.n, floors: [1, 2] }, themeLook('crypt')),
      catacomb: Object.assign({ name: THEMES.catacomb.n, floors: [3, 4] }, themeLook('catacomb')),
      inferno: Object.assign({ name: THEMES.inferno.n, floors: [5, 6] }, themeLook('inferno')),
      abyss: Object.assign({ name: THEMES.abyss.n, floors: [7, 9999] }, themeLook('abyss')),
    },
    _themes说明: 'floor_rgb / wall_hex / lava 取自 V0.1 THEMES（fa / wl / lava），3D 版按修道院地窖为基准换算成材质染色。',
    generator: {
      _出处: 'genDungeon / corridor / finishWalls',
      size: [58, 58], boss_room: [13, 13], rooms_base: 11, rooms_extra_max: 5, room_size: [5, 10], room_margin: 2, room_gap: 1, room_tries: 200,
      extra_corridors: 3, corridor_width: 2,
      deco: { bones_below: 0.035, rubble_below: 0.08, lava_below: 0.1 },
      torch: { chance: 0.07, min_spacing: 6 },
    },
    town_name: '烬原镇', boss_floors: [3, 6], abyss_boss_every: 5,
    bosses: { '3': 'mog', '6': 'abbot' }, abyss_boss_names: { mog: '深渊化身 · 缚链者', abbot: '深渊化身 · 焚誓者' }, boss_guards: { mog: 'zombie', abbot: 'skel' },
    props: { barrels_per_room: [0, 3], chest_chance: 0.2, shrine_floor_chance: 0.75, shrine_room_chance: 0.3 },
  },
  loot: {
    _出处: 'dropLoot / useProp',
    ilvl: { per_floor: 2, boss_bonus: 3, champion_bonus: 1 },
    normal: { gold_chance: 0.42, gold: [3, 9], potion_chance: 0.08, potion_hp_share: 0.7, scroll_chance: 0.015, item_chance: 0.11 },
    champion: { gold_mul: 3, items_two_chance: 0.7, mf_mul: 2.5 },
    boss: { gold: [40, 80], first_legendary_chance: 0.45, magic_find_mul: 3 },
    chest: { gold: [8, 20], items: [1, 2], ilvl_bonus: 1, mf_mul: 2, potion_chance: 0.5 },
    barrel: { gold_below: 0.3, gold: [2, 6], potion_below: 0.42, item_below: 0.47, imps_below: 0.55, imps: [1, 2] },
  },
  shop: {
    _出处: 'refreshShops / buy',
    prices: { hp: 25, mp: 25, tp: 40 },
    smith: { count: 8, rare_chance: 0.12, magic_chance: 0.45 }, alchemist: { count: 2, rare_chance: 0.15, bases: ['ring', 'amulet'] },
    ilvl: { min: 2, over_hero_lvl: 1 },
  },
};

// ---------- 对照答案：用 V0.1 自己的函数计算 ----------
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
function sandbox(extra) {
  return vm.createContext(Object.assign({ Math, BASES, AFF, UNIQ, MT, CHAMP, SK, clamp, ri: (a, b) => a, rand: () => 0, pick: a => a[0], UID: 1 }, extra || {}));
}
function run(ctx, code) { return vm.runInContext(code, ctx); }

const ref = { _说明: '由 tools/port_v01.js 用 V0.1 的原函数算出（阶段 P1）。Godot 测试（port 组）逐项比对。', source_sha256: require('crypto').createHash('sha256').update(src).digest('hex') };

// 经验曲线
{
  const ctx = sandbox(); run(ctx, fnSource('xpNeed'));
  ref.xp_need = Array.from({ length: 50 }, (_, i) => run(ctx, `xpNeed(${i + 1})`));
}
// 词缀数值范围：把 ri 换成取下限 / 上限
{
  const lo = sandbox({ ri: (a, b) => a }), hi = sandbox({ ri: (a, b) => b });
  run(lo, fnSource('rollAff')); run(hi, fnSource('rollAff'));
  ref.affix_range = {};
  for (const k of Object.keys(AFF)) for (const il of [1, 5, 12, 30, 60])
    ref.affix_range[`${k}@${il}`] = [run(lo, `rollAff('${k}', ${il})`), run(hi, `rollAff('${k}', ${il})`)];
}
// 品质掷骰：给定随机数与掉率倍数
{
  ref.rarity = [];
  for (const mul of [1, 2, 2.5, 3, 6]) for (const r of [0, .005, .011, .02, .05, .089, .1, .2, .3, .35, .5, .7, .72, .99]) {
    const ctx = sandbox({ rand: () => r }); run(ctx, fnSource('rollRarity'));
    ref.rarity.push({ mul, r, out: run(ctx, `rollRarity(${mul})`) });
  }
}
// 底材基础属性随物品等级成长
{
  const ctx = sandbox(); run(ctx, fnSource('baseStats'));
  ref.base_stats = {};
  for (const k of Object.keys(BASES)) for (const il of [1, 8, 20, 45]) {
    const it = { aff: {} }; run(ctx, `(function(it){ baseStats(it, BASES['${k}'], ${il}); })`)(it);
    ref.base_stats[`${k}@${il}`] = it;
  }
}
// 物品售价
{
  const ctx = sandbox(); run(ctx, fnSource('itemValue')); run(ctx, fnSource('sellValue'));
  ref.item_value = [];
  for (const it of [{ ilvl: 1, r: 0 }, { ilvl: 4, r: 1, arm: 6 }, { ilvl: 10, r: 2, dmg: [8, 17] }, { ilvl: 25, r: 3, arm: 30 }, { ilvl: 13, r: 1, dmg: [3, 9], arm: 0 }])
    ref.item_value.push({ it, value: run(ctx, 'itemValue')(it), sell: run(ctx, 'sellValue')(it) });
}
// 角色属性（calcStats）与减伤（drAgainst）
{
  const cases = [
    { name: '新角色', hero: { lvl: 1, str: 15, vit: 15, mag: 15, hp: 999, mp: 999, eq: {}, buff: null } },
    { name: '10 级剑盾', hero: { lvl: 10, str: 30, vit: 25, mag: 20, hp: 999, mp: 999, buff: null, eq: {
      weapon: { dmg: [7, 15], spd: 1.05, aff: { dmgp: 20, ias: 10, crit: 3 } }, off: { arm: 10, aff: { armp: 25 } },
      body: { arm: 15, aff: { life: 30, vit: 5 } }, feet: { arm: 2, aff: { ms: 15 } }, ring: { aff: { ls: 3, mf: 20, gf: 40 } } } } },
    { name: '20 级法杖 + 秘法神殿', hero: { lvl: 20, str: 20, vit: 40, mag: 80, hp: 999, mp: 999, buff: { k: 'arcane', t: 30 }, eq: {
      weapon: { dmg: [6, 13], spd: 1.0, aff: { spellp: 45, mag: 12 } }, neck: { aff: { mana: 40, regen: 4, light: 2 } } } } },
    { name: '15 级力量神殿', hero: { lvl: 15, str: 60, vit: 30, mag: 15, hp: 999, mp: 999, buff: { k: 'might', t: 10 }, eq: { weapon: { dmg: [12, 26], spd: .8, aff: {} } } } },
    { name: '守护与迅捷已过期', hero: { lvl: 8, str: 20, vit: 20, mag: 20, hp: 999, mp: 999, buff: { k: 'guard', t: 0 }, eq: { body: { arm: 12, aff: {} } } } },
    { name: '迅捷神殿', hero: { lvl: 12, str: 25, vit: 25, mag: 25, hp: 999, mp: 999, buff: { k: 'swift', t: 5 }, eq: { hands: { arm: 3, aff: { ias: 12 } } } } },
    { name: '守护神殿', hero: { lvl: 18, str: 25, vit: 35, mag: 25, hp: 999, mp: 999, buff: { k: 'guard', t: 50 }, eq: { body: { arm: 22, aff: { armp: 40 } }, helm: { arm: 6, aff: {} } } } },
  ];
  ref.calc_stats = [];
  for (const c of cases) {
    const S = {}, hero = JSON.parse(JSON.stringify(c.hero));
    const ctx = sandbox({ S, hero }); run(ctx, fnSource('calcStats')); run(ctx, fnSource('drAgainst'));
    run(ctx, 'calcStats()');
    const dr = Object.fromEntries([1, 5, 12, 30].map(l => [String(l), run(ctx, `drAgainst(${l})`)]));
    ref.calc_stats.push({ name: c.name, hero: c.hero, stats: JSON.parse(JSON.stringify(S)), dr });
  }
}
// 楼层主题、名称、首领层
{
  const ctx = sandbox({ THEMES });
  for (const f of ['themeFor', 'floorName', 'isBossFloor']) run(ctx, fnSource(f));
  ref.floors = Array.from({ length: 21 }, (_, f) => ({ floor: f, theme: f ? run(ctx, `themeFor(${f})`) : 'town', name: run(ctx, `floorName(${f})`), boss: run(ctx, `isBossFloor(${f})`) }));
}
// 怪物随楼层成长（spawnMon）
{
  ref.spawn = [];
  for (const key of Object.keys(MT)) for (const f of [1, 2, 3, 6, 10]) for (const champ of [null, ...Object.keys(CHAMP)]) {
    if (MT[key].boss && champ) continue;
    const m = { floor: f, mons: [] };
    const ctx = sandbox({ m }); run(ctx, fnSource('spawnMon'));
    const e = run(ctx, `spawnMon(m, '${key}', 0, 0, ${champ ? `'${champ}'` : 'null'})`);
    ref.spawn.push({ key, floor: f, champ, hp: e.hp, dmg: e.dmg, xp: e.xp, lvl: e.lvl, spd: e.spd, name: e.name });
  }
}

const w = (p, o) => { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, JSON.stringify(o, null, 1) + '\n'); console.log('写入', path.relative(ROOT, p)); };
w(path.join(GODOT, 'data/act1_items.json'), items);
w(path.join(GODOT, 'data/act1_monsters.json'), monsters);
w(path.join(GODOT, 'data/act1_rules.json'), rules);
w(path.join(GODOT, 'tests/fixtures/v01_reference.json'), ref);
console.log(`底材 ${Object.keys(BASES).length} · 词缀 ${Object.keys(AFF).length} · 传奇 ${UNIQ.length} · 怪物 ${Object.keys(MT).length} · 精英特性 ${Object.keys(CHAMP).length} · 技能 ${SK.length} · 神殿 ${SHRINES.length}`);
