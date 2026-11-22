"use strict";
// No browser, npm, network, or user credentials needed.
// Execute actual site JS against a tiny DOM shim, not copied scoring rules.
const fs=require("node:fs"),path=require("node:path"),vm=require("node:vm"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,".."),script=fs.readFileSync(path.join(root,"macro/compass-pages.js"),"utf8");
const sample=JSON.parse(fs.readFileSync(path.join(root,"data/asset-scores.json"),"utf8"));
class Element {
 constructor(tag="div"){this.tagName=tag;this.children=[];this.value="";this.textContent="";this.events={};this.className="";this.dataset={};this.attributes={};}
 setAttribute(name,value){this.attributes[name]=value}
 append(...children){this.children.push(...children)}
 replaceChildren(...children){this.children=children}
 addEventListener(name,fn){this.events[name]=fn}
 get firstChild(){return this.children[0]}
}
function session(){
 const ids=["headline","asset-grid","source-status","overview-kpis","macro-table-body",
            "indicator-search","indicator-filter","indicator-count","history-status"];
 const nodes=Object.fromEntries(ids.map(id=>[id,new Element()]));
 const document={body:{dataset:{page:"_test_only_"}},querySelector:selector=>nodes[selector.slice(1)]||null,
                 createElement:tag=>new Element(tag)};
 const context=vm.createContext({document,console,Date,Number,String,Object,Array,Intl,Promise});
 vm.runInContext(script,context,{filename:"compass-pages.js"});
 return {nodes,context};
}
function run(ctx,fn){return vm.runInContext(fn,ctx)}
function stamp(s){return s.toISOString().slice(0,10)}
function currentFixture(){
 const d=structuredClone(sample),now=new Date();
 const day=stamp(now),month=day.slice(0,7),target=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth()+12,1));
 d.generated_at=now.toISOString();d.observation_date=day;
 d.nyfed.observation_date=day;
 for(const key of ["cpi","core_cpi","payroll","unemployment"])d.bls.series[key].period=month;
 d.bea.core_pce.observation_period=month;
 d.fed_h41.total_assets.observation_date=day;
 for(const key of ["reserves","tga","overnight_rrp"])d.liquidity[key].observation_date=day;
 d.nyfed_recession_model.observation_period=month;
 d.nyfed_recession_model.target_period=target.toISOString().slice(0,7);
 return d;
}
function test(name,fn){try{fn();console.log("PASS",name)}catch(e){console.error("FAIL",name);throw e}}
test("render 14 real input series and six locked assets",()=>{
 const {nodes,context}=session(),snapshot=currentFixture();
 context.snapshot=snapshot;
 run(context,"overview(snapshot,null)");
 assert.equal(nodes["macro-table-body"].children.length,14);
 assert.equal(nodes["asset-grid"].children.length,6);
 assert.equal(nodes["overview-kpis"].children.length,3);
 assert.match(nodes["indicator-count"].textContent,/14 \/ 14/);
 assert.equal(nodes["asset-grid"].children.every(el=>el.children[1].textContent==="— / 100"),true);
 assert.match(nodes["source-status"].textContent,/官方数据快照/);
});
test("search and category filters change displayed real rows",()=>{
 const {nodes,context}=session();context.snapshot=currentFixture();
 run(context,"overview(snapshot,null)");
 nodes["indicator-filter"].value="通胀";
 nodes["indicator-filter"].events.change();
 assert.equal(nodes["macro-table-body"].children.length,3);
 nodes["indicator-search"].value="核心PCE";
 nodes["indicator-search"].events.input();
 assert.equal(nodes["macro-table-body"].children.length,1);
 nodes["indicator-search"].value="not-a-series";
 nodes["indicator-search"].events.input();
 assert.equal(nodes["macro-table-body"].children.length,1);
 assert.equal(nodes["macro-table-body"].children[0].children[0].textContent,"没有符合条件的指标");
});
test("official source links are HTTPS publisher references, not legacy Treasury year",()=>{
 const {nodes,context}=session();context.snapshot=currentFixture();
 run(context,"overview(snapshot,null)");
 const row=nodes["macro-table-body"].children.find(tr=>tr.children[0].textContent==="10年期名义国债收益率");
 assert.ok(row);
 const link=row.children[3].children[0];
 assert.equal(link.tagName,"a");
 assert.match(link.href,/^https:\/\/home\.treasury\.gov\//);
 assert.equal(link.rel,"noopener noreferrer");
 assert.doesNotMatch(link.href,/\/2025\/all/);
});
test("reject calendar overflow and invalid months",()=>{
 const {context}=session();
 for(const v of ["2026-02-30","2026-00-01","2026-13-01","not-a-date"]){
  context.bad=v;assert.equal(run(context,"isoDay(bad,30)"),false);
 }
 for(const v of ["2026-00","2026-13","1899-12","not-a-month"]){
  context.bad=v;assert.equal(run(context,"isoMonth(bad,4)"),false);
 }
});
test("stale source date, missing CPI and invalid probability are not counted",()=>{
 const {context}=session(),d=currentFixture();
 d.observation_date="2020-01-02";
 d.bls.series.cpi.value=null;
 d.nyfed_recession_model.probability_percent=220;
 context.snapshot=d;
 const rows=run(context,"overviewObservations(snapshot)");
 assert.equal(rows.filter(x=>x.value!==null).length,9);
 assert.equal(rows.find(x=>x.id==="treasury.us10y").value,null);
 assert.equal(rows.find(x=>x.id==="bls.cpi").value,null);
 assert.equal(rows.find(x=>x.id==="nyfed_recession.probability").value,null);
});
test("strict scoring remains blocked on production snapshot",()=>{
 const {nodes,context}=session();context.snapshot=sample;
 run(context,"overview(snapshot,null)");
 assert.equal(nodes["asset-grid"].children.length,6);
 assert.ok(nodes["asset-grid"].children.every(x=>x.children[1].textContent==="— / 100"));
});
test("empty / invalid report cannot silently display fabricated numeric observations",()=>{
 const {nodes,context}=session();
 run(context,"overview(null,null)");
 assert.equal(nodes["macro-table-body"].children.length,14);
 assert.ok(nodes["macro-table-body"].children.every(tr=>tr.children[1].textContent==="—"));
 assert.match(nodes["source-status"].textContent,/暂停展示数值/);
});
console.log("V40 UI behavior smoke tests passed.");
