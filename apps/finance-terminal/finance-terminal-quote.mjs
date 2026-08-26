/* 行情详情页：一个标的一个真实网址，直接从站内已在日更的公开管道读取。

   这一页只做三件事：把该标的的当期读数原样摆出来、按区间画它自己的历史序列、
   把逐项来源与口径写清楚。任何区间站内没有序列就如实说没有，不用别的区间顶替，
   也不做插值或前向填充。 */

import {
  formatAsOf,
  formatChange,
  formatMarketCap,
  formatPrice,
  isFiniteNumber,
  priceDecimals,
  tenorChangeBp
} from "./finance-terminal-board-data.mjs";
import { renderChart } from "./finance-terminal-chart.mjs";

const KIND_SOURCES = Object.freeze({
  tracker: {
    data: "../asset-tracker/data.json",
    daily: "../asset-tracker/history.json",
    monthly: "../asset-tracker/history-monthly.json"
  },
  company: {
    data: "../companies/data.json",
    daily: "../companies/history.json",
    monthly: "../companies/history-monthly.json"
  },
  crypto: { data: "../asset-ranking/crypto.json" },
  curve: { data: "../macro-radar/curve.json", monthly: "../macro-radar/curve-monthly.json" },
  macro: { data: "../macro-radar/data.json", daily: "../macro-radar/series.json" }
});

/* 近端四档读日线（约22/66/132/260个交易日），长端四档读月线。
   两份历史各自独立：日线滚动保留约一年，月线保留全部可得月份。 */
export const QUOTE_RANGES = Object.freeze([
  { key: "1m", label: "1个月", grain: "daily", points: 22 },
  { key: "3m", label: "3个月", grain: "daily", points: 66 },
  { key: "6m", label: "6个月", grain: "daily", points: 132 },
  { key: "1y", label: "1年", grain: "daily", points: 260 },
  { key: "5y", label: "5年", grain: "monthly", points: 60 },
  { key: "10y", label: "10年", grain: "monthly", points: 120 },
  { key: "25y", label: "25年", grain: "monthly", points: 300 },
  { key: "all", label: "全部", grain: "monthly", points: 0 }
]);

const cache = new Map();

function loadJson(path) {
  if (!cache.has(path)) {
    cache.set(path, fetch(path, { cache: "no-store" }).then((response) => {
      if (!response || response.ok !== true) throw new Error(`HTTP ${response && response.status}`);
      return response.json();
    }));
  }
  return cache.get(path);
}

export function readQuery(search) {
  const params = new URLSearchParams(String(search || ""));
  const kind = String(params.get("kind") || "").trim();
  return {
    symbol: String(params.get("symbol") || "").trim(),
    kind: Object.prototype.hasOwnProperty.call(KIND_SOURCES, kind) ? kind : ""
  };
}

/* 纯函数：把「共享日期轴 + 逐标的列」的日线历史取成点序列，null 直接丢弃不补。 */
export function dailyPoints(history, symbol) {
  const dates = history && Array.isArray(history.dates) ? history.dates : [];
  const values = history && history.series ? history.series[symbol] : null;
  if (!Array.isArray(values)) return [];
  return dates.map((date, index) => ({ label: date, value: values[index] }))
    .filter((point) => isFiniteNumber(point.value));
}

/* 纯函数：把「起始月 + 逐月收盘」的月线历史取成点序列，缺月同样丢弃不补。 */
export function monthlyPoints(history, symbol) {
  const entry = history && history.series ? history.series[symbol] : null;
  if (!entry || typeof entry.start !== "string" || !Array.isArray(entry.closes)) return [];
  const year = Number(entry.start.slice(0, 4));
  const month = Number(entry.start.slice(5, 7));
  if (!Number.isInteger(year) || !Number.isInteger(month)) return [];
  const base = year * 12 + (month - 1);
  return entry.closes.map((value, index) => {
    const cursor = base + index;
    const label = `${String(Math.floor(cursor / 12)).padStart(4, "0")}-${String(cursor % 12 + 1).padStart(2, "0")}`;
    return { label, value };
  }).filter((point) => isFiniteNumber(point.value));
}

