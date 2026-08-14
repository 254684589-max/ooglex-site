import assert from "node:assert/strict";
import {
  createDeferredSectionScheduler,
  createResourceLoader,
  financeTerminalResourceContract
} from "../apps/finance-terminal/finance-terminal-loader.mjs";
import { runBrowserRegressionProbe } from "../apps/finance-terminal/finance-terminal-regression.mjs";

function fakeResponse(payload, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => payload
  };
}

async function validateResourceStages() {
  const calls = [];
  const loader = createResourceLoader({
    cacheKey: "contract",
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return fakeResponse({ url });
    }
  });
  const [config, critical] = await Promise.all([loader.loadConfig(), loader.loadGroup("critical")]);
  assert.equal(typeof config.url, "string");
  assert.deepEqual(Object.keys(critical), [
    "macro", "macroHealth", "assetRanking", "assetRankingHealth", "marketLicense"
  ]);
  assert.equal(loader.snapshot().sourceRequestCount, 5, "首屏只应读取5份核心资源");
  assert.equal(loader.snapshot().requestCount, 6, "首屏应读取1份配置与5份核心资源");

  await loader.loadGroup("research");
  assert.equal(loader.snapshot().sourceRequestCount, 9, "研究区应复用已加载的资产榜资源");
  await loader.loadGroup("operations");
  assert.equal(loader.snapshot().sourceRequestCount, 10, "运行证据区应复用宏观、资产榜、跨资产与公司资源");
  await Promise.all([loader.loadGroup("risk"), loader.loadGroup("information")]);
  assert.equal(loader.snapshot().sourceRequestCount, 18, "全页最终应覆盖16份上游与2份本地证据资源");
  assert.equal(calls.length, 19, "同一资源不得因跨分区复用而重复请求");
  assert.equal(new Set(calls.map((call) => call.url)).size, calls.length, "请求URL必须唯一");
  assert.ok(calls.every((call) => call.options.cache === "no-store"), "静态金融快照必须保留no-store请求契约");
}

async function validateFailureIsolation() {
  const loader = createResourceLoader({
    cacheKey: "failure",
    fetchImpl: async (url) => url.startsWith("../ofr-monitor/")
      ? fakeResponse({}, 503)
      : fakeResponse({ ok: true })
  });
  const risk = await loader.loadGroup("risk");
  assert.equal(risk.macro.error, null);
  assert.match(risk.ofr.error.message, /^HTTP 503$/);
  assert.match(risk.ofrHealth.error.message, /^HTTP 503$/);
}

async function validateDeferredScheduler() {
  const observed = [];
  let instance;
  class FakeObserver {
    constructor(callback) {
      this.callback = callback;
      instance = this;
    }
    observe(target) { observed.push(target); }
    unobserve() {}
    disconnect() {}
    fire(target) { this.callback([{ target, isIntersecting: true }]); }
  }
  function fakeLink(hash) {
    const listeners = {};
    return {
      hash,
      addEventListener(type, listener) { listeners[type] = listener; },
      removeEventListener(type) { delete listeners[type]; },
      click() { listeners.click(); }
    };
  }
  const sections = {
    risk: { id: "risk-section" },
    research: { id: "research-section" },
    information: { id: "information-section" },
    operations: { id: "operations-section" }
  };
  const links = Object.values(sections).map((section) => fakeLink(`#${section.id}`));
  const loaded = [];
  const handlers = Object.keys(sections).reduce((result, name) => {
    result[name] = async () => { loaded.push(name); };
    return result;
  }, {});
  const scheduler = createDeferredSectionScheduler({
    handlers,
    sections,
    navigationLinks: links,
    Observer: FakeObserver
  });
  const start = scheduler.start();
  assert.equal(start.mode, "deferred");
  assert.equal(loaded.length, 0, "延迟模式启动时不得预取首屏以下分区");
  assert.equal(observed.length, 4);
  instance.fire(sections.risk);
  links[1].click();
  await Promise.all([scheduler.load("information"), scheduler.load("operations")]);
  await scheduler.allLoaded;
  assert.deepEqual(new Set(loaded), new Set(["risk", "research", "information", "operations"]));
  scheduler.disconnect();
}

async function main() {
  assert.equal(financeTerminalResourceContract.criticalSourceCount, 5);
  assert.equal(financeTerminalResourceContract.upstreamSourceCount, 16);
  assert.equal(financeTerminalResourceContract.localEvidenceSourceCount, 2);
  assert.equal(typeof runBrowserRegressionProbe, "function");
  await validateResourceStages();
  await validateFailureIsolation();
  await validateDeferredScheduler();
  console.log("Finance Terminal staged loader contract: PASS");
  console.log("- 5 critical sources / 13 deferred sources / 18 unique source requests: PASS");
  console.log("- viewport and section-navigation activation / shared request cache: PASS");
  console.log("- per-source HTTP failure isolation / no-store snapshots: PASS");
}

main().catch((error) => {
  console.error(error.stack || error.message || String(error));
  process.exitCode = 1;
});
