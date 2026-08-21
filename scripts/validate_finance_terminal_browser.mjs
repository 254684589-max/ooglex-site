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
const WIDTHS = [360, 768, 1280];
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
  const options = { browser: null, artifactsDir: null, height: 1400, timeout: 40 };
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

async function waitForLoadState(client, predicate, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  const expression = `JSON.stringify({
    state: window.__financeTerminalLoadState || null,
    critical: document.documentElement.getAttribute("data-critical-data-state"),
    deferred: document.documentElement.getAttribute("data-deferred-data-state"),
    informationBusy: document.getElementById("information-grid")?.getAttribute("aria-busy"),
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
    || information.state.failedSections.length !== 0
    || information.state.networkRequestCount !== 10
    || information.state.duplicateNetworkRequestCount !== 0
    || Object.values(information.state.requestStates).some((state) => state !== "ready")) {
    throw new Error(`资讯分区请求复用边界无效：${JSON.stringify(information.state)}`);
  }
  return {
    criticalSourceRequestCount: critical.state.sourceRequestCount,
    informationSourceRequestCount: information.state.sourceRequestCount,
    startupOrder: critical.state.startupOrder,
    criticalPaintBarrier: critical.state.criticalPaintBarrier,
    groupLoadSequence: information.state.groupLoadSequence,
    informationTransitions,
    duplicateNetworkRequestCount: information.state.duplicateNetworkRequestCount
  };
}

async function runWidth(client, baseUrl, artifacts, width, height, timeoutMs) {
  await client.send("Emulation.setDeviceMetricsOverride", {
    width,
    height,
    deviceScaleFactor: 1,
    mobile: false,
    screenWidth: width,
    screenHeight: height
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
    const sectionModules = await client.send("Runtime.evaluate", {
      expression: "window.__financeTerminalSectionModules || null",
      returnByValue: true
    });
    result.sectionModules = sectionModules.result.value;
    if (JSON.stringify(result.sectionModules?.requested?.slice().sort())
        !== JSON.stringify(["research", "risk"])
      || result.sectionModules?.states?.risk !== "ready"
      || result.sectionModules?.states?.research !== "ready") {
      throw new Error(`${width}px按需区块模块证据无效：${JSON.stringify(result.sectionModules)}`);
    }
    result.providerScriptTransport = scriptTransport.snapshot();
  } finally {
    scriptTransport.stop();
  }
  if (Math.abs((result.viewport?.width ?? 0) - width) > 1) {
    throw new Error(`${width}px请求得到异常视口宽度：${result.viewport?.width}`);
  }
  if (result.status !== "pass") {
    const targets = result.undersizedTargets?.length ? `；触控目标=${JSON.stringify(result.undersizedTargets)}` : "";
    throw new Error(`${width}px浏览器检查失败：${(result.failures || ["unknown"]).join(", ")}${targets}`);
  }

  const layout = await client.send("Page.getLayoutMetrics");
  const content = layout.cssContentSize || layout.contentSize;
  const screenshot = await client.send("Page.captureScreenshot", {
    format: "png",
    fromSurface: true,
    captureBeyondViewport: true,
    clip: { x: 0, y: 0, width: Math.ceil(content.width), height: Math.ceil(content.height), scale: 1 }
  });
  const screenshotPath = path.join(artifacts, `finance-terminal-${width}.png`);
  await writeFile(screenshotPath, Buffer.from(screenshot.data, "base64"));
  const screenshotStat = await stat(screenshotPath);
  if (screenshotStat.size < 1000) throw new Error(`${width}px截图文件异常`);
  result.screenshot = screenshotPath;
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
    console.log(`Deferred section loading: PASS · sources ${deferredProbe.criticalSourceRequestCount} → ${deferredProbe.informationSourceRequestCount} · groups ${deferredProbe.groupLoadSequence.join(" → ")} · duplicates ${deferredProbe.duplicateNetworkRequestCount}`);
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
      console.log(`${result.viewport.width}px: PASS · cards 8/3/3/2/4 · provider script ${script.state}/${script.reason} · proxy hosts ${mounted}/4 mounted · official trends ${result.officialObservationTrendCount}/3 · official health ${result.officialHealthPanelCount}/4 · support health ${result.supportingHealthPanelCount}/4 · V1 evidence ${result.readinessEvidencePanelCount}/4 · columns ${layout.market}/${layout.risk}/${layout.research}/${layout.information}/${layout.operations} · focusable ${result.focusableCount} · targets ${result.targetCount}`);
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
