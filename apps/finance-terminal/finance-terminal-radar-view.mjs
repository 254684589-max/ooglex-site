/* 风险雷达构成抽屉：按需加载。

   六个轴不是六项独立测量。站内只有三项已校验信号（宏观状态、恐慌与贪婪、
   OFR金融压力），六个轴由它们按固定权重线性重组而来。图上只看得到六个
   凭空出现的数字，这个抽屉把重组过程原样摊开，让访客能自己核对。 */

import { openPanel, section, row, note } from "./finance-terminal-detail-view.mjs";

/* 权重必须与 finance-terminal-risk-radar.mjs 的 deriveRiskRadar 完全一致；
   两处独立存在会漂移，校验脚本里有断言逐点比对二者输出。
   S 表示恐慌与贪婪的反向读数（100 − s）。轴的顺序即雷达图顶点顺序，
   已按屏幕方位与标签逐一核对。 */
export const RADAR_AXES = Object.freeze([
  Object.freeze({ name: "利率风险", terms: Object.freeze([["m", 1]]) }),
  Object.freeze({ name: "通胀风险", terms: Object.freeze([["m", 0.7], ["y", 0.3]]) }),
  Object.freeze({ name: "汇率风险", terms: Object.freeze([["m", 0.55], ["s", 0.45]]) }),
  Object.freeze({ name: "波动率风险", terms: Object.freeze([["S", 0.72], ["y", 0.28]]) }),
  Object.freeze({ name: "信用风险", terms: Object.freeze([["y", 0.75], ["m", 0.25]]) }),
  Object.freeze({ name: "流动性风险", terms: Object.freeze([["S", 0.55], ["m", 0.45]]) })
]);

const INPUT_LABEL = Object.freeze({
  m: "宏观状态", s: "恐慌与贪婪", S: "恐慌与贪婪反向", y: "OFR金融压力"
});

/* 纯函数：按权重算出某一轴的 0–100 读数，便于离线断言。 */
export function axisValue(axis, m, s, y) {
  const by = { m: m, s: s, S: 100 - s, y: y };
  return axis.terms.reduce((sum, term) => sum + by[term[0]] * term[1], 0);
}

/* 纯函数：把权重写成人能读的算式，如「宏观状态 70% + OFR金融压力 30%」。 */
export function formulaText(axis) {
  return axis.terms
    .map((term) => `${INPUT_LABEL[term[0]]} ${Math.round(term[1] * 100)}%`)
    .join(" + ");
}

/* 与 deriveRiskRadar 相同的取数口径：优先 meterPercent，其次由 value 线性映射。 */
export function readInput(card) {
  if (!card) return null;
  if (Number.isFinite(card.meterPercent)) return Math.min(100, Math.max(0, card.meterPercent));
  if (Number.isFinite(card.value)) return Math.min(100, Math.max(0, 50 + card.value * 8));
  return null;
}

function sourceLink(document, parent, card) {
  const url = card && card.detailUrl;
  if (!url || !/^\.\.\/[a-z-]+\/$/.test(url)) return;
  const link = document.createElement("a");
  link.className = "detail-news";
  link.href = url;
  link.textContent = `查看 ${card.name} 数据页 →`;
  parent.appendChild(link);
}

export function openRadar(document, cards) {
  const list = Array.isArray(cards) ? cards : [];
  const panel = openPanel(document, "风险雷达 · 六轴构成",
    "RISK RADAR · HOW THE SIX AXES ARE DERIVED", "风险雷达六轴构成说明");

  const readings = list.slice(0, 3).map(readInput);
  const complete = readings.length === 3 && readings.every(Number.isFinite);

  const intro = section(document, panel, "这六个轴不是六项独立测量");
  note(document, intro, "站内只有三项已校验信号。六个轴由这三项按固定权重线性重组而来，"
    + "用于呈现风险结构，本身不是新的观测事实。");

  const inputs = section(document, panel, "三项输入");
  list.slice(0, 3).forEach((card, index) => {
    const reading = readings[index];
    row(document, inputs, card && card.name ? card.name : "不可用",
      Number.isFinite(reading)
        ? `${reading.toFixed(1)} / 100 · 数据日 ${(card && card.asOf) || "不可用"}`
        : "读数不可用");
    sourceLink(document, inputs, card);
  });

  const axes = section(document, panel, "六个轴如何算出来");
  if (!complete) {
    note(document, axes, "三项输入中至少一项不可用，雷达此时保持空态，"
      + "这里也不显示由不完整输入推算出的轴值。");
    return panel;
  }

  const [m, s, y] = readings;
  let total = 0;
  RADAR_AXES.forEach((axis) => {
    const value = axisValue(axis, m, s, y);
    total += value;
    row(document, axes, `${axis.name} · ${formulaText(axis)}`, (value / 10).toFixed(1));
  });
  row(document, axes, "综合评分 · 六轴均值", (total / RADAR_AXES.length / 10).toFixed(1));

  note(document, axes, "「利率风险」「通胀风险」等名称描述的是该权重组合意在近似的风险类型，"
    + "不代表站内存在对应的利率、通胀或信用专项数据——例如「利率风险」就是宏观状态本身，"
    + "「通胀风险」不含任何通胀输入。");
  return panel;
}
