/** Build and validate bounded browser evidence for the four free proxy hosts. */

import path from "node:path";

export const EXPECTED_WIDTHS = [360, 768, 1280, 1672];
/* 2026-08-25 所有者决定撤下标普500与纳斯达克100两张代理卡，免费嵌入代理只剩两项。 */
export const EXPECTED_SYMBOLS = ["DIA", "GLD"];
export const EXPECTED_PROVIDER_SCRIPT = "https://widgets.tradingview-widget.com/w/en/tv-mini-chart.js";
export const EXPECTED_FALLBACK_URLS = {
  DIA: "https://www.tradingview.com/symbols/AMEX-DIA/",
  GLD: "https://www.tradingview.com/symbols/AMEX-GLD/"
};

const ALLOWED_STATES = new Set(["mounted", "unavailable"]);
const ALLOWED_UNAVAILABLE_REASONS = new Set([
  "custom-elements-unavailable",
  "registration-timeout",
  "registration-failed",
  "runtime-contract-unavailable",
  "component-host-missing",
  "component-host-tag-mismatch",
  "component-host-disconnected",
  "component-host-not-defined",
  "component-host-layout-unavailable",
  "component-host-empty-layout"
]);
const MOUNTED_REASON = "connected-defined-element-with-layout";
const ALLOWED_SCRIPT_STATES = new Set(["loaded", "failed", "pending", "not-observed"]);
const ALLOWED_SCRIPT_REASONS = new Set([
  "response-ok",
  "http-error",
  "loading-failed",
  "request-blocked",
  "response-pending",
  "not-requested"
]);
const SCRIPT_FAILURE_CATEGORIES = ["dns", "tls", "connection", "timeout", "blocked", "other"];
const ALLOWED_SCRIPT_FAILURE_CATEGORIES = new Set(SCRIPT_FAILURE_CATEGORIES);
const DOES_NOT_ASSERT = ["quote-rendered", "quote-freshness", "market-open"];
const ALLOWED_DIAGNOSIS_STATES = new Set(["healthy", "degraded", "unavailable", "unknown"]);
const ALLOWED_DIAGNOSIS_REASONS = new Set([
  "all-hosts-mounted",
  "partial-host-mount",
  "provider-script-transport-failure",
  "provider-script-response-pending",
  "provider-script-not-observed",
  "component-registration-timeout",
  "component-registration-failed",
  "browser-runtime-unavailable",
  "component-host-verification-failure"
]);

function exactKeys(record, expected) {
  return record && typeof record === "object" && !Array.isArray(record)
    && JSON.stringify(Object.keys(record).sort()) === JSON.stringify([...expected].sort());
}

function require(condition, message) {
  if (!condition) throw new Error(message);
}

export function classifyProviderScriptFailure(event = {}) {
  if (event.blockedReason) return "blocked";
  const errorText = typeof event.errorText === "string" ? event.errorText.toLowerCase() : "";
  if (/name_not_resolved|dns|resolve/.test(errorText)) return "dns";
  if (/ssl|tls|certificate|cert_/.test(errorText)) return "tls";
  if (/timed_out|timeout/.test(errorText)) return "timeout";
  if (/blocked|access_denied/.test(errorText)) return "blocked";
  if (/connection|internet_disconnected|network_changed|address_unreachable/.test(errorText)) {
    return "connection";
  }
  return "other";
}

export function buildViewportDiagnosis(providerScript, proxies) {
  const mounted = proxies.filter((proxy) => proxy.state === "mounted").length;
  if (providerScript.state === "failed") {
    return { state: "unavailable", reason: "provider-script-transport-failure" };
  }
  if (providerScript.state === "pending") {
    return { state: "unknown", reason: "provider-script-response-pending" };
  }
  if (providerScript.state === "not-observed") {
    return { state: "unavailable", reason: "provider-script-not-observed" };
  }
  if (mounted === proxies.length) return { state: "healthy", reason: "all-hosts-mounted" };
  if (mounted > 0) return { state: "degraded", reason: "partial-host-mount" };
  if (proxies.every((proxy) => proxy.reason === "registration-timeout")) {
    return { state: "unavailable", reason: "component-registration-timeout" };
  }
  if (proxies.every((proxy) => proxy.reason === "registration-failed")) {
    return { state: "unavailable", reason: "component-registration-failed" };
  }
  if (proxies.every((proxy) => ["custom-elements-unavailable", "runtime-contract-unavailable"].includes(proxy.reason))) {
    return { state: "unavailable", reason: "browser-runtime-unavailable" };
  }
  return { state: "unavailable", reason: "component-host-verification-failure" };
}

