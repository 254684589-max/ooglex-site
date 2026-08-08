#!/usr/bin/env node
/** Dependency-free Finance Terminal browser regression over Chrome DevTools Protocol. */

import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { access, mkdir, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WIDTHS = [360, 768, 1280];
const RESULT_ID = "finance-terminal-regression-result";
const MIME = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
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

  close() {
    this.socket.close();
  }
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

async function runWidth(client, baseUrl, artifacts, width, height, timeoutMs) {
  await client.send("Emulation.setDeviceMetricsOverride", {
    width,
    height,
    deviceScaleFactor: 1,
    mobile: false,
    screenWidth: width,
    screenHeight: height
  });
  const loaded = client.event("Page.loadEventFired");
  await client.send("Page.navigate", { url: `${baseUrl}/apps/finance-terminal/?regression=1&width=${width}&run=${randomUUID()}` });
  await loaded;
  const result = await waitForRegression(client, timeoutMs);
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
    await Promise.all([client.send("Page.enable"), client.send("Runtime.enable")]);
    const results = [];
    for (const width of WIDTHS) results.push(await runWidth(client, baseUrl, artifacts, width, options.height, timeoutMs));
    for (const result of results) {
      const layout = result.layout;
      console.log(`${result.viewport.width}px: PASS · cards 8/3/3/2/4 · official health ${result.officialHealthPanelCount}/3 · support health ${result.supportingHealthPanelCount}/4 · columns ${layout.market}/${layout.risk}/${layout.research}/${layout.information}/${layout.operations} · focusable ${result.focusableCount} · targets ${result.targetCount}`);
    }
    console.log(`Finance Terminal browser regression: PASS (${WIDTHS.join(", ")}px)`);
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
