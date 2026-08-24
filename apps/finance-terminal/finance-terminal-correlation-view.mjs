/* 资产相关性矩阵抽屉：按需加载。

   用站内已发布的 asset-tracker 滚动历史算日对数收益率的皮尔逊相关系数。
   三条口径写在这里，抽屉里也逐条说给访客：

   1. 用收益率、不用价位。价位序列本身带趋势，两条各自上涨的价位曲线相关系数
      天然接近 1，那个数字不描述「一起动」。
   2. 只用两个标的都有相邻两日报价的交易日。缺报价不前向填充、不跨日拼接——
      隔了一个休市日的两点之差不是「当日收益率」。
   3. 交易日历对不齐的标的整个不进矩阵。站内历史里若某标的的观测落在周六周日，
      说明它的日线时间戳没按交易所当地日期归档，与其余标的错位；这种错位算出来
      的相关系数是错的（实测欧元兑美元与美元指数应当接近 −0.95，错位样本只给出
      −0.39），宁可点名剔除，也不显示。 */

import { openPanel, section, row, note } from "./finance-terminal-detail-view.mjs";

/* 重叠样本少于这么多个交易日就不给数：样本太少的相关系数不稳定。 */
export const MIN_OVERLAP = 60;
/* 只列这么多条最强正相关与最强负相关——矩阵看趋势，清单看结论。 */
const TOP_PAIRS = 6;
const CATEGORY_ORDER = ["equity", "commodity", "fx", "bond"];

/* 纯函数：价位序列 → 日对数收益率。相邻两日都有正报价才算，其余留空。 */
export function logReturns(values) {
  const out = [];
  for (let index = 0; index < (values || []).length; index += 1) {
    const previous = values[index - 1];
    const current = values[index];
    out.push(index > 0 && previous > 0 && current > 0
      ? Math.log(current / previous)
      : null);
  }
  return out;
}

/* 纯函数：该标的的观测是否都落在工作日。周六周日出现观测，即时间戳未按交易所
   当地日期归档，这条序列与其他标的错位，不能一起算相关。 */
export function sessionAligned(dates, values) {
  return (values || []).every((value, index) => {
    if (value === null || value === undefined) return true;
    const day = new Date(`${dates[index]}T00:00:00Z`).getUTCDay();
    return day !== 0 && day !== 6;
  });
}

/* 纯函数：皮尔逊相关系数。任一侧零方差时不给数——常数序列没有相关性可言。 */
export function pearson(left, right) {
  const pairs = [];
  for (let index = 0; index < left.length; index += 1) {
    if (Number.isFinite(left[index]) && Number.isFinite(right[index])) {
      pairs.push([left[index], right[index]]);
    }
  }
  const n = pairs.length;
  if (n < MIN_OVERLAP) return { value: null, n };
  let sumLeft = 0;
  let sumRight = 0;
  pairs.forEach((pair) => { sumLeft += pair[0]; sumRight += pair[1]; });
  const meanLeft = sumLeft / n;
  const meanRight = sumRight / n;
  let covariance = 0;
  let varianceLeft = 0;
  let varianceRight = 0;
  pairs.forEach((pair) => {
    const dl = pair[0] - meanLeft;
    const dr = pair[1] - meanRight;
    covariance += dl * dr;
    varianceLeft += dl * dl;
    varianceRight += dr * dr;
  });
  if (!(varianceLeft > 0) || !(varianceRight > 0)) return { value: null, n };
  return { value: covariance / Math.sqrt(varianceLeft * varianceRight), n };
}

/* 纯函数：整张矩阵。excluded 逐个记录被剔除的标的与原因，供抽屉如实列出。 */
export function buildMatrix(history, assets) {
  const dates = (history && history.dates) || [];
  const series = (history && history.series) || {};
  const meta = new Map((assets || []).map((asset) => [asset.symbol, asset]));
  const excluded = [];
  const kept = [];
  Object.keys(series).forEach((symbol) => {
    const values = series[symbol];
    const observations = values.filter((value) => value !== null && value !== undefined).length;
    if (!sessionAligned(dates, values)) {
      const weekend = values.filter((value, index) => {
        if (value === null || value === undefined) return false;
        const day = new Date(`${dates[index]}T00:00:00Z`).getUTCDay();
        return day === 0 || day === 6;
      }).length;
      excluded.push({ symbol, weekend, observations, reason: "交易日历错位" });
      return;
    }
    kept.push(symbol);
  });
  kept.sort((left, right) => {
    const leftOrder = CATEGORY_ORDER.indexOf((meta.get(left) || {}).category);
    const rightOrder = CATEGORY_ORDER.indexOf((meta.get(right) || {}).category);
    if (leftOrder !== rightOrder) return leftOrder - rightOrder;
    return left < right ? -1 : 1;
  });
  const returns = new Map(kept.map((symbol) => [symbol, logReturns(series[symbol])]));
  const cells = [];
  kept.forEach((left, leftIndex) => {
    kept.forEach((right, rightIndex) => {
      if (rightIndex <= leftIndex) return;
      const result = pearson(returns.get(left), returns.get(right));
      cells.push({ left, right, value: result.value, n: result.n });
    });
  });
  excluded.sort((left, right) => right.weekend - left.weekend);
  return { symbols: kept, cells, excluded, dates };
}

