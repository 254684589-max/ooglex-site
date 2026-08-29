/** 标普500气泡图的渲染层：把 bubble-layout 算好的几何画成 SVG。
 *
 * 与热力图共用同一套色阶——两张图就摆在同一页上，读者不该为了看第二张图
 * 重新学一遍颜色。因此这里**颜色编码的是涨跌方向与幅度**（发散色阶），
 * 行业身份由横向的列位置与列标题承担，不另外派十一种颜色：
 * 气泡这类「任意两点都可能相邻」的图形，分类色最多只撑得住三种，
 * 十一种在色觉差异下必然有几对分不开。
 *
 * 纵向位置是收益率本身，零线画出来；面积正比于市值。两者都是量化承诺，
 * 不为了好看去改。
 */
import { SCALE, NO_CHANGE, stepFor, bandLabel, formatCap, formatPct } from "./heatmap-data.mjs";
import { layoutBubbles, isNum } from "./bubble-layout.mjs";

const NS = "http://www.w3.org/2000/svg";
/* 放得下才写字：字被裁掉比不写更难读。名字与价格各自有自己的门槛。 */
/* 写字的门槛按「这个半径的圆里放不放得下这行字」定，不是按名次定。
   门槛之上再做碰撞避让——两道关一起决定最后写出多少个。全部 495 家挤在一屏时
   写得出的自然少；筛到前 60/150 家，气泡变大，绝大多数都写得下。 */
const MIN_R_NAME = 13, MIN_R_PRICE = 19;

/* 股价一律带 $：这一页上同时有百分数、市值（亿/万亿美元）与股价三种数字，
   光一个「319.70」读不出它是价格还是别的什么。四位数以上取整，否则两位小数。 */
