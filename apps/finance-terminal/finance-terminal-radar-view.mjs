/* 风险雷达构成抽屉：按需加载。

   六个轴各对应宏观管线里一个已算好的制度信号（波动率来自 VIX 水平与期限结构、
   信用来自高收益债 OAS、流动性来自净流动性与 SOFR−IORB 等）。信号口径是
   「越高越宽松·支持」，风险方向相反，故 风险 = 100 − 信号分数。
   这里把每个轴的来源信号、原始分数与其依据原样列出，供访客核对。 */

import { openPanel, section, row, note } from "./finance-terminal-detail-view.mjs";
import { RADAR_SIGNAL_KEYS } from "./finance-terminal-risk-radar.mjs";

/* 轴名与雷达图上的标签一致，顺序即顶点顺序。 */
export const AXIS_LABELS = Object.freeze([
  "实际利率", "期限溢价", "美元汇率", "波动率", "信用利差", "流动性"
]);

/* 纯函数：信号分数 → 风险读数（0–10），便于离线断言。 */
export function riskReading(score) {
  return Number.isFinite(score) ? (100 - score) / 10 : null;
}

/* 纯函数：把六个轴与其来源信号配对；缺失的信号如实留空，不用其他轴顶替。 */
export function pairAxes(signals) {
  const byKey = new Map((signals || [])
    .filter((signal) => signal && typeof signal.key === "string")
    .map((signal) => [signal.key, signal]));
  return RADAR_SIGNAL_KEYS.map((key, index) => {
    const signal = byKey.get(key) || null;
    return {
      key,
      label: AXIS_LABELS[index] || key,
      signal,
      reading: signal ? riskReading(signal.score) : null
    };
  });
}

function findMacroCard(cards) {
  return (Array.isArray(cards) ? cards : [])
    .find((card) => card && Array.isArray(card.regimeSignals)) || null;
}

export function openRadar(document, cards) {
  const panel = openPanel(document, "风险雷达 · 六轴来源",
    "RISK RADAR · SIGNAL BEHIND EACH AXIS", "风险雷达六轴来源说明");

  const macro = findMacroCard(cards);
  const axes = pairAxes(macro ? macro.regimeSignals : []);
  const complete = axes.every((axis) => Number.isFinite(axis.reading));

  const intro = section(document, panel, "每个轴背后是一项真实测量");
  note(document, intro, "六个轴各取宏观管线里一个已算好的制度信号。"
    + "信号口径是「越高越宽松、越支持」，风险方向相反，故风险读数 = 100 − 信号分数。");

  const list = section(document, panel, "六轴与来源信号");
  axes.forEach((axis) => {
    if (!axis.signal || !Number.isFinite(axis.reading)) {
      row(document, list, `${axis.label} · 信号缺失`, "—");
      return;
    }
    row(document, list, `${axis.label} · ${axis.signal.label || axis.key} ${axis.signal.score}/100`,
      `${axis.reading.toFixed(1)}${axis.signal.statusLabel ? " · " + axis.signal.statusLabel : ""}`);
    if (axis.signal.detail) note(document, list, axis.signal.detail);
  });

  if (!complete) {
    note(document, list, "缺任一信号时雷达整体保持空态——六边形少一个顶点无法成形，"
      + "这里也不用其他轴的值替代缺失项。");
  } else {
    const total = axes.reduce((sum, axis) => sum + axis.reading, 0);
    row(document, list, "综合评分 · 六轴均值", (total / axes.length).toFixed(1));
  }

  const meta = section(document, panel, "口径");
  row(document, meta, "数据日", (macro && macro.asOf) || "不可用");
  row(document, meta, "更新时间", (macro && macro.updatedAt) || "不可用");
  row(document, meta, "来源", (macro && macro.source && macro.source.name) || "不可用");
  const link = document.createElement("a");
  link.className = "detail-news";
  link.href = "../macro-radar/";
  link.textContent = "查看宏观雷达完整方法学 →";
  meta.appendChild(link);
  note(document, meta, "轴名描述的是该信号刻画的风险类型；分数为各自序列在近两年窗口内的"
    + "分位，不是对后市的预测。");
  return panel;
}
