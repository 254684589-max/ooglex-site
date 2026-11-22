"use strict";
/* V9 Operations console — evidence and as-published monitoring only.
   Never claim a successful collector run based solely on a non-null observation. */
(()=>{
const $=id=>document.getElementById(id),now=Date.now();
const day=s=>{if(typeof s!=="string"||!/^\d{4}-\d{2}-\d{2}$/.test(s))return NaN;const n=Date.parse(s+"T00:00:00Z");return Number.isFinite(n)&&new Date(n).toISOString().slice(0,10)===s?n:NaN};
const monthly=s=>{if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(s||""))return Infinity;const [y,m]=s.split("-").map(Number),d=new Date();return (d.getUTCFullYear()-y)*12+d.getUTCMonth()+1-m};
const age=s=>(now-day(s))/86400000;
function cell(tr,value,className){const td=document.createElement("td");td.textContent=String(value);if(className)td.className=className;tr.append(td);return td}
function add(tbody,values,classes=[]){const tr=document.createElement("tr");values.forEach((v,i)=>cell(tr,v,classes[i]));tbody.append(tr)}
function safeDate(s){return typeof s==="string"&&s.length>=7?s:"—"}
function sourceRow(tbody,name,period,limit,source,url,kind){const months=kind==="month",a=months?monthly(period):age(period),valid=Number.isFinite(a)&&a>=0&&a<=limit;
const label=valid?"观测期在阈值内":"过期或缺失";const tr=document.createElement("tr");
cell(tr,name);cell(tr,safeDate(period));cell(tr,limit+(months?"自然月":"自然日"));cell(tr,label,valid?"ops-good":"ops-pending");
const td=document.createElement("td");if(url){const link=document.createElement("a");link.href=url;link.target="_blank";link.rel="noopener noreferrer";link.textContent=source;td.append(link)}else td.textContent=source;tr.append(td);tbody.append(tr)}
async function get(path){const response=await fetch(path,{cache:"no-store"});if(!response.ok)throw new Error(path+": HTTP "+response.status);return response.text()}
function assert(condition,msg){if(!condition)throw new Error(msg)}
function safeJSON(raw,path){try{return JSON.parse(raw)}catch{throw Error("JSON格式错误："+path)}}
function render(s,ready,v7,v8,events){
assert(s?.schema_version===1&&s.assets&&typeof s.generated_at==="string","宏观快照结构无效");
assert(ready?.report_type==="asset_compass_history_readiness"&&ready.validated_for_live_scoring===false,"归档报告结构或门禁异常");
assert(v7?.report_type==="asset_compass_v7_treasury_provenance"&&v7.validated_for_live_scoring===false,"V7报告无效");
assert(v8?.report_type==="asset_compass_monitor_v8"&&v8.validated_for_live_scoring===false&&Array.isArray(v8.issues),"V8报告无效");
assert(typeof v8.checked_at==="string"&&Number.isFinite(Date.parse(v8.checked_at)),"V8时间不可验证");
const checkedAge=(now-Date.parse(v8.checked_at))/3600000;
assert(checkedAge>=-0.5,"V8报告时间异常");
const monitorFresh=checkedAge<=36,ok=monitorFresh&&v8.operational_status==="healthy"&&v8.issues.length===0;
$("ops-health").textContent=!monitorFresh?"报告过期":ok?"运行正常":"发现异常";
$("ops-health").className=ok?"ops-good":"ops-bad";
$("ops-last").textContent="上次检查："+v8.checked_at;
$("ops-streak").textContent=Number.isInteger(v8.consecutive_alert_runs)?v8.consecutive_alert_runs:"—";
$("ops-archive").textContent=Number.isInteger(ready.archived_observations)?String(ready.archived_observations):"—";
$("ops-score").textContent=Object.values(s.assets).every(a=>a?.score===null)&&ready.validated_for_live_scoring===false?"关闭":"异常，需审核";
$("ops-score").className=$("ops-score").textContent==="关闭"?"ops-pending":"ops-bad";
$("ops-loading").textContent=ok?"监控报告在时效内且最近一次运行检查通过；不代表所有数据源实时在线。":!monitorFresh?"V8监控报告已超过36小时，当前运行健康无法确认。":"V8报告显示异常，请查看任务日志与阻断项。";
const tb=$("ops-sources");tb.replaceChildren();
sourceRow(tb,"美国财政部 · 10Y/2Y/TIPS",s.observation_date,7,"US Treasury","https://home.treasury.gov/resource-center/data-chart-center/interest-rates","day");
sourceRow(tb,"美国劳工统计局 · 失业率",s.bls?.series?.unemployment?.period,2,"BLS","https://www.bls.gov/cps/","month");
sourceRow(tb,"美国劳工统计局 · CPI",s.bls?.series?.cpi?.period,2,"BLS","https://www.bls.gov/cpi/","month");
sourceRow(tb,"美国经济分析局 · 核心PCE",s.bea?.core_pce?.observation_period,3,"BEA/FRED","https://www.bea.gov/data/personal-consumption-expenditures-price-index","month");
sourceRow(tb,"美联储 · H.4.1总资产",s.fed_h41?.total_assets?.observation_date,14,"Federal Reserve","https://www.federalreserve.gov/releases/h41/","day");
sourceRow(tb,"美联储 · 准备金",s.liquidity?.reserves?.observation_date,14,"Federal Reserve/FRED","https://fred.stlouisfed.org/series/WRESBAL","day");
sourceRow(tb,"纽约联储 · EFFR",s.nyfed?.observation_date,10,"NY Fed","https://www.newyorkfed.org/markets/reference-rates/effr","day");
sourceRow(tb,"纽约联储 · 衰退概率模型",s.nyfed_recession_model?.observation_period,3,"NY Fed","https://www.newyorkfed.org/research/capital_markets/ycfaq.html","month");
const ar=$("ops-archive-rows");ar.replaceChildren();const entries=Object.entries(ready.series||{}).sort(([a],[b])=>a.localeCompare(b));for(const [name,x]of entries)add(ar,[name,x.archived_versions??"—",x.distinct_observation_periods??"—",safeDate(x.latest_recorded_at)]);
$("ops-archive-note").textContent="已记录 "+entries.length+" 个系列；累计 "+ready.archived_observations+" 条不可变归档版本。当前V8事件不含每次归档行数，因此无法计算真实逐次增量；不以记录总数冒充新增数据。";
const ev=$("ops-events");ev.replaceChildren();let lines=events.split("\n").filter(Boolean),accepted=[];for(const line of lines){try{const x=JSON.parse(line);if(x&&Number.isFinite(Date.parse(x.checked_at))&&["healthy","alert"].includes(x.operational_status)&&Array.isArray(x.issues))accepted.push(x)}catch{}}
accepted.sort((a,b)=>Date.parse(b.checked_at)-Date.parse(a.checked_at));for(const x of accepted.slice(0,30))add(ev,[x.checked_at,x.run_id??"—",x.operational_status==="healthy"?"正常":"异常",x.consecutive_alert_runs??"—",x.issues.length?x.issues.map(z=>z.code).join("、"):"无"],["","","",x.operational_status==="healthy"?"ops-good":"ops-bad"]);
if(!accepted.length)add(ev,["—","—","无有效历史事件","—","—"]);
$("ops-events-note").textContent="实际已解析 "+accepted.length+" 条监控事件，仅展示最近30条。历史增量和GitHub任务结论需要更多流水线证据，不能由该事件列表推断。";
const gate=$("ops-blockers");gate.replaceChildren();
add(gate,["V7来源归档",v7.integrity_gate_passed===true&&v7.unexpected_mismatch_rows===0?"来源一致性通过":"异常","遗留隔离："+v7.legacy_quarantined_rows+"；新增异常："+v7.unexpected_mismatch_rows]);
add(gate,["历史PIT版本","未准入","历史首发时点未核验；当前首次采集记录不等同官方首发版本"]);
for(const code of ready.blockers||[])add(gate,["准入阻断", "未通过",code]);
for(const issue of v8.issues)add(gate,["运行监控："+issue.code,"异常",issue.detail]);
if(ready.validated_for_live_scoring!==false)add(gate,["安全门禁","严重异常","评分禁用标识异常"]);
}
async function init(){
try{const files=["../data/asset-scores.json","../data/asset-compass-history-readiness.json","../data/asset-compass-provenance-v7.json","../data/asset-compass-monitor-v8.json","../data/asset-compass-monitor-events-v8.jsonl"];const text=await Promise.all(files.map(get));
render(safeJSON(text[0],files[0]),safeJSON(text[1],files[1]),safeJSON(text[2],files[2]),safeJSON(text[3],files[3]),text[4]);
}catch(e){$("ops-loading").textContent="运营证据核验失败："+e.message+"。不显示未经核验的运行正常状态。";$("ops-health").textContent="无法确认";$("ops-health").className="ops-bad"}}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",init,{once:true});else init();
})();