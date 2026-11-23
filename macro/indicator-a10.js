"use strict";
/* A10 indicator-first dashboard: grades are research priority, NOT asset scores.
   No simulated current prices and no substitution of short rates for forwards. */
(()=>{
const $=id=>document.getElementById(id);
const summary=$("a10-summary"),body=$("a10-rows");
if(!summary||!body)return;
const treasury="https://home.treasury.gov/resource-center/data-chart-center/interest-rates";
const specs=[
 {name:"美国10年期实际收益率",source:"美国财政部 TIPS",url:treasury,period:d=>d.observation_date,value:d=>d.rates?.real10y,unit:"%",kind:"day",maxAge:7},
 {name:"美国10年期国债收益率",source:"美国财政部",url:treasury,period:d=>d.observation_date,value:d=>d.rates?.us10y,unit:"%",kind:"day",maxAge:7},
 {name:"美国2年期国债收益率",source:"美国财政部",url:treasury,period:d=>d.observation_date,value:d=>d.rates?.us2y,unit:"%",kind:"day",maxAge:7},
 {name:"10Y－2Y期限利差",source:"财政部同日名义收益率差（非独立原始序列）",url:treasury,period:d=>d.observation_date,value:d=>d.rates?.spread10y2y,unit:"百分点",kind:"day",maxAge:7},
 {name:"10年盈亏平衡通胀率",source:"财政部名义收益率－TIPS实际收益率（含风险溢价）",url:treasury,period:d=>d.observation_date,value:d=>d.rates?.breakeven10y,unit:"百分点",kind:"day",maxAge:7},
 {name:"SOFR及SOFR远期曲线",source:"纽约联储官方SOFR现货；远期曲线尚未接入",url:"https://www.newyorkfed.org/markets/reference-rates/sofr",period:d=>d.a10sofr?.observation_date,value:d=>d.a10sofr?.sofr_overnight_percent,unit:"%（仅隔夜SOFR现货）",kind:"day",maxAge:7,partial:true,note:"SOFR远期合约尚未取得独立授权和报价数据"},
 {name:"美国国债远期收益率曲线",source:"国债期限结构推导；尚未建立合规远期数据",url:treasury,note:"不能用现货10年期收益率代替未来起始收益率"},
 {name:"联邦基金目标利率及FOMC指引",source:"纽约联储 EFFR API 所列目标区间；FOMC指引需另行接入",url:"https://www.federalreserve.gov/monetarypolicy/openmarket.htm",period:d=>d.nyfed?.observation_date,value:d=>Number.isFinite(d.nyfed?.target_range_lower)&&Number.isFinite(d.nyfed?.target_range_upper)&&d.nyfed.target_range_lower<=d.nyfed.target_range_upper?d.nyfed.target_range_upper:null,unit:"%（仅区间）",display:d=>d.nyfed.target_range_lower.toFixed(2)+"% – "+d.nyfed.target_range_upper.toFixed(2)+"%（目标区间）",kind:"day",maxAge:7,partial:true,note:"EFFR实际成交利率和FOMC前瞻指引不是同一指标"},
 {name:"高收益债OAS信用利差",source:"ICE BofA / FRED · BAMLH0A0HYM2",url:"https://fred.stlouisfed.org/series/BAMLH0A0HYM2",note:"尚未取得可合法使用、独立校验的OAS快照"},
 {name:"美国非农就业与失业率",source:"美国劳工统计局 BLS；失业率与非农就业月增量",url:"https://www.bls.gov/ces/",period:d=>d.bls?.series?.unemployment?.period,value:d=>d.bls?.series?.unemployment?.period===d.bls?.series?.payroll?.period&&Number.isFinite(d.bls?.series?.payroll?.monthly_change_thousands)?d.bls?.series?.unemployment?.value:null,unit:"%",display:d=>"失业率 "+d.bls.series.unemployment.value.toFixed(1)+"% · 非农月增 "+d.bls.series.payroll.monthly_change_thousands.toLocaleString("en-US")+"千人",kind:"month",maxAge:2}
];
const finite=n=>typeof n==="number"&&Number.isFinite(n);
const dayAge=s=>{if(!/^\d{4}-\d{2}-\d{2}$/.test(s||""))return Infinity;const n=Date.parse(s+"T00:00:00Z");return Number.isFinite(n)?(Date.now()-n)/86400000:Infinity;};
const monthAge=s=>{if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(s||""))return Infinity;const [y,m]=s.split("-").map(Number),t=new Date();return (t.getUTCFullYear()-y)*12+t.getUTCMonth()+1-m;};
function add(tr,value){const td=document.createElement("td");td.textContent=String(value);tr.append(td);return td;}
function render(data){
 body.replaceChildren();let available=0,partial=0,stale=0,pending=0;
 for(const item of specs){
   const period=item.period?.(data),value=item.value?.(data);
   const age=item.kind==="month"?monthAge(period):dayAge(period);
   const fresh=age>=0&&age<=item.maxAge;
   const valid=finite(value)&&fresh;
   const status=valid?(item.partial?"仅部分接入":"可用观测"):finite(value)?"过期观测":"待接入／数据缺失";
   if(valid){if(item.partial)partial++;else available++;}else if(finite(value))stale++;else pending++;
   const tr=document.createElement("tr");add(tr,item.name);
   add(tr,valid?(item.display?item.display(data):value.toLocaleString("en-US",{maximumFractionDigits:3})+" "+item.unit):"—");
   add(tr,typeof period==="string"?period:"—");
   const st=add(tr,status);st.className=valid?"obs-verified":finite(value)?"obs-stale":"obs-missing";
   const td=document.createElement("td"),a=document.createElement("a");
   a.href=item.url;a.target="_blank";a.rel="noopener noreferrer";a.textContent=item.source;td.append(a);
   if(item.note){td.append(document.createTextNode(" · "+item.note));}tr.append(td);body.append(tr);
 }
 const at=data.generated_at&&Number.isFinite(Date.parse(data.generated_at))?new Date(data.generated_at).toISOString().slice(0,16).replace("T"," ")+" UTC":"生成时间未知";
 summary.textContent="A级10项：完整可用 "+available+"、部分接入 "+partial+"、过期 "+stale+"、待接入/缺失 "+pending+"；快照生成于 "+at+"。本表是指标数据可用性，不是投资资产评分。";
}
async function main(){
 try{
   const r=await fetch("../data/asset-scores.json",{cache:"no-store"});
   if(!r.ok)throw Error("HTTP "+r.status);
   const d=await r.json();
   if(d?.schema_version!==1||typeof d.generated_at!=="string"||!Number.isFinite(Date.parse(d.generated_at))||Date.parse(d.generated_at)>Date.now()+3600000)throw Error("快照格式或生成时间异常");
   try{
     const r2=await fetch("../data/asset-compass-a10-sofr.json",{cache:"no-store"});
     if(r2.ok){
       const sof=await r2.json();
       if(sof?.schema_version===1&&sof.report_type==="asset_compass_a10_sofr_observation"&&
          sof.sofr_forward_curve_available===false&&sof.validated_for_live_scoring===false&&
          sof.eligible_for_point_in_time_backtest===false&&
          typeof sof.observation_date==="string"&&typeof sof.sofr_overnight_percent==="number")
           d.a10sofr=sof;
     }
   }catch(_){/* optional SOFR file: main catalog remains functional */ }
   render(d);
 }catch(e){
   summary.textContent="A级指标数据暂未通过校验："+e.message+"；不以模拟数字填充。";
   body.replaceChildren();
   for(const item of specs){const tr=document.createElement("tr");for(const v of [item.name,"—","—","暂不可核验",item.source])add(tr,v);body.append(tr);}
 }
}
void main();
})();
