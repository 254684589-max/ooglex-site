#!/usr/bin/env node
/** Dependency-free Finance Terminal browser regression over Chrome DevTools Protocol. */

import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { access, mkdir, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  buildBrowserEvidence,
  classifyProviderScriptFailure,
  EXPECTED_PROVIDER_SCRIPT,
  renderBrowserEvidenceSummary
} from "./finance_terminal_browser_evidence.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WIDTHS = [360, 768, 1280, 1672, 2048];
const RESULT_ID = "finance-terminal-regression-result";
const CRITICAL_REQUEST_KEYS = [
  "$config", "macro", "macroHealth", "assetRanking", "assetRankingHealth", "marketLicense"
];
const MIME = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml"
};

function parseArgs(argv) {
  const options = { browser: null, artifactsDir: null, height: 925, timeout: 40 };
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (key === "--help" || key === "-h") {
      console.log("Usage: node scripts/validate_finance_terminal_browser.mjs [--browser PATH] [--artifacts-dir DIR] [--height PX] [--timeout SEC]");
      process.exit(0);
    }
    if (!["--browser", "--artifacts-dir", "--height", "--timeout"].includes(key) || index + 1 >= argv.length) {
      throw new Error(`未知或缺少值的参数：${key}`);
    }
    const value = argv[index + 1];
    index += 1;
    if (key === "--browser") options.browser = value;
    if (key === "--artifacts-dir") options.artifactsDir = value;
    if (key === "--height") options.height = Number(value);
    if (key === "--timeout") options.timeout = Number(value);
  }
  if (!Number.isInteger(options.height) || options.height < 800) throw new Error("height必须是至少800的整数");
  if (!Number.isFinite(options.timeout) || options.timeout < 5) throw new Error("timeout必须至少为5秒");
  return options;
}

async function executable(pathname) {
  if (!pathname) return null;
  try {
    await access(pathname, 1);
    return path.resolve(pathname);
  } catch {
    const found = spawnSync("which", [pathname], { encoding: "utf8" });
    return found.status === 0 && found.stdout.trim() ? found.stdout.trim() : null;
  }
}

async function resolveBrowser(requested) {
  const candidates = [requested, process.env.CHROME_BIN, "google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "chrome"];
  for (const candidate of candidates) {
    const resolved = await executable(candidate);
    if (resolved) return resolved;
  }
  return null;
}

function withTimeout(promise, milliseconds, label) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`${label}超过${Math.round(milliseconds / 1000)}秒未完成`)), milliseconds);
    })
  ]).finally(() => clearTimeout(timer));
}

