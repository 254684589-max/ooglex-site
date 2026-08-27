import { buildGeoRisk, renderGeoRisk } from "./finance-terminal-geo-risk.mjs";

function requireDependency(dependencies, name) {
  const value = dependencies && dependencies[name];
  if (value === undefined || value === null) {
    throw new Error(`市场状态视图缺少依赖：${name}`);
  }
  return value;
}

export function createRiskView(dependencies = {}) {
  const document = requireDependency(dependencies, "document");
  const grid = requireDependency(dependencies, "grid");
  const summary = requireDependency(dependencies, "summary");
  const isNumber = requireDependency(dependencies, "isNumber");
  const appendText = requireDependency(dependencies, "appendText");
  const appendSupportingHealth = requireDependency(dependencies, "appendSupportingHealth");
  const formatDate = requireDependency(dependencies, "formatDate");
  const appendSource = requireDependency(dependencies, "appendSource");
  const formatTimestamp = requireDependency(dependencies, "formatTimestamp");
  const isSafeHref = requireDependency(dependencies, "isSafeHref");

  /* 只返回读数本身；量纲后缀（如 / 100）单独成行，避免在圆环内被截断。 */
  function formatRiskValue(card) {
    if (!isNumber(card.value)) return "—";
    const decimals = Number.isInteger(card.decimals) ? card.decimals : 2;
    return (card.prefix || "") + card.value.toLocaleString("en-US", {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals
    });
  }

  function riskStatusLabel(card) {
    if (card.status === "stale") return { className: "stale-chip", text: "STALE" };
    if (card.status === "error") return { className: "error-chip", text: "ERROR" };
    if (card.status === "partial") return { className: "partial-chip", text: "PARTIAL" };
    return { className: "official-chip", text: "ACTIVE" };
  }

  function makeRiskCard(signal) {
    const card = document.createElement("article");
    card.className = "risk-card status-" + signal.status;
    card.setAttribute("role", "listitem");
    card.setAttribute("data-signal-id", signal.id);

    const head = document.createElement("div");
    head.className = "risk-card-head";
    const titleBox = document.createElement("div");
    appendText(titleBox, "h3", "risk-name", signal.name);
    appendText(titleBox, "span", "risk-en", signal.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "risk-symbol", signal.symbol);
    card.appendChild(head);

    const gauge = document.createElement("div");
    gauge.className = "risk-hud-gauge" + (isNumber(signal.meterPercent) ? " risk-hud-percent" : " risk-hud-raw");
    if (isNumber(signal.meterPercent)) {
      const percent = Math.max(0, Math.min(100, signal.meterPercent));
      gauge.style.setProperty("--risk-hud-progress", `${percent * 3.6}deg`);
      gauge.setAttribute("role", "progressbar");
      gauge.setAttribute("aria-valuemin", "0");
      gauge.setAttribute("aria-valuemax", "100");
      gauge.setAttribute("aria-valuenow", String(percent));
      gauge.setAttribute("aria-label", signal.name + "分数");
    } else {
      gauge.setAttribute("aria-label", signal.name + "原始指数读数，未归一化");
    }
    const valueRow = document.createElement("div");
    valueRow.className = "risk-value-row";
    appendText(valueRow, "span", "risk-value", formatRiskValue(signal));
    if (signal.suffix) appendText(valueRow, "span", "risk-value-suffix", signal.suffix.trim());
    /* 短态供首屏HUD用，卡面仍是完整判语。 */
    const verdict = appendText(valueRow, "span", "risk-assessment", signal.assessment);
    if (signal.shortAssessment) verdict.dataset.shortState = signal.shortAssessment;
    gauge.appendChild(valueRow);
    appendText(gauge, "span", "risk-hud-scale", isNumber(signal.meterPercent) ? "0 — 100" : "RAW INDEX");
    card.appendChild(gauge);
    appendText(card, "div", "risk-change", signal.changeText || "暂无可比变化");

    if (isNumber(signal.meterPercent) && Array.isArray(signal.meterLabels)
      && signal.meterLabels.length === 3) {
      const meter = document.createElement("div");
      meter.className = "signal-meter signal-meter-labels-only";
      const labels = document.createElement("div");
      labels.className = "meter-labels";
      signal.meterLabels.forEach((label) => { appendText(labels, "span", "", label); });
      meter.appendChild(labels);
      card.appendChild(meter);
    }

    appendText(card, "p", "risk-note", signal.note);
    if (signal.sourceHealth) appendSupportingHealth(card, signal.sourceHealth);
    const meta = document.createElement("div");
    meta.className = "risk-meta";
    appendText(meta, "span", "", "数据日 · " + formatDate(signal.asOf, false));
    appendText(meta, "span", "", signal.frequency || "频率未提供");
    card.appendChild(meta);

    const footer = document.createElement("div");
    footer.className = "risk-footer";
    const sourceBox = document.createElement("div");
    sourceBox.className = "risk-source";
    appendSource(sourceBox, signal);
    footer.appendChild(sourceBox);
    const time = appendText(footer, "time", "", "更新 · " + formatTimestamp(signal.updatedAt, false));
    if (signal.updatedAt) time.dateTime = signal.updatedAt;
    const chip = riskStatusLabel(signal);
    appendText(footer, "span", "status-chip " + chip.className, chip.text);
    if (isSafeHref(signal.detailUrl)) {
      const detail = appendText(footer, "a", "detail-link", "查看完整页面 →");
      detail.href = signal.detailUrl;
    }
    card.appendChild(footer);
    return card;
  }

  function render(cards) {
    grid.textContent = "";
    cards.forEach((card) => { grid.appendChild(makeRiskCard(card)); });
    grid.setAttribute("aria-busy", "false");
    const ok = cards.filter((card) => card.status === "ok").length;
    const partial = cards.filter((card) => card.status === "partial").length;
    const stale = cards.filter((card) => card.status === "stale").length;
    const errors = cards.filter((card) => card.status === "error").length;
    summary.textContent = `${ok} ACTIVE · ${partial} PARTIAL · ${stale} STALE · ${errors} ERROR`;
  }

  /* 地缘风险定价由本视图一并渲染，但它是站内复算出来的模型，单独成区：
     不混进那三张官方信号卡的列表，也不参与它们的 ACTIVE/STALE 计数。 */
  function renderGeo(sources) {
    const host = document.getElementById("geo-risk");
    if (!host) return;
    renderGeoRisk(document, host, buildGeoRisk(sources || {}));
  }

  return Object.freeze({ render, renderGeo });
}
