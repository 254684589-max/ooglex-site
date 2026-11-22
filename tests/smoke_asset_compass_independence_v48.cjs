"use strict";
// V48 executes the actual production script and checks the real official
// historical observations. No score, invented provenance or simulated source.
const assert=require("node:assert/strict"),fs=require("node:fs"),
 path=require("node:path"),vm=require("node:vm");
const root=path.resolve(__dirname,"..");
const js=fs.readFileSync(path.join(root,"macro/compass-pages.js"),"utf8");
const data=JSON.parse(fs.readFileSync(path.join(root,"data/asset-scores.json"),"utf8"));
const history=JSON.parse(fs.readFileSync(path.join(root,"data/asset-compass-treasury-history.json"),"utf8"));
class E {
 constructor(tag="div"){this.tagName=tag;this.children=[];this.textContent="";this.className="";this.events={};this.value="";this.attributes={};this.dataset={};}
 append(...x){this.children.push(...x)}
 replaceChildren(...x){this.children=x}
 addEventListener(name,fn){this.events[name]=fn}
 setAttribute(k,v){this.attributes[k]=v}
 get firstChild(){return this.children[0]}
}
function setup(){
 const ids=["indicator-independence","headline","asset-grid","source-status","overview-kpis","macro-table-body",
   "indicator-search","indicator-filter","indicator-count","history-status","asset-insights"];
 const nodes=Object.fromEntries(ids.map(id=>[id,new E()]));
 const doc={body:{dataset:{page:"test-only"}},querySelector:q=>nodes[q.slice(1)]||null,
  querySelectorAll:q=>[],createElement:tag=>new E(tag)};
 const ctx=vm.createContext({document:doc,Date,Number,String,Object,Set,Array,Math,Intl,console});
 vm.runInContext(js,ctx,{filename:"compass-pages.js"});ctx.snapshot=data;
 return{ctx,nodes};
}
const run=(ctx,s)=>vm.runInContext(s,ctx);
const contentText=e=>[e.textContent,...e.children.map(contentText)].join(" ");
function test(label,fn){try{fn();console.log("PASS",label)}catch(e){console.error("FAIL",label);throw e}}
test("audit registry covers exactly 14 existing source series; not 14 independent factors",()=>{
 const{ctx}=setup();
 const audit=run(ctx,"independenceAudit(overviewObservations(snapshot))");
 assert.equal(audit.sourceSeries,14);
 assert.equal(audit.entries.length,14);
 assert.equal(new Set(audit.entries.map(x=>x.id)).size,14);
 assert.equal(audit.derivedDefinitions,2);
 assert.equal(audit.independentSignalsCertified,false);
 assert.equal(audit.validatedForScoring,false);
 assert.equal(audit.entries.some(x=>x.id==="nyfed_recession.probability"&&x.relation.includes("非独立")),true);
});
test("official historical identities hold on every one of the matched 10y, 2y and real points",()=>{
 assert.ok(history.observation_count>=100);
 for(const row of history.observations){
  assert.ok(Math.abs(row.us10y-row.real10y-row.breakeven10y)<0.0011);
  assert.ok(Math.abs(row.us10y-row.us2y-row.spread10y2y)<0.0011);
 }
});
test("model derived spread, model output and underlying publisher series have different classifications",()=>{
 const{ctx}=setup();
 const identities=run(ctx,"EXACT_IDENTITIES");
 assert.equal(identities.length,2);
 for(const expression of identities){
  assert.equal(expression.inputs.length,2);
  assert.ok(expression.derived.startsWith("treasury."));
  assert.ok(!expression.inputs.includes(expression.derived));
 }
 const audit=run(ctx,"independenceAudit([])");
 const model=audit.entries.find(x=>x.id==="nyfed_recession.probability");
 assert.match(model.note,/不能再作为独立于期限利差的证据/);
 assert.ok(audit.entries.filter(x=>x.family==="美联储资产负债表").length===4);
 assert.ok(audit.entries.filter(x=>x.family==="通胀").length===3);
});
test("dashboard displays 14 source entries and two formulas, no phantom independent votes",()=>{
 const{ctx,nodes}=setup();
 run(ctx,"overview(snapshot,null)");
 const panel=nodes["indicator-independence"];
 assert.equal(panel.children.length,4);
 const table=panel.children[2].children[0];
 assert.equal(table.children[1].children.length,14);
 const displayed=contentText(panel);
 assert.match(displayed,/14 条已接入源系列/);
 assert.match(displayed,/2 条代数派生公式/);
 assert.match(displayed,/0项预测独立性认证/);
 assert.match(displayed,/名义10年/);
 assert.match(displayed,/FRED|美联储/);
 assert.ok(nodes["asset-grid"].children.every(x=>x.children[1].textContent==="— / 100"));
});
test("invalid or absent snapshot does not unlock any model score or fake observations",()=>{
 const{ctx,nodes}=setup();
 run(ctx,"overview(null,null)");
 const audit=nodes["indicator-independence"];
 assert.equal(audit.children[2].children[0].children[1].children.length,14);
 assert.ok(contentText(audit).includes("缺失或过期"));
 assert.ok(nodes["asset-grid"].children.every(x=>x.children[1].textContent==="— / 100"));
});
console.log("V48 indicator dependency and source-vote guard tests passed.");
