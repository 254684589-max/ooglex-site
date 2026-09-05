#!/usr/bin/env node
/** 全球大模型评测榜的浏览器回归契约。
 *
 * 这一页最容易出的错是**把「我们还没有可比的分」渲染成「这个模型不存在」**，或者
 * 反过来，给只有一个榜的模型编一个综合名次。两个方向都要守：
 *
 * 1. **排名区里每张卡都至少两个榜有分**——综合参考分是跨榜归一化后加权来的，
 *    只有一个榜的模型没法参与，硬排会被顶到虚高的位置。
 * 2. **单榜模型必须出现在页面上，且名次位是「—」**——给它一个编号就等于宣称它和
 *    上面的多榜模型比出了高下。它们从榜上消失同样不行：刚发布的模型必然先只被一个
 *    榜收录，静默清空的正是最该被看到的那批（2026-09-05 的 GPT-6 Astra）。
 * 3. **待补榜的分值是那一榜的原始分**——与 data.json 逐个比对，不是比对页面自己算的数。
 * 4. **三档宽度无横向溢出**——360 / 768 / 1280。
 * 5. **单榜页里单榜模型正常参与排名**——LiveBench 页按 LiveBench 分排，它该有名次。
 *
 * 纯离线：起本地静态服务器读仓库文件，不发外网请求。
 */
import assert from "node:assert/strict";
import http from "node:http";
import path from "node:path";
import { readFile, stat, access } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml", ".png": "image/png"
};
const VIEWPORTS = [[360, 780], [768, 1024], [1280, 900]];
const AXES = ["arena", "livebench", "aa"];

const axisCount = (m) => AXES.filter((k) => typeof m[k] === "number").length;

async function firstExisting(candidates) {
  for (const candidate of candidates) {
    if (!candidate) continue;
    try { await access(candidate); return candidate; } catch { /* 继续找下一个 */ }
  }
  return null;
}

