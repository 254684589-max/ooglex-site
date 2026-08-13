#!/usr/bin/env node
/** Offline contract tests for the bounded free-proxy browser evidence artifact. */

import assert from "node:assert/strict";
import { buildBrowserEvidence, validateBrowserEvidence } from "./finance_terminal_browser_evidence.mjs";

const symbols = ["SPY", "QQQ", "DIA", "GLD"];
const widths = [360, 768, 1280];
const results = widths.map((width, widthIndex) => ({
  status: "pass",
  viewport: { width, height: 1400 },
  screenshot: `/tmp/runtime/finance-terminal-${width}.png`,
  providerWidgetRuntimeEvidence: symbols.map((symbol, symbolIndex) => {
    const mounted = (widthIndex + symbolIndex) % 2 === 0;
    return {
      symbol,
      state: mounted ? "mounted" : "unavailable",
      reason: mounted ? "connected-defined-element-with-layout" : "registration-timeout"
    };
  })
}));

const evidence = buildBrowserEvidence(results, "2026-08-13T08:00:00Z");
assert.equal(evidence.summary.observationCount, 12);
assert.equal(evidence.summary.mountedObservations, 6);
assert.equal(evidence.summary.fallbackObservations, 6);
assert.equal(validateBrowserEvidence(evidence), evidence);

const quoteLeak = structuredClone(evidence);
quoteLeak.viewports[0].proxies[0].price = 123.45;
assert.throws(() => validateBrowserEvidence(quoteLeak), /未允许字段/);

const falseRender = structuredClone(evidence);
falseRender.doesNotAssert = ["market-open"];
assert.throws(() => validateBrowserEvidence(falseRender), /不得冒充报价渲染/);

const wrongSymbol = structuredClone(evidence);
wrongSymbol.viewports[1].proxies[0].symbol = "SPX";
assert.throws(() => validateBrowserEvidence(wrongSymbol), /代理顺序或代码无效/);

const unverifiedMount = structuredClone(evidence);
unverifiedMount.viewports[0].proxies[0].reason = "custom-element-registered";
assert.throws(() => validateBrowserEvidence(unverifiedMount), /宿主挂载证据无效/);

const forgedSummary = structuredClone(evidence);
forgedSummary.summary.mountedObservations = 12;
assert.throws(() => validateBrowserEvidence(forgedSummary), /汇总不可由逐视口状态复算/);

console.log("Finance Terminal proxy browser evidence contract: PASS");
console.log("- 360 / 768 / 1280px · SPY / QQQ / DIA / GLD: PASS");
console.log("- mounted vs official-link fallback reasons: PASS");
console.log("- no quote fields / no false rendering or freshness claims: PASS");
