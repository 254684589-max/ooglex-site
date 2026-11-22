"use strict";
/* Ooglex indicator historical comparison V3. Descriptive treasury data only, not PIT backtest. */
(()=>{
const $=id=>document.getElementById(id);
const fields={us10y:"美国10年期名义收益率",us2y:"美国2年期名义收益率",real10y:"10年期TIPS实际收益率",breakeven10y:"10年期通胀补偿",spread10y2y:"10Y−2Y期限利差"};
const NS="http://www.w3.org/2000/svg";
const svg=(name,attrs={},value)=>{const el=document.createElementNS(NS,name);for(const [k,v]of Object.entries(attrs))el.setAttribute(k,String(v));if(value!==undefined)el.textContent=String(value);return el};
const fmt=n=>n.toFixed(3),sign=n=>(n>=0?"+":"")+fmt(n);
const select=id=>$(id);
let dataset=null;
function optionize(node,selected){Object.entries(fields).forEach(([key,name])=>{const opt=document.createElement("option");opt.value=key;opt.textContent=name;node.append(opt)});node.value=selected}
function windowRows(rows,range){if(range==="all")return rows;const cutoff=Date.parse(rows[rows.length-1].date+"T00:00:00Z")-(range==="3m"?92:range==="6m"?183:366)*86400000;return rows.filter(r=>Date.parse(r.date+"T00:00:00Z")>=cutoff)}
function metrics(rows,k){const vals=rows.map(x=>x[k]).sort((a,b)=>a-b);const first=rows[0][k],last=rows[rows.length-1][k];const rank=vals.filter(v=>v<=last).length/vals.length*100;return{first,last,delta:last-first,min:vals[0],max:vals[vals.length-1],median:vals.length%2?vals[(vals.length-1)/2]:(vals[vals.length/2-1]+vals[vals.length/2])/2,rank}}
function render(){if(!dataset)return;const main=select("history-primary").value,secondary=select("history-secondary").value,range=select("history-window").value,rows=windowRows(dataset.observations,range);
const status=select("history-status"),out=select("history-metrics"),chart=select("history-chart"),probe=select("history-probe");out.replaceChildren();chart.replaceChildren();
if(rows.length<2){status.textContent="选定范围缺少至少两个真实观测日期，无法绘图。";return}
const keys=[main,...(secondary!=="none"&&secondary!==main?[secondary]:[])];const values=rows.flatMap(r=>keys.map(k=>r[k])),low=Math.min(...values),high=Math.max(...values),spread=high-low||1;const min=low-spread*.08,max=high+spread*.08;
const w=940,h=340,left=74,right=20,top=20,bottom=44,plotW=w-left-right,plotH=h-top-bottom;
const x=i=>left+i/(rows.length-1)*plotW,y=v=>top+(max-v)/(max-min)*plotH;
for(let i=0;i<=4;i++){let v=min+(max-min)*i/4,yy=y(v);chart.append(svg("line",{x1:left,x2:w-right,y1:yy,y2:yy,stroke:"#30445d","stroke-width":1}));chart.append(svg("text",{x:left-10,y:yy+4,"text-anchor":"end",fill:"#b8cbe0","font-size":12},v.toFixed(2)))}
chart.append(svg("text",{x:left,y:h-13,fill:"#b8cbe0","font-size":12},rows[0].date));
chart.append(svg("text",{x:w-right,y:h-13,"text-anchor":"end",fill:"#b8cbe0","font-size":12},rows[rows.length-1].date));
const colors=["#65b7ff","#eab96e"];
keys.forEach((k,i)=>{const path=rows.map((r,j)=>(j?"L":"M")+x(j).toFixed(2)+","+y(r[k]).toFixed(2)).join(" ");chart.append(svg("path",{d:path,fill:"none",stroke:colors[i],"stroke-width":2.4,"stroke-linejoin":"round","stroke-linecap":"round"}));const last=rows[rows.length-1];chart.append(svg("circle",{cx:x(rows.length-1),cy:y(last[k]),r:4.5,fill:colors[i]}));const s=metrics(rows,k);const card=document.createElement("article");card.className="history-stat";const title=document.createElement("strong");title.textContent=fields[k];card.append(title);const para=document.createElement("p");para.textContent="最新 "+fmt(s.last)+"% · 区间变化 "+sign(s.delta)+"个百分点（"+(s.delta*100>=0?"+":"")+(s.delta*100).toFixed(1)+" bp）";card.append(para);const detail=document.createElement("p");detail.className="fine";detail.textContent="区间最低 "+fmt(s.min)+"% · 最高 "+fmt(s.max)+"% · 中位数 "+fmt(s.median)+"% · 经验百分位 "+s.rank.toFixed(1)+"%";card.append(detail);out.append(card)});
status.textContent=rows[0].date+" 至 "+rows[rows.length-1].date+" · "+rows.length+" 个真实观测日 · 共用纵轴（%）· 截至"+dataset.end_date+"的最新已采集观测。";
const show=row=>{probe.textContent=row.date+" · "+keys.map(k=>fields[k]+" "+fmt(row[k])+"%").join(" · ")};
chart.onpointermove=e=>{const b=chart.getBoundingClientRect();if(!b.width)return;const xx=(e.clientX-b.left)/b.width*w;const idx=Math.max(0,Math.min(rows.length-1,Math.round((xx-left)/plotW*(rows.length-1))));show(rows[idx])};
chart.onpointerleave=()=>show(rows[rows.length-1]);chart.onfocus=()=>show(rows[rows.length-1]);chart.setAttribute("tabindex","0");show(rows[rows.length-1]);
select("history-meta").textContent="来源："+dataset.source+"；抓取时间："+dataset.retrieved_at+"；原始来源见财政部链接。经验百分位＝区间样本中小于或等于最新值的观测数/总数×100，含并列值；不是投资评分。首末变化为收益率百分点和bp，不是持有债券回报。";
}
async function init(){const status=select("history-status");if(!status)return;const a=select("history-primary"),b=select("history-secondary");optionize(a,"us10y");const blank=document.createElement("option");blank.value="none";blank.textContent="不对比";b.append(blank);optionize(b,"real10y");for(const id of ["history-primary","history-secondary","history-window"])select(id).addEventListener("change",render);try{if(typeof TREASURY_TRENDS==="undefined"||typeof TREASURY_TRENDS.validate!=="function")throw Error("财政部历史校验模块未加载");const response=await fetch("../data/asset-compass-treasury-history.json",{cache:"no-store"});if(!response.ok)throw Error("HTTP "+response.status);dataset=TREASURY_TRENDS.validate(await response.json());render()}catch(e){status.textContent="历史曲线不可用："+e.message+"。不会生成或填补模拟曲线。";select("history-metrics").replaceChildren();select("history-chart").replaceChildren();}}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",init,{once:true});else init();
})();