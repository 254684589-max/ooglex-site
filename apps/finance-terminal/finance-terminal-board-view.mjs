/* 品类行情板视图：六个品类标签页、可折叠列表与逐标的走势抽屉。
   抽屉复用资产详情抽屉的外壳与折线映射，保证焦点、Esc、遮罩与几何只有一份实现。
   没有站内历史序列的标的如实说明原因，不用相邻标的或推断值顶替。 */

import { openPanel, section, row, note, seriesPath, isPanelOpen } from "./finance-terminal-detail-view.mjs";
import { formatPrice } from "./finance-terminal-board-data.mjs";
import { mountWatchlist } from "./finance-terminal-watchlist.mjs";

/* 走势区间按交易日近似取点：站内序列本身就是交易日轴，不做日历插值。 */
const RANGES = Object.freeze([
  { key: "1m", label: "1个月", points: 22 },
  { key: "3m", label: "3个月", points: 66 },
  { key: "6m", label: "6个月", points: 132 },
  { key: "1y", label: "1年", points: 260 }
]);

/* 每行的迷你走势固定看最近60个交易日：足够看出形态，又不会让整屏的取点成本失控。
   取点复用抽屉那份裁剪函数，颜色按这段窗口自己的首尾变化算，不套用当日涨跌方向。 */
const SPARK_POINTS = 60;
const SPARK_BOX = Object.freeze({ width: 68, height: 22, pad: 3 });

const cache = new Map();

/* 每次重画自增：品类切得快时，先前那批异步补图落地前会看到令牌已过期而放弃。 */
let paintToken = 0;

function loadJson(url) {
  if (!cache.has(url)) {
    cache.set(url, fetch(url, { cache: "no-store" })
      .then((response) => (response.ok ? response.json() : null))
      .catch(() => null));
  }
  return cache.get(url);
}

function text(parent, tag, className, content) {
  const node = parent.ownerDocument.createElement(tag);
  if (className) node.className = className;
  if (content !== undefined && content !== null) node.textContent = content;
  parent.appendChild(node);
  return node;
}

/* 纯函数：按名称、英文名、代码或口径标签匹配搜索词；空搜索词匹配全部。 */
export function matchesQuery(item, query) {
  const needle = String(query || "").trim().toLowerCase();
  if (!needle) return true;
  return [item && item.name, item && item.nameEn, item && item.symbol, item && item.extraText]
    .filter(Boolean)
    .some((field) => String(field).toLowerCase().includes(needle));
}

/* 纯函数：先按搜索词过滤，再交给自选清单排序与筛选；自选项前置。 */
export function selectRows(rows, query, watch) {
  const matched = (rows || []).filter((item) => matchesQuery(item, query));
  if (!watch) return { matched, shown: matched, watched: 0 };
  const picked = watch.select(matched);
  return { matched, shown: picked.shown, watched: picked.count };
}

/* 纯函数：把共享日期轴上的序列裁到指定区间，只保留有观测的点，不前向填充。 */
export function sliceSeries(dates, values, points) {
  const pairs = [];
  const length = Math.min(
    Array.isArray(dates) ? dates.length : 0,
    Array.isArray(values) ? values.length : 0
  );
  for (let index = 0; index < length; index += 1) {
    const value = values[index];
    if (typeof value === "number" && Number.isFinite(value)) pairs.push([dates[index], value]);
  }
  const window = Number.isInteger(points) && points > 0 ? pairs.slice(-points) : pairs;
  return {
    dates: window.map((pair) => pair[0]),
    values: window.map((pair) => pair[1])
  };
}

/* 纯函数：区间变化。收益率按基点，其余按百分比；两端都有观测才计算。 */
export function rangeChange(values, isYield) {
  if (!Array.isArray(values) || values.length < 2) return null;
  const first = values[0];
  const last = values[values.length - 1];
  if (!Number.isFinite(first) || !Number.isFinite(last) || (!isYield && first === 0)) return null;
  if (isYield) {
    const bp = Math.round((last - first) * 100);
    return `${bp > 0 ? "+" : ""}${bp} bp`;
  }
  const pct = (last / first - 1) * 100;
  return `${pct > 0 ? "+" : ""}${pct.toFixed(2)}%`;
}

/* 纯函数：迷你走势的方向按该窗口首尾比较得到，与当日涨跌各算各的，互不顶替。 */
export function sparkDirection(values) {
  if (!Array.isArray(values) || values.length < 2) return "unknown";
  const first = values[0];
  const last = values[values.length - 1];
  if (!Number.isFinite(first) || !Number.isFinite(last)) return "unknown";
  return last > first ? "up" : (last < first ? "down" : "flat");
}

