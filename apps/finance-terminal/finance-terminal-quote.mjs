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
import { formatChangePct, formatLike, freshnessText, newerThan, startLive, usableSnapshot }
  from "./finance-terminal-live.mjs";

const KIND_SOURCES = Object.freeze({
  tracker: {
    data: "../asset-tracker/data.json",
    daily: "../asset-tracker/history.json",
    monthly: "../asset-tracker/history-monthly.json"
  },
  /* 公司的完整历史按市值名次每 100 家一片；逐行的 historyShard 指明在第几片。
     行情页只取自己那一片（约170KB），不把 500 家的整份历史拉下来。 */
  company: {
    data: "../companies/data.json",
    daily: "../companies/history.json",
    monthly: "../companies/history-monthly.json",
    sharded: true
  },
  crypto: { data: "../asset-ranking/crypto.json" },
  curve: { data: "../macro-radar/curve.json", monthly: "../macro-radar/curve-monthly.json" },
  macro: { data: "../macro-radar/data.json", daily: "../macro-radar/series.json" },
  /* 商品现货管道的日频与月频历史在同一个文件里分两个桶，因此 daily 与 monthly 指向同一份。 */
  commodity: {
    data: "../commodities/data.json",
    daily: "../commodities/history.json",
    monthly: "../commodities/history.json"
  },
  /* 各国主权债的日频与月频历史同样在一个文件里分两个桶，与商品现货同一种结构。 */
  bond: {
    data: "../bonds/data.json",
    daily: "../bonds/history.json",
    monthly: "../bonds/history.json"
  }
});

/* 近端四档读日线（约22/66/132/260个交易日），长端四档读月线。
   两份历史各自独立：日线滚动保留约一年，月线保留全部可得月份。 */
export const QUOTE_RANGES = Object.freeze([
  { key: "1m", label: "1个月", grain: "daily", points: 22 },
  { key: "3m", label: "3个月", grain: "daily", points: 66 },
  { key: "6m", label: "6个月", grain: "daily", points: 132 },
  { key: "1y", label: "1年", grain: "daily", points: 260 },
  { key: "5y", label: "5年", grain: "monthly", months: 60 },
  { key: "10y", label: "10年", grain: "monthly", months: 120 },
  { key: "25y", label: "25年", grain: "monthly", months: 300 },
  { key: "all", label: "全部", grain: "monthly", months: 0 }
]);

/* 4 小时线只有跨资产、公司榜与加密这三类有：它们的报价源头确实存在小时级观测。
   FRED 的商品现货/官方指数与美债收益率曲线在源头就没有小时数据，这几类连这份文件
   都不去读，页面上也不会出现粒度切换——给它们画 4 小时线只能靠插值，那是伪造。 */
const HOURLY_PATH = "../asset-tracker/hourly.json";
const HOURLY_KINDS = Object.freeze({ tracker: true, company: true, crypto: true });

/* 4 小时线的区间按天数而不是按点数：各市场每天成桶数不同（加密全天候 6 个、
   美股约 2 个），按点数裁会让「1周」在不同市场对应完全不同的真实跨度。 */
export const FOUR_HOUR_RANGES = Object.freeze([
  { key: "4h-3d", label: "3天", grain: "fourHour", days: 3 },
  { key: "4h-1w", label: "1周", grain: "fourHour", days: 7 },
  { key: "4h-2w", label: "2周", grain: "fourHour", days: 14 },
  { key: "4h-1m", label: "1个月", grain: "fourHour", days: 30 }
]);

const ALL_RANGES = QUOTE_RANGES.concat(FOUR_HOUR_RANGES);

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
  const range = String(params.get("range") || "").trim();
  return {
    symbol: String(params.get("symbol") || "").trim(),
    kind: Object.prototype.hasOwnProperty.call(KIND_SOURCES, kind) ? kind : "",
    range: ALL_RANGES.some((entry) => entry.key === range) ? range : ""
  };
}

