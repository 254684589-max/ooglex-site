const CRITICAL_REQUEST_KEYS = Object.freeze([
  "$config", "macro", "macroHealth", "assetRanking", "assetRankingHealth", "marketLicense"
]);
const DEFERRED_SECTION_NAMES = Object.freeze(["risk", "research", "information", "operations"]);
const EXPECTED_GROUP_SEQUENCE = Object.freeze(["critical", ...DEFERRED_SECTION_NAMES]);

function sameSequence(actual, expected) {
  return Array.isArray(actual) && actual.length === expected.length
    && actual.every((value, index) => value === expected[index]);
}

function hasCompleteSectionTransitions(transitions) {
  if (!Array.isArray(transitions) || transitions.length !== DEFERRED_SECTION_NAMES.length * 2) return false;
  return DEFERRED_SECTION_NAMES.every((name) => {
    const loadingIndex = transitions.findIndex((item) => item.name === name && item.state === "loading");
    const readyIndex = transitions.findIndex((item) => item.name === name && item.state === "ready");
    return loadingIndex !== -1 && readyIndex > loadingIndex
      && !transitions.some((item) => item.name === name && item.state === "error");
  });
}

function elementIsRendered(element) {
  if (!element) return false;
  const style = window.getComputedStyle(element);
  const rect = element.getBoundingClientRect();
  return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
}

function renderedGridColumns(element) {
  if (!element) return 0;
  return window.getComputedStyle(element).gridTemplateColumns.split(/\s+/).filter(Boolean).length;
}

