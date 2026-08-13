/** Build and validate bounded browser evidence for the four free proxy hosts. */

import path from "node:path";

export const EXPECTED_WIDTHS = [360, 768, 1280];
export const EXPECTED_SYMBOLS = ["SPY", "QQQ", "DIA", "GLD"];

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
const DOES_NOT_ASSERT = ["quote-rendered", "quote-freshness", "market-open"];

function exactKeys(record, expected) {
  return record && typeof record === "object" && !Array.isArray(record)
    && JSON.stringify(Object.keys(record).sort()) === JSON.stringify([...expected].sort());
}

function require(condition, message) {
  if (!condition) throw new Error(message);
}

export function validateBrowserEvidence(evidence) {
  require(exactKeys(evidence, [
    "schemaVersion", "generatedAt", "scope", "source", "viewports", "summary",
    "doesNotAssert", "doesNotReadOrStoreQuotes"
  ]), "浏览器证据顶层字段无效");
  require(evidence.schemaVersion === 1, "浏览器证据版本无效");
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
  evidence.viewports.forEach((viewport, index) => {
    require(exactKeys(viewport, ["width", "status", "screenshot", "proxies"]),
      "浏览器视口证据字段无效");
    require(viewport.width === EXPECTED_WIDTHS[index], "浏览器视口顺序或宽度无效");
    require(viewport.status === "pass", `${viewport.width}px浏览器证据未通过`);
    require(viewport.screenshot === `finance-terminal-${viewport.width}.png`,
      `${viewport.width}px截图名称无效`);
    require(Array.isArray(viewport.proxies) && viewport.proxies.length === EXPECTED_SYMBOLS.length,
      `${viewport.width}px代理证据数量无效`);
    viewport.proxies.forEach((proxy, proxyIndex) => {
      require(exactKeys(proxy, ["symbol", "state", "reason"]),
        `${viewport.width}px代理证据含有未允许字段`);
      require(proxy.symbol === EXPECTED_SYMBOLS[proxyIndex],
        `${viewport.width}px代理顺序或代码无效`);
      require(ALLOWED_STATES.has(proxy.state), `${proxy.symbol}运行时状态无效`);
      if (proxy.state === "mounted") {
        require(proxy.reason === MOUNTED_REASON, `${proxy.symbol}宿主挂载证据无效`);
        mountedObservations += 1;
      } else {
        require(ALLOWED_UNAVAILABLE_REASONS.has(proxy.reason), `${proxy.symbol}失败回退原因无效`);
        fallbackObservations += 1;
      }
    });
  });

  const expectedSummary = {
    viewportCount: EXPECTED_WIDTHS.length,
    proxyCountPerViewport: EXPECTED_SYMBOLS.length,
    observationCount: EXPECTED_WIDTHS.length * EXPECTED_SYMBOLS.length,
    mountedObservations,
    fallbackObservations,
    allViewportsPassed: true
  };
  require(JSON.stringify(evidence.summary) === JSON.stringify(expectedSummary),
    "浏览器证据汇总不可由逐视口状态复算");
  return evidence;
}

export function buildBrowserEvidence(results, generatedAt = new Date().toISOString()) {
  require(Array.isArray(results), "浏览器回归结果必须是数组");
  const viewports = results.map((result) => ({
    width: result.viewport?.width,
    status: result.status,
    screenshot: path.basename(result.screenshot || ""),
    proxies: (result.providerWidgetRuntimeEvidence || []).map((proxy) => ({
      symbol: proxy.symbol,
      state: proxy.state,
      reason: proxy.reason
    }))
  }));
  const observations = viewports.flatMap((viewport) => viewport.proxies);
  const evidence = {
    schemaVersion: 1,
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
      allViewportsPassed: viewports.every((item) => item.status === "pass")
    },
    doesNotAssert: DOES_NOT_ASSERT,
    doesNotReadOrStoreQuotes: true
  };
  return validateBrowserEvidence(evidence);
}
