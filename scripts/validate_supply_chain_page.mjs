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

  // 页面上按板块印的家数拿这份数据对照。断言必须比对**数据文件**，
  // 不能比对页面自己算出来的数——那样只是页面和自己一致。
  const NODES = JSON.parse(await readFile(
    path.join(ROOT, "apps/supply-chain/nodes.json"), "utf8"));
  const SECTORS = (NODES.coverage && NODES.coverage.bySector) || [];

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
    /* 未捕获异常的总闸。**这一条要防的不是某个功能，是「整块没渲染出来」。**
       本轮删掉一个变量声明却留下两处使用，ReferenceError 在 fetch().then()
       链里抛出——浏览器把它当成 unhandled rejection 咽掉，页面只是少了方法区
       和后面所有收尾，而 15 条断言各自报「内容不对」，没有一条指出真正原因，
       排查花的时间比修复长得多。
       监听器必须在**页面脚本之前**注入，navigate 之后再 evaluate 就晚了。 */
    await client.send("Page.addScriptToEvaluateOnNewDocument", {
      source: "window.__pageErrors = [];"
        + "addEventListener('error', function (e) {"
        + "  window.__pageErrors.push('error: ' + (e.message || e.type)); });"
        + "addEventListener('unhandledrejection', function (e) {"
        + "  var r = e.reason; window.__pageErrors.push("
        + "    'unhandledrejection: ' + ((r && (r.stack || r.message)) || String(r))); });"
    }, sessionId);
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
          const stages = document.querySelectorAll('.band').length;
          if (stages > 0) return done(true);
          if (Date.now() > deadline) return fail(new Error('20 秒内未渲染出环节卡片'));
          setTimeout(poll, 120);
        })();
      })`);

      const probe = await evaluate(`(() => {
        const text = document.body.innerText;
        const stages = [...document.querySelectorAll('.bandhd')];
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
          bandCov: [...document.querySelectorAll('#chain .band, #offchain .band')]
            .map(b => {
              // why 读的是 title（hover 提示），**手机上根本读不到**；
              // whyText 读的是 .bandwhy，那才是读者真看得见的字。
              // 两个都收：断言要能分出「写了但看不见」和「压根没写」。
              const w = b.querySelector('.bandwhy');
              return { stage: b.dataset.stage,
                       text: ((b.querySelector('.bandcov') || {}).textContent || ''),
                       why: ((b.querySelector('.bandcov') || {}).title || ''),
                       whyText: w ? w.textContent.trim() : '',
                       whyShown: !!(w && w.offsetHeight > 0
                         && getComputedStyle(w).visibility !== 'hidden') };
            }),
          covSum: (document.getElementById('cov-sum') || {}).textContent || '',
          covSumShown: (() => {
            const e = document.getElementById('cov-sum');
            return !!(e && e.offsetHeight > 0
              && getComputedStyle(e).visibility !== 'hidden');
          })(),
          statusText: (document.getElementById('statusrow') || {}).textContent || "",
          subtitle: (document.getElementById('subtitle') || {}).textContent || "",
          freqStruck: (() => {
            const e = document.querySelector('#statusrow .freq s');
            if (!e) return false;
            const d = getComputedStyle(e).textDecorationLine || '';
            return d.indexOf('line-through') >= 0;
          })(),
          bodyOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          undersizedTargets: small,
          focusable: stages.every(b => b.tagName === 'BUTTON' && b.tabIndex >= 0),
          expandedInitially: stages.filter(b => b.getAttribute('aria-expanded') === 'true').length
        };
      })()`);

      check(`环节带数与环节表一致`, () => assert.equal(
        probe.stageCount, NODES.stages.length,
        `页面 ${probe.stageCount} 条，环节表 ${NODES.stages.length} 段`));
      check(`「不是完整供应链」声明可见`, () => assert.ok(probe.hasCompletenessDisclaimer));
      check(`关系边状态已说明`, () => assert.ok(probe.hasEdgeStatement));
      check(`阶段判定口径已说明`, () => assert.ok(probe.hasBasisLine));
      // 摘要条要印的是**主量级**：公司、关系、申报人、冶炼厂。此前只有四项，
      // 读者看不到「有多少条关系、来自几家申报人」。断言盯的是「印的是不是
      // 那个数」，不是「印了几格」——格数会随设计变，数不该变。
      check(`摘要条印出主量级且与数据一致`, () => {
        const cov = NODES.coverage || {};
        const want = [cov.nodesTotal, cov.edgesTotal, cov.nodesWithEdges,
                      (cov.formSd || {}).uniqueSmelters];
        const got = probe.statusText.replace(/,/g, "");
        want.forEach((n) => {
          assert.ok(n == null || got.includes(String(n)),
            `摘要条里没有 ${n}：${probe.statusText.slice(0, 120)}`);
        });
      });
      // 「频率 每日」曾经单独一格，那是误导：关系数据一年一次，只有行情每日。
      check(`频率分开说：关系一年一次、行情每日`, () => {
        assert.match(probe.statusText, /关系一年一次/);
        assert.match(probe.statusText, /行情每日/);
        // <s> 默认带删除线。「行情每日」被划掉，意思正好反过来——
        // 读者会以为这一项作废了。
        assert.ok(!probe.freqStruck, "「行情每日」被画上了删除线");
      });
      /* 副标题写死过「标普500成分股按价值链环节分层」，扩池到 642 家之后
         那句话就成了假话。改成照数据渲染之后又栽了一次：写死两个池，
         本土 10-K 那 4,209 家入池后在首屏上根本不存在，而摘要条却印
         「公司 5,897 家」——两个数当场对不上。

         所以这条不再逐个池点名，改成**把副标题里的家数加起来，必须等于
         全池**。加一个池而不在副标题露面，这条就会失败；池子改名、顺序
         调整都不影响。 */
      check(`副标题列全所有公司池，家数加起来等于全池`, () => {
        const cov = NODES.coverage || {};
        assert.ok(!/^标普500成分股按价值链环节分层/.test(probe.subtitle),
          "副标题还是那句写死的旧文案");
        const pools = [cov.poolSp500, cov.poolForeignIssuer, cov.poolDomesticFiler]
          .filter((n) => n);
        if (!pools.length) return;
        // 副标题里出现的数（去掉千分位）逐个取出来
        const shown = (probe.subtitle.match(/[\d,]+(?=\s*家)/g) || [])
          .map((t) => parseInt(t.replace(/,/g, ""), 10)).filter((n) => n > 0);
        const sum = shown.reduce((a, b) => a + b, 0);
        assert.equal(sum, cov.nodesTotal,
          `副标题里的家数加起来 ${sum}，全池 ${cov.nodesTotal}——`
          + `有池子没在首屏露面：${probe.subtitle}`);
        pools.forEach((n) => assert.ok(shown.indexOf(n) >= 0,
          `副标题漏了一个 ${n} 家的池：${probe.subtitle}`));
      });
      // 每张环节卡片上的覆盖数，必须等于 nodes.json 里那一段的真值——
      // 断言盯「画的是不是那个数」，不是「画出来了没有」。
      check(`环节卡片的覆盖数逐段等于 nodes.json`, () => {
        assert.ok(probe.bandCov.length, "一张环节卡片都没有覆盖标记");
        probe.bandCov.forEach((b) => {
          const want = NODES.nodes.filter(n => n.stage === b.stage);
          const withEdges = want.filter(n => n.edgeCount).length;
          if (!want.length) return;
          assert.ok(b.text.replace(/\s/g, "").startsWith(withEdges + "/" + want.length),
            `${b.stage} 卡片印 ${b.text.trim()}，数据是 ${withEdges}/${want.length}`);
        });
      });
      // 不同的 0 要说成不同的 0：资源开采那 65 家是报了 13q-1 付款披露，
      // 物流与运输那 10 家是压根没申报。混成一个空白就是在说假话。
      check(`0 覆盖的环节就地写清成因，且不同的 0 说法不同`, () => {
        const zero = probe.bandCov.filter((b) => /^0\//.test(b.text.replace(/\s/g, "")));
        assert.ok(zero.length, "没有 0 覆盖的环节，这条断言失去意义时应删掉");
        zero.forEach((b) => {
          assert.ok(b.why.length > 20, `${b.stage} 的 0 没有成因说明`);
          assert.ok(!/^本环节 \d+ 家：。/.test(b.why), `${b.stage} 的成因是空的`);
        });
        const reasons = new Set(zero.map(b => b.why));
        assert.ok(reasons.size > 1,
          "所有 0 覆盖环节给的是同一句话——不同的 0 被混成了一种");
      });
      /* 成因必须**看得见**，不能只挂在 title 上。
         上面那条断言读的是 .bandcov 的 title——那是 hover 提示，手机上没有
         hover，等于这句话不存在，而断言照样过。**静默通过等于这条断言不存在**。
         公司池扩到一千多家之后「有出处」会掉到个位数百分比，这时候把「为什么
         没覆盖」藏在提示里，读者只会得出「数据很差」，而真相是那些公司根本
         不适用这套申报规则。所以这里盯的是渲染出来的 .bandwhy。 */
      check(`未覆盖的成因写在页面上，不是只挂在 hover 提示里`, () => {
        const has = probe.bandCov.filter((b) => b.whyText);
        assert.ok(has.length, "一个环节都没有可见的成因行（.bandwhy 全缺）");
        has.forEach((b) => {
          assert.ok(b.whyShown, `${b.stage} 的成因行在 DOM 里但不可见，等同于没写`);
          assert.match(b.whyText, /未覆盖的 \d+ 家/, `${b.stage}：${b.whyText}`);
        });
        // 每一个 0 覆盖的环节都必须有这一行——正是那些最会被读错的段
        const zeroNoLine = probe.bandCov
          .filter((b) => /^0\//.test(b.text.replace(/\s/g, "")) && !b.whyText);
        assert.equal(zeroNoLine.length, 0,
          `0 覆盖却没写成因：${zeroNoLine.map(b => b.stage).join("、")}`);
      });
      /* 市值合计算了谁。扩池之后有站内报价的比例掉到 9%~55%（资源开采
         153 家里只有 14 家），而市值就印在家数旁边——读者必然把两个数配成
         一对。一个星号扛不住这个落差，说明也不能只挂在 hover 上。
         这条钉的是：**口径写在看得见的地方，且数字与 nodes.json 对得上**。 */
      check(`市值合计的口径写在页面上，数字与数据一致`, () => {
        const isNum = (v) => typeof v === "number" && isFinite(v);
        let checked = 0;
        probe.bandCov.forEach((b) => {
          const grp = NODES.nodes.filter((n) => n.stage === b.stage);
          if (!grp.length) return;
          const quoted = grp.filter((n) => isNum(n.marketCap)).length;
          if (quoted === grp.length) return;        // 全有报价就不必写
          checked += 1;
          assert.ok(b.whyShown, `${b.stage} 的口径行不可见`);
          if (!quoted) {
            assert.match(b.whyText, /全部没有站内报价/,
              `${b.stage} 一家报价都没有，却没说明：${b.whyText}`);
            return;
          }
          assert.ok(b.whyText.includes(quoted + "/" + grp.length),
            `${b.stage} 没写出报价覆盖 ${quoted}/${grp.length}：${b.whyText}`);
          assert.match(b.whyText, /不是本环节的总市值/,
            `${b.stage} 没说清这不是总市值：${b.whyText}`);
        });
        assert.ok(checked > 0, "没有一个环节存在报价缺口，这条断言失去意义时应删掉");
      });
      /* 覆盖率的分母。**扩池只增加节点、不增加边**，所以「占全池多少」会随
         名录变大而变小——只印这一个数，读者会把名录扩大读成数据变差；而只印
         「占申报人多少」，又是拿小分母把覆盖率说好看。两个都印，才既不夸大
         也不自贬。这条断言钉的就是「两个都在」。 */
      check(`覆盖率同时印全池分母与「报过 Form SD」分母`, () => {
        assert.ok(probe.covSumShown, "覆盖率结论行不可见");
        const cv = NODES.coverage || {};
        const filers = NODES.nodes.filter((n) => ["listed", "filed-no-list",
          "resource-extraction"].indexOf(n.formSdStatus) >= 0).length;
        const flat = probe.covSum.replace(/\s/g, "");
        assert.ok(flat.includes(String(cv.nodesTotal)),
          `没印全池家数 ${cv.nodesTotal}：${probe.covSum}`);
        assert.ok(flat.includes(String(cv.nodesWithEdges)),
          `没印有出处家数 ${cv.nodesWithEdges}：${probe.covSum}`);
        assert.ok(filers > 0, "算不出报过 Form SD 的家数，这条断言失去意义");
        assert.ok(flat.includes(String(filers)),
          `没印报过 Form SD 的 ${filers} 家——只用全池当分母会把「规则不适用」`
          + `记成「我们没做到」：${probe.covSum}`);
        assert.match(probe.covSum, /Form\s*SD/,
          `没说清第二个分母是什么口径：${probe.covSum}`);
      });
      check(`页面无横向溢出`, () => assert.ok(probe.bodyOverflow <= 1,
        `溢出 ${probe.bodyOverflow}px`));
      check(`触控区域不小于 44×44`, () => assert.equal(probe.undersizedTargets, 0));
      check(`环节卡片键盘可达`, () => assert.ok(probe.focusable));
      check(`初始不展开任何环节`, () => assert.equal(probe.expandedInitially, 0));
      /* 渲染中途抛异常的总闸。

         本轮删掉一个变量声明却留下两处使用，ReferenceError 在 render() 里抛出，
         被 fetch 链尾部的 .catch 接住 → 页面显示「加载失败」横幅、但前半截内容
         已经画出来了，看着只是「后面几块是空的」。**15 条断言各自报「内容不对」，
         没有一条说得出原因**，排查花的时间比修复长得多。

         第一版只收 unhandledrejection，什么都没抓到——异常被 .catch 处理过，
         按定义就不是「未捕获」。真正的信号是那条**本不该出现的错误横幅**：
         正常路径上它必须是隐藏的，出现就说明渲染半路断了，而且它自带原因。 */
      const loadState = await evaluate(`(() => {
        const e = document.getElementById('state');
        if (!e) return { shown: false, cls: '', text: '' };
        return { shown: !e.hidden && e.offsetHeight > 0,
                 cls: e.className || '',
                 text: (e.textContent || '').trim().slice(0, 160) };
      })()`);
      const pageErrors = await evaluate(`(window.__pageErrors || []).slice(0, 4)`);
      check(`渲染没有中途失败（错误横幅不出现）`, () => {
        assert.equal(loadState.shown, false,
          `页面显示了状态横幅（class=${loadState.cls}）：${loadState.text}`);
        assert.ok(!/\berr\b/.test(loadState.cls),
          `状态元素被标成错误态：${loadState.text}`);
        assert.deepEqual(pageErrors, [],
          `另有未捕获异常：${pageErrors.join(" | ")}`);
      });

      /* 按板块的覆盖情况。这一段直接回答「为什么有的公司有数据、有的没有」，
         页面上印的每个数字都必须来自 nodes.json，不能由前端自己算出个近似值。
         同时守两件事：进度条的分段必须加满（缺一段 = 比例是错的），
         以及窄屏下这个三列网格不能把页面撑宽——上一次 360px 溢出 93px
         就是网格项默认 min-width:auto 造成的。 */
      const cov = await evaluate(`(() => {
        const box = document.getElementById('cov');
        if (!box || box.hidden) return { shown: false };
        // 只数板块那一栏。外国发行人按国别的行在 #cov-country-rows 里，
        // 混着数会把 11 个板块数成 52 行——这正是第一版失败的形态。
        const rows = [...box.querySelectorAll('#cov-rows .covrow')].map(r => {
          const segs = [...r.querySelectorAll('.t i')];
          return {
            sector: r.querySelector('.s').textContent,
            num: r.querySelector('.n').textContent,
            widthSum: Math.round(segs.reduce(
              (a, i) => a + parseFloat(i.style.width || '0'), 0)),
            label: r.querySelector('.t').getAttribute('aria-label') || '',
            segs: segs.length
          };
        });
        return {
          shown: true,
          heading: box.querySelector('h2').textContent,
          lead: box.querySelector('#cov-lead').textContent,
          foot: box.querySelector('#cov-foot').textContent,
          rows,
          keys: box.querySelectorAll('#cov-rows .covkey span').length,
          countryRows: box.querySelectorAll('#cov-country-rows .covrow').length,
          // 每行右侧印的是「有出处 / 共几家」。把分母加起来，就能验证
          // 长尾并入「其他」之后**合计仍等于全池**——那才是真正的契约。
          countryShown: [...box.querySelectorAll('#cov-country-rows .covrow .n')]
            .map(e => parseInt((e.textContent.split('/')[1] || '0').trim(), 10) || 0),
          countryLastLabel: (([...box.querySelectorAll('#cov-country-rows .covrow .s')]
            .pop() || {}).textContent) || '',
          countryLead: (box.querySelector('#cov-country-lead') || {}).textContent || '',
          sicLead: (box.querySelector('#cov-sic-lead') || {}).textContent || '',
          sicShown: (() => {
            const e = box.querySelector('#cov-sic-lead');
            return !!(e && !e.hidden && e.offsetHeight > 0);
          })(),
          catLead: (box.querySelector('#cov-cat-lead') || {}).textContent || '',
          catShown: (() => {
            const e = box.querySelector('#cov-cat-lead');
            return !!(e && !e.hidden && e.offsetHeight > 0);
          })(),
          catRows: [...box.querySelectorAll('#cov-cat-rows .covrow')].map(r => ({
            sector: (r.querySelector('.s') || {}).textContent || '',
            num: (r.querySelector('.n') || {}).textContent || ''
          })),
          bigMetric: (([...document.querySelectorAll('#statusrow .status')]
            .find(e => (e.textContent || '').indexOf('大型申报人') === 0) || {})
            .textContent) || '',
          countryLeadHidden: !!(box.querySelector('#cov-country-lead') || {}).hidden,
          overflow: box.scrollWidth - box.clientWidth
        };
      })()`);

      check(`按板块覆盖区块已渲染`, () => assert.ok(cov.shown));
      check(`板块数与节点表一致（${SECTORS.length}）`,
        () => assert.equal(cov.rows.length, SECTORS.length));
      check(`每行进度条分段加满 100%`, () => {
        const bad = cov.rows.filter(r => Math.abs(r.widthSum - 100) > 1);
        assert.equal(bad.length, 0,
          bad.map(r => `${r.sector} 只有 ${r.widthSum}%`).join("；"));
      });
      check(`页面印的家数与 nodes.json 一致`, () => {
        const bad = [];
        for (const r of SECTORS) {
          const row = cov.rows.find(x => x.sector === r.sector);
          if (!row) { bad.push(`${r.sector} 未渲染`); continue; }
          const want = `${r.withEdges} / ${r.companies}`;
          if (row.num !== want) bad.push(`${r.sector} 显示「${row.num}」应为「${want}」`);
        }
        assert.equal(bad.length, 0, bad.join("；"));
      });
      check(`零覆盖板块给出原因而不是留空`, () => {
        const zero = SECTORS.filter(r => !r.withEdges);
        assert.ok(zero.length > 0, "样本里没有零覆盖板块，这条断言失去意义");
        for (const r of zero) {
          const row = cov.rows.find(x => x.sector === r.sector);
          assert.ok(row && row.segs > 0, `${r.sector} 一段都没画，读者看不出原因`);
        }
      });
      check(`每段进度条有可读的无障碍描述`, () => {
        const bad = cov.rows.filter(r => !r.label.includes("共"));
        assert.equal(bad.length, 0, bad.map(r => r.sector).join("、"));
      });
      check(`图例与实际用到的分类对应`, () => assert.ok(cov.keys > 0));
      check(`不把「无申报」说成没有供应链`, () => {
        // Form SD 不适用 ≠ 这家公司没有供应链。这句话说错了就是对读者撒谎。
        if (!cov.foot.includes("无申报")) return;
        assert.ok(cov.foot.includes("不等于"),
          "提到「无申报」却没有澄清它不等于没有供应链");
      });
      /* 第二个池按国别。守的是**分母没有被悄悄换掉**：板块那一栏是标普 495 家，
         国别这一栏是外国发行人 147 家，两栏加起来才是 642。混成一栏的话，
         「金融 0/70」这类制度上限的解释就被稀释了。 */
      const COUNTRIES = (NODES.coverage || {}).byCountry || [];
      if (COUNTRIES.length) {
        const foreignN = COUNTRIES.reduce((a, r) => a + (r.companies || 0), 0);
        // 国别 30 行里 11 行只有 1 家，长尾把版面撑长却读不出东西，因此并入
        // 「其他」。断言不再盯行数（行数会随取舍变），改盯**合计**：
        // 显示出来的行加起来必须仍等于全池——那是「不是省略，是收拢」的证据。
        check(`外国发行人按国别单列，合计仍等于全池 ${foreignN} 家`, () => {
          assert.ok(!cov.countryLeadHidden, "国别栏的说明被藏起来了");
          const shown = cov.countryShown.reduce((a, b) => a + b, 0);
          assert.equal(shown, foreignN,
            `页面各行合计 ${shown}，全池 ${foreignN}——长尾被丢了，不是收拢`);
        });
        check(`长尾收进「其他」而不是截断`, () => {
          if (COUNTRIES.length <= cov.countryRows) return;   // 没折叠就不查
          assert.match(cov.countryLastLabel, /其他/,
            `最后一行是 ${cov.countryLastLabel}，没有「其他」这一行就是截断`);
        });
        check(`说清这一栏的口径是地理不是板块，且写明按经营地`, () => {
          assert.match(cov.countryLead, /口径是(国别|地理)，不是板块/,
            `实际：${cov.countryLead.slice(0, 80)}`);
          assert.ok(cov.countryLead.includes(String(foreignN)),
            `说明里没写家数：${cov.countryLead}`);
          /* 汇总用的是经营地（离岸注册者折回营业地址）。**说明必须跟着口径走**
             ——改了汇总不改这句话，页面就在说假话，而这正是最难被发现的一类错：
             数字全对，只有那句解释是旧的。 */
          assert.match(cov.countryLead, /经营地/,
            `没说清是按经营地汇总：${cov.countryLead.slice(0, 120)}`);
          assert.match(cov.countryLead, /开曼|离岸|只做登记/,
            `没说清为什么不用注册地：${cov.countryLead.slice(0, 160)}`);
        });
        /* 三栏加起来必须等于全池。**每加一个池就要在这里加一项**，
           否则新池的公司在页面上直接消失——覆盖率面板漏掉它们，
           而每个数字看着都对。本轮加第三池时这条正是拦下来的那道关口。 */
        check(`三栏加起来等于全池（板块 ${SECTORS.length} 个）`, () => {
          const sum = (rows) => (rows || []).reduce((a, r) => a + (r.companies || 0), 0);
          const sectorN = sum(SECTORS);
          const sicN = sum((NODES.coverage || {}).bySicMajor);
          assert.equal(sectorN + foreignN + sicN, NODES.nodes.length,
            `板块 ${sectorN} + 经营地 ${foreignN} + 行业大类 ${sicN} `
            + `≠ 全池 ${NODES.nodes.length}——有公司哪一栏都没进`);
        });
        if (((NODES.coverage || {}).bySicMajor || []).length) {
          check(`本土 10-K 申报人单列一栏，并写清是行业大类不是板块`, () => {
            assert.ok(cov.sicShown, "第三栏没渲染——这几千家会掉进「未分类」黑箱");
            assert.match(cov.sicLead, /行业大类/, `实际：${cov.sicLead.slice(0, 100)}`);
            assert.match(cov.sicLead, /不是 GICS 板块|不是板块/,
              `没说清与板块的区别：${cov.sicLead.slice(0, 120)}`);
          });
        }
      }

      /* 规模轴（申报人档位）。这一栏是**唯一一条三个池通用的规模尺**——
         站内报价只覆盖标普那 495 家（8%），市值答不了「这 5,897 家里
         哪些是大公司」。

         它上一版栽的跟头值得逐条钉住：SEC 的 category 是 "A<br>B<br>C"
         拼串，渲染层用 indexOf 去解析，于是 477 家的标签是
         「<br>Emerging growth company」——**HTML 标记原样印在屏幕上**，
         14 个原串归到 7 个标签、同一个档印两行，而且「小型申报公司」
         「新兴成长公司」这两种**不是规模**的身份混进了规模轴。
         解析已挪回构建脚本，这里守住页面不再退回去。 */
      const CATS = (NODES.coverage || {}).byFilerCategory || [];
      if (CATS.length) {
        check(`规模轴单列一栏并渲染`, () => assert.ok(cov.catShown,
          "第四栏没渲染——市值只覆盖 8%，没有这条轴就答不了「谁是大公司」"));
        check(`档位逐行等于数据，且不重复`, () => {
          assert.equal(cov.catRows.length, CATS.length,
            `页面 ${cov.catRows.length} 行，数据 ${CATS.length} 档`);
          const bad = [];
          for (const r of CATS) {
            const row = cov.catRows.find(x => x.sector === r.sector);
            if (!row) { bad.push(`${r.sector} 未渲染`); continue; }
            const want = `${r.withEdges} / ${r.companies}`;
            if (row.num !== want) bad.push(`${r.sector}「${row.num}」应为「${want}」`);
          }
          assert.equal(bad.length, 0, bad.join("；"));
          const labels = cov.catRows.map(r => r.sector);
          assert.equal(new Set(labels).size, labels.length,
            `有档印了两行：${labels.join(" / ")}`);
        });
        check(`档位标签里没有漏出的 HTML 标记`, () => {
          const dirty = cov.catRows.filter(r => /[<>]/.test(r.sector));
          assert.equal(dirty.length, 0,
            `${dirty.map(r => r.sector).join("；")}——SEC 原串没拆就印出来了`);
        });
        /* **覆盖率照数说。** 这条轴不是 100% 覆盖：新上市公司的档位要到
           财年末才评。数字全对而只有解释是旧的，是最难发现的错。 */
        const tiered = CATS.filter(r => r.sector !== "未分类"
          && r.sector !== "未标注档位")
          .reduce((a, r) => a + (r.companies || 0), 0);
        check(`不把这条轴说成 100% 覆盖（实际 ${tiered}/${NODES.nodes.length}）`, () => {
          assert.ok(cov.catLead.includes(String(tiered).replace(
              /\B(?=(\d{3})+(?!\d))/g, ",")),
            `导语没印真实覆盖 ${tiered} 家：${cov.catLead.slice(0, 160)}`);
          assert.ok(!/分档\s*100%\s*覆盖/.test(cov.catLead),
            `还在说「100% 覆盖」：${cov.catLead.slice(0, 160)}`);
          assert.match(cov.catLead, /不是市值区间/,
            `没说清它不是市值：${cov.catLead.slice(0, 160)}`);
        });
        const bigRow = CATS.find(r => r.sector === "大型加速申报人");
        if (bigRow && cov.bigMetric) {
          check(`摘要条的「大型申报人」等于这一栏的大型加速档`, () => {
            assert.ok(cov.bigMetric.includes(String(bigRow.companies).replace(
                /\B(?=(\d{3})+(?!\d))/g, ",")),
              `摘要条印「${cov.bigMetric}」，这一栏是 ${bigRow.companies} 家`);
          });
        }
      }

      check(`按板块区块无横向溢出`, () => assert.ok(cov.overflow <= 1,
        `溢出 ${cov.overflow}px`));

      /* 顺序与主体。细分构成是这一页的主体，必须**默认可见**——
         上一版把它藏在点击后面，不点开就只看得到六个数字。
         链的顺序用向下的箭头表示，只画在实物四段之间。 */
      const chain = await evaluate(`(() => {
        const cs = [...document.querySelectorAll('#chain .band')];
        const os = [...document.querySelectorAll('#offchain .band')];
        const wrapped = cs.concat(os).filter(el => {
          const nm = el.querySelector('.nm');
          if (!nm) return true;
          const r = nm.getBoundingClientRect();
          return r.height > parseFloat(getComputedStyle(nm).lineHeight) * 1.6;
        }).map(el => el.querySelector('.nm') ? el.querySelector('.nm').textContent : '?');
        return {
          chainCount: cs.length,
          offCount: os.length,
          linksInChain: document.querySelectorAll('#chain .link').length,
          linksOffChain: document.querySelectorAll('#offchain .link').length,
          wrapped,
          segsPerBand: cs.concat(os).map(el => el.querySelectorAll('.seg').length),
          openInitially: cs.concat(os)
            .filter(el => !el.querySelector('.panel').hidden).length,
          pctPerBand: cs.concat(os).map(el => el.querySelectorAll('.pc').length)
        };
      })()`);

      // 段数从环节表推导，不写死。写死的话每次调整分类都要改测试，
      // 而测试本该守的是「页面画的和数据说的一致」，不是某个具体数字。
      const CHAIN_N = NODES.stages.filter(s => s.chain).length;
      const OFF_N = NODES.stages.filter(s => !s.chain).length;
      check(`实物链 ${CHAIN_N} 段 + 使能层 ${OFF_N} 段`, () => {
        assert.equal(chain.chainCount, CHAIN_N, `链内 ${chain.chainCount}`);
        assert.equal(chain.offCount, OFF_N, `链外 ${chain.offCount}`);
      });
      check(`环节标题不折行（旧版「上游资／源」）`, () => assert.equal(
        chain.wrapped.length, 0, `折行的：${JSON.stringify(chain.wrapped)}`));
      // 这一条是本次改版的要点：细分是主体，不是点开才有
      check(`每个环节的细分构成默认就可见`, () => {
        const empty = chain.segsPerBand.filter(n => n === 0).length;
        assert.equal(empty, 0, `有 ${empty} 个环节没有细分条`);
      });
      check(`初始不展开任何公司表`, () => assert.equal(chain.openInitially, 0));
      check(`表头只留一个涨跌口径`, () => assert.ok(
        chain.pctPerBand.every(n => n <= 1),
        `实际 ${JSON.stringify(chain.pctPerBand)}`));
      check(`实物链各段之间有顺序箭头（${CHAIN_N - 1} 个）`, () => assert.equal(
        chain.linksInChain, CHAIN_N - 1, `箭头 ${chain.linksInChain} 个`));
      check(`链外不画箭头——它不在实物流转链条上`, () => assert.equal(
        chain.linksOffChain, 0));

      /* 横轴：一级产业链筛选。这一段守的是**二维模型没有变成一句口号**——
         选一条链，屏幕上的家数要真的跟着变，而且变成的那个数要等于数据里
         写的那个数。另外守两条诚实性：筛完不能拿全环节的涨跌冒充该链的涨跌；
         页面必须写明「链是分类不是关系」，否则读者会把同链两家当成有供应关系。 */
      const CHAINS = (NODES.chains || []).filter(c => c.count > 0);
      const PICKED = CHAINS.find(c => c.id === "semiconductor") || CHAINS[0] || {};
      const cp = await evaluate(`(() => {
        const host = document.getElementById('chainpick');
        if (!host || host.hidden) return { shown: false };
        const chips = [...host.querySelectorAll('.chip')];
        return {
          shown: true,
          chips: chips.length,
          labels: chips.map(c => (c.querySelector('.cl') || {}).textContent),
          counts: chips.map(c => (c.querySelector('.cc') || {}).textContent)
        };
      })()`);
      check(`横轴选择条已渲染`, () => assert.ok(cp.shown));

      /* 筛了链，风险面板必须跟着筛。

         这三块（真实流向 / 上游集中度 / 国别暴露）此前完全不读筛选状态：
         读者点「半导体」，环节卡筛到 48 家，往下滚读到的却是 23 条链合计的
         「31,320 条关系、72 个国别、128 家分母」。**数字本身没错，错在它
         回答的不是读者以为的那个问题**——在筛选语境下印全局数并且一个字不说，
         等于把全局风险说成这条链的风险。

         断言比对的是 nodes.json 里 chainRisk 的真值，不是页面自己算的数。 */
      const RISK = (NODES.chainRisk || {})[PICKED.id];
      if (RISK) {
        const rk = await evaluate(`(() => {
          const chip = [...document.querySelectorAll('#chainpick .chip')]
            .find(c => c.getAttribute('data-chain') === ${JSON.stringify(PICKED.id)}
              || ((c.querySelector('.cl') || {}).textContent || '').trim()
                 === ${JSON.stringify(PICKED.label || "")});
          const read = () => ({
            conc: (document.getElementById('conc-lead') || {}).textContent || '',
            expo: (document.getElementById('expo-lead') || {}).textContent || '',
            flow: (document.getElementById('flow-lead') || {}).textContent || '',
            rows: document.querySelectorAll('#expo-rows .exprow').length
          });
          const before = read();
          if (!chip) return { clicked: false, before };
          chip.click();
          const after = read();
          // **点完必须点回去。** 这个探针改的是页面状态，不还原的话后面
          // 每一条断言都在筛过的页面上跑——上一版就是这么让整个套件炸掉的。
          chip.click();
          return { clicked: true, before, after, restored: read() };
        })()`);
        check(`筛出「${PICKED.label}」后风险面板跟着换口径`, () => {
          assert.ok(rk.clicked, "没找到该链的筛选按钮");
          assert.notEqual(rk.after.conc, rk.before.conc, "上游集中度没跟着变");
          assert.notEqual(rk.after.expo, rk.before.expo, "国别暴露没跟着变");
        });
        check(`筛选后印的是这条链的分母，不是全池的`, () => {
          const all = String((NODES.coverage || {}).nodesWithEdges || 0);
          [["上游集中度", rk.after.conc], ["国别暴露", rk.after.expo]].forEach(
            ([name, text]) => {
              assert.ok(text.includes(String(RISK.filers)),
                `${name}没印这条链有名单的 ${RISK.filers} 家：${text.slice(0, 110)}`);
              assert.ok(text.indexOf(PICKED.label) >= 0,
                `${name}没写清当前筛的是哪条链：${text.slice(0, 110)}`);
              assert.ok(!new RegExp("有名单的 " + all + " 家").test(text),
                `${name}还在印全池分母 ${all} 家：${text.slice(0, 110)}`);
            });
        });
        check(`取消筛选后风险面板回到全池口径`, () => {
          assert.equal(rk.restored.conc, rk.before.conc,
            "再点一次没有回到全池——筛选是可逆的，回不去就是状态泄漏");
          assert.equal(rk.restored.expo, rk.before.expo, "国别暴露没回到全池");
        });
        /* 流向桑基也按链画。上一轮没有按链的版本，只能在页面上声明「这张图
           仍是全池口径」——照实说不算错，但那是缺口不是终点。现在按链预算了
           （24 条链共 81KB），断言从「必须声明是全池」翻成「必须画这条链自己的」：
           带子总数要等于这条链的关系数，不能还是 31,320。 */
        check(`流向图按链重画，总数等于这条链的关系数`, () => {
          assert.ok(rk.after.flow.includes(String(RISK.edges)),
            `没印这条链的关系数 ${RISK.edges}：${rk.after.flow.slice(0, 130)}`);
          assert.ok(!/仍是全池口径/.test(rk.after.flow),
            `还在声明「仍是全池口径」，说明没接上按链的流向：${rk.after.flow.slice(0, 130)}`);
          const all = String((NODES.coverage || {}).edgesTotal || 0);
          assert.ok(!rk.after.flow.includes(all),
            `流向图还在印全池的 ${all} 条：${rk.after.flow.slice(0, 130)}`);
          assert.ok(rk.after.flow.indexOf(PICKED.label) >= 0,
            `没写清当前是哪条链：${rk.after.flow.slice(0, 130)}`);
        });
      }

      /* 两个公司池。**这一段守的是「哪些数适用于哪一批公司」不被混起来**：
         外国私人发行人站内没有报价，市值合计与环节涨跌都不含它们。
         页面把 500 家印在一起而不说这件事，读者就会以为都有市值。 */
      const FOREIGN_N = (NODES.coverage || {}).poolForeignIssuer || 0;
      if (FOREIGN_N) {
        const pool = await evaluate(`(() => {
          const m = document.getElementById('method');
          const marked = [...document.querySelectorAll('#chain .bandhd .mc s, #offchain .bandhd .mc s')];
          return {
            method: m ? m.textContent : '',
            starred: marked.length,
            starTitles: marked.map(x => (x.parentNode || {}).title || '')
          };
        })()`);
        check(`方法区说明两个公司池（外国发行人 ${FOREIGN_N} 家）`, () => {
          assert.ok(pool.method.includes(String(FOREIGN_N)),
            "方法区没提外国发行人的家数");
          assert.match(pool.method, /站内没有它们的报价/);
          assert.match(pool.method, /市值合计与环节涨跌都不含这批公司/);
        });
        check(`说明为什么只收报 Form SD 的那一批`, () => assert.match(
          pool.method, /只增加孤立节点的扩池没有意义/));
        check(`说明指数商名单因许可未采用`, () => assert.match(
          pool.method, /再分发要授权/));
        // 有无报价公司的环节，市值要打星并说清差在哪几家
        if (pool.starred) {
          check(`市值打星处说清只含有报价的几家`, () => {
            assert.ok(pool.starTitles.every(t => /有站内报价/.test(t)),
              `实际：${JSON.stringify(pool.starTitles.slice(0, 2))}`);
          });
        }
        check(`方法区没有漏出的 Markdown 星号`, () => assert.ok(
          !/\*\*/.test(pool.method)));
      }


      /* 层次排布。守的是**页面画的层等于数据算的层**——层次是由 77 条连线算出来的，
         页面自己排一套的话，改一条连线两边就会悄悄对不上。 */
      const DEPTH = (NODES.coverage || {}).chainDepth || 0;
      if (DEPTH) {
        const lv = await evaluate(`(() => {
          const bands = [...document.querySelectorAll('#chainpick .picklv')];
          return {
            bands: bands.length,
            crossBands: document.querySelectorAll('#chainpick .picklv.cross').length,
            rows: bands.map(b => ({
              tag: (b.querySelector('.lv') || {}).textContent || '',
              chains: [...b.querySelectorAll('.chip .cl')].map(x => x.textContent)
            })),
            hint: (document.querySelector('#chainpick .pickhint') || {}).textContent || ''
          };
        })()`);
        const CROSS_IDS = Object.keys(NODES.chainCrossCutting || {});
        const layered = (NODES.chains || []).filter(c => c.count > 0 && typeof c.layer === "number");
        const crossShown = (NODES.chains || []).filter(c => c.count > 0 && CROSS_IDS.includes(c.id));
        const usedLayers = [...new Set(layered.map(c => c.layer))].sort((a, b) => a - b);

        check(`层次行数 = 用到的层数 ${usedLayers.length}${crossShown.length ? " + 使能层" : ""}`,
          () => assert.equal(lv.bands, usedLayers.length + (crossShown.length ? 1 : 0),
            `页面 ${lv.bands} 行`));
        check(`每条链画在数据说的那一层`, () => {
          usedLayers.forEach((n, i) => {
            const want = layered.filter(c => c.layer === n).map(c => c.label).sort();
            const got = [...(lv.rows[i].chains || [])].sort();
            assert.deepEqual(got, want,
              `L${n} 页面 ${JSON.stringify(got)}，数据 ${JSON.stringify(want)}`);
          });
        });
        check(`使能链单独一行，不塞进任何一层`, () => {
          if (!crossShown.length) return;
          assert.equal(lv.crossBands, 1, `使能行 ${lv.crossBands} 个`);
          const got = [...(lv.rows[lv.rows.length - 1].chains || [])].sort();
          assert.deepEqual(got, crossShown.map(c => c.label).sort());
        });
        check(`首尾标出方向感（最上游／最终端）`, () => {
          assert.match(lv.rows[0].tag, /最上游/, `首行「${lv.rows[0].tag}」`);
          assert.match(lv.rows[usedLayers.length - 1].tag, /最终端/,
            `末层「${lv.rows[usedLayers.length - 1].tag}」`);
        });
        check(`说明层次是算出来的，不是手工排的`, () => {
          assert.match(lv.hint, /不是手工排的/);
          assert.match(lv.hint, new RegExp(String(DEPTH) + " 层"));
        });
      }

      check(`链数与数据一致（${CHAINS.length} 条 + 全部）`, () => assert.equal(
        cp.chips, CHAINS.length + 1, `页面 ${cp.chips} 个 chip`));
      check(`每条链的家数取自数据，不在前端现编`, () => {
        CHAINS.forEach(c => {
          const i = cp.labels.indexOf(c.label);
          assert.ok(i >= 0, `${c.label} 没画出来`);
          assert.equal(cp.counts[i], c.count + " 家",
            `${c.label} 页面写 ${cp.counts[i]}，数据是 ${c.count} 家`);
        });
      });

      // 真点一下，看家数是否跟着变；该链没覆盖的环节要留在页面上并标空，不能藏
      const picked = await evaluate(`(() => {
        const label = ${JSON.stringify(PICKED.label || "")};
        const chips = [...document.querySelectorAll('#chainpick .chip')];
        const chip = chips.find(c => (c.querySelector('.cl') || {}).textContent === label);
        if (!chip) return { found: false };
        chip.click();
        const bands = [...document.querySelectorAll('#chain .band, #offchain .band')];
        const nOf = b => parseInt((b.querySelector('.n') || {}).textContent, 10) || 0;
        return {
          found: true,
          bands: bands.length,
          empty: bands.filter(b => b.classList.contains('empty')).length,
          total: bands.reduce((a, b) => a + nOf(b), 0),
          pcs: document.querySelectorAll('#chain .pc, #offchain .pc').length,
          sub: (document.getElementById('chain-sub') || {}).textContent || "",
          note: (document.getElementById('chain-note') || {}).textContent || "",
          overflow: Math.max(0, document.documentElement.scrollWidth - window.innerWidth)
        };
      })()`);
      check(`选中「${PICKED.label}」后各环节家数合计等于数据（${PICKED.count}）`, () => {
        assert.ok(picked.found, "选择条上找不到这条链");
        // 一家公司只落在一个环节上，所以各环节家数之和必须正好等于该链家数
        assert.equal(picked.total, PICKED.count,
          `页面各环节合计 ${picked.total}，数据说 ${PICKED.count}`);
      });
      check(`该链没覆盖的环节留在页面上并标空`, () => {
        assert.equal(picked.bands, NODES.stages.length,
          `筛选后只剩 ${picked.bands} 条带子——藏起来会让人以为这条链就这么短`);
        assert.ok(picked.empty > 0,
          "这条链铺满了全部环节？与家数对不上，先看数据");
      });
      check(`筛选后不拿全环节涨跌冒充该链涨跌`, () => assert.equal(
        picked.pcs, 0, `还显示着 ${picked.pcs} 个涨跌`));
      check(`筛选说明写清「链是分类不是关系」`, () => assert.ok(
        /链是分类，不是关系/.test(picked.note),
        `实际：${picked.note.slice(0, 60)}`));
      check(`标题写明这条链落在几个环节上`, () => assert.ok(
        /落在 \d+ \/ \d+ 个环节上/.test(picked.sub), `实际：${picked.sub}`));
      check(`筛选后无横向溢出`, () => assert.ok(picked.overflow <= 1,
        `溢出 ${picked.overflow}px`));

      // 再点一次要能取消，否则用户被困在一条链里
      const cleared = await evaluate(`(() => {
        const label = ${JSON.stringify(PICKED.label || "")};
        const chips = [...document.querySelectorAll('#chainpick .chip')];
        const chip = chips.find(c => (c.querySelector('.cl') || {}).textContent === label);
        chip.click();
        const bands = [...document.querySelectorAll('#chain .band, #offchain .band')];
        const nOf = b => parseInt((b.querySelector('.n') || {}).textContent, 10) || 0;
        return { total: bands.reduce((a, b) => a + nOf(b), 0),
                 empty: bands.filter(b => b.classList.contains('empty')).length };
      })()`);
      check(`再点一次取消筛选，回到全池`, () => {
        assert.equal(cleared.total, NODES.nodes.length,
          `取消后合计 ${cleared.total}，全池 ${NODES.nodes.length}`);
        assert.equal(cleared.empty, 0, "取消筛选后不该还有空环节");
      });

      /* 公司查找。642 家而页面上零个输入框是硬伤——这一段守的是它**找得到、
         说得准、不默默截断**：命中哪一项要标出来，超上限要说还有多少家，
         一条不中要说清本板块不是全市场。 */
      const look = await evaluate(`(async () => {
        const i = document.getElementById('q'), L = document.getElementById('qlist');
        if (!i || !L) return null;
        const probe = (q) => {
          i.value = q; i.dispatchEvent(new Event('input'));
          return {
            hidden: L.hidden,
            rows: [...L.querySelectorAll('a')].map((a) => ({
              text: a.textContent, href: a.getAttribute('href') })),
            note: (L.querySelector('.qnone') || {}).textContent || '',
          };
        };
        const first = ${JSON.stringify(NODES.nodes[0].symbol)};
        return { bySymbol: probe(first), noHit: probe('zzzzqqqq'), empty: probe('') };
      })()`);
      check(`总览页有公司查找入口`, () => assert.ok(look, "没有 #q 输入框"));
      check(`按代码查得到，且链接指向该公司页`, () => {
        const want = NODES.nodes[0].symbol;
        assert.ok(look.bySymbol.rows.length, `查 ${want} 一条都没有`);
        assert.ok(look.bySymbol.rows[0].href.includes(encodeURIComponent(want)),
          `第一条链接是 ${look.bySymbol.rows[0].href}`);
      });
      check(`结果里标出命中的是哪一项`, () => {
        assert.match(look.bySymbol.rows[0].text, /配(代码|中文名|英文名)/,
          `实际：${look.bySymbol.rows[0].text}`);
      });
      check(`结果里说明这家有没有关系数据`, () => {
        assert.ok(/条关系|暂无关系数据/.test(look.bySymbol.rows[0].text),
          `实际：${look.bySymbol.rows[0].text}`);
      });
      check(`查不到时说清本板块不是全市场`, () => {
        assert.equal(look.noHit.rows.length, 0, "乱输也匹配出了公司");
        assert.match(look.noHit.note, /不是全市场/, `实际：${look.noHit.note}`);
      });
      check(`清空输入后结果收起`, () => assert.ok(look.empty.hidden,
        "清空后下拉还开着"));

      /* 国别暴露。这一屏存在的理由是**条数与暴露家数是两个读数**——
         只印一个会把风险读反（印尼按条数第 4、按暴露家数第 1）。
         所以断言盯的是：两个数都印了、都等于数据、排名不一致时说出来了。 */
      const EXPO = NODES.countryExposure || [];
      if (EXPO.length) {
        const listedN2 = Object.keys(NODES.edgeIndex || {}).length;
        const ex = await evaluate(`(() => {
          const box = document.getElementById('expsec');
          if (!box || box.hidden) return { shown: false };
          const rows = [...box.querySelectorAll('.exprow')];
          return {
            shown: true,
            count: rows.length,
            names: rows.map(r => (r.querySelector('.nm') || {}).textContent || ''),
            filers: rows.map(r => parseInt(
              ((r.querySelector('.n') || {}).textContent || '').trim(), 10) || 0),
            edges: rows.map(r => ((r.querySelector('.ed') || {}).textContent || '')
              .replace(/[^0-9]/g, '')),
            reach: rows.map(r => {
              const c = r.querySelector('.rch');
              // textContent 对 display:none 照样返回文本，所以同时量可见性：
              // 没有布局盒 = 读者看不到 = 这一格等于没写。
              return c ? { text: (c.textContent || '').trim(),
                           seen: c.getClientRects().length > 0 } : null;
            }),
            lead: (document.getElementById('expo-lead') || {}).textContent || '',
            foot: (document.getElementById('expo-foot') || {}).textContent || '',
            overflow: Math.max(0,
              document.documentElement.scrollWidth - window.innerWidth),
          };
        })()`);
        check(`国别暴露已渲染`, () => assert.ok(ex.shown, "区块没显示"));
        check(`暴露家数逐行等于数据，且降序`, () => {
          const want = EXPO.slice(0, ex.count);
          assert.deepEqual(ex.filers, want.map(r => r.filerCount));
          assert.deepEqual(ex.names, want.map(r => r.country));
        });
        check(`关系条数也印了，且等于数据`, () => {
          const want = EXPO.slice(0, ex.count).map(r => String(r.edges));
          assert.deepEqual(ex.edges, want,
            "条数列没印或对不上——只印暴露家数会把风险读反");
        });
        /* 这一列是**这份数据的边界读数**：该国有多少家冶炼厂、其中几家点得开。
           全库 1,767 家冶炼厂里只有 6 条能对上池内公司（去重 2 家），中国 588
           家里 0 家、印尼 155 家里 0 家——冶炼厂本来就多是非上市的民营精炼厂。
           不印这一格，读者会以为「暴露在印尼」还能顺着点下去；印了才看得出
           这张图到冶炼厂这一层为止。所以它不能哪天悄悄消失，也不能被样式藏起来。 */
        const REACH = ((NODES.smelterReach || {}).byCountry) || [];
        if (REACH.length) {
          const want = ex.names.map(c => REACH.find(r => r.country === c) || null);
          check(`每行印出该国冶炼厂数与其中几家在池内`, () => {
            want.forEach((w, i) => {
              if (!w) return;                        // 数据里没这国就不该有这一格
              const got = ex.reach[i];
              assert.ok(got, `第 ${i + 1} 行「${ex.names[i]}」缺这一格`);
              assert.ok(got.text.includes(String(w.smelters).replace(
                  /\B(?=(\d{3})+(?!\d))/g, ",")),
                `「${ex.names[i]}」没印 ${w.smelters} 家冶炼厂：${got.text}`);
              assert.ok(w.inPool
                  ? got.text.includes(String(w.inPool))
                  : /均不在池内/.test(got.text),
                `「${ex.names[i]}」在池内的是 ${w.inPool} 家，印的是：${got.text}`);
            });
          });
          check(`这一列看得见，不是被样式藏起来的`, () => {
            const have = ex.reach.filter(Boolean);
            assert.ok(have.length, "一行都没渲染出这一格");
            const blind = have.filter(r => !r.seen).length;
            assert.equal(blind, 0,
              `${blind}/${have.length} 格有文本却没有布局盒——藏起来等于没写`);
          });
          const zero = REACH.filter(r => !r.inPool).length;
          check(`页面说清全库 ${NODES.smelterReach.smeltersTotal} 家冶炼厂里只有`
            + ` ${NODES.smelterReach.distinctCompanies} 家是池内公司`, () => {
            const txt = ex.lead + ex.foot;
            assert.ok(/冶炼厂|不在池内|点得开|点开/.test(txt + ex.reach.map(
                r => (r || {}).text || '').join('')),
              "整屏没有一处说明冶炼厂这一层的可达性");
            assert.ok(zero > 0, "口径变了：现在每个国别都有池内冶炼厂，断言该重写");
          });
        }
        check(`分母说清是有名单的 ${listedN2} 家，不是全部 ${NODES.nodes.length} 家`, () => {
          assert.ok(ex.lead.includes(String(listedN2)), `导语：${ex.lead}`);
          assert.match(ex.lead, /不是全部/);
        });
        // 两个读数排名不同时必须就地说出来——那正是这一屏存在的理由
        const byEdges = EXPO.slice().sort((a, b) => b.edges - a.edges);
        if (byEdges[0].country !== EXPO[0].country) {
          check(`两列排名不一致时页面把这件事说出来`, () => {
            assert.match(ex.foot, /排名不同/, `页脚：${ex.foot}`);
            assert.ok(ex.foot.includes(EXPO[0].country)
              && ex.foot.includes(byEdges[0].country),
              `页脚没点名那两个国别：${ex.foot}`);
          });
        }
        check(`不把「出现在名单里」说成采购关系`, () => {
          assert.match(ex.foot, /不说明.*直接采购关系/, `页脚：${ex.foot}`);
          assert.ok(!ex.foot.includes("供应商"), `页脚出现「供应商」：${ex.foot}`);
        });
        check(`国别暴露无横向溢出`, () => assert.ok(ex.overflow <= 1,
          `溢出 ${ex.overflow}px`));

        /* 矿种。§1502 点名的就是钽锡钨金四种，而页面此前只在一处 hover 里
           提过它们。这一屏守两件事：四种矿的读数逐行等于数据，以及**那句
           「HHI 不是采购量」必须在**——Form SD 不含采购量，少了这句话，
           「钨 HHI 2161」会被读成「四成的钨来自中国」，那是数据不支持的。 */
        const MV = (NODES.mineralView || {}).rows || [];
        const REAL = MV.filter(r => r.mineral && r.mineral !== "未写明");
        if (REAL.length) {
          const mn = await evaluate(`(() => {
            const box = document.getElementById('minsec');
            if (!box || box.hidden) return { shown: false };
            return {
              shown: true,
              rows: [...box.querySelectorAll('.mrow')].map(r => ({
                mineral: (r.querySelector('.nm') || {}).textContent || '',
                n: (r.querySelector('.n') || {}).textContent || '',
                hhi: (r.querySelector('.hh') || {}).textContent || '',
                cov: (r.querySelector('.cc2') || {}).textContent || '',
                seen: r.getClientRects().length > 0
              })),
              lead: (document.getElementById('mineral-lead') || {}).textContent || '',
              foot: (document.getElementById('mineral-foot') || {}).textContent || '',
              overflow: Math.max(0,
                document.documentElement.scrollWidth - window.innerWidth)
            };
          })()`);
          check(`矿种区块已渲染（${REAL.length} 种）`, () => {
            assert.ok(mn.shown, "区块没显示");
            assert.equal(mn.rows.length, REAL.length,
              `页面 ${mn.rows.length} 行，数据 ${REAL.length} 种`);
          });
          check(`每种矿的条数、HHI、受涵盖国条数都等于数据`, () => {
            const bad = [];
            REAL.forEach(w => {
              const got = mn.rows.find(r => r.mineral === w.mineral);
              if (!got) { bad.push(`${w.mineral} 未渲染`); return; }
              const digits = t => (t || '').replace(/[^0-9]/g, '');
              if (digits(got.n).indexOf(String(w.edges)) !== 0)
                bad.push(`${w.mineral} 条数「${got.n}」应含 ${w.edges}`);
              const grp = n => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
              if (!got.hhi.includes(grp(w.hhi)))
                bad.push(`${w.mineral} HHI「${got.hhi}」应为 ${w.hhi}`);
              if (!got.hhi.includes(w.hhiBand))
                bad.push(`${w.mineral} 没印档位「${w.hhiBand}」`);
              if (digits(got.cov) !== String(w.coveredEdges))
                bad.push(`${w.mineral} 受涵盖国「${got.cov}」应为 ${w.coveredEdges}`);
            });
            assert.equal(bad.length, 0, bad.join("；"));
          });
          check(`矿种行都看得见`, () => {
            const blind = mn.rows.filter(r => !r.seen).length;
            assert.equal(blind, 0, `${blind}/${mn.rows.length} 行没有布局盒`);
          });
          /* 这一条是本屏的底线。数据里没有采购量，把 HHI 说成采购集中度
             就是凭这份数据讲了另一件事。 */
          check(`写明 HHI 不是采购量`, () => {
            assert.match(mn.foot, /不是采购量/, `页脚：${mn.foot.slice(0, 160)}`);
            assert.match(mn.foot, /不要求.*采购量|不含采购量/,
              `没说清 Form SD 本身不含这个字段：${mn.foot.slice(0, 160)}`);
          });
          check(`分档写明取自公开标准，不是自定阈值`, () => {
            assert.match(mn.lead, /司法部|联邦贸易委员会|横向合并指引/,
              `导语没写分档依据：${mn.lead.slice(0, 160)}`);
          });
          check(`矿种区块无横向溢出`, () => assert.ok(mn.overflow <= 1,
            `溢出 ${mn.overflow}px`));
        }

        /* 名单雷同度。**这是读懂上游集中度与上游重叠的前提，不是花絮。**
           实测中位 Jaccard 0.89、中位公司名单里每一家厂都被别家也列了——
           少了这句话，「被 56 家共同列入」和「重叠 349 家」都会被当成强信号，
           而真正的解释是这些名单本身就是同一份名录的再现。 */
        const SIM = NODES.listSimilarity || {};
        if (SIM.companies) {
          const sm = await evaluate(`(() => {
            const e = document.getElementById('sim-note');
            if (!e || e.hidden) return { shown: false };
            return { shown: true, text: e.textContent || '',
                     seen: e.getClientRects().length > 0 };
          })()`);
          check(`上游集中度旁写明名单雷同度`, () => {
            assert.ok(sm.shown && sm.seen,
              "没渲染或看不见——缺了它，这份榜单会被读成供应链耦合信号");
            assert.ok(sm.text.includes(SIM.medianJaccard.toFixed(2)),
              `没印中位重合度 ${SIM.medianJaccard.toFixed(2)}：${sm.text.slice(0, 140)}`);
            assert.ok(sm.text.includes(String(SIM.atLeast90)),
              `没印 ≥0.90 的家数 ${SIM.atLeast90}：${sm.text.slice(0, 140)}`);
          });
          check(`说清重叠大是常态而非信号`, () => {
            assert.match(sm.text, /常态|不是信号/, `实际：${sm.text.slice(0, 160)}`);
            assert.match(sm.text, /RMI|名录/,
              `没给出原因（同一份名录的再现）：${sm.text.slice(0, 160)}`);
          });
        }

        /* 受涵盖国家。**这是本板块唯一一处法定口径**：没有多德-弗兰克
           §1502 就没有 Form SD，也就没有这张图。此前页面一个字没提，
           读者看到「卢旺达 10 家厂」不知道那正是这套制度盯着的地方。

           两件事一起守：法定十国的清单不许在页面上被改动或漏印，以及
           **那句「不等于用了冲突矿产」必须在**——少了它，整屏会被读成
           对 104 家公司的指控，而数据根本不支持那个读法。 */
        const CC = NODES.coveredCountries || {};
        if ((CC.byCountry || []).length) {
          const cv = await evaluate(`(() => {
            const box = document.getElementById('cov1502');
            if (!box || box.hidden) return { shown: false };
            const rows = [...box.querySelectorAll('.cvrow')];
            return {
              shown: true,
              rows: rows.map(r => ({
                country: (r.querySelector('.nm') || {}).textContent || '',
                filers: ((r.querySelector('.n') || {}).textContent || '')
                  .replace(/[^0-9]/g, ''),
                edges: ((r.querySelector('.ed') || {}).textContent || '')
                  .replace(/[^0-9]/g, ''),
                badge: !!(r.querySelector('.cv')
                  && r.querySelector('.cv').getClientRects().length)
              })),
              lead: (document.getElementById('cov1502-lead') || {}).textContent || '',
              foot: (document.getElementById('cov1502-foot') || {}).textContent || '',
              // 国别暴露榜里被标记的行——标记要落在正确的行上，不能乱标
              marked: [...document.querySelectorAll('#expo-rows .exprow')]
                .filter(r => r.querySelector('.cv'))
                .map(r => (r.querySelector('.nm') || {}).textContent || ''),
              overflow: Math.max(0,
                document.documentElement.scrollWidth - window.innerWidth)
            };
          })()`);
          const SEEN = (CC.byCountry || []).filter(r => r.edges || r.smelters);
          check(`受涵盖国家区块已渲染`, () => assert.ok(cv.shown,
            "没渲染——这套数据的立法依据在页面上就消失了"));
          check(`逐行等于数据（${SEEN.length} 个出现过的国家）`, () => {
            assert.equal(cv.rows.length, SEEN.length,
              `页面 ${cv.rows.length} 行，数据 ${SEEN.length} 行`);
            const bad = [];
            SEEN.forEach(w => {
              const got = cv.rows.find(r => r.country === w.country);
              if (!got) { bad.push(`${w.country} 未渲染`); return; }
              if (got.edges !== String(w.edges))
                bad.push(`${w.country} 条数「${got.edges}」应为 ${w.edges}`);
              if (got.filers !== String(w.filerCount))
                bad.push(`${w.country} 申报人「${got.filers}」应为 ${w.filerCount}`);
            });
            assert.equal(bad.length, 0, bad.join("；"));
          });
          check(`每行的「受涵盖国」标记看得见`, () => {
            const blind = cv.rows.filter(r => !r.badge).length;
            assert.equal(blind, 0,
              `${blind}/${cv.rows.length} 行没有可见标记`);
          });
          check(`写明法定依据是 §1502`, () => {
            assert.match(cv.lead, /1502/, `导语：${cv.lead.slice(0, 140)}`);
            assert.ok(/刚果/.test(cv.lead),
              `导语没点名刚果：${cv.lead.slice(0, 140)}`);
          });
          /* 这一条是本屏的底线。数据说的是「这些公司披露了这些厂」，
             说成「这些公司用了冲突矿产」就是凭同一份数据讲了另一件事。 */
          check(`不把「出现在名单里」说成使用了冲突矿产`, () => {
            assert.match(cv.foot, /不等于.*冲突矿产|不等于该公司使用/,
              `页脚缺少这句界线：${cv.foot.slice(0, 160)}`);
            assert.match(cv.foot, /尽责调查/,
              `没说清 Form SD 要求的是尽责调查：${cv.foot.slice(0, 160)}`);
          });
          check(`国别暴露榜上的受涵盖国被就地标出`, () => {
            const want = new Set(SEEN.map(r => r.country));
            const wrong = cv.marked.filter(c => !want.has(c));
            assert.equal(wrong.length, 0,
              `标错了行：${wrong.join("、")}——非受涵盖国被标成了受涵盖国`);
            const shownCovered = ex.names.filter(c => want.has(c));
            assert.deepEqual(cv.marked.slice().sort(),
              shownCovered.slice().sort(),
              `榜上出现的受涵盖国 ${shownCovered.join("、")}，`
              + `标了 ${cv.marked.join("、") || "（无）"}`);
          });
          check(`受涵盖国家区块无横向溢出`, () => assert.ok(cv.overflow <= 1,
            `溢出 ${cv.overflow}px`));
        }
      } else {
        console.log("  [--] 国别暴露：本轮数据还没带 countryExposure，跳过"
          + "（数据流水线跑过之后这一段自动生效）");
      }

      /* 链间上下游。这一段守的不只是「画出来了」，更是**它没有冒充实测数据**：
         框架标签要在、区分那句话要在、每条线要写清流动的是什么。
         这块界线是本板块最重要的一条，被样式藏起来等同于没写。 */
      const LINKS = NODES.chainLinks || [];
      if (LINKS.length) {
        const upN = LINKS.filter(l => l.to === PICKED.id).length;
        const downN = LINKS.filter(l => l.from === PICKED.id).length;
        const flow = await evaluate(`(() => {
          const label = ${JSON.stringify(PICKED.label || "")};
          const chips = [...document.querySelectorAll('#chainpick .chip')];
          const before = document.getElementById('chainflow').hidden;
          chips.find(c => (c.querySelector('.cl') || {}).textContent === label).click();
          const box = document.getElementById('chainflow');
          const rows = [...box.querySelectorAll('.flowlink')];
          return {
            hiddenBeforePick: before,
            shown: !box.hidden,
            up: rows.filter(r => (r.querySelector('.ar') || {}).textContent === '←').length,
            down: rows.filter(r => (r.querySelector('.ar') || {}).textContent === '→').length,
            withFlow: rows.filter(r => ((r.querySelector('.fl') || {}).textContent || '').trim()).length,
            back: rows.filter(r => r.querySelector('.bk')).length,
            total: rows.length,
            tag: (box.querySelector('.cfhd .tag') || {}).textContent || '',
            warn: (box.querySelector('.cfwarn') || {}).textContent || '',
            tagVisible: !!(box.querySelector('.cfhd .tag') || {}).offsetParent,
            lineageChips: [...box.querySelectorAll('.lnstrip .lnchip:not(.me)')]
              .map(a => (a.childNodes[0] || {}).textContent || ''),
            lineageCap: (box.querySelector('.lncap') || {}).textContent || '',
            lineageScrolls: (() => {
              const st = box.querySelector('.lnstrip');
              return !!st && getComputedStyle(st).overflowX === 'auto';
            })(),
            overflow: Math.max(0, document.documentElement.scrollWidth - window.innerWidth)
          };
        })()`);
        check(`未选链时上下游块不显示`, () => assert.ok(flow.hiddenBeforePick));
        check(`选中「${PICKED.label}」后上下游块出现`, () => assert.ok(flow.shown));
        check(`上游 ${upN} 条 / 下游 ${downN} 条与数据一致`, () => {
          assert.equal(flow.up, upN, `页面上游 ${flow.up}`);
          assert.equal(flow.down, downN, `页面下游 ${flow.down}`);
        });
        check(`每条都写清流动的是什么，不是光画箭头`, () => assert.equal(
          flow.withFlow, flow.total, `${flow.total} 条里只有 ${flow.withFlow} 条写了`));
        // 逆向边不标出来，读者会以为分层排错了
        const backN = LINKS.filter(l => l.direction === "counterflow"
          && (l.from === PICKED.id || l.to === PICKED.id)).length;
        check(`逆向边标出「逆向」（本链 ${backN} 条）`, () => assert.equal(
          flow.back, backN, `页面标了 ${flow.back} 条`));
        check(`「产业结构框架」标签可见`, () => {
          assert.match(flow.tag, /产业结构框架/);
          assert.ok(flow.tagVisible, "标签在 DOM 里但不可见，等同于没写");
        });
        check(`写明它与实测关系不是一回事`, () => {
          assert.match(flow.warn, /不是一回事/);
          assert.match(flow.warn, /只有申报文件说了算/);
          assert.match(flow.warn, /不指名任何公司/);
        });
        // 完整路径是**在 77 条声明连线上做多跳可达**，不是新的断言。
      // 因此断言拿同一套连线在 Node 里独立算一遍，比对页面画出来的是不是那个集合。
      check(`完整路径与框架连线独立算出的结果一致`, () => {
        const links = (NODES.chainLinks || []).filter(l => l.direction !== "counterflow");
        const reach = (id, dir) => {
          const seen = new Set([id]); let front = [id];
          for (let i = 0; i < 12 && front.length; i++) {
            const next = [];
            front.forEach((cur) => links.forEach((l) => {
              const a = dir === "up" ? l.to : l.from;
              const b = dir === "up" ? l.from : l.to;
              if (a === cur && !seen.has(b)) { seen.add(b); next.push(b); }
            }));
            front = next;
          }
          seen.delete(id); return seen;
        };
        const want = new Set([...reach(PICKED.id, "up"), ...reach(PICKED.id, "down")]);
        const meta = {}; (NODES.chains || []).forEach(c => { meta[c.id] = c.label; });
        const wantLabels = new Set([...want].map(id => meta[id]).filter(Boolean));
        const got = new Set(flow.lineageChips);
        wantLabels.forEach((lb) => assert.ok(got.has(lb),
          `路径里少了 ${lb}（页面画了 ${got.size} 个，独立算出 ${wantLabels.size} 个）`));
        got.forEach((lb) => assert.ok(wantLabels.has(lb),
          `路径里多画了 ${lb}——多跳可达只能从那 77 条连线推出来`));
      });
      check(`路径说明写清这是框架、不是实测关系`, () => {
        assert.match(flow.lineageCap, /框架/);
        assert.ok(/不是实测/.test(flow.lineageCap),
          `说明没写清它不是实测关系：${flow.lineageCap}`);
      });
      check(`路径说明写明逆向边不参与推导`, () => {
        assert.match(flow.lineageCap, /逆向边/,
          `没说逆向边的处理：${flow.lineageCap}`);
      });
      check(`路径说明里没有漏出的星号`, () => assert.ok(!flow.lineageCap.includes("*"),
        `实际：${flow.lineageCap}`));
      check(`路径条在自身容器内滚动，页面不横向溢出`, () => {
        assert.ok(flow.lineageScrolls, "路径条没有设成容器内滚动");
      });
      check(`上下游块无横向溢出`, () => assert.ok(flow.overflow <= 1,
          `溢出 ${flow.overflow}px`));

        // 点上游一条要能跳过去，否则这张图只能看不能走
        const hop = await evaluate(`(() => {
          const row = document.querySelector('#chainflow .flowlink');
          const target = (row.querySelector('.nm') || {}).textContent;
          row.click();
          return { target,
            picked: (document.querySelector('#chainpick .chip.on .cl') || {}).textContent };
        })()`);
        check(`点上下游能跳到那条链`, () => assert.equal(hop.picked, hop.target,
          `点了「${hop.target}」，选中的却是「${hop.picked}」`));

        // 使能链没有连线是刻意的，必须给出解释而不是留一块空白
        const CROSS = Object.keys(NODES.chainCrossCutting || {});
        if (CROSS.length) {
          const crossRow = (NODES.chains || []).find(c => c.id === CROSS[0] && c.count > 0);
          if (crossRow) {
            const cx = await evaluate(`(() => {
              const label = ${JSON.stringify("")} ;
              const chips = [...document.querySelectorAll('#chainpick .chip')];
              const chip = chips.find(c => (c.querySelector('.cl') || {}).textContent
                === ${JSON.stringify(crossRow.label)});
              chip.click();
              const box = document.getElementById('chainflow');
              return { note: (box.querySelector('.cfnote') || {}).textContent || '',
                       rows: box.querySelectorAll('.flowlink').length };
            })()`);
            check(`横跨全链的「${crossRow.label}」给出解释而非留空`, () => {
              assert.match(cx.note, /横跨全部产业链|衔接每一段/,
                `实际：「${cx.note}」`);
            });
          }
        }

        // 这一段点了好几次 chip，页面还停在某条链上。后面的断言都按全池写，
        // 不复位就会在一张筛过的页面上跑——上一版正是这么炸的（Uncaught）。
        const reset = await evaluate(`(() => {
          const all = document.querySelector('#chainpick .chip');
          if (all) all.click();
          const on = document.querySelector('#chainpick .chip.on .cl');
          return { back: (on || {}).textContent || '' };
        })()`);
        check(`上下游测完复位回全池`, () => assert.match(reset.back, /全部产业链/,
          `复位后停在「${reset.back}」，后面的断言会在筛过的页面上跑`));
      }

      /* 方案 C · 真实流向。这是全站唯一一张带子宽度有实测含义的图，
         所以要守的不是「画出来了」，而是**画的是不是那个数**，
         以及**空缺有没有画出来**。 */
      const fl = await evaluate(`(() => {
        const sec = document.getElementById('flowsec');
        if (!sec || sec.hidden) return { shown: false };
        const box = document.getElementById('flow-chart');
        return {
          shown: true,
          ribbons: box.querySelectorAll('path[fill-opacity]').length,
          nodes: box.querySelectorAll('rect').length,
          titles: [...box.querySelectorAll('path title')].map(t => t.textContent),
          lead: document.getElementById('flow-lead').textContent,
          sub: document.getElementById('flow-sub').textContent,
          key: document.getElementById('flow-key').textContent,
          labels: [...box.querySelectorAll('text')].map(t => t.textContent),
          overflow: sec.scrollWidth - sec.clientWidth
        };
      })()`);

      check(`流向图已渲染`, () => assert.ok(fl.shown));
      check(`带子数与节点数都不为零`, () => {
        assert.ok(fl.ribbons > 0, `带子 ${fl.ribbons}`);
        assert.ok(fl.nodes > 0, `节点 ${fl.nodes}`);
      });
      check(`流向合计与 edgesTotal 一致`, () => {
        const want = NODES.coverage.edgesTotal;
        assert.ok(fl.lead.includes(String(want)),
          `文案「${fl.lead.slice(0, 60)}」未写出 ${want}`);
      });
      check(`每条带子可查到具体条数`, () => {
        assert.equal(fl.titles.length, fl.ribbons);
        assert.ok(fl.titles.every(t => /[0-9]+ 条$/.test(t)),
          `样例 ${JSON.stringify(fl.titles.slice(0, 2))}`);
      });
      check(`无出处的环节画成 0 条死头，不是筛掉`, () => {
        const dead = (NODES.flow && NODES.flow.stagesWithoutEdges) || [];
        if (!dead.length) return;
        assert.ok(fl.labels.some(t => t.indexOf("0 条") === 0),
          `无边环节 ${JSON.stringify(dead)} 未画出`);
      });
      check(`点明有多少家公司不在图中`, () => {
        const without = NODES.coverage.nodesTotal - NODES.coverage.nodesWithEdges;
        assert.ok(fl.key.includes(String(without)),
          `图注未写出 ${without}：「${fl.key.slice(0, 70)}」`);
      });
      check(`不把冶炼厂说成供应商`, () => {
        assert.ok(!/供应商/.test(fl.lead + fl.sub + fl.key),
          "流向图文案出现「供应商」——语义是「出现在供应链中」，间接、不含份额");
      });
      /* 上游集中度。这是本页少见的、完全不需要推断的读数，也正因如此最容易被
         读成「这 N 家都从它采购」。守两件事：数对得上，以及那句澄清在。 */
      const CONC = NODES.upstreamConcentration || [];
      if (CONC.length) {
        const listedN = Object.keys(NODES.edgeIndex || {}).length;
        const cc = await evaluate(`(() => {
          const sec = document.getElementById('concsec');
          if (!sec || sec.hidden) return { shown: false };
          const rows = [...sec.querySelectorAll('.concrow')];
          return {
            shown: true,
            count: rows.length,
            names: rows.map(r => (r.querySelector('.nm') || {}).textContent || ''),
            nums: rows.map(r => parseInt((r.querySelector('.n') || {}).textContent, 10)),
            marks: rows.filter(r => r.querySelector('.nm s')).length,
            lead: (document.getElementById('conc-lead') || {}).textContent || '',
            foot: (document.getElementById('conc-foot') || {}).textContent || '',
            overflow: Math.max(0, document.documentElement.scrollWidth - window.innerWidth)
          };
        })()`);
        check(`上游集中度已渲染（${CONC.length} 行）`, () => {
          assert.ok(cc.shown, "区块没显示");
          assert.equal(cc.count, CONC.length, `页面 ${cc.count} 行`);
        });
        check(`每行的家数取自数据且降序`, () => {
          assert.deepEqual(cc.nums, CONC.map(r => r.filerCount));
          const desc = cc.nums.every((n, i) => i === 0 || cc.nums[i - 1] >= n);
          assert.ok(desc, `不是降序：${JSON.stringify(cc.nums.slice(0, 8))}`);
        });
        check(`说清分母是有名单的 ${listedN} 家，不是全部 ${NODES.nodes.length} 家`, () => {
          assert.ok(cc.lead.includes(String(listedN)), `导语：${cc.lead}`);
          assert.match(cc.lead, /不是全部/);
        });
        check(`不把「共同列入」说成直接采购`, () => {
          assert.match(cc.foot, /不说明.*直接采购关系/);
          assert.match(cc.foot, /只会少算/);
        });
        // 同名两条是登记表刻意不合并的结果，页面必须标出来，否则看起来像 bug
        const dupNames = new Set();
        const seenName = new Map();
        CONC.forEach(r => {
          const k = (r.name || "").toLowerCase();
          if (seenName.has(k)) dupNames.add(k);
          seenName.set(k, true);
        });
        if (dupNames.size) {
          check(`同名多条被标出并解释（${dupNames.size} 组）`, () => {
            assert.ok(cc.marks >= dupNames.size * 2,
              `标记 ${cc.marks} 个，至少该有 ${dupNames.size * 2} 个`);
            assert.match(cc.foot, /不做同义合并/);
          });
        }
        /* 咽喉点反查。数据层给每行带了 filers，页面点开列出那几家。
           **这一段最要守的是语义没有跟着放大**：展开后仍然只是「共同列入」，
           不是采购关系，也不是这几家公司之间有往来。 */
        const CROW = CONC[0] || {};
        if (CROW.filers && CROW.filers.length) {
          const back = await evaluate(`(() => {
            const btn = document.querySelector('#conc-rows .expand');
            if (!btn) return null;
            btn.click();
            const box = document.querySelector('.concfilers');
            if (!box) return null;
            return {
              chips: [...box.querySelectorAll('.cf-chip s')].map(e => e.textContent),
              hrefs: [...box.querySelectorAll('.cf-chip')].map(
                a => a.getAttribute('href') || ''),
              cap: (box.querySelector('.cf-cap') || {}).textContent || '',
              expanded: btn.getAttribute('aria-expanded'),
              overflow: Math.max(0,
                document.documentElement.scrollWidth - window.innerWidth),
            };
          })()`);
          check(`集中度榜首可点开，列出的正是数据里那几家`, () => {
            assert.ok(back, "没有展开按钮或展开区");
            assert.deepEqual(back.chips.slice().sort(), CROW.filers.slice().sort(),
              `页面列了 ${back.chips.length} 家，数据里是 ${CROW.filers.length} 家`);
          });
          check(`每一家都点得进它自己的公司页`, () => {
            back.hrefs.forEach((h) => assert.match(h, /company\.html\?symbol=/, h));
          });
          check(`展开后语义没有放大：仍然只是「共同列入」`, () => {
            assert.match(back.cap, /共同列入/, `实际：${back.cap}`);
            assert.match(back.cap, /不表示/, `实际：${back.cap}`);
            assert.ok(back.cap.includes("采购关系"), `实际：${back.cap}`);
            assert.ok(back.cap.includes("业务往来"), `实际：${back.cap}`);
            assert.ok(!back.cap.includes("供应商"),
              `展开的说明里出现了「供应商」：${back.cap}`);
            assert.ok(!back.cap.includes("*"), `漏出星号：${back.cap}`);
          });
          check(`展开态可被辅助技术读到`, () => assert.equal(back.expanded, "true"));
          check(`展开后无横向溢出`, () => assert.ok(back.overflow <= 1,
            `溢出 ${back.overflow}px`));
        } else {
          console.log("  [--] 集中度反查：本轮数据还没带 filers，跳过"
            + "（数据流水线跑过之后这一段自动生效）");
        }

        check(`上游集中度无横向溢出`, () => assert.ok(cc.overflow <= 1,
          `溢出 ${cc.overflow}px`));
      }

      check(`流向区块无横向溢出`, () => assert.ok(fl.overflow <= 1,
        `溢出 ${fl.overflow}px`));

      /* 点开一个细分格，公司表就开在它所属的那条带子里面。
         这里同时守两件老规矩：逐家显示 SIC 与可核验的申报链接，
         以及「显示几家就得有几行」——口径对不上是过去抓到过的真 bug。 */
      const opened = await evaluate(`(() => {
        const band = document.querySelectorAll('.band')[1];
        const seg = band.querySelectorAll('.seg')[0];
        const m = seg.querySelector('.sc').textContent.match(/SIC ([0-9]{2}) . ([0-9]+) 家/);
        seg.click();
        const b2 = document.querySelectorAll('.band')[1];
        const panel = b2.querySelector('.panel');
        const rows = panel.querySelectorAll('tbody tr');
        const first = rows[0];
        const cells = first ? [...first.children].map(c => c.textContent.trim()) : [];
        return {
          stage: b2.dataset.stage,
          segCode: m ? m[1] : null,
          segCount: m ? Number(m[2]) : -1,
          hidden: panel.hidden,
          rowCount: rows.length,
          headers: [...panel.querySelectorAll('th')].map(t => t.textContent.trim()),
          sicShown: cells.length >= 4 && /^[0-9]{3,4}$/.test(cells[3]),
          evidenceLinks: panel.querySelectorAll('td.basis a[href^="https://"]').length,
          wrapScrolls: (() => {
            const w = panel.querySelector('.tablewrap');
            return !!w && getComputedStyle(w).overflowX === 'auto';
          })(),
          // 表必须开在自己那条带子里，不是页面别处的公共面板
          openElsewhere: [...document.querySelectorAll('.band')]
            .filter((b, i) => i !== 1 && !b.querySelector('.panel').hidden).length,
          pageOverflowAfterOpen:
            document.documentElement.scrollWidth - document.documentElement.clientWidth
        };
      })()`);

      check(`点开细分格后表就在该环节里`, () => {
        assert.equal(opened.hidden, false);
        assert.equal(opened.openElsewhere, 0, "别的环节也开着表");
      });
      check(`表头含「判定依据」`, () => assert.ok(opened.headers.includes("判定依据"),
        `实际表头 ${JSON.stringify(opened.headers)}`));
      check(`逐家显示 SIC 码`, () => assert.ok(opened.sicShown));
      check(`判定依据附可核验申报链接`, () => assert.ok(opened.evidenceLinks > 0,
        `链接数 ${opened.evidenceLinks}`));
      check(`宽表在自身容器内滚动`, () => assert.ok(opened.wrapScrolls));
      // 细分格写几家，表就得有几行（上限 60）。口径对不上是抓到过的真 bug。
      check(`细分家数与表格行数同口径`, () => assert.equal(
        opened.rowCount, Math.min(opened.segCount, 60),
        `细分写 ${opened.segCount} 家，表格 ${opened.rowCount} 行`));
      check(`展开后页面仍无横向溢出`, () => assert.ok(
        opened.pageOverflowAfterOpen <= 1, `溢出 ${opened.pageOverflowAfterOpen}px`));

      /* 方案 B 的其余守则：显示的家数必须和 nodes.json 对得上、
         再点一次能收起、表头点击看全环节。 */
      const seg = await evaluate(`(() => {
        const band = document.querySelectorAll('.band')[1];
        const stage = band.dataset.stage;
        const read = (b) => {
          const m = b.querySelector('.sc').textContent.match(/SIC ([0-9]{2}) . ([0-9]+) 家/);
          return m ? { code: m[1], n: Number(m[2]) } : null;
        };
        const before = [...band.querySelectorAll('.seg')].map(read);
        const openN = () => [...document.querySelectorAll('.panel')]
          .filter(p => !p.hidden).length;
        const bandAt = () => document.querySelectorAll('.band')[1];
        // 当前是第 0 格开着的状态（上一段点开的）
        const cap = bandAt().querySelector('.cap').textContent;
        const pressed = bandAt().querySelectorAll('.seg[aria-pressed="true"]').length;
        bandAt().querySelectorAll('.seg')[0].click();
        const afterSame = openN();
        bandAt().querySelector('.bandhd').click();
        const headerRows = bandAt().querySelectorAll('tbody tr').length;
        const clipped = [...bandAt().querySelectorAll('.seg')].filter(b => {
          const sn = b.querySelector('.sn'), sc = b.querySelector('.sc');
          return sn.scrollWidth > sn.clientWidth + 1
            || sc.scrollWidth > sc.clientWidth + 1;
        }).map(b => b.querySelector('.sn').textContent);
        bandAt().querySelector('.bandhd').click();
        return {
          stage, before, cap, pressed, afterSame, headerRows, clipped,
          rest: (band.querySelector('.segwrap .rest') || {}).textContent || "",
          allThree: bandAt().querySelectorAll('.perf2 b').length,
          overflow: document.documentElement.scrollWidth
            - document.documentElement.clientWidth
        };
      })()`);

      check(`细分家数与 nodes.json 逐组一致`, () => {
        const truth = {};
        NODES.nodes.filter(n => n.stage === seg.stage).forEach(n => {
          const k = n.sicMajor || "?";
          truth[k] = (truth[k] || 0) + 1;
        });
        const bad = seg.before.filter(g => g && truth[g.code] !== g.n)
          .map(g => `SIC ${g.code} 显示 ${g.n} 实际 ${truth[g.code]}`);
        assert.equal(bad.length, 0, bad.join("；"));
      });
      check(`筛选后表头写明是哪一组`, () => assert.ok(
        seg.cap.includes("SIC"), `表头「${seg.cap.slice(0, 60)}」`));
      check(`选中的格子有按下态`, () => assert.equal(seg.pressed, 1));
      check(`同一格再点一次收起`, () => assert.equal(seg.afterSame, 0));
      check(`点表头看该环节全部公司`, () => assert.ok(seg.headerRows > 0,
        `表头点开 ${seg.headerRows} 行`));
      check(`未单列的小类如实说明有多少家`, () => {
        if (!seg.rest) return;
        assert.ok(/[0-9]+ 家/.test(seg.rest), `「${seg.rest}」`);
      });
      // 表头上只留了等权，另两个口径降级到细分条下面——是降级不是删掉
      check(`三个涨跌口径在细分区给全`, () => assert.equal(seg.allThree, 3));
      check(`细分区无横向溢出`, () => assert.ok(seg.overflow <= 1,
        `溢出 ${seg.overflow}px`));
            check(`细分标签不被切断`, () => assert.equal(seg.clipped.length, 0,
        `被切断的：${JSON.stringify(seg.clipped)}`));
      check(`展开后页面仍无横向溢出`, () => assert.ok(opened.pageOverflowAfterOpen <= 1,
        `溢出 ${opened.pageOverflowAfterOpen}px`));
    }

    // ── 单家公司视图 ──────────────────────────────────────────────────
    // 这一页今天没有任何关系边，因此守的是「空的时候有没有说清楚为什么空」：
    // 真实数据与待接入结构必须一眼分得开，每处空缺都要给出原因。
    for (const [width, height] of VIEWPORTS) {
      console.log(`\n── 公司视图 ${width}×${height} ──`);
      await client.send("Emulation.setDeviceMetricsOverride",
        { width, height, deviceScaleFactor: 1, mobile: width < 700 }, sessionId);
      await client.send("Page.navigate",
        { url: `http://127.0.0.1:${port}/apps/supply-chain/company.html?symbol=AAPL` }, sessionId);
      await evaluate(`new Promise((done, fail) => {
        const deadline = Date.now() + 20000;
        (function poll() {
          if (document.querySelectorAll('.pick').length) return done(true);
          if (Date.now() > deadline) return fail(new Error('20 秒内未渲染出层级卡'));
          setTimeout(poll, 120);
        })();
      })`);

      const co = await evaluate(`(() => {
        const text = document.body.innerText;
        const picks = [...document.querySelectorAll('.pick')];
        const small = picks.filter(b => {
          const r = b.getBoundingClientRect();
          return r.width > 0 && (r.width < 44 || r.height < 44);
        }).length;
        // 点一张「待接入」卡：既测线型不变，也测点击不会销毁被聚焦的元素
        const demo = picks.find(b => b.classList.contains('demo'));
        let dashedWhenSelected = null, keptFocus = null;
        if (demo) {
          demo.focus();
          demo.click();
          const still = document.body.contains(demo);
          keptFocus = still && document.activeElement === demo;
          dashedWhenSelected = still ? getComputedStyle(demo).borderTopStyle : 'node-replaced';
        }
        return {
          title: document.title,
          identity: text.includes('苹果') && text.includes('3571') && text.includes('320193'),
          zeroEdgeStated: text.includes('尚未收录任何供应链关系'),
          notComplete: text.includes('不是完整供应链'),
          gapExplained: text.includes('没有免费数据源'),
          peers: [...document.querySelectorAll('.peer a')].map(a => a.textContent.trim()),
          peerLinksToCompany: [...document.querySelectorAll('.peer a')]
            .every(a => a.getAttribute('href').indexOf('company.html?symbol=') === 0),
          evidenceLinks: document.querySelectorAll('a[href^="https://www.sec.gov"], a[href^="https://data.sec.gov"]').length,
          undersized: small,
          bodyOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          demoBorderWhenSelected: dashedWhenSelected,
          keptFocus,
          gapAfterClick: document.body.innerText.includes('没有免费数据源'),
          segButtons: document.querySelectorAll('#seg button').length,
          // 图注不得压住层级卡——绝对定位曾经把它钉在第三张卡上
          noteOverlaps: (() => {
            const note = document.querySelector('.fignote');
            if (!note) return false;
            const nr = note.getBoundingClientRect();
            return picks.some(p => {
              const r = p.getBoundingClientRect();
              return nr.left < r.right && nr.right > r.left
                && nr.top < r.bottom && nr.bottom > r.top;
            });
          })()
        };
      })()`);

      check(`标题带公司名`, () => assert.ok(co.title.includes("苹果"), co.title));
      check(`身份为真实数据（SIC 3571 · CIK 320193）`, () => assert.ok(co.identity));
      check(`明说尚未收录任何关系`, () => assert.ok(co.zeroEdgeStated));
      check(`「不是完整供应链」声明可见`, () => assert.ok(co.notComplete));
      // 层级卡默认落在有来源的那一层，缺口原因点开待接入卡才显示——一次点击可达即可
      check(`点开待接入项后给出空缺原因`, () => assert.ok(co.gapAfterClick));
      check(`同行业公司为真实同 SIC 公司`, () => assert.ok(co.peers.length > 0,
        `同行数 ${co.peers.length}`));
      check(`同行链接指向公司视图`, () => assert.ok(co.peerLinksToCompany));
      check(`附可核验的 SEC 链接`, () => assert.ok(co.evidenceLinks > 0));
      check(`视图切换 2 个`, () => assert.equal(co.segButtons, 2));
      check(`触控区域不小于 44×44`, () => assert.equal(co.undersized, 0));
      check(`页面无横向溢出`, () => assert.ok(co.bodyOverflow <= 1, `溢出 ${co.bodyOverflow}px`));
      // 选中不得把待接入项的虚线变成实线——实线在这套视觉语言里意味着已核验
      check(`待接入项选中后仍是虚线`, () => assert.equal(co.demoBorderWhenSelected, "dashed"));
      // 点击不得销毁被聚焦的元素，否则键盘用户按回车后焦点就丢了
      check(`选中后焦点仍在被点的卡片上`, () => assert.equal(co.keptFocus, true));
      check(`图注不与层级卡重叠`, () => assert.equal(co.noteOverlaps, false));

      /* 公司页的所属产业链与上下游。守两件事：数与 nodes.json 一致，
         以及那句「不表示这家公司与上下游企业之间有供应关系」在——
         这一块最容易被读成「苹果的供应商是这些」，而那正是不能说的话。 */
      const AAPL = (NODES.nodes || []).find(n => n.symbol === "AAPL") || {};
      const MYCH = AAPL.chains || [];
      if (MYCH.length && (NODES.chainLinks || []).length) {
        const wantUp = new Set((NODES.chainLinks || [])
          .filter(l => MYCH.includes(l.to) && !MYCH.includes(l.from)).map(l => l.from));
        const wantDown = new Set((NODES.chainLinks || [])
          .filter(l => MYCH.includes(l.from) && !MYCH.includes(l.to)).map(l => l.to));
        const cb = await evaluate(`(() => {
          const box = document.querySelector('.chainbox');
          if (!box) return { shown: false };
          const links = [...box.querySelectorAll('.clink')];
          return {
            shown: true,
            pills: [...box.querySelectorAll('.cpill')].map(a => a.textContent),
            pillHrefs: [...box.querySelectorAll('.cpill')].map(a => a.getAttribute('href')),
            up: links.filter(a => (a.querySelector('.ar')||{}).textContent === '←').length,
            down: links.filter(a => (a.querySelector('.ar')||{}).textContent === '→').length,
            withFlow: links.filter(a => ((a.querySelector('.fl')||{}).textContent||'').trim()).length,
            total: links.length,
            warn: (box.querySelector('.cwarn') || {}).textContent || '',
            warnVisible: !!(box.querySelector('.cwarn') || {}).offsetParent
          };
        })()`, sessionId);
        check(`公司页显示所属产业链`, () => {
          assert.ok(cb.shown, "没渲染出所属产业链块");
          assert.equal(cb.pills.length, MYCH.length,
            `页面 ${cb.pills.length} 条链，数据说 ${MYCH.length} 条`);
        });
        check(`上游 ${wantUp.size} 条 / 下游 ${wantDown.size} 条与数据一致`, () => {
          assert.equal(cb.up, wantUp.size, `页面上游 ${cb.up}`);
          assert.equal(cb.down, wantDown.size, `页面下游 ${cb.down}`);
        });
        check(`每条上下游都写清流动的是什么`, () => assert.equal(
          cb.withFlow, cb.total, `${cb.total} 条里只有 ${cb.withFlow} 条写了`));
        check(`链名可点回总览页并带上 chain 参数`, () => assert.ok(
          cb.pillHrefs.every(h => /\?chain=/.test(h || "")),
          `实际 ${JSON.stringify(cb.pillHrefs)}`));
        check(`写明它不表示这家公司与上下游有供应关系`, () => {
          assert.ok(cb.warnVisible, "说明在 DOM 里但不可见，等同于没写");
          assert.match(cb.warn, /不表示这家公司与上下游企业之间有供应关系/);
          assert.match(cb.warn, /只能来自申报文件/);
        });
        // 星号会原样显示——上一轮在总览页栽过一次，这里一并钉住
        check(`说明里没有漏出的 Markdown 星号`, () => assert.ok(
          !/\*\*/.test(cb.warn), `实际：${cb.warn.slice(0, 60)}`));
      }
    }

    // ── 有冶炼厂数据的公司 ────────────────────────────────────────────
    // 上一节守的是「空的时候说清楚为什么空」，这一节守的是「有数据的时候别说过头」。
    // 冶炼厂那一层最容易出的错是把「出现在申报人供应链中」写成「是供应商」——
    // 前者是申报原义，后者是我们替申报人下的结论，而且是错的。
    const graph = NODES;
    const withEdges = Object.keys(graph.edgeIndex || {}).sort();
    if (!withEdges.length) {
      console.log("\n── 公司视图 · 有冶炼厂数据 ── [跳过] 目前没有任何公司有边文件");
    } else {
      const target = withEdges[0];
      const bundle = JSON.parse(await readFile(
        path.join(ROOT, "apps/supply-chain/edges", `${target}.json`), "utf8"));
      const expected = bundle.edges.length;
      const countries = new Set(bundle.edges.map(e => e.country || "未归类")).size;
      console.log(`\n── 公司视图 · 有冶炼厂数据（${target}，${expected} 条）──`);
      await client.send("Emulation.setDeviceMetricsOverride",
        { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false }, sessionId);
      await client.send("Page.navigate",
        { url: `http://127.0.0.1:${port}/apps/supply-chain/company.html?symbol=${target}` },
        sessionId);
      await evaluate(`new Promise((done, fail) => {
        const deadline = Date.now() + 20000;
        (function poll() {
          if (document.querySelectorAll('#smelters .sm').length) return done(true);
          if (Date.now() > deadline) return fail(new Error('20 秒内未渲染出冶炼厂清单'));
          setTimeout(poll, 150);
        })();
      })`);

      const ed = await evaluate(`(() => {
        const text = document.body.innerText;
        const picks = [...document.querySelectorAll('.pick')];
        const smelterCard = picks[2];
        // 冶炼厂清单里每一条的名字都应当是能点开原始申报的链接
        const items = document.querySelectorAll('#smelters .sm');
        const rows = document.querySelectorAll(
          '#smelters a[href^="https://www.sec.gov/Archives"]');
        // 线型必须在切视图之前读：切到地理视图会重建 #fig，层级卡就成了游离节点，
        // getComputedStyle 对游离节点返回空串——那不是「线型不对」，是根本没量到。
        const smelterBorder = smelterCard
          ? getComputedStyle(smelterCard).borderTopStyle : 'missing';
        const tierOneBorder = picks[0]
          ? getComputedStyle(picks[0]).borderTopStyle : 'missing';
        const smelterText = smelterCard ? smelterCard.innerText : '';
        // 分批展开的三件事要在切地理视图之前读完：按钮文案、按钮印的总数、
        // 点开之后的真实条数。切视图会重建卡片，之后再去点按钮读到的是另一棵树。
        const moreBtns = (kw) => {
          const b = [...document.querySelectorAll('#smelters .smmore')]
            .find((x) => x.textContent.indexOf(kw) >= 0);
          return b || null;
        };
        const moreEl = moreBtns('还有');
        const allEl = moreBtns('全部展开');
        const moreBtn = moreEl ? moreEl.textContent.trim() : '';
        const allBtn = allEl ? allEl.textContent.trim() : '';
        if (allEl) allEl.click();
        const afterExpandAll = document.querySelectorAll('#smelters .sm').length;
        // 切到地理视图
        const geoBtn = [...document.querySelectorAll('#seg button')]
          .find(b => b.textContent.indexOf('地理') >= 0);
        if (geoBtn) geoBtn.click();
        const geoText = document.body.innerText;
        return {
          statesSemantics: text.indexOf('出现在申报人的供应链中') >= 0
            || text.indexOf('出现在该公司 Form SD 申报供应链中') >= 0,
          // 红线：不得把冶炼厂说成这家公司的供应商
          callsThemSuppliers: text.indexOf('冶炼厂是') >= 0
            || text.indexOf('的供应商包括') >= 0,
          notComplete: text.indexOf('不是完整供应链') >= 0,
          smelterCardSolid: smelterBorder,
          smelterCardText: smelterText,
          listLinks: rows.length,
          listItems: items.length,
          moreBtn, allBtn, afterExpandAll,
          firstLink: rows.length ? rows[0].getAttribute('href') : '',
          tierOneStillDashed: tierOneBorder,
          geoShowsCountries: geoText.indexOf('个国家／地区') >= 0,
          geoText: geoText.slice(0, 400),
          bodyOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
        };
      })()`);

      check(`覆盖率声明写出真实条数`, () => assert.ok(
        ed.smelterCardText.includes(`已收录 ${expected} 条`),
        `卡片文字：${ed.smelterCardText.replace(/\n/g, " / ")}`));
      check(`语义写的是「出现在供应链中」`, () => assert.ok(ed.statesSemantics));
      check(`没有把冶炼厂说成供应商`, () => assert.equal(ed.callsThemSuppliers, false));
      check(`「不是完整供应链」声明仍在`, () => assert.ok(ed.notComplete));
      // 线型跟着数据走：这一层有已核验数据了才是实线
      check(`有数据的冶炼厂层是实线`, () => assert.equal(ed.smelterCardSolid, "solid"));
      // 但一级供应商仍然没有数据源，必须还是虚线
      check(`无数据源的一级供应商仍是虚线`, () => assert.equal(ed.tierOneStillDashed, "dashed"));
      // 349 条在手机上一列摊开是 22,201px（65 屏）。改为分批展开——
      // **渐进展开与截断的差别在于说不说得出剩下多少**，所以断言盯的是：
      // 默认只画一批、按钮上写清还剩多少、点「全部展开」后一条不少。
      check(`清单默认分批展开，不是一次摊开 ${expected} 条`, () => {
        assert.ok(ed.listItems < expected,
          `默认就画了 ${ed.listItems} 条，没有分批`);
        assert.ok(ed.listItems > 0, "一条都没画");
      });
      check(`按钮上写清还剩多少家，不是默默截断`, () => {
        assert.match(ed.moreBtn, /还有\s*\d+\s*家/, `按钮文案：${ed.moreBtn}`);
        const left = parseInt((ed.moreBtn.match(/还有\s*(\d+)\s*家/) || [])[1], 10);
        assert.equal(left, expected - ed.listItems,
          `按钮说还有 ${left} 家，实际还剩 ${expected - ed.listItems} 家`);
      });
      check(`「一次全部展开」写明总数并且真的全展开`, () => {
        assert.ok(ed.allBtn.includes(String(expected)),
          `按钮没印总数 ${expected}：${ed.allBtn}`);
        assert.equal(ed.afterExpandAll, expected,
          `点全部展开后只有 ${ed.afterExpandAll} 条，应为 ${expected}`);
      });
      check(`已画出的每条都能点开原始申报`, () => assert.equal(ed.listLinks, ed.listItems,
        `${expected} 条里只有 ${ed.listLinks} 条可点开`));
      check(`出处链接指向 SEC 申报归档`, () => assert.ok(
        ed.firstLink.startsWith("https://www.sec.gov/Archives/"), ed.firstLink));
      check(`地理视图按国别汇总（${countries} 个）`, () => assert.ok(ed.geoShowsCountries,
        ed.geoText.slice(0, 120)));
      check(`页面无横向溢出`, () => assert.ok(ed.bodyOverflow <= 1,
        `溢出 ${ed.bodyOverflow}px`));
      const coState = await evaluate(`(() => {
        const e = document.getElementById('state');
        const errs = (window.__pageErrors || []).slice(0, 4);
        return { shown: !!(e && !e.hidden && e.offsetHeight > 0),
                 cls: (e && e.className) || '',
                 text: ((e && e.textContent) || '').trim().slice(0, 160), errs };
      })()`);
      check(`公司页渲染没有中途失败`, () => {
        assert.equal(coState.shown, false,
          `显示了状态横幅（${coState.cls}）：${coState.text}`);
        assert.deepEqual(coState.errs, [], `未捕获异常：${coState.errs.join(" | ")}`);
      });

      /* 公司页的上游冶炼厂重叠。这是全站唯一一条公司 ↔ 公司的关系，
         最容易被读成「苹果的供应商是这些」——而那正是不能说的话。 */
      let PEERS = null;
      try {
        PEERS = JSON.parse(await readFile(path.join(ROOT, "apps/supply-chain/peers.json"), "utf8"));
      } catch { /* 还没算过就跳过这一组 */ }
      const myPeer = PEERS && (PEERS.companies || {})[target];
      if (myPeer && (myPeer.peers || []).length) {
        const pb = await evaluate(`(() => {
          const box = document.querySelector('.peerbox');
          if (!box) return { shown: false };
          const rows = [...box.querySelectorAll('.peer')];
          return {
            shown: true,
            count: rows.length,
            shared: rows.map(a => parseInt((a.querySelector('.sh')||{}).textContent, 10)),
            hrefs: rows.map(a => a.getAttribute('href')),
            cap: (box.querySelector('.pcap') || {}).textContent || '',
            topShared: box.querySelectorAll('.pshare').length,
            warn: (box.querySelector('.pwarn') || {}).textContent || '',
            warnVisible: !!(box.querySelector('.pwarn') || {}).offsetParent
          };
        })()`, sessionId);
        check(`${target} 页显示上游重叠（${myPeer.peers.length} 家）`, () => {
          assert.ok(pb.shown, "没渲染出上游重叠块");
          assert.equal(pb.count, myPeer.peers.length, `页面 ${pb.count} 行`);
        });
        check(`重叠数取自 peers.json，且降序`, () => {
          assert.deepEqual(pb.shared, myPeer.peers.map(p => p.shared));
          const desc = pb.shared.every((n, i) => i === 0 || pb.shared[i - 1] >= n);
          assert.ok(desc, `不是降序：${JSON.stringify(pb.shared)}`);
        });
        check(`重叠不超过本公司名单长度 ${myPeer.total}`, () => {
          const over = pb.shared.filter(n => n > myPeer.total);
          assert.equal(over.length, 0, `有 ${over.length} 行超过`);
        });
        check(`导语写明本公司名单多大、共有多少家重叠`, () => {
          assert.ok(pb.cap.includes(String(myPeer.total)), `导语：${pb.cap}`);
          assert.ok(pb.cap.includes(String(myPeer.peerCount)));
        });
        check(`可点进对方公司页`, () => assert.ok(
          pb.hrefs.every(h => /company\.html\?symbol=/.test(h || "")),
          `实际 ${JSON.stringify(pb.hrefs.slice(0, 3))}`));
        check(`写明重叠不表示业务往来`, () => {
          assert.ok(pb.warnVisible, "说明在 DOM 里但不可见，等同于没写");
          assert.match(pb.warn, /不表示两家之间有业务往来/);
          assert.match(pb.warn, /只会少算/);
        });
        check(`上游重叠的说明里没有漏出的星号`, () => assert.ok(
          !/\*\*/.test(pb.warn), `实际：${pb.warn.slice(0, 60)}`));
      }


      // 清单进主栏之后要在窄屏上复核一遍：几百条多列排布最容易撑破布局，
      // 而这一段是新加的，之前三档宽度的断言没覆盖到它。
      for (const [width, height] of [[360, 780], [768, 1024]]) {
        await client.send("Emulation.setDeviceMetricsOverride",
          { width, height, deviceScaleFactor: 1, mobile: width < 700 }, sessionId);
        await client.send("Page.navigate",
          { url: `http://127.0.0.1:${port}/apps/supply-chain/company.html?symbol=${target}` },
          sessionId);
        await evaluate(`new Promise((done, fail) => {
          const deadline = Date.now() + 20000;
          (function poll() {
            if (document.querySelectorAll('#smelters .sm').length) return done(true);
            if (Date.now() > deadline) return fail(new Error('20 秒内未渲染出冶炼厂清单'));
            setTimeout(poll, 150);
          })();
        })`);
        const narrow = await evaluate(`(() => {
          const box = document.querySelector('#smelters');
          const more = [...document.querySelectorAll('#smelters .smmore')]
            .find((x) => x.textContent.indexOf('还有') >= 0);
          return {
            items: document.querySelectorAll('#smelters .sm').length,
            more: more ? more.textContent.trim() : '',
            page: document.documentElement.scrollWidth - document.documentElement.clientWidth,
            box: box ? box.scrollWidth - box.clientWidth : 0
          };
        })()`);
        // 窄屏同样分批。这一条要守的不是「画满 349」，而是**画出来的那些
        // 加上按钮说的剩余数，等于总数**——分批不能把总量说小。
        check(`${width}px 分批展开后条数与按钮口径自洽`, () => {
          assert.ok(narrow.items > 0, "窄屏一条都没画");
          assert.ok(narrow.items <= expected,
            `窄屏画了 ${narrow.items} 条，超过总数 ${expected}`);
          if (narrow.items < expected) {
            assert.match(narrow.more || "", /还有\s*\d+\s*家/,
              `窄屏按钮没写剩余数：${narrow.more}`);
            const left = parseInt(((narrow.more || "").match(/还有\s*(\d+)\s*家/) || [])[1], 10);
            assert.equal(narrow.items + left, expected,
              `窄屏画 ${narrow.items} + 按钮说剩 ${left} ≠ 总数 ${expected}`);
          }
        });
        check(`${width}px 页面无横向溢出`, () => assert.ok(narrow.page <= 1,
          `溢出 ${narrow.page}px`));
        check(`${width}px 清单容器无横向溢出`, () => assert.ok(narrow.box <= 1,
          `溢出 ${narrow.box}px`));
      }

      // 清单筛选。**筛选只能取子集，不能把总量说小**——标题里必须同时印
      // 「筛出多少 / 共多少」，并且说清隐藏的那些仍在申报里。
      console.log("\n── 公司视图 · 冶炼厂清单筛选 ──");
      await client.send("Page.navigate",
        { url: `http://127.0.0.1:${port}/apps/supply-chain/company.html?symbol=${target}` },
        sessionId);
      const flt = await evaluate(`new Promise((done) => {
        const deadline = Date.now() + 20000;
        (function poll() {
          const bar = document.querySelector('.smfilt');
          const items = document.querySelectorAll('.smelters .sm');
          if (bar && items.length) {
            const groups = [...document.querySelectorAll('.smfilt .fg')].map((g) => ({
              label: (g.querySelector('.lb') || {}).textContent || '',
              buttons: [...g.querySelectorAll('.fb')].map((b) => b.textContent.trim()),
              more: (g.querySelector('.more') || {}).textContent || '',
            }));
            // 点第一个真正的筛选按钮。**不能用 :not(:first-child) 跳过「全部」**——
            // .fg 的第一个子节点是标签 span，「全部」是第二个，那样选中的正是
            // 「全部」，点了等于没点，断言会以为功能坏了。用未按下状态来选。
            const first = document.querySelector('.smfilt .fg .fb[aria-pressed="false"]');
            // 清单改成分批展开之后，**DOM 里的条数不再等于总数**。拿当前批次的
            // 60 当「筛前共多少」，断言就会反过来逼标题去印 60——那正是这一组
            // 要拦的错。所以每次数之前先点「一次全部展开」，数到底。
            const expandAll = () => {
              const b = [...document.querySelectorAll('.smelters .smmore')]
                .find((x) => x.textContent.indexOf('全部展开') >= 0);
              if (b) b.click();
            };
            const leftText = () => {
              const b = [...document.querySelectorAll('.smelters .smmore')]
                .find((x) => x.textContent.indexOf('还有') >= 0);
              return b ? b.textContent.trim() : '';
            };
            const beforeVisible = items.length;
            const beforeTitle = (document.querySelector('.smelters h3') || {}).textContent || '';
            expandAll();
            const grandTotal = document.querySelectorAll('.smelters .sm').length;
            first.click();
            setTimeout(() => {
              // 换筛选会把批次重置回第一批，所以这里先量分批口径，再展开数总数
              const afterVisible = document.querySelectorAll('.smelters .sm').length;
              const afterMore = leftText();
              const afterTitle =
                (document.querySelector('.smelters h3') || {}).textContent || '';
              expandAll();
              done({
                groups, beforeVisible, grandTotal, beforeTitle,
                chosen: first.textContent.trim(),
                afterVisible, afterMore, afterTitle,
                afterTotal: document.querySelectorAll('.smelters .sm').length,
                clearNote: (document.querySelector('.smclear') || {}).textContent || '',
                overflow: Math.max(0,
                  document.documentElement.scrollWidth - window.innerWidth),
              });
            }, 400);
            return;
          }
          if (Date.now() > deadline) return done(null);
          setTimeout(poll, 120);
        })();
      })`);
      check(`清单有矿种与国别两组筛选`, () => {
        assert.ok(flt, "筛选条没渲染出来");
        const labels = flt.groups.map((g) => g.label);
        assert.ok(labels.includes("矿种") && labels.includes("国别"),
          `实际分组：${labels.join("/")}`);
      });
      check(`展开到底数得出申报里的全部 ${expected} 条`, () => assert.equal(
        flt.grandTotal, expected,
        `点完「一次全部展开」只数到 ${flt.grandTotal} 条，申报里有 ${expected} 条`));
      check(`筛选后只剩子集，且确实变少了`, () => {
        assert.ok(flt.afterTotal > 0, "筛完一条不剩");
        assert.ok(flt.afterTotal < flt.grandTotal,
          `筛前 ${flt.grandTotal} 条、筛后 ${flt.afterTotal} 条——没筛掉任何东西`);
      });
      check(`标题同时印「筛出多少 / 共多少」，不把总量说小`, () => {
        // 「共多少」必须是申报里的总数，不能是当前批次画出来的那几条
        assert.match(flt.afterTitle, /筛出/, `筛后标题：${flt.afterTitle}`);
        assert.ok(flt.afterTitle.includes(String(expected)),
          `筛后标题没印总数 ${expected}：${flt.afterTitle}`);
        assert.ok(flt.afterTitle.includes(String(flt.afterTotal)),
          `筛后标题没印筛出数 ${flt.afterTotal}：${flt.afterTitle}`);
      });
      check(`筛完仍然分批，按钮口径跟着筛后总数走`, () => {
        assert.ok(flt.afterVisible <= flt.afterTotal,
          `筛后画了 ${flt.afterVisible} 条，超过筛后总数 ${flt.afterTotal}`);
        if (flt.afterTotal > flt.afterVisible) {
          assert.match(flt.afterMore, /还有\s*\d+\s*家/, `筛后按钮：${flt.afterMore}`);
          const left = parseInt((flt.afterMore.match(/还有\s*(\d+)\s*家/) || [])[1], 10);
          assert.equal(flt.afterVisible + left, flt.afterTotal,
            `筛后画 ${flt.afterVisible} + 按钮说剩 ${left} ≠ 筛后总数 ${flt.afterTotal}`);
        }
      });
      check(`说清隐藏的那些仍在申报里`, () => {
        assert.match(flt.clearNote, /仍在这份申报里/, `实际：${flt.clearNote}`);
        assert.ok(flt.clearNote.includes(String(expected - flt.afterTotal)),
          `没说隐藏了多少家：${flt.clearNote}`);
      });
      check(`取值多于上限时说明「另有 N 个未单列」而不是默默截断`, () => {
        const country = flt.groups.filter((g) => g.label === "国别")[0];
        if (!country || !country.more) return;      // 没超上限就不查
        assert.match(country.more, /另有 \d+ 个未单列/, `实际：${country.more}`);
      });
      check(`筛选后无横向溢出`, () => assert.ok(flt.overflow <= 1,
        `溢出 ${flt.overflow}px`));
    }

    /* 按 CID 回填的国别。丰田、飞利浦、安波福那几份申报的国别列没被抽取器
       认出来，98% 的条目原本是空的——`parse.countryRatio` 早记着 0.02，
       而页面照印一屏「未写明」，一个字不解释。

       现在按 RMI CID 从登记表补上了（同一个编号就是同一座厂），但**那不是
       本份申报写的**，所以每条补过的都要标出来。守两件事：补回来的国别
       真的显示了，以及那一格的来源标记看得见——不标的话读者会以为丰田
       那份申报里真写了国别。 */
    let BACKFILLED = null;
    for (const sym of Object.keys(NODES.edgeIndex || {})) {
      let bundle;
      try {
        bundle = JSON.parse(await readFile(
          path.join(ROOT, `apps/supply-chain/edges/${sym}.json`), "utf8"));
      } catch { continue; }
      const n = (bundle.edges || [])
        .filter(e => e.countryBasis === "rmi-registry").length;
      // 取补得最多的那家，样本大、断言才有分量
      if (n && (!BACKFILLED || n > BACKFILLED.n)) BACKFILLED = { symbol: sym, n };
    }
    if (BACKFILLED) {
      console.log(`\n── 公司视图 · 国别按 CID 回填（${BACKFILLED.symbol}，`
        + `${BACKFILLED.n} 条）──`);
      await client.send("Page.navigate", { url: `http://127.0.0.1:${port}`
        + `/apps/supply-chain/company.html?symbol=${BACKFILLED.symbol}` }, sessionId);
      const bf = await evaluate(`new Promise((done) => {
        const deadline = Date.now() + 20000;
        (function poll() {
          const items = document.querySelectorAll('#smelters .grid .meta');
          if (items.length) {
            const marks = [...document.querySelectorAll('#smelters .grid .meta .cid')]
              .filter(e => (e.textContent || '').indexOf('登记表') >= 0);
            return done({
              rows: items.length,
              marks: marks.length,
              seen: marks.filter(e => e.getClientRects().length > 0).length,
              titled: marks.filter(e => /RMI|登记表/.test(e.title || '')).length,
              unknown: [...items].filter(
                e => /国别未写明/.test(e.textContent || '')).length,
              overflow: Math.max(0,
                document.documentElement.scrollWidth - window.innerWidth)
            });
          }
          if (Date.now() > deadline) return done({ rows: 0 });
          setTimeout(poll, 120);
        })();
      })`);
      check(`回填过的公司页真的印出了国别`, () => {
        assert.ok(bf.rows > 0, "冶炼厂清单没渲染");
        assert.ok(bf.unknown < bf.rows,
          `${bf.rows} 条里 ${bf.unknown} 条仍是「国别未写明」——回填没生效`);
      });
      check(`补来的国别标出依据，且标记看得见`, () => {
        assert.ok(bf.marks > 0, "一条都没标「国别据登记表」——"
          + "读者会以为这是本份申报写的");
        assert.equal(bf.marks - bf.seen, 0,
          `${bf.marks - bf.seen} 个标记有文本却没有布局盒`);
        assert.equal(bf.marks - bf.titled, 0, "标记没有说明来源的悬浮文字");
      });
      check(`回填后公司页无横向溢出`, () => assert.ok(bf.overflow <= 1,
        `溢出 ${bf.overflow}px`));
    }

    // 外国私人发行人这一池：没有市值、没有板块。页面必须说清那是口径如此，
    // 不是取数失败——什么都不写的话读者只会以为数据缺了一块。
    console.log("\n── 公司视图 · 外国私人发行人 ──");
    await client.send("Page.navigate",
      { url: `http://127.0.0.1:${port}/apps/supply-chain/company.html?symbol=TSM` }, sessionId);
    const fpi = await evaluate(`new Promise((done) => {
      const deadline = Date.now() + 20000;
      (function poll() {
        const p = document.getElementById('c-pool');
        const zh = document.getElementById('c-zh');
        if (zh && zh.textContent && p) {
          return done({
            shown: !p.hidden,
            text: p.textContent || "",
            facts: (document.getElementById('c-facts') || {}).textContent || "",
            overflow: Math.max(0, document.documentElement.scrollWidth - window.innerWidth),
          });
        }
        if (Date.now() > deadline) return done({ shown: false, text: "", facts: "", overflow: 0 });
        setTimeout(poll, 120);
      })();
    })`);
    check(`外国发行人页显示所属池的说明`, () => assert.ok(fpi.shown,
      "c-pool 没显示——这一池没有市值也没有板块，不说明就是个哑缺口"));
    check(`说明写清没有市值是口径而非取数失败`, () => assert.ok(
      fpi.text.includes("不是取数失败") && fpi.text.includes("外国私人发行人"),
      `实际：${fpi.text.slice(0, 80)}`));
    check(`说明里写明国别取自哪个字段`, () => assert.ok(
      /注册地|备案地址|没有可用的地区字段/.test(fpi.text),
      `实际：${fpi.text.slice(0, 80)}`));
    check(`说明里没有漏出的星号`, () => assert.ok(!fpi.text.includes("*"),
      `实际：${fpi.text.slice(0, 80)}`));
    check(`身份条不显示市值（这一池没有站内行情）`, () => assert.ok(
      !fpi.facts.includes("市值"), `实际：${fpi.facts.slice(0, 80)}`));
    check(`外国发行人页无横向溢出`, () => assert.ok(fpi.overflow <= 1,
      `溢出 ${fpi.overflow}px`));

    /* 注册在离岸法域的那一批（1,193 家里 422 家注册地 ≠ 经营地）。

       **这一段守的是两个页面对同一家公司说同一句话。** 总览页的国别汇总改用
       经营地之后（开曼 340 家折回中国 236、新加坡 79…），公司页一度还只印
       注册地——读者在总览页看到「中国 236 家」，点进来却写着「国别 开曼群岛」。
       两处都印注册地至少是一致的错；一处经营地一处注册地是自相矛盾，更糟。

       注册地不删：它是备案事实，而且「注册在开曼」本身是信息（控股架构）。
       两个都印、各自标清是什么。 */
    const OFFSHORE_ONE = (NODES.nodes || []).find(
      (n) => n.offshoreIncorporation && n.geoCountry && n.geoCountry !== n.country);
    if (OFFSHORE_ONE) {
      console.log(`\n── 公司视图 · 离岸注册（${OFFSHORE_ONE.symbol}）──`);
      await client.send("Page.navigate", { url:
        `http://127.0.0.1:${port}/apps/supply-chain/company.html?symbol=${OFFSHORE_ONE.symbol}` },
        sessionId);
      const off = await evaluate(`new Promise((done) => {
        const deadline = Date.now() + 20000;
        (function poll() {
          const st = document.getElementById('state');
          if (st && st.hidden) {
            return done({
              facts: (document.getElementById('c-facts') || {}).textContent || "",
              pool: (document.getElementById('c-pool') || {}).textContent || "",
              overflow: Math.max(0,
                document.documentElement.scrollWidth - window.innerWidth),
            });
          }
          if (Date.now() > deadline) return done({ facts: "", pool: "", overflow: 0 });
          setTimeout(poll, 120);
        })();
      })`);
      check(`离岸注册的公司页同时印经营地与注册地`, () => {
        assert.match(off.facts, /经营地/, `身份条没有「经营地」：${off.facts.slice(0, 90)}`);
        assert.match(off.facts, /注册地/, `身份条没有「注册地」：${off.facts.slice(0, 90)}`);
        assert.ok(off.facts.includes(OFFSHORE_ONE.geoCountry),
          `没印经营地 ${OFFSHORE_ONE.geoCountry}：${off.facts.slice(0, 90)}`);
        assert.ok(off.facts.includes(OFFSHORE_ONE.country),
          `没印注册地 ${OFFSHORE_ONE.country}：${off.facts.slice(0, 90)}`);
      });
      check(`并说清为什么不拿注册地当国别，以及与总览页口径一致`, () => {
        assert.match(off.pool, /只做登记|回答不了/, `实际：${off.pool.slice(0, 120)}`);
        assert.match(off.pool, /总览页.*(一致|也是)/,
          `没说清与总览页同口径：${off.pool.slice(0, 140)}`);
      });
      check(`离岸公司页无横向溢出`, () => assert.ok(off.overflow <= 1,
        `溢出 ${off.overflow}px`));
    }

    // 未知代码要有明确说明，不能白屏
    console.log("\n── 公司视图 · 未知代码 ──");
    await client.send("Page.navigate",
      { url: `http://127.0.0.1:${port}/apps/supply-chain/company.html?symbol=NOSUCH` }, sessionId);
    const unknown = await evaluate(`new Promise((done) => {
      const deadline = Date.now() + 15000;
      (function poll() {
        const s = document.getElementById('state');
        if (s && !s.hidden && s.textContent.length > 10) return done(s.textContent);
        if (Date.now() > deadline) return done("");
        setTimeout(poll, 120);
      })();
    })`);
    check(`未知代码给出明确说明`, () => assert.ok(unknown.includes("NOSUCH"),
      `实际提示：${unknown.slice(0, 60)}`));

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
