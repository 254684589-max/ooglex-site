/* 品类行情板视图：六个品类标签页、可折叠列表与逐标的走势抽屉。
   抽屉复用资产详情抽屉的外壳与折线映射，保证焦点、Esc、遮罩与几何只有一份实现。
   没有站内历史序列的标的如实说明原因，不用相邻标的或推断值顶替。 */

import { openPanel, section, row, note, seriesPath, isPanelOpen } from "./finance-terminal-detail-view.mjs";
import { formatPrice } from "./finance-terminal-board-data.mjs";

/* 走势区间按交易日近似取点：站内序列本身就是交易日轴，不做日历插值。 */
const RANGES = Object.freeze([
  { key: "1m", label: "1个月", points: 22 },
  { key: "3m", label: "3个月", points: 66 },
  { key: "6m", label: "6个月", points: 132 },
  { key: "1y", label: "1年", points: 260 }
]);

const cache = new Map();

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

function renderRows(document, host, category, bundles, expanded) {
  host.textContent = "";
  if (!category.rows.length) {
    text(host, "p", "board-empty", "本类暂无可用数据；对应日更管道恢复后会自动出现。");
    return;
  }
  const head = text(host, "div", "board-row board-row-head");
  text(head, "span", "board-cell-name", "标的");
  text(head, "span", "board-cell-price", "最新价");
  text(head, "span", "board-cell-change", "涨跌");
  text(head, "span", "board-cell-extra", category.extraLabel || "口径");
  const visible = expanded ? category.rows : category.rows.slice(0, category.collapseAfter);
  visible.forEach((item) => {
    const line = text(host, "button", `board-row board-change-${item.change.direction}`);
    line.type = "button";
    line.setAttribute("aria-label",
      `${item.name}，最新价 ${item.priceText}，${item.change.text}，查看走势与数据口径`);
    const name = text(line, "span", "board-cell-name");
    text(name, "b", "", item.name);
    text(name, "i", "", item.symbol + (item.status === "stale" ? " · 过期" : ""));
    const price = text(line, "span", "board-cell-price", item.priceText);
    if (item.currency && item.currency !== "USD") text(price, "i", "board-cell-currency", item.currency);
    const change = text(line, "span", "board-cell-change");
    text(change, "i", "board-arrow", item.change.arrow);
    text(change, "b", "", item.change.text);
    text(line, "span", "board-cell-extra", item.extraText || "—");
    line.addEventListener("click", () => { openTrend(document, item, bundles); });
  });
  if (category.rows.length > category.collapseAfter) {
    const toggle = text(host, "button", "board-toggle",
      expanded ? "收起" : `展开全部 ${category.rows.length} 项`);
    toggle.type = "button";
    toggle.setAttribute("aria-expanded", expanded ? "true" : "false");
    toggle.addEventListener("click", () => {
      renderRows(document, host, category, bundles, !expanded);
      const next = host.querySelector(".board-toggle");
      if (next) next.focus();
    });
  }
}

export function createBoardView(document) {
  const tabsHost = document.getElementById("board-tabs");
  const panelHost = document.getElementById("board-panel");
  const summaryHost = document.getElementById("board-summary");

  function render(board) {
    if (!tabsHost || !panelHost) return;
    tabsHost.textContent = "";
    panelHost.textContent = "";
    const expandedByKey = new Map();
    const bundles = { curveHistory: board.curveHistory, cryptoHistory: board.cryptoHistory };
    let active = (board.categories.filter((category) => category.rows.length)[0]
      || board.categories[0]).key;

    function paint() {
      const category = board.categories.filter((item) => item.key === active)[0];
      Array.from(tabsHost.children).forEach((button) => {
        const selected = button.dataset.category === active;
        button.setAttribute("aria-selected", selected ? "true" : "false");
        button.tabIndex = selected ? 0 : -1;
      });
      panelHost.setAttribute("aria-label", `${category.label}行情列表`);
      if (summaryHost) {
        summaryHost.textContent = `${category.label} · ${category.summary.text}`
          + (category.summary.asOf ? ` · 数据日 ${category.summary.asOf}` : "");
      }
      renderRows(document, panelHost, category, bundles, expandedByKey.get(active) === true);
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
        expandedByKey.set(active, panelHost.querySelector(".board-toggle")
          ? panelHost.querySelector(".board-toggle").getAttribute("aria-expanded") === "true"
          : false);
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
