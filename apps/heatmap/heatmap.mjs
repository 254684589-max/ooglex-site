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
  SCALE, NO_CHANGE, stepFor, formatCap, formatPct, groupBySector, summarize, BAND_SCALE
} from "./heatmap-data.mjs";
import { formatPrice, renderBubbles, updateBubbles, paintBubbleLegend } from "./bubble.mjs";
import {
  usableSnapshot, newerThan, freshnessText, isFiniteNumber
} from "../finance-terminal/finance-terminal-live.mjs";

const DATA_PATH = "../companies/sp500.json";
const INTRADAY_PATH = "../companies/intraday.json";
/* 页面重读盘中文件的间隔。文件本身约30分钟一轮，这里读得勤一点只是为了
   「它一更新就看得见」，不是把刷新周期说成20秒。 */
const LIVE_INTERVAL_MS = 20000;
/* 滚轮缩放的档位。1 是整屏铺满，往上是为了看清小市值公司——每一档都会**重新排版**
   而不是把同一张图糊着放大：格子在更大的画布上重算，小格因此越过写字的门槛，
   名字、代码、涨跌与股价才真的显示得出来。 */
const ZOOM_STEPS = Object.freeze([1, 1.5, 2, 3, 4, 6]);
/* 瓦片小到放不下字时就不放：挤成半个字比留白更难读。
   中文名一个字约等于两个拉丁字符宽，因此放名字的门槛比放代码时高一些；
   实在放不下中文名的小格退回显示代码，再放不下就只留颜色，读数交给悬浮层与数据表。 */
const MIN_W_NAME = 52, MIN_H_NAME = 18;
const MIN_W_SYMBOL = 30, MIN_H_PCT = 34, MIN_W_CODE = 74, MIN_H_CODE = 52;
/* 股价是第四行，门槛最高：前三行（名字、代码、涨跌）先满足，还有余地才写价。
   放不下就不写——写一半的数字比不写更糟，读数交给悬浮层与数据表。 */
const MIN_W_PRICE = 74, MIN_H_PRICE = 68;

/* 名字太长的按瓦片宽度截断——挤到溢出会盖住相邻格，比截断更难读。 */
function fitName(name, width) {
  const text = String(name || "");
  const max = Math.max(2, Math.floor((width - 8) / 12));
  return text.length <= max ? text : `${text.slice(0, max - 1)}…`;
}

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
  ["#", "标的", "代码", "行业", "股价", "市值", "当日涨跌"].forEach((label) => el(head, "th", "", label));
  const body = el(table, "tbody");
  members.forEach((row) => {
    const tr = el(body, "tr");
    el(tr, "td", "", String(row.rank || ""));
    el(tr, "td", "", row.name || row.nameEn || row.symbol);
    el(tr, "td", "heat-mono", row.symbol);
    el(tr, "td", "", row.sector || "—");
    el(tr, "td", "heat-mono", formatPrice(row.price));
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
      const type = typeScale(tile.w, tile.h);
      /* 以中文名为主：放得下就写中文名，放不下退回代码，再放不下就不写。 */
      const label = row.name || row.nameEn || row.symbol;
      if (tile.w >= MIN_W_NAME && tile.h >= MIN_H_NAME) {
        el(cell, "b", "heat-tile-name", fitName(label, tile.w))
          .style.fontSize = `${type.symbol}px`;
      } else if (tile.w >= MIN_W_SYMBOL && tile.h >= MIN_H_NAME) {
        el(cell, "b", "heat-tile-symbol", row.symbol)
          .style.fontSize = `${Math.min(type.symbol, 12)}px`;
      }
      /* 大格再补一行代码：中文名之外，交易代码是另一条检索线索。 */
      if (tile.w >= MIN_W_CODE && tile.h >= MIN_H_CODE) {
        el(cell, "span", "heat-tile-symbol", row.symbol)
          .style.fontSize = `${Math.max(9, Math.round(type.pct * 0.9))}px`;
      }
      /* 颜色之外的第二重编码：涨跌数字带 ▲▼，放得下就一定写出来。 */
      if (tile.w >= MIN_W_SYMBOL && tile.h >= MIN_H_PCT) {
        el(cell, "span", "heat-tile-pct", formatPct(row.changePct))
          .style.fontSize = `${type.pct}px`;
      }
      /* 股价：够大的格子再补一行。缩放放大后小格也会越过这个门槛——
         这正是滚轮放大的意义，不是把同一张图糊着放大。 */
      if (tile.w >= MIN_W_PRICE && tile.h >= MIN_H_PRICE) {
        el(cell, "span", "heat-tile-price", formatPrice(row.price))
          .style.fontSize = `${Math.max(9, Math.round(type.pct * 0.95))}px`;
      }
    });
  });
  return blocks;
}

