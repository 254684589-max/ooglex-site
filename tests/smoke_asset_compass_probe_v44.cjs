"use strict";
// V44 tests actual production chart JS against committed official history.
const assert=require("node:assert/strict"),fs=require("node:fs"),
path=require("node:path"),vm=require("node:vm");
const ROOT=path.resolve(__dirname,"..");
const script=fs.readFileSync(path.join(ROOT,"macro/treasury-trends.js"),"utf8");
const history=JSON.parse(fs.readFileSync(path.join(ROOT,"data/asset-compass-treasury-history.json"),"utf8"));
const ids=["treasury-trend-svg","treasury-trend-status","treasury-trend-meta",
 "treasury-trend-table","treasury-trend-series","treasury-trend-range",
 "treasury-trend-compare","treasury-trend-legend","treasury-trend-difference",
 "treasury-trend-panel","treasury-trend-probe","treasury-compare-start",
 "treasury-compare-end","treasury-compare-result"];
class E{
 constructor(tag="div"){this.tagName=tag;this.children=[];this.events={};
  this.attributes={};this.textContent="";this.value="";}
 setAttribute(k,v){this.attributes[k]=v}
 append(...nodes){this.children.push(...nodes)}
 replaceChildren(...nodes){this.children=nodes;if(this.tagName==="select")this.value=""}
 addEventListener(type,fn){this.events[type]=fn}
 getBoundingClientRect(){return {left:100,width:720}}
}
function setup(){
 const nodes=Object.fromEntries(ids.map(k=>[k,new E(k.includes("compare-start")||k.includes("compare-end")?"select":"div")]));
 nodes["treasury-trend-series"].value="us10y";
 nodes["treasury-trend-compare"].value="real10y";
 nodes["treasury-trend-range"].value="all";
 const document={body:{dataset:{page:"not-auto"}},getElementById:k=>nodes[k]||null,
  createElement:tag=>new E(tag),createElementNS:(_,tag)=>new E(tag)};
 const ctx=vm.createContext({document,Date,URL,Math,Number,Object,Array,Set,console,Promise,
  window:{},fetch:async()=>({ok:true,json:async()=>history})});
 vm.runInContext(script,ctx,{filename:"treasury-trends.js"});
 ctx.data=history;return {ctx,nodes};
}
function run(ctx,source){return vm.runInContext(source,ctx)}
function test(name,fn){try{fn();console.log("PASS",name)}catch(e){console.error("FAIL",name);throw e}}
test("V44 real history exactly validates without falsely claiming original release PIT",()=>{
 const {ctx}=setup(),d=run(ctx,"TREASURY_TRENDS.validate(data)");
 assert.ok(d.observation_count>=100);
 assert.equal(d.original_release_vintages_available,false);
 assert.equal(d.not_valid_for_point_in_time_backtest,true);
});
test("comparison uses actual first/last observation and correct signed pp/bp",()=>{
 const {ctx}=setup();ctx.a=history.observations[0].date;
 ctx.b=history.observations.at(-1).date;
 const result=run(ctx,'TREASURY_TRENDS.compareDates(data.observations,a,b,"us10y","real10y")');
 assert.equal(result.changes.length,2);
 const a=history.observations[0],b=history.observations.at(-1);
 assert.equal(result.changes[0].percentagePoints,b.us10y-a.us10y);
 assert.equal(result.changes[0].basisPoints,Math.round((b.us10y-a.us10y)*100));
 assert.equal(result.changes[1].basisPoints,Math.round((b.real10y-a.real10y)*100));
});
test("same-day comparison is exactly zero with no imputed market return",()=>{
 const {ctx}=setup();ctx.day=history.observations[8].date;
 const r=run(ctx,'TREASURY_TRENDS.compareDates(data.observations,day,day,"breakeven10y","none")');
 assert.equal(r.changes[0].percentagePoints,0);
 assert.equal(r.changes[0].basisPoints,0);
});
test("weekend, reversed dates, unknown metric and missing dates fail closed",()=>{
 const {ctx}=setup(),rows=history.observations;
 const start=rows[0].date,end=rows.at(-1).date;
 ctx.start=start;ctx.end=end;
 assert.equal(run(ctx,'TREASURY_TRENDS.compareDates(data.observations,end,start,"us10y","real10y")'),null);
 assert.equal(run(ctx,'TREASURY_TRENDS.compareDates(data.observations,"2020-01-01",end,"us10y","real10y")'),null);
 assert.equal(run(ctx,'TREASURY_TRENDS.compareDates(data.observations,start,end,"foo","us10y")'),null);
});
test("plot fills two exact-date selectors and renders true period changes",()=>{
 const {ctx,nodes}=setup();
 run(ctx,'TREASURY_TRENDS.plot(data,"us10y","3m","real10y")');
 const n=nodes["treasury-compare-start"].children.length;
 assert.ok(n>20&&n<100);
 assert.equal(nodes["treasury-compare-end"].children.length,n);
 assert.match(nodes["treasury-compare-result"].textContent,/bp/);
 assert.match(nodes["treasury-compare-result"].textContent,/非资产价格回报/);
 assert.match(nodes["treasury-trend-probe"].textContent,/移动鼠标/);
});
test("changing selected dates preserves choices and rejects end before start",()=>{
 const {ctx,nodes}=setup();
 run(ctx,'TREASURY_TRENDS.plot(data,"us10y","1y","real10y")');
 const s=nodes["treasury-compare-start"],e=nodes["treasury-compare-end"];
 s.value=s.children[2].value;e.value=e.children[9].value;
 s.onchange();assert.match(nodes["treasury-compare-result"].textContent,/变化/);
 const previous=[s.value,e.value];
 run(ctx,'TREASURY_TRENDS.plot(data,"real10y","1y","us10y")');
 assert.deepEqual([s.value,e.value],previous);
 e.value=e.children[0].value;e.onchange();
 assert.match(nodes["treasury-compare-result"].textContent,/起点不晚于终点/);
});
test("pointer movement probes nearest actual market observation, not a weekend",()=>{
 const {ctx,nodes}=setup();
 run(ctx,'TREASURY_TRENDS.plot(data,"us10y","all","real10y")');
 const plot=nodes["treasury-trend-svg"];
 assert.equal(typeof plot.onpointermove,"function");
 plot.onpointermove({clientX:100+62});
 assert.match(nodes["treasury-trend-probe"].textContent,new RegExp(history.start_date));
 plot.onpointermove({clientX:100+700});
 assert.match(nodes["treasury-trend-probe"].textContent,new RegExp(history.end_date));
 plot.onpointerleave();
 assert.match(nodes["treasury-trend-probe"].textContent,/移动鼠标/);
});
test("no chart UI or synthetic data when valid history is missing",()=>{
 const {ctx,nodes}=setup();ctx.invalid={observations:[]};
 run(ctx,'TREASURY_TRENDS.plot(invalid,"us10y","all","real10y")');
 assert.equal(nodes["treasury-compare-start"].children.length,0);
 assert.equal(nodes["treasury-trend-svg"].children.length,0);
 assert.match(nodes["treasury-compare-result"].textContent,/无可比较/);
});
console.log("V44 exact-observation date and basis-point tests passed");
