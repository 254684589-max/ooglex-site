#!/usr/bin/env node
/** Offline contract tests for the bounded free-proxy browser evidence artifact. */

import assert from "node:assert/strict";
import {
  buildBrowserEvidence,
  classifyProviderScriptFailure,
  renderBrowserEvidenceSummary,
  validateBrowserEvidence
} from "./finance_terminal_browser_evidence.mjs";

const symbols = ["SPY", "QQQ", "DIA", "GLD"];
const fallbackUrls = {
  SPY: "https://www.tradingview.com/symbols/AMEX-SPY/",
  QQQ: "https://www.tradingview.com/symbols/NASDAQ-QQQ/",
  DIA: "https://www.tradingview.com/symbols/AMEX-DIA/",
  GLD: "https://www.tradingview.com/symbols/AMEX-GLD/"
};
const widths = [360, 768, 1280];
const results = widths.map((width, widthIndex) => ({
  status: "pass",
  viewport: { width, height: 1400 },
  screenshot: `/tmp/runtime/finance-terminal-${width}.png`,
  providerScriptTransport: widthIndex === 0
    ? {
        url: "https://www.tradingview-widget.com/w/en/tv-mini-chart.js",
        state: "loaded",
        reason: "response-ok",
        httpStatus: 200,
        fromCache: false,
        failureCategory: null
      }
    : widthIndex === 1
      ? {
          url: "https://www.tradingview-widget.com/w/en/tv-mini-chart.js",
          state: "failed",
          reason: "request-blocked",
          httpStatus: null,
          fromCache: null,
          failureCategory: "blocked"
        }
      : {
          url: "https://www.tradingview-widget.com/w/en/tv-mini-chart.js",
          state: "pending",
          reason: "response-pending",
          httpStatus: null,
          fromCache: true,
          failureCategory: null
        },
  providerWidgetRuntimeEvidence: symbols.map((symbol, symbolIndex) => {
    const mounted = (widthIndex + symbolIndex) % 2 === 0;
    return {
      symbol,
      state: mounted ? "mounted" : "unavailable",
      reason: mounted ? "connected-defined-element-with-layout" : "registration-timeout",
      fallbackUrl: fallbackUrls[symbol],
      fallbackVisible: !mounted
    };
  })
}));

const evidence = buildBrowserEvidence(results, "2026-08-13T08:00:00Z");
assert.equal(evidence.summary.observationCount, 12);
assert.equal(evidence.summary.mountedObservations, 6);
assert.equal(evidence.summary.fallbackObservations, 6);
assert.equal(evidence.summary.verifiedFallbackObservations, 6);
assert.equal(evidence.summary.hiddenFallbackObservations, 6);
assert.equal(evidence.summary.providerScriptLoadedViewports, 1);
assert.equal(evidence.summary.providerScriptFailedViewports, 1);
assert.equal(evidence.summary.providerScriptPendingViewports, 1);
assert.equal(evidence.summary.providerScriptNotObservedViewports, 0);
assert.deepEqual(evidence.summary.providerScriptFailureCategories, {
  dns: 0,
  tls: 0,
  connection: 0,
  timeout: 0,
  blocked: 1,
  other: 0
});
assert.deepEqual(evidence.summary.diagnosisCounts, {
  healthy: 0,
  degraded: 1,
  unavailable: 1,
  unknown: 1
});
assert.equal(validateBrowserEvidence(evidence), evidence);
const markdown = renderBrowserEvidenceSummary(evidence);
assert.match(markdown, /Provider script/);
assert.match(markdown, /HTTP 200/);
assert.match(markdown, /partial-host-mount/);
assert.match(markdown, /does not read quotes/);
assert.match(markdown, /request-blocked \/ blocked/);
assert.match(markdown, /Verified fallbacks/);

assert.equal(classifyProviderScriptFailure({ errorText: "net::ERR_NAME_NOT_RESOLVED" }), "dns");
assert.equal(classifyProviderScriptFailure({ errorText: "net::ERR_CERT_AUTHORITY_INVALID" }), "tls");
assert.equal(classifyProviderScriptFailure({ errorText: "net::ERR_CONNECTION_REFUSED" }), "connection");
assert.equal(classifyProviderScriptFailure({ errorText: "net::ERR_TIMED_OUT" }), "timeout");
assert.equal(classifyProviderScriptFailure({ errorText: "net::ERR_BLOCKED_BY_CLIENT" }), "blocked");
assert.equal(classifyProviderScriptFailure({ errorText: "net::ERR_FAILED" }), "other");
assert.equal(classifyProviderScriptFailure({ blockedReason: "inspector", errorText: "secret detail" }), "blocked");

