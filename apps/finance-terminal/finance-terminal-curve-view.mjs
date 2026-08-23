/* 美债收益率曲线抽屉：按需加载。

   十一个期限来自 FRED 官方序列，共享日期轴。缺读数的期限直接断开折线，
   不插值、不用相邻期限顶替；非当日观测单独标注。倒挂只在两端同日都有
   观测时判定。 */

import { openPanel, section, row, note } from "./finance-terminal-detail-view.mjs";

const WIDTH = 520;
const HEIGHT = 170;
const PAD = 26;

/* 纯函数：把期限按月数映射到对数横轴，短端才不会挤成一团。 */
export function tenorX(months, minMonths, maxMonths) {
  if (!(months > 0) || !(minMonths > 0) || !(maxMonths > minMonths)) return PAD;
  const span = Math.log(maxMonths) - Math.log(minMonths);
  return PAD + (Math.log(months) - Math.log(minMonths)) / span * (WIDTH - PAD * 2);
}

/* 纯函数：读数映射到纵轴；上下各留一点余量，避免极值贴边。 */
export function valueY(value, low, high) {
  const span = high - low || 1;
  return HEIGHT - PAD - (value - low) / span * (HEIGHT - PAD * 2);
}

/* 纯函数：生成折线段。缺读数处断开，返回多段而非一条穿过空洞的线。 */
export function curveSegments(points) {
  const segments = [];
  let current = [];
  (points || []).forEach((point) => {
    if (point && Number.isFinite(point.value)) current.push(point);
    else if (current.length) { segments.push(current); current = []; }
  });
  if (current.length) segments.push(current);
  return segments.filter((segment) => segment.length > 1);
}

/* 纯函数：形态判断只用实际读数，缺档不猜。 */
export function describeShape(tenors) {
  const usable = (tenors || []).filter((tenor) => Number.isFinite(tenor.value));
  if (usable.length < 3) return "读数不足，不判断形态";
  const short = usable[0].value;
  const long = usable[usable.length - 1].value;
  const gap = long - short;
  if (gap < -0.1) return "整体倒挂 · 短端高于长端";
  if (gap > 0.5) return "正常上行 · 长端明显高于短端";
  return "较为平坦 · 长短端接近";
}

function loadCurve() {
  return fetch("../macro-radar/curve.json", { cache: "no-store" })
    .then((response) => (response.ok ? response.json() : null))
    .catch(() => null);
}

function drawCurve(document, parent, curve) {
  const tenors = curve.tenors || [];
  const usable = tenors.filter((tenor) => Number.isFinite(tenor.value));
  if (usable.length < 2) {
    note(document, parent, "本轮可用期限不足两个，不绘制曲线，也不以推断值补齐。");
    return;
  }
  const months = usable.map((tenor) => tenor.months);
  const values = usable.map((tenor) => tenor.value);
  const minMonths = Math.min(...months);
  const maxMonths = Math.max(...months);
  const low = Math.min(...values);
  const high = Math.max(...values);

  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("class", "curve-chart");
  svg.setAttribute("viewBox", `0 0 ${WIDTH} ${HEIGHT}`);
  svg.setAttribute("role", "img");
  svg.setAttribute("aria-label",
    `美债收益率曲线，${usable.length} 个期限，自 ${usable[0].label} ${usable[0].value}% `
    + `至 ${usable[usable.length - 1].label} ${usable[usable.length - 1].value}%`);

  const points = tenors.map((tenor) => (Number.isFinite(tenor.value)
    ? { ...tenor, x: tenorX(tenor.months, minMonths, maxMonths), y: valueY(tenor.value, low, high) }
    : null));

  curveSegments(points).forEach((segment) => {
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("class", "curve-line");
    path.setAttribute("d", segment
      .map((point, index) => `${index ? "L" : "M"}${point.x.toFixed(1)} ${point.y.toFixed(1)}`)
      .join(" "));
    svg.appendChild(path);
  });

  points.forEach((point) => {
    if (!point) return;
    const dot = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    dot.setAttribute("class", point.current ? "curve-dot" : "curve-dot curve-dot-stale");
    dot.setAttribute("cx", point.x.toFixed(1));
    dot.setAttribute("cy", point.y.toFixed(1));
    dot.setAttribute("r", "2.6");
    svg.appendChild(dot);
    const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
    label.setAttribute("class", "curve-tick");
    label.setAttribute("x", point.x.toFixed(1));
    label.setAttribute("y", HEIGHT - 8);
    label.setAttribute("text-anchor", "middle");
    label.textContent = point.label;
    svg.appendChild(label);
  });

  parent.appendChild(svg);
  row(document, parent, "区间", `${low}% — ${high}%`);
  row(document, parent, "形态", describeShape(tenors));
}

