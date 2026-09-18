#!/usr/bin/env node
/**
 * 模拟「不开 VPN 的大陆网络」验证 /apps/macro-radar/、/apps/supply-chain/、/apps/billionaires/ 的可用性。
 *
 * 背景：这两个页面在构建时会被注入会员校验适配器（pro-access.js / pro-rich-data.js）。
 * 适配器访问 Ooglex 自有域名的会员 API。测试仍刻意把该域名模拟成**挂住而不是
 * 快速失败** —— 一旦权限结果成为同源静态数据的前置条件，整页就只剩空壳：卡片、
 * 制度信号、页脚时间全空，连 app.js 自己的「数据加载中或暂不可用」都显示不出来
 * （它的 catch 同样在等那个永远不 settle 的 Promise）。
 *
 * 因此这里刻意用「挂住」而不是「快速失败」来拦截外域请求 —— 挂住才是最伤页面的那种。
 *
 * 五个场景：
 *   1) 访客 + 外域挂住   → 必须照常出数据，且**一次都不许**请求会员 API（访客不可能是 PRO）
 *   2) 已登录 + 外域挂住 → 允许发请求，但必须在闸门时限内降级为预览，不得无限等待
 *   3) PRO + 会员 API 可达 → 完整数据仍必须走拦截通道注入，且不出现付费墙
 *   4) 产业链页 + 外域挂住 → 同一适配器也注入该页，同样不能被会员校验卡住
 *   5) 富豪榜页 + 外域挂住 → 它用的是另一个适配器（pro-billionaires.js），同一条规矩
 *
 * 跑法（先构建 .site）：
 *   python3 scripts/pro/build_pro_datasets.py
 *   python3 scripts/pro/build_rich_previews.py
 *   python3 scripts/build_public_site.py --pro-cutover
 *   node scripts/macro-radar/verify-cn.mjs
 *
 * 退出码：0 通过 / 1 失败 / 2 本机没有 Chrome，未执行（不算通过）。
 */
import { spawn } from "node:child_process";
import { access as fsAccess, mkdtemp, readFile, rm } from "node:fs/promises";
import { constants } from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const SITE = path.join(ROOT, ".site");
const PRO_API_HOST = "pro-api.ooglex.com";
// 与 assets/pro-rich-data.js 的 ACCESS_GATE_MS 对齐，再留出渲染余量。
const ACCESS_GATE_MS = 4000;
const GUEST_BUDGET_MS = 3000;
const SUPPLY_BUDGET_MS = 6000;
const MEMBER_BUDGET_MS = ACCESS_GATE_MS + 2500;
const SENTINEL = "完整数据校验样本";

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".webp": "image/webp",
  ".jpg": "image/jpeg",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2"
};

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function resolveBrowser() {
  const candidates = [
    process.env.CHROME_BIN,
    "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser"
  ].filter(Boolean);
  for (const candidate of candidates) {
    try {
      await fsAccess(candidate, constants.X_OK);
      return candidate;
    } catch {
      // 继续找下一个
    }
  }
  return null;
}

