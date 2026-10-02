// 网页基准测试（路线图 1.5）：打开 play/?perf=1（可加 &q=low|medium|high），游戏自动在 3 个机位各测 3 秒，
// 结果表显示在左上角性能浮层，并打出 IC_BENCH。这里等 IC_BENCH 出来后截图。
// 所有者在真机上不需要这个脚本：直接打开 https://www.ooglex.com/games/ironcrown/play/?perf=1 ，等结果表出来截图即可。
//   python3 games/ironcrown/tools/serve_gzip.py . 8765   # 仓库根目录
//   node games/ironcrown/tools/bench_web.js <截图目录> [auto|low|medium|high] [宽x高] [mobile]
const path = require('path');
let pw;
try { pw = require('playwright'); } catch (e) { pw = require('/opt/node22/lib/node_modules/playwright'); }
const outDir = process.argv[2] || '.';
const q = (process.argv[3] || 'auto') === 'auto' ? '' : process.argv[3];   // auto = 按设备自动选档
const [w, h] = (process.argv[4] || '1280x720').split('x').map(Number);
const mobile = process.argv[5] === 'mobile';
(async () => {
  const b = await pw.chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: w, height: h }, isMobile: mobile, hasTouch: mobile });
  const p = await ctx.newPage();
  const logs = [], errs = [];
  p.on('console', m => { logs.push(m.text()); if (m.type() === 'error') errs.push(m.text()); });
  await p.goto(`http://localhost:8765/games/ironcrown/play/?perf=1${q ? '&q=' + q : ''}`);
  let bench;
  for (let i = 0; i < 480 && !bench; i++) { await p.waitForTimeout(250); bench = logs.find(l => l.startsWith('IC_BENCH')); }
  await p.waitForTimeout(1200);
  const file = path.join(outDir, `ic-bench-${q || 'auto'}-${w}.png`);
  await p.screenshot({ path: file, timeout: 120000 });
  const ok = !!bench && errs.length === 0;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${w}x${h}${mobile ? ' 触屏' : ''} | ${bench || '没有 IC_BENCH'} | 报错 ${errs.length}${errs.length ? '：' + errs.slice(0, 2).join(' || ') : ''} | ${file}`);
  await b.close();
  process.exit(ok ? 0 : 1);
})();
