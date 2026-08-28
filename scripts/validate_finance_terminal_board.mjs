#!/usr/bin/env node
/** 品类行情板离线契约：六大类组合、逐行来源与口径、失败隔离与走势区间裁剪。 */

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  BOARD_CATEGORIES,
  COMMODITY_GROUPS,
  STOCK_ROW_LIMIT,
  buildBoard,
  absoluteChange,
  commodityBasis,
  formatAbsolute,
  periodSet,
  spotBasis,
  formatAsOf,
  formatChange,
  formatPrice,
  groupKeyOf,
  groupSummary,
  summarize,
  tenorChangeBp,
  withGroups
} from "../apps/finance-terminal/finance-terminal-board-data.mjs";
import {
  dailyPoints,
  monthlyPoints,
  QUOTE_RANGES,
  rangeStats,
  readQuery,
  sliceMonths,
  slicePoints
} from "../apps/finance-terminal/finance-terminal-quote.mjs";
import {
  periodsFromSeries,
  valueBefore,
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
  /* 商品现货管道是后补的可选文件：首轮日更跑完前它不存在，那不是管线故障。 */
  const commodities = await readJson("apps/commodities/data.json").catch(() => null);
  return {
    assetTracker: { data: assetTracker, error: null },
    companies: { data: companies, error: null },
    assetRanking: { data: assetRanking, error: null },
    assetRankingCrypto: { data: assetRankingCrypto, error: null },
    macro: { data: macro, error: null },
    macroCurve: { data: macroCurve, error: null },
    commodities: commodities ? { data: commodities, error: null } : undefined
  };
}

/* 合成载荷：现货管道首轮跑完前仓库里没有这份文件，但它的解析逻辑必须先测透——
   上一轮的教训正是「等真实数据落地才发现问题」。 */
const SPOT_FIXTURE = Object.freeze({
  updatedAt: "2026-08-28T04:00:00Z",
  asOf: "2026-07-01",
  source: "FRED (U.S. EIA / IMF Primary Commodity Prices)",
  series: [
    { id: "PURANUSDM", name: "铀", group: "energy", unit: "美元/磅", price: 69.2338,
      changePct: 1.25, previousAsOf: "2026-06-01", frequency: "monthly", stale: false,
      dataMeta: { mode: "market", source: "FRED / IMF Primary Commodity Prices",
        asOf: "2026-07-01", updatedAt: "2026-08-28T04:00:00Z", frequency: "monthly", status: "ok" } },
    { id: "DHHNGSP", name: "亨利港天然气现货", group: "energy", unit: "美元/百万英热",
      price: 2.7, changePct: -0.74, previousAsOf: "2026-08-24", frequency: "daily", stale: false,
      dataMeta: { mode: "market", source: "FRED / U.S. EIA", asOf: "2026-08-25",
        updatedAt: "2026-08-28T04:00:00Z", frequency: "daily", status: "ok" } },
    { id: "PMETAINDEXM", name: "IMF金属指数", group: "index", unit: "指数 2016=100",
      price: 226.1695, changePct: 0.9, previousAsOf: "2026-06-01", frequency: "monthly",
      stale: false, dataMeta: { mode: "market", source: "FRED / IMF Primary Commodity Prices",
        asOf: "2026-07-01", updatedAt: "2026-08-28T04:00:00Z", frequency: "monthly", status: "ok" } },
    { id: "PFAKEUSDM", name: "组名未登记的品种", group: "not-a-group", unit: "美元/吨",
      price: 10, changePct: 0, previousAsOf: "2026-06-01", frequency: "monthly", stale: false,
      dataMeta: { mode: "market", source: "FRED / IMF Primary Commodity Prices",
        asOf: "2026-07-01", updatedAt: "2026-08-28T04:00:00Z", frequency: "monthly", status: "ok" } },
    { id: "PNULLUSDM", name: "本轮没取到的品种", group: "grain", unit: "美元/吨", price: null,
      changePct: null, previousAsOf: "", frequency: "monthly", stale: false,
      dataMeta: { mode: "unavailable", source: "FRED / IMF Primary Commodity Prices",
        asOf: null, updatedAt: "2026-08-28T04:00:00Z", frequency: "monthly", status: "error" } }
  ]
});

