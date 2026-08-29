#!/usr/bin/env node
/** 标普500热力图的离线契约。
 *
 * 这张图最容易出的错是「看起来对、其实在骗人」，所以守四件事：
 * 1. 面积必须严格正比于市值——方块图唯一的量化承诺；
 * 2. 颜色不是唯一编码——色阶两条分支各自单调、中点中性，且每档都自带 ink 供文字取色；
 * 3. 缺口不隐瞒——名单里站内没有行情的公司必须逐个列出，页面照实显示；
 * 4. 缺当日涨跌的不涂成「持平」——没取到不等于没变化。
 */
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { squarify, layoutSectors } from "../apps/heatmap/heatmap-layout.mjs";
import {
  SCALE, NO_CHANGE, stepFor, formatCap, formatPct, groupBySector, summarize
} from "../apps/heatmap/heatmap-data.mjs";
import { defaultLimit, aspectFor } from "../apps/heatmap/heatmap.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function validateScale() {
  assert.equal(SCALE.length, 7, "发散色阶应为「三档跌 + 中性 + 三档涨」");
  const flat = SCALE.filter((s) => s.key === "flat")[0];
  assert.ok(flat, "必须有中性档");
  /* 中点必须读作「没变化」：给它一个色相就等于说「不变也是一种方向」。 */
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(flat.color.slice(i, i + 2), 16));
  assert.ok(Math.max(r, g, b) - Math.min(r, g, b) < 24,
    `中性档必须接近灰，实为 ${flat.color}`);
  assert.ok(SCALE.every((s) => s.ink === "light" || s.ink === "dark"),
    "每一档都要声明瓦片上用浅字还是深字——对比度是逐档算过的，不能由页面随便挑");
  assert.ok(SCALE.every((s) => s.label && /[涨跌持平]/.test(s.label)),
    "每一档都要有文字标签：图例不能只有色块");

  /* 分档边界连续且单调，落点不重叠、不留空。 */
  const bounds = SCALE.map((s) => s.max);
  assert.deepEqual(bounds, bounds.slice().sort((a, b) => a - b), "分档上界必须单调递增");
  assert.equal(bounds[bounds.length - 1], Infinity, "最后一档必须收口到无穷");
  [-9, -3, -1.5, -0.05, 0, 0.05, 2, 9].forEach((v) => {
    assert.ok(SCALE.includes(stepFor(v)), `${v}% 必须落进某一档`);
  });
  assert.equal(stepFor(-5).key, "down3");
  assert.equal(stepFor(0).key, "flat");
  assert.equal(stepFor(2).key, "up2");

  /* 缺当日涨跌的必须单独一档，不得并进「基本持平」。 */
  assert.equal(stepFor(null), NO_CHANGE);
  assert.equal(stepFor(undefined), NO_CHANGE);
  assert.equal(stepFor(NaN), NO_CHANGE);
  assert.notEqual(NO_CHANGE.color, flat.color,
    "「没取到」和「没变化」必须是两种颜色：涂成一样就是把缺失说成持平");
}

function validateFormatting() {
  assert.equal(formatCap(3751.8), "3.75万亿美元");
  assert.equal(formatCap(500), "5,000亿美元", "上游单位是十亿美元，中文里要换成亿");
  assert.equal(formatCap(21.7), "217亿美元");
  assert.equal(formatCap(null), "—", "缺市值不得显示成 0");
  /* 颜色之外的第二重编码：涨跌文字必须带方向符号。 */
  assert.match(formatPct(1.23), /^▲1\.23%$/);
  assert.match(formatPct(-1.23), /^▼1\.23%$/);
  assert.equal(formatPct(0), "—0.00%");
  assert.equal(formatPct(null), "—", "缺涨跌不得显示成 0.00%");
}

function validateGrouping() {
  const members = [
    { symbol: "A", marketCap: 400, changePct: 2, sector: "科技" },
    { symbol: "B", marketCap: 100, changePct: -8, sector: "科技" },
    { symbol: "C", marketCap: 200, changePct: 1, sector: "金融" },
    { symbol: "D", marketCap: 50, changePct: null, sector: "金融" },
    { symbol: "E", marketCap: 0, changePct: 5, sector: "能源" },
    { symbol: "F", marketCap: null, changePct: 5, sector: "能源" }
  ];
  const sectors = groupBySector(members);
  assert.deepEqual(sectors.map((s) => s.key), ["科技", "金融"],
    "市值非正或缺失的一律剔除，也不得凭空造出只有它们的行业块");
  assert.equal(sectors[0].value, 500, "行业面积是成分股市值之和");

  /* 行业涨跌按市值加权：等权平均会让一家小公司的暴跌看起来像全行业在跌。 */
  const tech = sectors[0].changePct;
  assert.ok(Math.abs(tech - (2 * 400 + -8 * 100) / 500) < 1e-9,
    `行业涨跌必须按市值加权，实得 ${tech}`);
  assert.notEqual(tech, (2 + -8) / 2, "不得用等权平均");

  /* 缺涨跌的公司仍计入面积，但不参与加权——否则它会被当成 0% 拉平整个行业。 */
  const fin = sectors[1];
  assert.equal(fin.value, 250, "缺涨跌的公司仍要计入行业面积");
  assert.equal(fin.changePct, 1, "缺涨跌的公司不得被当成 0% 参与加权");

  const limited = groupBySector(members, 2);
  assert.equal(limited.reduce((sum, s) => sum + s.count, 0), 2,
    "限制家数时按市值取前 N，不是随便截断");
  assert.deepEqual(limited.map((s) => s.key), ["科技", "金融"]);

  const stats = summarize(members);
  assert.equal(stats.count, 5, "统计口径是「有市值的行」");
  assert.equal(stats.up, 3);
  assert.equal(stats.down, 1);
  assert.equal(stats.unknown, 1, "缺涨跌的要单独计数，供页面如实说明");
}

