function requireDependency(dependencies, name) {
  const value = dependencies && dependencies[name];
  if (value === undefined || value === null) {
    throw new Error(`稳定V1运行证据视图缺少依赖：${name}`);
  }
  return value;
}

export function createOperationsView(dependencies = {}) {
  const document = requireDependency(dependencies, "document");
  const grid = requireDependency(dependencies, "grid");
  const summary = requireDependency(dependencies, "summary");
  const appendText = requireDependency(dependencies, "appendText");
  const formatHealthCoverage = requireDependency(dependencies, "formatHealthCoverage");
  const formatTimestamp = requireDependency(dependencies, "formatTimestamp");
  const isSafeHref = requireDependency(dependencies, "isSafeHref");

  function operationStatusLabel(card) {
    if (card.status === "healthy") return { className: "official-chip", text: "HEALTHY" };
    if (card.status === "degraded") return { className: "partial-chip", text: "DEGRADED" };
    if (card.status === "stale") return { className: "stale-chip", text: "STALE" };
    if (card.status === "failed") return { className: "error-chip", text: "FAILED" };
    return { className: "error-chip", text: "UNKNOWN" };
  }

  function operationCountLabel(card) {
    const published = Number.isInteger(card.publishedRecords) ? card.publishedRecords : "—";
    return `${published} / ${card.expectedRecords}`;
  }

  function operationFailureLabel(card) {
    return card.historyKnown && Number.isInteger(card.consecutiveFailures)
      ? `${card.consecutiveFailures}次` : "历史待建立";
  }

  function operationSnapshotLabel(card) {
    if (!card.historyKnown) return "历史待建立";
    if (card.snapshotPreserved === true) return "已保留旧快照";
    if (card.snapshotPreserved === false) return "本轮未触发";
    return "状态不可用";
  }

  function makeOperationCard(card) {
    const article = document.createElement("article");
    article.className = `operation-card status-${card.status}`;
    article.setAttribute("role", "listitem");

    const head = document.createElement("div");
    head.className = "operation-card-head";
    const titleBox = document.createElement("div");
    appendText(titleBox, "h3", "operation-name", card.name);
    appendText(titleBox, "span", "operation-en", card.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "operation-symbol", card.symbol);
    article.appendChild(head);

    const kpi = document.createElement("div");
    kpi.className = "operation-kpi";
    appendText(kpi, "strong", "operation-kpi-value", operationCountLabel(card));
    appendText(kpi, "span", "operation-kpi-label", `可展示${card.unit}`);
    article.appendChild(kpi);

    const metrics = document.createElement("div");
    metrics.className = "operation-metrics";
    const coverageMetrics = [
      ["可用覆盖", formatHealthCoverage(card.availableCoveragePct)],
      ["本轮新鲜", formatHealthCoverage(card.freshCoveragePct)],
      [card.slowRecords ? "慢频估值" : "已验证覆盖", card.slowRecords
        ? `${card.slowEstimateRecords} / ${card.slowRecords}`
        : formatHealthCoverage(card.verifiedCoveragePct)],
      ["连续失败", operationFailureLabel(card)]
    ];
    coverageMetrics.forEach((item) => {
      const metric = document.createElement("span");
      metric.className = "operation-metric";
      appendText(metric, "span", "operation-metric-label", item[0]);
      appendText(metric, "strong", "operation-metric-value", item[1]);
      metrics.appendChild(metric);
    });
    article.appendChild(metrics);

    const times = document.createElement("div");
    times.className = "operation-times";
    [
      ["最近尝试", formatTimestamp(card.lastAttemptAt, false)],
      ["最后成功", formatTimestamp(card.lastSuccessfulAt, false)],
      ["失败回退", operationSnapshotLabel(card)]
    ].forEach((item) => {
      const row = document.createElement("span");
      appendText(row, "span", "", item[0]);
      appendText(row, "strong", "", item[1]);
      times.appendChild(row);
    });
    article.appendChild(times);

    if (card.readiness) {
      const evidence = document.createElement("div");
      evidence.className = `operation-readiness evidence-${card.readiness.status}`;
      const evidenceHead = document.createElement("div");
      evidenceHead.className = "operation-readiness-head";
      appendText(evidenceHead, "span", "operation-readiness-label", "STABLE V1 EVIDENCE");
      appendText(evidenceHead, "strong", "operation-readiness-state", card.readiness.label);
      evidence.appendChild(evidenceHead);
      const evidenceValue = Number.isInteger(card.readiness.consecutiveSuccessfulCycles)
        ? `${card.readiness.consecutiveSuccessfulCycles} / 7 DAYS` : "— / 7 DAYS";
      appendText(evidence, "strong", "operation-readiness-value", evidenceValue);
      const progress = document.createElement("div");
      progress.className = "operation-readiness-progress";
      progress.setAttribute("role", "progressbar");
      progress.setAttribute("aria-label", `${card.name}稳定V1连续成功周期`);
      progress.setAttribute("aria-valuemin", "0");
      progress.setAttribute("aria-valuemax", "7");
      progress.setAttribute("aria-valuenow", Number.isInteger(card.readiness.consecutiveSuccessfulCycles)
        ? String(Math.min(7, card.readiness.consecutiveSuccessfulCycles)) : "0");
      const progressFill = document.createElement("span");
      progressFill.style.width = Number.isInteger(card.readiness.consecutiveSuccessfulCycles)
        ? `${Math.min(100, card.readiness.consecutiveSuccessfulCycles / 7 * 100)}%` : "0%";
      progress.appendChild(progressFill);
      evidence.appendChild(progress);
      appendText(evidence, "p", "operation-readiness-note", card.readiness.note);
      if (card.readiness.latestCycleDate) {
        appendText(evidence, "span", "operation-readiness-date", `最近周期 ${card.readiness.latestCycleDate}`);
      }
      if (card.readiness.latestRunUrl) {
        const runLink = appendText(evidence, "a", "operation-readiness-link", "查看本轮运行 ↗");
        runLink.href = card.readiness.latestRunUrl;
        runLink.target = "_blank";
        runLink.rel = "noopener noreferrer";
      }
      article.appendChild(evidence);
    }
    appendText(article, "p", "operation-note", card.note || "运行状态说明不可用。");

    const footer = document.createElement("div");
    footer.className = "operation-footer";
    const chip = operationStatusLabel(card);
    appendText(footer, "span", `status-chip ${chip.className}`, chip.text);
    if (isSafeHref(card.detailUrl)) {
      const detail = appendText(footer, "a", "detail-link", "查看数据页面 →");
      detail.href = card.detailUrl;
    }
    article.appendChild(footer);
    return article;
  }

  function render(cards) {
    grid.textContent = "";
    cards.forEach((card) => { grid.appendChild(makeOperationCard(card)); });
    grid.setAttribute("aria-busy", "false");
    const healthy = cards.filter((card) => card.status === "healthy").length;
    const degraded = cards.filter((card) => card.status === "degraded").length;
    const stale = cards.filter((card) => card.status === "stale").length;
    const failed = cards.filter((card) => card.status === "failed").length;
    const unknown = cards.filter((card) => card.status === "unknown").length;
    const evidenceCards = cards.filter((card) => card.readiness);
    const evidenceSummary = evidenceCards.length ? ` · V1 ${Math.min(...evidenceCards.map((card) => {
      return Number.isInteger(card.readiness.consecutiveSuccessfulCycles)
        ? card.readiness.consecutiveSuccessfulCycles : 0;
    }))}/7` : "";
    summary.textContent = `${healthy} HEALTHY · ${degraded} DEGRADED · ${stale} STALE · `
      + `${failed} FAILED · ${unknown} UNKNOWN${evidenceSummary}`;
  }

  return Object.freeze({ render });
}
