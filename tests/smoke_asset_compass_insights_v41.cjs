"use strict";
// Executes production macro/compass-pages.js; no network or npm dependency.
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const base=path.resolve(__dirname,"..");
const script=fs.readFileSync(path.join(base,"macro/compass-pages.js"),"utf8");
const snapshot=JSON.parse(fs.readFileSync(path.join(base,"data/asset-scores.json"),"utf8"));
class E {
 constructor(tag="div"){this.tagName=tag;this.children=[];this.events={};this.dataset={};this.attributes={};this.textContent="";this.className="";this.value="";}
 append(...nodes){this.children.push(...nodes)}
 replaceChildren(...nodes){this.children=nodes}
 addEventListener(name,callback){this.events[name]=callback}
 setAttribute(name,value){this.attributes[name]=value}
 getAttribute(name){return this.attributes[name]}
 get firstChild(){return this.children[0]}
}
function fixture(){
 const d=structuredClone(snapshot),now=new Date(),day=now.toISOString().slice(0,10),month=day.slice(0,7);
 d.generated_at=now.toISOString();d.observation_date=day;d.nyfed.observation_date=day;
 // Isolate arithmetic tests from daily live rate movements; deliberately
 // disagree with stored derived value to prove same-day recomputation.
 d.rates.us10y=4.95;d.rates.real10y=2.80;d.rates.breakeven10y=9.99;
 for(const id of ["cpi","core_cpi","unemployment","payroll"])d.bls.series[id].period=month;
 d.bea.core_pce.observation_period=month;
 d.fed_h41.total_assets.observation_date=day;
 for(const id of ["reserves","tga","overnight_rrp"])d.liquidity[id].observation_date=day;
 d.nyfed_recession_model.observation_period=month;
 const future=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth()+12,1));
 d.nyfed_recession_model.target_period=future.toISOString().slice(0,7);
 return d;
}
function makeDOM(){
 const ids=["headline","asset-grid","source-status","overview-kpis","macro-table-body","indicator-search",
  "indicator-filter","indicator-count","history-status","asset-insights"];
 const nodes=Object.fromEntries(ids.map(id=>[id,new E()]));
 const walk=(e)=>[e,...e.children.flatMap(walk)];
 const document={body:{dataset:{page:"no-auto-run"}},querySelector:q=>nodes[q.slice(1)]||null,
  querySelectorAll:q=>q==="[data-insight-asset]"?walk(nodes["asset-grid"]).filter(e=>e.dataset.insightAsset):[],
  createElement:tag=>new E(tag)};
 const ctx=vm.createContext({document,console,Date,Number,String,Object,Array,Intl,Promise});
 vm.runInContext(script,ctx,{filename:"macro/compass-pages.js"});
 return {nodes,ctx};
}
function test(name,fn){try{fn();console.log("PASS",name)}catch(e){console.error("FAIL",name);throw e}}
function panelText(e){return [e.textContent,...e.children.map(panelText)].join(" ")}
function buttons(nodes){return nodes["asset-grid"].children.map(card=>card.children.find(x=>x.dataset.insightAsset))}
function render(){
 const {nodes,ctx}=makeDOM(),d=fixture();ctx.d=d;vm.runInContext("overview(d,null)",ctx);return {nodes,ctx,d};
}
test("six genuine asset cards provide accessible buttons and a default explainer",()=>{
 const {nodes}=render(),b=buttons(nodes);
 assert.equal(b.length,6);
 assert.deepEqual(b.map(x=>x.dataset.insightAsset),["gold","us_equities","us_long_bonds","usd","bitcoin","oil"]);
 assert.equal(b[0].getAttribute("aria-pressed"),"true");
 assert.equal(b[0].getAttribute("aria-controls"),"asset-insights");
 assert.equal(nodes["asset-insights"].children[2].children.length,4);
 assert.match(panelText(nodes["asset-insights"]),/黄金/);
 assert.ok(nodes["asset-grid"].children.every(x=>x.children[1].textContent==="— / 100"));
});
test("clicking all six assets changes evidence and pressed state; no fabricated scores",()=>{
 const {nodes}=render(),b=buttons(nodes);
 for(const button of b){
  button.events.click();
  assert.equal(button.getAttribute("aria-pressed"),"true");
  assert.equal(b.filter(x=>x.getAttribute("aria-pressed")==="true").length,1);
  assert.equal(nodes["asset-insights"].children[2].children.length,4);
  assert.ok(nodes["asset-grid"].children.every(x=>x.children[1].textContent==="— / 100"));
 }
 assert.match(panelText(nodes["asset-insights"]),/原油/);
});
test("missing or stale macro values show missing, not fabricated zero",()=>{
 const {nodes,ctx,d}=render();
 d.observation_date="2020-01-01";
 d.bea.core_pce.value=null;d.bea.core_pce.yoy_percent=null;
 ctx.updated=d;vm.runInContext("overview(updated,null)",ctx);
 assert.match(panelText(nodes["asset-insights"]),/数据缺失或过期/);
 const gold=buttons(nodes)[0];gold.events.click();
 assert.equal(nodes["asset-insights"].children[2].children.length,4);
 assert.ok(nodes["asset-grid"].children.every(x=>x.children[1].textContent==="— / 100"));
});
test("derived break-even is same-day nominal minus real, never a distinct source",()=>{
 const {nodes}=render();
 const items=nodes["asset-insights"].children[2].children;
 const breakEven=items[1];
 assert.match(panelText(breakEven),/通胀补偿（派生）/);
 assert.match(panelText(breakEven),/同日代数派生，非独立来源/);
 assert.match(panelText(breakEven),/2\.15/);
});
test("derived input stale suppresses derived numeric value",()=>{
 const {nodes,ctx,d}=render();d.observation_date="2020-01-01";
 ctx.updated=d;vm.runInContext("overview(updated,null)",ctx);
 assert.match(panelText(nodes["asset-insights"].children[2].children[1]),/数据缺失或过期/);
 assert.doesNotMatch(panelText(nodes["asset-insights"].children[2].children[1]),/2\.15/);
});
test("no snapshot produces explanations but no numeric source values or scores",()=>{
 const {nodes,ctx}=makeDOM();vm.runInContext("overview(null,null)",ctx);
 assert.equal(nodes["asset-insights"].children[2].children.length,4);
 assert.equal(nodes["asset-insights"].children[2].children.every(x=>panelText(x).includes("数据缺失或过期")),true);
 assert.ok(nodes["asset-grid"].children.every(x=>x.children[1].textContent==="— / 100"));
});
test("every asset has non-empty explanatory text and no directional advice",()=>{
 const {ctx}=makeDOM(),out=vm.runInContext("ASSET_INSIGHTS",ctx);
 for(const def of Object.values(out)){
  assert.equal(def.items.length,4);
  for(const item of def.items){assert.ok(item[1].length>15)}
 }
 assert.equal(Object.keys(out).length,6);
});
console.log("V41 six-asset evidence interactions passed.");
