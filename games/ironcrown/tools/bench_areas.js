// 逐区域性能复测（路线图 3.8）：每个区域的前三个固定机位各打开一次 play/?perf=1&area=…&view=…&probe=3，
// 游戏载入 2 秒后测 3 秒，打出 IC_PERF（平均帧率、最慢一帧、绘制调用、图元）。结果按区域 × 机位列表，供 TEST_REPORT 使用。
// 主街三个机位的完整基准（含结果浮层截图）仍用 tools/bench_web.js。
//   python3 games/ironcrown/tools/serve_gzip.py . 8765   # 仓库根目录
//   node games/ironcrown/tools/bench_areas.js [auto|low|medium|high] [宽x高] [mobile|desktop] [区域,区域]
let pw;
try { pw = require('playwright'); } catch (e) { pw = require('/opt/node22/lib/node_modules/playwright'); }
const q = (process.argv[2] || 'auto') === 'auto' ? '' : process.argv[2];
const [w, h] = (process.argv[3] || '1280x720').split('x').map(Number);
const mobile = process.argv[4] === 'mobile';
const AREAS = [['frostford', 3], ['tavern', 3], ['churchyard', 3], ['chapel', 3], ['birch', 3], ['ferry', 3], ['marsh', 6]];   // 鹭沼（4.4a）：六个机位，分帧搭完才测（main 等 all_built）
const ONLY = process.argv[5] ? process.argv[5].split(',') : null;   // 第五个参数：只测这几个区域（逗号分隔）
(async () => {
  const b = await pw.chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: w, height: h }, isMobile: mobile, hasTouch: mobile });
  const p = await ctx.newPage();
  const logs = [], errs = [];
  p.on('console', m => { logs.push(m.text()); if (m.type() === 'error') errs.push(m.text()); });
  let failed = 0;
  console.log(`${w}x${h}${mobile ? ' 触屏' : ''} 画质 ${q || '自动'}`);
  for (const [area, views] of AREAS) {
    if (ONLY && !ONLY.includes(area)) continue;
    const cells = [];
    for (let v = 0; v < views; v++) {
      logs.length = 0;
      await p.goto(`http://localhost:8765/games/ironcrown/play/?perf=1&probe=3&area=${area}&view=${v}${q ? '&q=' + q : ''}`);
      let line;
      for (let i = 0; i < 480 && !line; i++) { await p.waitForTimeout(250); line = logs.find(l => l.startsWith('IC_PERF')); }
      if (!line) { failed++; cells.push('没测到'); continue; }
      const g = k => Number((line.match(new RegExp(k + '=([0-9.]+)')) || [])[1]);
      cells.push(`${g('fps').toFixed(1)} 帧 · 最慢 ${g('worst_ms').toFixed(0)} 毫秒 · ${g('draw_calls').toFixed(0)} 次 · ${(g('primitives') / 1000).toFixed(0)}k 图元`);
    }
    console.log(`| ${area} | ${cells.join(' | ')} |`);
  }
  console.log(`报错 ${errs.length}${errs.length ? '：' + errs.slice(0, 2).join(' || ') : ''}`);
  await b.close();
  process.exit(failed === 0 && errs.length === 0 ? 0 : 1);
})();
