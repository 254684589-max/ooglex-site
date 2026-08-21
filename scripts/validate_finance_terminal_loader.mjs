import assert from "node:assert/strict";
import {
  createDeferredSectionScheduler,
  createResourceLoader,
  financeTerminalResourceContract,
  startFinanceTerminal,
  waitForCriticalPaint
} from "../apps/finance-terminal/finance-terminal-loader.mjs";
import { runBrowserRegressionProbe } from "../apps/finance-terminal/finance-terminal-regression.mjs";
import { createRiskView } from "../apps/finance-terminal/finance-terminal-risk-view.mjs";
import { createResearchView } from "../apps/finance-terminal/finance-terminal-research-view.mjs";

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
  const snapshot = loader.snapshot();
  assert.equal(snapshot.sourceRequestCount, 18, "全页最终应覆盖16份上游与2份本地证据资源");
  assert.equal(calls.length, 19, "同一资源不得因跨分区复用而重复请求");
  assert.equal(new Set(calls.map((call) => call.url)).size, calls.length, "请求URL必须唯一");
  assert.ok(calls.every((call) => call.options.cache === "no-store"), "静态金融快照必须保留no-store请求契约");
  assert.deepEqual(snapshot.groupLoadSequence,
    ["critical", "research", "operations", "risk", "information"],
    "加载证据必须保留实际分区启动顺序");
  assert.equal(snapshot.networkRequestCount, 19);
  assert.equal(snapshot.duplicateNetworkRequestCount, 0, "共享资源不得产生重复网络请求");
  assert.ok(Object.values(snapshot.requestStates).every((state) => state === "ready"));
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
  const snapshot = loader.snapshot();
  assert.equal(snapshot.requestStates.macro, "ready");
  assert.equal(snapshot.requestStates.ofr, "error");
  assert.equal(snapshot.requestStates.ofrHealth, "error");
  assert.equal(snapshot.duplicateNetworkRequestCount, 0);
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
  assert.deepEqual(await scheduler.allSettled, {
    loaded: ["risk", "research", "information", "operations"],
    failed: [],
    settled: ["risk", "research", "information", "operations"]
  });
  assert.deepEqual(new Set(loaded), new Set(["risk", "research", "information", "operations"]));
  scheduler.disconnect();
}

async function validateDeferredFailureIsolation() {
  const completed = [];
  const transitions = [];
  const scheduler = createDeferredSectionScheduler({
    eager: true,
    handlers: {
      risk: async () => { throw new Error("risk adapter unavailable"); },
      research: async () => { completed.push("research"); },
      information: async () => { completed.push("information"); },
      operations: async () => { completed.push("operations"); }
    },
    sections: {},
    onStateChange(state) {
      transitions.push({
        name: state.name,
        state: state.state,
        loaded: state.loaded.slice(),
        failed: state.failed.slice(),
        settled: state.settled.slice()
      });
    }
  });
  scheduler.start();
  const rejected = assert.rejects(scheduler.allLoaded, /risk adapter unavailable/);
  const summary = await scheduler.allSettled;
  await rejected;
  assert.deepEqual(new Set(completed), new Set(["research", "information", "operations"]),
    "单个分区失败后其余分区仍必须完成");
  assert.deepEqual(summary.failed, ["risk"]);
  assert.deepEqual(new Set(summary.loaded), new Set(["research", "information", "operations"]));
  assert.deepEqual(new Set(summary.settled),
    new Set(["risk", "research", "information", "operations"]));
  assert.deepEqual(scheduler.failedSections(), ["risk"]);
  assert.equal(transitions.filter((item) => item.state === "error").length, 1);
  assert.equal(transitions.filter((item) => item.state === "ready").length, 3);
}

async function validateCriticalPaintBarrier() {
  const frames = [];
  let resolved = false;
  const barrier = waitForCriticalPaint({
    requestAnimationFrame(callback) { frames.push(callback); }
  }).then((result) => {
    resolved = true;
    return result;
  });
  assert.equal(frames.length, 1, "首帧回调必须先登记");
  frames.shift()();
  assert.equal(resolved, false, "单帧不能冒充关键内容已经完成一次绘制");
  assert.equal(frames.length, 1, "首帧后必须登记第二帧边界");
  frames.shift()();
  assert.deepEqual(await barrier, {
    status: "yielded", strategy: "double-animation-frame", frameCount: 2
  });

  const phases = [];
  const attributes = new Map();
  const doc = {
    documentElement: {
      setAttribute(name, value) { attributes.set(name, value); }
    }
  };
  const win = { location: { search: "" } };
  await startFinanceTerminal({
    document: doc,
    window: win,
    loaderOptions: {
      cacheKey: "paint",
      fetchImpl: async (url) => fakeResponse({ url })
    },
    buildCritical: () => ({ marketLicense: {}, sections: [] }),
    renderCritical: () => { phases.push("critical-rendered"); },
    announceCritical: () => {},
    monitorProvider: () => Promise.resolve(),
    yieldAfterCritical: () => { phases.push("paint-yielded"); },
    buildSection: () => [],
    renderSection: () => {},
    sections: {},
    navigationLinks: []
  });
  assert.deepEqual(phases, ["critical-rendered", "paint-yielded"]);
  assert.deepEqual(win.__financeTerminalLoadState.startupOrder, [
    "critical-rendered", "critical-paint-yielded", "deferred-scheduler-started"
  ]);
  assert.deepEqual(
    win.__financeTerminalLoadState.requestedKeysAtSchedulerStart,
    win.__financeTerminalLoadState.requestedKeysAfterCritical,
    "延迟调度器启动前不得夹带首屏以下请求"
  );
  assert.equal(win.__financeTerminalLoadState.criticalPaintBarrier.strategy, "injected");
  assert.deepEqual(win.__financeTerminalLoadState.groupLoadSequence, ["critical"]);
  assert.equal(win.__financeTerminalLoadState.duplicateNetworkRequestCount, 0);
  assert.ok(Object.values(win.__financeTerminalLoadState.requestStates)
    .every((state) => state === "ready"));
  assert.equal(attributes.get("data-critical-data-state"), "ready");
}

