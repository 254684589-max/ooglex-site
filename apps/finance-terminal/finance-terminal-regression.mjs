const CRITICAL_REQUEST_KEYS = Object.freeze([
  "$config", "macro", "macroHealth", "assetRanking", "assetRankingHealth", "marketLicense"
]);
const DEFERRED_SECTION_NAMES = Object.freeze(["board", "risk", "research", "information", "operations"]);
/* 2026-08-25 所有者决定撤下标普500与纳斯达克100两张ETF代理卡：核心资产六张，
   免费嵌入代理两项（DIA、GLD）。改动清单时这两个常量与契约文件一起改。 */
const EXPECTED_ASSET_CARDS = 6;
const EXPECTED_PROXY_WIDGETS = 2;
/* 站内官方管道卡：只有它们在卡面上直接画主数字，代理卡的报价由组件自己渲染。 */
const EXPECTED_OFFICIAL_CARDS = EXPECTED_ASSET_CARDS - EXPECTED_PROXY_WIDGETS;
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
  const boardPanel = document.getElementById("board-panel");
  const boardTabs = Array.from(document.querySelectorAll("#board-tabs .board-tab"));
  const boardRows = Array.from(document.querySelectorAll("#board-panel .board-row:not(.board-row-head)"));
  const boardToggle = document.querySelector("#board-panel .board-toggle");
  const boardSearch = document.getElementById("board-search");
  /* 折叠壳的默认状态要在量尺寸之前记下来：窄屏默认收起，桌面各自成页保持展开。
     记完立即展开，后面的列数与裁切测量才和改造前一致。 */
  const sectionFolds = Array.from(document.querySelectorAll("details.section-fold"));
  const foldDefaults = sectionFolds.map((fold) => ({ id: fold.id, open: fold.open }));
  const wideViewport = window.innerWidth > 1040;
  sectionFolds.forEach((fold) => { fold.open = true; });
  const boardWatchButtons = Array.from(document.querySelectorAll("#board-panel .watch-toggle"));
  const licenseNotice = document.getElementById("license-notice");
  const pageAnnouncer = document.getElementById("page-announcer");
  const width = window.innerWidth;
  const expectedColumns = width <= 620
    ? { market: 1, risk: 1, research: 1, information: 1, operations: 1 }
    : width <= 1040
      ? { market: 2, risk: 2, research: 2, information: 1, operations: 2 }
      /* 桌面一屏总览里核心资产只占第三行的一格（宽度约为整行的三分之一），
         按两列纵向铺开；它在自己的「资产」视图里仍是四列。 */
      : { market: 2, risk: 3, research: 3, information: 1, operations: 4 };
  const cards = Array.from(document.querySelectorAll(
    ".asset-card, .risk-card, .research-card, .information-card, .operation-card"
  ));
  const focusables = Array.from(document.querySelectorAll(
    'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])'
  )).filter(elementIsRendered);
  const targetMinimum = width <= 620 ? 44 : 24;
  const targetElements = Array.from(document.querySelectorAll(
    ".brand, .back-link, .terminal-rail a, .stable-v1-chip, .section-nav a, .method summary, .period-tab, .source-link, .detail-link, .news-link, .operation-action, .operation-readiness-link, .legal-links a, .board-tab, .board-open, .board-toggle, .board-search"
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
  const overviewLegible = Array.from(document.querySelectorAll(
    "#market-grid .asset-price, #market-grid .asset-footer"));
  const riskHudGauges = Array.from(document.querySelectorAll("#risk-grid .risk-hud-gauge"));
  const marketGlobe = document.getElementById("market-globe-canvas");
  const radarAxisValues = Array.from(document.querySelectorAll("#risk-radar-values text"));
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
  /* 页面现在有两组标签：跨资产周期与品类行情板。键盘与语义都按「组」校验，
     否则第二组一出现，全页只允许一个选中项的旧断言就会误报。 */
  const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
  const tabGroups = [];
  tabs.forEach((tab) => {
    const owner = tab.closest('[role="tablist"]') || tab.parentElement;
    const group = tabGroups.filter((entry) => entry.owner === owner)[0]
      || (tabGroups.push({ owner: owner, items: [] }), tabGroups[tabGroups.length - 1]);
    group.items.push(tab);
  });
  const renderedGroups = tabGroups.filter((group) => group.items.some(elementIsRendered));
  /* 桌面单屏总览下两组标签都可能不在视图里；没有渲染出来的标签组不参与断言，
     与改造前「页面没有标签则跳过」的语义保持一致。 */
  let keyboardTabs = renderedGroups.every((group) => {
    return group.items.filter((tab) => tab.getAttribute("aria-selected") === "true").length === 1;
  });
  renderedGroups.forEach((group) => {
    if (!keyboardTabs) return;
    const selected = group.items.filter((tab) => tab.getAttribute("aria-selected") === "true")[0];
    const previousId = selected.id;
    selected.focus();
    selected.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }));
    const moved = document.activeElement;
    keyboardTabs = Boolean(moved) && moved.getAttribute("role") === "tab"
      && Boolean(previousId) && moved.id !== previousId
      && moved.getAttribute("aria-selected") === "true";
    if (!keyboardTabs) return;
    moved.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true }));
    keyboardTabs = Boolean(document.activeElement) && document.activeElement.id === previousId;
  });

  /* 一屏总览不再摆研究与运维两块，它们在自己的视图里才有布局；
     没有渲染出来的栅格不参与列数断言，桌面分区切换由浏览器校验器逐个核对。 */
  function columnsMatch(grid, expected) {
    return !elementIsRendered(grid) || renderedGridColumns(grid) === expected;
  }

  const checks = {
    dataLoaded: [grid, boardPanel, riskGrid, researchGrid, informationGrid, operationsGrid].every((item) => {
      return item && item.getAttribute("aria-busy") === "false";
    }) && !document.querySelector(".load-error"),
    stagedDataLoading: stagedLoad.mode === "eager"
      && stagedLoad.criticalSourceRequestCount === 5
      && stagedLoad.sourceRequestCount === 20
      && stagedLoad.requestCount === 21
      && stagedLoad.criticalPaintBarrier?.status === "yielded"
      && sameSequence(stagedLoad.startupOrder,
        ["critical-rendered", "critical-paint-yielded", "deferred-scheduler-started"])
      && sameSequence(stagedLoad.requestedKeysAfterCritical, CRITICAL_REQUEST_KEYS)
      && sameSequence(stagedLoad.requestedKeysAtSchedulerStart, CRITICAL_REQUEST_KEYS)
      && sameSequence(stagedLoad.groupLoadSequence, EXPECTED_GROUP_SEQUENCE)
      && Array.isArray(stagedLoad.loadedSections) && stagedLoad.loadedSections.length === 5
      && Array.isArray(stagedLoad.failedSections) && stagedLoad.failedSections.length === 0
      && Array.isArray(stagedLoad.settledSections) && stagedLoad.settledSections.length === 5
      && stagedLoad.networkRequestCount === 21
      && stagedLoad.duplicateNetworkRequestCount === 0
      && requestStates.length === 21 && requestStates.every((state) => state === "ready")
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
    providerWidgetContracts: providerWidgets.length === EXPECTED_PROXY_WIDGETS
      && providerWidgets.every((widget) => {
        return /^AMEX:(DIA|GLD)$/.test(widget.getAttribute("symbol") || "")
          && widget.getAttribute("theme") === "dark";
      }) && document.querySelectorAll(".provider-widget-fallback").length === EXPECTED_PROXY_WIDGETS,
    providerAttribution: poweredByCoinGeckoLinks.length === coinGeckoAttributions.length
      && coinGeckoAttributions.every((link) => {
        return link.textContent.trim() === "Powered by CoinGecko"
          && Number.parseFloat(window.getComputedStyle(link).fontSize) >= 10;
      }),
    providerWidgetRuntime: providerWidgetShells.length === EXPECTED_PROXY_WIDGETS
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
    /* 主数字曾被压进9px盒子。 */
    overviewCardLegibility: overviewLegible.length === EXPECTED_ASSET_CARDS + EXPECTED_OFFICIAL_CARDS
      && overviewLegible.every((n) => n.scrollHeight <= n.clientHeight + 1),
    orbitalTerminalVisuals: marketTapeItems.length === EXPECTED_ASSET_CARDS
      && marketTapeItems.every((item) => item.textContent.trim().length > 4)
      && marketTapeItems.filter((item) => item.textContent.includes("组件报价")).length
        === EXPECTED_PROXY_WIDGETS
      && marketClocks.length === 4
      && marketClocks.every((clock) => /^\d{2}:\d{2}$/.test(clock.textContent.trim()))
      && Boolean(document.querySelector(".market-orbit.globe-canvas-ready"))
      && marketGlobe && marketGlobe.width >= 220 && marketGlobe.height >= 220,
    riskHudVisuals: riskHudGauges.length === 3
      && riskHudGauges.filter((gauge) => gauge.getAttribute("role") === "progressbar").length === 2
      && riskHudGauges.filter((gauge) => gauge.classList.contains("risk-hud-raw")).length === 1
      && radarAxisValues.length === 6
      && radarAxisValues.every((value) => /^\d+\.\d$/.test(value.textContent.trim())),
    globalRiskHeatmap: globalRiskMap && globalRiskMap.getAttribute("aria-busy") === "false"
      && !globalRiskMap.classList.contains("status-loading")
      && riskRegionRows.length === 7
      && riskRegionRows.every((row) => row.querySelector("strong")?.textContent.trim() !== "—")
      && document.querySelectorAll(".risk-region-glow").length === 7
      && document.querySelector('.risk-map-texture[href="../tv/vendor/earth-night.jpg"]')
      && globalRiskMap.textContent.includes("压力代理")
      && globalRiskMap.textContent.includes("Yahoo Finance"),
    marketInsight: !document.getElementById("market-insight-title")?.textContent.includes("正在读取")
      && document.getElementById("market-insight-copy")?.textContent.includes("/10"),
    stableV1Hud: pipelineCommand && pipelineCommand.getAttribute("aria-busy") === "false"
      && stableV1Ring && Number(stableV1Ring.getAttribute("aria-valuenow")) === minimumReadinessCycle
      && stableV1Chip && stableV1Chip.textContent.includes(`${minimumReadinessCycle} / 7`)
      && document.querySelectorAll("#pipeline-nodes [data-pipeline-node]").length === 4,
    cardCounts: document.querySelectorAll(".asset-card").length === EXPECTED_ASSET_CARDS
      && document.querySelectorAll(".risk-card").length === 3
      && document.querySelectorAll(".research-card").length === 3
      && document.querySelectorAll(".information-card").length === 2
      && document.querySelectorAll(".operation-card").length === 4,
    noHorizontalOverflow: document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1
      && cards.every((card) => {
        const rect = card.getBoundingClientRect();
        return rect.left >= -1 && rect.right <= document.documentElement.clientWidth + 1;
      }),
    responsiveColumns: columnsMatch(grid, expectedColumns.market)
      && columnsMatch(riskGrid, expectedColumns.risk)
      && columnsMatch(researchGrid, expectedColumns.research)
      && columnsMatch(informationGrid, expectedColumns.information)
      && columnsMatch(operationsGrid, expectedColumns.operations),
    focusOrder: focusables.length > 6 && focusables[0].classList.contains("skip-link")
      && !focusables.some((element) => {
        return element.matches(".asset-card, .risk-card, .research-card, .information-card, .operation-card");
      }),
    sectionNavigation: sectionLinks.length === 8
      && sectionLinks.every((link) => link.hash && document.getElementById(link.hash.slice(1)))
      && Boolean(document.querySelector("details.method > summary")),
    keyboardTabs,
    tabSemantics: tabs.length === 11
      && renderedGroups.every((group) => group.items.filter((tab) => tab.tabIndex === 0).length === 1)
      && tabs.every((tab) => {
        const panel = document.getElementById(tab.getAttribute("aria-controls"));
        return panel && panel.getAttribute("role") === "tabpanel";
      }),
    /* 工程/运营向分区的明细：窄屏默认收起，桌面（各自成页）保持展开。 */
    sectionFolding: foldDefaults.length === 2
      && foldDefaults.every((fold) => fold.id && fold.open === wideViewport)
      && sectionFolds.every((fold) => fold.querySelector("summary")),
    /* 品类行情板：六个品类都要出标签，当前品类要真的画出带价格与涨跌的行，
       折叠按钮存在时必须处于收起状态（默认不展开整张长列表）。 */
    categoryBoard: boardTabs.length === 6
      && boardTabs.filter((tab) => tab.getAttribute("aria-selected") === "true").length === 1
      && boardRows.length >= 4
      && boardRows.every((row) => {
        const price = row.querySelector(".board-cell-price");
        const change = row.querySelector(".board-cell-change");
        return price && price.textContent.trim() && change && change.textContent.trim();
      })
      && (!boardToggle || boardToggle.getAttribute("aria-expanded") === "false")
      && Boolean(boardSearch) && boardSearch.type === "search"
      && boardWatchButtons.length === boardRows.length
      && boardWatchButtons.every((button) => button.getAttribute("aria-pressed") === "false"
        || button.getAttribute("aria-pressed") === "true"),
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
    assetCardCount: document.querySelectorAll(".asset-card").length,
    sectionFolds: foldDefaults,
    board: {
      tabs: boardTabs.length,
      rows: boardRows.length,
      collapsed: Boolean(boardToggle),
      search: Boolean(boardSearch),
      watchToggles: boardWatchButtons.length
    },
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
