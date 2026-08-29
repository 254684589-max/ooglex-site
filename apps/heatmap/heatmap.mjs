/** 标普500热力图：把 sp500.json 画成按行业分块、按市值定面积、按当日涨跌上色的方块图。
 *
 * 三条硬约束：
 * 1. 面积严格正比于市值——这是方块图唯一的量化承诺，不为了好看去改；
 * 2. 颜色不是唯一编码——每块瓦片同时写出带 ▲▼ 的涨跌数字，另有图例与表格视图，
 *    红绿色觉差异的读者靠数字与箭头一样读得出方向；
 * 3. 覆盖缺口写在页面上——名单里站内没有行情的公司逐个列出，不静默丢弃。
 */
import { layoutSectors } from "./heatmap-layout.mjs";
import {
  SCALE, NO_CHANGE, stepFor, formatCap, formatPct, groupBySector, summarize
} from "./heatmap-data.mjs";

const DATA_PATH = "../companies/sp500.json";
/* 瓦片小到放不下字时就不放：挤成半个字比留白更难读。阈值按实测的字号定。 */
const MIN_W_SYMBOL = 34, MIN_H_SYMBOL = 18, MIN_H_PCT = 32;

/* 字号随瓦片大小走：最大的几家给到 26px，最小的仍是 10px。
   面积已经在编码市值，字号只是让大块读得清，不额外承载信息——所以按短边定，
   不按面积定：一块细长条即使面积大，也放不下大字。 */
function typeScale(w, h) {
  const side = Math.min(w, h);
  const symbol = Math.max(10, Math.min(26, Math.round(side * 0.22)));
  return { symbol, pct: Math.max(9, Math.round(symbol * 0.72)) };
}

function el(parent, tag, className, text) {
  const node = parent.ownerDocument.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined && text !== null) node.textContent = text;
  parent.appendChild(node);
  return node;
}

function paintLegend(host) {
  host.textContent = "";
  el(host, "span", "legend-label", "当日涨跌");
  SCALE.forEach((step) => {
    const chip = el(host, "span", "legend-chip");
    el(chip, "i", "legend-swatch").style.background = step.color;
    el(chip, "span", "", step.label);
  });
  const chip = el(host, "span", "legend-chip");
  el(chip, "i", "legend-swatch").style.background = NO_CHANGE.color;
  el(chip, "span", "", NO_CHANGE.label);
}

function paintTable(host, members) {
  host.textContent = "";
  const table = el(host, "table", "heat-table");
  const head = el(el(table, "thead"), "tr");
  ["#", "标的", "代码", "行业", "市值", "当日涨跌"].forEach((label) => el(head, "th", "", label));
  const body = el(table, "tbody");
  members.forEach((row) => {
    const tr = el(body, "tr");
    el(tr, "td", "", String(row.rank || ""));
    el(tr, "td", "", row.name || row.nameEn || row.symbol);
    el(tr, "td", "heat-mono", row.symbol);
    el(tr, "td", "", row.sector || "—");
    el(tr, "td", "heat-mono", formatCap(row.marketCap));
    const cell = el(tr, "td", "heat-mono", formatPct(row.changePct));
    cell.classList.add(Number.isFinite(row.changePct)
      ? (row.changePct > 0 ? "heat-up" : (row.changePct < 0 ? "heat-down" : "heat-flat"))
      : "heat-unknown");
  });
}

export function renderHeatmap(document, host, sectors, box) {
  host.textContent = "";
  host.style.height = `${box.h}px`;
  const blocks = layoutSectors(sectors, { x: 0, y: 0, w: box.w, h: box.h },
    { headHeight: 22, gap: 3 });

  blocks.forEach((block) => {
    const group = el(host, "div", "heat-sector");
    Object.assign(group.style, {
      left: `${block.x}px`, top: `${block.y}px`,
      width: `${block.w}px`, height: `${block.h}px`
    });
    const head = el(group, "div", "heat-sector-head");
    head.style.height = `${block.headHeight}px`;
    el(head, "span", "heat-sector-name", block.sector.label);
    el(head, "span", "heat-sector-meta",
      `${block.sector.count}家 · ${formatPct(block.sector.changePct)}`);

    block.tiles.forEach((tile) => {
      const row = tile.item.row;
      const step = stepFor(row.changePct);
      const cell = el(group, "a", `heat-tile heat-ink-${step.ink}`);
      cell.href = `../finance-terminal/quote.html?kind=company&symbol=${encodeURIComponent(row.symbol)}`;
      Object.assign(cell.style, {
        left: `${tile.x - block.x}px`, top: `${tile.y - block.y}px`,
        width: `${Math.max(0, tile.w - 1)}px`, height: `${Math.max(0, tile.h - 1)}px`,
        background: step.color
      });
      /* 无障碍：每块瓦片自带完整读数，读屏与键盘用户不依赖悬浮层。 */
      cell.setAttribute("aria-label",
        `${row.name || row.symbol}（${row.symbol}），${block.sector.label}，`
        + `市值 ${formatCap(row.marketCap)}，当日 ${formatPct(row.changePct)}`);
      cell.dataset.symbol = row.symbol;
      if (tile.w >= MIN_W_SYMBOL && tile.h >= MIN_H_SYMBOL) {
        const type = typeScale(tile.w, tile.h);
        el(cell, "b", "heat-tile-symbol", row.symbol).style.fontSize = `${type.symbol}px`;
        /* 颜色之外的第二重编码：涨跌数字带 ▲▼，放得下就一定写出来。 */
        if (tile.h >= MIN_H_PCT) {
          el(cell, "span", "heat-tile-pct", formatPct(row.changePct))
            .style.fontSize = `${type.pct}px`;
        }
      }
    });
  });
  return blocks;
}