export function validateBrowserEvidence(evidence) {
  require(exactKeys(evidence, [
    "schemaVersion", "generatedAt", "scope", "source", "viewports", "summary",
    "doesNotAssert", "doesNotReadOrStoreQuotes"
  ]), "浏览器证据顶层字段无效");
  require(evidence.schemaVersion === 6, "浏览器证据版本无效");
  require(typeof evidence.generatedAt === "string"
    && /(?:Z|[+-]\d{2}:\d{2})$/.test(evidence.generatedAt)
    && Number.isFinite(Date.parse(evidence.generatedAt)), "浏览器证据时间无效");
  require(evidence.scope === "finance-terminal-free-proxy-runtime", "浏览器证据范围无效");
  require(evidence.source === "Chrome DevTools Protocol / static branch checkout", "浏览器证据来源无效");
  require(JSON.stringify(evidence.doesNotAssert) === JSON.stringify(DOES_NOT_ASSERT),
    "浏览器宿主证据不得冒充报价渲染、新鲜度或开市状态");
  require(evidence.doesNotReadOrStoreQuotes === true, "浏览器证据不得读取或保存组件行情");
  require(Array.isArray(evidence.viewports) && evidence.viewports.length === EXPECTED_WIDTHS.length,
    "浏览器证据必须覆盖三档视口");

  let mountedObservations = 0;
  let fallbackObservations = 0;
  let providerScriptLoadedViewports = 0;
  let providerScriptFailedViewports = 0;
  let providerScriptPendingViewports = 0;
  let providerScriptNotObservedViewports = 0;
  const diagnosisCounts = { healthy: 0, degraded: 0, unavailable: 0, unknown: 0 };
  evidence.viewports.forEach((viewport, index) => {
    require(exactKeys(viewport, ["width", "status", "screenshot", "providerScript", "proxies", "diagnosis"]),
      "浏览器视口证据字段无效");
    require(viewport.width === EXPECTED_WIDTHS[index], "浏览器视口顺序或宽度无效");
    require(viewport.status === "pass", `${viewport.width}px浏览器证据未通过`);
    require(viewport.screenshot === `finance-terminal-${viewport.width}.png`,
      `${viewport.width}px截图名称无效`);
    const script = viewport.providerScript;
    require(exactKeys(script, ["url", "state", "reason", "httpStatus", "fromCache", "failureCategory"]),
      `${viewport.width}px提供方脚本证据字段无效`);
    require(script.url === EXPECTED_PROVIDER_SCRIPT, `${viewport.width}px提供方脚本URL无效`);
    require(ALLOWED_SCRIPT_STATES.has(script.state), `${viewport.width}px提供方脚本状态无效`);
    require(ALLOWED_SCRIPT_REASONS.has(script.reason), `${viewport.width}px提供方脚本原因无效`);
    if (script.state === "loaded") {
      require(script.reason === "response-ok"
        && Number.isInteger(script.httpStatus) && script.httpStatus >= 200 && script.httpStatus < 400
        && typeof script.fromCache === "boolean" && script.failureCategory === null,
      `${viewport.width}px提供方脚本成功证据无效`);
      providerScriptLoadedViewports += 1;
    } else if (script.state === "failed") {
      const httpFailure = script.reason === "http-error"
        && Number.isInteger(script.httpStatus) && script.httpStatus >= 400 && script.httpStatus < 600
        && typeof script.fromCache === "boolean" && script.failureCategory === null;
      const transportFailure = ["loading-failed", "request-blocked"].includes(script.reason)
        && script.httpStatus === null && script.fromCache === null
        && ALLOWED_SCRIPT_FAILURE_CATEGORIES.has(script.failureCategory)
        && (script.reason !== "request-blocked" || script.failureCategory === "blocked");
      require(httpFailure || transportFailure, `${viewport.width}px提供方脚本失败证据无效`);
      providerScriptFailedViewports += 1;
    } else if (script.state === "pending") {
      require(script.reason === "response-pending" && script.httpStatus === null
        && typeof script.fromCache === "boolean" && script.failureCategory === null,
      `${viewport.width}px提供方脚本等待证据无效`);
      providerScriptPendingViewports += 1;
    } else {
      require(script.reason === "not-requested" && script.httpStatus === null && script.fromCache === null
        && script.failureCategory === null,
        `${viewport.width}px提供方脚本未观察证据无效`);
      providerScriptNotObservedViewports += 1;
    }
    require(Array.isArray(viewport.proxies) && viewport.proxies.length === EXPECTED_SYMBOLS.length,
      `${viewport.width}px代理证据数量无效`);
    viewport.proxies.forEach((proxy, proxyIndex) => {
      require(exactKeys(proxy, ["symbol", "state", "reason", "fallbackUrl", "fallbackVisible"]),
        `${viewport.width}px代理证据含有未允许字段`);
      require(proxy.symbol === EXPECTED_SYMBOLS[proxyIndex],
        `${viewport.width}px代理顺序或代码无效`);
      require(proxy.fallbackUrl === EXPECTED_FALLBACK_URLS[proxy.symbol],
        `${proxy.symbol}官方回退链接无效`);
      require(typeof proxy.fallbackVisible === "boolean",
        `${proxy.symbol}官方回退可见性无效`);
      require(ALLOWED_STATES.has(proxy.state), `${proxy.symbol}运行时状态无效`);
      if (proxy.state === "mounted") {
        require(proxy.reason === MOUNTED_REASON, `${proxy.symbol}宿主挂载证据无效`);
        require(proxy.fallbackVisible === false, `${proxy.symbol}宿主挂载时不得显示回退链接`);
        mountedObservations += 1;
      } else {
        require(ALLOWED_UNAVAILABLE_REASONS.has(proxy.reason), `${proxy.symbol}失败回退原因无效`);
        require(proxy.fallbackVisible === true, `${proxy.symbol}不可用时必须显示官方回退链接`);
        fallbackObservations += 1;
      }
    });
    require(exactKeys(viewport.diagnosis, ["state", "reason"])
      && ALLOWED_DIAGNOSIS_STATES.has(viewport.diagnosis.state)
      && ALLOWED_DIAGNOSIS_REASONS.has(viewport.diagnosis.reason),
    `${viewport.width}px关联诊断字段无效`);
    require(JSON.stringify(viewport.diagnosis) === JSON.stringify(buildViewportDiagnosis(script, viewport.proxies)),
      `${viewport.width}px关联诊断不可由脚本传输与宿主状态复算`);
    diagnosisCounts[viewport.diagnosis.state] += 1;
  });

  const expectedSummary = {
    viewportCount: EXPECTED_WIDTHS.length,
    proxyCountPerViewport: EXPECTED_SYMBOLS.length,
    observationCount: EXPECTED_WIDTHS.length * EXPECTED_SYMBOLS.length,
    mountedObservations,
    fallbackObservations,
    verifiedFallbackObservations: fallbackObservations,
    hiddenFallbackObservations: mountedObservations,
    providerScriptLoadedViewports,
    providerScriptFailedViewports,
    providerScriptPendingViewports,
    providerScriptNotObservedViewports,
    providerScriptFailureCategories: Object.fromEntries(SCRIPT_FAILURE_CATEGORIES.map((category) => [
      category,
      evidence.viewports.filter((viewport) => viewport.providerScript.failureCategory === category).length
    ])),
    diagnosisCounts,
    allViewportsPassed: true
  };
  require(JSON.stringify(evidence.summary) === JSON.stringify(expectedSummary),
    "浏览器证据汇总不可由逐视口状态复算");
  return evidence;
}

