/* 品类行情板视图：六个品类标签页、可折叠列表与逐标的走势抽屉。
   抽屉复用资产详情抽屉的外壳与折线映射，保证焦点、Esc、遮罩与几何只有一份实现。
   没有站内历史序列的标的如实说明原因，不用相邻标的或推断值顶替。 */

import { seriesPath } from "./finance-terminal-detail-view.mjs";
import { mountWatchlist } from "./finance-terminal-watchlist.mjs";

/* 走势区间按交易日近似取点：站内序列本身就是交易日轴，不做日历插值。 */
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
  return [item && item.name, item && item.nameEn, item && item.symbol,
    item && item.extraText, item && item.groupLabel]
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

/* 纯函数：逐行链接到独立的行情详情页。序列引用里的 kind 决定详情页读哪一条管道；
   没有序列引用的行也仍然可以打开——详情页会照样摆出它的当期读数与来源。
   base 让同一份视图能被不同目录下的页面复用（金融终端与「全球市场行情」各给各的相对路径）。 */
export function quoteHref(item, base) {
  const kinds = { tracker: "tracker", company: "company", cryptoBoard: "crypto", curve: "curve",
    macro: "macro", commodity: "commodity" };
  const reference = item && item.series ? item.series : null;
  const kind = reference && kinds[reference.kind] ? kinds[reference.kind] : "";
  const symbol = reference && reference.key ? reference.key : (item ? item.symbol : "");
  if (!kind || !symbol) return "";
  const target = base || "quote.html";
  return `${target}?kind=${encodeURIComponent(kind)}&symbol=${encodeURIComponent(symbol)}`;
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
  if (reference.kind === "commodity") {
    const bundle = await loadJson("../commodities/history.json");
    const grain = reference.grain === "monthly" ? "monthly" : "daily";
    const record = bundle && bundle[grain] ? bundle[grain] : null;
    if (!record || !record.series || !record.series[reference.key]) return null;
    return {
      dates: record.dates || [],
      values: record.series[reference.key],
      source: record.source || bundle.source || "",
      note: record.note || bundle.note || ""
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
  /* 观测单位按该行自己的频率说：月频序列写「个月度观测」，写成「交易日」就是把
     月频数据说成了日频。 */
  const grain = item.frequency === "monthly" ? "个月度观测"
    : (item.frequency === "weekly" ? "个周度观测" : "个交易日");
  svg.setAttribute("aria-label", `${item.name} 最近${window.values.length}${grain}站内走势`
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
  /* 末端光点：标出「这条线画到哪一天为止」。它只是最后一个真实观测的位置标记，
     不代表实时——脉冲动画在系统开启「减少动态效果」时会自动停下。 */
  const last = window.values[window.values.length - 1];
  const low = Math.min(...window.values);
  const high = Math.max(...window.values);
  const span = (high - low) || 1;
  const dot = document.createElementNS("http://www.w3.org/2000/svg", "circle");
  dot.setAttribute("class", "board-spark-dot");
  dot.setAttribute("cx", String(SPARK_BOX.width - SPARK_BOX.pad));
  dot.setAttribute("cy", (SPARK_BOX.pad + (1 - (last - low) / span)
    * (SPARK_BOX.height - SPARK_BOX.pad * 2)).toFixed(1));
  dot.setAttribute("r", "2");
  svg.appendChild(dot);
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
  /* 只看某一组时不再折叠（每组本来就只有几行）；分组小标题也只在「全部」视图里出现，
     已经筛到一组时，标题就是分组条上那颗选中的芯片。 */
  const limit = context.group ? rows.length : category.collapseAfter;
  const grouped = Boolean(category.groups && category.groups.length) && !context.group;
  const visible = expanded ? rows : rows.slice(0, limit);
  const pending = [];
  let openGroup = "";
  visible.forEach((item) => {
    if (grouped && item.group && item.group !== openGroup) {
      openGroup = item.group;
      const band = text(host, "div", "board-group-head");
      text(band, "b", "", item.groupLabel || item.group);
      text(band, "i", "", `${rows.filter((row) => row.group === item.group).length}项`);
    }
    const line = text(host, "div", `board-row board-change-${item.change.direction}`);
    /* 盘中快照目前只覆盖跨资产管道的标的：给这些行标出代码与当前显示的数据日，
       活更新模块据此判断「盘中那条是不是真的更新」，其余品类原样保留日更读数。 */
    if (item.series && item.series.kind === "tracker") {
      line.dataset.liveSymbol = item.symbol;
      line.dataset.liveAsof = item.asOf || "";
      line.dataset.livePrice = item.priceText;
    }
    if (context.watch) line.appendChild(context.watch.button(item.symbol));
    else text(line, "span", "board-cell-watch", "");
    const open = text(line, "a", "board-open");
    open.href = quoteHref(item, document.documentElement.dataset.quoteBase);
    open.setAttribute("aria-label",
      `${item.name}，最新价 ${item.priceText}，${item.change.text}，打开完整行情页`);
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
  });
  paintToken += 1;
  if (pending.length) fillSparks(document, pending, bundles, paintToken);
  if (rows.length > limit) {
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

/* 二级分组条：只在当前品类确实分了组时出现。它是筛选器而不是第二组标签页——面板仍是
   同一个品类的 tabpanel，因此用 aria-pressed 的按钮。计数口径与品类标签一致。 */
function paintGroups(document, host, category, active, query, onPick) {
  if (!host) return;
  host.textContent = "";
  const groups = category.groups || [];
  host.hidden = groups.length < 2;
  if (host.hidden) return;
  host.setAttribute("aria-label", `${category.label}分组`);
  const entries = [{ key: "", label: "全部", rows: category.rows }].concat(
    groups.map((group) => ({
      key: group.key,
      label: group.label,
      rows: category.rows.filter((row) => row.group === group.key)
    })));
  entries.forEach((entry) => {
    const chip = text(host, "button", "board-group-chip");
    chip.type = "button";
    chip.dataset.group = entry.key;
    chip.setAttribute("aria-pressed", entry.key === active ? "true" : "false");
    text(chip, "b", "", entry.label);
    const hits = query ? entry.rows.filter((row) => matchesQuery(row, query)).length : entry.rows.length;
    text(chip, "i", "", query ? `${hits}/${entry.rows.length}` : String(entry.rows.length));
    chip.addEventListener("click", () => { onPick(entry.key === active ? "" : entry.key); });
  });
}

export function createBoardView(document, view) {
  const tabsHost = document.getElementById("board-tabs");
  const panelHost = document.getElementById("board-panel");
  const summaryHost = document.getElementById("board-summary");
  const searchInput = document.getElementById("board-search");
  const pulseHost = document.getElementById("board-pulse");
  const groupsHost = document.getElementById("board-groups");

  function render(board) {
    if (!tabsHost || !panelHost) return;
    tabsHost.textContent = "";
    panelHost.textContent = "";
    const expandedByKey = new Map();
    /* 每个品类记住自己选中的二级分组，切回来时还在原处。 */
    const groupByKey = new Map();
    const bundles = { curveHistory: board.curveHistory, cryptoHistory: board.cryptoHistory };
    let active = (board.categories.filter((category) => category.rows.length)[0]
      || board.categories[0]).key;
    let query = searchInput ? searchInput.value : "";
    /* 自选与核心资产卡共用同一份清单：任一处切换都会回到这里重画。 */
    const watch = mountWatchlist(document, view || globalThis, () => paint(),
      { filterId: "board-watch-filter" });

    function paint() {
      const category = board.categories.filter((item) => item.key === active)[0];
      const group = groupByKey.get(active) || "";
      const scoped = group ? category.rows.filter((row) => row.group === group) : category.rows;
      const picked = selectRows(scoped, query, watch);
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
      paintGroups(document, groupsHost, category, group, String(query || "").trim(), (next) => {
        groupByKey.set(active, next);
        expandedByKey.delete(active);
        paint();
        const chip = groupsHost.querySelector(`.board-group-chip[data-group="${next}"]`);
        if (chip) chip.focus();
      });
      const groupLabel = group
        ? (category.groups.filter((item) => item.key === group)[0] || {}).label || ""
        : "";
      panelHost.setAttribute("aria-label",
        `${category.label}${groupLabel ? `·${groupLabel}` : ""}行情列表`);
      if (tabsHost.parentElement) tabsHost.parentElement.dataset.boardCategory = category.key;
      paintPulse(document, pulseHost, picked.shown, category);
      if (summaryHost) {
        const scope = query || picked.shown.length !== category.rows.length
          ? `显示${picked.shown.length}/${category.rows.length}项`
          : category.summary.text;
        summaryHost.textContent = `${category.label}${groupLabel ? ` · ${groupLabel}` : ""} · ${scope}`
          + (category.summary.asOfRange ? ` · 数据日 ${category.summary.asOfRange}` : "");
      }
      renderRows(document, panelHost, category, bundles, expandedByKey.get(active) === true, {
        shown: picked.shown,
        query: String(query || "").trim(),
        watched: picked.watched,
        group,
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