const STYLE_ID = "finance-terminal-curve-style";
const STYLE_TEXT = `
.curve-chart{display:block;width:100%;height:auto;margin-bottom:6px}
.curve-line{fill:none;stroke:var(--vision-cyan);stroke-width:1.6}
.curve-dot{fill:var(--vision-cyan)}
.curve-dot-stale{fill:none;stroke:var(--vision-amber);stroke-width:1.2}
.curve-tick{fill:var(--faint);font:7px var(--mono)}
`;

function ensureCurveStyle(document) {
  if (document.getElementById(STYLE_ID)) return;
  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = STYLE_TEXT;
  document.head.appendChild(style);
}

export async function openCurve(document) {
  const panel = openPanel(document, "美债收益率曲线",
    "U.S. TREASURY YIELD CURVE · FRED H.15", "美债收益率曲线");
  ensureCurveStyle(document);
  const body = document.createElement("div");
  body.className = "detail-body";
  panel.appendChild(body);

  const curve = await loadCurve();
  if (!document.getElementById(STYLE_ID)) return panel;
  if (!curve || !Array.isArray(curve.tenors)) {
    note(document, section(document, body, "曲线"),
      "站内尚未生成收益率曲线文件；日更任务运行后此处会显示完整期限结构。"
      + "在此之前不显示推断值。");
    return panel;
  }

  const chart = section(document, body, `期限结构 · 数据日 ${curve.asOf || "不可用"}`);
  drawCurve(document, chart, curve);

  const missing = (curve.tenors || []).filter((tenor) => !Number.isFinite(tenor.value));
  const lagging = (curve.tenors || []).filter((tenor) => Number.isFinite(tenor.value) && !tenor.current);
  if (missing.length) {
    note(document, chart, `${missing.map((tenor) => tenor.label).join("、")} 本轮无观测，曲线在该处断开，未做插值。`);
  }
  if (lagging.length) {
    note(document, chart, `${lagging.map((tenor) => `${tenor.label}（${tenor.asOf}）`).join("、")} `
      + "为较早观测，图上以空心点标出。");
  }

  const spreadBox = section(document, body, "关键利差");
  (curve.spreads || []).forEach((spread) => {
    row(document, spreadBox, `${spread.id} · 数据日 ${spread.asOf}`,
      `${spread.value > 0 ? "+" : ""}${spread.value} 个百分点${spread.inverted ? " · 倒挂" : ""}`);
  });
  if (!(curve.spreads || []).length) {
    note(document, spreadBox, "两端缺少同日观测，本轮不计算利差。");
  } else {
    note(document, spreadBox, "利差只在两端同日都有观测时计算；倒挂是该口径下的事实陈述，不构成对后市的预测。");
  }

  const meta = section(document, body, "来源与口径");
  row(document, meta, "来源", curve.source || "不可用");
  row(document, meta, "频率", curve.frequency === "daily" ? "日频" : (curve.frequency || "不可用"));
  row(document, meta, "更新时间", curve.updatedAt || "不可用");
  row(document, meta, "历史点位", String((curve.history && curve.history.dates || []).length));
  if (curve.sourceUrl) {
    const link = document.createElement("a");
    link.className = "detail-news";
    link.href = curve.sourceUrl;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.textContent = "前往 FRED 查看原始序列";
    meta.appendChild(link);
  }
  note(document, meta, curve.note || "");
  return panel;
}