function startStaticServer() {
  const server = http.createServer(async (request, response) => {
    try {
      const pathname = decodeURIComponent(new URL(request.url, "http://local").pathname);
      let target = path.resolve(ROOT, `.${pathname}`);
      if (!target.startsWith(`${ROOT}${path.sep}`)) throw new Error("invalid path");
      const meta = await stat(target).catch(() => null);
      if (meta?.isDirectory()) target = path.join(target, "index.html");
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

/* ── 最小 CDP 客户端：仓库没有前端依赖，不为一个测试引入 ── */
function connect(wsUrl) {
  return new Promise((resolve, reject) => {
    const { WebSocket } = globalThis;
    if (!WebSocket) return reject(new Error("此 Node 版本没有内置 WebSocket"));
    const socket = new WebSocket(wsUrl);
    const pending = new Map();
    let nextId = 1;
    socket.addEventListener("open", () => resolve({
      send(method, params = {}, sessionId) {
        const id = nextId++;
        return new Promise((ok, bad) => {
          pending.set(id, { ok, bad });
          socket.send(JSON.stringify({ id, method, params, sessionId }));
        });
      },
      close() { socket.close(); }
    }));
    socket.addEventListener("error", reject);
    socket.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (message.id && pending.has(message.id)) {
        const { ok, bad } = pending.get(message.id);
        pending.delete(message.id);
        message.error ? bad(new Error(message.error.message)) : ok(message.result);
      }
    });
  });
}

async function main() {
  const browserPath = await firstExisting([
    process.env.CHROME_BIN,
    "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    "/opt/pw-browsers/chromium/chrome-linux/chrome",
    "/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome"
  ]);
  if (!browserPath) {
    console.log("[跳过] 找不到 Chrome/Chromium，无法运行浏览器契约");
    return 0;
  }

  // 断言比对**数据文件**，不比对页面自己算出来的数——那样只是页面和自己一致。
  const DATA = JSON.parse(await readFile(path.join(ROOT, "apps/ai-rankings/data.json"), "utf8"));
  const singles = DATA.models.filter((m) => axisCount(m) === 1);
  const multis = DATA.models.filter((m) => axisCount(m) >= 2);
  console.log(`data.json：${DATA.models.length} 个模型（多榜 ${multis.length}，单榜 ${singles.length}）`);

  const server = await startStaticServer();
  const port = server.address().port;
  const pageUrl = `http://127.0.0.1:${port}/apps/ai-rankings/`;

  const child = spawn(browserPath, [
    "--headless=new", "--disable-gpu", "--no-sandbox", "--remote-debugging-port=0",
    "--disable-dev-shm-usage", "about:blank"
  ], { stdio: ["ignore", "ignore", "pipe"] });

  const wsUrl = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("浏览器 60 秒未就绪")), 60000);
    let buffer = "";
    child.stderr.on("data", (chunk) => {
      buffer += chunk.toString();
      const match = buffer.match(/ws:\/\/[^\s]+/);
      if (match) { clearTimeout(timer); resolve(match[0]); }
    });
    child.once("error", reject);
  });

  const failures = [];
  const check = (name, fn) => {
    try { fn(); console.log(`  [OK] ${name}`); }
    catch (error) { failures.push(`${name}：${error.message}`); console.log(`  [XX] ${name}：${error.message}`); }
  };

  const client = await connect(wsUrl);
  try {
    const { targetId } = await client.send("Target.createTarget", { url: "about:blank" });
    const { sessionId } = await client.send("Target.attachToTarget", { targetId, flatten: true });
    const evaluate = async (expression) => {
      const result = await client.send("Runtime.evaluate", {
        expression, returnByValue: true, awaitPromise: true
      }, sessionId);
      if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
      return result.result.value;
    };
    const waitForRows = () => evaluate(`new Promise((done, fail) => {
      const deadline = Date.now() + 20000;
      (function poll() {
        if (document.querySelectorAll('#list .rowcard').length > 0) return done(true);
        if (Date.now() > deadline) return fail(new Error('20 秒内未渲染出模型卡'));
        setTimeout(poll, 120);
      })();
    })`);
    // 页面上每张卡的名次、名称与主分值；名次「—」即不参与排名
    const readRows = () => evaluate(`(() => [...document.querySelectorAll('#list .rowcard')].map(c => ({
      rank: c.querySelector('.rk').textContent.trim(),
      name: c.querySelector('.nm').childNodes[0].textContent.trim(),
      tags: [...c.querySelectorAll('.tag')].map(t => t.textContent.trim()),
      score: c.querySelector('.score .big').textContent.trim(),
      lab: c.querySelector('.score .lab').textContent.trim()
    })))()`);

    for (const [width, height] of VIEWPORTS) {
      console.log(`\n── ${width}×${height} ──`);
      await client.send("Emulation.setDeviceMetricsOverride",
        { width, height, deviceScaleFactor: 1, mobile: width < 700 }, sessionId);
      await client.send("Page.navigate", { url: pageUrl }, sessionId);
      await waitForRows();

      const rows = await readRows();
      const page = await evaluate(`(() => ({
        bodyOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        sechead: (document.querySelector('#list .sechead') || {}).innerText || '',
        sectionVisible: !!(document.querySelector('#list .sechead') &&
          document.querySelector('#list .sechead').getBoundingClientRect().height > 0),
        summary: (document.getElementById('summary') || {}).innerText || '',
        pendingCards: document.querySelectorAll('#list .rowcard.pending').length
      }))()`);

      const ranked = rows.filter((r) => r.rank !== "—");
      const pending = rows.filter((r) => r.rank === "—");

      check("排名区只收多榜模型（每张卡都能在 data.json 里找到且 ≥2 榜有分）", () => {
        const bad = ranked.filter((r) => {
          const m = DATA.models.find((x) => x.name === r.name);
          return !m || axisCount(m) < 2;
        });
        assert.equal(bad.length, 0, `${bad.length} 张卡不该有名次：${bad.map((b) => b.name).join("、")}`);
      });
      check("排名区名次连续从 1 开始", () => {
        assert.deepEqual(ranked.map((r) => r.rank), ranked.map((_, i) => String(i + 1)));
      });
      check(`单榜模型全部出现在页面上（data.json 有 ${singles.length} 个）`, () => {
        assert.equal(pending.length, singles.length,
          `页面 ${pending.length} 个，数据 ${singles.length} 个`);
        assert.equal(page.pendingCards, singles.length, "待补榜卡片数与名次为「—」的卡片数不一致");
      });
      // 某天三个榜的收录恰好完全重合时单榜模型可以是 0 个，那时不该有这一区，
      // 也不该因此判失败——契约要跟着数据走，不能写死「一定有待补榜」。
      check(singles.length ? "待补榜区的说明文字真的可见" : "没有单榜模型时不出现待补榜区", () => {
        if (!singles.length) {
          assert.equal(page.sectionVisible, false, "没有单榜模型却渲染了待补榜区");
          return;
        }
        assert.ok(page.sectionVisible, "找不到或高度为 0");
        assert.ok(page.sechead.includes("不参与综合排名"), `文案是「${page.sechead.slice(0, 40)}」`);
        assert.ok(page.sechead.includes("不代表跨榜高下"), "缺少「本区排序不代表跨榜高下」的说明");
      });
      check("待补榜卡片给的是那一榜的原始分，不是编出来的综合分", () => {
        for (const r of pending) {
          const m = DATA.models.find((x) => x.name === r.name);
          assert.ok(m, `data.json 里没有「${r.name}」`);
          const key = AXES.find((k) => typeof m[k] === "number");
          const want = key === "arena" ? String(Math.round(m[key])) : m[key].toFixed(1);
          assert.equal(r.score, want, `「${r.name}」页面 ${r.score}，数据 ${want}`);
          assert.equal(r.lab, "待补榜", `「${r.name}」的分值标签是「${r.lab}」`);
          assert.ok(r.tags.some((t) => t.startsWith("仅 ")), `「${r.name}」缺「仅 X 有分」标签`);
        }
      });
      check("覆盖模型数与 data.json 一致", () => {
        assert.ok(page.summary.includes(`覆盖 ${DATA.models.length} 个模型`),
          `摘要是「${page.summary.replace(/\n/g, " / ")}」`);
      });
      check("页面无横向溢出", () => assert.ok(page.bodyOverflow <= 1, `溢出 ${page.bodyOverflow}px`));

      // 切到 LiveBench 页：单榜模型在这里按自己的分参与排名，应当拿到名次
      await evaluate(`(() => {
        const chip = [...document.querySelectorAll('#tabs .chip')]
          .find(c => c.textContent.includes('LiveBench'));
        chip.click(); return true;
      })()`);
      const lbRows = await readRows();
      const lbData = DATA.models.filter((m) => typeof m.livebench === "number")
        .sort((a, b) => b.livebench - a.livebench);
      check("LiveBench 页：单榜模型正常参与排名（有名次、按 LiveBench 分降序）", () => {
        assert.equal(lbRows.length, lbData.length, `页面 ${lbRows.length} 行，数据 ${lbData.length} 行`);
        assert.equal(lbRows.filter((r) => r.rank === "—").length, 0, "这一页不该有「—」名次");
        assert.deepEqual(lbRows.map((r) => r.name), lbData.map((m) => m.name));
      });
    }
  } finally {
    client.close();
    child.kill();
    server.close();
  }

  console.log("");
  if (failures.length) {
    console.log(`浏览器契约失败 ${failures.length} 项：`);
    failures.forEach((f) => console.log("  - " + f));
    return 1;
  }
  console.log("浏览器契约全部通过");
  return 0;
}

main().then((code) => process.exit(code)).catch((error) => {
  console.error("契约执行出错：" + error.message);
  process.exit(1);
});
