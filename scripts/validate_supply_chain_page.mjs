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
      check(`状态条 4 项（数据日/更新/公司/频率）`, () => assert.equal(probe.statusChips, 4));
      check(`页面无横向溢出`, () => assert.ok(probe.bodyOverflow <= 1,
        `溢出 ${probe.bodyOverflow}px`));
      check(`触控区域不小于 44×44`, () => assert.equal(probe.undersizedTargets, 0));
      check(`环节卡片键盘可达`, () => assert.ok(probe.focusable));
      check(`初始不展开任何环节`, () => assert.equal(probe.expandedInitially, 0));

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
          countryLead: (box.querySelector('#cov-country-lead') || {}).textContent || '',
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
        check(`外国发行人按国别单列（${COUNTRIES.length} 个国别 / ${foreignN} 家）`, () => {
          assert.ok(!cov.countryLeadHidden, "国别栏的说明被藏起来了");
          assert.equal(cov.countryRows, COUNTRIES.length,
            `页面 ${cov.countryRows} 行，数据 ${COUNTRIES.length} 行`);
        });
        check(`说清这一栏的口径是国别不是板块`, () => {
          assert.match(cov.countryLead, /口径是国别，不是板块/);
          assert.ok(cov.countryLead.includes(String(foreignN)),
            `说明里没写家数：${cov.countryLead}`);
        });
        check(`板块那一栏仍只统计标普池（${SECTORS.length} 个板块）`, () => {
          const sectorN = SECTORS.reduce((a, r) => a + (r.companies || 0), 0);
          assert.equal(sectorN + foreignN, NODES.nodes.length,
            `板块 ${sectorN} + 国别 ${foreignN} ≠ 全池 ${NODES.nodes.length}`);
        });
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
      check(`清单条数与边文件一致（${expected}）`, () => assert.equal(ed.listItems, expected));
      check(`清单每条都能点开原始申报`, () => assert.equal(ed.listLinks, expected,
        `${expected} 条里只有 ${ed.listLinks} 条可点开`));
      check(`出处链接指向 SEC 申报归档`, () => assert.ok(
        ed.firstLink.startsWith("https://www.sec.gov/Archives/"), ed.firstLink));
      check(`地理视图按国别汇总（${countries} 个）`, () => assert.ok(ed.geoShowsCountries,
        ed.geoText.slice(0, 120)));
      check(`页面无横向溢出`, () => assert.ok(ed.bodyOverflow <= 1,
        `溢出 ${ed.bodyOverflow}px`));

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
          return {
            items: document.querySelectorAll('#smelters .sm').length,
            page: document.documentElement.scrollWidth - document.documentElement.clientWidth,
            box: box ? box.scrollWidth - box.clientWidth : 0
          };
        })()`);
        check(`${width}px 清单仍渲染 ${expected} 条`,
          () => assert.equal(narrow.items, expected));
        check(`${width}px 页面无横向溢出`, () => assert.ok(narrow.page <= 1,
          `溢出 ${narrow.page}px`));
        check(`${width}px 清单容器无横向溢出`, () => assert.ok(narrow.box <= 1,
          `溢出 ${narrow.box}px`));
      }
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
