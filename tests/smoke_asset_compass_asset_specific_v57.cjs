"use strict";
const fs=require("node:fs"),path=require("node:path"),vm=require("node:vm"),assert=require("node:assert/strict");
const JS=fs.readFileSync(path.join(__dirname,"../macro/compass-pages.js"),"utf8");
const V56=JSON.parse(fs.readFileSync(path.join(__dirname,"../data/asset-compass-new-sources-v56.json"),"utf8"));
class E{
 constructor(tag="div"){this.tagName=tag;this.textContent="";this.children=[];this.href="";this.className="";this.dataset={};}
 append(...children){this.children.push(...children)}
 replaceChildren(...children){this.children=children}
 setAttribute(){}
 addEventListener(){}
}
function report(){
 const source=(series,dt,z)=>({series_id:series,source_sha256:"a".repeat(64),reference_count:series.startsWith("CFTC")?104:36,
   latest_observation_date:dt,latest_auction_date:dt,research_z_score:z,
   observation_count:135,auction_count:75,signal_verified:false,
   report_date_is_publication_time:false,auction_date_is_publication_time:false,
   latest_managed_money_net_contracts:90000,latest_managed_money_net_percent_oi:18.8,
   latest_bid_to_cover_ratio:2.5,fresh_for_research:true});
 return {schema_version:1,report_type:"asset_compass_v57_authentic_asset_specific_source_research",
  status:"research_only_no_model_promotion",validated_for_live_scoring:false,
  eligible_for_point_in_time_backtest:false,approved_asset_scores:0,
  first_publication_vintages_certified:0,independent_model_factor_qualified_count:0,
  v56_observed_at:V56.generated_at,
  v56_oil_source_date:V56.sources.oil_inventory.latest_observation_date,
  sources:{
   cftc_gold:source("CFTC_COMEX_GOLD_MANAGED_MONEY_FUTURES_ONLY","2026-11-17",0.26),
   treasury_30y:source("TREASURY_30Y_BOND_AUCTION_BID_TO_COVER","2026-11-12",0.48)},
  assets:Object.fromEntries(["gold","us_equities","us_long_bonds","usd","bitcoin","oil"].map(a=>
   [a,{score:null,verified_asset_specific_model_signal:false,
    historic_as_published_vintages_certified:false,
    historical_calibration_passed:false,out_of_sample_validation_passed:false,
    asset_specific_research_source_available:["gold","us_long_bonds","oil"].includes(a)}]))};
}
function execute(r,v56=V56){
 const node=new E(),document={body:{dataset:{page:"_v57_"}},
  querySelector:q=>q==="#asset-specific-v57"?node:null,
  createElement:tag=>new E(tag)};
 const context=vm.createContext({document,console,Date,Object,Intl,String,Number,Array,Promise});
 vm.runInContext(JS,context,{filename:"macro/compass-pages.js"});
 context.report=r;context.sources=v56;
 vm.runInContext("renderAssetSpecificV57(report,sources)",context);
 return node;
}
function test(name,fn){try{fn();console.log("PASS V57",name)}catch(e){console.error("FAIL V57",name);throw e}}
test("V57 three source assets shown, other three missing",()=>{
 const area=execute(report());assert.equal(area.children.length,5);
 const rows=area.children[1].children[0].children[1].children;
 assert.equal(rows.length,3);
 assert.match(rows[0].children[0].textContent,/黄金/);
 assert.match(rows[1].children[0].textContent,/30年/);
 assert.match(rows[2].children[0].textContent,/原油/);
 assert.match(area.children[2].textContent,/美股/);
 assert.match(area.children[2].textContent,/美元/);
 assert.match(area.children[2].textContent,/比特币/);
 assert.match(area.children[4].textContent,/禁止作为已验证评分输入/);
});
test("V57 external source links are official",()=>{
 const a=execute(report());
 assert.match(a.children[3].children[0].href,/www.cftc.gov/);
 assert.match(a.children[3].children[2].href,/fiscaldata.treasury.gov/);
});
test("V57 invalid source digest rejects entire panel",()=>{
 const r=report();r.sources.cftc_gold.source_sha256="not-sha";
 const a=execute(r);assert.equal(a.children.length,1);
 assert.match(a.children[0].textContent,/拒绝展示/);
});
test("V57 disallow staged publication vintage claim",()=>{
 const r=report();r.sources.cftc_gold.report_date_is_publication_time=true;
 const a=execute(r);assert.equal(a.children.length,1);
});
test("V57 asset score forgery rejected",()=>{
 const r=report();r.assets.gold.score=88.3;
 const a=execute(r);assert.equal(a.children.length,1);
});
test("V57 report bound to actual V56 EIA inventory provenance",()=>{
 const r=report();r.v56_oil_source_date="2018-01-01";
 const a=execute(r);assert.equal(a.children.length,1);
});
test("V57 missing report explicitly unavailable",()=>{
 const a=execute(null);
 assert.equal(a.children.length,1);
 assert.match(a.children[0].textContent,/未发布/);
});
test("V57 expired research dates cannot appear as current",()=>{
 const r=report();
 r.sources.cftc_gold.latest_observation_date="2023-01-03";
 const a=execute(r);
 assert.equal(a.children[1].children[0].children[1].children[0].children[4].textContent,"过期或未验证");
});
console.log("V57 official-source asset frontend audit complete");