const quoteLeak = structuredClone(evidence);
quoteLeak.viewports[0].proxies[0].price = 123.45;
assert.throws(() => validateBrowserEvidence(quoteLeak), /未允许字段/);

const falseRender = structuredClone(evidence);
falseRender.doesNotAssert = ["market-open"];
assert.throws(() => validateBrowserEvidence(falseRender), /不得冒充报价渲染/);

const wrongSymbol = structuredClone(evidence);
wrongSymbol.viewports[1].proxies[0].symbol = "SPX";
assert.throws(() => validateBrowserEvidence(wrongSymbol), /代理顺序或代码无效/);

const wrongFallbackUrl = structuredClone(evidence);
wrongFallbackUrl.viewports[0].proxies[0].fallbackUrl = "https://example.com/SPY";
assert.throws(() => validateBrowserEvidence(wrongFallbackUrl), /官方回退链接无效/);

const hiddenRequiredFallback = structuredClone(evidence);
hiddenRequiredFallback.viewports[0].proxies[1].fallbackVisible = false;
assert.throws(() => validateBrowserEvidence(hiddenRequiredFallback), /不可用时必须显示官方回退链接/);

const visibleMountedFallback = structuredClone(evidence);
visibleMountedFallback.viewports[0].proxies[0].fallbackVisible = true;
assert.throws(() => validateBrowserEvidence(visibleMountedFallback), /宿主挂载时不得显示回退链接/);

const unverifiedMount = structuredClone(evidence);
unverifiedMount.viewports[0].proxies[0].reason = "custom-element-registered";
assert.throws(() => validateBrowserEvidence(unverifiedMount), /宿主挂载证据无效/);

const forgedSummary = structuredClone(evidence);
forgedSummary.summary.mountedObservations = 12;
assert.throws(() => validateBrowserEvidence(forgedSummary), /汇总不可由逐视口状态复算/);

const scriptLeak = structuredClone(evidence);
scriptLeak.viewports[0].providerScript.responseBody = "not allowed";
assert.throws(() => validateBrowserEvidence(scriptLeak), /脚本证据字段无效/);

const wrongScript = structuredClone(evidence);
wrongScript.viewports[0].providerScript.url = "https://example.com/widget.js";
assert.throws(() => validateBrowserEvidence(wrongScript), /脚本URL无效/);

const falseHttpSuccess = structuredClone(evidence);
falseHttpSuccess.viewports[0].providerScript.httpStatus = 503;
assert.throws(() => validateBrowserEvidence(falseHttpSuccess), /脚本成功证据无效/);

const rawTransportFailure = structuredClone(evidence);
rawTransportFailure.viewports[1].providerScript.errorText = "net::ERR_BLOCKED_BY_CLIENT";
assert.throws(() => validateBrowserEvidence(rawTransportFailure), /脚本证据字段无效/);

const falseFailureCategory = structuredClone(evidence);
falseFailureCategory.viewports[1].providerScript.failureCategory = "proxy-auth-required";
assert.throws(() => validateBrowserEvidence(falseFailureCategory), /脚本失败证据无效/);

const forgedDiagnosis = structuredClone(evidence);
forgedDiagnosis.viewports[0].diagnosis = { state: "healthy", reason: "all-hosts-mounted" };
assert.throws(() => validateBrowserEvidence(forgedDiagnosis), /关联诊断不可由脚本传输与宿主状态复算/);

console.log("Finance Terminal proxy browser evidence contract: PASS");
console.log("- 360 / 768 / 1280px · SPY / QQQ / DIA / GLD: PASS");
console.log("- mounted vs official-link fallback reasons: PASS");
console.log("- exact allowlisted official fallback URL and state-linked visibility: PASS");
console.log("- allowlisted provider script request / response / cache / failure states: PASS");
console.log("- bounded DNS / TLS / connection / timeout / blocked / other failure categories: PASS");
console.log("- transport-to-host diagnosis and bounded Markdown summary: PASS");
console.log("- no quote fields / no false rendering or freshness claims: PASS");
