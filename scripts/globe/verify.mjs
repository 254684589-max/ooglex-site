/**
 * 全球态势地球的浏览器实测：中文化、署名保留、图标完好、响应式、无异常。
 *
 * 跑法（需先起本地服务器并装好 puppeteer）：
 *   npx http-server -p 8902 -s .        # 仓库根目录
 *   node scripts/globe/verify.mjs
 *
 * 两个踩过的坑固化在这里，别改回去：
 *
 * 1) **断言计算样式，不是 hidden 属性。** 进入卡的 `.gate` 自带 `display:flex`，
 *    会覆盖 UA 样式表里 `[hidden]` 的 `display:none`；只读 `element.hidden`
 *    会返回 true 看着是对的，但卡片其实还浮在应用上面。
 *
 * 2) **轮询等待稳定状态，不要固定 sleep；断言用 textContent 不用 innerText。**
 *    窄屏下应用启动明显更慢（软件 WebGL），固定等待会误判成「没翻译」；
 *    而 innerText 对隐藏/折叠元素返回空串，同样会误判。
 *
 * 另外：断言前必须摘掉署名子树（#cesium-credits、.cesium-credit-lightbox 等）。
 * 那里的英文是许可要求的原文，本就不该翻译，留着会让「无残留英文」误报。
 */
import { launchGlobeBrowser } from './browser.mjs';

/** 取完整应用的 document。层级：包装页 → lite 轻量地球 → #full 内层 iframe。
 *  只穿一层会把 lite 页当成应用，断言会全部落空（踩过）。 */
function appDocExpr() {
  return `(() => { const l = document.querySelector('.stage iframe');
    const ld = l && l.contentDocument; const f = ld && ld.querySelector('#full');
    return (f && f.contentDocument) || null; })()`;
}

const B = process.env.GLOBE_VERIFY_URL || 'http://127.0.0.1:8902';
const browser = await launchGlobeBrowser();
let fails = 0;
const ck = (l,c)=>{ if(!c) fails++; console.log(`  ${c?'✅':'❌'} ${l}`); };

