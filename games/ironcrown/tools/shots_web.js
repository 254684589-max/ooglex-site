// 固定机位截图 + 性能统计（画质类步骤给所有者看的实机截图；TECH.md 第七节）。
// 依次打开 play/?view=N&q=<画质>&perf=1（N = 0..2，见 world/frostford.gd 的 VIEWS），等游戏打出 IC_PERF 后截图。
// 每个机位用一个新页面并在截完后关掉（同时开着几个游戏实例会把软件渲染拖垮）。
//   python3 games/ironcrown/tools/serve_gzip.py . 8765   # 仓库根目录
//   node games/ironcrown/tools/shots_web.js <截图目录> [low|medium|high] [宽x高]
// 无头 Chromium 用 SwiftShader 软件渲染：帧率只供参考，绘制调用与图元数与显卡无关。
const path = require('path');
let pw;
try { pw = require('playwright'); } catch (e) { pw = require('/opt/node22/lib/node_modules/playwright'); }
const outDir = process.argv[2] || '.';
const q = process.argv[3] || 'medium';
const [w, h] = (process.argv[4] || '1280x720').split('x').map(Number);
(async () => {
  const b = await pw.chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  let failed = 0;
  for (const v of [0, 1, 2]) {
    const ctx = await b.newContext({ viewport: { width: w, height: h } });
    const p = await ctx.newPage();
    const logs = [], errs = [];
    p.on('console', m => { logs.push(m.text()); if (m.type() === 'error') errs.push(m.text()); });
    await p.goto(`http://localhost:8765/games/ironcrown/play/?view=${v}&q=${q}&perf=1`);
    let perf;
    for (let i = 0; i < 240 && !perf; i++) { await p.waitForTimeout(250); perf = logs.find(l => l.startsWith('IC_PERF')); }
    const file = path.join(outDir, `ic-view${v}-${q}-${w}.png`);
    await p.screenshot({ path: file, timeout: 120000 });
    if (!perf || errs.length) failed++;
    console.log(`${perf && !errs.length ? 'PASS' : 'FAIL'} 机位 ${v} ${w}x${h} ${q} | ${perf || '没有 IC_PERF'} | 报错 ${errs.length}${errs.length ? '：' + errs.slice(0, 2).join(' || ') : ''} | ${file}`);
    await ctx.close();
  }
  await b.close();
  process.exit(failed ? 1 : 0);
})();
