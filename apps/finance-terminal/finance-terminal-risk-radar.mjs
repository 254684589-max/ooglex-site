function finite(value) { return typeof value === "number" && Number.isFinite(value); }
function clamp(value) { return Math.max(0, Math.min(100, value)); }

export function deriveRiskRadar(cards) {
  const source = (Array.isArray(cards) ? cards : []).map((card) => finite(card?.meterPercent)
    ? clamp(card.meterPercent) : finite(card?.value) ? clamp(50 + card.value * 8) : null);
  if (source.filter(finite).length !== 3) return null;
  const [m, s, y] = source;
  const values = [m, m * .7 + y * .3, m * .55 + s * .45, (100 - s) * .72 + y * .28,
    y * .75 + m * .25, (100 - s) * .55 + m * .45];
  return { values, score: values.reduce((sum, value) => sum + value, 0) / values.length / 10 };
}

export function renderRiskRadar(document, cards) {
  const polygon = document.getElementById("risk-radar-polygon");
  const points = document.querySelectorAll("#risk-radar-points circle");
  const score = document.getElementById("risk-radar-score");
  const state = document.getElementById("risk-radar-state");
  const insightTitle = document.getElementById("market-insight-title");
  const insightCopy = document.getElementById("market-insight-copy");
  const values = document.querySelectorAll("#risk-radar-values text");
  if (!polygon || points.length !== 6 || values.length !== 6 || !score || !state) return;
  const radar = deriveRiskRadar(cards);
  if (!radar) {
    polygon.setAttribute("points", "130,118 130,118 130,118 130,118 130,118 130,118");
    score.textContent = "—";
    values.forEach((value) => { value.textContent = "—"; });
    state.textContent = "UNAVAILABLE";
    state.className = "status-error-text";
    if (insightTitle) insightTitle.textContent = "风险信号不完整，摘要保持空态";
    if (insightCopy) insightCopy.textContent = "缺少任一来源时不补造判断。";
    return;
  }
  const coordinates = radar.values.map((value, index) => {
    const angle = -Math.PI / 2 + index * Math.PI / 3;
    const distance = .96 * value;
    return [130 + Math.cos(angle) * distance, 118 + Math.sin(angle) * distance];
  });
  polygon.setAttribute("points", coordinates.map((point) => point.join(",")).join(" "));
  coordinates.forEach((point, index) => {
    points[index].setAttribute("cx", point[0]);
    points[index].setAttribute("cy", point[1]);
    values[index].textContent = (radar.values[index] / 10).toFixed(1);
  });
  score.textContent = radar.score.toFixed(1);
  state.textContent = radar.score >= 6.5 ? "HIGH RISK" : radar.score >= 4 ? "MODERATE" : "LOW RISK";
  state.className = radar.score >= 6.5 ? "status-watch-text" : "status-ok-text";
  const band = radar.score >= 6.5 ? "风险偏高，优先关注敞口与流动性"
    : radar.score >= 4 ? "风险偏中高，保持分散耐心"
      : "风险相对温和，继续跟踪数据";
  if (insightTitle) insightTitle.textContent = band;
  if (insightCopy) insightCopy.textContent = `三项来源映射的六维风险均值为${radar.score.toFixed(1)}/10；不改变原始口径。`;
}