function validateGeometry() {
  const rect = { x: 0, y: 0, w: 1000, h: 600 };
  const items = Array.from({ length: 80 }, (_, i) => ({ key: `s${i}`, value: Math.pow(1.1, 80 - i) }));
  const out = squarify(items, rect);
  const total = items.reduce((s, i) => s + i.value, 0);
  out.forEach((t) => {
    const expected = (t.item.value / total) * rect.w * rect.h;
    assert.ok(Math.abs(t.w * t.h - expected) / expected < 1e-9,
      `${t.item.key} 面积与数值不成比例——方块图的量化承诺被破坏了`);
  });
  for (let i = 0; i < out.length; i += 1) {
    for (let j = i + 1; j < out.length; j += 1) {
      const a = out[i], b = out[j];
      const ov = Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x))
               * Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));
      assert.ok(ov < 1e-6, `${a.item.key} 与 ${b.item.key} 重叠`);
    }
  }
  const blocks = layoutSectors(
    [{ key: "t", value: 3, children: [{ key: "x", value: 2 }, { key: "y", value: 1 }] }],
    rect, { headHeight: 20, gap: 2 });
  blocks[0].tiles.forEach((tile) => {
    assert.ok(tile.y >= blocks[0].y + 20 - 1e-9, "公司瓦片不得压到行业标题条上");
  });
}

function validateResponsive() {
  /* 窄屏默认少画一些，但必须是「按市值取前 N 并写明」，而不是悄悄少画。 */
  assert.ok(defaultLimit(360) > 0 && defaultLimit(360) <= 100, "窄屏默认限量");
  assert.equal(defaultLimit(1672), 0, "宽屏默认全部");
  assert.ok(defaultLimit(360) < defaultLimit(768), "越窄画得越少");
  assert.ok(aspectFor(360) > aspectFor(1672),
    "窄屏要把画布拉高，否则每块被压成读不出的细条");
}

async function validatePublished() {
  let payload;
  try {
    payload = JSON.parse(await readFile(path.join(ROOT, "apps/companies/sp500.json"), "utf8"));
  } catch (error) {
    console.log("标普500快照尚未生成，跳过发布数据检查（首次运行前属于正常状态）。");
    return null;
  }
  assert.ok(Array.isArray(payload.members) && payload.members.length > 0, "必须至少带一条成分股");
  assert.equal(payload.count, payload.members.length, "count 必须与实际条数一致");
  assert.ok(Array.isArray(payload.missing), "缺口必须是一个可列举的名单，不能只给个数字");
  assert.ok(payload.constituents >= payload.count, "覆盖数不得超过名单总数");
  /* 缺口必须完整：名单总数 − 覆盖数 就是缺的家数，missing 必须逐个列全。
     只报一个数字、名单里却少列几十家，页面上写出来的「未覆盖 N 家」就是假的。 */
  assert.equal(payload.constituents - payload.count, payload.missing.length,
    `缺口没列全：名单 ${payload.constituents} − 覆盖 ${payload.count} = `
    + `${payload.constituents - payload.count}，但 missing 只列了 ${payload.missing.length} 个`);
  assert.equal(payload.status, payload.missing.length || payload.listStale ? "partial" : "ok",
    "有缺口或名单沿用时不能自称 ok");
  assert.ok(String(payload.note || "").includes("不是指数权重"),
    "说明必须写明这里的市值不是指数权重：两者口径不同");
  const symbols = new Set();
  payload.members.forEach((row) => {
    assert.ok(row.symbol && !symbols.has(row.symbol), `${row.symbol} 重复出现`);
    symbols.add(row.symbol);
    assert.ok(Number.isFinite(row.marketCap) && row.marketCap > 0,
      `${row.symbol} 市值缺失或非正——它决定面积，不能是空的`);
    assert.ok(row.sector, `${row.symbol} 缺行业，会掉进「未分类」块`);
  });
  const caps = payload.members.map((r) => r.marketCap);
  assert.deepEqual(caps, caps.slice().sort((a, b) => b - a), "必须按市值降序");
  assert.ok(payload.members.every((r, i) => r.rank === i + 1), "名次必须与顺序一致");
  assert.ok(!payload.missing.some((s) => symbols.has(s)),
    "缺口名单里的代码不得同时出现在成分股里");
  return payload;
}

async function main() {
  validateScale();
  validateFormatting();
  validateGrouping();
  validateGeometry();
  validateResponsive();
  const published = await validatePublished();
  console.log("S&P 500 heatmap contract: PASS");
  console.log("- diverging scale: 3+1+3 steps, neutral midpoint, per-step ink, missing ≠ flat");
  console.log("- area strictly proportional to market cap, no overlap, header never covers tiles");
  console.log("- sector change is cap-weighted; rows without a change are counted but not weighted");
  console.log("- narrow screens draw fewer by market cap and say so; canvas grows taller");
  if (published) {
    console.log(`- published snapshot: ${published.count}/${published.constituents} constituents, `
      + `${published.missing.length} missing (listed by symbol)`);
  }
}

main().catch((error) => {
  console.error(`FAIL: ${error && error.message ? error.message : error}`);
  process.exit(1);
});
