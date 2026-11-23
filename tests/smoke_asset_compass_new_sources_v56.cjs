"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const js=fs.readFileSync(path.join(__dirname,"../macro/compass-pages.js"),"utf8");
class E{
 constructor(tag="div"){this.tagName=tag;this.textContent="";this.children=[];this.className="";this.href="";this.dataset={};}
 append(...items){this.children.push(...items)}
 replaceChildren(...items){this.children=items}
 addEventListener(){}
 setAttribute(){}
}
function mock(){
 const src=(id,group,level,unit)=>({series_id:id,group,source_raw_sha256:"a".repeat(64),
  latest_observation_date:"2026-11-13",latest_level:level,latest_week_delta:1.5,
  observation_count:200,reference_104week_count:104,
  first_publication_vintages_verified:false,independent_scoring_signal_qualified:false,
  out_of_sample_calibration_passed:false,research_z_score:-0.82,current_observation_fresh:true,
  recent_observations:[{date:"2026-11-13",value:level}],latest_level_unit:unit});
 return {schema_version:1,report_type:"asset_compass_v56_official_risk_and_oil_research",
  status:"research_only_two_official_sources_current",approved_asset_scores:0,
  validated_for_live_scoring:false,eligible_for_point_in_time_backtest:false,
  independent_scoring_factor_groups_qualified:0,source_vintages_qualified:0,
  groups_with_any_observation_across_v54_and_v56:6,
  sources:{nfci:src("NFCI","risk",-0.478,"index"),
   oil_inventory:src("WCESTUS1","asset_specific",417797,"thousand_barrels")},
  assets:Object.fromEntries(["gold","us_equities","us_long_bonds","usd","bitcoin","oil"].map(id=>
  [id,{score:null,research_price_direction_signal:null,validated_for_live_scoring:false,
       independent_model_signal_coverage_pct:0}]))};
}
function render(report){
 const node=new E(),document={body:{dataset:{page:"_v56_test_"}},
  querySelector:q=>q==="#new-sources-v56"?node:null,createElement:tag=>new E(tag)};
 const context=vm.createContext({document,console,Date,Number,Intl,Object,Array,Promise});
 vm.runInContext(js,context,{filename:"macro/compass-pages.js"});
 context.r=report;
 vm.runInContext("renderOfficialSourcesV56(r)",context);
 return node;
}
function test(name,fn){try{fn();console.log("PASS V56",name)}catch(e){console.error("FAIL V56",name);throw e}}
test("real sourced research presents two distinct official series",()=>{
 const v=render(mock());
 assert.equal(v.children.length,5);
 assert.match(v.children[0].textContent,/六个因子组/);
 const table=v.children[1].children[0],rows=table.children[1].children;
 assert.equal(rows.length,2);
 assert.match(rows[0].children[0].textContent,/NFCI/);
 assert.match(rows[1].children[0].textContent,/EIA/);
 assert.match(rows[1].children[2].textContent,/417797/);
 assert.match(v.children[2].textContent,/重复投票/);
 assert.match(v.children[4].textContent,/不是ICE/);
});
test("source provenance citations are visible",()=>{
 const v=render(mock());
 assert.equal(v.children[3].children[0].href,"https://fred.stlouisfed.org/series/NFCI");
 assert.match(v.children[3].children[2].href,/eia.gov/);
});
test("no forged asset score permitted",()=>{
 const r=mock();r.assets.oil.score=83;
 const v=render(r);
 assert.equal(v.children.length,1);
 assert.match(v.children[0].textContent,/未经授权/);
});
test("PIT or scoring approval fraud is rejected",()=>{
 const r=mock();r.sources.nfci.first_publication_vintages_verified=true;
 let v=render(r);
 assert.equal(v.children.length,1);
 assert.match(v.children[0].textContent,/拒绝展示/);
 const p=mock();p.validated_for_live_scoring=true;
 v=render(p);assert.equal(v.children.length,1);
});
test("missing source and misleading number of groups rejected",()=>{
 const p=mock();delete p.sources.oil_inventory;
 assert.equal(render(p).children.length,1);
 const q=mock();q.groups_with_any_observation_across_v54_and_v56=5;
 assert.equal(render(q).children.length,1);
});
test("stale publication date not disguised as current",()=>{
 const r=mock();r.sources.oil_inventory.latest_observation_date="2025-04-18";
 const v=render(r);
 assert.equal(v.children[1].children[0].children[1].children[1].children[5].textContent,"过期或未验证");
});
console.log("V56 actual website JavaScript report guards passed");