export function buildBrowserEvidence(results, generatedAt = new Date().toISOString()) {
  require(Array.isArray(results), "浏览器回归结果必须是数组");
  const viewports = results.map((result) => {
    const proxies = (result.providerWidgetRuntimeEvidence || []).map((proxy) => ({
      symbol: proxy.symbol,
      state: proxy.state,
      reason: proxy.reason,
      fallbackUrl: proxy.fallbackUrl,
      fallbackVisible: proxy.fallbackVisible
    }));
    return {
      width: result.viewport?.width,
      status: result.status,
      screenshot: path.basename(result.screenshot || ""),
      providerScript: result.providerScriptTransport,
      proxies,
      diagnosis: buildViewportDiagnosis(result.providerScriptTransport, proxies)
    };
  });
  const observations = viewports.flatMap((viewport) => viewport.proxies);
  const evidence = {
    schemaVersion: 6,
    generatedAt,
    scope: "finance-terminal-free-proxy-runtime",
    source: "Chrome DevTools Protocol / static branch checkout",
    viewports,
    summary: {
      viewportCount: viewports.length,
      proxyCountPerViewport: EXPECTED_SYMBOLS.length,
      observationCount: observations.length,
      mountedObservations: observations.filter((item) => item.state === "mounted").length,
      fallbackObservations: observations.filter((item) => item.state === "unavailable").length,
      verifiedFallbackObservations: observations.filter((item) => item.state === "unavailable"
        && item.fallbackVisible === true).length,
      hiddenFallbackObservations: observations.filter((item) => item.state === "mounted"
        && item.fallbackVisible === false).length,
      providerScriptLoadedViewports: viewports.filter((item) => item.providerScript?.state === "loaded").length,
      providerScriptFailedViewports: viewports.filter((item) => item.providerScript?.state === "failed").length,
      providerScriptPendingViewports: viewports.filter((item) => item.providerScript?.state === "pending").length,
      providerScriptNotObservedViewports: viewports.filter((item) => item.providerScript?.state === "not-observed").length,
      providerScriptFailureCategories: Object.fromEntries(SCRIPT_FAILURE_CATEGORIES.map((category) => [
        category,
        viewports.filter((item) => item.providerScript?.failureCategory === category).length
      ])),
      diagnosisCounts: {
        healthy: viewports.filter((item) => item.diagnosis.state === "healthy").length,
        degraded: viewports.filter((item) => item.diagnosis.state === "degraded").length,
        unavailable: viewports.filter((item) => item.diagnosis.state === "unavailable").length,
        unknown: viewports.filter((item) => item.diagnosis.state === "unknown").length
      },
      allViewportsPassed: viewports.every((item) => item.status === "pass")
    },
    doesNotAssert: DOES_NOT_ASSERT,
    doesNotReadOrStoreQuotes: true
  };
  return validateBrowserEvidence(evidence);
}