export function slicePoints(points, limit) {
  if (!limit || limit <= 0 || points.length <= limit) return points.slice();
  return points.slice(points.length - limit);
}

/* 纯函数：区间统计。收益率类按基点，其余按百分比，两者都由首尾两个真实观测算出。 */
export function rangeStats(points, mode) {
  if (!Array.isArray(points) || points.length < 2) return null;
  const first = points[0];
  const last = points[points.length - 1];
  const values = points.map((point) => point.value);
  const change = mode === "bp"
    ? formatChange((last.value - first.value) * 100, "bp")
    : formatChange((last.value / first.value - 1) * 100, "pct");
  return {
    change,
    first,
    last,
    high: Math.max(...values),
    low: Math.min(...values),
    count: points.length
  };
}

function trackerInstrument(data, symbol) {
  const rows = data && Array.isArray(data.assets) ? data.assets : [];
  const asset = rows.filter((row) => row && row.symbol === symbol)[0];
  if (!asset) return null;
  const meta = asset.dataMeta || {};
  return {
    name: asset.name,
    nameEn: "",
    symbol,
    categoryLabel: { equity: "指数", commodity: "商品", fx: "外汇", bond: "债券" }[asset.category] || "",
    priceText: formatPrice(asset.price, priceDecimals(asset.price)),
    change: formatChange(asset.returns ? asset.returns.d1 : null, "pct"),
    changeBasis: "较前一交易日收盘",
    unit: "",
    changeMode: "pct",
    asOf: formatAsOf(meta.asOf),
    updatedAt: meta.updatedAt || "",
    frequency: meta.frequency || "",
    sourceName: meta.source || "",
    sourceUrl: `https://finance.yahoo.com/quote/${encodeURIComponent(symbol)}`,
    sourceLabel: "在 Yahoo Finance 打开原始行情页",
    status: asset.stale ? "stale" : (meta.status || "ok"),
    note: asset.note || meta.note || "",
    proxyOf: asset.proxy && asset.proxy.targetSymbol ? asset.proxy.targetSymbol : "",
    extra: asset.returns ? [
      ["近一周", formatChange(asset.returns.w1, "pct").text],
      ["近一月", formatChange(asset.returns.m1, "pct").text],
      ["年初至今", formatChange(asset.returns.ytd, "pct").text],
      ["近一年", formatChange(asset.returns.y1, "pct").text]
    ] : []
  };
}

function companyInstrument(data, symbol) {
  const rows = data && Array.isArray(data.companies) ? data.companies : [];
  const row = rows.filter((item) => item && item.symbol === symbol)[0];
  if (!row) return null;
  const meta = row.dataMeta || {};
  return {
    name: row.name,
    nameEn: row.nameEn || "",
    symbol,
    categoryLabel: "股票",
    priceText: formatPrice(row.price, priceDecimals(row.price)),
    change: formatChange(row.changePct, "pct"),
    changeBasis: "较前一交易日收盘",
    unit: "",
    changeMode: "pct",
    asOf: formatAsOf(meta.asOf),
    updatedAt: meta.updatedAt || "",
    frequency: meta.frequency || "",
    sourceName: meta.source || "",
    sourceUrl: `https://finance.yahoo.com/quote/${encodeURIComponent(symbol)}`,
    sourceLabel: "在 Yahoo Finance 打开原始行情页",
    status: row.stale ? "stale" : (meta.status || "ok"),
    note: meta.note || "",
    proxyOf: "",
    extra: [["市值", formatMarketCap(row.marketCap) || "—"], ["榜内排名", row.rank ? `第 ${row.rank} 位` : "—"]]
  };
}

