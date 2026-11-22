"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const root=path.resolve(__dirname,"..");
const js=fs.readFileSync(path.join(root,"macro/treasury-trends.js"),"utf8");
const real=JSON.parse(fs.readFileSync(path.join(root,"data/asset-compass-treasury-history.json"),"utf8"));
const ids=["treasury-correlation","treasury-rate-distribution","treasury-period-statistics",
 "treasury-trend-svg","treasury-trend-status","treasury-trend-meta","treasury-trend-table",
 "treasury-trend-legend","treasury-trend-difference","treasury-trend-probe","treasury-compare-start",
 "treasury-compare-end","treasury-compare-result"];
class E{
 constructor(tag="div"){this.tagName=tag;this.textContent="";this.children=[];this.value="";this.attributes={};this.className="";}
 append(...a){this.children.push(...a)}replaceChildren(...a){this.children=a}
 setAttribute(k,v){this.attributes[k]=v}getBoundingClientRect(){return{left:0,width:720}}
}
function setup(){
 const nodes=Object.fromEntries(ids.map(id=>[id,new E()]));
 const document={body:{dataset:{page:"test"}},getElementById:k=>nodes[k]||null,
 createElement:tag=>new E(tag),createElementNS:(_,tag)=>new E(tag)};
 const ctx=vm.createContext({document,Date,URL,Math,Number,Object,Array,Set,String,Intl,console});
 vm.runInContext(js,ctx,{filename:"treasury-trends.js"});ctx.real=real;
 return{ctx,nodes};
}
const run=(ctx,s)=>vm.runInContext(s,ctx);
function tree(e){return[e.textContent,...e.children.map(tree)].join(" ")}
function test(n,fn){try{fn();console.log("PASS",n)}catch(e){console.error("FAIL",n);throw e}}
test("official Treasury provenance and 1472+ real paired changes",()=>{
 const{ctx}=setup();const verified=run(ctx,"TREASURY_TRENDS.validate(real)");
 assert.equal(verified.original_release_vintages_available,false);
 ctx.pairs=run(ctx,'TREASURY_TRENDS.pairedYieldChanges(real.observations,"us10y","real10y")');
 assert.equal(ctx.pairs.length,real.observation_count-1);
 const stats=run(ctx,"TREASURY_TRENDS.correlationStatistics(pairs)");
 assert.equal(stats.sampleCount,ctx.pairs.length);
 assert.equal(stats.concordant+stats.discordant+stats.neutral,stats.sampleCount);
 assert.ok(stats.correlation>=-1&&stats.correlation<=1);
 assert.ok(stats.sameDirectionFraction>=0&&stats.sameDirectionFraction<=1);
});
test("exact calendar-matched changes and consistency with raw bp arithmetic",()=>{
 const{ctx}=setup();
 const pairs=run(ctx,'TREASURY_TRENDS.pairedYieldChanges(real.observations,"us10y","real10y")');
 const a=real.observations[0],b=real.observations[1];
 assert.equal(pairs[0].date,b.date);
 assert.equal(pairs[0].x,Math.round((b.us10y-a.us10y)*10000)/100);
 assert.equal(pairs[0].y,Math.round((b.real10y-a.real10y)*10000)/100);
});
test("perfect positive/negative and zero-variance correlation",()=>{
 const{ctx}=setup();ctx.positive=Array.from({length:20},(_,i)=>({date:String(i),x:i,y:i*3}));
 ctx.negative=Array.from({length:20},(_,i)=>({date:String(i),x:i,y:-i}));
 ctx.flat=Array.from({length:20},(_,i)=>({date:String(i),x:i,y:0}));
 assert.ok(Math.abs(run(ctx,"TREASURY_TRENDS.correlationStatistics(positive).correlation")-1)<1e-12);
 assert.ok(Math.abs(run(ctx,"TREASURY_TRENDS.correlationStatistics(negative).correlation")+1)<1e-12);
 assert.equal(run(ctx,"TREASURY_TRENDS.correlationStatistics(flat).correlation"),null);
});
test("zero change excluded from directional denominator; no artificial 100% on zero-only",()=>{
 const{ctx}=setup();ctx.pairs=Array.from({length:12},(_,i)=>({date:String(i),x:i===0?1:0,y:i===0?1:0}));
 const a=run(ctx,"TREASURY_TRENDS.correlationStatistics(pairs)");
 assert.equal(a.concordant,1);assert.equal(a.neutral,11);assert.equal(a.sameDirectionFraction,1);
 ctx.pairs=Array.from({length:12},(_,i)=>({date:String(i),x:0,y:0}));
 const b=run(ctx,"TREASURY_TRENDS.correlationStatistics(pairs)");
 assert.equal(b.sameDirectionFraction,null);assert.equal(b.correlation,null);
});
test("rolling windows use 20 and 60 actual adjacent-pair observations",()=>{
 const{ctx}=setup();ctx.pairs=run(ctx,'TREASURY_TRENDS.pairedYieldChanges(real.observations,"us10y","real10y")');
 for(const w of [20,60]){
  ctx.w=w;const out=run(ctx,"TREASURY_TRENDS.rollingCorrelations(pairs,w)");
  assert.equal(out.length,ctx.pairs.length-w+1);
  assert.equal(out.at(-1).date,real.end_date);
  assert.ok(out.filter(x=>x.correlation!==null).every(x=>x.correlation>=-1&&x.correlation<=1));
 }
 assert.equal(run(ctx,"TREASURY_TRENDS.rollingCorrelations(pairs,21).length"),0);
});
test("reject duplicate and unsorted dates, missing values, same variable and unrecognized identifiers",()=>{
 const{ctx}=setup();ctx.bad=structuredClone(real.observations.slice(0,11));
 ctx.bad[1].date=ctx.bad[0].date;
 assert.equal(run(ctx,'TREASURY_TRENDS.pairedYieldChanges(bad,"us10y","real10y")'),null);
 ctx.bad[1].date="2026-02-30";
 assert.equal(run(ctx,'TREASURY_TRENDS.pairedYieldChanges(bad,"us10y","real10y")'),null);
 assert.equal(run(ctx,'TREASURY_TRENDS.pairedYieldChanges(real.observations,"us10y","us10y")'),null);
 assert.equal(run(ctx,'TREASURY_TRENDS.pairedYieldChanges(real.observations,"btc","real10y")'),null);
});
test("live plot renders paired statistics with non-independent signal warning",()=>{
 const{ctx,nodes}=setup();
 run(ctx,'TREASURY_TRENDS.plot(real,"us10y","1y","real10y")');
 const p=nodes["treasury-correlation"];
 assert.equal(p.children.length,3);
 const t=tree(p);
 assert.match(t,/同期变化样本/);assert.match(t,/Pearson/);
 assert.match(t,/滚动 20 组/);assert.match(t,/滚动 60 组/);
 assert.match(t,/存在代数依赖/);assert.match(t,/不能被当作独立证据/);
});
test("single curve and absent history fail closed with honest messages",()=>{
 const{ctx,nodes}=setup();
 run(ctx,'TREASURY_TRENDS.plot(real,"us10y","3m","none")');
 assert.match(tree(nodes["treasury-correlation"]),/请选择不同/);
 ctx.empty={observations:[]};
 run(ctx,'TREASURY_TRENDS.plot(empty,"us10y","1y","real10y")');
 assert.match(tree(nodes["treasury-correlation"]),/不足10组/);
});
console.log("V47 historical correlation and algebraic-dependence checks passed.");