/* 纯函数：当前显示行的涨跌分布，用于品类脉冲条。无观测的行归入 unknown，不算持平。 */
export function distribution(rows) {
  const counts = { up: 0, down: 0, flat: 0, unknown: 0, total: 0 };
  (rows || []).forEach((item) => {
    const direction = item && item.change ? item.change.direction : "unknown";
    counts[counts[direction] === undefined ? "unknown" : direction] += 1;
    counts.total += 1;
  });
  return counts;
}

/* 序列解析：五种来源各自独立读取，缺哪一种就如实说没有，不互相顶替。 */
async function resolveSeries(reference, bundles) {
  if (!reference) return null;
  const curveHistory = bundles && bundles.curveHistory;
  const cryptoHistory = bundles && bundles.cryptoHistory;
  if (reference.kind === "curve") {
    if (!curveHistory || !curveHistory.values) return null;
    return {
      dates: curveHistory.dates || [],
      values: curveHistory.values[reference.key] || [],
      source: "FRED / U.S. Treasury H.15",
      note: "十一个期限共享同一日期轴，某期限当日无观测即留空，不插值。"
    };
  }
  if (reference.kind === "cryptoBoard") {
    if (!cryptoHistory || !cryptoHistory.series || !cryptoHistory.series[reference.key]) return null;
    return {
      dates: cryptoHistory.dates || [],
      values: cryptoHistory.series[reference.key],
      source: cryptoHistory.source || "CoinGecko",
      note: cryptoHistory.note || ""
    };
  }
  if (reference.kind === "company") {
    const history = await loadJson("../companies/history.json");
    if (!history || !history.series || !history.series[reference.key]) return null;
    return {
      dates: history.dates || [],
      values: history.series[reference.key],
      source: history.source || "Yahoo Finance",
      note: history.note || ""
    };
  }
  if (reference.kind === "tracker") {
    const history = await loadJson("../asset-tracker/history.json");
    if (!history || !history.series || !history.series[reference.key]) return null;
    return {
      dates: history.dates || [],
      values: history.series[reference.key],
      source: history.source || "Yahoo Finance",
      note: history.note || ""
    };
  }
  if (reference.kind === "macro") {
    const bundle = await loadJson("../macro-radar/series.json");
    const record = bundle && bundle.series ? bundle.series[reference.key] : null;
    if (!record) return null;
    return {
      dates: record.dates || [],
      values: record.values || [],
      source: bundle.source || "",
      note: bundle.note || ""
    };
  }
  return null;
}

/* 行内迷你走势：面积+折线两条路径共用同一份取点，颜色由窗口首尾决定。
   取不到两个以上有效观测就返回 false，由调用方如实标注「无序列」。 */
function drawSpark(document, cell, item, window) {
  const line = seriesPath(window.values, SPARK_BOX.width, SPARK_BOX.height, SPARK_BOX.pad);
  if (!line) return false;
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("class", `board-spark board-spark-${sparkDirection(window.values)}`);
  svg.setAttribute("viewBox", `0 0 ${SPARK_BOX.width} ${SPARK_BOX.height}`);
  svg.setAttribute("preserveAspectRatio", "none");
  svg.setAttribute("role", "img");
  const change = rangeChange(window.values, item.unit === "年化收益率");
  svg.setAttribute("aria-label", `${item.name} 最近${window.values.length}个交易日站内收盘走势`
    + (change ? `，区间变化 ${change}` : ""));
  const area = document.createElementNS("http://www.w3.org/2000/svg", "path");
  area.setAttribute("class", "board-spark-area");
  area.setAttribute("d",
    `${line} L${SPARK_BOX.width - SPARK_BOX.pad} ${SPARK_BOX.height} L${SPARK_BOX.pad} ${SPARK_BOX.height} Z`);
  svg.appendChild(area);
  const stroke = document.createElementNS("http://www.w3.org/2000/svg", "path");
  stroke.setAttribute("class", "board-spark-line");
  stroke.setAttribute("d", line);
  svg.appendChild(stroke);
  cell.textContent = "";
  cell.appendChild(svg);
  return true;
}

/* 迷你走势按当前显示的行批量补齐：同一份历史文件只请求一次（loadJson 自带缓存），
   站内没有序列的行保持空位并写明原因，不用相邻标的或推断值顶替。 */
