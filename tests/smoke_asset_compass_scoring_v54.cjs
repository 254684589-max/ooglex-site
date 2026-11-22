"use strict";
// Execute the production website JS, never a copied scoring implementation.
const fs=require("node:fs"),path=require("node:path"),vm=require("node:vm"),assert=require("node:assert/strict");
const ROOT=path.resolve(__dirname,"..");
const code=fs.readFileSync(path.join(ROOT,"macro/compass-pages.js"),"utf8");
const snap=JSON.parse(fs.readFileSync(path.join(ROOT,"data/asset-scores.json"),"utf8"));
const factors=JSON.parse(fs.readFileSync(path.join(ROOT,"data/asset-compass-factor-observations.json"),"utf8"));
const config=JSON.parse(fs.readFileSync(path.join(ROOT,"macro/model-config.json"),"utf8"));

class E {
 constructor(tag="div"){this.tagName=tag;this.children=[];this.textContent="";this.value="";this.events={};this.dataset={};this.attributes={};this.className="";}
 setAttribute(k,v){this.attributes[k]=v}
 append(...items){this.children.push(...items)}
 replaceChildren(...items){this.children=items}
 addEventListener(k,fn){this.events[k]=fn}
 get firstChild(){return this.children[0]}
}
function session(){
 const ids=["headline","asset-grid","source-status","overview-kpis","macro-table-body",
  "indicator-search","indicator-filter","indicator-count","history-status","scoring-readiness-v54"];
 const nodes=Object.fromEntries(ids.map(id=>[id,new E()]));
 const document={body:{dataset:{page:"_v54_testing_"}},
  querySelector:q=>nodes[q.slice(1)]||null,createElement:tag=>new E(tag)};
 const context=vm.createContext({document,console,Date,Number,String,Object,Array,Intl,Promise});
 vm.runInContext(code,context,{filename:"macro/compass-pages.js"});
 return {nodes,context};
}
function overview(ctx,data,report=null,obs=factors){
 ctx.data=data;ctx.report=report;ctx.obs=obs;
 return vm.runInContext("overview(data,null,obs,report)",ctx);
}
function mkReport(){
 const groups=Object.fromEntries(config.factor_order.map(g=>[g,{label:g,
  source_observation_count:factors.groups[g].observations.length}]));
 const assets=Object.fromEntries(Object.entries(config.weights).map(([id,weights])=>[id,{
  status:"unavailable",score:null,qualified_model_signal_coverage_pct:0,
  source_observation_weight_pct_research_only:weights.reduce((sum,n,i)=>
   sum+(factors.groups[config.factor_order[i]].observations.length?n:0),0),
  missing_source_groups:config.factor_order.filter(g=>!factors.groups[g].observations.length),
  validated_for_live_scoring:false}]));
 return {schema_version:1,report_type:"asset_compass_v54_scoring_readiness",
  status:"research_only_no_authorized_scores",validated_for_live_scoring:false,
  independently_qualified_factor_groups:0,source_pit_qualified_count:0,
  source_snapshot_generated_at:snap.generated_at,
  source_observations_generated_at:factors.generated_at,
  groups,assets,asset_count:6,factor_group_count:6,
  groups_with_source_observations:Object.values(groups).filter(x=>x.source_observation_count).length,
  groups_without_source_observations:Object.values(groups).filter(x=>!x.source_observation_count).length,
  website_archived_first_seen_records:21,treasury_source_year_mismatch_records:5};
}
function test(name,fn){try{fn();console.log("PASS",name)}catch(e){console.error("FAIL",name);throw e}}
test("V54 live report explains six missing asset scores without inventing numbers",()=>{
 const {nodes,context}=session();overview(context,snap,mkReport());
 assert.equal(nodes["asset-grid"].children.length,6);
 assert.ok(nodes["asset-grid"].children.every(x=>x.children[1].textContent==="— / 100"));
 const area=nodes["scoring-readiness-v54"];
 assert.equal(area.children.length,3);
 assert.match(area.children[0].textContent,/正式评分：0\/6/);
 const tbody=area.children[1].children[0].children[1];
 assert.equal(tbody.children.length,6);
 assert.equal(tbody.children[0].children[2].textContent,"0%");
 assert.match(tbody.children[0].children[3].textContent,/风险/);
 assert.match(tbody.children[0].children[3].textContent,/估值/);
});
test("V54 missing readiness and stale artifact do not show fabricated percent coverage",()=>{
 const {nodes,context}=session();overview(context,snap,null);
 assert.match(nodes["scoring-readiness-v54"].children[0].textContent,/报告缺失/);
 const old=mkReport();old.source_snapshot_generated_at="2024-01-01T00:00:00Z";
 overview(context,snap,old);
 assert.match(nodes["scoring-readiness-v54"].children[0].textContent,/快照不匹配/);
});
test("V54 calibrated future backend contract does NOT get rejected by snapshotValid",()=>{
 const data=structuredClone(snap);
 data.scoring.calibration_verified=true;data.scoring.out_of_sample_verified=true;
 data.assets.gold={score:68.25,status:"calibrated",
  validation:{historical_calibration_passed:true,out_of_sample_passed:true}};
 const {nodes,context}=session();overview(context,data);
 assert.match(nodes["source-status"].textContent,/官方数据快照/);
 assert.equal(nodes["asset-grid"].children[0].children[1].textContent,"68.3/100");
 assert.ok(nodes["asset-grid"].children.slice(1).every(x=>x.children[1].textContent==="— / 100"));
});
test("V54 forged numeric score lacking per-asset certification is rejected",()=>{
 const data=structuredClone(snap);
 data.scoring.calibration_verified=true;data.scoring.out_of_sample_verified=true;
 data.assets.gold={score:99,status:"calibrated"};
 const {nodes,context}=session();overview(context,data);
 assert.equal(nodes["asset-grid"].children[0].children[1].textContent,"— / 100");
});
test("V54 per-asset scores cannot bypass globally unapproved scoring",()=>{
 const data=structuredClone(snap);
 data.assets.gold={score:99,status:"calibrated",
  validation:{historical_calibration_passed:true,out_of_sample_passed:true}};
 const {nodes,context}=session();overview(context,data);
 assert.equal(nodes["asset-grid"].children[0].children[1].textContent,"— / 100");
});
test("V54 malformed scoring metadata cannot be accepted",()=>{
 const data=structuredClone(snap);data.scoring.out_of_sample_verified="true";
 const {nodes,context}=session();overview(context,data);
 assert.match(nodes["source-status"].textContent,/暂停展示数值/);
 assert.ok(nodes["asset-grid"].children.every(x=>x.children[1].textContent==="— / 100"));
});
test("V54 fabricated report asset score causes report rejection",()=>{
 const r=mkReport();r.assets.gold.score=94;
 const {nodes,context}=session();overview(context,snap,r);
 assert.match(nodes["scoring-readiness-v54"].children[0].textContent,/拒绝展示/);
});
console.log("V54 scoring UI and model-contract smoke passed");
