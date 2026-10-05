// 军队规模压力测试（网页）：打开 tools/army_bench_web.sh 导出的临时网页，收集 ICB 行，等 ICB_DONE 后退出。
//   node games/ironcrown/tools/army_bench_web.js "mode=combat&model=1&no3d=1" [端口]
let pw;
try { pw = require('playwright'); } catch (e) { pw = require('/opt/node22/lib/node_modules/playwright'); }
const q = process.argv[2] || '';
const port = process.argv[3] || '8790';
(async () => {
  const b = await pw.chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await (await b.newContext({ viewport: { width: 1280, height: 720 } })).newPage();
  const logs = [], errs = [];
  p.on('console', m => {
    const t = m.text();
    logs.push(t);
    if (t.startsWith('ICB')) console.log(t);
    if (m.type() === 'error' && !t.includes('status of 404')) errs.push(t);
  });
  p.on('response', r => { if (r.status() === 404) console.log(`404（不计入报错）：${r.url()}`); });
  p.on('pageerror', e => errs.push(String(e)));
  await p.goto(`http://localhost:${port}/index.html?${q}`);
  for (let i = 0; i < 2400 && !logs.some(l => l.startsWith('ICB_DONE')); i++) await p.waitForTimeout(250);
  const done = logs.some(l => l.startsWith('ICB_DONE'));
  if (errs.length) console.log(`报错 ${errs.length}：${errs.slice(0, 3).join(' || ')}`);
  await b.close();
  process.exit(done && errs.length === 0 ? 0 : 1);
})();
