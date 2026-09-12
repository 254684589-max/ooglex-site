const { chromium } = require('playwright');
const fs = require('fs');

/* 逐页核对某套主题的可读性：对比度、残留深色块、主题选择器是否可见。
   用法：python3 -m http.server 8899 &  然后 node scripts/theme/audit_theme.js ft
   判定口径见 docs/THEME.md。 */
const path = require('path');
const ROOT = path.resolve(__dirname, '../..');
const SKIP = ['.git', 'home-redesign', 'terminal-redesign', 'docs', 'node_modules'];
function walkDir(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const rel = path.relative(ROOT, path.join(dir, e.name));
    if (SKIP.some(s => rel === s || rel.startsWith(s + path.sep))) continue;
    if (e.isDirectory()) walkDir(path.join(dir, e.name), out);
    else if (e.name.endsWith('.html')) out.push(rel.split(path.sep).join('/'));
  }
  return out;
}
const PAGES = walkDir(ROOT).sort();
const THEME = process.argv[2] || 'ft';
const BASE = process.env.OOGLEX_BASE || 'http://127.0.0.1:8899/';

function lum([r,g,b]){ const f=c=>{c/=255;return c<=0.03928?c/12.92:Math.pow((c+0.055)/1.055,2.4)};
  return 0.2126*f(r)+0.7152*f(g)+0.0722*f(b); }
function contrast(a,b){ const L1=lum(a),L2=lum(b); return (Math.max(L1,L2)+0.05)/(Math.min(L1,L2)+0.05); }

