import assert from "node:assert/strict";
import { deriveOperationalRadar } from "../apps/finance-terminal/finance-terminal-operational-radar.mjs";
import {
  derivePipelineSummary,
  deriveRegionalHeatmap
} from "../apps/finance-terminal/finance-terminal-visuals.mjs";

function asset(symbol, dailyReturn, options = {}) {
  return {
    symbol,
    returns: { d1: dailyReturn },
    stale: options.stale === true,
    suspect: options.suspect === true,
    proxy: options.proxy === true ? { type: "etf" } : null
  };
}

const regionalCard = {
  id: "cross-asset",
  status: "ok",
  assets: [
    asset("^GSPC", -1.2),
    asset("^BVSP", 0.4),
    asset("^STOXX", -0.4),
    asset("^FTSE", 0.2),
    asset("^GDAXI", 0.4),
    asset("^FCHI", -0.2),
    asset("510300.SS", -0.8, { proxy: true }),
    asset("^HSI", 0.2),
    asset("^N225", -0.3),
    asset("^BSESN", 0),
    asset("^AXJO", 0.5),
    asset("^NZ50", 0.3)
  ]
};

const regions = deriveRegionalHeatmap(regionalCard);
assert.equal(regions.length, 7, "热力图必须生成七组有真实代表指数的区域");
assert.equal(regions.find((region) => region.id === "north-america")?.value, -1.2);
assert.equal(regions.find((region) => region.id === "europe")?.value, 0);
assert.ok(Math.abs(regions.find((region) => region.id === "greater-china")?.value + 0.3) < 1e-12);
assert.equal(regions.find((region) => region.id === "greater-china")?.assets[0].proxy?.type, "etf");
assert.deepEqual(deriveRegionalHeatmap({ status: "error", assets: [] }), [],
  "区域数据错误时不得生成推断值");

const pipelineCards = [
  ["macro-radar", "healthy", 5],
  ["asset-tracker", "healthy", 6],
  ["companies", "degraded", 5],
  ["asset-ranking", "stale", 7]
].map(([id, status, cycles]) => ({
  id,
  status,
  readiness: { consecutiveSuccessfulCycles: cycles, reportStale: false }
}));

const progress = derivePipelineSummary(pipelineCards);
assert.deepEqual(progress, {
  minimumCycle: 5,
  evidenceStale: false,
  healthy: 2,
  degraded: 2,
  failed: 0
}, "稳定V1 HUD必须使用四管线最小连续周期且独立汇总健康状态");

const ready = derivePipelineSummary(pipelineCards.map((card) => ({
  ...card,
  status: "healthy",
  readiness: { consecutiveSuccessfulCycles: 7, reportStale: false }
})));
assert.equal(ready.minimumCycle, 7, "四管线全部7/7时必须可复算为完整资格");
assert.equal(ready.healthy, 4);

const staleEvidence = derivePipelineSummary(pipelineCards.map((card) => ({
  ...card,
  readiness: { ...card.readiness, reportStale: card.id === "macro-radar" }
})));
assert.equal(staleEvidence.minimumCycle, 5, "证据过期不得清空已有周期");
assert.equal(staleEvidence.evidenceStale, true, "任一资格证据过期必须向HUD传播");

assert.equal(derivePipelineSummary(pipelineCards.slice(0, 3)).minimumCycle, null,
  "缺少任一核心管线时不得显示伪造的总资格进度");

const radar = deriveOperationalRadar({
  riskCards: [
    { id: "macro-regime", status: "ok", value: 54, meterPercent: 54 },
    { id: "fear-greed", status: "ok", value: 52, meterPercent: 52 },
    { id: "ofr-fsi", status: "ok", value: -2.66, meterPercent: null }
  ],
  marketAssets: [
    { demo: false, externalDisplay: false, status: "ok" },
    { demo: false, externalDisplay: false, status: "ok" },
    { demo: false, externalDisplay: false, status: "partial" },
    { demo: false, externalDisplay: false, status: "stale" },
    { demo: false, externalDisplay: true, status: "ok" }
  ],
  pipelineSummary: progress,
  regionalRegions: regions
});
assert.equal(radar.length, 6, "风险雷达必须保持六个独立且可解释的数据轴");
assert.equal(radar.find((axis) => axis.id === "macro")?.value, 54,
  "宏观支持轴必须沿用原始0—100分数");
assert.equal(radar.find((axis) => axis.id === "sentiment")?.value, 52,
  "情绪位置轴必须沿用原始0—100分数");
assert.equal(radar.find((axis) => axis.id === "stress")?.display, "-2.66",
  "金融压力轴必须继续显示OFR原值而不是伪造总分");
assert.equal(radar.find((axis) => axis.id === "data-health")?.display, "2 / 4",
  "数据健康轴必须排除第三方组件并披露站内健康覆盖");
assert.equal(radar.find((axis) => axis.id === "readiness")?.display, "5 / 7",
  "稳定资格轴必须保留四管线最小周期");
assert.equal(radar.find((axis) => axis.id === "regional-pressure")?.display, "−1.20%",
  "区域压力轴必须显示真实最弱区域回报");

const unavailableRadar = deriveOperationalRadar({});
assert.ok(unavailableRadar.every((axis) => axis.value === null && axis.display === "—"),
  "缺少真实输入时风险雷达不得补造示意值");

console.log("Finance Terminal visual data contracts: PASS");
console.log("- seven-region daily return pressure proxy / error isolation: PASS");
console.log("- dynamic 5/7 to 7/7 minimum-cycle continuity / stale evidence preservation: PASS");
console.log("- six-axis operational radar / raw-value disclosure / no-demo fallback: PASS");
