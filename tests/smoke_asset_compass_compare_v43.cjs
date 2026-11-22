"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),
 vm=require("node:vm"),path=require("node:path");
const root=path.resolve(__dirname,"..");
const chartJS=fs.readFileSync(path.join(root,"macro/treasury-trends.js"),"utf8");
const overviewJS=fs.readFileSync(path.join(root,"macro/compass-pages.js"),"utf8");
const history=JSON.parse(fs.readFileSync(path.join(root,"data/asset-compass-treasury-history.json"),"utf8"));
const live=JSON.parse(fs.readFileSync(path.join(root,"data/asset-scores.json"),"utf8"));
const ids=["treasury-trend-svg","treasury-trend-status","treasury-trend-meta",
 "treasury-trend-table","treasury-trend-series","treasury-trend-range",
 "treasury-trend-compare","treasury-trend-legend","treasury-trend-difference",
 "treasury-trend-panel","headline","asset-grid","source-status","overview-kpis",
 "macro-table-body","indicator-search","indicator-filter","indicator-count",
 "history-status","asset-insights"];
class E{
 constructor(tag="div"){this.tagName=tag;this.children=[];this.events={};
  this.attributes={};this.dataset={};this.textContent="";this.value="";this.scrolled=false;}
 setAttribute(k,v){this.attributes[k]=v}
 getAttribute(k){return this.attributes[k]}
 append(...children){this.children.push(...children)}
 replaceChildren(...children){this.children=children}
 addEventListener(k,fn){this.events[k]=fn}
 scrollIntoView(){this.scrolled=true}
 get firstChild(){return this.children[0]}
}
function setup(){
 const nodes=Object.fromEntries(ids.map(k=>[k,new E()]));
 nodes["treasury-trend-series"].value="us10y";
 nodes["treasury-trend-compare"].value="real10y";
 nodes["treasury-trend-range"].value="1y";
 const walk=e=>[e,...e.children.flatMap(walk)];
 const document={
  body:{dataset:{page:"v43-test"}},
  createElement:tag=>new E(tag),
  createElementNS:(ns,tag)=>new E(tag),
  getElementById:k=>nodes[k]||null,
  querySelector:s=>nodes[s.slice(1)]||null,
  querySelectorAll:s=>s==="[data-insight-asset]"?
   walk(nodes["asset-grid"]).filter(x=>x.dataset.insightAsset):[]
 };
 const window={};
 const ctx=vm.createContext({document,window,Date,URL,Number,Math,
  Object,Array,Set,String,Intl,Promise,console,fetch:async()=>({ok:true,json:async()=>history})});
 vm.runInContext(overviewJS,ctx,{filename:"compass-pages.js"});
 vm.runInContext(chartJS,ctx,{filename:"treasury-trends.js"});
 return {ctx,nodes,window};
}
function evalWith(ctx,name,expression,value){ctx[name]=value;return vm.runInContext(expression,ctx)}
function test(name,fn){try{fn();console.log("PASS",name)}catch(e){console.error("FAIL",name);throw e}}
function paths(nodes){return nodes["treasury-trend-svg"].children.filter(e=>e.tagName==="path")}
function textOf(e){return [e.textContent,...e.children.map(textOf)].join(" ")}
test("real committed 1472-date history is validated with its actual official source",()=>{
 const {ctx}=setup();ctx.data=history;
 const x=vm.runInContext("TREASURY_TRENDS.validate(data)",ctx);
 assert.ok(x.observation_count>=1000);
 assert.equal(x.source,"U.S. Department of the Treasury");
 assert.equal(x.original_release_vintages_available,false);
 assert.equal(x.not_valid_for_point_in_time_backtest,true);
});
test("two curves share exact 1472 source-matched dates and both render",()=>{
 const {ctx,nodes}=setup();ctx.data=history;
 vm.runInContext('TREASURY_TRENDS.plot(data,"us10y","all","real10y")',ctx);
 assert.equal(paths(nodes).length,2);
 assert.equal(nodes["treasury-trend-legend"].children.length,2);
 assert.equal(nodes["treasury-trend-table"].children.length,8);
 assert.equal(nodes["treasury-trend-table"].children[0].children.length,3);
 assert.match(nodes["treasury-trend-status"].textContent,/1472 个匹配观测日/);
 assert.match(nodes["treasury-trend-svg"].attributes["aria-label"],/双曲线对比/);
});
test("breakeven spread exactly matches the last real date in both percentage points and bp",()=>{
 const {ctx,nodes}=setup();ctx.data=history;
 vm.runInContext('TREASURY_TRENDS.plot(data,"us10y","all","real10y")',ctx);
 const last=history.observations.at(-1),basis=(last.us10y-last.real10y);
 assert.match(nodes["treasury-trend-difference"].textContent,
  new RegExp(basis.toFixed(2).replace(".","\\.")));
 assert.ok(nodes["treasury-trend-difference"].textContent.includes(
  Math.round(basis*100)+" bp"));
 assert.match(nodes["treasury-trend-difference"].textContent,/名义−10年TIPS实际/);
});
test("single curve has one path and never calls arbitrary difference inflation compensation",()=>{
 const {ctx,nodes}=setup();ctx.data=history;
 vm.runInContext('TREASURY_TRENDS.plot(data,"us10y","1y","none")',ctx);
 assert.equal(paths(nodes).length,1);
 assert.equal(nodes["treasury-trend-legend"].children.length,1);
 assert.equal(nodes["treasury-trend-difference"].textContent,"");
 vm.runInContext('TREASURY_TRENDS.plot(data,"us10y","1y","spread10y2y")',ctx);
 assert.equal(paths(nodes).length,2);
 assert.equal(nodes["treasury-trend-difference"].textContent,"");
});
test("identical selections never double-count a line",()=>{
 const {ctx,nodes}=setup();ctx.data=history;
 vm.runInContext('TREASURY_TRENDS.plot(data,"real10y","3m","real10y")',ctx);
 assert.equal(paths(nodes).length,1);
});
test("asset trend focus presets map all six assets to permitted real Treasury fields",()=>{
 const {ctx,nodes}=setup();
 for(const asset of ["gold","us_equities","us_long_bonds","usd","bitcoin","oil"]){
  ctx.asset=asset;
  assert.equal(vm.runInContext("TREASURY_TRENDS.focusAsset(asset)",ctx),true);
  assert.ok(["us10y","real10y","breakeven10y","spread10y2y"].includes(nodes["treasury-trend-series"].value));
  assert.ok(["us10y","real10y","breakeven10y","spread10y2y"].includes(nodes["treasury-trend-compare"].value));
 }
 assert.equal(vm.runInContext('TREASURY_TRENDS.focusAsset("unknown")',ctx),false);
 assert.equal(nodes["treasury-trend-panel"].scrolled,true);
});
test("six real asset card buttons call linked real chart after data loads",async()=>{
 const {ctx,nodes,window}=setup();
 await vm.runInContext("TREASURY_TRENDS.init()",ctx);
 assert.equal(typeof window.ooglexTreasuryFocus,"function");
 const date=new Date(),day=date.toISOString().slice(0,10),month=day.slice(0,7);
 const snapshot=structuredClone(live);
 snapshot.generated_at=date.toISOString();snapshot.observation_date=day;
 snapshot.nyfed.observation_date=day;
 for(const id of ["cpi","core_cpi","unemployment","payroll"])
  snapshot.bls.series[id].period=month;
 snapshot.bea.core_pce.observation_period=month;
 snapshot.fed_h41.total_assets.observation_date=day;
 for(const id of ["reserves","tga","overnight_rrp"])
  snapshot.liquidity[id].observation_date=day;
 ctx.snapshot=snapshot;
 vm.runInContext("overview(snapshot,null)",ctx);
 const buttons=nodes["asset-grid"].children.map(card=>
  card.children.find(x=>x.dataset.trendAsset));
 assert.equal(buttons.length,6);
 for(const b of buttons){
  assert.equal(typeof b.events.click,"function");
  b.events.click();
  assert.equal(paths(nodes).length,2);
  assert.equal(nodes["asset-grid"].children.every(card=>
   card.children[1].textContent==="— / 100"),true);
 }
 assert.equal(nodes["treasury-trend-series"].value,"breakeven10y");
 assert.equal(nodes["treasury-trend-compare"].value,"us10y");
 assert.equal(nodes["treasury-trend-panel"].scrolled,true);
});
test("history unavailable never creates imaginary chart",async()=>{
 const {ctx,nodes}=setup();
 ctx.fetch=async()=>({ok:false,status:404});
 await vm.runInContext("TREASURY_TRENDS.init()",ctx);
 assert.equal(paths(nodes).length,0);
 assert.match(nodes["treasury-trend-status"].textContent,/历史趋势尚不可用/);
});
console.log("V43 real-history dual curve and cross-asset linkage smoke tests passed.");
