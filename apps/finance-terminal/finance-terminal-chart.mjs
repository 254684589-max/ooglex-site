/* 走势图渲染器：一份实现，供行情详情页与后续别的分区共用。

   只画传进来的点，不做任何补点、插值或平滑：缺观测的位置由调用方在取点时就剔除，
   坐标轴刻度直接由这批点的极值算出，读数游标显示的是命中的那个真实观测。 */

const NS = "http://www.w3.org/2000/svg";
const BOX = Object.freeze({ width: 960, height: 340, left: 62, right: 18, top: 18, bottom: 30 });

function node(parent, tag, className) {
  const created = parent.ownerDocument.createElementNS(NS, tag);
  if (className) created.setAttribute("class", className);
  parent.appendChild(created);
  return created;
}

export function isNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

/* 纯函数：把观测折成坐标。points 为 [{label, value}]，按输入顺序即时间顺序。 */
export function layout(points, box = BOX) {
  const usable = (points || []).filter((point) => point && isNumber(point.value));
  if (usable.length < 2) return null;
  const values = usable.map((point) => point.value);
  const low = Math.min(...values);
  const high = Math.max(...values);
  const pad = (high - low) * 0.08 || Math.abs(high || 1) * 0.02 || 1;
  const floor = low - pad;
  const ceiling = high + pad;
  const innerW = box.width - box.left - box.right;
  const innerH = box.height - box.top - box.bottom;
  /* 点自带 at（真实时间序号）时按时间轴摆放：数据源对超长区间会自行降采样，
     若一律按数组下标等距摆放，稀疏时段会被拉宽成和密集时段一样，读出来的形状就是假的。 */
  const stamps = usable.map((point, index) => (Number.isFinite(point.at) ? point.at : index));
  const firstStamp = stamps[0];
  const lastStamp = stamps[stamps.length - 1];
  const span = lastStamp - firstStamp || 1;
  const x = (index) => box.left + (usable.length === 1 ? innerW / 2
    : (stamps[index] - firstStamp) / span * innerW);
  const y = (value) => box.top + (1 - (value - floor) / (ceiling - floor)) * innerH;
  return {
    points: usable,
    low,
    high,
    floor,
    ceiling,
    box,
    coords: usable.map((point, index) => [x(index), y(point.value)]),
    x,
    y
  };
}

/* 纯函数：纵轴刻度，取 5 档等分，标签由调用方给的格式化函数决定。 */
export function ticks(plan, count = 5) {
  if (!plan) return [];
  const step = (plan.ceiling - plan.floor) / (count - 1);
  return Array.from({ length: count }, (unused, index) => {
    const value = plan.floor + step * index;
    return { value, y: plan.y(value) };
  });
}

function path(coords) {
  return coords.map(([px, py], index) => `${index ? "L" : "M"}${px.toFixed(1)} ${py.toFixed(1)}`).join(" ");
}

