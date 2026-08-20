const RESOURCE_PATHS = Object.freeze({
  macro: "../macro-radar/data.json",
  macroHealth: "../macro-radar/health.json",
  fearGreed: "../fear-greed/data.json",
  fearGreedHealth: "../fear-greed/health.json",
  ofr: "../ofr-monitor/data.json",
  ofrHealth: "../ofr-monitor/health.json",
  assetTracker: "../asset-tracker/data.json",
  assetTrackerHealth: "../asset-tracker/health.json",
  assetRanking: "../asset-ranking/data.json",
  assetRankingHealth: "../asset-ranking/health.json",
  companies: "../companies/data.json",
  companiesHealth: "../companies/health.json",
  calendar: "../econ-calendar/data.json",
  calendarHealth: "../econ-calendar/health.json",
  news: "../whats-latest/data.json",
  newsHealth: "../whats-latest/health.json",
  readiness: "readiness.json",
  marketLicense: "market-source-readiness.json"
});

const RESOURCE_GROUPS = Object.freeze({
  critical: Object.freeze([
    "macro", "macroHealth", "assetRanking", "assetRankingHealth", "marketLicense"
  ]),
  risk: Object.freeze([
    "macro", "fearGreed", "fearGreedHealth", "ofr", "ofrHealth"
  ]),
  research: Object.freeze([
    "assetTracker", "assetTrackerHealth", "assetRanking", "assetRankingHealth",
    "companies", "companiesHealth"
  ]),
  information: Object.freeze([
    "calendar", "calendarHealth", "news", "newsHealth"
  ]),
  operations: Object.freeze([
    "macro", "macroHealth", "assetTracker", "assetTrackerHealth", "companies",
    "companiesHealth", "assetRanking", "assetRankingHealth", "readiness"
  ])
});

function resourceUrl(path, cacheKey) {
  const separator = path.includes("?") ? "&" : "?";
  return `${path}${separator}t=${encodeURIComponent(cacheKey)}`;
}

function errorMessage(error) {
  return error && typeof error.message === "string" ? error.message : String(error || "请求失败");
}

export function waitForCriticalPaint(win, yieldImpl) {
  if (typeof yieldImpl === "function") {
    return Promise.resolve().then(() => yieldImpl()).then(() => ({
      status: "yielded",
      strategy: "injected",
      frameCount: null
    }));
  }
  if (!win || typeof win.requestAnimationFrame !== "function") {
    return Promise.resolve({
      status: "yielded",
      strategy: "animation-frame-unavailable",
      frameCount: 0
    });
  }
  return new Promise((resolve) => {
    win.requestAnimationFrame(() => {
      win.requestAnimationFrame(() => resolve({
        status: "yielded",
        strategy: "double-animation-frame",
        frameCount: 2
      }));
    });
  });
}

export function createResourceLoader(options = {}) {
  const fetchImpl = options.fetchImpl || globalThis.fetch;
  if (typeof fetchImpl !== "function") throw new Error("当前环境不支持静态数据请求");
  const cacheKey = options.cacheKey || Date.now();
  const paths = options.paths || RESOURCE_PATHS;
  const groups = options.groups || RESOURCE_GROUPS;
  const requests = new Map();
  const requestedKeys = [];

  function fetchJson(path) {
    return fetchImpl(resourceUrl(path, cacheKey), { cache: "no-store" }).then((response) => {
      if (!response || response.ok !== true) {
        throw new Error(`HTTP ${response && Number.isInteger(response.status) ? response.status : "ERROR"}`);
      }
      return response.json();
    });
  }

  function loadConfig() {
    if (!requests.has("$config")) {
      requestedKeys.push("$config");
      requests.set("$config", fetchJson("data.json"));
    }
    return requests.get("$config");
  }

  function loadSource(key) {
    if (!Object.prototype.hasOwnProperty.call(paths, key)) {
      return Promise.reject(new Error(`未知金融终端资源：${key}`));
    }
    if (!requests.has(key)) {
      requestedKeys.push(key);
      requests.set(key, fetchJson(paths[key]).then(
        (data) => ({ data, error: null }),
        (error) => ({ data: null, error: new Error(errorMessage(error)) })
      ));
    }
    return requests.get(key);
  }

  function loadGroup(name) {
    const keys = groups[name];
    if (!Array.isArray(keys)) return Promise.reject(new Error(`未知金融终端分区：${name}`));
    return Promise.all(keys.map((key) => loadSource(key))).then((values) => {
      return keys.reduce((result, key, index) => {
        result[key] = values[index];
        return result;
      }, {});
    });
  }

  function snapshot() {
    return {
      requestedKeys: requestedKeys.slice(),
      requestCount: requestedKeys.length,
      sourceRequestCount: requestedKeys.filter((key) => key !== "$config").length
    };
  }

  return { loadConfig, loadGroup, loadSource, snapshot };
}