function cryptoInstrument(data, symbol) {
  const rows = data && Array.isArray(data.assets) ? data.assets : [];
  const row = rows.filter((item) => item && (item.id === symbol || item.symbol === symbol))[0];
  if (!row) return null;
  const meta = row.dataMeta || {};
  return {
    name: row.name,
    nameEn: row.nameEn || "",
    symbol: row.symbol || row.id,
    seriesKey: row.id,
    categoryLabel: "加密",
    priceText: formatPrice(row.price, priceDecimals(row.price)),
    change: formatChange(row.changePct, "pct"),
    changeBasis: data.changeBasis || "过去24小时",
    unit: "",
    changeMode: "pct",
    asOf: formatAsOf(meta.asOf || data.asOf),
    updatedAt: meta.updatedAt || data.updatedAt || "",
    frequency: meta.frequency || data.frequency || "",
    sourceName: meta.source || data.source || "CoinGecko",
    sourceUrl: `https://www.coingecko.com/en/coins/${encodeURIComponent(row.id)}`,
    sourceLabel: "在 CoinGecko 打开原始行情页",
    status: row.stale ? "stale" : (meta.status || "ok"),
    note: meta.note || data.note || "",
    proxyOf: "",
    extra: [["市值", formatMarketCap(row.marketCap) || "—"], ["榜内排名", row.rank ? `第 ${row.rank} 位` : "—"]]
  };
}

function curveInstrument(data, symbol) {
  const tenors = data && Array.isArray(data.tenors) ? data.tenors : [];
  const tenor = tenors.filter((item) => item && item.id === symbol)[0];
  if (!tenor) return null;
  return {
    name: `美国国债收益率 ${tenor.label}`,
    nameEn: symbol,
    symbol,
    categoryLabel: "债券",
    priceText: isFiniteNumber(tenor.value) ? `${tenor.value.toFixed(2)}%` : "—",
    change: formatChange(tenorChangeBp(data.history, symbol), "bp"),
    changeBasis: "较前一观测（基点）",
    unit: "%",
    changeMode: "bp",
    asOf: formatAsOf(tenor.asOf),
    updatedAt: data.updatedAt || "",
    frequency: data.frequency || "",
    sourceName: data.source || "FRED",
    sourceUrl: `https://fred.stlouisfed.org/series/${encodeURIComponent(symbol)}`,
    sourceLabel: "在 FRED 打开官方序列页",
    status: tenor.current ? "ok" : "stale",
    note: data.note || "",
    proxyOf: "",
    extra: []
  };
}

function macroInstrument(data, symbol) {
  const series = data && data.referenceSeries ? data.referenceSeries[symbol] : null;
  if (!series) return null;
  return {
    name: series.name || symbol,
    nameEn: series.nameEn || "",
    symbol,
    categoryLabel: symbol === "RWTC" ? "商品" : "外汇",
    priceText: formatPrice(series.price, priceDecimals(series.price)),
    change: formatChange(series.changePct, "pct"),
    changeBasis: `较前一观测 ${series.previousAsOf || "—"}`,
    unit: "",
    changeMode: "pct",
    asOf: formatAsOf(series.asOf),
    updatedAt: series.updatedAt || "",
    frequency: series.frequency || "",
    sourceName: series.source && series.source.name ? series.source.name : "",
    sourceUrl: series.source && series.source.url ? series.source.url : "",
    sourceLabel: "打开官方序列页",
    status: series.status === "ok" ? "ok" : (series.status || "unknown"),
    note: series.note || "",
    proxyOf: "",
    extra: []
  };
}

const INSTRUMENT_READERS = Object.freeze({
  tracker: trackerInstrument,
  company: companyInstrument,
  crypto: cryptoInstrument,
  curve: curveInstrument,
  macro: macroInstrument
});

export async function loadInstrument(kind, symbol) {
  const paths = KIND_SOURCES[kind];
  if (!paths) throw new Error("未知的标的类别");
  const data = await loadJson(paths.data);
  const instrument = INSTRUMENT_READERS[kind](data, symbol);
  if (!instrument) throw new Error("站内当前的日更快照里没有这个标的");
  const seriesKey = instrument.seriesKey || symbol;
  const daily = await (async () => {
    if (kind === "crypto") return dailyPoints(data.history, seriesKey);
    if (kind === "curve") {
      const values = data.history && data.history.values ? data.history.values[symbol] : null;
      return dailyPoints({ dates: data.history && data.history.dates, series: { [symbol]: values } }, symbol);
    }
    if (!paths.daily) return [];
    try {
      const file = await loadJson(paths.daily);
      if (kind === "macro") {
        const entry = file.series ? file.series[symbol] : null;
        return dailyPoints({ dates: entry && entry.dates, series: { [symbol]: entry && entry.values } }, symbol);
      }
      return dailyPoints(file, seriesKey);
    } catch (error) {
      return [];
    }
  })();
  const monthly = await (async () => {
    if (!paths.monthly) return [];
    try {
      return monthlyPoints(await loadJson(paths.monthly), seriesKey);
    } catch (error) {
      return [];
    }
  })();
  return { instrument, daily, monthly };
}