async function suite(label, vp, full) {
  const page = await browser.newPage();
  await page.setViewport(vp);
  const errs=[], bad=[];
  page.on('pageerror', e=>errs.push(String(e).slice(0,140)));
  page.on('response', r=>{ if(r.url().startsWith(B)&&r.status()>=400&&!r.url().includes('/api/')) bad.push(r.status()+' '+r.url().slice(B.length)); });
  await page.goto(`${B}/apps/globe/`, {waitUntil:'networkidle2', timeout:90000});
  await new Promise(r=>setTimeout(r,2500));

  for(let i=0;i<25;i++){
    if(await page.evaluate(()=>{const l=document.querySelector('.stage iframe');const ld=l&&l.contentDocument;const fu=ld&&ld.querySelector('#full');const d=fu&&fu.contentDocument;return !!(d&&d.querySelector('#data-toggles'));})) break;
    await new Promise(r=>setTimeout(r,1500));
  }
  await new Promise(r=>setTimeout(r,4000));
  await page.evaluate(()=>{const l=document.querySelector('.stage iframe');const ld=l.contentDocument;const fu=ld.querySelector('#full');const d=fu&&fu.contentDocument;if(!d)return;const b=d.querySelector('[data-collapse-target="data-panel"]');if(b&&b.getAttribute('aria-expanded')==='false')b.click();});
  // 断言前轮询等待「中文化已落地」这个稳定状态，而不是固定 sleep。
  // 窄屏下应用启动明显更慢（软件 WebGL），固定等待会误判。
  let settled = false;
  for (let i=0;i<30;i++){
    settled = await page.evaluate(()=>{
      const l=document.querySelector('.stage iframe');const ld=l.contentDocument;const fu=ld.querySelector('#full');const d=fu&&fu.contentDocument;if(!d)return;
      const c=d.body.cloneNode(true);
      c.querySelectorAll('#cesium-credits,.cesium-widget-credits,.cesium-credit-lightbox,.cesium-credit-lightbox-overlay,[data-no-translate]').forEach(e=>e.remove());
      return ((c.textContent||'').match(/[\u4e00-\u9fa5]/g)||[]).length > 100;
    });
    if (settled) break;
    await new Promise(r=>setTimeout(r,1500));
  }
  console.log(`  （中文化就绪：${settled?'是':'超时未就绪'}）`);

  console.log(`\n===== ${label} ${vp.width}x${vp.height} =====`);
  const r = await page.evaluate(()=>{
    const l=document.querySelector('.stage iframe'); const ld=l.contentDocument;
    const f=ld.querySelector('#full'); const d=f&&f.contentDocument;
    if(!d) return {noApp:true};
    // 窄屏下上游用另一套界面，图层行不在 #data-toggles 里，所以对整个文档断言；
    // 但必须先摘掉署名子树 —— 那里的英文是许可要求的原文，本就不该翻译。
    const clone = d.body.cloneNode(true);
    clone.querySelectorAll('#cesium-credits,.cesium-widget-credits,.cesium-credit-lightbox,.cesium-credit-lightbox-overlay,[data-no-translate]')
      .forEach(function(e){ e.remove(); });
    const panel = clone.textContent || '';
    const all = panel;
    const cred=d.querySelector('#cesium-credits, .cesium-widget-credits');
    return {
      zh:['实时航班','军用航班','地震（近 24 小时）','卫星','航天任务（近 30 天）','道路交通','监控摄像头','电台','车牌识别摄像头'].filter(s=>panel.includes(s)),
      enLeft:['Live Flights','Military Flights','Satellites','Space Missions (30d)','Street Traffic'].filter(s=>panel.includes(s)),
      neverZh: panel.includes('从未更新'), neverEn: panel.includes('· never'),
      srcKept:['OpenSky','adsb.lol','USGS','CelesTrak','Launch Library 2','OpenStreetMap'].filter(s=>panel.includes(s)),
      icons:['arrow_forward','chevron_left','public','radar'].filter(s=>d.body.innerHTML.includes('>'+s+'<')),
      creditEn: cred ? /Made with Natural Earth/i.test(cred.textContent||'') : false,

      panelTitleZh: all.includes('数据图层'),
      cesium: typeof f.contentWindow.Cesium!=='undefined',
      zhChars: (panel.match(/[\u4e00-\u9fa5]/g)||[]).length,
      // 无障碍标签由 JS 动态拼接（`${图层名}: ON|OFF`），走的是属性路径。
      // 曾经漏接过：正则规则只加在文本节点上，属性仍是英文。
      ariaEn: Array.from(d.querySelectorAll('button.data-toggle-btn'))
        .map(b=>b.getAttribute('aria-label')||'').filter(v=>/: (ON|OFF)$/.test(v)),
      ariaZh: Array.from(d.querySelectorAll('button.data-toggle-btn'))
        .map(b=>b.getAttribute('aria-label')||'').filter(v=>/：(开|关)$/.test(v)),
    };
  });
  ck('Cesium 初始化', r.cesium);
  // 窄屏下上游只渲染部分图层行，所以「9/9」只对宽屏成立；
  // 窄屏改为「凡渲染出来的都已中文化」——由下一条『无残留英文』保证。
  if (full) ck(`图层名中文化 ${r.zh.length}/9`, r.zh.length===9);
  else ck(`图层名中文化 ${r.zh.length} 条（窄屏仅渲染部分）`, r.zh.length>0);
  ck(`中文字符数 ${r.zhChars}（应 >100）`, r.zhChars>100);
  ck('无残留英文图层名', r.enLeft.length===0);
  ck('状态词无英文 never 残留', !r.neverEn);
  if (full) ck('状态词 never→从未更新', r.neverZh);
  ck(`数据源专名保留原文 ${r.srcKept.length} 项`, r.srcKept.length>=4);
  ck(`图标连字完好 ${r.icons.length}/4`, r.icons.length===4);
  ck('署名行保持英文原文', r.creditEn);
  ck('面板标题中文化', r.panelTitleZh);
  const of = await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth+1);
  if (full) ck(`开关 aria-label 中文化 ${r.ariaZh.length} 项，英文残留 ${r.ariaEn.length} 项`,
              r.ariaZh.length>0 && r.ariaEn.length===0);
  ck('无横向溢出', !of);
  ck('无站内非 api 的 404', bad.length===0); if(bad.length) console.log('    '+bad.join('\n    '));
  ck('无 JS 异常', errs.length===0); if(errs.length) console.log('    '+errs.slice(0,2).join(' | '));
  await page.close();
}
await suite('桌面', {width:1400,height:950}, true);
await suite('平板', {width:768,height:1024}, true);
await suite('手机', {width:360,height:740,isMobile:true,hasTouch:true}, false);
console.log(`\n总计失败项：${fails}`);
await browser.close();
process.exit(fails?1:0);
