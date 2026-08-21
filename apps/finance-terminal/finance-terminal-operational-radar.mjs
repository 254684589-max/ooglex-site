function finiteNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

function validRiskCard(cards, id) {
  const rows = Array.isArray(cards) ? cards : [];
  const card = rows.find((item) => item?.id === id);
  return card && card.status !== "error" ? card : null;
}

function operationalAxis(id, label, value, display, note) {
  return Object.freeze({
    id,
    label,
    value: finiteNumber(value) ? clamp(value, 0, 100) : null,
    display: display || "—",
    note
  });
}

function signedPercent(value) {
  if (!finiteNumber(value)) return "—";
  const sign = value > 0 ? "+" : value < 0 ? "−" : "";
  return `${sign}${Math.abs(value).toFixed(2)}%`;
}

export function deriveOperationalRadar(inputs = {}) {
  const macro = validRiskCard(inputs.riskCards, "macro-regime");
  const sentiment = validRiskCard(inputs.riskCards, "fear-greed");
  const stress = validRiskCard(inputs.riskCards, "ofr-fsi");
  const officialAssets = (Array.isArray(inputs.marketAssets) ? inputs.marketAssets : [])
    .filter((asset) => asset?.demo === false && !asset.externalDisplay);
  const healthWeight = (asset) => asset.status === "ok" ? 1
    : asset.status === "partial" ? 0.6
      : asset.status === "stale" ? 0.35 : 0;
  const marketHealth = officialAssets.length
    ? officialAssets.reduce((sum, asset) => sum + healthWeight(asset), 0) / officialAssets.length * 100
    : null;
  const minimumCycle = Number.isInteger(inputs.pipelineSummary?.minimumCycle)
    ? inputs.pipelineSummary.minimumCycle : null;
  const readiness = minimumCycle === null ? null : minimumCycle / 7 * 100;
  const regionalValues = (Array.isArray(inputs.regionalRegions) ? inputs.regionalRegions : [])
    .map((region) => region?.value)
    .filter(finiteNumber);
  const weakestRegion = regionalValues.length ? Math.min(...regionalValues) : null;
  const regionalPressure = finiteNumber(weakestRegion)
    ? clamp(Math.max(0, -weakestRegion) / 4 * 100, 0, 100) : null;
  const stressRaw = finiteNumber(stress?.value) ? stress.value : null;
  const stressPosition = finiteNumber(stressRaw)
    ? clamp(50 + Math.atan(stressRaw) * 100 / Math.PI, 0, 100) : null;
  const healthyAssets = officialAssets.filter((asset) => asset.status === "ok").length;

  return Object.freeze([
    operationalAxis("macro", "宏观支持", macro?.meterPercent,
      finiteNumber(macro?.value) ? `${macro.value.toFixed(0)} / 100` : "—",
      "沿用宏观状态原始0—100分数"),
    operationalAxis("sentiment", "情绪位置", sentiment?.meterPercent,
      finiteNumber(sentiment?.value) ? `${sentiment.value.toFixed(0)} / 100` : "—",
      "沿用CNN恐慌与贪婪原始0—100分数"),
    operationalAxis("stress", "金融压力", stressPosition,
      finiteNumber(stressRaw) ? stressRaw.toFixed(2) : "—",
      "OFR FSI原值以反正切函数缩放到雷达位置；卡片保留原值"),
    operationalAxis("data-health", "数据健康", marketHealth,
      officialAssets.length ? `${healthyAssets} / ${officialAssets.length}` : "—",
      "站内官方资产按正常、部分、过期和错误状态加权"),
    operationalAxis("readiness", "稳定资格", readiness,
      minimumCycle === null ? "—" : `${minimumCycle} / 7`,
      "四条核心管线最小连续UTC日周期"),
    operationalAxis("regional-pressure", "区域压力", regionalPressure,
      finiteNumber(weakestRegion) ? signedPercent(weakestRegion) : "—",
      "区域代表指数中最弱当日回报；跌幅4%映射为雷达满刻度")
  ]);
}

export function createOperationalRadarRenderer(document) {
  const inputs = {
    marketAssets: [],
    pipelineSummary: null,
    regionalRegions: [],
    riskCards: []
  };

  function render(patch = {}) {
    Object.assign(inputs, patch);
    const shape = document.getElementById("operational-radar-shape");
    const status = document.getElementById("operational-radar-status");
    const coverage = document.getElementById("operational-radar-coverage");
    const svg = document.querySelector(".operational-radar-svg");
    if (!shape || !status || !coverage || !svg) return;
    const axes = deriveOperationalRadar(inputs);
    const points = axes.map((axis, index) => {
      const angle = (-90 + index * 60) * Math.PI / 180;
      const level = finiteNumber(axis.value) ? axis.value / 100 : 0;
      return {
        ...axis,
        x: 140 + Math.cos(angle) * 100 * level,
        y: 130 + Math.sin(angle) * 100 * level
      };
    });
    shape.setAttribute("points", points.map((point) => `${point.x.toFixed(1)},${point.y.toFixed(1)}`).join(" "));
    points.forEach((point) => {
      const marker = svg.querySelector(`[data-radar-point="${point.id}"]`);
      const value = svg.querySelector(`[data-radar-value="${point.id}"]`);
      if (marker) {
        marker.setAttribute("cx", point.x.toFixed(1));
        marker.setAttribute("cy", point.y.toFixed(1));
        marker.style.opacity = finiteNumber(point.value) ? "1" : "0";
      }
      if (value) value.textContent = point.display;
    });
    const available = axes.filter((axis) => finiteNumber(axis.value)).length;
    status.textContent = available === 6 ? "六轴数据已核验" : `${available} / 6 轴可用`;
    coverage.textContent = `${available} / 6 AXES`;
    shape.classList.toggle("is-partial", available !== 6);
    svg.setAttribute("aria-label", `风险雷达：${axes.map((axis) => `${axis.label}${axis.display}`).join("；")}。各轴独立，不合成为投资评分。`);
  }

  return Object.freeze({ render });
}
