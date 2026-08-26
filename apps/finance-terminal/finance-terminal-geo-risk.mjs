/* 地缘风险定价：读的是「市场为地缘风险付出的价格」，不统计也不解读地缘政治事件本身。
   四条轴全部来自站内已在日更的公开管道（跨资产行情、宏观雷达、OFR、无一例外），
   每条轴都给出原值、映射口径、来源与数据日，任一轴缺失即整卡不给等级——
   不用三条轴的平均去顶替四条轴的结论，也不引入任何AI生成文本作为数据来源。 */

/* 五档等级：分数落在 [下界, 上界) 内即为该档；上界100那档含端点。 */
export const GEO_LEVELS = Object.freeze([
  { key: "low", label: "低", floor: 0 },
  { key: "mild", label: "偏低", floor: 20 },
  { key: "mid", label: "中性", floor: 40 },
  { key: "high", label: "偏高", floor: 60 },
  { key: "severe", label: "高", floor: 80 }
]);

/* 四条轴的定义与权重；权重相等，任何一条都不会被悄悄加权。 */
export const GEO_AXES = Object.freeze([
  { key: "energy", label: "能源溢价", weight: 25 },
  { key: "haven", label: "避险需求", weight: 25 },
  { key: "volatility", label: "波动率制度", weight: 25 },
  { key: "stress", label: "金融压力", weight: 25 }
]);

function isNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

export function clampScore(value) {
  if (!isNumber(value)) return null;
  return Math.max(0, Math.min(100, Math.round(value)));
}

/* 纯函数：把一个原值按显式区间线性映射到0–100，超出区间取端点（并如实标注已取端点）。 */
export function linearScore(value, low, high) {
  if (!isNumber(value) || !isNumber(low) || !isNumber(high) || high === low) return null;
  return clampScore((value - low) / (high - low) * 100);
}

/* 纯函数：当前值在给定观测窗口里的百分位（小于等于它的观测占比）。
   窗口本身来自上游文件保存的序列，不做任何插值或补点。 */
export function percentileScore(series, value) {
  if (!isNumber(value)) return null;
  const points = (series || []).filter(isNumber);
  if (points.length < 12) return null;
  const below = points.filter((point) => point <= value).length;
  return clampScore(below / points.length * 100);
}

export function levelOf(score) {
  if (!isNumber(score)) return null;
  return GEO_LEVELS.filter((level) => score >= level.floor).slice(-1)[0] || GEO_LEVELS[0];
}

function asOfDate(value) {
  const text = String(value || "");
  return /^\d{4}-\d{2}-\d{2}T/.test(text) ? text.slice(0, 10) : text;
}

function pickAsset(tracker, symbol) {
  const assets = tracker && Array.isArray(tracker.assets) ? tracker.assets : [];
  return assets.filter((asset) => asset && asset.symbol === symbol)[0] || null;
}

function monthReturn(asset) {
  return asset && asset.returns && isNumber(asset.returns.m1) ? asset.returns.m1 : null;
}

function signedPercent(value, unit) {
  if (!isNumber(value)) return "—";
  return `${value > 0 ? "+" : ""}${value.toFixed(2)}${unit || "%"}`;
}

function sourceOf(entry) {
  const data = entry && !entry.error ? entry.data : null;
  return data || null;
}

/* 能源溢价：布伦特近一个月涨幅按 ±15% 线性映射。地缘供给风险最先反映在原油溢价上；
   WTI 同期涨幅一并显示，作为同一判断的旁证，不参与打分。 */
function energyAxis(tracker) {
  const brent = pickAsset(tracker, "BZ=F");
  const wti = pickAsset(tracker, "CL=F");
  const value = monthReturn(brent);
  const score = linearScore(value, -15, 15);
  if (!isNumber(score)) return { key: "energy", available: false, reason: "跨资产管道里没有可用的布伦特原油近一月涨幅" };
  const meta = brent.dataMeta || {};
  return {
    key: "energy",
    available: true,
    score,
    rawText: `布油近1个月 ${signedPercent(value)}`
      + (isNumber(monthReturn(wti)) ? ` · WTI ${signedPercent(monthReturn(wti))}` : ""),
    method: "按 −15% ~ +15% 线性映射，超出取端点",
    sourceName: meta.source || "Yahoo Finance",
    asOf: asOfDate(meta.asOf),
    updatedAt: meta.updatedAt || "",
    stale: brent.stale === true
  };
}

