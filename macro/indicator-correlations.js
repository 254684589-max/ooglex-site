"use strict";
/* Ooglex V4: correlations of synchronized DAILY CHANGES in audited Treasury observations.
   Correlation is descriptive, not causality, signal quality, or asset return forecast. */
(()=>{
 const $=id=>document.getElementById(id);
 const keys={us10y:"10年名义利率",us2y:"2年名义利率",real10y:"10年实际利率",breakeven10y:"10年通胀补偿",spread10y2y:"10Y－2Y利差"};
 const minSample=60;
 function pearson(xs,ys){const n=xs.length;if(n<minSample||ys.length!==n)return null;let ax=0,ay=0;for(let i=0;i<n;i++){ax+=xs[i];ay+=ys[i]}ax/=n;ay/=n;let cov=0,vx=0,vy=0;for(let i=0;i<n;i++){const a=xs[i]-ax,b=ys[i]-ay;cov+=a*b;vx+=a*a;vy+=b*b}return vx>1e-18&&vy>1e-18?Math.max(-1,Math.min(1,cov/Math.sqrt(vx*vy))):null}
 function windowed(rows,w){if(w==="all")return rows;const end=Date.parse(rows.at(-1).date+"T00:00:00Z"),days=w==="3m"?92:w==="6m"?183:366;return rows.filter(r=>Date.parse(r.date+"T00:00:00Z")>=end-days*86400000)}
 function matrix(rows){const ds=[];for(let i=1;i<rows.length;i++){const prev=rows[i-1],cur=rows[i],dt=(Date.parse(cur.date+"T00:00:00Z")-Date.parse(prev.date+"T00:00:00Z"))/86400000;if(dt<1||dt>4)continue;const delta={date:cur.date};for(const k of Object.keys(keys))delta[k]=cur[k]-prev[k];ds.push(delta)}return ds}
 function paintCell(r,diagonal){const cell=document.createElement("td");cell.textContent=r===null?"—":r.toFixed(2);cell.className="corr-value";if(r!==null){cell.dataset.sign=r>0.25?"positive":r<-.25?"negative":"neutral";cell.title=(diagonal?"指标自身":"同日收益率变动")+" · Pearson r="+r.toFixed(4)}return cell}
 function render(d){const w=$("corr-window").value,rows=windowed(d.observations,w),deltas=matrix(rows),status=$("corr-status"),table=$("corr-table"),insight=$("corr-observation");table.replaceChildren();insight.replaceChildren();const list=Object.entries(keys);
 const head=document.createElement("thead"),tr=document.createElement("tr");for(const label of ["指标",...list.map(x=>x[1])]){const th=document.createElement("th");th.scope="col";th.textContent=label;tr.append(th)}head.append(tr);table.append(head);
 const body=document.createElement("tbody"),pairs=[];for(let i=0;i<list.length;i++){const row=document.createElement("tr"),th=document.createElement("th");th.scope="row";th.textContent=list[i][1];row.append(th);for(let j=0;j<list.length;j++){const k1=list[i][0],k2=list[j][0],valid=deltas.filter(t=>Number.isFinite(t[k1])&&Number.isFinite(t[k2])),r=pearson(valid.map(t=>t[k1]),valid.map(t=>t[k2]));row.append(paintCell(r,i===j));if(j>i&&r!==null)pairs.push({a:list[i][1],b:list[j][1],r,n:valid.length})}body.append(row)}table.append(body);
 status.textContent="数据区间："+rows[0].date+" — "+rows.at(-1).date+"；有效相邻日变动样本："+deltas.length+"；相关系数要求至少"+minSample+"组同日样本。源数据："+d.source+"。";
 const candidates=pairs.filter(x=>Math.abs(x.r)<.9995).sort((a,b)=>Math.abs(b.r)-Math.abs(a.r));
 const msg=document.createElement("p");msg.textContent=candidates.length?"示例：除去接近代数恒等关系的组合，样本中绝对相关性较高的是「"+candidates[0].a+"」与「"+candidates[0].b+"」，r="+candidates[0].r.toFixed(3)+"，n="+candidates[0].n+"。这不表示因果关系或未来预测能力。":"当前数据没有足够的独立同日样本可供相关性解释。";insight.append(msg);
 const note=document.createElement("p");note.className="fine";note.textContent="已知代数关系：10年名义收益率≈10年实际收益率＋通胀补偿；10Y－2Y利差＝10年－2年收益率，因此部分高相关性源自构造公式，不能当作独立证据。统计单位为收益率日变化（百分点），不是收益率水平或资产日回报；非历史首次发布版本。";insight.append(note)}
 async function init(){const status=$("corr-status");if(!status)return;try{if(typeof TREASURY_TRENDS==="undefined"||typeof TREASURY_TRENDS.validate!=="function")throw Error("官方数据校验模块不可用");const r=await fetch("../data/asset-compass-treasury-history.json",{cache:"no-store"});if(!r.ok)throw Error("历史数据 HTTP "+r.status);const d=TREASURY_TRENDS.validate(await r.json());$("corr-window").addEventListener("change",()=>render(d));render(d)}catch(e){status.textContent="相关性矩阵暂不可用："+e.message+"。不会显示模拟统计量。";$("corr-table").replaceChildren();$("corr-observation").replaceChildren()}}
 if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",init,{once:true});else init();
})();