/* 首页HUD只镜像页面中已经完成校验的读数，不另算一套指标。 */
export function initAuroraHome({ document, MutationObserver }) {
  function copy(targetId, source, fallback = "读取中") {
    const target = document.getElementById(targetId);
    if (target) target.textContent = source?.textContent.trim() || fallback;
  }

  /* HUD 一行只放得下短标签：优先用来源节点自己声明的短态，其次取「中文 · ENGLISH」的中文段。 */
  function copyShort(targetId, source, fallback = "读取中") {
    const target = document.getElementById(targetId);
    if (!target) return;
    const full = source?.textContent.trim() || "";
    const short = source?.dataset?.shortState || full.split(" · ")[0];
    target.textContent = short || fallback;
  }

  function sync() {
    copy("overview-insight-title", document.getElementById("market-insight-title"));
    copy("overview-insight-copy", document.getElementById("market-insight-copy"));
    copy("hud-risk-value", document.getElementById("risk-radar-score"));
    copyShort("hud-risk-state", document.getElementById("risk-radar-state"));
    const score = document.getElementById("risk-radar-score")?.textContent.trim();
    const riskChip = document.getElementById("overview-risk-chip");
    if (riskChip) riskChip.textContent = score && score !== "—" ? `${score} / 10` : "信号不足";

    const macro = document.querySelector('#risk-grid [data-signal-id="macro-regime"]');
    const macroScore = Number(macro?.querySelector('[role="progressbar"]')?.getAttribute("aria-valuenow"));
    const macroState = macro?.querySelector(".risk-assessment");
    const macroValue = document.getElementById("hud-macro-value");
    if (macroValue) macroValue.textContent = Number.isFinite(macroScore) ? (macroScore / 10).toFixed(1) : "—";
    copyShort("hud-macro-state", macroState, "信号不足");
    copy("overview-macro-chip", macroState, "信号不足");

    const stress = document.querySelector('#risk-grid [data-signal-id="ofr-fsi"]');
    copy("hud-stress-value", stress?.querySelector(".risk-value"), "—");
    copyShort("hud-stress-state", stress?.querySelector(".risk-assessment"), "信号不足");

    const cards = Array.from(document.querySelectorAll("#market-grid .asset-card"));
    if (!cards.length) {
      copy("hud-data-value", null, "— / 6");
      copy("hud-data-state", null, "校验中");
      copy("overview-coverage-chip", null, "校验中");
      return;
    }
    const available = cards.filter((card) => !card.classList.contains("status-error")
      && !card.querySelector('[data-provider-state="unavailable"]')).length;
    const total = cards.length || 6;
    const coverage = `${available} / ${total}`;
    const coverageValue = document.getElementById("hud-data-value");
    if (coverageValue) coverageValue.textContent = coverage;
    const dataState = document.getElementById("hud-data-state");
    if (dataState) dataState.textContent = available === total ? "无不可用项" : `${total - available}项不可用`;
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
