"use strict";
// Execute actual V45 production JavaScript against the repository's
// authenticated-source historical observations. No fabricated plot points.
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const root=path.resolve(__dirname,"..");
const script=fs.readFileSync(path.join(root,"macro/treasury-trends.js"),"utf8");
const history=JSON.parse(fs.readFileSync(path.join(root,"data/asset-compass-treasury-history.json"),"utf8"));
class Element{
 constructor(tag="div"){this.tagName=tag;this.textContent="";this.children=[];this.value="";this.attributes={};this.className="";}
 append(...nodes){this.children.push(...nodes)}
 replaceChildren(...nodes){this.children=nodes}
 setAttribute(key,value){this.attributes[key]=value}
 getBoundingClientRect(){return {left:0,width:720}}
}
const ids=["treasury-period-statistics","treasury-trend-svg","treasury-trend-status",
 "treasury-trend-meta","treasury-trend-table","treasury-trend-legend","treasury-trend-difference",
 "treasury-trend-probe","treasury-compare-start","treasury-compare-end","treasury-compare-result"];
function setup(){
 const nodes=Object.fromEntries(ids.map(id=>[id,new Element("div")]));
 const document={body:{dataset:{page:"test"}},getElementById:id=>nodes[id]||null,
  createElement:tag=>new Element(tag),createElementNS:(_,tag)=>new Element(tag)};
 const ctx=vm.createContext({document,Date,URL,Number,Math,Object,Array,Set,console});
 vm.runInContext(script,ctx);
 ctx.history=history;
 return {ctx,nodes};
}
function call(ctx,code){return vm.runInContext(code,ctx)}
function textTree(node){return [node.textContent,...node.children.map(textTree)].join(" ")}
function test(name,fn){try{fn();console.log("PASS",name)}catch(error){console.error("FAIL",name);throw error}}
test("real official source still passes V42 provenance validation",()=>{
 const {ctx}=setup();const doc=call(ctx,"TREASURY_TRENDS.validate(history)");
 assert.ok(doc.observation_count>=100);
 assert.equal(doc.not_valid_for_point_in_time_backtest,true);
});
test("3m 6m 1y statistics use only actual dated observations with exact max/min/mean",()=>{
 const {ctx}=setup();
 for(const key of ["us10y","real10y","breakeven10y","spread10y2y"]){
  for(const window of ["3m","6m","1y"]){
   ctx.key=key;ctx.window=window;
   const result=call(ctx,"TREASURY_TRENDS.periodStatistics(history.observations,key,window)");
   assert.ok(result&&result.sampleCount>2);
   assert.ok(result.minimum<=result.average&&result.average<=result.maximum);
   assert.ok(result.latest>=result.minimum&&result.latest<=result.maximum);
   assert.ok(history.observations.some(r=>r.date===result.minimumDate&&r[key]===result.minimum));
   assert.ok(history.observations.some(r=>r.date===result.maximumDate&&r[key]===result.maximum));
   assert.ok(history.observations.some(r=>r.date===result.startDate));
   assert.equal(result.endDate,history.observations.at(-1).date);
   const matching=history.observations.filter(r=>r.date>=result.startDate&&r.date<=result.endDate);
   const arithmetic=matching.reduce((s,r)=>s+r[key],0)/matching.length;
   assert.ok(Math.abs(result.average-arithmetic)<1e-10);
   assert.equal(result.changeBasisPoints,Math.round((matching.at(-1)[key]-matching[0][key])*100));
  }
 }
});
test("negative yields and decreasing yields retain signs; no investment-score conversion",()=>{
 const {ctx}=setup();
 ctx.rows=[
  {date:"2026-11-18",us10y:-0.20},
  {date:"2026-11-19",us10y:-0.30},
  {date:"2026-11-20",us10y:-0.50}
 ];
 const r=call(ctx,'TREASURY_TRENDS.periodStatistics(rows,"us10y","3m")');
 assert.equal(r.changeBasisPoints,-30);
 assert.equal(r.minimum,-0.5);
 assert.equal(r.maximum,-0.2);
 assert.equal(r.rangePosition,0);
});
test("flat range position is null (not invented midpoint or percentile)",()=>{
 const {ctx}=setup();ctx.rows=[
  {date:"2026-11-19",real10y:2.1},{date:"2026-11-20",real10y:2.1}
 ];
 const r=call(ctx,'TREASURY_TRENDS.periodStatistics(rows,"real10y","3m")');
 assert.equal(r.rangePosition,null);
 assert.equal(r.changeBasisPoints,0);
});
test("missing values, unknown field, invalid window and short history fail closed",()=>{
 const {ctx}=setup();
 for(const code of [
  'TREASURY_TRENDS.periodStatistics([], "us10y", "3m")',
  'TREASURY_TRENDS.periodStatistics(history.observations, "oil", "1y")',
  'TREASURY_TRENDS.periodStatistics(history.observations, "us10y", "wrong")'
 ])assert.equal(call(ctx,code),null);
 ctx.rows=[{date:"2026-11-20",us10y:2.1}];
 assert.equal(call(ctx,'TREASURY_TRENDS.periodStatistics(rows,"us10y","3m")'),null);
});
test("dual-series chart renders two 3-window tables using real official data",()=>{
 const {ctx,nodes}=setup();
 call(ctx,'TREASURY_TRENDS.plot(history,"us10y","1y","real10y")');
 const stat=nodes["treasury-period-statistics"];
 assert.equal(stat.children.length,2);
 const grid=stat.children[1];
 assert.equal(grid.children.length,2);
 for(const article of grid.children){
  const tbody=article.children[1].children[0].children[1];
  assert.equal(tbody.children.length,3);
  assert.equal(tbody.children[0].children.length,8);
 }
 const description=textTree(stat);
 assert.match(description,/最新值/);
 assert.match(description,/算术均值/);
 assert.match(description,/不是百分位、资产评分或涨跌预测/);
 assert.match(description,/bp/);
});
test("single chart displays one stats panel and no missing second series",()=>{
 const {ctx,nodes}=setup();call(ctx,'TREASURY_TRENDS.plot(history,"real10y","3m","none")');
 assert.equal(nodes["treasury-period-statistics"].children[1].children.length,1);
});
test("empty chart clears old statistics and refuses stale numeric display",()=>{
 const {ctx,nodes}=setup();
 call(ctx,'TREASURY_TRENDS.plot(history,"us10y","1y","real10y")');
 ctx.empty={observations:[]};
 call(ctx,'TREASURY_TRENDS.plot(empty,"us10y","1y","real10y")');
 assert.equal(nodes["treasury-period-statistics"].children.length,1);
 assert.match(textTree(nodes["treasury-period-statistics"]),/缺少经过核验的真实历史观测/);
});
console.log("V45 descriptive rates tests passed");