function startStaticServer(root) {
  const server = http.createServer(async (req, res) => {
    let rel = decodeURIComponent(String(req.url || "/").split("?")[0]);
    if (rel.endsWith("/")) rel += "index.html";
    const file = path.join(root, rel);
    if (!file.startsWith(root)) {
      res.writeHead(403).end("forbidden");
      return;
    }
    try {
      const body = await readFile(file);
      res.writeHead(200, { "content-type": MIME[path.extname(file)] || "application/octet-stream" });
      res.end(body);
    } catch {
      res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      res.end("not found");
    }
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}

async function devToolsUrl(port, deadline) {
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/list`);
      const targets = await res.json();
      const page = targets.find((t) => t.type === "page" && t.webSocketDebuggerUrl);
      if (page) return page.webSocketDebuggerUrl;
    } catch {
      // DevTools 还没起来
    }
    await sleep(60);
  }
  throw new Error("Chrome 未在限定时间内提供调试目标");
}

class Cdp {
  constructor(url) {
    this.socket = new WebSocket(url);
    this.seq = 0;
    this.pending = new Map();
    this.observers = new Map();
  }

  open() {
    return new Promise((resolve, reject) => {
      this.socket.addEventListener("open", resolve, { once: true });
      this.socket.addEventListener("error", () => reject(new Error("无法连接 Chrome DevTools")), { once: true });
      this.socket.addEventListener("message", (event) => {
        const message = JSON.parse(String(event.data));
        if (message.id && this.pending.has(message.id)) {
          const entry = this.pending.get(message.id);
          this.pending.delete(message.id);
          if (message.error) entry.reject(new Error(`${entry.method}: ${message.error.message}`));
          else entry.resolve(message.result || {});
          return;
        }
        const observers = this.observers.get(message.method);
        if (observers) for (const observer of observers) observer(message.params || {});
      });
    });
  }

  send(method, params = {}) {
    const id = ++this.seq;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { method, resolve, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  on(method, observer) {
    const observers = this.observers.get(method) || new Set();
    observers.add(observer);
    this.observers.set(method, observers);
  }

  close() {
    try { this.socket.close(); } catch { /* 已关闭 */ }
  }
}

function b64(value) {
  return Buffer.from(value, "utf8").toString("base64");
}

const MACRO_PROBE = `(function () {
    var signals = document.getElementById("signals");
    var foot = document.getElementById("foot-left");
    var wall = document.getElementById("ooglex-preview-wall");
    var badge = document.getElementById("ooglex-rich-access");
    return {
      signals: signals ? signals.children.length : 0,
      regime: (document.getElementById("regime") || {}).textContent ? document.getElementById("regime").textContent.replace(/\\s+/g, " ").trim() : "",
      foot: foot ? foot.textContent.trim() : "",
      wall: !!wall,
      wallText: wall ? wall.textContent : "",
      badge: badge ? badge.textContent : ""
    };
  })()`;

// 产业链页用状态行是否填好来判断“数据到了没有”，语义与宏观页的制度信号一致。
const SUPPLY_PROBE = `(function () {
  var status = document.getElementById("statusrow");
  var wall = document.getElementById("ooglex-preview-wall");
  var badge = document.getElementById("ooglex-rich-access");
  return {
    signals: status ? status.children.length : 0,
    regime: "",
    foot: status ? status.textContent.replace(/\\s+/g, " ").trim() : "",
    wall: !!wall,
    wallText: wall ? wall.textContent : "",
    badge: badge ? badge.textContent : ""
  };
})()`;

// 富豪榜页用榜单行数判断“数据到了没有”。
const BILLIONAIRES_PROBE = `(function () {
  var list = document.getElementById("list");
  var status = document.getElementById("status");
  var wall = document.getElementById("ooglex-preview-wall");
  var badge = document.getElementById("ooglex-rich-access");
  return {
    signals: list ? list.children.length : 0,
    regime: "",
    foot: status ? status.textContent.replace(/\\s+/g, " ").trim() : "",
    wall: !!wall,
    wallText: wall ? wall.textContent : "",
    badge: badge ? badge.textContent : ""
  };
})()`;

async function probe(client, expression) {
  const result = await client.send("Runtime.evaluate", { expression, returnByValue: true });
  return result.result?.value || { signals: 0, regime: "", foot: "", wall: false, wallText: "", badge: "" };
}

async function runScenario(browserPath, base, scenario) {
  const profile = await mkdtemp(path.join(os.tmpdir(), "macro-cn-"));
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
  ], { stdio: ["ignore", "ignore", "pipe"] });

  let client = null;
  try {
    const deadline = Date.now() + 30000;
    let port = null;
    while (Date.now() < deadline && port === null) {
      try {
        const marker = await readFile(path.join(profile, "DevToolsActivePort"), "utf8");
        const first = marker.trim().split(/\r?\n/)[0];
        if (/^\d+$/.test(first)) port = Number(first);
      } catch {
        await sleep(50);
      }
    }
    if (port === null) throw new Error("Chrome 调试端口未就绪");

    client = new Cdp(await devToolsUrl(port, deadline));
    await client.open();
    await client.send("Page.enable");
    await client.send("Runtime.enable");

    const hung = new Set();
    const requested = new Set();
    client.on("Fetch.requestPaused", async (event) => {
      const url = event.request.url;
      let host = "";
      try { host = new URL(url).host; } catch { host = ""; }
      if (host) requested.add(host);

      if (url.startsWith(base) || url.startsWith("data:") || url.startsWith("blob:")) {
        await client.send("Fetch.continueRequest", { requestId: event.requestId }).catch(() => {});
        return;
      }
      const stub = scenario.stub && scenario.stub(url);
      if (stub) {
        // 带 Authorization 的跨域 GET 会先发 CORS 预检，桩必须把预检也答上，
        // 否则 fetch 直接被浏览器拒掉，测出来的就不是权限逻辑而是桩自己的坑。
        const cors = [
          { name: "access-control-allow-origin", value: "*" },
          { name: "access-control-allow-headers", value: "authorization,content-type,accept" },
          { name: "access-control-allow-methods", value: "GET,OPTIONS" }
        ];
        const preflight = event.request.method === "OPTIONS";
        await client.send("Fetch.fulfillRequest", {
          requestId: event.requestId,
          responseCode: preflight ? 204 : 200,
          responseHeaders: preflight
            ? cors
            : cors.concat([{ name: "content-type", value: "application/json; charset=utf-8" }]),
          body: preflight ? b64("") : b64(stub)
        }).catch(() => {});
        return;
      }
      // 墙的行为：挂住。既不放行也不拒绝，请求永远悬着。
      hung.add(host);
    });
    await client.send("Fetch.enable", { patterns: [{ urlPattern: "*" }] });

    if (scenario.seedSession) {
      await client.send("Page.addScriptToEvaluateOnNewDocument", {
        source: `try { localStorage.setItem("sb-nwthqkpkvbtilafqpjlf-auth-token", ${JSON.stringify(JSON.stringify({ access_token: "verify-cn-fake-token" }))}); } catch (e) {}`
      });
    }

    const started = Date.now();
    await client.send("Page.navigate", { url: base + (scenario.path || "/apps/macro-radar/") });

    let readyAt = null;
    let state = null;
    const hardStop = Date.now() + 20000;
    while (Date.now() < hardStop) {
      state = await probe(client, scenario.probe || MACRO_PROBE);
      if (readyAt === null && state.signals > 0) readyAt = Date.now() - started;
      if (readyAt !== null && (state.wall || !scenario.expectWall)) break;
      await sleep(120);
    }

    return { hung: [...hung], requested: [...requested], readyAt, state };
  } finally {
    if (client) client.close();
    browser.kill("SIGKILL");
    await rm(profile, { recursive: true, force: true }).catch(() => {});
  }
}

async function main() {
  try {
    await fsAccess(path.join(SITE, "apps/macro-radar/index.html"));
  } catch {
    console.error("未找到 .site/apps/macro-radar/index.html；请先运行 scripts/build_public_site.py --pro-cutover");
    return 1;
  }

  const browserPath = await resolveBrowser();
  if (!browserPath) {
    console.error("BROWSER_UNAVAILABLE: 未找到 Chrome 或 Chromium，未执行大陆网络验证。");
    return 2;
  }

  const fullSource = JSON.parse(await readFile(path.join(ROOT, "apps/macro-radar/data.json"), "utf8"));
  fullSource.regime = Object.assign({}, fullSource.regime, { labelZh: SENTINEL });
  const fullBundle = JSON.stringify({ mode: "full", data: fullSource });

  const server = await startStaticServer(SITE);
  const base = `http://127.0.0.1:${server.address().port}`;
  const failures = [];

  try {
    const guest = await runScenario(browserPath, base, { expectWall: true });
    console.log("\n=== 场景 1 · 访客 + 外域全部挂住（模拟不开 VPN）===");
    console.log(`  挂住的外域: ${guest.hung.join(", ") || "(无)"}`);
    console.log(`  制度信号卡片: ${guest.state.signals}　出现耗时: ${guest.readyAt === null ? "从未出现" : guest.readyAt + "ms"}`);
    console.log(`  页脚: ${guest.state.foot}　付费墙: ${guest.state.wall}　角标: ${guest.state.badge.trim()}`);
    if (guest.state.signals <= 0) failures.push("场景1：外域挂住时制度信号一张都没渲染出来（页面空壳）");
    if (guest.readyAt === null || guest.readyAt > GUEST_BUDGET_MS) {
      failures.push(`场景1：数据出现耗时 ${guest.readyAt === null ? "超时" : guest.readyAt + "ms"}，超过 ${GUEST_BUDGET_MS}ms 预算`);
    }
    if (!/\d{4}-\d{2}-\d{2}/.test(guest.state.foot)) failures.push("场景1：页脚没有数据更新时间，说明 data.json 没有加载");
    if (!guest.state.wall) failures.push("场景1：FREE 付费墙没有出现");
    if (guest.requested.includes(PRO_API_HOST)) failures.push("场景1：访客仍然请求了会员 API，未登录用户不应依赖该域名");

    const member = await runScenario(browserPath, base, { expectWall: true, seedSession: true });
    console.log("\n=== 场景 2 · 已登录 + 会员 API 挂住 ===");
    console.log(`  挂住的外域: ${member.hung.join(", ") || "(无)"}`);
    console.log(`  制度信号卡片: ${member.state.signals}　出现耗时: ${member.readyAt === null ? "从未出现" : member.readyAt + "ms"}`);
    console.log(`  页脚: ${member.state.foot}　付费墙: ${member.state.wall}`);
    if (!member.requested.includes(PRO_API_HOST)) failures.push("场景2：已登录用户没有发起会员校验请求");
    if (member.state.signals <= 0) failures.push("场景2：会员 API 挂住时页面没有降级出数据");
    if (member.readyAt === null || member.readyAt > MEMBER_BUDGET_MS) {
      failures.push(`场景2：降级耗时 ${member.readyAt === null ? "超时" : member.readyAt + "ms"}，超过 ${MEMBER_BUDGET_MS}ms 闸门预算`);
    }
    if (!member.state.wallText.includes("连不上会员服务")) failures.push("场景2：付费墙没有如实说明会员服务不可达");

    const pro = await runScenario(browserPath, base, {
      expectWall: false,
      seedSession: true,
      stub(url) {
        if (url.indexOf("/v1/access") >= 0) {
          return JSON.stringify({ product: "macro_risk", plan: "pro", access_level: "full", authenticated: true });
        }
        if (url.indexOf("/v1/data/macro_risk") >= 0) return fullBundle;
        return null;
      }
    });
    console.log("\n=== 场景 3 · PRO + 会员 API 可达 ===");
    console.log(`  制度信号卡片: ${pro.state.signals}　出现耗时: ${pro.readyAt === null ? "从未出现" : pro.readyAt + "ms"}`);
    console.log(`  角标: ${pro.state.badge.trim()}　付费墙: ${pro.state.wall}`);
    if (pro.state.signals <= 0) failures.push("场景3：PRO 用户页面没有渲染数据");
    if (!pro.state.regime.includes(SENTINEL)) failures.push("场景3：完整数据没有通过拦截通道注入（页面仍是静态预览）");
    if (pro.state.wall) failures.push("场景3：PRO 用户不应看到 FREE 付费墙");
    if (!/FULL/.test(pro.state.badge)) failures.push("场景3：角标没有显示 FULL 权限");

    // 同一个适配器也注入产业链页，那边同样不能被会员校验卡住。
    const supply = await runScenario(browserPath, base, {
      expectWall: true,
      path: "/apps/supply-chain/",
      probe: SUPPLY_PROBE
    });
    console.log("\n=== 场景 4 · 产业链页 · 访客 + 外域全部挂住 ===");
    console.log(`  状态行条目: ${supply.state.signals}　出现耗时: ${supply.readyAt === null ? "从未出现" : supply.readyAt + "ms"}`);
    console.log(`  状态行: ${supply.state.foot.slice(0, 60)}　付费墙: ${supply.state.wall}`);
    if (supply.state.signals <= 0) failures.push("场景4：产业链页在外域挂住时没有加载出数据");
    if (supply.readyAt === null || supply.readyAt > SUPPLY_BUDGET_MS) {
      failures.push(`场景4：数据出现耗时 ${supply.readyAt === null ? "超时" : supply.readyAt + "ms"}，超过 ${SUPPLY_BUDGET_MS}ms 预算`);
    }
    if (supply.requested.includes(PRO_API_HOST)) failures.push("场景4：产业链页访客仍然请求了会员 API");

    // 富豪榜页走的是另一个适配器（pro-billionaires.js），必须单独守。
    const rich = await runScenario(browserPath, base, {
      expectWall: true,
      path: "/apps/billionaires/",
      probe: BILLIONAIRES_PROBE
    });
    console.log("\n=== 场景 5 · 富豪榜页 · 访客 + 外域全部挂住 ===");
    console.log(`  榜单行数: ${rich.state.signals}　出现耗时: ${rich.readyAt === null ? "从未出现" : rich.readyAt + "ms"}`);
    console.log(`  状态: ${rich.state.foot.slice(0, 60)}　付费墙: ${rich.state.wall}　角标: ${rich.state.badge.trim()}`);
    if (rich.state.signals <= 0) failures.push("场景5：富豪榜页在外域挂住时没有加载出数据");
    if (rich.readyAt === null || rich.readyAt > GUEST_BUDGET_MS) {
      failures.push(`场景5：数据出现耗时 ${rich.readyAt === null ? "超时" : rich.readyAt + "ms"}，超过 ${GUEST_BUDGET_MS}ms 预算`);
    }
    if (!rich.state.wall) failures.push("场景5：Top 10 预览付费墙没有出现");
    if (rich.requested.includes(PRO_API_HOST)) failures.push("场景5：富豪榜页访客仍然请求了会员 API");
  } finally {
    server.close();
  }

  console.log("");
  if (failures.length) {
    for (const failure of failures) console.error("FAIL " + failure);
    return 1;
  }
  console.log("大陆网络验证通过：会员校验不再是同源静态数据的前置条件，PRO 完整数据通道不受影响。");
  return 0;
}

process.exitCode = await main();