function attachTooltip(document, host, tip) {
  const show = (cell) => {
    const data = cell.getAttribute("aria-label") || "";
    tip.textContent = data;
    tip.hidden = false;
    const box = cell.getBoundingClientRect();
    const wrap = host.getBoundingClientRect();
    const left = Math.min(Math.max(box.left - wrap.left + box.width / 2 - tip.offsetWidth / 2, 4),
      Math.max(4, wrap.width - tip.offsetWidth - 4));
    tip.style.left = `${left}px`;
    tip.style.top = `${Math.max(4, box.top - wrap.top - tip.offsetHeight - 8)}px`;
  };
  const hide = () => { tip.hidden = true; };
  host.addEventListener("mouseover", (event) => {
    const cell = event.target.closest(".heat-tile");
    if (cell) show(cell);
  });
  host.addEventListener("mouseleave", hide);
  host.addEventListener("focusin", (event) => {
    const cell = event.target.closest(".heat-tile");
    if (cell) show(cell);
  });
  host.addEventListener("focusout", hide);
}

/* 窄屏一屏塞不下五百块：默认只画前若干家，并把「画了多少、共多少」写在标题上，
   而不是悄悄少画几百家。读者可以自己切到全部。 */
export function defaultLimit(width) {
  if (width < 560) return 60;
  if (width < 900) return 150;
  if (width < 1400) return 300;
  return 0;                      // 0 = 全部
}

export function aspectFor(width) {
  if (width < 560) return 1.15;  // 窄屏拉高，否则每块被压成细条
  if (width < 900) return 0.78;
  return 0.52;
}

async function start() {
  const root = document.getElementById("heat-root");
  if (!root) return;
  const status = document.getElementById("heat-status");
  let payload;
  try {
    const response = await fetch(DATA_PATH, { cache: "no-store" });
    if (!response || response.ok !== true) throw new Error(`HTTP ${response && response.status}`);
    payload = await response.json();
  } catch (error) {
    status.textContent = "暂时读不到标普500快照：" + (error && error.message ? error.message : "未知错误")
      + "。这份数据由站内每日管道生成，生成前页面不显示任何推断内容。";
    root.setAttribute("aria-busy", "false");
    return;
  }

  const members = payload.members || [];
  const stats = summarize(members);
  const text = (id, value) => {
    const node = document.getElementById(id);
    if (node) node.textContent = value;
  };
  text("stat-count", `${stats.count} 家`);
  text("stat-cap", formatCap(stats.totalCap));
  text("stat-asof", payload.asOf || "—");
  text("stat-breadth", `▲${stats.up} ▼${stats.down}`);
  text("stat-missing", payload.missing && payload.missing.length
    ? `${payload.missing.length} 家` : "0 家");

  const note = document.getElementById("heat-note");
  if (note) {
    note.textContent = `${payload.note || ""}`
      + `名单共 ${payload.constituents || "—"} 个成分代码，站内当日取到行情的 ${stats.count} 家；`
      + (payload.missing && payload.missing.length
        ? `未覆盖 ${payload.missing.length} 家：${payload.missing.join("、")}。`
        : "全部覆盖。")
      + (stats.unknown ? `另有 ${stats.unknown} 家当日涨跌缺失，按「缺失」单独着色，不涂成持平。` : "");
  }

  paintLegend(document.getElementById("heat-legend"));
  paintTable(document.getElementById("heat-table-host"), members);

  const canvas = document.getElementById("heat-canvas");
  const tip = document.getElementById("heat-tip");
  const limitBar = document.getElementById("heat-limits");
  const shownLabel = document.getElementById("heat-shown");
  let limit = defaultLimit(window.innerWidth);

  function draw() {
    const width = canvas.clientWidth || 900;
    const sectors = groupBySector(members, limit);
    const drawn = sectors.reduce((sum, sector) => sum + sector.count, 0);
    renderHeatmap(document, canvas, sectors, { w: width, h: Math.round(width * aspectFor(width)) });
    shownLabel.textContent = limit && drawn < stats.count
      ? `显示市值前 ${drawn} 家（共 ${stats.count} 家）`
      : `显示全部 ${drawn} 家`;
    Array.from(limitBar.children).forEach((button) => {
      button.setAttribute("aria-pressed", Number(button.dataset.limit) === limit ? "true" : "false");
    });
  }

  [["60", 60], ["150", 150], ["300", 300], ["全部", 0]].forEach(([label, value]) => {
    const button = el(limitBar, "button", "heat-limit", label);
    button.type = "button";
    button.dataset.limit = String(value);
    button.setAttribute("aria-pressed", "false");
    button.addEventListener("click", () => { limit = value; draw(); });
  });

  attachTooltip(document, canvas.parentElement, tip);
  draw();
  root.setAttribute("aria-busy", "false");
  if (status) status.remove();

  let timer = 0;
  window.addEventListener("resize", () => {
    window.clearTimeout(timer);
    timer = window.setTimeout(draw, 160);
  });

  const toggle = document.getElementById("heat-table-toggle");
  const tableWrap = document.getElementById("heat-table-wrap");
  if (toggle && tableWrap) {
    toggle.addEventListener("click", () => {
      const open = tableWrap.hidden;
      tableWrap.hidden = !open;
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
      toggle.textContent = open ? "收起数据表" : "以数据表查看";
    });
  }
}

if (typeof document !== "undefined" && typeof window !== "undefined" && window.location) {
  start();
}
