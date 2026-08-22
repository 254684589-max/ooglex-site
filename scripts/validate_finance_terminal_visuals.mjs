import assert from "node:assert/strict";
import {
  derivePipelineSummary,
  deriveRegionalHeatmap
} from "../apps/finance-terminal/finance-terminal-visuals.mjs";
import { deriveRiskRadar } from "../apps/finance-terminal/finance-terminal-risk-radar.mjs";
import { textureCoordinate } from "../apps/finance-terminal/finance-terminal-globe.mjs";
import { sessionState } from "../apps/finance-terminal/finance-terminal-sessions.mjs";

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

const radar = deriveRiskRadar([{ meterPercent: 62 }, { meterPercent: 44 }, { value: -1.25 }]);
assert.equal(radar.values.length, 6, "风险雷达必须由三项现有信号生成六个可视维度");
assert.ok(radar.values.every((value) => value >= 0 && value <= 100));
assert.ok(radar.score >= 0 && radar.score <= 10);
assert.equal(deriveRiskRadar([{ meterPercent: 50 }]), null,
  "三项信号不完整时风险雷达不得生成推断分数");

assert.equal(textureCoordinate(0, 0), .5, "地球中央经线必须映射到纹理中央");
assert.equal(textureCoordinate(0, 1), .75, "地球右侧边缘必须映射到东经90度");
assert.equal(textureCoordinate(0, -1), .25, "地球左侧边缘必须映射到西经90度");


/* 交易时段：纯日历推导，覆盖盘中、午休、盘前、收盘、周末与未知时区。 */
const at = (iso, zone) => sessionState(zone, new Date(iso));
assert.equal(at("2026-08-19T18:00:00Z", "America/New_York").state, "open",
  "周三纽约14:00应处于常规交易时段");
assert.equal(at("2026-08-20T00:00:00Z", "America/New_York").state, "closed",
  "纽约收盘后不得仍标记为开盘");
assert.equal(at("2026-08-19T12:00:00Z", "America/New_York").state, "pre",
  "纽约盘前应标记为待开盘");
assert.equal(at("2026-08-19T11:00:00Z", "Europe/London").state, "open",
  "周三伦敦12:00应处于常规交易时段");
assert.equal(at("2026-08-19T04:00:00Z", "Asia/Shanghai").state, "lunch",
  "上海12:00应识别为午间休市而非收盘");
assert.equal(at("2026-08-19T03:00:00Z", "Asia/Tokyo").state, "lunch",
  "东京12:00应识别为午间休市而非收盘");
assert.ok(at("2026-08-19T02:30:00Z", "Asia/Shanghai").detail.includes("午休"),
  "上半场剩余时间应指向午休而非收盘");
assert.ok(at("2026-08-19T06:00:00Z", "Asia/Shanghai").detail.includes("收盘"),
  "下半场剩余时间应指向收盘");
assert.equal(at("2026-08-22T18:00:00Z", "America/New_York").state, "weekend",
  "周六必须标记为周末休市");
assert.equal(at("2026-08-19T18:00:00Z", "Mars/Olympus").state, "unknown",
  "无法解析的时区必须返回未知而不是猜测开盘");

console.log("Finance Terminal visual data contracts: PASS");
console.log("- seven-region daily return pressure proxy / error isolation: PASS");
console.log("- dynamic 5/7 to 7/7 minimum-cycle continuity / stale evidence preservation: PASS");
console.log("- three-source normalized six-axis risk radar / incomplete-source isolation: PASS");
console.log("- rotating globe longitude projection / texture wrap contract: PASS");
console.log("- calendar-only trading sessions / lunch break / weekend / unknown zone: PASS");