async function fillSparks(document, pending, bundles, token) {
  const resolved = await Promise.all(
    pending.map((entry) => resolveSeries(entry.item.series, bundles).catch(() => null)));
  if (token !== paintToken) return;
  pending.forEach((entry, index) => {
    if (!entry.cell.isConnected) return;
    const series = resolved[index];
    const window = series
      ? sliceSeries(series.dates, series.values, SPARK_POINTS)
      : { dates: [], values: [] };
    if (drawSpark(document, entry.cell, entry.item, window)) return;
    markSparkEmpty(document, entry.cell);
  });
}

function markSparkEmpty(document, cell) {
  cell.textContent = "";
  const mark = text(cell, "i", "board-spark-empty", "无序列");
  mark.title = "站内日更管道还没有覆盖该标的的历史序列，此处不画任何推断曲线";
}

function renderChart(document, box, item, series, rangeKey) {
  const range = RANGES.filter((entry) => entry.key === rangeKey)[0] || RANGES[RANGES.length - 1];
  const window = sliceSeries(series.dates, series.values, range.points);
  if (window.values.length < 2) {
    note(document, box, `该标的在${range.label}窗口内不足两个有效观测，暂不绘制曲线。`);
    return;
  }
  const isYield = item.unit === "年化收益率";
  const width = 520;
  const height = 150;
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("class", "detail-chart");
  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  svg.setAttribute("role", "img");
  const first = window.dates[0];
  const last = window.dates[window.dates.length - 1];
  svg.setAttribute("aria-label",
    `${item.name} 自 ${first} 至 ${last} 共 ${window.values.length} 个收盘观测的走势`);
  const line = document.createElementNS("http://www.w3.org/2000/svg", "path");
  line.setAttribute("class", "detail-chart-line");
  line.setAttribute("d", seriesPath(window.values, width, height, 10));
  svg.appendChild(line);
  box.appendChild(svg);
  const low = Math.min(...window.values);
  const high = Math.max(...window.values);
  const unit = isYield ? "%（年化收益率）" : (item.currency ? `${item.currency}计价` : "标的自身计价单位");
  row(document, box, "区间", isYield
    ? `${low.toFixed(2)}% — ${high.toFixed(2)}% · 年化收益率`
    : `${formatPrice(low)} — ${formatPrice(high)} · ${unit}`);
  row(document, box, "覆盖", `${first} → ${last} · ${window.values.length} 个交易日观测`);
  const change = rangeChange(window.values, isYield);
  if (change) row(document, box, `${range.label}变化`, change);
}

/* 走势抽屉：先画来源与口径，再按区间画曲线；序列缺失时说明原因并给官方入口。 */
async function openTrend(document, item, bundles) {
  const panel = openPanel(document, item.name,
    `${item.nameEn ? item.nameEn + " · " : ""}${item.symbol}`, `${item.name} 走势与数据口径`);
  const meta = section(document, panel, "来源与口径");
  row(document, meta, "最新价", item.priceText);
  row(document, meta, "涨跌", `${item.change.arrow} ${item.change.text} · ${item.changeBasis}`);
  row(document, meta, "数据日", item.asOf || "不可用");
  row(document, meta, "更新时间", item.updatedAt || "不可用");
  row(document, meta, "频率", item.frequency || "不可用");
  row(document, meta, "来源", item.sourceName || "不可用");
  row(document, meta, "状态", item.status === "ok" ? "正常" : (item.status === "stale" ? "过期" : item.status));
  if (item.currency) row(document, meta, "计价货币", item.currency);
  if (item.proxyOf) row(document, meta, "代理原标的", item.proxyOf);
  if (item.note) note(document, meta, item.note);
  if (item.sourceUrl) {
    const link = document.createElement("a");
    link.className = "detail-news";
    link.href = item.sourceUrl;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.textContent = "前往官方来源查看";
    meta.appendChild(link);
  }

  const box = section(document, panel, "站内历史走势");
  if (!item.series) {
    note(document, box, "该标的目前只有站内日更的最新报价，没有可绘制的历史序列；"
      + "在日更管道补齐序列之前，这里不显示任何推断曲线。完整历史请前往上方官方来源。");
    return;
  }
  const loading = text(box, "p", "detail-note", "正在读取站内历史序列…");
  const series = await resolveSeries(item.series, bundles);
  if (!isPanelOpen()) return;
  loading.remove();
  if (!series || !Array.isArray(series.values)) {
    note(document, box, "站内历史文件里还没有该标的的序列；对应日更任务补齐后此处会显示完整曲线，"
      + "在此之前不显示任何推断值。");
    return;
  }
  const tabs = text(box, "div", "board-range-tabs");
  tabs.setAttribute("role", "group");
  tabs.setAttribute("aria-label", "走势区间");
  const canvas = text(box, "div", "board-chart-body");
  let active = "1y";
  function draw() {
    canvas.textContent = "";
    renderChart(document, canvas, item, series, active);
    Array.from(tabs.children).forEach((button) => {
      button.setAttribute("aria-pressed", button.dataset.range === active ? "true" : "false");
    });
  }
  RANGES.forEach((range) => {
    const button = text(tabs, "button", "board-range-tab", range.label);
    button.type = "button";
    button.dataset.range = range.key;
    button.addEventListener("click", () => { active = range.key; draw(); });
  });
  draw();
  if (series.source) note(document, box, `序列来源：${series.source}。${series.note || ""}`);
}