function text(parent, tag, className, content) {
  const node = parent.ownerDocument.createElement(tag);
  if (className) node.className = className;
  if (content !== undefined && content !== null) node.textContent = content;
  parent.appendChild(node);
  return node;
}

function statusChip(status) {
  if (status === "stale") return { className: "quote-chip quote-chip-stale", label: "STALE · 上游未刷新" };
  if (status === "partial") return { className: "quote-chip quote-chip-stale", label: "PARTIAL · 部分口径缺失" };
  if (status === "ok") return { className: "quote-chip quote-chip-ok", label: "ACTIVE · 本轮已刷新" };
  return { className: "quote-chip", label: "UNKNOWN · 上游未声明状态" };
}

function metaRow(list, key, value) {
  if (!value) return;
  const row = text(list, "div", "quote-meta-row");
  text(row, "dt", "", key);
  text(row, "dd", "", value);
}

export function renderQuote(document, root, payload) {
  const { instrument, daily, monthly } = payload;
  root.textContent = "";
  root.setAttribute("aria-busy", "false");
  document.title = `${instrument.name} 行情详情 · Ooglex金融终端`;

  const head = text(root, "section", "quote-head");
  const nameRow = text(head, "div", "quote-name");
  text(nameRow, "h1", "", instrument.name);
  text(nameRow, "span", "quote-symbol", instrument.symbol);
  if (instrument.categoryLabel) text(nameRow, "span", "quote-tag", instrument.categoryLabel);
  if (instrument.nameEn) text(nameRow, "span", "quote-symbol", instrument.nameEn);

  const priceRow = text(head, "div", "quote-price-row");
  text(priceRow, "strong", "quote-price", instrument.priceText);
  const change = text(priceRow, "span", `quote-change quote-change-${instrument.change.direction}`);
  text(change, "i", "", instrument.change.arrow).style.fontStyle = "normal";
  text(change, "span", "", instrument.change.text);
  text(priceRow, "span", "quote-basis", instrument.changeBasis);

  const chips = text(head, "div", "quote-chips");
  const chip = statusChip(instrument.status);
  text(chips, "span", chip.className, chip.label);
  if (instrument.asOf) text(chips, "span", "quote-chip", `数据日 ${instrument.asOf}`);
  if (instrument.frequency) text(chips, "span", "quote-chip", `频率 ${instrument.frequency}`);
  if (instrument.sourceName) text(chips, "span", "quote-chip", `来源 ${instrument.sourceName}`);
  if (instrument.proxyOf) text(chips, "span", "quote-chip", `代理标的 ${instrument.proxyOf}`);

  const panel = text(root, "section", "quote-panel");
  const tabs = text(panel, "div", "quote-ranges");
  tabs.setAttribute("role", "group");
  tabs.setAttribute("aria-label", "走势区间");
  const chartHost = text(panel, "div", "quote-chart-host");
  const stats = text(panel, "div", "quote-stats");

  const decimals = instrument.changeMode === "bp" ? 2 : priceDecimals(daily.length
    ? daily[daily.length - 1].value : 1);
  const format = (value) => value.toLocaleString("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals
  });

  function pointsFor(range) {
    const source = range.grain === "daily" ? daily : monthly;
    return slicePoints(source, range.points);
  }

  function paint(range) {
    Array.from(tabs.children).forEach((button) => {
      button.setAttribute("aria-pressed", button.dataset.range === range.key ? "true" : "false");
    });
    const points = pointsFor(range);
    renderChart(document, chartHost, {
      points,
      format,
      unit: instrument.unit,
      label: `${instrument.name} ${range.label}走势，共 ${points.length} 个站内观测`,
      emptyText: range.grain === "monthly"
        ? "站内还没有该标的的月线序列，这一档区间暂时画不出来；管道每日更新，取到后会自动出现。"
        : "站内还没有该标的的日线序列，这一档区间暂时画不出来。"
    });
    stats.textContent = "";
    const summary = rangeStats(points, instrument.changeMode);
    if (!summary) return;
    const changeCell = text(stats, "div", `quote-stat quote-stat-${summary.change.direction}`);
    text(changeCell, "span", "", `${range.label}区间变化`);
    text(changeCell, "b", "", summary.change.text);
    [["区间最高", format(summary.high)], ["区间最低", format(summary.low)],
      ["观测点数", String(summary.count)],
      ["区间起止", `${summary.first.label} → ${summary.last.label}`]].forEach(([key, value]) => {
      const cell = text(stats, "div", "quote-stat");
      text(cell, "span", "", key);
      text(cell, "b", "", value);
    });
  }

  let initial = null;
  QUOTE_RANGES.forEach((range) => {
    const button = text(tabs, "button", "quote-range", range.label);
    button.type = "button";
    button.dataset.range = range.key;
    const available = pointsFor(range).length >= 2;
    if (!available) {
      button.disabled = true;
      button.title = "站内暂无该区间的历史序列";
    } else if (!initial) {
      initial = range;
    }
    button.setAttribute("aria-pressed", "false");
    button.addEventListener("click", () => { paint(range); });
  });
  const preferred = QUOTE_RANGES.filter((range) => range.key === "1y" && pointsFor(range).length >= 2)[0];
  paint(preferred || initial || QUOTE_RANGES[0]);

  const meta = text(root, "section", "quote-panel");
  text(meta, "h2", "quote-symbol", "逐项来源与口径");
  const list = text(meta, "dl", "quote-meta");
  metaRow(list, "来源", instrument.sourceName);
  metaRow(list, "数据日", instrument.asOf);
  metaRow(list, "更新时间", instrument.updatedAt);
  metaRow(list, "频率", instrument.frequency);
  metaRow(list, "涨跌口径", instrument.changeBasis);
  (instrument.extra || []).forEach(([key, value]) => { metaRow(list, key, value); });
  metaRow(list, "口径说明", instrument.note);
  metaRow(list, "近端序列", daily.length
    ? `站内日线 ${daily.length} 个交易日（${daily[0].label} → ${daily[daily.length - 1].label}）`
    : "站内暂无日线序列");
  metaRow(list, "长周期序列", monthly.length
    ? `站内月线 ${monthly.length} 个月（${monthly[0].label} → ${monthly[monthly.length - 1].label}）`
    : "站内暂无月线序列");
  if (instrument.sourceUrl) {
    const link = text(meta, "a", "quote-source-link", `${instrument.sourceLabel} →`);
    link.href = instrument.sourceUrl;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
  }
  text(meta, "p", "quote-note",
    "本页所有数值都取自站内每日运行的公开管道快照，不在浏览器里调用任何外部行情接口；"
    + "缺观测的位置一律留空，不插值、不前向填充，也不用其他标的顶替。");
}

export function renderQuoteError(document, root, message) {
  root.textContent = "";
  root.setAttribute("aria-busy", "false");
  const box = text(root, "div", "quote-error");
  text(box, "p", "", message);
  const back = text(box, "a", "quote-source-link", "← 返回品类行情");
  back.href = "index.html#board-section";
}

async function start() {
  const root = document.getElementById("quote-root");
  if (!root) return;
  const query = readQuery(window.location.search);
  if (!query.symbol || !query.kind) {
    renderQuoteError(document, root, "网址里缺少标的代码或类别，请从品类行情列表点进来。");
    return;
  }
  try {
    renderQuote(document, root, await loadInstrument(query.kind, query.symbol));
  } catch (error) {
    renderQuoteError(document, root,
      `暂时读不到这个标的：${error && error.message ? error.message : "未知错误"}。`);
  }
}

if (typeof document !== "undefined" && typeof window !== "undefined" && window.location) {
  start();
}