(async () => {
  const browser = await chromium.launch();
  const out = [];
  for (const rel of PAGES) {
    const ctx = await browser.newContext({ viewport:{width:1280,height:900} });
    await ctx.addInitScript(t => { try{ localStorage.setItem('ooglex.theme', t); }catch(e){} }, THEME);
    const p = await ctx.newPage();
    const errs=[]; p.on('pageerror',e=>errs.push(e.message.slice(0,90)));
    try { await p.goto(BASE+rel, {waitUntil:'networkidle', timeout:25000}); }
    catch(e){ out.push({rel, fail:'加载失败 '+e.message.slice(0,50)}); await ctx.close(); continue; }
    await p.waitForTimeout(700);
    const r = await p.evaluate(() => {
      const parse = s => {
        if(!s) return null;
        const t=String(s).trim();
        if(/^(none|transparent|currentcolor|inherit)$/i.test(t)) return null;
        // color(srgb 1 0.94 0.89 / .88) —— 分量是 0–1
        let m=t.match(/^color\(\s*srgb\s+([^)]+)\)/i);
        if(m){ const p=m[1].split(/[\s/]+/).filter(Boolean).map(Number);
               if(p.length>=3) return [p[0]*255,p[1]*255,p[2]*255]; return null; }
        m=t.match(/-?[\d.]+/g);
        return m? m.slice(0,3).map(Number):null;
      };
      const alphaOf = s => {
        const t=String(s||'');
        let m=t.match(/^color\(\s*srgb\s+[^/)]+\/\s*([\d.]+)/i); if(m) return parseFloat(m[1]);
        m=t.match(/^rgba?\(([^)]*)\)$/);
        if(m){ const p=m[1].split(/[,/\s]+/).filter(Boolean);
               return p.length>3? parseFloat(p[3]) : 1; }
        return /^(none|transparent)$/i.test(t)?0:1;
      };
      const chroma = c => Math.max(c[0],c[1],c[2])-Math.min(c[0],c[1],c[2]);
      const L = c => { const f=x=>{x/=255;return x<=0.03928?x/12.92:Math.pow((x+0.055)/1.055,2.4)};
                       return 0.2126*f(c[0])+0.7152*f(c[1])+0.0722*f(c[2]); };
      const bodyCS = getComputedStyle(document.body);
      const htmlCS = getComputedStyle(document.documentElement);
      let bg = parse(bodyCS.backgroundColor);
      if (!bg || /rgba\(0, 0, 0, 0\)/.test(bodyCS.backgroundColor)) bg = parse(htmlCS.backgroundColor);
      const darkBlocks = [], lowText = [];
      const seen = new Set();
      for (const el of document.querySelectorAll('body *')) {
        const cs = getComputedStyle(el);
        if (cs.display==='none' || cs.visibility==='hidden') continue;
        const rect = el.getBoundingClientRect();
        const area = rect.width*rect.height;
        // 大面积深色底
        const b = parse(cs.backgroundColor);
        const alpha = alphaOf(cs.backgroundColor);
        // 只算「近中性的深色块」；饱和色是数据编码（热力图瓦片等），不算问题
        if (b && alpha>0.5 && area>18000 && L(b)<0.22 && chroma(b)<=90) {
          const key = el.tagName+'.'+(el.className||'').toString().trim().split(/\s+/)[0];
          if (!seen.has('b'+key)) { seen.add('b'+key);
            darkBlocks.push({sel:key, area:Math.round(area), bg:cs.backgroundColor}); }
        }
        // 文字对比度（只看直接含文本的元素）
        const hasText = Array.from(el.childNodes).some(n=>n.nodeType===3 && n.textContent.trim().length>1);
        if (hasText && area>60) {
          const fg = parse(cs.color);
          // 找最近的不透明背景
          let bb=null, q=el, grad=false;
          while(q && q!==document.documentElement){ const c=getComputedStyle(q);
            if(/gradient|url\(/i.test(c.backgroundImage||'')){ grad=true; break; }
            const pb=parse(c.backgroundColor); const a=alphaOf(c.backgroundColor);
            if(pb && a>0.6){ bb=pb; break;} q=q.parentElement; }
          if(grad) continue;              // 渐变/图片底：算不出有效对比度，跳过
          if(!bb) bb=bg;
          if (fg && bb) {
            const l1=L(fg), l2=L(bb);
            const cr=(Math.max(l1,l2)+0.05)/(Math.min(l1,l2)+0.05);
            if (cr < 3.0) {
              const key = el.tagName+'.'+(el.className||'').toString().trim().split(/\s+/)[0];
              if (!seen.has('t'+key)) { seen.add('t'+key);
                lowText.push({sel:key, cr:+cr.toFixed(2), fg:cs.color, bg:`rgb(${bb.join(',')})`,
                              txt:(el.textContent||'').trim().slice(0,18)}); }
            }
          }
        }
      }
      return {
        theme: document.documentElement.getAttribute('data-theme'),
        lock: document.documentElement.getAttribute('data-theme-lock')||'',
        bodyBg: bodyCS.backgroundColor, bodyFg: bodyCS.color,
        picker: !!document.querySelector('.ogx-theme'),
        pickerVisible: (()=>{ const e=document.querySelector('.ogx-theme__btn'); if(!e) return false;
          const r=e.getBoundingClientRect(); return r.width>10 && r.height>10; })(),
        darkBlocks: darkBlocks.sort((a,b)=>b.area-a.area).slice(0,6),
        lowText: lowText.sort((a,b)=>a.cr-b.cr).slice(0,6),
        docW: document.documentElement.scrollWidth
      };
    });
    r.rel = rel; r.errs = errs;
    out.push(r);
    await ctx.close();
  }
  await browser.close();
  fs.writeFileSync(path.join(ROOT, `.theme-audit-${THEME}.json`), JSON.stringify(out,null,1));

  // 汇总
  let bad=0;
  console.log(`\n主题=${THEME}  共 ${out.length} 页\n`);
  console.log('页面'.padEnd(40), '主题'.padEnd(7), '选择器', '深色块', '低对比', '错误');
  for (const r of out) {
    if (r.fail) { console.log(r.rel.padEnd(40), r.fail); bad++; continue; }
    // 深色主题（含固定深色的页面）下，深色底与其上的浅色文字就是设计本身，
    // 只看主题选择器是否可见与有无报错。
    const darkMode = THEME === 'dark' || !!r.lock;
    const flag = ((darkMode ? 0 : r.darkBlocks.length + r.lowText.length) || !r.pickerVisible || r.errs.length) ? '  ←' : '';
    console.log(r.rel.padEnd(40), (r.lock?r.theme+'(锁)':r.theme).padEnd(7),
      (r.pickerVisible?'有':'缺').padEnd(6), String(r.darkBlocks.length).padEnd(6),
      String(r.lowText.length).padEnd(6), r.errs.length, flag);
    if (flag) bad++;
  }
  console.log(`\n需处理：${bad} 页  明细见 .theme-audit-${THEME}.json`);
})();
