"use strict";
// V49 tests *real repo snapshots* and production browser JS.
// The 14 source rows can be observed but none can silently earn scores.
const assert=require("node:assert/strict"),fs=require("node:fs"),
 path=require("node:path"),vm=require("node:vm");
const root=path.resolve(__dirname,"..");
const source=fs.readFileSync(path.join(root,"macro/compass-pages.js"),"utf8");
const scores=JSON.parse(fs.readFileSync(path.join(root,"data/asset-scores.json"),"utf8"));
const readiness=JSON.parse(fs.readFileSync(path.join(root,"data/asset-compass-history-readiness.json"),"utf8"));
const report=JSON.parse(fs.readFileSync(path.join(root,"data/asset-compass-factor-observations.json"),"utf8"));
class E{
 constructor(tag="div"){this.tagName=tag;this.children=[];this.textContent="";this.className="";this.events={};this.value="";this.dataset={};this.attributes={};}
 append(...x){this.children.push(...x)}replaceChildren(...x){this.children=x}
 addEventListener(k,fn){this.events[k]=fn}setAttribute(k,v){this.attributes[k]=v}
 get firstChild(){return this.children[0]}
}
function setup(){
 const ids=["factor-qualification","indicator-independence","source-status","overview-kpis",
 "macro-table-body","indicator-search","indicator-filter","indicator-count","headline",
 "asset-grid","asset-insights","history-status"];
 const nodes=Object.fromEntries(ids.map(id=>[id,new E()]));
 const document={body:{dataset:{page:"v49-test"}},querySelector:q=>nodes[q.slice(1)]||null,
  querySelectorAll:q=>[],createElement:tag=>new E(tag)};
 const ctx=vm.createContext({document,Date,Number,Object,Set,String,Intl,Array,Math,console});
 vm.runInContext(source,ctx,{filename:"compass-pages.js"});
 ctx.scores=scores;ctx.readiness=readiness;ctx.report=report;
 return{ctx,nodes};
}
const run=(ctx,script)=>vm.runInContext(script,ctx);
const tree=e=>[e.textContent,...e.children.map(tree)].join(" ");
function test(name,fn){try{fn();console.log("PASS",name)}catch(e){console.error("FAIL",name);throw e}}
test("V49 authentic readiness is observation archive, not original publication PIT",()=>{
 assert.equal(readiness.validated_for_live_scoring,false);
 assert.equal(readiness.eligible_for_point_in_time_backtest,false);
 assert.ok(readiness.archived_observations>=0);
 assert.ok(readiness.blockers.includes("official_historical_release_vintages_unverified"));
 assert.equal(report.validated_for_live_scoring,false);
 assert.equal(report.factor_signals_calibrated,false);
});
test("all 14 source series have individual 252 daily / 104 weekly / 36 monthly history thresholds",()=>{
 const{ctx}=setup();
 const result=run(ctx,"factorQualification(overviewObservations(scores),readiness,report)");
 assert.equal(result.entries.length,14);
 assert.equal(new Set(result.entries.map(r=>r.id)).size,14);
 assert.equal(result.certifiedSignalCount,0);
 assert.equal(result.scoringEnabled,false);
 for(const entry of result.entries){
  assert.ok([252,104,36].includes(entry.minimum));
  assert.equal(entry.minimum,entry.cadence==="daily"?252:entry.cadence==="weekly"?104:36);
  assert.equal(entry.qualified,false);
  assert.equal(entry.releaseVerified,false);
  assert.equal(entry.revisionTraceVerified,false);
  assert.equal(entry.independentEvidence,false);
  assert.equal(entry.oosVerified,false);
  const archive=readiness.series[entry.id];
  if(archive)assert.equal(entry.periods,archive.distinct_observation_periods);
 }
});
test("real Treasury history can span 1472 days yet latest revised observations are not publisher release PIT evidence",()=>{
 const hist=JSON.parse(fs.readFileSync(path.join(root,"data/asset-compass-treasury-history.json"),"utf8"));
 assert.ok(hist.observation_count>1000);
 assert.equal(hist.original_release_vintages_available,false);
 assert.equal(hist.not_valid_for_point_in_time_backtest,true);
 const{ctx}=setup();
 const r=run(ctx,"factorQualification(overviewObservations(scores),readiness,report)");
 for(const id of ["treasury.us10y","treasury.us2y","treasury.real10y"]){
  assert.equal(r.entries.find(x=>x.id===id).qualified,false);
 }
});
test("dashboard displays explicit individual evidence gaps and preserves six locked score cards",()=>{
 const{ctx,nodes}=setup();
 run(ctx,"overview(scores,readiness,report)");
 const panel=nodes["factor-qualification"];
 assert.equal(panel.children.length,4);
 assert.equal(panel.children[2].children[0].children[1].children.length,14);
 const copy=tree(panel);
 assert.match(copy,/V49准入规则/);
 assert.match(copy,/已认证独立预测信号：0/);
 assert.match(copy,/日频252、周频104、月频36/);
 assert.match(copy,/仅研究 · 不可评分/);
 assert.match(copy,/官方首发时间/);
 assert.match(copy,/首次观察记录不代表官方首次发布日期/);
 assert.ok(nodes["asset-grid"].children.every(c=>c.children[1].textContent==="— / 100"));
});
test("missing readiness or forged score approvals cannot certify factor qualification",()=>{
 const{ctx,nodes}=setup();
 run(ctx,"overview(null,null,null)");
 assert.match(tree(nodes["factor-qualification"]),/未核实/);
 assert.ok(nodes["asset-grid"].children.every(c=>c.children[1].textContent==="— / 100"));
 ctx.forged=JSON.parse(JSON.stringify(readiness));
 ctx.forged.validated_for_live_scoring=true;
 ctx.forged.eligible_for_point_in_time_backtest=true;
 ctx.forged.archived_observations=999999;
 const r=run(ctx,"factorQualification([],forged,report)");
 assert.equal(r.historyVerified,false);
 assert.equal(r.entries.every(x=>!x.qualified&&x.periods===null),true);
});
test("synthetic high history counts never override absent official-vintage, overlap and OOS evidence",()=>{
 const{ctx}=setup();
 ctx.synthetic=JSON.parse(JSON.stringify(readiness));
 for(const id of Object.keys(ctx.synthetic.series)){
  ctx.synthetic.series[id].distinct_observation_periods=10000;
  ctx.synthetic.series[id].archived_versions=10000;
 }
 const output=run(ctx,"factorQualification([],synthetic,report)");
 assert.ok(output.entries.some(x=>x.historyLength===true));
 assert.equal(output.entries.every(x=>!x.qualified&&x.releaseVerified===false&&x.oosVerified===false),true);
});
console.log("V49 factor qualification evidence gates passed.");