function attachTooltip(document, host, tip, selector = ".heat-tile") {
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
    const cell = event.target.closest(selector);
    if (cell) show(cell);
  });
  host.addEventListener("mouseleave", hide);
  host.addEventListener("focusin", (event) => {
    const cell = event.target.closest(selector);
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
  const viewport = document.getElementById("heat-viewport");
  const tip = document.getElementById("heat-tip");
  const limitBar = document.getElementById("heat-limits");
  const shownLabel = document.getElementById("heat-shown");
  const zoomLabel = document.getElementById("heat-zoom-level");
  let limit = defaultLimit(window.innerWidth);
  let zoom = 1;

  function draw() {
    const width = (viewport ? viewport.clientWidth : canvas.clientWidth) || 900;
    const sectors = groupBySector(members, limit);
    const drawn = sectors.reduce((sum, sector) => sum + sector.count, 0);
    /* 放大就是把画布真的做大再重排一次，不是 CSS 缩放：字会跟着重新排版，
       小格因此才写得下名字与股价，而不是被糊着放大。 */
    const w = Math.round(width * zoom);
    const h = Math.round(width * aspectFor(width) * zoom);
    canvas.style.width = `${w}px`;
    renderHeatmap(document, canvas, sectors, { w, h });
    shownLabel.textContent = limit && drawn < stats.count
      ? `显示市值前 ${drawn} 家（共 ${stats.count} 家）`
      : `显示全部 ${drawn} 家`;
    if (zoomLabel) zoomLabel.textContent = `${zoom.toFixed(zoom % 1 ? 1 : 0)}×`;
    Array.from(limitBar.children).forEach((button) => {
      button.setAttribute("aria-pressed", Number(button.dataset.limit) === limit ? "true" : "false");
    });
    paintLive();
  }

  /* 缩放锚定在光标处：放大后光标下面的那家公司还在光标下面，
     否则每滚一格视野就跳到别处，等于每次都要重新找。 */
  function setZoom(next, anchor) {
    const clamped = Math.max(ZOOM_STEPS[0], Math.min(ZOOM_STEPS[ZOOM_STEPS.length - 1], next));
    if (clamped === zoom) return false;
    const before = zoom;
    const rect = viewport.getBoundingClientRect();
    const px = anchor ? anchor.clientX - rect.left : rect.width / 2;
    const py = anchor ? anchor.clientY - rect.top : rect.height / 2;
    const atX = (viewport.scrollLeft + px) / before;
    const atY = (viewport.scrollTop + py) / before;
    zoom = clamped;
    draw();
    viewport.scrollLeft = atX * zoom - px;
    viewport.scrollTop = atY * zoom - py;
    return true;
  }

  function stepZoom(direction, anchor) {
    const index = ZOOM_STEPS.indexOf(zoom);
    const at = index >= 0 ? index : ZOOM_STEPS.findIndex((value) => value > zoom);
    const next = ZOOM_STEPS[Math.max(0, Math.min(ZOOM_STEPS.length - 1, at + direction))];
    return setZoom(next, anchor);
  }

  /* ── 盘中层 ────────────────────────────────────────────────────────
     两张图读同一份盘中快照。覆盖只发生在盘中报价确实比日更那条更新时；
     文件过期、缺这个标的、或者取数失败，就原样保留日更读数并如实说明。
     这里绝不做定时抖动——那等于伪造实时。 */
  let live = null;
  const liveNote = document.getElementById("heat-live");

  /* 把盘中价覆盖到一行上，返回是否真的覆盖了。日更那份原样留在 dailyPrice /
     dailyChangePct 上，随时可以说清「现在显示的是哪一层」。 */
  function overlay(row, now) {
    if (!row.dailyPrice) {
      row.dailyPrice = row.price;
      row.dailyChangePct = row.changePct;
      row.dailyAsOf = payload.asOf || "";
    }
    const quote = live && live.quotes ? live.quotes[row.symbol] : null;
    if (live && usableSnapshot(live, now) && newerThan(quote, row.dailyAsOf)) {
      row.price = quote.price;
      row.changePct = isFiniteNumber(quote.changePct) ? quote.changePct : row.changePct;
      row.intraday = true;
      return true;
    }
    row.price = row.dailyPrice;
    row.changePct = row.dailyChangePct;
    row.intraday = false;
    return false;
  }

  function paintLive() {
    if (!liveNote) return;
    const now = Date.now();
    const covered = members.filter((row) => overlay(row, now)).length;
    if (!live) {
      liveNote.textContent = "盘中快照尚未生成，当前显示的是收盘口径的日更读数。";
      return;
    }
    if (!covered) {
      liveNote.textContent = `盘中快照未覆盖当前读数（${freshnessText(live.updatedAt, now)}），`
        + "显示的是收盘口径的日更读数。";
      return;
    }
    liveNote.textContent = `盘中读数已覆盖 ${covered} 家 · 刷新周期约 `
      + `${live.cadenceMinutes || 30} 分钟 · ${freshnessText(live.updatedAt, now)} · 非实时行情`;
  }

  async function pullLive() {
    try {
      const response = await fetch(INTRADAY_PATH, { cache: "no-store" });
      if (!response || response.ok !== true) return;
      const next = await response.json();
      if (!next || next.realtime !== false) return;   // 自称实时的文件一律不采信
      live = next;
    } catch (error) {
      return;                                        // 取不到就继续显示日更读数
    }
    const now = Date.now();
    members.forEach((row) => overlay(row, now));
    repaintFromRows();
    paintLive();
  }

  [["60", 60], ["150", 150], ["300", 300], ["全部", 0]].forEach(([label, value]) => {
    const button = el(limitBar, "button", "heat-limit", label);
    button.type = "button";
    button.dataset.limit = String(value);
    button.setAttribute("aria-pressed", "false");
    /* 家数一变，两张图都要跟着重排：气泡图的取数与热力图同一份筛选结果，
       只更新一张会让两张图当场对不上。 */
    button.addEventListener("click", () => { limit = value; draw(); drawBubbles(); });
  });

  /* ── 气泡图 ────────────────────────────────────────────────────────
     与热力图同源同色：同一份成分股、同一套发散色阶。区别只在于把「市值」
     从面积换成气泡大小、把「涨跌」从颜色再加一条纵轴——因此一眼能看出
     同一个行业里谁在涨、谁在跌、各自多大。 */
  const bubbleHost = document.getElementById("bubble-canvas");
  const metricBar = document.getElementById("bubble-metrics");
  /* band 是这一档的色阶倍数：色阶的 ±0.1/±1/±3 是给当日定的，
     拿去看年初至今几乎每家都越过 +3%，整张图会全绿。 */
  const METRICS = [
    { key: "d1", label: "当日", of: (row) => row.changePct, band: BAND_SCALE.d1 },
    { key: "w1", label: "每周", of: (row) => (row.returns || {}).w1, band: BAND_SCALE.w1 },
    { key: "m1", label: "月度", of: (row) => (row.returns || {}).m1, band: BAND_SCALE.m1 },
    { key: "ytd", label: "年初至今", of: (row) => (row.returns || {}).ytd, band: BAND_SCALE.ytd }
  ];
  let metric = METRICS[0];
  let bubbles = null;
  let bubbleZoom = 1;
  const bubbleViewport = document.getElementById("bubble-viewport");
  const bubbleZoomLabel = document.getElementById("bubble-zoom-level");

  function bubbleBox() {
    const base = (bubbleViewport ? bubbleViewport.clientWidth : 900) || 900;
    const h = Math.max(320, Math.round(base * (base < 700 ? 0.95 : 0.5)));
    /* 放大与热力图同一个做法：把画布真的做大再重排一次，气泡因此变大，
       小气泡才越过写字的门槛——不是把同一张图糊着放大。 */
    return { w: Math.round(base * bubbleZoom), h: Math.round(h * bubbleZoom) };
  }

  function drawBubbles() {
    if (!bubbleHost) return;
    const shown = groupBySector(members, limit).flatMap((sector) => sector.children.map((c) => c.row));
    const box = bubbleBox();
    bubbleHost.style.width = `${box.w}px`;
    /* 某一档区间涨跌整批都没有时，如实说出来——画一张空图什么都不说，
       读者只会以为页面坏了。（这一档的数据由公司榜日更管道回写，
       管道尚未跑过时它就是空的。） */
    const withMetric = shown.filter((row) => Number.isFinite(metric.of(row))).length;
    if (!withMetric) {
      bubbleHost.textContent = "";
      const empty = el(bubbleHost, "p", "heat-note");
      empty.textContent = `站内暂时没有「${metric.label}」这一档的区间涨跌，`
        + "因此这张图画不出来。这一档由公司榜日更管道在建完历史后回写，"
        + "下一轮日更跑完即会出现——这里不拿别的档位顶替，也不画一张空图假装有数据。";
      bubbles = null;
      if (bubbleZoomLabel) bubbleZoomLabel.textContent = `${bubbleZoom}×`;
      Array.from(metricBar ? metricBar.children : []).forEach((button) => {
        button.setAttribute("aria-pressed", button.dataset.metric === metric.key ? "true" : "false");
      });
      const note = document.getElementById("bubble-note");
      if (note) note.textContent = "";
      return;
    }
    bubbles = renderBubbles(document, bubbleHost, shown, box,
      { metricOf: metric.of, metricLabel: metric.label, band: metric.band });
    paintBubbleLegend(document, document.getElementById("bubble-legend"),
      metric.band, metric.label);
    const drawn = bubbles.layout.circles.length;
    const gap = shown.length - drawn;
    const outside = bubbles.layout.circles.filter((circle) => circle.outside).length;
    const domain = bubbles.layout.domain;
    const note = document.getElementById("bubble-note");
    if (note) {
      note.textContent = `纵向是${metric.label}涨跌，横向按行业分列，气泡面积正比于市值；`
        + `共画出 ${drawn} 家。`
        + `纵轴按第2–98百分位取范围（${domain.min}% ~ ${domain.max}%）而不是按极值——`
        + `按极值定范围会被个别极端值撑开，其余几百家挤成一条线。`
        + (outside ? `有 ${outside} 家的真实涨跌在这个范围之外，贴边显示并描了虚线圈，`
          + `真实数值见悬浮读数与数据表。` : "")
        + (gap ? `另有 ${gap} 家缺这一档涨跌、不画在图上——放到零线上会被读成「没涨没跌」，那是伪造。` : "");
    }
    if (bubbleZoomLabel) {
      bubbleZoomLabel.textContent = `${bubbleZoom.toFixed(bubbleZoom % 1 ? 1 : 0)}×`;
    }
    Array.from(metricBar ? metricBar.children : []).forEach((button) => {
      button.setAttribute("aria-pressed", button.dataset.metric === metric.key ? "true" : "false");
    });
  }

  /* 缩放锚定光标，与热力图同一套行为：档位真的变了才拦截滚动，
     到顶到底继续滚则页面照常走。 */
  function setBubbleZoom(next, anchor) {
    const clamped = Math.max(ZOOM_STEPS[0], Math.min(ZOOM_STEPS[ZOOM_STEPS.length - 1], next));
    if (clamped === bubbleZoom || !bubbleViewport) return false;
    const before = bubbleZoom;
    const rect = bubbleViewport.getBoundingClientRect();
    const px = anchor ? anchor.clientX - rect.left : rect.width / 2;
    const py = anchor ? anchor.clientY - rect.top : rect.height / 2;
    const atX = (bubbleViewport.scrollLeft + px) / before;
    const atY = (bubbleViewport.scrollTop + py) / before;
    bubbleZoom = clamped;
    drawBubbles();
    bubbleViewport.scrollLeft = atX * bubbleZoom - px;
    bubbleViewport.scrollTop = atY * bubbleZoom - py;
    return true;
  }

  function stepBubbleZoom(direction, anchor) {
    const index = ZOOM_STEPS.indexOf(bubbleZoom);
    const at = index >= 0 ? index : ZOOM_STEPS.findIndex((value) => value > bubbleZoom);
    return setBubbleZoom(
      ZOOM_STEPS[Math.max(0, Math.min(ZOOM_STEPS.length - 1, at + direction))], anchor);
  }

  /* 盘中刷新时两张图各自就地更新：热力图重排一次（面积不变、颜色与数字变），
     气泡图只移动纵向位置，因此看上去是在上下浮动而不是整张重画。 */
  function repaintFromRows() {
    draw();
    if (bubbles && metric.key === "d1") {
      updateBubbles(bubbles, members,
        { metricOf: metric.of, metricLabel: metric.label, band: metric.band });
    }
  }

  METRICS.forEach((entry) => {
    if (!metricBar) return;
    const button = el(metricBar, "button", "heat-limit", entry.label);
    button.type = "button";
    button.dataset.metric = entry.key;
    button.setAttribute("aria-pressed", "false");
    button.addEventListener("click", () => { metric = entry; drawBubbles(); });
  });

  attachTooltip(document, canvas.parentElement, tip);
  if (bubbleViewport) attachTooltip(document, bubbleViewport.parentElement, tip, ".bubble-node");
  draw();
  drawBubbles();
  root.setAttribute("aria-busy", "false");
  if (status) status.remove();

  /* ── 滚轮缩放 ──────────────────────────────────────────────────────
     只有确实改变了档位才拦截滚动：到了最大/最小档还继续滚，页面照常往下走，
     不会把读者困在图里。键盘与按钮同样能缩放——只给滚轮等于把它挡在门外。 */
  if (viewport) {
    viewport.addEventListener("wheel", (event) => {
      if (event.deltaY === 0) return;
      if (stepZoom(event.deltaY < 0 ? 1 : -1, event)) event.preventDefault();
    }, { passive: false });
    viewport.addEventListener("keydown", (event) => {
      if (event.key === "+" || event.key === "=") { if (stepZoom(1)) event.preventDefault(); }
      if (event.key === "-" || event.key === "_") { if (stepZoom(-1)) event.preventDefault(); }
      if (event.key === "0") { setZoom(1); event.preventDefault(); }
    });
  }
  const zoomIn = document.getElementById("heat-zoom-in");
  const zoomOut = document.getElementById("heat-zoom-out");
  const zoomReset = document.getElementById("heat-zoom-reset");
  if (zoomIn) zoomIn.addEventListener("click", () => stepZoom(1));
  if (zoomOut) zoomOut.addEventListener("click", () => stepZoom(-1));
  if (zoomReset) zoomReset.addEventListener("click", () => setZoom(1));

  /* 气泡图的缩放与热力图完全同一套交互，读者不必学两遍。 */
  if (bubbleViewport) {
    bubbleViewport.addEventListener("wheel", (event) => {
      if (event.deltaY === 0) return;
      if (stepBubbleZoom(event.deltaY < 0 ? 1 : -1, event)) event.preventDefault();
    }, { passive: false });
    bubbleViewport.addEventListener("keydown", (event) => {
      if (event.key === "+" || event.key === "=") { if (stepBubbleZoom(1)) event.preventDefault(); }
      if (event.key === "-" || event.key === "_") { if (stepBubbleZoom(-1)) event.preventDefault(); }
      if (event.key === "0") { setBubbleZoom(1); event.preventDefault(); }
    });
  }
  const bZoomIn = document.getElementById("bubble-zoom-in");
  const bZoomOut = document.getElementById("bubble-zoom-out");
  const bZoomReset = document.getElementById("bubble-zoom-reset");
  if (bZoomIn) bZoomIn.addEventListener("click", () => stepBubbleZoom(1));
  if (bZoomOut) bZoomOut.addEventListener("click", () => stepBubbleZoom(-1));
  if (bZoomReset) bZoomReset.addEventListener("click", () => setBubbleZoom(1));

  pullLive();
  window.setInterval(pullLive, LIVE_INTERVAL_MS);

  let timer = 0;
  window.addEventListener("resize", () => {
    window.clearTimeout(timer);
    timer = window.setTimeout(() => { draw(); drawBubbles(); }, 160);
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