function startStaticServer() {
  const server = http.createServer(async (request, response) => {
    try {
      const pathname = decodeURIComponent(new URL(request.url, "http://local").pathname);
      let target = path.resolve(ROOT, `.${pathname}`);
      if (!target.startsWith(`${ROOT}${path.sep}`)) throw new Error("invalid path");
      const metadata = await stat(target).catch(() => null);
      if (metadata?.isDirectory()) target = path.join(target, "index.html");
      const body = await readFile(target);
      response.writeHead(200, {
        "Cache-Control": "no-store",
        "Content-Type": MIME[path.extname(target)] || "application/octet-stream"
      });
      response.end(body);
    } catch {
      response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      response.end("not found");
    }
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}

async function waitForDevTools(profile, browser, logs, timeoutMs) {
  const marker = path.join(profile, "DevToolsActivePort");
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (browser.exitCode !== null) throw new Error(`Chrome提前退出（${browser.exitCode}）：${logs.value.slice(-1600)}`);
    try {
      const lines = (await readFile(marker, "utf8")).trim().split(/\r?\n/);
      if (/^\d+$/.test(lines[0])) return Number(lines[0]);
    } catch {
      // Chrome has not created the marker yet.
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`Chrome调试端口未在限定时间内就绪：${logs.value.slice(-1600)}`);
}

async function pageWebSocket(port, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let createAttempted = false;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/list`);
      const targets = await response.json();
      const page = targets.find((target) => target.type === "page" && target.webSocketDebuggerUrl);
      if (page) return page.webSocketDebuggerUrl;
      if (!createAttempted) {
        createAttempted = true;
        const createdResponse = await fetch(`http://127.0.0.1:${port}/json/new?about%3Ablank`, { method: "PUT" });
        if (createdResponse.ok) {
          const created = await createdResponse.json();
          if (created.type === "page" && created.webSocketDebuggerUrl) return created.webSocketDebuggerUrl;
        }
      }
    } catch {
      // DevTools HTTP endpoint is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error("Chrome未提供可用页面调试目标");
}

class CdpClient {
  constructor(url, timeoutMs) {
    this.socket = new WebSocket(url);
    this.timeoutMs = timeoutMs;
    this.sequence = 0;
    this.pending = new Map();
    this.waiters = new Map();
    this.observers = new Map();
  }

  async open() {
    await withTimeout(new Promise((resolve, reject) => {
      this.socket.addEventListener("open", resolve, { once: true });
      this.socket.addEventListener("error", () => reject(new Error("无法连接Chrome DevTools WebSocket")), { once: true });
    }), this.timeoutMs, "连接Chrome DevTools");
    this.socket.addEventListener("message", (event) => this.onMessage(event.data));
    this.socket.addEventListener("close", () => {
      for (const pending of this.pending.values()) pending.reject(new Error("Chrome DevTools连接已关闭"));
      this.pending.clear();
    });
  }

  onMessage(raw) {
    const message = JSON.parse(String(raw));
    if (message.id && this.pending.has(message.id)) {
      const pending = this.pending.get(message.id);
      this.pending.delete(message.id);
      if (message.error) pending.reject(new Error(`${pending.method}: ${message.error.message}`));
      else pending.resolve(message.result || {});
      return;
    }
    if (message.method && this.waiters.has(message.method)) {
      const waiter = this.waiters.get(message.method).shift();
      if (!this.waiters.get(message.method).length) this.waiters.delete(message.method);
      waiter(message.params || {});
    }
    if (message.method && this.observers.has(message.method)) {
      for (const observer of this.observers.get(message.method)) observer(message.params || {});
    }
  }

  send(method, params = {}) {
    const id = ++this.sequence;
    return withTimeout(new Promise((resolve, reject) => {
      this.pending.set(id, { method, resolve, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    }), this.timeoutMs, method);
  }

  event(method) {
    return withTimeout(new Promise((resolve) => {
      const waiters = this.waiters.get(method) || [];
      waiters.push(resolve);
      this.waiters.set(method, waiters);
    }), this.timeoutMs, method);
  }

  subscribe(method, observer) {
    const observers = this.observers.get(method) || new Set();
    observers.add(observer);
    this.observers.set(method, observers);
    return () => {
      observers.delete(observer);
      if (!observers.size) this.observers.delete(method);
    };
  }

  close() {
    this.socket.close();
  }
}

function trackProviderScriptTransport(client) {
  const requestIds = new Set();
  let transport = {
    url: EXPECTED_PROVIDER_SCRIPT,
    state: "not-observed",
    reason: "not-requested",
    httpStatus: null,
    fromCache: null,
    failureCategory: null
  };
  const subscriptions = [
    client.subscribe("Network.requestWillBeSent", (event) => {
      if (event.type !== "Script" || event.request?.url !== EXPECTED_PROVIDER_SCRIPT) return;
      requestIds.add(event.requestId);
      transport = {
        url: EXPECTED_PROVIDER_SCRIPT,
        state: "pending",
        reason: "response-pending",
        httpStatus: null,
        fromCache: false,
        failureCategory: null
      };
    }),
    client.subscribe("Network.requestServedFromCache", (event) => {
      if (requestIds.has(event.requestId) && transport.state === "pending") transport.fromCache = true;
    }),
    client.subscribe("Network.responseReceived", (event) => {
      if (!requestIds.has(event.requestId) || event.response?.url !== EXPECTED_PROVIDER_SCRIPT) return;
      const status = Math.round(Number(event.response.status));
      const fromCache = Boolean(event.response.fromDiskCache
        || event.response.fromServiceWorker || event.response.fromPrefetchCache || transport.fromCache);
      transport = {
        url: EXPECTED_PROVIDER_SCRIPT,
        state: status >= 200 && status < 400 ? "loaded" : "failed",
        reason: status >= 200 && status < 400 ? "response-ok" : "http-error",
        httpStatus: status,
        fromCache,
        failureCategory: null
      };
    }),
    client.subscribe("Network.loadingFailed", (event) => {
      if (!requestIds.has(event.requestId)) return;
      transport = {
        url: EXPECTED_PROVIDER_SCRIPT,
        state: "failed",
        reason: event.blockedReason ? "request-blocked" : "loading-failed",
        httpStatus: null,
        fromCache: null,
        failureCategory: classifyProviderScriptFailure(event)
      };
    })
  ];
  return {
    snapshot() {
      return { ...transport };
    },
    stop() {
      subscriptions.forEach((unsubscribe) => unsubscribe());
    }
  };
}

async function waitForRegression(client, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  const expression = `document.getElementById(${JSON.stringify(RESULT_ID)})?.textContent || ""`;
  while (Date.now() < deadline) {
    const evaluation = await client.send("Runtime.evaluate", { expression, returnByValue: true });
    const payload = evaluation.result?.value;
    if (typeof payload === "string" && payload.trim()) return JSON.parse(payload);
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error("页面未在限定时间内生成浏览器回归结果");
}

async function readLoadSnapshot(client) {
  return waitForLoadState(client, () => true, 5000);
}

async function waitForLoadState(client, predicate, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  const expression = `JSON.stringify({
    state: window.__financeTerminalLoadState || null,
    critical: document.documentElement.getAttribute("data-critical-data-state"),
    deferred: document.documentElement.getAttribute("data-deferred-data-state"),
    informationBusy: document.getElementById("information-grid")?.getAttribute("aria-busy"),
    operationsBusy: document.getElementById("operations-grid")?.getAttribute("aria-busy"),
    modules: window.__financeTerminalSectionModules || null,
    error: document.querySelector(".load-error")?.textContent || null
  })`;
  while (Date.now() < deadline) {
    const evaluation = await client.send("Runtime.evaluate", { expression, returnByValue: true });
    const payload = evaluation.result?.value;
    if (typeof payload === "string") {
      const snapshot = JSON.parse(payload);
      if (snapshot.critical === "error") {
        throw new Error(`金融终端首屏启动失败：${snapshot.error || "unknown"}`);
      }
      if (predicate(snapshot)) return snapshot;
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error("页面未在限定时间内达到分区加载状态");
}

async function validateDesktopViews(client, width) {
  if (width <= 1040) return [];
  const evaluation = await client.send("Runtime.evaluate", {
    expression: `(async () => {
      const views = ["market", "board", "risk", "research", "information", "operations", "method"];
      const evidence = [];
      for (const view of views) {
        document.querySelector('.section-nav a[href="#' + view + '-section"]')?.click();
        await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        const target = document.getElementById(view + "-section");
        evidence.push({
          view,
          active: document.body.dataset.terminalView,
          current: document.querySelector('.section-nav a[aria-current="page"]')?.hash,
          visible: getComputedStyle(target).display !== "none" && target.getBoundingClientRect().height > 0
        });
      }
      document.querySelector('.section-nav a[href="#overview-section"]')?.click();
      return evidence;
    })()`,
    awaitPromise: true,
    returnByValue: true
  });
  const evidence = evaluation.result?.value || [];
  if (evidence.length !== 7 || evidence.some((item) => {
    return item.active !== item.view || item.current !== `#${item.view}-section` || !item.visible;
  })) {
    throw new Error(`${width}px桌面分区切换失败：${JSON.stringify(evidence)}`);
  }
  return evidence;
}

async function validateDeferredLoading(client, baseUrl, timeoutMs) {
  await client.send("Emulation.setDeviceMetricsOverride", {
    width: 360,
    height: 640,
    deviceScaleFactor: 1,
    mobile: false,
    screenWidth: 360,
    screenHeight: 640
  });
  const loaded = client.event("Page.loadEventFired");
  await client.send("Page.navigate", {
    url: `${baseUrl}/apps/finance-terminal/?deferredProbe=1&run=${randomUUID()}`
  });
  await loaded;
  const critical = await waitForLoadState(client, (snapshot) => {
    return snapshot.critical === "ready"
      && snapshot.state?.criticalSourceRequestCount === 5
      && snapshot.state?.criticalPaintBarrier?.status === "yielded"
      && snapshot.state?.startupOrder?.at(-1) === "deferred-scheduler-started";
  }, timeoutMs);
  if (critical.state.mode !== "deferred" || critical.state.sourceRequestCount !== 5
    || critical.state.requestCount !== 6
    || critical.state.loadedSections.length !== 0
    || JSON.stringify(critical.state.startupOrder) !== JSON.stringify([
      "critical-rendered", "critical-paint-yielded", "deferred-scheduler-started"
    ])
    || JSON.stringify(critical.state.requestedKeysAfterCritical) !== JSON.stringify(CRITICAL_REQUEST_KEYS)
    || JSON.stringify(critical.state.requestedKeysAtSchedulerStart) !== JSON.stringify(CRITICAL_REQUEST_KEYS)
    || JSON.stringify(critical.state.groupLoadSequence) !== JSON.stringify(["critical"])
    || critical.modules?.requested?.length !== 0
    || Object.values(critical.modules?.states || {}).some((state) => state !== "idle")
    || critical.state.networkRequestCount !== 6
    || critical.state.duplicateNetworkRequestCount !== 0
    || Object.values(critical.state.requestStates).some((state) => state !== "ready")) {
    throw new Error(`首屏延迟加载边界无效：${JSON.stringify(critical.state)}`);
  }
  await client.send("Runtime.evaluate", {
    expression: `document.querySelector('.section-nav a[href="#information-section"]')?.click()`
  });
  const information = await waitForLoadState(client, (snapshot) => {
    return snapshot.state?.loadedSections?.includes("information")
      && snapshot.informationBusy === "false";
  }, timeoutMs);
  const informationTransitions = information.state.sectionTransitions
    .filter((item) => item.name === "information").map((item) => item.state);
  if (information.state.sourceRequestCount !== 9
    || information.state.requestCount !== 10
    || JSON.stringify(information.state.groupLoadSequence) !== JSON.stringify(["critical", "information"])
    || JSON.stringify(informationTransitions) !== JSON.stringify(["loading", "ready"])
    || JSON.stringify(information.modules?.requested) !== JSON.stringify(["information"])
    || information.modules?.states?.information !== "ready"
    || information.modules?.states?.risk !== "idle"
    || information.modules?.states?.research !== "idle"
    || information.modules?.states?.operations !== "idle"
    || information.state.failedSections.length !== 0
    || information.state.networkRequestCount !== 10
    || information.state.duplicateNetworkRequestCount !== 0
    || Object.values(information.state.requestStates).some((state) => state !== "ready")) {
    throw new Error(`资讯分区请求复用边界无效：${JSON.stringify(information.state)}`);
  }
  await client.send("Runtime.evaluate", {
    expression: `document.querySelector('.section-nav a[href="#operations-section"]')?.click()`
  });
  const operations = await waitForLoadState(client, (snapshot) => {
    return snapshot.state?.loadedSections?.includes("operations")
      && snapshot.operationsBusy === "false";
  }, timeoutMs);
  const operationsTransitions = operations.state.sectionTransitions
    .filter((item) => item.name === "operations").map((item) => item.state);
  if (operations.state.sourceRequestCount !== 14
    || operations.state.requestCount !== 15
    || JSON.stringify(operations.state.groupLoadSequence)
      !== JSON.stringify(["critical", "information", "operations"])
    || JSON.stringify(operationsTransitions) !== JSON.stringify(["loading", "ready"])
    || JSON.stringify(operations.modules?.requested) !== JSON.stringify(["information", "operations"])
    || operations.modules?.states?.operations !== "ready"
    || operations.modules?.states?.risk !== "idle"
    || operations.modules?.states?.research !== "idle"
    || operations.state.failedSections.length !== 0
    || operations.state.networkRequestCount !== 15
    || operations.state.duplicateNetworkRequestCount !== 0
    || Object.values(operations.state.requestStates).some((state) => state !== "ready")) {
    throw new Error(`运行证据分区请求复用边界无效：${JSON.stringify(operations.state)}`);
  }
  /* 上面三段的快照都取在「该分区刚就绪」那一刻，而锚点跳转是平滑滚动，取样时
     动画往往还没走完。沿途分区在视野里掠过约两百毫秒，掠过即加载的话整页请求
     会被一并拉起——这一点只有等动画停稳后再看一次才验得出来，此前三段断言都是
     抢在动画前面取样才侥幸通过的。 */
  await new Promise((resolve) => setTimeout(resolve, 2500));
  const settled = await readLoadSnapshot(client);
  /* 工程/运营向明细在窄屏默认折叠后长页明显变短，跳到底部的运行证据时，
     市场状态可能确实停在视野边缘，那时加载它是对的。真正要守住的仍是
     「一路掠过不算看过」：品类行情板在页面中段，平滑滚动整段经过它，
     停稳后它必须还是 idle。 */
  if (settled.modules?.states?.board !== "idle") {
    throw new Error(`分区跳转滚动停稳后越界加载品类行情板：${JSON.stringify(settled.modules)}`);
  }
  /* 反过来的一面同样要成立：窄屏下 #risk-section 在四千像素之下，访客若停在
     首屏雷达前，雷达必须自己把风险数据取回来，不能一直空着。 */
  await client.send("Runtime.evaluate", {
    expression: `document.querySelector('.risk-radar-panel')?.scrollIntoView({ block: "center" })`
  });
  const dwelled = await waitForLoadState(client, (snapshot) => {
    return snapshot.modules?.states?.risk === "ready";
  }, timeoutMs);
  if (!dwelled.state.loadedSections.includes("risk")
    || dwelled.state.duplicateNetworkRequestCount !== 0) {
    throw new Error(`首屏雷达停留未取回风险数据：${JSON.stringify(dwelled.state)}`);
  }
  return {
    criticalSourceRequestCount: critical.state.sourceRequestCount,
    informationSourceRequestCount: information.state.sourceRequestCount,
    operationsSourceRequestCount: operations.state.sourceRequestCount,
    startupOrder: critical.state.startupOrder,
    criticalPaintBarrier: critical.state.criticalPaintBarrier,
    groupLoadSequence: operations.state.groupLoadSequence,
    informationTransitions,
    operationsTransitions,
    duplicateNetworkRequestCount: operations.state.duplicateNetworkRequestCount
  };
}

async function runWidth(client, baseUrl, artifacts, width, height, timeoutMs) {
  const viewportHeight = width === 1672 ? 941 : width === 2048 ? 1219 : height;
  await client.send("Emulation.setDeviceMetricsOverride", {
    width,
    height: viewportHeight,
    deviceScaleFactor: 1,
    mobile: false,
    screenWidth: width,
    screenHeight: viewportHeight
  });
  const scriptTransport = trackProviderScriptTransport(client);
  let result;
  try {
    const loaded = client.event("Page.loadEventFired");
    await client.send("Page.navigate", {
      url: `${baseUrl}/apps/finance-terminal/?regression=1&runtimeEvidence=1&width=${width}&run=${randomUUID()}`
    });
    await loaded;
    result = await waitForRegression(client, timeoutMs);
    result.desktopViewEvidence = await validateDesktopViews(client, width);
    const sectionModules = await client.send("Runtime.evaluate", {
      expression: "window.__financeTerminalSectionModules || null",
      returnByValue: true
    });
    result.sectionModules = sectionModules.result.value;
    if (JSON.stringify(result.sectionModules?.requested?.slice().sort())
        !== JSON.stringify(["board", "information", "operations", "research", "risk"])
      || result.sectionModules?.states?.board !== "ready"
      || result.sectionModules?.states?.risk !== "ready"
      || result.sectionModules?.states?.research !== "ready"
      || result.sectionModules?.states?.information !== "ready"
      || result.sectionModules?.states?.operations !== "ready") {
      throw new Error(`${width}px按需区块模块证据无效：${JSON.stringify(result.sectionModules)}`);
    }
    /* 点阵世界地图曾因 onload 回调里的残留常量静默抛错：页面不报任何错，
       只是回落到被拉伸的降级贴图，看起来"有点糊"而已，三档检查全绿。
       这里锁住不变式——区域明细已渲染出行，点阵画布就必须真的画出来。 */
    const heatmap = await client.send("Runtime.evaluate", {
      expression: `(() => {
        const rows = document.querySelectorAll("#risk-region-list .risk-region-row").length;
        const canvas = document.getElementById("risk-map-canvas");
        const ready = Boolean(document.querySelector(".risk-map-figure.risk-map-canvas-ready"));
        let painted = 0;
        try {
          const data = canvas.getContext("2d")
            .getImageData(0, 0, canvas.width, canvas.height).data;
          for (let i = 3; i < data.length; i += 4) if (data[i] > 8) painted += 1;
        } catch (error) { painted = -1; }
        return { rows, ready, painted, width: canvas?.width ?? 0, height: canvas?.height ?? 0 };
      })()`,
      returnByValue: true
    });
    result.heatmapCanvas = heatmap.result.value;
    if (result.heatmapCanvas?.rows > 0
      && (!result.heatmapCanvas.ready || result.heatmapCanvas.painted < 1000)) {
      throw new Error(`${width}px点阵世界地图未真正绘制：`
        + `${JSON.stringify(result.heatmapCanvas)}（区域明细已有数据，画布却是空的或未就绪，`
        + `通常意味着绘制回调抛错后静默回落到降级贴图）`);
    }
    /* 单屏总览把每个分区压进一格并 overflow:hidden。分区自己能缩到 0，分区里
       那一层却是网格项、min-width 默认 auto，撑到 min-content 后整块被裁掉——
       没有报错、没有横向滚动条，只是内容从边界起消失。曾因此在总览里裁掉
       OFR金融压力卡片的 137px 与运行证据面板的 201px。 */
    const clipped = await client.send("Runtime.evaluate", {
      expression: `(() => {
        if (document.body.dataset.terminalView !== "overview") return [];
        const out = [];
        document.querySelectorAll("#main-content > section").forEach((section) => {
          if (getComputedStyle(section).overflow !== "hidden") return;
          const box = section.getBoundingClientRect();
          section.querySelectorAll("*").forEach((node) => {
            const rect = node.getBoundingClientRect();
            if (rect.width < 8 || rect.height < 8) return;
            if (rect.top >= box.bottom - 2 || rect.bottom <= box.top + 2) return;
            const over = Math.round(rect.right - box.right);
            if (over > 1) out.push({ section: section.id, over,
              node: node.tagName.toLowerCase() + "." + String(node.className || "").split(" ")[0] });
          });
        });
        return out.slice(0, 8);
      })()`,
      returnByValue: true
    });
    result.overviewClippedNodes = clipped.result.value || [];
    if (result.overviewClippedNodes.length) {
      throw new Error(`${width}px总览分区把可见内容裁在边界外：`
        + `${JSON.stringify(result.overviewClippedNodes)}`);
    }
    result.providerScriptTransport = scriptTransport.snapshot();
  } finally {
    scriptTransport.stop();
  }
  if (Math.abs((result.viewport?.width ?? 0) - width) > 1) {
    throw new Error(`${width}px请求得到异常视口宽度：${result.viewport?.width}`);
  }
  const layout = await client.send("Page.getLayoutMetrics");
  const content = layout.cssContentSize || layout.contentSize;
  const capture = width === 1672 || width === 2048
    ? { width, height: viewportHeight }
    : { width: Math.ceil(content.width), height: Math.ceil(content.height) };
  const screenshot = await client.send("Page.captureScreenshot", {
    format: "png",
    fromSurface: true,
    captureBeyondViewport: true,
    clip: { x: 0, y: 0, width: capture.width, height: capture.height, scale: 1 }
  });
  const screenshotPath = path.join(artifacts, `finance-terminal-${width}.png`);
  await writeFile(screenshotPath, Buffer.from(screenshot.data, "base64"));
  const screenshotStat = await stat(screenshotPath);
  if (screenshotStat.size < 1000) throw new Error(`${width}px截图文件异常`);
  result.screenshot = screenshotPath;
  if (result.status !== "pass") {
    const targets = result.undersizedTargets?.length ? `；触控目标=${JSON.stringify(result.undersizedTargets)}` : "";
    const boundary = `；视口=${result.viewport?.width ?? "?"}，文档宽度=${result.scrollWidth ?? "?"}`;
    const overflow = result.overflowCandidates?.length ? `；越界元素=${JSON.stringify(result.overflowCandidates)}` : "";
    const cardBoxes = result.overviewCardBoxes?.length
      ? `；资产主值盒=${JSON.stringify(result.overviewCardBoxes)}` : "";
    throw new Error(`${width}px浏览器检查失败：${(result.failures || ["unknown"]).join(", ")}${boundary}${targets}${overflow}${cardBoxes}`);
  }
  return result;
}

async function stopBrowser(browser) {
  if (!browser || browser.exitCode !== null) return;
  browser.kill("SIGTERM");
  await Promise.race([
    new Promise((resolve) => browser.once("exit", resolve)),
    new Promise((resolve) => setTimeout(resolve, 1000))
  ]);
  if (browser.exitCode === null) browser.kill("SIGKILL");
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const browserPath = await resolveBrowser(options.browser);
  if (!browserPath) {
    console.error("BROWSER_UNAVAILABLE: 未找到Chrome或Chromium；未执行真实浏览器回归。");
    return 2;
  }
  const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "finance-terminal-browser-"));
  const artifacts = options.artifactsDir ? path.resolve(options.artifactsDir) : path.join(temporaryRoot, "artifacts");
  const profile = path.join(temporaryRoot, "profile");
  const cache = path.join(temporaryRoot, "cache");
  await Promise.all([mkdir(artifacts, { recursive: true }), mkdir(profile, { recursive: true }), mkdir(cache, { recursive: true })]);

  const server = await startStaticServer();
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  const logs = { value: "" };
  const browser = spawn(browserPath, [
    "--headless=new",
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--disable-background-networking",
    "--disable-extensions",
    "--no-first-run",
    "--remote-allow-origins=*",
    "--remote-debugging-port=0",
    `--user-data-dir=${profile}`,
    "about:blank"
  ], {
    cwd: ROOT,
    env: { ...process.env, XDG_CACHE_HOME: cache },
    stdio: ["ignore", "ignore", "pipe"]
  });
  browser.stderr.on("data", (chunk) => {
    logs.value = (logs.value + chunk.toString()).slice(-6000);
  });
  browser.once("exit", (code, signal) => {
    if (code !== 0 && code !== null) {
      logs.value = `${logs.value}\nChrome exited with code ${code}${signal ? ` (${signal})` : ""}`.slice(-6000);
    }
  });

  let client;
  try {
    const timeoutMs = options.timeout * 1000;
    const port = await waitForDevTools(profile, browser, logs, timeoutMs);
    client = new CdpClient(await pageWebSocket(port, timeoutMs), timeoutMs);
    client.socket.addEventListener("close", () => {
      if (browser.exitCode !== null && logs.value.trim()) console.error(logs.value.trim());
    }, { once: true });
    await client.open();
    await Promise.all([client.send("Page.enable"), client.send("Runtime.enable"), client.send("Network.enable")]);
    const deferredProbe = await validateDeferredLoading(client, baseUrl, timeoutMs);
    console.log(`Deferred section loading: PASS · sources ${deferredProbe.criticalSourceRequestCount} → ${deferredProbe.informationSourceRequestCount} → ${deferredProbe.operationsSourceRequestCount} · groups ${deferredProbe.groupLoadSequence.join(" → ")} · duplicates ${deferredProbe.duplicateNetworkRequestCount}`);
    const results = [];
    for (const width of WIDTHS) results.push(await runWidth(client, baseUrl, artifacts, width, options.height, timeoutMs));
    const evidence = buildBrowserEvidence(results);
    const evidencePath = path.join(artifacts, "finance-terminal-browser-evidence.json");
    await writeFile(evidencePath, `${JSON.stringify(evidence, null, 2)}\n`);
    const evidenceSummaryPath = path.join(artifacts, "finance-terminal-browser-evidence.md");
    await writeFile(evidenceSummaryPath, renderBrowserEvidenceSummary(evidence));
    for (const result of results) {
      const layout = result.layout;
      const mounted = result.providerWidgetRuntimeEvidence.filter((item) => item.state === "mounted").length;
      const script = result.providerScriptTransport;
      const proxyHosts = result.providerWidgetRuntimeEvidence.length;
      console.log(`${result.viewport.width}px: PASS · cards ${result.assetCardCount}/3/3/2/4 · provider script ${script.state}/${script.reason} · proxy hosts ${mounted}/${proxyHosts} mounted · official trends ${result.officialObservationTrendCount}/3 · official health ${result.officialHealthPanelCount}/4 · support health ${result.supportingHealthPanelCount}/4 · V1 evidence ${result.readinessEvidencePanelCount}/4 · columns ${layout.market}/${layout.risk}/${layout.research}/${layout.information}/${layout.operations} · focusable ${result.focusableCount} · targets ${result.targetCount}`);
    }
    console.log(`Finance Terminal browser regression: PASS (${WIDTHS.join(", ")}px)`);
    console.log(`Proxy runtime evidence: ${evidence.summary.mountedObservations}/${evidence.summary.observationCount} mounted observations; ${evidence.summary.fallbackObservations} official-link fallbacks`);
    console.log(`Proxy diagnosis: ${JSON.stringify(evidence.summary.diagnosisCounts)}`);
    if (options.artifactsDir) console.log(`Screenshots: ${artifacts}`);
    return 0;
  } finally {
    client?.close();
    await stopBrowser(browser);
    await new Promise((resolve) => server.close(resolve));
    if (!options.artifactsDir) await rm(temporaryRoot, { recursive: true, force: true });
  }
}

main().then((code) => process.exitCode = code).catch((error) => {
  console.error(error.stack || error.message || String(error));
  process.exitCode = 1;
});
