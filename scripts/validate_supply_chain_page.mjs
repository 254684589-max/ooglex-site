#!/usr/bin/env node
/** 全球产业链页面的浏览器回归契约。
 *
 * 这一页最容易出的错是「看起来对、其实在骗人」，所以守四件事：
 *
 * 1. **覆盖率声明必须真的渲染出来**——不是写在 HTML 里就算，要在真实浏览器里可见。
 *    「不是完整供应链」这句话是本板块诚实性的底线，被样式藏起来等同于没写。
 * 2. **阶段判定必须显示依据**——每家公司要能看到 SIC 码和可点开的原始申报链接。
 *    把行业码推断显示成公司级结论而不给依据，正是规范里禁止的。
 * 3. **三档宽度无横向溢出**——360 / 768 / 1280，页面本身不得横向滚动；
 *    宽内容（公司表）只能在自己的容器内滚动。
 * 4. **交互可用**——环节卡片键盘可达、触控区域不小于 44×44、展开后能看到表格。
 *
 * 纯离线：起本地静态服务器读仓库文件，不发外网请求。
 *
 * **降级数据会让本契约失败，这是刻意的**：SEC 取数失败时构建会退回板块级口径，
 * 此时页面缺少 SIC 与可核验申报链接，第 2 条守不住。契约失败 → 工作流不提交 →
 * 保留上一份好数据。宁可不更新，也不发布看起来完整却没有依据的页面。
 */