export function runBrowserRegressionProbe(options = {}) {
  const params = new URLSearchParams(window.location.search);
  if (params.get("regression") !== "1") return null;
  const providerWidgetUnavailableCopy = options.providerWidgetUnavailableCopy;
  if (typeof providerWidgetUnavailableCopy !== "function") {
    throw new Error("浏览器回归缺少免费组件回退解释器");
  }
  const grid = document.getElementById("market-grid");
  const riskGrid = document.getElementById("risk-grid");
  const researchGrid = document.getElementById("research-grid");
  const informationGrid = document.getElementById("information-grid");
  const operationsGrid = document.getElementById("operations-grid");
  const licenseNotice = document.getElementById("license-notice");
  const pageAnnouncer = document.getElementById("page-announcer");
  const width = window.innerWidth;
  const expectedColumns = width <= 620
    ? { market: 1, risk: 1, research: 1, information: 1, operations: 1 }
    : width <= 1040
      ? { market: 2, risk: 2, research: 2, information: 1, operations: 2 }
      : { market: 4, risk: 3, research: 3, information: 1, operations: 4 };
  const cards = Array.from(document.querySelectorAll(
    ".asset-card, .risk-card, .research-card, .information-card, .operation-card"
  ));
  const focusables = Array.from(document.querySelectorAll(
    'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])'
  )).filter(elementIsRendered);
  const targetMinimum = width <= 620 ? 44 : 24;
  const targetElements = Array.from(document.querySelectorAll(
    ".brand, .back-link, .terminal-rail a, .stable-v1-chip, .section-nav a, .method summary, .period-tab, .source-link, .detail-link, .news-link, .operation-action, .operation-readiness-link, .legal-links a"
  )).filter(elementIsRendered);
  const sectionLinks = Array.from(document.querySelectorAll(".section-nav a"));
  const supportingHealthPanels = Array.from(document.querySelectorAll(
    "#risk-grid .pipeline-health, #information-grid .pipeline-health"
  ));
  const officialHealthPanels = Array.from(document.querySelectorAll("#market-grid .official-update-health"));
  const officialTrendPanels = Array.from(document.querySelectorAll("#market-grid .official-trend"));
  const providerWidgets = Array.from(document.querySelectorAll("#market-grid tv-mini-chart"));
  const providerWidgetShells = Array.from(document.querySelectorAll("#market-grid .provider-widget-shell"));
  const readinessEvidencePanels = Array.from(document.querySelectorAll("#operations-grid .operation-readiness"));
  const marketTapeItems = Array.from(document.querySelectorAll("#market-tape .market-tape-item"));
  const marketClocks = Array.from(document.querySelectorAll("[data-market-time]"));
  const riskHudGauges = Array.from(document.querySelectorAll("#risk-grid .risk-hud-gauge"));
  const globalRiskMap = document.getElementById("global-risk-map");
  const riskRegionRows = Array.from(document.querySelectorAll("#risk-region-list .risk-region-row"));
  const pipelineCommand = document.getElementById("pipeline-command");
  const stableV1Ring = document.getElementById("stable-v1-ring");
  const stableV1Chip = document.getElementById("stable-v1-chip");
  const readinessCycleValues = readinessEvidencePanels.map((panel) => {
    const progress = panel.querySelector('[role="progressbar"]');
    return progress ? Number(progress.getAttribute("aria-valuenow")) : null;
  });
  const minimumReadinessCycle = readinessCycleValues.length === 4
    && readinessCycleValues.every((value) => Number.isInteger(value) && value >= 0 && value <= 7)
    ? Math.min(...readinessCycleValues) : null;
  const poweredByCoinGeckoLinks = Array.from(document.querySelectorAll(".asset-source a.source-link"))
    .filter((link) => link.textContent.trim() === "Powered by CoinGecko");
  const coinGeckoAttributions = Array.from(document.querySelectorAll(".coingecko-attribution"));
  const stagedLoad = window.__financeTerminalLoadState || {};
  const requestStates = stagedLoad.requestStates && typeof stagedLoad.requestStates === "object"
    ? Object.values(stagedLoad.requestStates) : [];
  const undersizedTargets = targetElements.map((element) => {
    const rect = element.getBoundingClientRect();
    return {
      selector: element.className,
      text: element.textContent.trim().slice(0, 60),
      width: Math.round(rect.width * 10) / 10,
      height: Math.round(rect.height * 10) / 10
    };
  }).filter((target) => {
    return target.width + 0.5 < targetMinimum || target.height + 0.5 < targetMinimum;
  });
  const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
  const selectedBefore = tabs.filter((tab) => tab.getAttribute("aria-selected") === "true");
  const tabsRendered = tabs.some(elementIsRendered);
  let keyboardTabs = !tabsRendered || selectedBefore.length === 1;
  if (keyboardTabs && tabsRendered) {
    const previousId = selectedBefore[0].id;
    selectedBefore[0].focus();
    selectedBefore[0].dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }));
    const moved = document.activeElement;
    keyboardTabs = moved && moved.getAttribute("role") === "tab"
      && moved.id !== previousId && moved.getAttribute("aria-selected") === "true";
    if (keyboardTabs) {
      moved.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true }));
      keyboardTabs = document.activeElement && document.activeElement.id === previousId;
    }
  }

  const checks = {
    dataLoaded: [grid, riskGrid, researchGrid, informationGrid, operationsGrid].every((item) => {
      return item && item.getAttribute("aria-busy") === "false";
    }) && !document.querySelector(".load-error"),
    stagedDataLoading: stagedLoad.mode === "eager"
      && stagedLoad.criticalSourceRequestCount === 5
      && stagedLoad.sourceRequestCount === 18
      && stagedLoad.requestCount === 19
      && stagedLoad.criticalPaintBarrier?.status === "yielded"
      && sameSequence(stagedLoad.startupOrder,
        ["critical-rendered", "critical-paint-yielded", "deferred-scheduler-started"])
      && sameSequence(stagedLoad.requestedKeysAfterCritical, CRITICAL_REQUEST_KEYS)
      && sameSequence(stagedLoad.requestedKeysAtSchedulerStart, CRITICAL_REQUEST_KEYS)
      && sameSequence(stagedLoad.groupLoadSequence, EXPECTED_GROUP_SEQUENCE)
      && Array.isArray(stagedLoad.loadedSections) && stagedLoad.loadedSections.length === 4
      && Array.isArray(stagedLoad.failedSections) && stagedLoad.failedSections.length === 0
      && Array.isArray(stagedLoad.settledSections) && stagedLoad.settledSections.length === 4
      && stagedLoad.networkRequestCount === 19
      && stagedLoad.duplicateNetworkRequestCount === 0
      && requestStates.length === 19 && requestStates.every((state) => state === "ready")
      && hasCompleteSectionTransitions(stagedLoad.sectionTransitions),
    supportingHealthResources: supportingHealthPanels.length === 4
      && supportingHealthPanels.every((panel) => panel.textContent.indexOf("更新链健康不可用") === -1),
    officialHealthResources: officialHealthPanels.length === 4
      && officialHealthPanels.every((panel) => panel.textContent.indexOf("逐源更新链健康不可用") === -1),
    officialObservationTrends: officialTrendPanels.length === 3
      && officialTrendPanels.every((panel) => {
        const count = panel.querySelector(".official-trend-count");
        const match = count && count.textContent.match(/^(\d+)\s*\/\s*8$/);
        const observationCount = match ? Number(match[1]) : null;
        return panel.textContent.indexOf("RECENT OBSERVATIONS") !== -1
          && observationCount !== null && observationCount >= 1 && observationCount <= 8
          && Boolean(panel.querySelector(".sparkline")) === (observationCount >= 2);
      }),
    marketLicenseReadiness: licenseNotice && !licenseNotice.classList.contains("status-unknown")
      && licenseNotice.textContent.indexOf("免费ETF代理") !== -1
      && licenseNotice.textContent.indexOf("API密钥") !== -1,
    providerWidgetContracts: providerWidgets.length === 4
      && providerWidgets.every((widget) => {
        return /^(AMEX:(SPY|DIA|GLD)|NASDAQ:QQQ)$/.test(widget.getAttribute("symbol") || "")
          && widget.getAttribute("theme") === "dark";
      }) && document.querySelectorAll(".provider-widget-fallback").length === 4,
    providerAttribution: poweredByCoinGeckoLinks.length === coinGeckoAttributions.length
      && coinGeckoAttributions.every((link) => {
        return link.textContent.trim() === "Powered by CoinGecko"
          && Number.parseFloat(window.getComputedStyle(link).fontSize) >= 10;
      }),
    providerWidgetRuntime: providerWidgetShells.length === 4
      && providerWidgetShells.every((shell) => {
        const state = shell.getAttribute("data-provider-state");
        const reason = shell.getAttribute("data-provider-reason");
        const fallback = shell.querySelector(".provider-widget-fallback");
        const widget = shell.querySelector("tv-mini-chart");
        const status = shell.closest(".asset-card").querySelector(".provider-runtime-status");
        return (state === "mounted" || state === "unavailable") && reason && status
          && status.textContent === (state === "mounted"
            ? "组件宿主已挂载 · 报价状态见组件"
            : providerWidgetUnavailableCopy(reason).status)
          && (state === "mounted" ? !elementIsRendered(fallback) : elementIsRendered(fallback))
          && (state === "mounted" ? elementIsRendered(widget) : !elementIsRendered(widget));
      }),
    readinessEvidenceResources: readinessEvidencePanels.length === 4
      && readinessEvidencePanels.every((panel) => {
        const progress = panel.querySelector('[role="progressbar"]');
        const value = progress ? Number(progress.getAttribute("aria-valuenow")) : null;
        return panel.textContent.indexOf("STABLE V1 EVIDENCE") !== -1
          && panel.textContent.indexOf("UNKNOWN") === -1
          && Number.isInteger(value) && value >= 0 && value <= 7;
      }),
    orbitalTerminalVisuals: marketTapeItems.length === 8
      && marketTapeItems.every((item) => item.textContent.trim().length > 4)
      && marketTapeItems.filter((item) => item.textContent.includes("组件报价")).length === 4
      && marketClocks.length === 4
      && marketClocks.every((clock) => /^\d{2}:\d{2}$/.test(clock.textContent.trim()))
      && Boolean(document.querySelector(".market-orbit-svg .globe-sphere")),
    riskHudVisuals: riskHudGauges.length === 3
      && riskHudGauges.filter((gauge) => gauge.getAttribute("role") === "progressbar").length === 2
      && riskHudGauges.filter((gauge) => gauge.classList.contains("risk-hud-raw")).length === 1,
    globalRiskHeatmap: globalRiskMap && globalRiskMap.getAttribute("aria-busy") === "false"
      && !globalRiskMap.classList.contains("status-loading")
      && riskRegionRows.length === 7
      && riskRegionRows.every((row) => row.querySelector("strong")?.textContent.trim() !== "—")
      && globalRiskMap.textContent.includes("压力代理")
      && globalRiskMap.textContent.includes("Yahoo Finance"),
    stableV1Hud: pipelineCommand && pipelineCommand.getAttribute("aria-busy") === "false"
      && stableV1Ring && Number(stableV1Ring.getAttribute("aria-valuenow")) === minimumReadinessCycle
      && stableV1Chip && stableV1Chip.textContent.includes(`${minimumReadinessCycle} / 7`)
      && document.querySelectorAll("#pipeline-nodes [data-pipeline-node]").length === 4,
    cardCounts: document.querySelectorAll(".asset-card").length === 8
      && document.querySelectorAll(".risk-card").length === 3
      && document.querySelectorAll(".research-card").length === 3
      && document.querySelectorAll(".information-card").length === 2
      && document.querySelectorAll(".operation-card").length === 4,
    noHorizontalOverflow: document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1
      && cards.every((card) => {
        const rect = card.getBoundingClientRect();
        return rect.left >= -1 && rect.right <= document.documentElement.clientWidth + 1;
      }),
    responsiveColumns: renderedGridColumns(grid) === expectedColumns.market
      && renderedGridColumns(riskGrid) === expectedColumns.risk
      && renderedGridColumns(researchGrid) === expectedColumns.research
      && renderedGridColumns(informationGrid) === expectedColumns.information
      && renderedGridColumns(operationsGrid) === expectedColumns.operations,
    focusOrder: focusables.length > 6 && focusables[0].classList.contains("skip-link")
      && !focusables.some((element) => {
        return element.matches(".asset-card, .risk-card, .research-card, .information-card, .operation-card");
      }),
    sectionNavigation: sectionLinks.length === 7
      && sectionLinks.every((link) => link.hash && document.getElementById(link.hash.slice(1)))
      && Boolean(document.querySelector("details.method > summary")),
    keyboardTabs,
    tabSemantics: tabs.length === 5
      && tabs.filter((tab) => tab.tabIndex === 0).length === 1
      && tabs.every((tab) => {
        const panel = document.getElementById(tab.getAttribute("aria-controls"));
        return panel && panel.getAttribute("role") === "tabpanel";
      }),
    targetSizes: targetElements.length > 8 && undersizedTargets.length === 0,
    externalLinkSafety: Array.from(document.querySelectorAll('a[target="_blank"]')).every((link) => {
      return /(^|\s)noopener(\s|$)/.test(link.rel) && /(^|\s)noreferrer(\s|$)/.test(link.rel);
    }),
    liveSummary: pageAnnouncer && pageAnnouncer.textContent.indexOf("金融终端加载完成") === 0,
    uniqueIds: (() => {
      const ids = Array.from(document.querySelectorAll("[id]")).map((element) => element.id);
      return ids.length === new Set(ids).size;
    })()
  };
  const failures = Object.keys(checks).filter((name) => !checks[name]);
  const overflowCandidates = Array.from(document.querySelectorAll("body *")).map((element) => {
    const rect = element.getBoundingClientRect();
    return {
      selector: element.id ? `#${element.id}` : `.${String(element.className).trim().split(/\s+/).filter(Boolean).join(".")}`,
      left: Math.round(rect.left),
      right: Math.round(rect.right),
      width: Math.round(rect.width)
    };
  }).filter((item) => item.left < -1 || item.right > width + 1).slice(0, 20);
  const result = {
    status: failures.length ? "fail" : "pass",
    requestedWidth: Number(params.get("width")) || null,
    viewport: { width, height: window.innerHeight },
    scrollWidth: document.documentElement.scrollWidth,
    focusableCount: focusables.length,
    targetCount: targetElements.length,
    supportingHealthPanelCount: supportingHealthPanels.length,
    officialHealthPanelCount: officialHealthPanels.length,
    officialObservationTrendCount: officialTrendPanels.length,
    providerWidgetCount: providerWidgets.length,
    providerWidgetRuntimeStates: providerWidgetShells.map((shell) => shell.getAttribute("data-provider-state")),
    providerWidgetRuntimeEvidence: providerWidgetShells.map((shell) => {
      const fallback = shell.querySelector(".provider-widget-fallback");
      const fallbackLink = fallback && fallback.querySelector("a.source-link");
      return {
        symbol: shell.getAttribute("data-provider-symbol"),
        state: shell.getAttribute("data-provider-state"),
        reason: shell.getAttribute("data-provider-reason"),
        fallbackUrl: fallbackLink ? fallbackLink.href : null,
        fallbackVisible: Boolean(fallback && elementIsRendered(fallback))
      };
    }),
    readinessEvidencePanelCount: readinessEvidencePanels.length,
    stagedDataLoading: stagedLoad,
    undersizedTargets,
    overflowCandidates,
    layout: {
      market: renderedGridColumns(grid),
      risk: renderedGridColumns(riskGrid),
      research: renderedGridColumns(researchGrid),
      information: renderedGridColumns(informationGrid),
      operations: renderedGridColumns(operationsGrid)
    },
    checks,
    failures
  };
  const output = document.createElement("pre");
  output.id = "finance-terminal-regression-result";
  output.hidden = true;
  output.textContent = JSON.stringify(result);
  document.body.appendChild(output);
  document.documentElement.setAttribute("data-regression-status", result.status);
  return result;
}