function renderRows(document, host, category, bundles, expanded, context) {
  host.textContent = "";
  const rows = context.shown;
  if (!rows.length) {
    text(host, "p", "board-empty", context.query
      ? `没有匹配「${context.query}」的标的，换个名称或代码再试。`
      : (context.watched
        ? "自选里还没有本品类的标的；点行首的☆即可加入。"
        : "本类暂无可用数据；对应日更管道恢复后会自动出现。"));
    return;
  }
  const head = text(host, "div", "board-row board-row-head");
  text(head, "span", "board-cell-watch", "自选");
  const headCells = text(head, "span", "board-head-cells");
  text(headCells, "span", "board-cell-name", "标的");
  text(headCells, "span", "board-cell-spark", "近60日");
  text(headCells, "span", "board-cell-price", "最新价");
  text(headCells, "span", "board-cell-change", "涨跌");
  text(headCells, "span", "board-cell-extra", category.extraLabel || "口径");
  const visible = expanded ? rows : rows.slice(0, category.collapseAfter);
  const pending = [];
  visible.forEach((item) => {
    const line = text(host, "div", `board-row board-change-${item.change.direction}`);
    if (context.watch) line.appendChild(context.watch.button(item.symbol));
    else text(line, "span", "board-cell-watch", "");
    const open = text(line, "button", "board-open");
    open.type = "button";
    open.setAttribute("aria-label",
      `${item.name}，最新价 ${item.priceText}，${item.change.text}，查看走势与数据口径`);
    const name = text(open, "span", "board-cell-name");
    text(name, "b", "", item.name);
    text(name, "i", "", item.symbol + (item.status === "stale" ? " · 过期" : ""));
    pending.push({ item, cell: text(open, "span", "board-cell-spark") });
    const price = text(open, "span", "board-cell-price", item.priceText);
    if (item.currency && item.currency !== "USD") text(price, "i", "board-cell-currency", item.currency);
    const change = text(open, "span", "board-cell-change");
    text(change, "i", "board-arrow", item.change.arrow);
    text(change, "b", "", item.change.text);
    text(open, "span", "board-cell-extra", item.extraText || "—");
    open.addEventListener("click", () => { openTrend(document, item, bundles); });
  });
  paintToken += 1;
  if (pending.length) fillSparks(document, pending, bundles, paintToken);
  if (rows.length > category.collapseAfter) {
    const toggle = text(host, "button", "board-toggle",
      expanded ? "收起" : `展开全部 ${rows.length} 项`);
    toggle.type = "button";
    toggle.setAttribute("aria-expanded", expanded ? "true" : "false");
    toggle.addEventListener("click", () => {
      renderRows(document, host, category, bundles, !expanded, context);
      const next = host.querySelector(".board-toggle");
      if (next) next.focus();
    });
  }
}

/* 品类脉冲条：只统计当前显示的行，涨跌各占多少一目了然。
   债券品类的方向词按该品类自己的口径（上行/下行），不套用股票的涨跌措辞。 */