async function validateAsyncSectionBuild() {
  const attributes = new Map();
  const phases = [];
  const doc = {
    documentElement: {
      setAttribute(name, value) { attributes.set(name, value); }
    }
  };
  const win = { location: { search: "?loadAll=1" } };
  const result = await startFinanceTerminal({
    document: doc,
    window: win,
    loaderOptions: {
      cacheKey: "async-section",
      fetchImpl: async (url) => fakeResponse({ url })
    },
    buildCritical: () => ({ marketLicense: {}, risks: [] }),
    renderCritical: () => {},
    monitorProvider: () => Promise.resolve(),
    yieldAfterCritical: () => {},
    buildSection: async (name) => {
      phases.push(`${name}-module-ready`);
      return [{ id: name }];
    },
    renderSection: (name, cards) => {
      assert.equal(cards[0].id, name);
      phases.push(`${name}-rendered`);
    },
    experienceKeys: { risk: "risks" },
    sections: { risk: { id: "risk-section" } },
    navigationLinks: []
  });
  assert.deepEqual(phases, ["risk-module-ready", "risk-rendered"],
    "延迟区块必须等待异步视图模块后再渲染");
  assert.deepEqual(result.experience.risks, [{ id: "risk" }]);
  assert.equal(attributes.get("data-deferred-data-state"), "ready");
}

function validateRiskViewContract() {
  assert.throws(() => createRiskView({}), /市场状态视图缺少依赖：document/);
  const grid = {
    textContent: "loading",
    appendChild() {},
    setAttribute(name, value) { this[name] = value; }
  };
  const summary = { textContent: "" };
  const noop = () => {};
  const view = createRiskView({
    document: {}, grid, summary,
    isNumber: Number.isFinite,
    appendText: noop,
    appendSupportingHealth: noop,
    formatDate: noop,
    appendSource: noop,
    formatTimestamp: noop,
    isSafeHref: noop
  });
  view.render([]);
  assert.equal(grid["aria-busy"], "false");
  assert.equal(summary.textContent, "0 ACTIVE · 0 PARTIAL · 0 STALE · 0 ERROR");
}

function validateResearchViewContract() {
  assert.throws(() => createResearchView({}), /市场研究视图缺少依赖：document/);
  const grid = {
    textContent: "loading",
    appendChild() {},
    setAttribute(name, value) { this[name] = value; }
  };
  const summary = { textContent: "" };
  const noop = () => {};
  const view = createResearchView({
    document: {}, grid, summary,
    isNumber: Number.isFinite,
    appendText: noop,
    formatSignedPercent: noop,
    appendQualitySummary: noop,
    appendSourceHealth: noop,
    rankCrossAssetPeriod: noop,
    periodTabTargetIndex: noop,
    appendResearchFooter: noop
  });
  view.render([]);
  assert.equal(grid["aria-busy"], "false");
  assert.equal(summary.textContent, "0 ACTIVE · 0 PARTIAL · 0 STALE · 0 ERROR");
}

async function main() {
  assert.equal(financeTerminalResourceContract.criticalSourceCount, 5);
  assert.equal(financeTerminalResourceContract.upstreamSourceCount, 16);
  assert.equal(financeTerminalResourceContract.localEvidenceSourceCount, 2);
  assert.equal(typeof runBrowserRegressionProbe, "function");
  await validateResourceStages();
  await validateFailureIsolation();
  await validateDeferredScheduler();
  await validateDeferredFailureIsolation();
  await validateCriticalPaintBarrier();
  await validateAsyncSectionBuild();
  validateRiskViewContract();
  validateResearchViewContract();
  console.log("Finance Terminal staged loader contract: PASS");
  console.log("- 5 critical sources / 13 deferred sources / 18 unique source requests: PASS");
  console.log("- viewport and section-navigation activation / shared request cache: PASS");
  console.log("- per-source HTTP failure isolation / no-store snapshots: PASS");
  console.log("- critical render / paint yield / deferred scheduler order: PASS");
  console.log("- one-section failure / three-section continuation / partial completion: PASS");
  console.log("- per-request state / network de-duplication / section transition evidence: PASS");
  console.log("- async section module barrier / risk + research view contracts: PASS");
}

main().catch((error) => {
  console.error(error.stack || error.message || String(error));
  process.exitCode = 1;
});
