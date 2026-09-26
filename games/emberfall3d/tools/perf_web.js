// 网页性能基准（TECH.md 第 5.2 节）：打开 play/?perf=1，游戏把玩家放到大厅中央（无敌）、等怪物围上来，
// 采样 1 秒后打出 EF_PERF（绘制调用、图元、可见物体、帧率、物理 / 逻辑耗时）。
// 先在仓库根目录 python3 -m http.server 8765，然后：node games/emberfall3d/tools/perf_web.js [截图目录]
// 注意：无头 Chromium 用 SwiftShader 软件渲染，帧率与耗时只供参考；绘制调用与图元数与显卡无关。
const path = require('path');
let pw;
try { pw = require('playwright'); } catch (e) { pw = require('/opt/node22/lib/node_modules/playwright'); }
const outDir = process.argv[2] || '.';
(async () => {
  const b = await pw.chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await (await b.newContext({ viewport: { width: 1280, height: 720 } })).newPage();
  const logs = [];
  p.on('console', m => logs.push(m.text()));
  await p.goto('http://localhost:8765/games/emberfall3d/play/?perf=1');
  let perf;
  for (let i = 0; i < 240 && !perf; i++) { await p.waitForTimeout(250); perf = logs.find(l => l.startsWith('EF_PERF')); }
  await p.screenshot({ path: path.join(outDir, 'ef3d-perf.png') });
  console.log(perf || 'FAIL 没有收到 EF_PERF');
  await b.close();
  process.exit(perf ? 0 : 1);
})();
