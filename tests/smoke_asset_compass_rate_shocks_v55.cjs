"use strict";
// Executes actual production site JS on the output from real historical
// Treasury data. No copied scoring formulas or invented research values.
const fs=require("node:fs"),path=require("node:path"),vm=require("node:vm"),assert=require("node:assert/strict");
const ROOT=path.resolve(__dirname,"..");
const SITE=fs.readFileSync(path.join(ROOT,"macro/compass-pages.js"),"utf8");
const snap=JSON.parse(fs.readFileSync(path.join(ROOT,"data/asset-scores.json"),"utf8"));
const report=JSON.parse(fs.readFileSync(path.join(ROOT,"data/asset-compass-rate-shocks-v55.json"),"utf8"));
class E {
 constructor(tag="div"){this.tagName=tag;this.children=[];this.textContent="";this.className="";this.events={};this.dataset={};}
 append(...children){this.children.push(...children)}
 replaceChildren(...children){this.children=children}
 setAttribute(){}
 addEventListener(){}
}
function run(obj=report,data=snap){
 const nodes={"rate-shocks-v55":new E()};
 const document={body:{dataset:{page:"_v55_smoke_"}},querySelector:sel=>nodes[sel.slice(1)]||null,createElement:tag=>new E(tag)};
 const context=vm.createContext({document,Date,Number,Object,String,Array,Intl,Promise,console});
 vm.runInContext(SITE,context,{filename:"macro/compass-pages.js"});
 context.research=obj;context.source=data;
 vm.runInContext("renderRateShocksV55(research,source)",context);
 return nodes["rate-shocks-v55"];
}
function test(name,fn){try{fn();console.log("PASS",name)}catch(e){console.error("FAIL",name);throw e}}
test("V55 genuine Treasury observation history is visible but not scored",()=>{
 const area=run();
 assert.equal(area.children.length,4);
 assert.match(area.children[0].textContent,/个真实观测/);
 assert.equal(area.children[1].children[0].children[1].children.length,5);
 assert.equal(area.children[2].children[0].children[1].children.length,6);
 assert.match(area.children[3].textContent,/不是上涨概率/);
 const cells=area.children[2].children[0].children[1].children;
 for(const row of cells)assert.equal(row.children[3].textContent,"— / 100");
});
test("V55 candidate direction has research hypothesis and no certified score",()=>{
 const area=run();
 const assets=area.children[2].children[0].children[1].children;
 assert.match(assets[0].children[1].textContent,/实际利率/);
 assert.match(assets[2].children[1].textContent,/名义长期收益率/);
 assert.match(assets[1].children[2].textContent,/不提供/);
});
test("V55 cannot show stale rate pressure as current",()=>{
 const bad=structuredClone(report);
 bad.source_end_date="2020-01-02";
 const area=run(bad);
 const assets=area.children[2].children[0].children[1].children;
 assert.equal(assets[0].children[2].textContent,"不提供");
 assert.match(area.children[0].textContent,/已超过11日/);
});
test("V55 stale snapshot hash lineage rejects report instead of using old rates",()=>{
 const bad=structuredClone(report);
 bad.source_snapshot_generated_at="2024-01-01T00:00:00Z";
 const area=run(bad);
 assert.equal(area.children.length,1);
 assert.match(area.children[0].textContent,/快照不一致/);
});
test("V55 injected scoring authorization is rejected",()=>{
 const bad=structuredClone(report);
 bad.validated_for_live_scoring=true;
 const area=run(bad);
 assert.equal(area.children.length,1);
 assert.match(area.children[0].textContent,/不显示/);
});
test("V55 invented asset score causes fail-closed report rejection",()=>{
 const bad=structuredClone(report);bad.assets.gold.official_score=95;
 const area=run(bad);
 assert.equal(area.children.length,1);
 assert.match(area.children[0].textContent,/防误用校验/);
});
test("V55 invented factor independence is rejected",()=>{
 const bad=structuredClone(report);
 bad.shock_features.us10y.qualified_independent_model_signal=true;
 const area=run(bad);
 assert.equal(area.children.length,1);
 assert.match(area.children[0].textContent,/完整性校验/);
});
console.log("V55 authentic-history website contract passed, all 0–100 scores locked");
