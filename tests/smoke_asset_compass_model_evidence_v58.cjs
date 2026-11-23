"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const ROOT=path.join(__dirname,"..");
const site=fs.readFileSync(path.join(ROOT,"macro/compass-pages.js"),"utf8");
const dollar=JSON.parse(fs.readFileSync(path.join(ROOT,"data/asset-compass-usd-h10-v58.json"),"utf8"));
const report=JSON.parse(fs.readFileSync(path.join(ROOT,"data/asset-compass-model-gaps-v58.json"),"utf8"));
class Node{
 constructor(tag="div"){this.tagName=tag;this.children=[];this.textContent="";this.href="";this.className="";this.dataset={}}
 append(...items){this.children.push(...items)}
 replaceChildren(...items){this.children=items}
 addEventListener(){}
 setAttribute(){}
}
function render(r=report,d=dollar){
 const node=new Node();
 const document={body:{dataset:{page:"_v58_smoke_"}},querySelector:id=>id==="#model-evidence-v58"?node:null,createElement:tag=>new Node(tag)};
 const ctx=vm.createContext({document,Intl,Date,Array,Math,Number,console});
 vm.runInContext(site,ctx,{filename:"macro/compass-pages.js"});
 ctx.r=r;ctx.d=d;vm.runInContext("renderModelEvidenceV58(r,d)",ctx);
 return node;
}
function test(label,fn){try{fn();console.log("PASS V58",label)}catch(e){console.error("FAIL V58",label);throw e}}
test("real official H10 and audited source matrix display",()=>{
 const p=render();
 assert.equal(p.children.length,5);
 assert.match(p.children[0].textContent,/专属研究来源：4\/6/);
 const body=p.children[1].children[0].children[1];
 assert.equal(body.children.length,6);
 assert.match(body.children[0].children[1].textContent,/CFTC/);
 assert.equal(body.children[1].children[1].textContent,"缺失");
 assert.match(body.children[2].children[1].textContent,/30年/);
 assert.match(body.children[3].children[1].textContent,/H.10/);
 assert.equal(body.children[4].children[1].textContent,"缺失");
 assert.match(body.children[5].children[1].textContent,/EIA/);
 for(const row of body.children)assert.equal(row.children[5].textContent,"— / 100");
 assert.match(p.children[2].textContent,/广义美元/);
 assert.match(p.children[4].textContent,/尚未完成/);
});
test("official Fed index provenance link survives rendering",()=>{
 const p=render();
 assert.equal(p.children[3].children[0].href,"https://fred.stlouisfed.org/series/DTWEXBGS");
});
test("malicious forged approved score is refused",()=>{
 const r=structuredClone(report);r.research_assets.gold.official_score=91;
 const p=render(r);
 assert.equal(p.children.length,1);
 assert.match(p.children[0].textContent,/拒绝展示/);
});
test("fake historic PIT or OOS certification rejected",()=>{
 const a=structuredClone(report);a.oos_validated_assets=6;
 assert.equal(render(a).children.length,1);
 const b=structuredClone(dollar);b.historical_first_publication_vintages_verified=true;
 assert.equal(render(report,b).children.length,1);
});
test("fake source count / scope rejected",()=>{
 const r=structuredClone(report);r.asset_specific_observed_count=6;
 assert.equal(render(r).children.length,1);
 const c=structuredClone(report);delete c.research_assets.bitcoin;
 assert.equal(render(c).children.length,1);
});
test("stale USD H10 source never displayed as live research",()=>{
 const d=structuredClone(dollar);d.latest_observation_date="2020-01-01";
 const p=render(report,d);
 assert.match(p.children[2].textContent,/时效过期/);
});
console.log("V58 six-asset real research evidence and model-score lock passed");
