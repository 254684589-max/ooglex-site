#!/usr/bin/env node
/** 品类行情板离线契约：六大类组合、逐行来源与口径、失败隔离与走势区间裁剪。 */

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  BOARD_CATEGORIES,
  STOCK_ROW_LIMIT,
  buildBoard,
  formatAsOf,
  formatChange,
  formatPrice,
  summarize,
  tenorChangeBp
} from "../apps/finance-terminal/finance-terminal-board-data.mjs";
import { rangeChange, sliceSeries } from "../apps/finance-terminal/finance-terminal-board-view.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

async function readJson(relative) {
  return JSON.parse(await readFile(path.join(ROOT, relative), "utf8"));
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

async function loadGroup() {
  const [assetTracker, companies, assetRanking, macro, macroCurve] = await Promise.all([
    readJson("apps/asset-tracker/data.json"),
    readJson("apps/companies/data.json"),
    readJson("apps/asset-ranking/data.json"),
    readJson("apps/macro-radar/data.json"),
    readJson("apps/macro-radar/curve.json")
  ]);
  return {
    assetTracker: { data: assetTracker, error: null },
    companies: { data: companies, error: null },
    assetRanking: { data: assetRanking, error: null },
    macro: { data: macro, error: null },
    macroCurve: { data: macroCurve, error: null }
  };
}

function categoryOf(board, key) {
  return board.categories.filter((category) => category.key === key)[0];
}

function validateFormatting() {
  assert.equal(formatChange(null, "pct").text, "—", "缺值不得显示成0%");
  assert.equal(formatChange(null, "pct").direction, "unknown");
  assert.equal(formatChange(1.234, "pct").text, "+1.23%");
  assert.equal(formatChange(1.234, "pct").arrow, "▲", "涨跌必须有颜色以外的符号编码");
  assert.equal(formatChange(-0.5, "pct").arrow, "▼");
  assert.equal(formatChange(0, "pct").text, "0.00%");
  assert.equal(formatChange(0, "pct").direction, "flat");
  assert.equal(formatChange(5.2, "bp").text, "+5 bp", "收益率变化必须按基点显示");
  assert.equal(formatPrice(1.16671, 4), "1.1667", "汇率不得被四舍五入成两位小数");
  assert.equal(formatPrice(7652.8599), "7,652.86");
  assert.equal(formatPrice(null), "—");
  assert.equal(formatAsOf("2026-08-24T20:00:00Z"), "2026-08-24");
  assert.equal(formatAsOf("2026-08-24"), "2026-08-24");
  assert.equal(formatAsOf(null), "");
}

function validateSeriesWindow() {
  const dates = ["2026-08-17", "2026-08-18", "2026-08-19", "2026-08-20"];
  const values = [10, null, 12, 13];
  const all = sliceSeries(dates, values, 260);
  assert.deepEqual(all.dates, ["2026-08-17", "2026-08-19", "2026-08-20"],
    "无观测的交易日必须被跳过，不做前向填充");
  assert.deepEqual(all.values, [10, 12, 13]);
  const window = sliceSeries(dates, values, 2);
  assert.deepEqual(window.dates, ["2026-08-19", "2026-08-20"], "区间只取窗口末端的真实观测");
  assert.equal(rangeChange([10, 13], false), "+30.00%");
  assert.equal(rangeChange([4.0, 4.25], true), "+25 bp", "收益率区间必须按基点表达");
  assert.equal(rangeChange([10], false), null, "单点不得推算区间变化");
  assert.equal(rangeChange([], true), null);
}

function validateCategories(board) {
  assert.deepEqual(board.categories.map((category) => category.key),
    ["commodity", "index", "stock", "fx", "crypto", "bond"], "六大品类顺序必须固定");
  assert.deepEqual(board.categories.map((category) => category.label),
    ["商品", "指数", "股票", "外汇", "加密", "债券"]);
  assert.equal(BOARD_CATEGORIES.length, 6);
  assert.equal(board.status, "ok");
  board.categories.forEach((category) => {
    assert.ok(category.rows.length > 0, `${category.label}必须有可展示的标的`);
    assert.ok(Number.isInteger(category.collapseAfter) && category.collapseAfter > 0,
      `${category.label}必须有可折叠的首屏行数阈值`);
    assert.ok(category.extraLabel, `${category.label}缺少附加列标题`);
    category.rows.forEach((row) => {
      assert.ok(row.name && row.symbol, "每行必须有名称与代码");
      assert.ok(row.sourceName, `${row.name} 缺少来源`);
      assert.ok(row.asOf, `${row.name} 缺少数据日`);
      assert.ok(row.frequency, `${row.name} 缺少频率`);
      assert.ok(["ok", "partial", "stale", "unknown"].includes(row.status));
      assert.ok(row.changeBasis, `${row.name} 缺少涨跌口径`);
      assert.notEqual(row.priceText, "—", `${row.name} 不得在没有价格时进入行情板`);
      assert.ok(/^https:\/\//.test(row.sourceUrl), `${row.name} 缺少可核对的来源链接`);
    });
  });
}

function validateCalibration(board) {
  const stock = categoryOf(board, "stock");
  const crypto = categoryOf(board, "crypto");
  const bond = categoryOf(board, "bond");
  assert.ok(stock.rows.every((row) => row.changeBasis === "当日价格变动"));
  assert.ok(crypto.rows.every((row) => row.changeBasis === "过去24小时"),
    "加密涨跌是24小时口径，必须与股票当日口径分开标注");
  assert.ok(bond.rows.some((row) => row.change.text.endsWith("bp")),
    "美债收益率必须按基点显示，不得用百分比相对变化冒充");
  assert.ok(stock.rows.length <= STOCK_ROW_LIMIT);
  assert.ok(bond.rows.every((row) => row.unit === "年化收益率" || row.proxyOf || row.note),
    "债券行必须标明是收益率还是代理");
}

function validateProvenance(board, group) {
  const stock = categoryOf(board, "stock");
  const listed = new Map((group.companies.data.companies || []).map((item) => [item.symbol, item]));
  stock.rows.forEach((row) => {
    const upstream = listed.get(row.symbol);
    assert.ok(upstream, `${row.name} 必须来自公司榜真实记录`);
    assert.equal(upstream.dataMeta.mode, "market", "未上市估值不得进入股票行情板");
    assert.equal(row.price, upstream.price, "价格必须与上游一致，不得二次加工");
  });
  const fx = categoryOf(board, "fx");
  assert.ok(fx.rows.every((row) => row.symbol !== "DX-Y.NYB"),
    "ICE美元指数是专有基准，本页按许可决定只展示美联储广义美元指数");
  assert.ok(fx.rows.some((row) => row.symbol === "DTWEXBGS"));

  const curve = group.macroCurve.data;
  const bond = categoryOf(board, "bond");
  const tenor = bond.rows.filter((row) => row.symbol === "DGS10")[0];
  assert.ok(tenor, "债券品类必须包含10年期");
  const values = curve.history.values.DGS10.filter((value) => typeof value === "number");
  const expected = Math.round((values[values.length - 1] - values[values.length - 2]) * 100);
  assert.equal(tenor.change.text, `${expected > 0 ? "+" : ""}${expected} bp`,
    "基点变化必须能由曲线历史的最后两个观测复算");
  assert.equal(tenorChangeBp({ values: { X: [1] } }, "X"), null, "单点不得推算基点变化");
  assert.equal(tenorChangeBp(null, "X"), null);
}

async function validateFailureIsolation(group) {
  const broken = { ...group, companies: { data: null, error: new Error("HTTP 500") } };
  const board = buildBoard(broken);
  assert.equal(board.status, "partial", "单条管线失败只降级为部分可用");
  assert.equal(categoryOf(board, "stock").rows.length, 0);
  assert.equal(categoryOf(board, "stock").summary.text, "本类暂无可用数据");
  assert.ok(categoryOf(board, "index").rows.length > 0, "其他品类不得因股票失败一起清空");
  assert.ok(board.failures.some((message) => message.includes("公司榜")));

  const empty = buildBoard({});
  assert.equal(empty.status, "error");
  assert.equal(empty.total, 0);
  assert.equal(empty.summaryText, "品类行情暂不可用");
}

function validateStaleAndMissing(group) {
  const mutated = clone(group);
  const target = mutated.assetTracker.data.assets.filter((asset) => asset.category === "commodity")[0];
  target.stale = true;
  target.dataMeta.status = "partial";
  const board = buildBoard({
    assetTracker: { data: mutated.assetTracker.data, error: null },
    companies: { data: mutated.companies.data, error: null },
    assetRanking: { data: mutated.assetRanking.data, error: null },
    macro: { data: mutated.macro.data, error: null },
    macroCurve: { data: mutated.macroCurve.data, error: null }
  });
  const commodity = categoryOf(board, "commodity");
  const row = commodity.rows.filter((item) => item.symbol === target.symbol)[0];
  assert.equal(row.status, "stale", "上游过期必须逐行显示，不得静默展示旧值");
  assert.ok(commodity.summary.text.includes("过期1"));

  const withoutChange = summarize([
    { change: { direction: "unknown" }, status: "unknown", asOf: "" }
  ]);
  assert.equal(withoutChange.up, 0);
  assert.equal(withoutChange.down, 0, "缺涨跌的行不得被计入任何一边");
}

async function main() {
  const group = await loadGroup();
  const board = buildBoard(group);
  validateFormatting();
  validateSeriesWindow();
  validateCategories(board);
  validateCalibration(board);
  validateProvenance(board, group);
  await validateFailureIsolation(group);
  validateStaleAndMissing(group);
  const counts = board.categories.map((category) => `${category.label}${category.rows.length}`).join(" · ");
  console.log("Finance Terminal category board contract: PASS");
  console.log(`- six categories from existing daily pipelines: ${counts}`);
  console.log("- per-row source / as-of / frequency / stale / change basis: PASS");
  console.log("- listed-only stocks / no proprietary DXY level / reproducible bp change: PASS");
  console.log("- single-pipeline failure isolation / stale propagation / no forward fill: PASS");
}

main().catch((error) => {
  console.error(error.stack || error.message || String(error));
  process.exitCode = 1;
});