function cellLookup(cells) {
  const map = new Map();
  cells.forEach((cell) => {
    map.set(`${cell.left}|${cell.right}`, cell);
    map.set(`${cell.right}|${cell.left}`, cell);
  });
  return map;
}

/* 相关系数 → 颜色。正为青、负为琥珀，与终端其他面板一致；0 附近保持底色，
   不用红绿——相关性本身无所谓好坏。 */
function cellColor(value) {
  if (!Number.isFinite(value)) return "transparent";
  const weight = Math.min(1, Math.abs(value)) * 0.8;
  return value >= 0
    ? `rgba(69, 212, 255, ${weight.toFixed(2)})`
    : `rgba(244, 192, 92, ${weight.toFixed(2)})`;
}

function shortLabel(asset, symbol) {
  const name = (asset && asset.name) || symbol;
  return name.length > 6 ? `${name.slice(0, 6)}…` : name;
}

function drawMatrix(document, parent, matrix, meta) {
  const lookup = cellLookup(matrix.cells);
  const grid = document.createElement("div");
  grid.className = "corr-grid";
  grid.style.setProperty("--corr-columns", String(matrix.symbols.length + 1));
  const corner = document.createElement("span");
  corner.className = "corr-head corr-corner";
  grid.appendChild(corner);
  matrix.symbols.forEach((symbol) => {
    const head = document.createElement("span");
    head.className = "corr-head";
    head.textContent = shortLabel(meta.get(symbol), symbol);
    head.title = symbol;
    grid.appendChild(head);
  });
  matrix.symbols.forEach((left) => {
    const label = document.createElement("span");
    label.className = "corr-head corr-row-head";
    label.textContent = shortLabel(meta.get(left), left);
    label.title = left;
    grid.appendChild(label);
    matrix.symbols.forEach((right) => {
      const cell = document.createElement("span");
      cell.className = "corr-cell";
      if (left === right) {
        cell.className = "corr-cell corr-self";
        cell.textContent = "—";
        grid.appendChild(cell);
        return;
      }
      const entry = lookup.get(`${left}|${right}`);
      if (!entry || !Number.isFinite(entry.value)) {
        cell.classList.add("corr-empty");
        cell.textContent = "";
        cell.title = `${left} / ${right} 重叠样本不足`;
      } else {
        cell.style.background = cellColor(entry.value);
        cell.textContent = entry.value.toFixed(1).replace("0.", ".").replace("-.", "−.");
        cell.title = `${left} / ${right} ${entry.value.toFixed(2)}（${entry.n} 个交易日）`;
      }
      grid.appendChild(cell);
    });
  });
  const scroller = document.createElement("div");
  scroller.className = "corr-scroll";
  scroller.appendChild(grid);
  parent.appendChild(scroller);
}

function listExtremes(document, parent, matrix, meta) {
  const ranked = matrix.cells
    .filter((cell) => Number.isFinite(cell.value))
    .sort((left, right) => right.value - left.value);
  const label = (symbol) => (meta.get(symbol) || {}).name || symbol;
  ranked.slice(0, TOP_PAIRS).forEach((cell) => {
    row(document, parent, `${label(cell.left)} / ${label(cell.right)}`,
      `+${cell.value.toFixed(2)} · ${cell.n}日`);
  });
  const negative = ranked.slice(-TOP_PAIRS).reverse();
  negative.forEach((cell) => {
    row(document, parent, `${label(cell.left)} / ${label(cell.right)}`,
      `${cell.value.toFixed(2).replace("-", "−")} · ${cell.n}日`);
  });
}