/* 避险需求：黄金与标普500的近一月涨幅差（百分点）按 ±15 线性映射。
   黄金跑赢股票越多，说明市场买入避险资产的力度越大。 */
function havenAxis(tracker) {
  const gold = pickAsset(tracker, "GC=F");
  const equity = pickAsset(tracker, "^GSPC");
  const goldReturn = monthReturn(gold);
  const equityReturn = monthReturn(equity);
  if (!isNumber(goldReturn) || !isNumber(equityReturn)) {
    return { key: "haven", available: false, reason: "跨资产管道里缺黄金或标普500的近一月涨幅" };
  }
  const spread = goldReturn - equityReturn;
  const meta = gold.dataMeta || {};
  return {
    key: "haven",
    available: true,
    score: linearScore(spread, -15, 15),
    rawText: `黄金 ${signedPercent(goldReturn)} − 标普500 ${signedPercent(equityReturn)}`
      + ` = ${signedPercent(spread, "个百分点")}`,
    method: "按 −15 ~ +15 个百分点线性映射，超出取端点",
    sourceName: meta.source || "Yahoo Finance",
    asOf: asOfDate(meta.asOf),
    updatedAt: meta.updatedAt || "",
    stale: gold.stale === true || equity.stale === true
  };
}

/* 波动率制度：直接取宏观雷达已经算好的波动率信号分（高=支持风险偏好），
   风险方向为 100 减该分数——与首屏风险雷达的取向完全一致，不另起一套算法。 */
function volatilityAxis(macro) {
  const signals = macro && Array.isArray(macro.signals) ? macro.signals : [];
  const signal = signals.filter((item) => item && item.key === "volatility")[0];
  if (!signal || !isNumber(signal.score)) {
    return { key: "volatility", available: false, reason: "宏观雷达里没有可用的波动率制度信号" };
  }
  return {
    key: "volatility",
    available: true,
    score: clampScore(100 - signal.score),
    rawText: `宏观雷达波动率信号 ${signal.score}/100（${signal.statusZh || signal.status || "—"}）`,
    method: "风险方向 = 100 − 信号分，与首屏风险雷达同一取向",
    sourceName: macro.source || "",
    asOf: asOfDate(macro.asOf),
    updatedAt: macro.updatedAt || "",
    stale: false
  };
}

/* 金融压力：OFR 金融压力指数当前值在该文件自己保存的观测窗口里的百分位。
   FSI 没有固定量纲，用百分位而不是拍脑袋的阈值来定位当前读数。 */
function stressAxis(ofr) {
  const fsi = ofr && ofr.fsi ? ofr.fsi : null;
  if (!fsi || !isNumber(fsi.value)) {
    return { key: "stress", available: false, reason: "OFR金融压力指数当前不可用" };
  }
  const spark = Array.isArray(fsi.spark) ? fsi.spark.slice() : [];
  if (spark[spark.length - 1] !== fsi.value) spark.push(fsi.value);
  const score = percentileScore(spark, fsi.value);
  if (!isNumber(score)) {
    return { key: "stress", available: false, reason: "OFR金融压力指数的站内观测窗口不足以定位百分位" };
  }
  return {
    key: "stress",
    available: true,
    score,
    rawText: `OFR FSI ${fsi.value.toFixed(2)}，处于站内 ${spark.filter(isNumber).length} 个观测的第 ${score} 百分位`,
    method: "百分位取自该文件自己保存的观测窗口，不设人为阈值",
    sourceName: ofr.source || "U.S. Office of Financial Research (OFR)",
    asOf: asOfDate(ofr.asOf),
    updatedAt: ofr.updatedAt || "",
    stale: false
  };
}

/* 组装：四条轴齐了才给等级；缺任何一条都只说明缺哪一条，不给分数。 */
export function buildGeoRisk(group = {}) {
  const tracker = sourceOf(group.assetTracker);
  const macro = sourceOf(group.macro);
  const ofr = sourceOf(group.ofr);
  const axes = [
    energyAxis(tracker),
    havenAxis(tracker),
    volatilityAxis(macro),
    stressAxis(ofr)
  ].map((axis) => {
    const definition = GEO_AXES.filter((item) => item.key === axis.key)[0];
    return Object.assign({ label: definition.label, weight: definition.weight }, axis);
  });
  const missing = axes.filter((axis) => !axis.available);
  if (missing.length) {
    return {
      available: false,
      axes,
      missing: missing.map((axis) => `${axis.label}：${axis.reason}`),
      score: null,
      level: null
    };
  }
  const score = clampScore(axes.reduce((sum, axis) => sum + axis.score * axis.weight, 0) / 100);
  const dates = axes.map((axis) => axis.asOf).filter(Boolean).sort();
  return {
    available: true,
    axes,
    missing: [],
    score,
    level: levelOf(score),
    asOf: dates[0] || "",
    stale: axes.some((axis) => axis.stale === true),
    sources: axes.map((axis) => axis.sourceName).filter(Boolean)
      .filter((name, index, list) => list.indexOf(name) === index)
  };
}