export function formatPrice(value) {
  if (!isNum(value)) return "—";
  const decimals = Math.abs(value) >= 1000 ? 0 : 2;
  return "$" + value.toLocaleString("en-US",
    { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
}

function svgEl(parent, tag, className) {
  const node = parent.ownerDocument.createElementNS(NS, tag);
  if (className) node.setAttribute("class", className);
  parent.appendChild(node);
  return node;
}

function svgText(parent, className, content, attrs) {
  const node = svgEl(parent, "text", className);
  Object.entries(attrs || {}).forEach(([k, v]) => node.setAttribute(k, String(v)));
  node.textContent = content;
  return node;
}

/* 挑一个真的读得出来的标签。

   截断成「美…」「泛…」这种一个字加省略号毫无用处——既认不出公司，又占着地方。
   因此规则是：中文名整个放得下就用中文名；放不下就退回交易代码（拉丁字符窄得多，
   同样宽度能多放几个）；两个都放不下就**不写**，读数交给悬浮层与数据表。
   一律不做截断。 */
export function pickLabel(name, symbol, radius) {
  const cn = String(name || "");
  const code = String(symbol || "");
  const inner = radius * 1.7;                 // 圆内可用的横向宽度
  if (cn && cn.length * 11.5 <= inner) return cn;
  if (code && code.length * 7.2 <= inner) return code;
  return "";
}

/* 一次完整绘制。返回逐代码的气泡节点，供盘中刷新时只改位置与颜色，
   不重画整张图——重画会让所有气泡瞬移，读不出「在浮动」。 */
export function renderBubbles(document, host, rows, box, options = {}) {
  host.textContent = "";
  const metricOf = options.metricOf || ((row) => row.changePct);
  const metricLabel = options.metricLabel || "当日涨跌";
  const band = options.band || 1;
  const layout = layoutBubbles(rows, box, { metricOf });
  const svg = svgEl(host, "svg", "bubble-svg");
  svg.setAttribute("viewBox", `0 0 ${box.w} ${box.h}`);
  svg.setAttribute("width", "100%");
  svg.setAttribute("height", String(box.h));
  svg.setAttribute("role", "img");
  svg.setAttribute("aria-label",
    `标普500成分股气泡图：横向按行业分列，纵向是${metricLabel}，气泡面积正比于市值，`
    + `共 ${layout.circles.length} 家。完整读数见下方数据表。`);
  if (!layout.plot) return { nodes: new Map(), layout };

  /* 刻度线在最底层，永远不压住数据。 */
  const grid = svgEl(svg, "g", "bubble-grid");
  layout.ticks.forEach((tick) => {
    const y = layout.yOf(tick);
    const line = svgEl(grid, "line", tick === 0 ? "bubble-zero" : "bubble-gridline");
    line.setAttribute("x1", layout.plot.x);
    line.setAttribute("x2", layout.plot.x + layout.plot.w);
    line.setAttribute("y1", y);
    line.setAttribute("y2", y);
    svgText(grid, "bubble-tick", `${tick > 0 ? "+" : ""}${tick}%`,
      { x: layout.plot.x - 8, y: y + 4, "text-anchor": "end" });
  });

  /* 行业列标题与分隔。列的次序写死，不随当天涨跌变。 */
  const cols = svgEl(svg, "g", "bubble-cols");
  layout.columns.forEach((column, index) => {
    if (index > 0) {
      const sep = svgEl(cols, "line", "bubble-colsep");
      sep.setAttribute("x1", column.x);
      sep.setAttribute("x2", column.x);
      sep.setAttribute("y1", layout.plot.y);
      sep.setAttribute("y2", layout.plot.y + layout.plot.h);
    }
    svgText(cols, "bubble-collabel", column.label,
      { x: column.centerX, y: box.h - 14, "text-anchor": "middle" });
    svgText(cols, "bubble-colcount", `${column.drawn}家`,
      { x: column.centerX, y: box.h - 2, "text-anchor": "middle" });
  });

  const layer = svgEl(svg, "g", "bubble-layer");
  const nodes = new Map();
  /* 字放在**所有圆之上**的独立一层，并从大到小逐个避让：写得下就写，写不下就不写。
     早先把字直接挂在各自的圆上，结果小气泡压住大气泡时两行字叠在一起糊成一团——
     那比不写更难读。这里按已放置的字框做碰撞检测，冲突就跳过这一个。 */
  const labelLayer = svgEl(svg, "g", "bubble-labels");
  const placedLabels = [];
  const fits = (x, y, w, h) => {
    const box = { x0: x - w / 2, x1: x + w / 2, y0: y - h / 2, y1: y + h / 2 };
    if (box.x0 < layout.plot.x || box.x1 > layout.plot.x + layout.plot.w) return false;
    const hit = placedLabels.some((other) => !(box.x1 < other.x0 || box.x0 > other.x1
      || box.y1 < other.y0 || box.y0 > other.y1));
    if (hit) return false;
    placedLabels.push(box);
    return true;
  };

  /* 大的先画、小的后画：小气泡压在大气泡上面才不会被整个盖住。 */
  layout.circles.slice().sort((a, b) => b.r - a.r).forEach((circle) => {
    const row = circle.row;
    const step = stepFor(circle.value, band);
    const group = svgEl(layer, "a",
      `bubble-node bubble-ink-${step.ink}${circle.outside ? " bubble-clamped" : ""}`);
    group.setAttribute("href",
      `../finance-terminal/quote.html?kind=company&symbol=${encodeURIComponent(row.symbol)}`);
    group.setAttribute("transform", `translate(${circle.x.toFixed(1)} ${circle.y.toFixed(1)})`);
    group.dataset.symbol = row.symbol;
    const label = `${row.name || row.symbol}（${row.symbol}），${circle.sector}，`
      + `股价 ${formatPrice(row.price)}，市值 ${formatCap(row.marketCap)}，`
      + `${metricLabel} ${formatPct(circle.value)}`
      + (circle.outside ? "（超出纵轴范围，已贴边显示）" : "");
    group.setAttribute("aria-label", label);
    const dot = svgEl(group, "circle", "bubble-dot");
    dot.setAttribute("r", circle.r.toFixed(1));
    dot.setAttribute("fill", step.color);

    /* 字层：名字与股价一起放，一起避让——只写名字不写价、或反过来，读起来是残的。 */
    let priceNode = null;
    if (circle.r >= MIN_R_NAME) {
      const name = pickLabel(row.name, row.symbol, circle.r);
      const withPrice = name && circle.r >= MIN_R_PRICE;
      const w = Math.max(name.length * 11.5, withPrice ? 44 : 0) + 3;
      const h = withPrice ? 25 : 13;
      if (name && fits(circle.x, circle.y, w, h)) {
        const box = svgEl(labelLayer, "g", `bubble-label bubble-ink-${step.ink}`);
        box.setAttribute("transform", `translate(${circle.x.toFixed(1)} ${circle.y.toFixed(1)})`);
        box.dataset.symbol = row.symbol;
        svgText(box, "bubble-name", name,
          { x: 0, y: withPrice ? -2 : 4, "text-anchor": "middle" });
        if (withPrice) {
          priceNode = svgText(box, "bubble-price", formatPrice(row.price),
            { x: 0, y: 12, "text-anchor": "middle" });
        }
        nodes.set(row.symbol, { group, dot, label: box, priceNode, layout: circle });
        return;
      }
    }
    nodes.set(row.symbol, { group, dot, label: null, priceNode: null, layout: circle });
  });
  return { nodes, layout };
}

/* 盘中刷新：只改已经画好的气泡的纵向位置与颜色，不重建 SVG。
   位置用 transform 过渡，因此视觉上是「浮上去/沉下来」，而不是整张图重画。 */
export function updateBubbles(handles, rows, options = {}) {
  if (!handles || !handles.nodes || !handles.layout || !handles.layout.yOf) return 0;
  const metricOf = options.metricOf || ((row) => row.changePct);
  const metricLabel = options.metricLabel || "当日涨跌";
  const band = options.band || 1;
  const yOf = handles.layout.yOf;
  const domain = handles.layout.domain;
  let moved = 0;
  rows.forEach((row) => {
    const handle = handles.nodes.get(row.symbol);
    if (!handle) return;
    const value = metricOf(row);
    if (!isNum(value)) return;
    /* 超出当前纵轴范围就贴边并标出来——悄悄画到框外等于把它藏了。 */
    const clamped = Math.max(domain.min, Math.min(domain.max, value));
    const y = yOf(clamped);
    const step = stepFor(value, band);
    if (Math.abs(y - handle.layout.y) > 0.2) {
      const shift = `translate(${handle.layout.x.toFixed(1)} ${y.toFixed(1)})`;
      handle.group.setAttribute("transform", shift);
      if (handle.label) handle.label.setAttribute("transform", shift);
      handle.layout.y = y;
      moved += 1;
    }
    handle.dot.setAttribute("fill", step.color);
    handle.group.setAttribute("class", `bubble-node bubble-ink-${step.ink}`);
    handle.group.classList.toggle("bubble-clamped", value !== clamped);
    if (handle.priceNode) handle.priceNode.textContent = formatPrice(row.price);
    if (handle.label) handle.label.setAttribute("class", `bubble-label bubble-ink-${step.ink}`);
    handle.group.setAttribute("aria-label",
      `${row.name || row.symbol}（${row.symbol}），${handle.layout.sector}，`
      + `股价 ${formatPrice(row.price)}，市值 ${formatCap(row.marketCap)}，`
      + `${metricLabel} ${formatPct(value)}`);
  });
  return moved;
}

/* 图例与热力图共用同一套色阶，因此这里只负责摆，不另定义颜色。 */
export function paintBubbleLegend(document, host, band = 1, metricLabel = "当日") {
  host.textContent = "";
  const add = (color, text) => {
    const chip = document.createElement("span");
    chip.className = "legend-chip";
    const swatch = document.createElement("i");
    swatch.className = "legend-swatch";
    swatch.style.background = color;
    chip.appendChild(swatch);
    const label = document.createElement("span");
    label.textContent = text;
    chip.appendChild(label);
    host.appendChild(chip);
  };
  const head = document.createElement("span");
  head.className = "legend-label";
  head.textContent = `气泡颜色 = ${metricLabel}涨跌`;
  host.appendChild(head);
  /* 图例写的是**当前这一档**的真实边界：±3% 那套是给当日定的，
     拿去看年初至今会几乎全落在最上一档，颜色就不区分任何东西了。 */
  SCALE.forEach((step) => add(step.color, bandLabel(step, band)));
  add(NO_CHANGE.color, `${metricLabel}涨跌缺失`);
}
