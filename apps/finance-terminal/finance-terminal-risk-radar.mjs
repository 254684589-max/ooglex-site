export function deriveRiskRadar(cards) {
  const source = (Array.isArray(cards) ? cards : []).map((card) => Number.isFinite(card?.meterPercent)
    ? Math.min(100, Math.max(0, card.meterPercent))
    : Number.isFinite(card?.value) ? Math.min(100, Math.max(0, 50 + card.value * 8)) : null);
  if (source.filter(Number.isFinite).length !== 3) return null;
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
  const verdict = document.getElementById("risk-radar-verdict");
  const insightTitle = document.getElementById("market-insight-title");
  const insightCopy = document.getElementById("market-insight-copy");
  const values = document.querySelectorAll("#risk-radar-values text");
  if (!polygon || points.length !== 6 || values.length !== 6 || !score || !state) return;
  const radar = deriveRiskRadar(cards);
  if (!radar) {
    polygon.setAttribute("points", Array(6).fill("130,118").join(" "));
    score.textContent = "—";
    values.forEach((value) => { value.textContent = "—"; });
    state.textContent = "UNAVAILABLE";
    state.className = "status-error-text";
    if (verdict) verdict.textContent = "信号不足";
    if (insightTitle) insightTitle.textContent = "风险信号不完整，摘要保持空态";
    if (insightCopy) insightCopy.textContent = "缺少任一来源时不补造判断。";
    return;
  }
  const pts = radar.values.map((value, index) => {
    const angle = -Math.PI / 2 + index * Math.PI / 3;
    const x = 130 + Math.cos(angle) * .96 * value;
    const y = 118 + Math.sin(angle) * .96 * value;
    points[index].setAttribute("cx", x);
    points[index].setAttribute("cy", y);
    values[index].textContent = (value / 10).toFixed(1);
    return `${x},${y}`;
  });
  polygon.setAttribute("points", pts.join(" "));
  const tier = radar.score >= 6.5 ? 2 : radar.score >= 4 ? 1 : 0;
  const reading = radar.score.toFixed(1);
  score.textContent = reading;
  state.textContent = ["LOW RISK", "MODERATE", "HIGH RISK"][tier];
  state.className = tier === 2 ? "status-watch-text" : "status-ok-text";
  if (verdict) verdict.textContent = ["低风险\n继续跟踪", "中等风险\n保持审慎", "高风险\n控制敞口"][tier];
  if (insightTitle) insightTitle.textContent = ["风险相对温和，继续跟踪数据", "风险偏中高，保持分散耐心", "风险偏高，优先关注敞口与流动性"][tier];
  if (insightCopy) insightCopy.textContent = `六维风险均值${reading}/10，不改变原始口径。`;
}