/* 渲染：返回一个可查询的句柄，调用方可以问「当前游标停在哪个观测上」。 */
export function renderChart(document, host, options = {}) {
  const plan = layout(options.points);
  host.textContent = "";
  if (!plan) {
    const empty = document.createElement("p");
    empty.className = "quote-chart-empty";
    empty.textContent = options.emptyText || "站内暂无该区间的历史序列，这里不画任何推断曲线。";
    host.appendChild(empty);
    return null;
  }
  const direction = plan.points[plan.points.length - 1].value >= plan.points[0].value ? "up" : "down";
  const format = typeof options.format === "function"
    ? options.format
    : (value) => value.toFixed(2);
  const uid = `chart-${Math.random().toString(36).slice(2, 8)}`;

  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("class", `quote-chart quote-chart-${direction}`);
  svg.setAttribute("viewBox", `0 0 ${plan.box.width} ${plan.box.height}`);
  svg.setAttribute("preserveAspectRatio", "none");
  svg.setAttribute("role", "img");
  svg.setAttribute("tabindex", "0");
  svg.setAttribute("aria-label", options.label
    || `走势图：${plan.points.length} 个观测，区间最低 ${format(plan.low)}，最高 ${format(plan.high)}`);

  const defs = node(svg, "defs");
  const gradient = node(defs, "linearGradient");
  gradient.setAttribute("id", `${uid}-fill`);
  gradient.setAttribute("x1", "0");
  gradient.setAttribute("x2", "0");
  gradient.setAttribute("y1", "0");
  gradient.setAttribute("y2", "1");
  const stopTop = node(gradient, "stop");
  stopTop.setAttribute("offset", "0");
  stopTop.setAttribute("stop-color", "currentColor");
  stopTop.setAttribute("stop-opacity", "0.34");
  const stopBottom = node(gradient, "stop");
  stopBottom.setAttribute("offset", "1");
  stopBottom.setAttribute("stop-color", "currentColor");
  stopBottom.setAttribute("stop-opacity", "0");

  const grid = node(svg, "g", "quote-grid");
  ticks(plan).forEach((tick) => {
    const line = node(grid, "line");
    line.setAttribute("x1", String(plan.box.left));
    line.setAttribute("x2", String(plan.box.width - plan.box.right));
    line.setAttribute("y1", tick.y.toFixed(1));
    line.setAttribute("y2", tick.y.toFixed(1));
    const label = node(grid, "text", "quote-grid-label");
    label.setAttribute("x", String(plan.box.left - 8));
    label.setAttribute("y", (tick.y + 3.5).toFixed(1));
    label.setAttribute("text-anchor", "end");
    label.textContent = format(tick.value);
  });

  const line = path(plan.coords);
  const [firstX] = plan.coords[0];
  const [lastX] = plan.coords[plan.coords.length - 1];
  const baseline = plan.box.height - plan.box.bottom;
  const area = node(svg, "path", "quote-area");
  area.setAttribute("d", `${line} L${lastX.toFixed(1)} ${baseline} L${firstX.toFixed(1)} ${baseline} Z`);
  area.setAttribute("fill", `url(#${uid}-fill)`);
  const stroke = node(svg, "path", "quote-line");
  stroke.setAttribute("d", line);

  /* 极值标注：区间最高与最低各标一个点，标签贴着点走，不遮住曲线两端。 */
  const highIndex = plan.points.reduce((best, point, index) =>
    point.value > plan.points[best].value ? index : best, 0);
  const lowIndex = plan.points.reduce((best, point, index) =>
    point.value < plan.points[best].value ? index : best, 0);
  [[highIndex, "high"], [lowIndex, "low"]].forEach(([index, kind]) => {
    const [px, py] = plan.coords[index];
    const dot = node(svg, "circle", `quote-extreme quote-extreme-${kind}`);
    dot.setAttribute("cx", px.toFixed(1));
    dot.setAttribute("cy", py.toFixed(1));
    dot.setAttribute("r", "3.4");
    const label = node(svg, "text", `quote-extreme-label quote-extreme-label-${kind}`);
    label.setAttribute("x", Math.min(Math.max(px, plan.box.left + 26), plan.box.width - plan.box.right - 26).toFixed(1));
    label.setAttribute("y", (kind === "high" ? py - 9 : py + 15).toFixed(1));
    label.setAttribute("text-anchor", "middle");
    label.textContent = `${kind === "high" ? "高" : "低"} ${format(plan.points[index].value)}`;
  });

  const axis = node(svg, "g", "quote-axis");
  [0, Math.floor((plan.points.length - 1) / 2), plan.points.length - 1].forEach((index, slot) => {
    const label = node(axis, "text", "quote-axis-label");
    const [px] = plan.coords[index];
    label.setAttribute("x", px.toFixed(1));
    label.setAttribute("y", String(plan.box.height - 9));
    label.setAttribute("text-anchor", slot === 0 ? "start" : (slot === 2 ? "end" : "middle"));
    label.textContent = plan.points[index].label;
  });

  const cursor = node(svg, "g", "quote-cursor");
  cursor.setAttribute("aria-hidden", "true");
  const cursorLine = node(cursor, "line", "quote-cursor-line");
  cursorLine.setAttribute("y1", String(plan.box.top));
  cursorLine.setAttribute("y2", String(baseline));
  const cursorDot = node(cursor, "circle", "quote-cursor-dot");
  cursorDot.setAttribute("r", "4.2");
  cursor.style.opacity = "0";

  host.appendChild(svg);
  const readout = document.createElement("p");
  readout.className = "quote-readout";
  readout.setAttribute("role", "status");
  readout.textContent = options.readoutHint || "把鼠标移到图上（或聚焦后按左右方向键）可读出逐点数值。";
  host.appendChild(readout);

  let active = -1;
  function show(index) {
    if (index < 0 || index >= plan.points.length) return;
    active = index;
    const [px, py] = plan.coords[index];
    cursorLine.setAttribute("x1", px.toFixed(1));
    cursorLine.setAttribute("x2", px.toFixed(1));
    cursorDot.setAttribute("cx", px.toFixed(1));
    cursorDot.setAttribute("cy", py.toFixed(1));
    cursor.style.opacity = "1";
    const point = plan.points[index];
    readout.textContent = `${point.label} · ${format(point.value)}${options.unit || ""}`;
  }
  function hide() {
    active = -1;
    cursor.style.opacity = "0";
    readout.textContent = options.readoutHint || "把鼠标移到图上（或聚焦后按左右方向键）可读出逐点数值。";
  }
  function indexFromClientX(clientX) {
    const rect = svg.getBoundingClientRect();
    if (!rect.width) return -1;
    const ratio = (clientX - rect.left) / rect.width * plan.box.width;
    let best = 0;
    let bestGap = Infinity;
    plan.coords.forEach(([px], index) => {
      const gap = Math.abs(px - ratio);
      if (gap < bestGap) {
        bestGap = gap;
        best = index;
      }
    });
    return best;
  }
  svg.addEventListener("pointermove", (event) => { show(indexFromClientX(event.clientX)); });
  svg.addEventListener("pointerleave", hide);
  svg.addEventListener("blur", hide);
  svg.addEventListener("keydown", (event) => {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    event.preventDefault();
    const start = active < 0 ? plan.points.length - 1 : active;
    show(Math.max(0, Math.min(plan.points.length - 1, start + (event.key === "ArrowRight" ? 1 : -1))));
  });
  return {
    points: plan.points.length,
    low: plan.low,
    high: plan.high,
    first: plan.points[0],
    last: plan.points[plan.points.length - 1],
    direction
  };
}