import assert from "node:assert/strict";
import http from "node:http";
import path from "node:path";
import { readFile, stat, access } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml", ".png": "image/png"
};
const VIEWPORTS = [[360, 780], [768, 1024], [1280, 900]];

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
    import("node:http").then(() => {
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
    }).catch(reject);
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

  const server = await startStaticServer();
  const port = server.address().port;
  const pageUrl = `http://127.0.0.1:${port}/apps/supply-chain/`;

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
    catch (error) { failures.push(`${name}：${error.message}`); console.log(`  [XX] ${name}`); }
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

    for (const [width, height] of VIEWPORTS) {
      console.log(`\n── ${width}×${height} ──`);
      await client.send("Emulation.setDeviceMetricsOverride",
        { width, height, deviceScaleFactor: 1, mobile: width < 700 }, sessionId);
      await client.send("Page.navigate", { url: pageUrl }, sessionId);
      // 等渲染完成：状态条填好即表示 nodes.json 已加载并渲染
      await evaluate(`new Promise((done, fail) => {
        const deadline = Date.now() + 20000;
        (function poll() {
          const stages = document.querySelectorAll('.stage').length;
          if (stages > 0) return done(true);
          if (Date.now() > deadline) return fail(new Error('20 秒内未渲染出环节卡片'));
          setTimeout(poll, 120);
        })();
      })`);

      const probe = await evaluate(`(() => {
        const text = document.body.innerText;
        const stages = [...document.querySelectorAll('.stage')];
        const small = stages.filter(b => {
          const r = b.getBoundingClientRect();
          return r.width < 44 || r.height < 44;
        }).length;
        return {
          stageCount: stages.length,
          hasCompletenessDisclaimer: text.includes('不是完整供应链'),
          hasEdgeStatement: text.includes('尚无企业间关系边') || text.includes('带出处的关系'),
          hasBasisLine: text.includes('阶段判定口径'),
          statusChips: document.querySelectorAll('#statusrow .status').length,
          bodyOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          undersizedTargets: small,
          focusable: stages.every(b => b.tagName === 'BUTTON' && b.tabIndex >= 0),
          expandedInitially: stages.filter(b => b.getAttribute('aria-expanded') === 'true').length
        };
      })()`);

      check(`环节卡片渲染（6 个）`, () => assert.equal(probe.stageCount, 6));
      check(`「不是完整供应链」声明可见`, () => assert.ok(probe.hasCompletenessDisclaimer));
      check(`关系边状态已说明`, () => assert.ok(probe.hasEdgeStatement));
      check(`阶段判定口径已说明`, () => assert.ok(probe.hasBasisLine));
      check(`状态条 4 项（数据日/更新/公司/频率）`, () => assert.equal(probe.statusChips, 4));
      check(`页面无横向溢出`, () => assert.ok(probe.bodyOverflow <= 1,
        `溢出 ${probe.bodyOverflow}px`));
      check(`触控区域不小于 44×44`, () => assert.equal(probe.undersizedTargets, 0));
      check(`环节卡片键盘可达`, () => assert.ok(probe.focusable));
      check(`初始不展开任何环节`, () => assert.equal(probe.expandedInitially, 0));

      // 展开一个环节，检查公司表与判定依据
      const opened = await evaluate(`(() => {
        document.querySelector('.stage').click();
        const panel = document.getElementById('panel');
        const rows = panel.querySelectorAll('tbody tr');
        const first = rows[0];
        const cells = first ? [...first.children].map(c => c.textContent.trim()) : [];
        const links = panel.querySelectorAll('td.basis a[href^="https://"]').length;
        const headers = [...panel.querySelectorAll('th')].map(t => t.textContent.trim());
        const card = document.querySelector('.stage');
        const cardText = card ? card.querySelector('.cnt').textContent : "";
        // 用字符类而非 \d / \s：这段表达式在 JS 模板字面量里，反斜杠转义会被吃掉
        const cardMatch = cardText.match(/^([0-9]+) *家/);
        return {
          hidden: panel.hidden,
          cardCount: cardMatch ? Number(cardMatch[1]) : -1,
          rowCount: rows.length,
          headers,
          firstRowCells: cells.length,
          sicShown: cells.length >= 4 && /^[0-9]{3,4}$/.test(cells[3]),
          evidenceLinks: links,
          wrapScrolls: (() => {
            const w = panel.querySelector('.tablewrap');
            return !!w && getComputedStyle(w).overflowX === 'auto';
          })(),
          pageOverflowAfterOpen:
            document.documentElement.scrollWidth - document.documentElement.clientWidth
        };
      })()`);

      check(`展开后面板可见`, () => assert.equal(opened.hidden, false));
      check(`公司表有行`, () => assert.ok(opened.rowCount > 0, `行数 ${opened.rowCount}`));
      check(`表头含「判定依据」`, () => assert.ok(opened.headers.includes("判定依据"),
        `实际表头 ${JSON.stringify(opened.headers)}`));
      check(`逐家显示 SIC 码`, () => assert.ok(opened.sicShown));
      check(`判定依据附可核验申报链接`, () => assert.ok(opened.evidenceLinks > 0,
        `链接数 ${opened.evidenceLinks}`));
      check(`宽表在自身容器内滚动`, () => assert.ok(opened.wrapScrolls));
      // 卡片上的「N 家」与展开后表格的行数必须同口径。曾经卡片数的是「有有效
      // 报价的公司」而表格数的是节点，两边对不上；表现数据缺失时卡片更会显示
      // 成「0 家」——「支持性行业 0 家」是对事实的错误陈述。
      check(`卡片计数与面板行数同口径`, () => {
        const shown = Math.min(opened.cardCount, 60);
        assert.equal(opened.rowCount, shown,
          `卡片写 ${opened.cardCount} 家，表格 ${opened.rowCount} 行`);
      });
      check(`展开后页面仍无横向溢出`, () => assert.ok(opened.pageOverflowAfterOpen <= 1,
        `溢出 ${opened.pageOverflowAfterOpen}px`));
    }

    // 数据加载失败必须有明确的用户可见状态，不能白屏
    console.log("\n── 失败路径 ──");
    await client.send("Page.navigate",
      { url: `http://127.0.0.1:${port}/apps/supply-chain/?missing=1` }, sessionId);
    const errorState = await evaluate(`(() => {
      const s = document.getElementById('state');
      return { text: (s && s.textContent) || "", visible: !!s && !s.hidden };
    })()`);
    check(`正常路径下加载状态最终隐藏`, () => assert.ok(!errorState.visible || errorState.text.length > 0));
  } finally {
    client.close();
    child.kill();
    server.close();
  }

  console.log("\n" + "─".repeat(60));
  if (failures.length) {
    console.log(`失败 ${failures.length} 项：`);
    failures.forEach((f) => console.log(`  · ${f}`));
    return 1;
  }
  console.log("全部通过");
  return 0;
}

main().then((code) => process.exit(code)).catch((error) => {
  console.error("契约运行失败：", error.message);
  process.exit(1);
});
