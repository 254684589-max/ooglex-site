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
import {
  dailyPoints,
  monthlyPoints,
  QUOTE_RANGES,
  rangeStats,
  readQuery,
  slicePoints
} from "../apps/finance-terminal/finance-terminal-quote.mjs";
import {
  distribution,
  matchesQuery,
  rangeChange,
  quoteHref,
  selectRows,
  sliceSeries,
  sparkDirection
} from "../apps/finance-terminal/finance-terminal-board-view.mjs";
import {
  createWatchlistStore,
  orderByWatchlist,
  sanitizeSymbol
} from "../apps/finance-terminal/finance-terminal-watchlist.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

async function readJson(relative) {
  return JSON.parse(await readFile(path.join(ROOT, relative), "utf8"));
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

async function loadGroup() {
  const [assetTracker, companies, assetRanking, assetRankingCrypto, macro, macroCurve] =
    await Promise.all([
      readJson("apps/asset-tracker/data.json"),
      readJson("apps/companies/data.json"),
      readJson("apps/asset-ranking/data.json"),
      readJson("apps/asset-ranking/crypto.json"),
      readJson("apps/macro-radar/data.json"),
      readJson("apps/macro-radar/curve.json")
    ]);
  return {
    assetTracker: { data: assetTracker, error: null },
    companies: { data: companies, error: null },
    assetRanking: { data: assetRanking, error: null },
    assetRankingCrypto: { data: assetRankingCrypto, error: null },
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

/* 搜索与自选：搜索只做字面匹配，自选只前置不改数值，两者叠加时先搜后选。 */
function validateSearchAndWatchlist(board) {
  const commodity = categoryOf(board, "commodity");
  assert.ok(commodity.rows.every((row) => matchesQuery(row, "")), "空搜索词必须匹配全部");
  const gold = commodity.rows.filter((row) => matchesQuery(row, "黄金"));
  assert.ok(gold.length >= 1 && gold.every((row) => row.name.includes("黄金")),
    "中文名搜索必须命中对应标的");
  assert.ok(commodity.rows.filter((row) => matchesQuery(row, "gc=f")).length === 1,
    "代码搜索必须大小写不敏感");
  assert.equal(commodity.rows.filter((row) => matchesQuery(row, "不存在的标的")).length, 0,
    "没有命中时不得回退成全部");

  const plain = selectRows(commodity.rows, "", null);
  assert.equal(plain.shown.length, commodity.rows.length);
  const searched = selectRows(commodity.rows, "黄金", null);
  assert.equal(searched.shown.length, gold.length, "搜索结果必须与匹配数一致");

  const memory = new Map();
  const storage = {
    getItem: (key) => (memory.has(key) ? memory.get(key) : null),
    setItem: (key, value) => memory.set(key, value)
  };
  const store = createWatchlistStore(storage);
  const target = commodity.rows[commodity.rows.length - 1];
  store.toggle(target.symbol);
  const watch = {
    select: (rows) => ({
      ordered: orderByWatchlist(rows, store.list(), (row) => row.symbol),
      shown: orderByWatchlist(rows, store.list(), (row) => row.symbol),
      count: store.size()
    })
  };
  const picked = selectRows(commodity.rows, "", watch);
  assert.equal(picked.shown[0].symbol, target.symbol, "自选标的必须置顶");
  assert.equal(picked.shown.length, commodity.rows.length, "置顶不得丢行");
  assert.equal(picked.watched, 1);
  board.categories.forEach((category) => {
    category.rows.forEach((row) => {
      assert.ok(sanitizeSymbol(row.symbol), `${row.name} 的代码不能进自选存储：${row.symbol}`);
    });
  });
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
  assert.equal(STOCK_ROW_LIMIT, 40, "股票行数必须与公司榜日线历史覆盖的标的数一致");
  assert.ok(stock.rows.length <= STOCK_ROW_LIMIT);
  assert.ok(stock.rows.every((row) => row.series && row.series.kind === "company"),
    "股票行必须指向公司榜日线历史");
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

/* 加密品类板首次生成前是空占位：必须回退到资产榜里已有的加密条目，并且不算管线失败。 */
function validateCryptoFallback(group) {
  const pending = { ...group, assetRankingCrypto: { data: {
    status: "pending", assets: [], history: null
  }, error: null } };
  const board = buildBoard(pending);
  const crypto = categoryOf(board, "crypto");
  assert.ok(crypto.rows.length > 0, "加密品类板未生成时必须回退到资产榜的加密条目");
  assert.ok(crypto.rows.every((row) => row.series === null),
    "回退来源没有日线，必须如实标为无序列");
  assert.equal(board.status, "ok", "可选文件缺内容不得把整块降级");
  assert.equal(board.failures.length, 0, "加密品类板尚未生成不算管线失败");

  const missing = { ...group, assetRankingCrypto: { data: null, error: new Error("HTTP 404") } };
  assert.ok(categoryOf(buildBoard(missing), "crypto").rows.length > 0,
    "加密品类板文件缺失时同样回退，不留空白品类");

  const filled = { ...group, assetRankingCrypto: { data: {
    updatedAt: "2026-08-25T00:00:00Z",
    asOf: "2026-08-24",
    source: "CoinGecko",
    frequency: "daily",
    assets: [{
      id: "bitcoin", symbol: "BTC", name: "比特币", nameEn: "Bitcoin",
      price: 78916, changePct: 1.44, marketCap: 1580, rank: 1, stale: false,
      dataMeta: { mode: "market", status: "ok", source: "CoinGecko",
        asOf: "2026-08-24T21:54:20.000Z", updatedAt: "2026-08-25T00:00:00Z", frequency: "daily" }
    }],
    history: { dates: ["2026-08-23", "2026-08-24"], series: { BTC: [77000, 78916] },
      source: "CoinGecko", note: "" }
  }, error: null } };
  const upgraded = buildBoard(filled);
  const row = categoryOf(upgraded, "crypto").rows[0];
  assert.equal(row.symbol, "BTC");
  assert.equal(row.changeBasis, "过去24小时");
  assert.equal(row.series.kind, "cryptoBoard", "加密行必须接上同一次取数的日线");
  assert.equal(row.sourceUrl, "https://www.coingecko.com/en/coins/bitcoin");
  assert.ok(upgraded.cryptoHistory && upgraded.cryptoHistory.series.BTC,
    "加密日线必须随分区数据一起交给视图，不额外发请求");
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

/* 迷你走势与脉冲条只是同一批数据的另一种呈现：方向按窗口自己的首尾算，
   缺观测既不当成持平也不借用当日涨跌；分布计数与摘要口径必须对得上。 */
function validateSparkAndPulse(board) {
  assert.equal(sparkDirection([1, 2, 3]), "up");
  assert.equal(sparkDirection([3, 2, 1]), "down");
  assert.equal(sparkDirection([2, 5, 2]), "flat", "首尾相等即为持平，中途高点不改变方向");
  assert.equal(sparkDirection([1]), "unknown", "只有一个观测不足以判定方向");
  assert.equal(sparkDirection([]), "unknown");
  assert.equal(sparkDirection([Number.NaN, 2]), "unknown");

  const window = sliceSeries(["2026-01-02", "2026-01-05", "2026-01-06"], [10, null, 12], 60);
  assert.deepEqual(window.values, [10, 12], "缺观测的日子不得被前向填充进迷你走势");
  assert.equal(sparkDirection(window.values), "up");

  const counts = distribution([
    { change: { direction: "up" } },
    { change: { direction: "down" } },
    { change: { direction: "flat" } },
    { change: { direction: "unknown" } },
    {}
  ]);
  assert.deepEqual(counts, { up: 1, down: 1, flat: 1, unknown: 2, total: 5 },
    "缺涨跌的行必须计入 unknown，不得算作持平");

  const commodity = categoryOf(board, "commodity");
  const live = distribution(commodity.rows);
  assert.equal(live.total, commodity.rows.length);
  assert.equal(live.up, commodity.summary.up, "脉冲条的上涨计数必须与该品类摘要一致");
  assert.equal(live.down, commodity.summary.down, "脉冲条的下跌计数必须与该品类摘要一致");
}

/* 逐行必须链到一个真实网址，而不是弹层：链接要带类别与代码，且能被详情页解析回来。
   月线取点、区间裁剪与区间统计也在这里对齐，避免详情页自己另算一套。 */
function validateQuoteLinks(board) {
  const rows = board.categories.flatMap((category) => category.rows);
  const linked = rows.filter((row) => quoteHref(row));
  assert.ok(linked.length >= rows.length - 2,
    "除极个别没有序列引用的行外，每一行都要能链到独立行情页");
  const gold = rows.filter((row) => row.symbol === "GC=F")[0];
  assert.equal(quoteHref(gold), "quote.html?kind=tracker&symbol=GC%3DF",
    "跨资产行的链接必须带 tracker 类别与转义后的代码");
  const parsed = readQuery(quoteHref(gold).split("?")[1]);
  assert.deepEqual(parsed, { symbol: "GC=F", kind: "tracker", range: "" },
    "详情页必须能把链接解析回同一个标的");
  assert.equal(readQuery("kind=evil&symbol=X").kind, "",
    "未登记的类别一律不接受，避免详情页去读任意路径");

  const stock = rows.filter((row) => row.series && row.series.kind === "company")[0];
  assert.match(quoteHref(stock), /^quote\.html\?kind=company&symbol=/);
  const tenor = rows.filter((row) => row.series && row.series.kind === "curve")[0];
  assert.match(quoteHref(tenor), /^quote\.html\?kind=curve&symbol=DGS/);

  assert.equal(QUOTE_RANGES.length, 8, "区间档位应为 1月/3月/6月/1年/5年/10年/25年/全部");
  assert.deepEqual(QUOTE_RANGES.filter((range) => range.grain === "monthly").map((r) => r.key),
    ["5y", "10y", "25y", "all"], "五年及以上一律读月线");

  const monthly = monthlyPoints({ series: { X: { start: "2024-11", closes: [1, null, 3] } } }, "X");
  assert.deepEqual(monthly, [{ label: "2024-11", value: 1 }, { label: "2025-01", value: 3 }],
    "月线缺月必须整点丢弃，不得前向填充，也不得让后面的月份错位");
  const daily = dailyPoints({ dates: ["2026-01-02", "2026-01-05"], series: { X: [null, 7] } }, "X");
  assert.deepEqual(daily, [{ label: "2026-01-05", value: 7 }]);
  assert.equal(slicePoints(monthly, 1).length, 1);
  assert.equal(slicePoints(monthly, 0).length, 2, "「全部」区间不做截断");

  const stats = rangeStats([{ label: "a", value: 2 }, { label: "b", value: 3 }], "pct");
  assert.equal(stats.change.text, "+50.00%");
  assert.equal(stats.high, 3);
  assert.equal(stats.low, 2);
  const bp = rangeStats([{ label: "a", value: 3.5 }, { label: "b", value: 4.1 }], "bp");
  assert.equal(bp.change.text, "+60 bp", "收益率类的区间变化按基点，不按百分比");
  assert.equal(rangeStats([{ label: "a", value: 1 }], "pct"), null, "只有一个观测时不给区间统计");
}

async function main() {
  const group = await loadGroup();
  const board = buildBoard(group);
  validateFormatting();
  validateSeriesWindow();
  validateCategories(board);
  validateCalibration(board);
  validateProvenance(board, group);
  validateCryptoFallback(group);
  validateSearchAndWatchlist(board);
  validateSparkAndPulse(board);
  validateQuoteLinks(board);
  await validateFailureIsolation(group);
  validateStaleAndMissing(group);
  const counts = board.categories.map((category) => `${category.label}${category.rows.length}`).join(" · ");
  console.log("Finance Terminal category board contract: PASS");
  console.log(`- six categories from existing daily pipelines: ${counts}`);
  console.log("- per-row source / as-of / frequency / stale / change basis: PASS");
  console.log("- listed-only stocks / no proprietary DXY level / reproducible bp change: PASS");
  console.log("- single-pipeline failure isolation / stale propagation / no forward fill: PASS");
  console.log("- literal name/symbol search / starred-first ordering / sanitised watchlist keys: PASS");
  console.log("- per-row sparkline window / direction / pulse distribution vs summary: PASS");
  console.log("- per-row link to a standalone quote page / range grain / monthly gaps: PASS");
}

main().catch((error) => {
  console.error(error.stack || error.message || String(error));
  process.exitCode = 1;
});