export function createDeferredSectionScheduler(options = {}) {
  const handlers = options.handlers || {};
  const sections = options.sections || {};
  const names = Object.keys(handlers);
  const eager = options.eager === true;
  const navigationLinks = Array.from(options.navigationLinks || []);
  const Observer = Object.prototype.hasOwnProperty.call(options, "Observer")
    ? options.Observer
    : globalThis.IntersectionObserver;
  const rootMargin = options.rootMargin || "480px 0px";
  const inFlight = new Map();
  const loaded = new Set();
  let observer = null;
  const navigationListeners = [];
  let resolveAll;
  let rejectAll;
  const allLoaded = new Promise((resolve, reject) => {
    resolveAll = resolve;
    rejectAll = reject;
  });

  function notify(name, state) {
    if (typeof options.onStateChange === "function") {
      options.onStateChange({ name, state, loaded: Array.from(loaded) });
    }
  }

  function maybeComplete() {
    if (loaded.size === names.length) resolveAll(Array.from(loaded));
  }

  function load(name) {
    if (!Object.prototype.hasOwnProperty.call(handlers, name)) {
      return Promise.reject(new Error(`未知延迟加载分区：${name}`));
    }
    if (inFlight.has(name)) return inFlight.get(name);
    notify(name, "loading");
    const task = Promise.resolve().then(() => handlers[name]()).then((value) => {
      loaded.add(name);
      notify(name, "ready");
      maybeComplete();
      return value;
    }).catch((error) => {
      notify(name, "error");
      rejectAll(error);
      throw error;
    });
    inFlight.set(name, task);
    return task;
  }

  function start() {
    if (names.length === 0) {
      resolveAll([]);
      return { mode: "empty", allLoaded };
    }
    if (eager || typeof Observer !== "function") {
      Promise.all(names.map((name) => load(name))).catch(() => {});
      return { mode: "eager", allLoaded };
    }
    observer = new Observer((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        const name = names.find((candidate) => sections[candidate] === entry.target);
        if (!name) return;
        observer.unobserve(entry.target);
        load(name).catch(() => {});
      });
    }, { rootMargin });
    names.forEach((name) => {
      if (sections[name]) observer.observe(sections[name]);
      else load(name).catch(() => {});
    });
    navigationLinks.forEach((link) => {
      const name = names.find((candidate) => {
        return sections[candidate] && link.hash === `#${sections[candidate].id}`;
      });
      if (!name) return;
      const listener = () => load(name).catch(() => {});
      link.addEventListener("click", listener, { passive: true });
      navigationListeners.push([link, listener]);
    });
    return { mode: "deferred", allLoaded };
  }

  function disconnect() {
    if (observer) observer.disconnect();
    navigationListeners.forEach(([link, listener]) => link.removeEventListener("click", listener));
  }

  return { start, load, allLoaded, disconnect, loadedSections: () => Array.from(loaded) };
}