const STYLE_ID = "finance-terminal-corr-style";
const STYLE_TEXT = `
.corr-scroll{overflow-x:auto;margin-bottom:8px;-webkit-overflow-scrolling:touch}
.corr-grid{display:grid;grid-template-columns:repeat(var(--corr-columns),minmax(22px,1fr));
 gap:1px;min-width:340px}
.corr-head{display:flex;align-items:center;justify-content:center;overflow:hidden;
 padding:2px 1px;color:var(--faint);font:6px var(--mono);text-align:center;word-break:break-all}
.corr-row-head{justify-content:flex-end;padding-right:3px;text-align:right}
.corr-cell{display:flex;min-height:15px;align-items:center;justify-content:center;
 border:1px solid rgba(140,152,170,.14);color:var(--ink);font:6px var(--mono);
 font-variant-numeric:tabular-nums}
.corr-self{border-style:dashed;color:var(--faint)}
.corr-empty{background:repeating-linear-gradient(45deg,transparent,transparent 2px,
 rgba(140,152,170,.16) 2px,rgba(140,152,170,.16) 4px)}
`;

function ensureStyle(document) {
  if (document.getElementById(STYLE_ID)) return;
  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = STYLE_TEXT;
  document.head.appendChild(style);
}

function loadJson(path) {
  return fetch(path, { cache: "no-store" })
    .then((response) => (response.ok ? response.json() : null))
    .catch(() => null);
}

export async function openCorrelation(document) {
  const panel = openPanel(document, "资产相关性矩阵",
    "ASSET CORRELATION · DAILY LOG RETURNS", "资产相关性矩阵");
  ensureStyle(document);
  const body = document.createElement("div");
  body.className = "detail-body";
  panel.appendChild(body);

  const [history, tracker] = await Promise.all([
    loadJson("../asset-tracker/history.json"),
    loadJson("../asset-tracker/data.json")
  ]);
  if (!document.getElementById(STYLE_ID)) return panel;
  if (!history || !Array.isArray(history.dates) || !history.series) {
    note(document, section(document, body, "矩阵"),
      "站内尚未生成滚动历史文件；日更任务运行后此处会显示相关性矩阵。"
      + "在此之前不显示推算值。");
    return panel;
  }

  const assets = (tracker && Array.isArray(tracker.assets)) ? tracker.assets : [];
  const meta = new Map(assets.map((asset) => [asset.symbol, asset]));
  const matrix = buildMatrix(history, assets);

  const intro = section(document, body,
    `${matrix.symbols.length} 个标的 · 数据日 ${history.asOf || "不可用"}`);
  note(document, intro, "格子里是两个标的日对数收益率的皮尔逊相关系数（−1 到 +1）。"
    + "青色为同向、琥珀为反向，颜色越深绝对值越大；"
    + "悬停可看该格的系数与实际重叠交易日数。");

  const chart = section(document, body, "矩阵");
  if (matrix.symbols.length >= 2) drawMatrix(document, chart, matrix, meta);
  else note(document, chart, "交易日历对齐的标的不足两个，本轮不绘制矩阵。");

  const insufficient = matrix.cells.filter((cell) => !Number.isFinite(cell.value));
  if (insufficient.length) {
    note(document, chart, `${insufficient.length} 组配对的重叠交易日少于 ${MIN_OVERLAP} 天，`
      + "格子以斜纹留空，不给出不稳定的系数。");
  }

  const extremes = section(document, body, `最强同向与最强反向 · 各 ${TOP_PAIRS} 组`);
  listExtremes(document, extremes, matrix, meta);
  note(document, extremes, "这是所选窗口内的历史统计，不是对后市的预测，"
    + "也不表示其中一个标的的变动导致了另一个。");

  if (matrix.excluded.length) {
    const dropped = section(document, body, `未纳入 · ${matrix.excluded.length} 个标的`);
    matrix.excluded.forEach((item) => {
      const asset = meta.get(item.symbol);
      row(document, dropped, `${(asset && asset.name) || item.symbol}（${item.symbol}）`,
        `${item.weekend}/${item.observations} 个观测落在周末`);
    });
    note(document, dropped, "这些标的在站内历史里的日线戳到了周六或周日，"
      + "说明其时间戳未按交易所当地日期归档，与其余标的的交易日错位。"
      + "错位样本算出的相关系数是错的，因此整列不纳入，也不显示。");
  }

  const source = section(document, body, "来源与口径");
  row(document, source, "来源", history.source || "不可用");
  row(document, source, "频率", history.frequency === "daily" ? "日频" : (history.frequency || "不可用"));
  row(document, source, "更新时间", history.updatedAt || "不可用");
  row(document, source, "日期轴长度", `${(history.dates || []).length} 个交易日`);
  row(document, source, "最少重叠样本", `${MIN_OVERLAP} 个交易日`);
  note(document, source, "收益率按相邻两日都有报价的交易日计算；缺报价处不前向填充，"
    + "也不把跨休市日的两点之差当作当日收益率。");
  return panel;
}