export function renderBrowserEvidenceSummary(evidence) {
  validateBrowserEvidence(evidence);
  const lines = [
    "# Finance Terminal free-proxy runtime evidence",
    "",
    `Generated: ${evidence.generatedAt}`,
    "",
    "This report describes only the allowlisted provider script transport and component-host state. It does not read quotes or assert quote rendering, freshness, or market-open state.",
    "",
    "| Viewport | Provider script | Host diagnosis | Mounted hosts | Verified fallbacks |",
    "|---:|---|---|---:|---:|"
  ];
  evidence.viewports.forEach((viewport) => {
    const mounted = viewport.proxies.filter((proxy) => proxy.state === "mounted").length;
    const status = viewport.providerScript.httpStatus === null
      ? `${viewport.providerScript.reason}${viewport.providerScript.failureCategory ? ` / ${viewport.providerScript.failureCategory}` : ""}`
      : `${viewport.providerScript.reason} / HTTP ${viewport.providerScript.httpStatus}`;
    const verifiedFallbacks = viewport.proxies.filter((proxy) => proxy.state === "unavailable"
      && proxy.fallbackVisible).length;
    lines.push(`| ${viewport.width}px | ${status} | ${viewport.diagnosis.state} / ${viewport.diagnosis.reason} | ${mounted}/${viewport.proxies.length} | ${verifiedFallbacks}/${viewport.proxies.length} |`);
  });
  lines.push("");
  return `${lines.join("\n")}\n`;
}
