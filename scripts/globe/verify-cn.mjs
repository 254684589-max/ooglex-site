/**
 * 模拟中国大陆网络（不开 VPN）验证首屏可用性。
 *
 * 做法：用请求拦截把**所有**非本地请求「挂住」30 秒 —— 刻意不用快速失败，
 * 因为真实的墙通常是挂住而非立即拒绝，而挂住才是最伤页面的那种。
 *
 * 断言两件事：
 * 1) **首屏必须在几秒内可见。** 样式表与同步脚本是渲染阻塞资源；上游原本在
 *    <head> 里引了三个 fonts.googleapis.com 样式表，在大陆会一直挂住，
 *    页面表现为打不开/白屏。字体改为同源自托管后这个问题消失。
 * 2) **图标连字必须生效。** Material Symbols 的连字靠
 *    `font-feature-settings: 'liga'` 打开，这条规则在 Google 原 CSS 的
 *    `.material-symbols-outlined{…}` 里，不在 @font-face 里。自托管时若只搬了
 *    @font-face，图标会退化成 `layers_clear` 这样的字母文本 —— 第一版就是这么坏的。
 *    判据是「整串名字的渲染宽度 ≤ 字号的 2 倍」（生效时是一个字形）。
 *
 * 跑法：
 *   npx http-server -p 8903 -s .        # 仓库根目录
 *   node scripts/globe/verify-cn.mjs
 */
const { default: puppeteer } = await import('/home/user/bilawalsidhu/gods-eye-view/node_modules/puppeteer/lib/puppeteer/puppeteer.js');
const B = process.env.GLOBE_VERIFY_URL || 'http://127.0.0.1:8903';
const browser = await puppeteer.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',headless:true,args:['--no-sandbox','--enable-unsafe-swiftshader','--use-gl=angle','--use-angle=swiftshader']});

async function run(label, blockExternal) {
  const page = await browser.newPage();
  await page.setViewport({width:1280,height:800});
  await page.setRequestInterception(true);
  const blocked = new Set();
  page.on('request', req => {
    const u = req.url();
    // 允许域名必须由 B 推导，不能写死端口 —— 写死过一次，结果把本地服务器也拦了
    const external = !(u.startsWith(B) || /^(data:|blob:|about:|chrome)/.test(u));
    if (blockExternal && external) {
      blocked.add(new URL(u).host);
      // 模拟墙的行为：挂住而不是快速失败 —— 这才是真实情况下最伤的一种
      setTimeout(()=>{ try{ req.abort('timedout'); }catch(e){} }, 30000);
      return;
    }
    req.continue();
  });
  const t0 = Date.now();
  let firstPaint = null, uiReady = null;
  await page.goto(`${B}/apps/globe/`, {waitUntil:'domcontentloaded', timeout:60000}).catch(()=>{});
  // 轮询：包装页顶栏出现算「首屏可见」
  for(let i=0;i<60;i++){
    const ok = await page.evaluate(()=>{
      const bar=document.querySelector('.bar h1');
      return !!(bar && bar.getBoundingClientRect().height>0);
    }).catch(()=>false);
    if(ok){ firstPaint = Date.now()-t0; break; }
    await new Promise(r=>setTimeout(r,250));
  }
  // 应用就绪（包装页已回到单栏单层结构：包装页 → 应用 iframe）
  for(let i=0;i<120;i++){
    const ok = await page.evaluate(()=>{
      const f=document.querySelector('.stage iframe');
      const d=f&&f.contentDocument;
      return !!(d && (d.body.textContent||'').includes('数据图层'));
    }).catch(()=>false);
    if(ok){ uiReady = Date.now()-t0; break; }
    await new Promise(r=>setTimeout(r,500));
  }
  const st = await page.evaluate(()=>{
    const f=document.querySelector('.stage iframe');
    const d=f&&f.contentDocument;
    if(!d) return {noApp:true};
    // 图标是否用上了本地字体（连字被渲染成单字形时宽度远小于文字宽度）
    const icons=Array.from(d.querySelectorAll('.material-symbols-outlined'))
      .filter(e=>(e.textContent||'').trim().length>3 && e.getBoundingClientRect().width>0);
    const icon=icons[0];
    const w = icon ? Math.round(icon.getBoundingClientRect().width) : -1;
    // 连字生效时整串名字渲染为一个字形，宽度应 ≤ 字号的 2 倍；
    // 失效时按字母逐个排版，宽度会是数十到上百像素。
    const fs = icon ? parseFloat(getComputedStyle(icon).fontSize) : 0;
    const ligaOn = icon ? (w>0 && w <= fs*2) : null;
    const feat = icon ? (getComputedStyle(icon).webkitFontFeatureSettings||getComputedStyle(icon).fontFeatureSettings) : null;
    return {
      canvas: !!d.querySelector('canvas'),
      zhChars: (d.body.textContent||'').match(/[一-龥]/g)?.length||0,
      iconText: icon ? (icon.textContent||'').trim() : null,
      iconWidth: w,
      iconCount: icons.length, fontSize: fs, ligaOn, featureSettings: feat,
      fontsLoaded: d.fonts ? d.fonts.status : 'n/a',
      loadedFamilies: d.fonts ? Array.from(d.fonts).filter(f=>f.status==='loaded').map(f=>f.family) : [],
    };
  }).catch(e=>({err:String(e)}));
  console.log(`\n===== ${label} =====`);
  console.log(`首屏可见: ${firstPaint===null?'❌ 超时未出现':firstPaint+' ms'}`);
  console.log(`应用 UI 就绪: ${uiReady===null?'❌ 超时未就绪':uiReady+' ms'}`);
  console.log(`被拦外部域名: ${[...blocked].join(', ')||'(无)'}`);
  console.log(`状态: ${JSON.stringify(st)}`);
  await page.screenshot({path:`/tmp/claude-0/-home-user-ooglex-site/40798ce6-474a-5f37-8eaf-84b8b50050dc/scratchpad/cn-${blockExternal?'blocked':'open'}.png`});
  await page.close();
  return {firstPaint, uiReady, st};
}
const openNet = await run('正常网络', false);
const cn = await run('模拟大陆（外部请求全部挂住 30s）', true);
await browser.close();

let bad = 0;
const ck = (l, c) => { if (!c) bad++; console.log(`  ${c ? '✅' : '❌'} ${l}`); };
console.log('\n===== 判定 =====');
for (const [label, r] of [['正常网络', openNet], ['模拟大陆', cn]]) {
  ck(`${label} 首屏 5 秒内可见（实测 ${r.firstPaint ?? '超时'} ms）`,
     r.firstPaint !== null && r.firstPaint < 5000);
  ck(`${label} 应用 UI 15 秒内就绪（实测 ${r.uiReady ?? '超时'} ms）`,
     r.uiReady !== null && r.uiReady < 15000);
  ck(`${label} 界面已中文化（${r.st.zhChars} 个中文字符）`, (r.st.zhChars || 0) > 100);
  ck(`${label} 图标连字生效（宽 ${r.st.iconWidth}px / 字号 ${r.st.fontSize}px）`, r.st.ligaOn === true);
}
console.log(`\n总计失败项：${bad}`);
process.exit(bad ? 1 : 0);