/* 更新时间按上游文件里的UTC时点原样显示，只去掉秒；不换算、不改写。 */
function formatUpdated(value) {
  const text = String(value || "");
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(text)) return "不可用";
  return `${text.slice(0, 10)} ${text.slice(11, 16)} UTC`;
}

function text(parent, tag, className, content) {
  const node = parent.ownerDocument.createElement(tag);
  if (className) node.className = className;
  if (content !== undefined && content !== null) node.textContent = content;
  parent.appendChild(node);
  return node;
}

const MODEL_NOTE = "本模型读的是市场为地缘风险付出的价格：能源溢价、避险需求、波动率制度与金融压力四条轴等权，"
  + "全部由站内已在日更的公开管道逐日复算。它不统计、不解读地缘政治事件本身，"
  + "也不使用任何AI生成的文本作为数据来源；四条轴缺任何一条即不给等级。";

/* 渲染：等级梯 + 分数 + 四条轴的原值与口径。任一轴缺失时只写明缺哪一条。 */
export function renderGeoRisk(document, host, model) {
  if (!host) return;
  host.textContent = "";
  host.hidden = false;
  const head = text(host, "div", "geo-risk-head");
  const title = text(head, "div", "geo-risk-title");
  text(title, "span", "geo-risk-label", "GEOPOLITICAL RISK PRICING");
  text(title, "h3", "geo-risk-name", "地缘风险定价").id = "geo-risk-heading";
  if (!model || !model.available) {
    text(head, "span", "geo-risk-level geo-risk-level-off", "不可用");
    const reasons = model && model.missing && model.missing.length
      ? model.missing.join("；")
      : "四条轴所需的站内数据当前都不可用";
    text(host, "p", "geo-risk-note",
      `暂不给出等级：${reasons}。缺轴期间不用其余轴的平均顶替。`);
    return;
  }
  const level = model.level || GEO_LEVELS[0];
  const badge = text(head, "span", `geo-risk-level geo-risk-level-${level.key}`, level.label);
  badge.setAttribute("data-level", level.key);
  const score = text(head, "strong", "geo-risk-score", String(model.score));
  text(score, "small", "", " / 100");

  const ladder = text(host, "div", "geo-risk-ladder");
  ladder.setAttribute("role", "img");
  ladder.setAttribute("aria-label",
    `地缘风险定价 ${model.score} 分，五档中的第 ${GEO_LEVELS.indexOf(level) + 1} 档：${level.label}`);
  GEO_LEVELS.forEach((entry) => {
    const step = text(ladder, "i", `geo-risk-step geo-risk-step-${entry.key}`
      + (entry.key === level.key ? " is-active" : ""));
    step.setAttribute("data-label", entry.label);
  });

  const axes = text(host, "div", "geo-risk-axes");
  model.axes.forEach((axis) => {
    const row = text(axes, "div", "geo-axis");
    text(row, "span", "geo-axis-name", axis.label);
    const bar = text(row, "span", "geo-axis-bar");
    bar.setAttribute("role", "progressbar");
    bar.setAttribute("aria-valuemin", "0");
    bar.setAttribute("aria-valuemax", "100");
    bar.setAttribute("aria-valuenow", String(axis.score));
    bar.setAttribute("aria-label", `${axis.label} ${axis.score} 分（权重${axis.weight}%）`);
    const level = levelOf(axis.score) || GEO_LEVELS[0];
    text(bar, "i", `geo-axis-fill geo-axis-fill-${level.key}`).style.width = `${axis.score}%`;
    text(row, "b", "geo-axis-score", String(axis.score));
    text(row, "span", "geo-axis-raw", `${axis.rawText} · ${axis.method}`);
    text(row, "span", "geo-axis-meta",
      `${axis.sourceName || "来源不可用"} · 数据日 ${axis.asOf || "不可用"}`
      + ` · 更新 ${formatUpdated(axis.updatedAt)}`
      + (axis.stale ? " · 上游已过期" : ""));
  });
  text(host, "p", "geo-risk-note", MODEL_NOTE);
}
