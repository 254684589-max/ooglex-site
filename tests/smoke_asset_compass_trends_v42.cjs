"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm"),path=require("node:path");
const script=fs.readFileSync(path.resolve(__dirname,"../macro/treasury-trends.js"),"utf8");
class Element {
 constructor(tag){this.tagName=tag;this.children=[];this.attributes={};this.events={};this.value="";}
 setAttribute(key,value){this.attributes[key]=value}
 append(...nodes){this.children.push(...nodes)}
 replaceChildren(...nodes){this.children=nodes}
 addEventListener(name,fn){this.events[name]=fn}
}
function makeContext(){
 const ids=["treasury-trend-svg","treasury-trend-status","treasury-trend-meta","treasury-trend-table","treasury-trend-series","treasury-trend-range"];
 const nodes=Object.fromEntries(ids.map(k=>[k,new Element(k)]));
 const document={body:{dataset:{page:"offline-test"}},getElementById:k=>nodes[k]||null,
   createElement:tag=>new Element(tag),createElementNS:(ns,tag)=>new Element(tag)};
 const ctx=vm.createContext({document,Date,URL,Number,Math,Object,Array,Set,Error,console});
 vm.runInContext(script,ctx,{filename:"treasury-trends.js"});
 return {nodes,ctx};
}
function records(){
 const dates=["2026-11-17","2026-11-18","2026-11-19","2026-11-20"];
 return dates.map((date,i)=>{
  const us10y=4.3+i/10,us2y=4.1+i/10,real10y=2+i/10;
  return {date,us10y,us2y,real10y,breakeven10y:+(us10y-real10y).toFixed(3),spread10y2y:+(us10y-us2y).toFixed(3)};
 });
}
function fixture(){
 const rows=records(),u="https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/2026/all?";
 return {
  schema_version:1,dataset:"treasury_historical_daily_observations",
  source:"U.S. Department of the Treasury",retrieved_at:"2026-11-22T08:00:00Z",
  original_release_vintages_available:false,not_valid_for_point_in_time_backtest:true,
  observation_count:rows.length,start_date:rows[0].date,end_date:rows.at(-1).date,
  source_urls:[u+"type=daily_treasury_yield_curve&field_tdr_date_value=2026",u+"type=daily_treasury_real_yield_curve&field_tdr_date_value=2026"],
  observations:rows
 };
}
function test(name,fn){try{fn();console.log("PASS",name)}catch(err){console.log("FAIL",name);throw err}}
test("V42 validates genuine schema and Treasury observation-only safeguard",()=>{
 const {ctx}=makeContext();ctx.data=fixture();
 const validated=vm.runInContext("TREASURY_TRENDS.validate(data)",ctx);
 assert.equal(validated.observation_count,4);
 assert.equal(validated.original_release_vintages_available,false);
});
test("V42 draws real path, SVG accessible labels, and exact historical rows",()=>{
 const {ctx,nodes}=makeContext();ctx.data=fixture();
 vm.runInContext('TREASURY_TRENDS.plot(TREASURY_TRENDS.validate(data),"us10y","all")',ctx);
 assert.ok(nodes["treasury-trend-svg"].children.some(c=>c.tagName==="path"));
 assert.equal(nodes["treasury-trend-svg"].attributes.role,"img");
 assert.equal(nodes["treasury-trend-table"].children.length,4);
 assert.match(nodes["treasury-trend-status"].textContent,/4 个匹配观测日/);
 assert.match(nodes["treasury-trend-meta"].textContent,/不能直接用于当年可得信息回测/);
});
test("V42 four measures have distinct chart labels without model scores",()=>{
 const {ctx,nodes}=makeContext();ctx.data=fixture();
 for(const name of ["us10y","real10y","breakeven10y","spread10y2y"]){
  ctx.name=name;
  vm.runInContext('TREASURY_TRENDS.plot(TREASURY_TRENDS.validate(data),name,"all")',ctx);
  assert.equal(nodes["treasury-trend-table"].children.length,4);
  assert.ok(nodes["treasury-trend-svg"].children.some(c=>c.tagName==="path"));
 }
 assert.match(nodes["treasury-trend-status"].textContent,/10Y−2Y期限利差/);
});
test("V42 refuses fake source domain or PIT authorization",()=>{
 const {ctx}=makeContext();
 for(const fault of ["host","pit","formula","order","future"]){
  const d=fixture();
  if(fault==="host")d.source_urls[0]=d.source_urls[0].replace("home.treasury.gov","home.treasury.gov.attacker.test");
  if(fault==="pit")d.original_release_vintages_available=true;
  if(fault==="formula")d.observations[0].breakeven10y=9;
  if(fault==="order")d.observations[1].date=d.observations[0].date;
  if(fault==="future"){d.observations[3].date="2099-01-01";d.end_date="2099-01-01"}
  ctx.data=d;assert.throws(()=>vm.runInContext("TREASURY_TRENDS.validate(data)",ctx),{name:"Error"});
 }
});
test("V42 recent window does not synthesize points",()=>{
 const {ctx}=makeContext();ctx.data=fixture();
 assert.equal(vm.runInContext('TREASURY_TRENDS.selectWindow(data,"3m").length',ctx),4);
 assert.equal(vm.runInContext('TREASURY_TRENDS.selectWindow(data,"1y").length',ctx),4);
});
test("V42 missing historical archive fails closed",async()=>{
 const {ctx,nodes}=makeContext();
 ctx.fetch=async()=>({ok:false,status:404});
 ctx.document.getElementById("treasury-trend-series").value="us10y";
 ctx.document.getElementById("treasury-trend-range").value="1y";
 await vm.runInContext("TREASURY_TRENDS.init()",ctx);
 assert.match(nodes["treasury-trend-status"].textContent,/历史趋势尚不可用/);
 assert.equal(nodes["treasury-trend-svg"].children.length,0);
});
(async()=>{await (async()=>{})();console.log("V42 chart smoke test complete")})().catch(e=>{throw e});