function paintPulse(document, host, rows, category) {
  if (!host) return;
  host.textContent = "";
  const counts = distribution(rows);
  if (!counts.total) {
    host.hidden = true;
    return;
  }
  host.hidden = false;
  const labels = (category && category.directionLabels) || { up: "上涨", down: "下跌" };
  const bar = text(host, "span", "board-pulse-bar");
  ["up", "flat", "unknown", "down"].forEach((key) => {
    if (!counts[key]) return;
    const segment = text(bar, "i", `board-pulse-seg board-pulse-${key}`);
    segment.style.width = `${(counts[key] / counts.total * 100).toFixed(1)}%`;
  });
  const rest = counts.flat + counts.unknown;
  text(host, "span", "board-pulse-text", `▲${counts.up} ▼${counts.down} ▬${rest}`);
  host.setAttribute("role", "img");
  host.setAttribute("aria-label", `当前显示 ${counts.total} 项：${labels.up} ${counts.up} 项，`
    + `${labels.down} ${counts.down} 项，持平或暂无观测 ${rest} 项`);
}

export function createBoardView(document, view) {
  const tabsHost = document.getElementById("board-tabs");
  const panelHost = document.getElementById("board-panel");
  const summaryHost = document.getElementById("board-summary");
  const searchInput = document.getElementById("board-search");
  const pulseHost = document.getElementById("board-pulse");

  function render(board) {
    if (!tabsHost || !panelHost) return;
    tabsHost.textContent = "";
    panelHost.textContent = "";
    const expandedByKey = new Map();
    const bundles = { curveHistory: board.curveHistory, cryptoHistory: board.cryptoHistory };
    let active = (board.categories.filter((category) => category.rows.length)[0]
      || board.categories[0]).key;
    let query = searchInput ? searchInput.value : "";
    /* 自选与核心资产卡共用同一份清单：任一处切换都会回到这里重画。 */
    const watch = mountWatchlist(document, view || globalThis, () => paint(),
      { filterId: "board-watch-filter" });

    function paint() {
      const category = board.categories.filter((item) => item.key === active)[0];
      const picked = selectRows(category.rows, query, watch);
      Array.from(tabsHost.children).forEach((button) => {
        const selected = button.dataset.category === active;
        button.setAttribute("aria-selected", selected ? "true" : "false");
        button.tabIndex = selected ? 0 : -1;
        const owner = board.categories.filter((item) => item.key === button.dataset.category)[0];
        const count = button.querySelector("i");
        if (owner && count) {
          const hits = query
            ? owner.rows.filter((row) => matchesQuery(row, query)).length
            : owner.rows.length;
          count.textContent = query ? `${hits}/${owner.rows.length}` : String(owner.rows.length);
        }
      });
      panelHost.setAttribute("aria-label", `${category.label}行情列表`);
      if (tabsHost.parentElement) tabsHost.parentElement.dataset.boardCategory = category.key;
      paintPulse(document, pulseHost, picked.shown, category);
      if (summaryHost) {
        const scope = query || picked.shown.length !== category.rows.length
          ? `显示${picked.shown.length}/${category.rows.length}项`
          : category.summary.text;
        summaryHost.textContent = `${category.label} · ${scope}`
          + (category.summary.asOf ? ` · 数据日 ${category.summary.asOf}` : "");
      }
      renderRows(document, panelHost, category, bundles, expandedByKey.get(active) === true, {
        shown: picked.shown,
        query: String(query || "").trim(),
        watched: picked.watched,
        watch
      });
    }

    board.categories.forEach((category, index) => {
      const button = text(tabsHost, "button", "board-tab");
      button.type = "button";
      button.id = `board-tab-${category.key}`;
      button.setAttribute("role", "tab");
      button.setAttribute("aria-controls", "board-panel");
      button.dataset.category = category.key;
      text(button, "b", "", category.label);
      text(button, "i", "", String(category.rows.length));
      button.addEventListener("click", () => {
        expandedByKey.set(active, Boolean(panelHost.querySelector(".board-toggle"))
          && panelHost.querySelector(".board-toggle").getAttribute("aria-expanded") === "true");
        active = category.key;
        paint();
      });
      button.addEventListener("keydown", (event) => {
        const step = event.key === "ArrowRight" ? 1 : (event.key === "ArrowLeft" ? -1 : 0);
        if (!step) return;
        event.preventDefault();
        const next = (index + step + board.categories.length) % board.categories.length;
        active = board.categories[next].key;
        paint();
        tabsHost.children[next].focus();
      });
    });
    if (searchInput) {
      searchInput.addEventListener("input", () => {
        query = searchInput.value;
        expandedByKey.clear();
        paint();
      });
    }
    paint();
    panelHost.setAttribute("aria-busy", "false");
    if (board.failures.length && summaryHost) {
      const warning = document.getElementById("board-failures");
      if (warning) {
        warning.hidden = false;
        warning.textContent = `部分来源不可用：${board.failures.join("；")}`;
      }
    }
  }

  return { render };
}