/* 纯函数：按片号改写历史文件路径。第 1 片沿用原文件名，其余加 -N，与管道一致。
   片号缺失或不是大于 1 的整数时退回第 1 片：宁可多取一片取不到，也不要拼出乱路径。 */
export function shardPath(path, shard) {
  const index = Number(shard);
  if (!Number.isInteger(index) || index <= 1) return path;
  return path.replace(/\.json$/, `-${index}.json`);
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
    return { label, value, at: cursor };
  }).filter((point) => isFiniteNumber(point.value));
}

/* 纯函数：商品现货管道的月频历史用「共享日期轴 + 逐序列列」，与公司/跨资产那份
   {start, closes} 压缩格式不同；这里按同一套月序号口径转成月线点，缺观测整点丢弃。 */
export function monthlyPointsFromAxis(history, symbol) {
  const dates = history && Array.isArray(history.dates) ? history.dates : [];
  const values = history && history.series ? history.series[symbol] : null;
  if (!Array.isArray(values)) return [];
  return dates.map((date, index) => {
    const year = Number(String(date).slice(0, 4));
    const month = Number(String(date).slice(5, 7));
    if (!Number.isInteger(year) || !Number.isInteger(month) || month < 1 || month > 12) return null;
    return {
      label: `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}`,
      value: values[index],
      at: year * 12 + (month - 1)
    };
  }).filter((point) => point && isFiniteNumber(point.value));
}

/* 纯函数：把「共享时间轴 + 逐标的列」的 4 小时线取成点序列，缺观测丢弃不补。
   时点一律按 UTC 标注——桶本身就是按 UTC 对齐切出来的，换成浏览器本地时区会让
   标签和分桶口径对不上（同一根柱子在不同时区显示成不同的整点）。 */
export function hourlyPoints(file, symbol) {
  const axis = file && Array.isArray(file.axis) ? file.axis : [];
  const values = file && file.series ? file.series[symbol] : null;
  if (!Array.isArray(values)) return [];
  return axis.map((stamp, index) => ({
    label: hourLabel(stamp),
    value: values[index],
    at: Number(stamp)
  })).filter((point) => isFiniteNumber(point.value) && Number.isFinite(point.at));
}

function hourLabel(stamp) {
  const at = new Date(Number(stamp) * 1000);
  const pad = (value) => String(value).padStart(2, "0");
  return `${pad(at.getUTCMonth() + 1)}-${pad(at.getUTCDate())} ${pad(at.getUTCHours())}:00`;
}

/* 纯函数：4 小时线按真实时间窗口裁剪，理由同 FOUR_HOUR_RANGES 上的注释。 */
export function sliceDays(points, days) {
  if (!days || days <= 0 || !points.length) return points.slice();
  const last = points[points.length - 1].at;
  if (!Number.isFinite(last)) return points.slice();
  const floor = last - days * 86400;
  return points.filter((point) => Number.isFinite(point.at) && point.at > floor);
}

export function slicePoints(points, limit) {
  if (!limit || limit <= 0 || points.length <= limit) return points.slice();
  return points.slice(points.length - limit);
}

/* 月线按真实时间窗口裁剪，而不是按点数：数据源对超长区间会自行降采样，
   按点数裁「25年」在季度点上会一路裁到七十多年前，窗口名与实际区间对不上。 */
