/* 首页HUD只镜像页面中已经完成校验的读数，不另算一套指标。 */
export function initAuroraHome({ document, MutationObserver }) {
  function copy(targetId, source, fallback = "读取中") {
    const target = document.getElementById(targetId);
    if (target) target.textContent = source?.textContent.trim() || fallback;
  }

  function sync() {
    copy("overview-insight-title", document.getElementById("market-insight-title"));
    copy("overview-insight-copy", document.getElementById("market-insight-copy"));
    copy("hud-risk-value", document.getElementById("risk-radar-score"));
    const riskState = document.getElementById("risk-radar-state")?.textContent.trim();
    const riskStateLabel = {
      "LOW RISK": "偏低",
      MODERATE: "中等",
      "HIGH RISK": "偏高",
      UNAVAILABLE: "不可用"
    }[riskState];
    const hudRiskState = document.getElementById("hud-risk-state");
    if (hudRiskState) hudRiskState.textContent = riskStateLabel || "读取中";
    const score = document.getElementById("risk-radar-score")?.textContent.trim();
    const riskChip = document.getElementById("overview-risk-chip");
    if (riskChip) riskChip.textContent = score && score !== "—" ? `${score} / 10` : "信号不足";

    const macro = document.querySelector('#risk-grid [data-signal-id="macro-regime"]');
    const macroScore = Number(macro?.querySelector('[role="progressbar"]')?.getAttribute("aria-valuenow"));
    const macroState = macro?.querySelector(".risk-assessment");
    const macroValue = document.getElementById("hud-macro-value");
    if (macroValue) macroValue.textContent = Number.isFinite(macroScore) ? (macroScore / 10).toFixed(1) : "—";
    const macroLabel = macroState?.textContent.trim().split("·")[0].trim();
    const hudMacroState = document.getElementById("hud-macro-state");
    if (hudMacroState) hudMacroState.textContent = macroLabel || "信号不足";
    copy("overview-macro-chip", macroState, "信号不足");

    const stress = document.querySelector('#risk-grid [data-signal-id="ofr-fsi"]');
    const stressValueNode = stress?.querySelector(".risk-value");
    copy("hud-stress-value", stressValueNode, "—");
    const stressValue = Number.parseFloat(stressValueNode?.textContent);
    const hudStressState = document.getElementById("hud-stress-state");
    if (hudStressState) hudStressState.textContent = Number.isFinite(stressValue)
      ? (stressValue < -.1 ? "偏低" : stressValue > .1 ? "偏高" : "中性")
      : "信号不足";

    const cards = Array.from(document.querySelectorAll("#market-grid .asset-card"));
    if (!cards.length) {
      copy("hud-data-value", null, "—%");
      copy("hud-data-state", null, "校验中");
      copy("overview-coverage-chip", null, "校验中");
      return;
    }
    const available = cards.filter((card) => !card.classList.contains("status-error")
      && !card.querySelector('[data-provider-state="unavailable"]')).length;
    const total = cards.length || 6;
    const coverage = `${available} / ${total}`;
    const coveragePercent = `${Math.round(available / total * 100)}%`;
    const coverageValue = document.getElementById("hud-data-value");
    if (coverageValue) coverageValue.textContent = coveragePercent;
    const dataState = document.getElementById("hud-data-state");
    if (dataState) dataState.textContent = available === total ? "良好" : `${total - available}项需关注`;
    const coverageChip = document.getElementById("overview-coverage-chip");
    if (coverageChip) coverageChip.textContent = `${coverage} 可用`;
  }

  const observer = new MutationObserver(sync);
  ["market-grid", "risk-grid", "risk-radar-score", "risk-radar-state", "market-insight-title", "market-insight-copy"]
    .map((id) => document.getElementById(id)).filter(Boolean)
    .forEach((node) => observer.observe(node, {
      childList: true, subtree: true, characterData: true, attributes: true
    }));
  sync();
  return () => observer.disconnect();
}
