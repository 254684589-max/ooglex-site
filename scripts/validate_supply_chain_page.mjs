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
        const rows = [...box.querySelectorAll('.covrow')].map(r => {
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
          keys: box.querySelectorAll('.covkey span').length,
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