export async function startFinanceTerminal(options = {}) {
  const doc = options.document || globalThis.document;
  const win = options.window || globalThis.window;
  if (!doc || !win) throw new Error("金融终端启动器需要浏览器文档环境");
  const params = new URLSearchParams(win.location.search);
  const eager = params.get("regression") === "1" || params.get("loadAll") === "1";
  const root = doc.documentElement;
  root.setAttribute("data-critical-data-state", "loading");
  root.setAttribute("data-deferred-data-state", "idle");
  const loader = createResourceLoader(options.loaderOptions);
  const [config, sources] = await Promise.all([loader.loadConfig(), loader.loadGroup("critical")]);
  const experience = options.buildCritical(config, sources);
  options.renderCritical(experience);
  if (typeof options.announceCritical === "function") options.announceCritical(experience);
  root.setAttribute("data-critical-data-state", "ready");
  const criticalSnapshot = loader.snapshot();
  const loadState = {
    mode: eager ? "eager" : "deferred",
    criticalSourceRequestCount: criticalSnapshot.sourceRequestCount,
    requestedKeysAfterCritical: criticalSnapshot.requestedKeys,
    requestedKeys: criticalSnapshot.requestedKeys,
    sourceRequestCount: criticalSnapshot.sourceRequestCount,
    loadedSections: [],
    criticalPaintBarrier: { status: "pending", strategy: null, frameCount: null },
    startupOrder: ["critical-rendered"]
  };
  win.__financeTerminalLoadState = loadState;

  function updateLoadSnapshot(loadedSections) {
    const snapshot = loader.snapshot();
    loadState.requestedKeys = snapshot.requestedKeys;
    loadState.sourceRequestCount = snapshot.sourceRequestCount;
    loadState.loadedSections = loadedSections.slice();
  }

  const handlers = Object.keys(options.sections).reduce((result, name) => {
    result[name] = () => loader.loadGroup(name).then((group) => {
      const value = options.buildSection(name, group);
      const key = options.experienceKeys[name] || name;
      experience[key] = value;
      options.renderSection(name, value);
    }).catch((error) => {
      if (typeof options.renderSectionError === "function") options.renderSectionError(name, error);
      throw error;
    });
    return result;
  }, {});
  const scheduler = createDeferredSectionScheduler({
    eager,
    handlers,
    sections: options.sections,
    navigationLinks: options.navigationLinks,
    rootMargin: options.rootMargin,
    onStateChange(state) {
      if (state.state === "loading") root.setAttribute("data-deferred-data-state", "loading");
      if (state.state === "error") root.setAttribute("data-deferred-data-state", "error");
      if (state.state === "ready") {
        root.setAttribute("data-loaded-sections", state.loaded.join(" "));
        root.setAttribute("data-deferred-data-state", state.loaded.length === 4 ? "ready" : "partial");
      }
      updateLoadSnapshot(state.loaded);
    }
  });
  const providerReady = Promise.resolve(options.monitorProvider(experience.marketLicense));
  loadState.criticalPaintBarrier = await waitForCriticalPaint(win, options.yieldAfterCritical);
  loadState.startupOrder.push("critical-paint-yielded");
  loadState.requestedKeysAtSchedulerStart = loader.snapshot().requestedKeys;
  loadState.startupOrder.push("deferred-scheduler-started");
  scheduler.start();
  scheduler.allLoaded.then(() => {
    if (typeof options.announceComplete === "function") options.announceComplete(experience);
    updateLoadSnapshot(scheduler.loadedSections());
    root.setAttribute("data-deferred-data-state", "ready");
  }).catch(() => {
    // Each failed section exposes its own visible and machine-readable state.
  });
  if (eager) {
    await Promise.all([providerReady, scheduler.allLoaded]);
    if (typeof options.runRegression === "function") await options.runRegression();
  } else {
    providerReady.catch(() => {
      // Per-card official links remain visible when the provider runtime is unavailable.
    });
  }
  return { experience, loader, scheduler, mode: eager ? "eager" : "deferred" };
}

export const financeTerminalResourceContract = Object.freeze({
  paths: RESOURCE_PATHS,
  groups: RESOURCE_GROUPS,
  criticalSourceCount: RESOURCE_GROUPS.critical.length,
  upstreamSourceCount: 16,
  localEvidenceSourceCount: 2
});
