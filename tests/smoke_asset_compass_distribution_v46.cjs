"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const root=path.resolve(__dirname,"..");
const script=fs.readFileSync(path.join(root,"macro/treasury-trends.js"),"utf8");
const history=JSON.parse(fs.readFileSync(path.join(root,"data/asset-compass-treasury-history.json"),"utf8"));
const ids=["treasury-rate-distribution","treasury-period-statistics",
 "treasury-trend-svg","treasury-trend-status","treasury-trend-meta","treasury-trend-table",
 "treasury-trend-legend","treasury-trend-difference","treasury-trend-probe",
 "treasury-compare-start","treasury-compare-end","treasury-compare-result"];
class E{
 constructor(tag="div"){this.tagName=tag;this.textContent="";this.children=[];this.value="";this.attributes={};this.className="";}
 append(...xs){this.children.push(...xs)}
 replaceChildren(...xs){this.children=xs}
 setAttribute(k,v){this.attributes[k]=v}
 getBoundingClientRect(){return{left:0,width:720}}
}
function setup(){
 const nodes=Object.fromEntries(ids.map(id=>[id,new E()]));
 const document={body:{dataset:{page:"test"}},getElementById:id=>nodes[id]||null,
  createElement:tag=>new E(tag),createElementNS:(_,tag)=>new E(tag)};
 const ctx=vm.createContext({document,Date,URL,Number,Math,Object,Array,Set,console});
 vm.runInContext(script,ctx,{filename:"macro/treasury-trends.js"});ctx.history=history;
 return{ctx,nodes};
}
function run(ctx,s){return vm.runInContext(s,ctx)}
function textTree(el){return [el.textContent,...el.children.map(textTree)].join(" ")}
function test(name,fn){try{fn();console.log("PASS",name)}catch(e){console.error("FAIL",name);throw e}}
test("verified actual history produces four series with empirical midrank and signed move bins",()=>{
 const {ctx}=setup();
 run(ctx,"TREASURY_TRENDS.validate(history)");
 for(const key of ["us10y","real10y","breakeven10y","spread10y2y"]){
  ctx.key=key;
  const r=run(ctx,'TREASURY_TRENDS.rateDistribution(history.observations,key)');
  assert.equal(r.levelCount,history.observation_count);
  assert.equal(r.changeCount,r.levelCount-1);
  assert.equal(r.bins.reduce((total,b)=>total+b.count,0),r.changeCount);
  assert.ok(r.percentile>0&&r.percentile<100);
  assert.equal(r.percentile,100*(r.lowerCount+r.equalCount/2)/r.levelCount);
  assert.equal(r.largest.length,5);
  assert.equal(r.latestMove.date,history.end_date);
  assert.equal(r.latestFlagged,r.latestMove.absoluteBp>=r.cutoff95AbsBp);
  assert.ok(r.cutoff95AbsBp>=0);
 }
});
test("tied levels receive middle empirical rank, not range position or probability",()=>{
 const {ctx}=setup();ctx.rows=[
  {date:"2026-11-17",us10y:1},
  {date:"2026-11-18",us10y:2},
  {date:"2026-11-19",us10y:2},
  {date:"2026-11-20",us10y:2}
 ];
 const r=run(ctx,'TREASURY_TRENDS.rateDistribution(rows,"us10y")');
 assert.equal(r.percentile,62.5);
 assert.equal(r.lowerCount,1);
 assert.equal(r.equalCount,3);
 assert.equal(r.changeCount,3);
});
test("exact bucket boundaries and all-zero moves are counted once",()=>{
 const {ctx}=setup(),bp=[-20,-10,-5,0,5,10,20];
 let value=0;ctx.rows=[{date:"2026-11-01",us10y:0}];
 const day=2;
 for(let i=0;i<bp.length;i++){
  value+=bp[i]/100;ctx.rows.push({date:"2026-11-"+String(i+2).padStart(2,"0"),us10y:value});
 }
 const r=run(ctx,'TREASURY_TRENDS.rateDistribution(rows,"us10y")');
 assert.deepEqual(Array.from(r.bins,x=>x.count),[1,1,1,1,1,1,1]);
 assert.equal(r.bins.reduce((sum,b)=>sum+b.count,0),7);
});
test("large move flagged by in-sample absolute p95, largest dates are actual pairs",()=>{
 const {ctx}=setup();ctx.rows=[
  {date:"2026-11-16",real10y:1},
  {date:"2026-11-17",real10y:1.01},
  {date:"2026-11-18",real10y:1.02},
  {date:"2026-11-19",real10y:1.03},
  {date:"2026-11-20",real10y:1.53}
 ];
 const r=run(ctx,'TREASURY_TRENDS.rateDistribution(rows,"real10y")');
 assert.equal(r.latestFlagged,true);
 assert.equal(r.largest[0].date,"2026-11-20");
 assert.equal(r.largest[0].previousDate,"2026-11-19");
 assert.ok(r.cutoff95AbsBp<50&&r.cutoff95AbsBp>0);
});
test("short, unsorted, invalid and unknown series fail without invented statistics",()=>{
 const {ctx}=setup();
 for(const command of [
  'TREASURY_TRENDS.rateDistribution([],"us10y")',
  'TREASURY_TRENDS.rateDistribution(history.observations,"bitcoin")'
 ])assert.equal(run(ctx,command),null);
 ctx.bad=[
  {date:"2026-11-17",us10y:3},
  {date:"2026-11-17",us10y:3.1},
  {date:"2026-11-20",us10y:3.2}
 ];
 assert.equal(run(ctx,'TREASURY_TRENDS.rateDistribution(bad,"us10y")'),null);
 ctx.bad[1].date="2026-02-30";
 assert.equal(run(ctx,'TREASURY_TRENDS.rateDistribution(bad,"us10y")'),null);
});
test("existing plot renders V45 statistics plus two V46 distribution panels",()=>{
 const {ctx,nodes}=setup();
 run(ctx,'TREASURY_TRENDS.plot(history,"us10y","1y","real10y")');
 const dist=nodes["treasury-rate-distribution"];
 assert.equal(dist.children.length,2);
 assert.equal(dist.children[1].children.length,2);
 for(const item of dist.children[1].children){
  const tree=textTree(item);
  assert.match(tree,/历史区间/);
  assert.match(tree,/收益率经验分位/);
  assert.match(tree,/单次观测间变化分布/);
  assert.match(tree,/绝对变化最大的5个/);
 }
 assert.match(textTree(dist),/不构成实时预警、资产评分或预测/);
});
test("single curve has one panel and empty history clears stale stats",()=>{
 const {ctx,nodes}=setup();
 run(ctx,'TREASURY_TRENDS.plot(history,"us10y","3m","none")');
 assert.equal(nodes["treasury-rate-distribution"].children[1].children.length,1);
 ctx.empty={observations:[]};
 run(ctx,'TREASURY_TRENDS.plot(empty,"us10y","1y","none")');
 assert.equal(nodes["treasury-rate-distribution"].children.length,1);
 assert.match(textTree(nodes["treasury-rate-distribution"]),/至少需要3个真实/);
});
console.log("V46 empirical yield distributions and anomaly context passed.");