export function sliceMonths(points, months) {
  if (!months || months <= 0 || !points.length) return points.slice();
  const last = points[points.length - 1].at;
  if (!Number.isFinite(last)) return points.slice();
  return points.filter((point) => Number.isFinite(point.at) && point.at > last - months);
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
    categoryLabel: "公司",
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
    /* 完整历史按市值名次分片存放，这一行落在第几片由管道写在 data.json 里。 */
    historyShard: row.historyShard,
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
    seriesKey: row.symbol || row.id,
    categoryLabel: "加密",
    priceText: formatPrice(row.price, priceDecimals(row.price)),
    change: formatChange(row.changePct, "pct"),
    changeBasis: "过去24小时",
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

/* 商品现货与官方指数：涨跌一律相对该序列自己的上一观测，频率逐条如实标注——
   多数是月频，写成「当日涨跌」就是把月频说成了日频。 */
function commodityInstrument(data, symbol) {
  const rows = data && Array.isArray(data.series) ? data.series : [];
  const row = rows.filter((item) => item && item.id === symbol)[0];
  if (!row || !isFiniteNumber(row.price)) return null;
  const meta = row.dataMeta || {};
  const frequency = row.frequency || meta.frequency || "";
  return {
    name: row.name,
    nameEn: "",
    symbol,
    categoryLabel: "商品",
    grain: frequency === "monthly" ? "monthly" : "daily",
    priceText: formatPrice(row.price, priceDecimals(row.price)),
    change: formatChange(row.changePct, "pct"),
    changeBasis: `较前一观测 ${row.previousAsOf || "—"}`,
    unit: row.unit || "",
    changeMode: "pct",
    asOf: formatAsOf(meta.asOf),
    updatedAt: meta.updatedAt || data.updatedAt || "",
    frequency,
    sourceName: meta.source || data.source || "",
    sourceUrl: `https://fred.stlouisfed.org/series/${encodeURIComponent(symbol)}`,
    sourceLabel: "在 FRED 打开官方序列页",
    status: row.stale ? "stale" : (meta.status || "ok"),
    note: row.note || meta.note || "",
    proxyOf: "",
    extra: []
  };
}

/* 频率是机器可读的英文标记（daily/weekly/monthly/irregular），页面上要读成中文。
   映射之外的取值原样显示，不猜也不吞——上游多出一种频率时页面上看得见，
   而不是被悄悄显示成别的什么。 */
const FREQUENCY_LABEL = Object.freeze({
  daily: "日频", weekly: "周频", monthly: "月频", irregular: "不定期", mixed: "多种频率"
});

export function describeFrequency(value) {
  const key = String(value || "");
  return FREQUENCY_LABEL[key] || key;
}

/* 各国十年期国债收益率。涨跌是基点而不是百分比，与美债曲线同一口径；
   频率逐行沿用上游，月频序列在页面上就写成月频。 */
function bondInstrument(data, symbol) {
  const rows = data && Array.isArray(data.series) ? data.series : [];
  const row = rows.filter((item) => item && item.id === symbol)[0];
  if (!row || !isFiniteNumber(row.price)) return null;
  const meta = row.dataMeta || {};
  const frequency = row.frequency || meta.frequency || "";
  const ecb = meta.source === "ECB Data Portal";
  return {
    name: row.name,
    nameEn: row.nameEn || "",
    symbol,
    categoryLabel: "债券",
    grain: frequency === "monthly" ? "monthly" : "daily",
    priceText: `${row.price.toFixed(2)}%`,
    change: formatChange(row.changeBp, "bp"),
    changeBasis: `较前一观测 ${row.previousAsOf || "—"}（基点）`,
    unit: row.unit || "年化收益率",
    changeMode: "bp",
    asOf: formatAsOf(meta.asOf),
    updatedAt: meta.updatedAt || data.updatedAt || "",
    frequency,
    sourceName: meta.source || data.source || "",
    sourceUrl: ecb ? "https://data.ecb.europa.eu/"
      : `https://fred.stlouisfed.org/series/${encodeURIComponent(symbol)}`,
    sourceLabel: ecb ? "在欧洲央行数据门户打开" : "在 FRED 打开官方序列页",
    status: row.stale ? "stale" : (meta.status || "ok"),
    note: row.note || meta.note || "",
    proxyOf: "",
    extra: []
  };
}

const INSTRUMENT_READERS = Object.freeze({
  tracker: trackerInstrument,
  company: companyInstrument,
  crypto: cryptoInstrument,
  curve: curveInstrument,
  macro: macroInstrument,
  commodity: commodityInstrument,
  bond: bondInstrument
});

export async function loadInstrument(kind, symbol) {
  const paths = KIND_SOURCES[kind];
  if (!paths) throw new Error("未知的标的类别");
  const data = await loadJson(paths.data);
  const instrument = INSTRUMENT_READERS[kind](data, symbol);
  if (!instrument) throw new Error("站内当前的日更快照里没有这个标的");
  const seriesKey = instrument.seriesKey || symbol;
  const dailyTask = (async () => {
    if (kind === "crypto") return dailyPoints(data.history, seriesKey);
    if (kind === "curve") {
      const values = data.history && data.history.values ? data.history.values[symbol] : null;
      return dailyPoints({ dates: data.history && data.history.dates, series: { [symbol]: values } }, symbol);
    }
    if (!paths.daily) return [];
    /* 月频序列没有日线：把 400 个月度观测塞进「1个月/3个月」这几档会把月频说成日频，
       因此这里如实返回空，长端区间读月线那一支。日频/周频序列两个桶都有，八档都能开。 */
    if ((kind === "commodity" || kind === "bond") && instrument.grain === "monthly") return [];
    try {
      const file = await loadJson(
        paths.sharded ? shardPath(paths.daily, instrument.historyShard) : paths.daily);
      if (kind === "commodity" || kind === "bond") return dailyPoints(file.daily, seriesKey);
      if (kind === "macro") {
        const entry = file.series ? file.series[symbol] : null;
        return dailyPoints({ dates: entry && entry.dates, series: { [symbol]: entry && entry.values } }, symbol);
      }
      return dailyPoints(file, seriesKey);
    } catch (error) {
      return [];
    }
  })();
  const monthlyTask = (async () => {
    if (!paths.monthly) return [];
    try {
      const file = await loadJson(
        paths.sharded ? shardPath(paths.monthly, instrument.historyShard) : paths.monthly);
      /* 长端区间一律读月频桶：月频序列本来就在那里，日频序列另有一份官方月末聚合。
         桶里没有这条序列就返回空，长端几档自然禁用——不拿日线冒充月线。 */
      if (kind === "commodity" || kind === "bond") return monthlyPointsFromAxis(file.monthly, seriesKey);
      return monthlyPoints(file, seriesKey);
    } catch (error) {
      return [];
    }
  })();
  /* 4 小时线只对源头确有小时观测的类别去取：其余类别连这个请求都不发。 */
  const hourlyTask = (async () => {
    if (!HOURLY_KINDS[kind]) return { points: [], file: null };
    try {
      const file = await loadJson(HOURLY_PATH);
      return { points: hourlyPoints(file, seriesKey), file };
    } catch (error) {
      return { points: [], file: null };
    }
  })();
  const [daily, monthly, hourly] = await Promise.all([dailyTask, monthlyTask, hourlyTask]);
  return { instrument, daily, monthly, hourly };
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

export function renderQuote(document, root, payload, wanted) {
  const { instrument, daily, monthly } = payload;
  const hourly = (payload.hourly && payload.hourly.points) || [];
  const hourlyFile = (payload.hourly && payload.hourly.file) || null;
  root.textContent = "";
  root.setAttribute("aria-busy", "false");
  document.title = `${instrument.name} 行情详情 · Ooglex金融终端`;

  const head = text(root, "section", "quote-head");
  const nameRow = text(head, "div", "quote-name");
  text(nameRow, "h1", "", instrument.name);
  text(nameRow, "span", "quote-symbol", instrument.symbol);
  if (instrument.categoryLabel) text(nameRow, "span", "quote-tag", instrument.categoryLabel);
  if (instrument.nameEn && instrument.nameEn !== instrument.symbol) {
    text(nameRow, "span", "quote-symbol", instrument.nameEn);
  }

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
  if (instrument.frequency) text(chips, "span", "quote-chip", `频率 ${describeFrequency(instrument.frequency)}`);
  if (instrument.sourceName) text(chips, "span", "quote-chip", `来源 ${instrument.sourceName}`);
  if (instrument.proxyOf) text(chips, "span", "quote-chip", `代理标的 ${instrument.proxyOf}`);

  const panel = text(root, "section", "quote-panel");
  /* 粒度切换只在站内确实有这条 4 小时线时出现：没有小时观测的标的（FRED 商品现货、
     美债曲线）连这个按钮都不给，而不是给一个点开只有空图的选项。 */
  const grains = [{ key: "daily", label: "日线", ranges: QUOTE_RANGES }];
  if (hourly.length >= 2) {
    grains.push({ key: "4h", label: "4小时", ranges: FOUR_HOUR_RANGES });
  }
  const grainBar = grains.length > 1 ? text(panel, "div", "quote-grains") : null;
  if (grainBar) {
    grainBar.setAttribute("role", "group");
    grainBar.setAttribute("aria-label", "走势粒度");
  }
  const tabs = text(panel, "div", "quote-ranges");
  tabs.setAttribute("role", "group");
  tabs.setAttribute("aria-label", "走势区间");
  const chartHost = text(panel, "div", "quote-chart-host");
  const grainNote = text(panel, "p", "quote-grain-note");
  const stats = text(panel, "div", "quote-stats");

  const sample = daily.length ? daily : hourly;
  const decimals = instrument.changeMode === "bp" ? 2 : priceDecimals(sample.length
    ? sample[sample.length - 1].value : 1);
  const format = (value) => value.toLocaleString("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals
  });

  function pointsFor(range) {
    if (range.grain === "fourHour") return sliceDays(hourly, range.days);
    return range.grain === "daily"
      ? slicePoints(daily, range.points)
      : sliceMonths(monthly, range.months);
  }

  /* 4 小时线的每一句披露都取自数据文件自报的字段，不在页面上另写一套说法：
     它是本站聚合的、不是交易所原生的 4 小时 K 线，时间标签是 UTC，刷新有周期。
     加密的报价在站内来自 CoinGecko 而这条线来自 Yahoo，来源不同就明说。 */
  function aggregatedFrom(file) {
    /* 文件里记的是机器可读的 "1h"，页面上要写成中文的「1 小时」。 */
    const raw = file && file.aggregatedFrom;
    return raw === "1h" ? "1 小时" : (raw ? `${raw} ` : "1 小时");
  }

  function describeGrain(range) {
    grainNote.textContent = "";
    if (!hourlyFile || range.grain !== "fourHour") return;
    const meta = (hourlyFile.meta || {})[instrument.seriesKey || instrument.symbol] || {};
    const cadence = Number.isFinite(hourlyFile.cadenceHours) ? hourlyFile.cadenceHours : null;
    const lines = [`4小时线由本站把 ${hourlyFile.source || "上游"} 的 `
      + `${aggregatedFrom(hourlyFile)}行情按 UTC 对齐聚合而成（每桶取桶内最后一个收盘），`
      + "不是交易所原生的 4 小时 K 线，与交易所自己划分的 4 小时周期不一定对齐；"
      + "休市缺口如实留空，不插值、不前向填充。图上时间标签为 UTC。"
      + (cadence ? `约 ${cadence} 小时刷新一次，不是实时行情。` : "不是实时行情。")];
    if (instrument.sourceName && hourlyFile.source
        && instrument.sourceName !== hourlyFile.source) {
      lines.push(`本页报价来自 ${instrument.sourceName}，这条 4 小时线取自 `
        + `${hourlyFile.source}${meta.source ? `（代码 ${meta.source}）` : ""}`
        + "——同一标的、两个来源，数值可能不完全一致。");
    }
    if (meta.stale === true) {
      lines.push("这条序列本轮未取到，显示的是上一轮的观测，没有补造新点。");
    }
    grainNote.textContent = lines.join("");
  }

  function paint(range) {
    Array.from(tabs.children).forEach((button) => {
      button.setAttribute("aria-pressed", button.dataset.range === range.key ? "true" : "false");
    });
    const points = pointsFor(range);
    const grain = range.grain === "fourHour" ? "个4小时桶" : "个站内观测";
    renderChart(document, chartHost, {
      points,
      format,
      unit: instrument.unit,
      label: `${instrument.name} ${range.label}走势，共 ${points.length} ${grain}`,
      emptyText: range.grain === "monthly"
        ? "站内还没有该标的的月线序列，这一档区间暂时画不出来；管道每日更新，取到后会自动出现。"
        : (range.grain === "fourHour"
          ? "站内还没有该标的这一档区间的 4 小时观测，这里不画任何推断曲线。"
          : "站内还没有该标的的日线序列，这一档区间暂时画不出来。")
    });
    describeGrain(range);
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

  function rememberRange(key) {
    if (!window.history || typeof window.history.replaceState !== "function") return;
    const url = new URL(window.location.href);
    url.searchParams.set("range", key);
    window.history.replaceState(null, "", url.toString());
  }

  /* 换粒度就整条区间条重建：两种粒度的档位本来就不是同一套，
     日线是1个月到全部，4小时是3天到1个月，混在一条上读不出来是哪种粒度。 */
  function showGrain(grain, askedKey) {
    if (grainBar) {
      Array.from(grainBar.children).forEach((button) => {
        button.setAttribute("aria-pressed", button.dataset.grain === grain.key ? "true" : "false");
      });
    }
    tabs.textContent = "";
    let initial = null;
    grain.ranges.forEach((range) => {
      const button = text(tabs, "button", "quote-range", range.label);
      button.type = "button";
      button.dataset.range = range.key;
      if (pointsFor(range).length < 2) {
        button.disabled = true;
        button.title = "站内暂无该区间的历史序列";
      } else if (!initial) {
        initial = range;
      }
      button.setAttribute("aria-pressed", "false");
      button.addEventListener("click", () => {
        paint(range);
        rememberRange(range.key);
      });
    });
    /* 日线默认停在1年、4小时默认停在1周；网址带 range 时按网址来，
       分享出去的链接能落回同一种粒度的同一档区间。 */
    const usable = (key) => grain.ranges.filter(
      (range) => range.key === key && pointsFor(range).length >= 2)[0];
    paint(usable(askedKey) || usable(grain.key === "4h" ? "4h-1w" : "1y")
      || initial || grain.ranges[0]);
  }

  grains.forEach((grain) => {
    if (!grainBar) return;
    const button = text(grainBar, "button", "quote-grain", grain.label);
    button.type = "button";
    button.dataset.grain = grain.key;
    button.setAttribute("aria-pressed", "false");
    button.addEventListener("click", () => { showGrain(grain, ""); });
  });
  /* 区间键两套之间不重名，因此粒度可以直接由网址里的 range 反推，不必另开一个参数。 */
  const wantedGrain = FOUR_HOUR_RANGES.some((range) => range.key === wanted) ? "4h" : "daily";
  showGrain(grains.filter((grain) => grain.key === wantedGrain)[0] || grains[0], wanted);

  /* 盘中活更新：只有跨资产管道的标的才有盘中层，且盘中报价必须比本页显示的
     数据日更新才会覆盖。覆盖后价格与涨跌都改成盘中口径，并在标签里写明。 */
  if (payload.kind === "tracker") startQuoteLive(document, instrument, priceRow, change, chips);

  const meta = text(root, "section", "quote-panel");
  text(meta, "h2", "quote-symbol", "逐项来源与口径");
  const list = text(meta, "dl", "quote-meta");
  metaRow(list, "来源", instrument.sourceName);
  metaRow(list, "数据日", instrument.asOf);
  metaRow(list, "更新时间", instrument.updatedAt);
  metaRow(list, "频率", describeFrequency(instrument.frequency));
  metaRow(list, "涨跌口径", instrument.changeBasis);
  (instrument.extra || []).forEach(([key, value]) => { metaRow(list, key, value); });
  metaRow(list, "口径说明", instrument.note);
  metaRow(list, "近端序列", daily.length
    ? `站内日线 ${daily.length} 个交易日（${daily[0].label} → ${daily[daily.length - 1].label}）`
    : "站内暂无日线序列");
  metaRow(list, "长周期序列", monthly.length
    ? `站内月线 ${monthly.length} 个月（${monthly[0].label} → ${monthly[monthly.length - 1].label}）`
    : "站内暂无月线序列");
  metaRow(list, "4小时线", hourly.length
    ? `站内 ${hourly.length} 个 4 小时桶（UTC ${hourly[0].label} → ${hourly[hourly.length - 1].label}），`
      + `由 ${aggregatedFrom(hourlyFile)}行情聚合，非交易所原生 K 线`
    : "该标的在源头没有小时级观测，站内不提供 4 小时线");
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

function startQuoteLive(document, instrument, priceRow, changeNode, chips) {
  const priceNode = priceRow.querySelector(".quote-price");
  const chip = document.createElement("span");
  chip.className = "quote-chip";
  chips.appendChild(chip);
  let shownAsOf = instrument.asOf;
  startLive({
    path: "../asset-tracker/intraday.json",
    onState: (state) => {
      const snapshot = state.snapshot;
      if (state.error || state.absent || !snapshot || !usableSnapshot(snapshot, state.now)) {
        chip.className = "quote-chip";
        chip.textContent = state.error
          ? "盘中快照读取失败 · 显示日更收盘值"
          : (state.absent ? "暂无盘中快照 · 显示日更收盘值" : "盘中快照已过期 · 显示日更收盘值");
        return;
      }
      const quote = snapshot.quotes[instrument.symbol];
      const cadence = Number.isInteger(snapshot.cadenceMinutes) ? snapshot.cadenceMinutes : null;
      if (!quote || !newerThan(quote, shownAsOf)) {
        chip.className = "quote-chip";
        chip.textContent = "盘中层暂无更新 · 显示日更收盘值";
        return;
      }
      const next = formatLike(priceNode.textContent, quote.price);
      const rising = Number(String(next).replace(/,/g, ""))
        >= Number(String(priceNode.textContent || "0").replace(/,/g, ""));
      if (priceNode.textContent !== next) {
        priceNode.textContent = next;
        priceNode.classList.remove("live-tick-up", "live-tick-down");
        void priceNode.offsetWidth;
        priceNode.classList.add(rising ? "live-tick-up" : "live-tick-down");
        window.setTimeout(() => {
          priceNode.classList.remove("live-tick-up", "live-tick-down");
        }, 900);
      }
      const moved = formatChangePct(quote.changePct);
      changeNode.className = `quote-change quote-change-${moved.direction}`;
      changeNode.textContent = "";
      const arrow = document.createElement("i");
      arrow.style.fontStyle = "normal";
      arrow.textContent = moved.arrow;
      changeNode.appendChild(arrow);
      const body = document.createElement("span");
      body.textContent = moved.text;
      changeNode.appendChild(body);
      shownAsOf = quote.asOf || shownAsOf;
      chip.className = "quote-chip quote-chip-live";
      chip.textContent = `盘中 · ${freshnessText(snapshot.updatedAt, state.now)}`
        + (cadence ? ` · 约${cadence}分钟一刷，非实时` : " · 非实时");
      chip.title = String(snapshot.note || "");
    }
  });
}

export function renderQuoteError(document, root, message) {
  root.textContent = "";
  root.setAttribute("aria-busy", "false");
  const box = text(root, "div", "quote-error");
  text(box, "p", "", message);
  const back = text(box, "a", "quote-source-link", "← 返回全球市场行情");
  back.href = "../markets/";
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
    const payload = await loadInstrument(query.kind, query.symbol);
    payload.kind = query.kind;
    renderQuote(document, root, payload, query.range);
  } catch (error) {
    renderQuoteError(document, root,
      `暂时读不到这个标的：${error && error.message ? error.message : "未知错误"}。`);
  }
}

if (typeof document !== "undefined" && typeof window !== "undefined" && window.location) {
  start();
}