/* 现货管道并进商品品类：频率、涨跌口径与分组都必须如实，绝不与期货的日频混用。 */
function validateSpotPipeline(group) {
  const board = buildBoard({ ...group, commodities: { data: SPOT_FIXTURE, error: null } });
  const commodity = categoryOf(board, "commodity");
  const byId = new Map(commodity.rows.map((row) => [row.symbol, row]));

  assert.ok(!byId.has("PNULLUSDM"), "本轮没取到的序列不得以空行进入行情板");
  assert.equal(commodity.rows.filter((row) => row.symbol === "PFAKEUSDM")[0].group, "other",
    "上游声明了未登记的组名时必须落进「其他」，不得凭空造出一个分组");

  const uranium = byId.get("PURANUSDM");
  assert.ok(uranium, "现货管道的品种必须进入商品品类");
  assert.equal(uranium.group, "energy", "分组必须采用上游声明的已登记组");
  assert.equal(uranium.frequency, "monthly", "月频必须如实标注");
  assert.equal(uranium.extraText, "月度现货", "月频现货的口径列不得写成期货或日频");
  assert.equal(uranium.changeBasis, "较前一观测 2026-06-01",
    "涨跌口径必须写明是相对上一观测，不得写成当日涨跌");
  assert.equal(uranium.series.grain, "monthly", "月频序列必须指向月频历史桶");
  assert.match(uranium.sourceUrl, /^https:\/\/fred\.stlouisfed\.org\/series\//);
  assert.equal(quoteHref(uranium), "quote.html?kind=commodity&symbol=PURANUSDM");

  const henry = byId.get("DHHNGSP");
  assert.equal(henry.extraText, "现货");
  assert.equal(henry.frequency, "daily");
  assert.equal(henry.series.grain, "daily");
  assert.equal(byId.get("PMETAINDEXM").extraText, "月度指数",
    "官方指数是指数点位，口径列必须与现货区分开");

  assert.equal(spotBasis({ frequency: "weekly" }), "周度均价");
  assert.equal(spotBasis({ frequency: "daily" }), "现货");
  assert.equal(spotBasis({ frequency: "monthly", group: "index" }), "月度指数");

  /* 一类里混着日频期货与月频现货时，摘要必须给数据日区间——只写最新那天会把
     整类说得比实际更新。 */
  assert.match(commodity.summary.asOfRange, /^\d{4}-\d{2}-\d{2} ~ \d{4}-\d{2}-\d{2}$/,
    "商品同时含日频与月频，数据日必须给区间");
  const single = summarize([{ change: { direction: "up" }, status: "ok", asOf: "2026-08-28" }]);
  assert.equal(single.asOfRange, "2026-08-28", "数据日一致时写单日，不要写成区间");
  assert.equal(summarize([]).asOfRange, "", "没有行时不编造数据日");

  /* 期货那半边一条都不能因为现货管道并入而改口径。 */
  assert.equal(byId.get("GC=F").extraText, "期货");
  assert.equal(byId.get("GC=F").changeBasis, "较前一交易日收盘");

  /* 现货管道整份缺失时，期货那半边必须照常显示，且不算管线故障。 */
  const without = buildBoard({ ...group, commodities: undefined });
  assert.equal(without.status, "ok", "可选的现货管道缺失不得把整块降级");
  assert.ok(categoryOf(without, "commodity").rows.length > 0,
    "现货管道缺失时期货那半边必须照常显示");
  assert.ok(categoryOf(without, "commodity").rows.every((row) => row.series.kind !== "commodity"));
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
  assert.deepEqual(monthly, [
    { label: "2024-11", value: 1, at: 24298 },
    { label: "2025-01", value: 3, at: 24300 }
  ], "月线缺月必须整点丢弃，不得前向填充，也不得让后面的月份错位；每点带真实月序号");
  assert.equal(sliceMonths(monthly, 1).length, 1, "月线区间按真实时间窗口裁剪，不按点数");
  assert.equal(sliceMonths(monthly, 3).length, 2);
  assert.equal(sliceMonths(monthly, 0).length, 2, "「全部」不裁剪");
  const daily = dailyPoints({ dates: ["2026-01-02", "2026-01-05"], series: { X: [null, 7] } }, "X");
  assert.deepEqual(daily, [{ label: "2026-01-05", value: 7 }]);
  assert.equal(slicePoints(monthly, 1).length, 1);
  assert.equal(slicePoints(monthly, 0).length, 2, "「全部」区间不做截断");
  assert.deepEqual(QUOTE_RANGES.filter((range) => range.grain === "monthly").map((r) => r.months),
    [60, 120, 300, 0], "长端四档按月数定义窗口");

  const stats = rangeStats([{ label: "a", value: 2 }, { label: "b", value: 3 }], "pct");
  assert.equal(stats.change.text, "+50.00%");
  assert.equal(stats.high, 3);
  assert.equal(stats.low, 2);
  const bp = rangeStats([{ label: "a", value: 3.5 }, { label: "b", value: 4.1 }], "bp");
  assert.equal(bp.change.text, "+60 bp", "收益率类的区间变化按基点，不按百分比");
  assert.equal(rangeStats([{ label: "a", value: 1 }], "pct"), null, "只有一个观测时不给区间统计");
}

/* 商品品类下的二级分组：分组只是静态归类，因此这里守的是「不猜、不丢、不改口径」——
   每一行都要落进一个已登记的组（落进「其他」即说明有新代码没登记，属于要修的事），
   组序稳定、计数可复算，且分组不得改动任何一行的价格、涨跌、数据日与来源。 */
function validateCommodityGroups(board) {
  assert.deepEqual(COMMODITY_GROUPS.map((group) => group.key),
    ["energy", "precious", "base", "grain", "soft", "livestock", "index", "other"],
    "商品二级分组的顺序必须固定");
  assert.deepEqual(COMMODITY_GROUPS.map((group) => group.label),
    ["能源", "贵金属", "工业金属", "农产品", "软商品", "畜牧", "商品指数", "其他"]);

  const commodity = categoryOf(board, "commodity");
  const registered = COMMODITY_GROUPS.map((group) => group.key);
  commodity.rows.forEach((row) => {
    assert.ok(registered.includes(row.group), `${row.name} 的分组未登记：${row.group}`);
    assert.ok(row.groupLabel, `${row.name} 缺少分组显示名`);
    assert.notEqual(row.group, "other",
      `${row.name}（${row.symbol}）没有登记所属分组，请在 COMMODITY_GROUP 里补上`);
  });

  /* 组序：同一个组的行必须连成一段，否则列表里的分组小标题会重复出现。 */
  const seen = [];
  commodity.rows.forEach((row) => {
    if (seen[seen.length - 1] !== row.group) seen.push(row.group);
  });
  assert.equal(seen.length, new Set(seen).size, "同一分组的行必须连续，不得被别的组打断");
  assert.deepEqual(seen, registered.filter((key) => seen.includes(key)),
    "分组在列表里的先后必须与登记顺序一致");

  /* 分组条只列出真的有行的组，计数逐组可复算并且加总等于该品类的行数。 */
  assert.ok(commodity.groups.length >= 2, "商品品类必须至少分出两组才值得摆分组条");
  commodity.groups.forEach((group) => {
    assert.ok(group.count > 0, `${group.label} 没有行就不该出现在分组条上`);
    assert.equal(group.count, commodity.rows.filter((row) => row.group === group.key).length,
      `${group.label} 的计数必须能由行逐条复算`);
  });
  assert.equal(commodity.groups.reduce((sum, group) => sum + group.count, 0), commodity.rows.length,
    "分组计数之和必须等于该品类的行数：不得有行落在所有分组之外");
  board.categories.filter((category) => category.key !== "commodity").forEach((category) => {
    assert.deepEqual(category.groups, [], `${category.label}尚未分组，不得凭空生成分组条`);
  });
  assert.deepEqual(groupSummary("stock", [{ group: "energy" }]), [],
    "没有登记分组的品类一律返回空数组");

  /* 口径列按工具本身取值：期货、官方现货序列与基金份额价格是三种东西。 */
  assert.equal(commodityBasis("CL=F"), "期货");
  assert.equal(commodityBasis("DBC"), "ETF代理");
  assert.equal(commodityBasis(""), "");
  const spot = commodity.rows.filter((row) => row.symbol === "RWTC")[0];
  assert.ok(spot && spot.extraText === "现货" && spot.group === "energy",
    "EIA 官方现货序列必须标成现货并归入能源组");
  /* 商品品类由两条管道并成：口径列必须按行自己的来源判定。跨资产管道的行按代码
     （=F 是期货，其余是基金份额价格），商品现货管道的行按它自己声明的频率与分组。
     用同一个函数校验所有行会把现货说成 ETF 代理——这条断言原本就是那样写窄的。 */
  commodity.rows.forEach((row) => {
    const kind = row.series && row.series.kind;
    if (kind === "tracker") {
      assert.equal(row.extraText, commodityBasis(row.symbol),
        `${row.name} 的口径列必须由代码本身决定，不得一律写成期货`);
    } else if (kind === "commodity") {
      assert.equal(row.extraText, spotBasis({ frequency: row.frequency, group: row.group }),
        `${row.name} 的口径列必须由它自己的频率决定，不得套用期货口径`);
      assert.ok(["daily", "weekly", "monthly"].includes(row.frequency),
        `${row.name} 必须如实标注观测频率`);
      assert.match(row.changeBasis, /^较前一观测 /,
        `${row.name} 的涨跌必须写明相对上一观测，不得写成当日涨跌`);
    }
  });
  /* 两条管道的行必须都在，且都不与对方混淆口径。 */
  const trackerRows = commodity.rows.filter((row) => row.series.kind === "tracker");
  const spotPipeline = commodity.rows.filter((row) => row.series.kind === "commodity");
  assert.ok(trackerRows.length > 0 && spotPipeline.length > 0,
    "商品品类应同时含交易所期货与官方现货两条管道的行");
  assert.ok(trackerRows.every((row) => row.changeBasis === "较前一交易日收盘"),
    "期货那半边的涨跌口径不得被现货管道带偏");
  assert.ok(spotPipeline.every((row) => row.extraText !== "期货"),
    "现货与官方指数不得被标成期货");
  assert.equal(groupKeyOf("index", "^GSPC"), "", "只有商品品类参与二级分组");
  assert.equal(groupKeyOf("commodity", "NEW=F"), "other", "未登记的代码落进「其他」而不是就近归组");

  /* 分组只重排，不改任何一行的事实字段。 */
  const before = [{ symbol: "GC=F", price: 1 }, { symbol: "CL=F", price: 2 }, { symbol: "SI=F", price: 3 }];
  const after = withGroups(before, "commodity");
  assert.deepEqual(after.map((row) => row.symbol), ["CL=F", "GC=F", "SI=F"],
    "重排必须按组序，且同组内保持上游顺序");
  assert.deepEqual(after.map((row) => row.price), [2, 1, 3], "重排不得改动任何一行的数值");
  assert.deepEqual(before.map((row) => row.symbol), ["GC=F", "CL=F", "SI=F"], "不得就地改写入参");
  assert.deepEqual(withGroups(before, "stock"), before, "未分组的品类原样返回");
}

/* 新增的五列：绝对变化必须能由已发布的价与涨跌幅复算，区间涨跌必须要么来自上游、
   要么由站内历史按同一口径算出，算不出就留空——绝不推算，也绝不把月度冒充成周度。 */
function validateExtraColumns(board) {
  /* 绝对变化 = 价 − 价 ÷ (1+涨跌%)，逐行可复现。 */
  assert.ok(Math.abs(absoluteChange(110, 10) - 10) < 1e-9, "涨10%时绝对变化应为10");
  assert.ok(Math.abs(absoluteChange(90, -10) - -10) < 1e-9);
  assert.equal(absoluteChange(100, null), null, "涨跌缺失时不得推算绝对变化");
  assert.equal(absoluteChange(null, 5), null);
  assert.equal(absoluteChange(100, -100), null, "跌满100%不可复算前值");
  assert.equal(formatAbsolute(null), "—", "缺值必须写「—」，不得显示0");
  assert.equal(formatAbsolute(1.5, 2), "+1.50");
  assert.equal(formatAbsolute(-1.5, 2), "-1.50");

  /* 区间集合：上游给什么用什么，非数字一律 null。 */
  assert.deepEqual(periodSet({ w1: 1, m1: null, ytd: "x", y1: 4 }),
    { w1: 1, m1: null, ytd: null, y1: 4 }, "非数字的上游值必须落成 null，不得当成 0");
  assert.deepEqual(periodSet(null), { w1: null, m1: null, ytd: null, y1: null });

  /* 锚点取「该日或之前的最后一个观测」，缺当天观测顺延到更早那个，不前向填充。 */
  const pairs = [["2026-01-02", 10], ["2026-01-09", 11], ["2026-01-20", 12]];
  assert.equal(valueBefore(pairs, "2026-01-15"), 11, "锚点当天无观测时顺延到更早的一个");
  assert.equal(valueBefore(pairs, "2026-01-01"), null, "锚点早于序列起点时没有基准");

  /* 序列不够长就如实返回 null，不拿最早那个点冒充一年前。 */
  const short = periodsFromSeries(["2026-08-20", "2026-08-27"], [100, 110], "daily");
  assert.equal(short.w1, 10, "一周区间在序列覆盖得到时必须算出");
  assert.equal(short.y1, null, "序列不够一年时同比必须留空");
  assert.equal(short.ytd, null, "序列覆盖不到上年末时年初至今必须留空");

  /* 月频序列没有「每周」：往回推7天落到的还是上一个月度观测。 */
  const months = [];
  const values = [];
  for (let index = 0; index < 30; index += 1) {
    const year = 2024 + Math.floor(index / 12);
    const month = (index % 12) + 1;
    months.push(`${year}-${String(month).padStart(2, "0")}-01`);
    values.push(100 + index);
  }
  const monthly = periodsFromSeries(months, values, "monthly");
  assert.equal(monthly.w1, null, "月频序列不得给出周度变化——那其实是月度变化");
  assert.ok(Number.isFinite(monthly.m1) && Number.isFinite(monthly.y1));
  assert.notEqual(periodsFromSeries(months, values, "daily").w1, null,
    "同一序列按日频口径时周度可算，说明留空是频率判定而不是数据缺失");

  /* 逐行字段必须齐备：每一行都要有 changeAbs 与 periods 两个键（值可以是 null）。 */
  board.categories.forEach((category) => {
    category.rows.forEach((row) => {
      assert.ok("changeAbs" in row, `${row.name} 缺少绝对变化字段`);
      assert.ok(row.periods && PERIOD_FIELDS.every((key) => key in row.periods),
        `${row.name} 缺少区间涨跌字段`);
      if (Number.isFinite(row.changeAbs) && Number.isFinite(row.price)) {
        const back = row.price - row.changeAbs;
        assert.ok(Number.isFinite(back) && back !== 0,
          `${row.name} 的绝对变化必须能反推出前值`);
      }
    });
  });
  /* 跨资产管道的行必须直接沿用上游已算好的四档，不该退回现场计算。 */
  const tracker = board.categories.flatMap((category) => category.rows)
    .filter((row) => row.series && row.series.kind === "tracker");
  assert.ok(tracker.length > 0);
  assert.ok(tracker.every((row) => Number.isFinite(row.periods.ytd)),
    "跨资产管道已算好年初至今，行情板必须直接沿用");
}

const PERIOD_FIELDS = Object.freeze(["w1", "m1", "ytd", "y1"]);

async function main() {
  const group = await loadGroup();
  const board = buildBoard(group);
  validateFormatting();
  validateSeriesWindow();
  validateCategories(board);
  validateCommodityGroups(board);
  validateSpotPipeline(group);
  validateExtraColumns(board);
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
  const groups = categoryOf(board, "commodity").groups
    .map((group) => `${group.label}${group.count}`).join(" · ");
  console.log(`- commodity sub-groups, every row registered, counts reproducible: ${groups}`);
  console.log("- spot pipeline merged: per-row frequency / observation-basis change / grain: PASS");
  console.log("- extra columns: reproducible absolute change / period returns / no weekly on monthly: PASS");
}

main().catch((error) => {
  console.error(error.stack || error.message || String(error));
  process.exitCode = 1;
});
