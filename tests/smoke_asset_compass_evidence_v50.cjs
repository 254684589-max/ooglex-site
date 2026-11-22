"use strict";
// V50: execute production browser code and authoritative, real repository
// evidence ledger. No fixture can promote a financial prediction signal.
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const root=path.resolve(__dirname,"..");
const source=fs.readFileSync(path.join(root,"macro/compass-pages.js"),"utf8");
const v50=fs.readFileSync(path.join(root,"macro/asset-compass-evidence-v50.js"),"utf8");
const registry=JSON.parse(fs.readFileSync(path.join(root,"data/asset-compass-pit-evidence-v50.json"),"utf8"));
const readiness=JSON.parse(fs.readFileSync(path.join(root,"data/asset-compass-history-readiness.json"),"utf8"));
const scores=JSON.parse(fs.readFileSync(path.join(root,"data/asset-scores.json"),"utf8"));
class Element{
 constructor(tag="div"){this.tagName=tag;this.children=[];this.textContent="";this.className="";
  this.dataset={};this.attributes={};this.value="";}
 append(...x){this.children.push(...x)}replaceChildren(...x){this.children=x}
 addEventListener(){}setAttribute(k,v){this.attributes[k]=v}
 get firstChild(){return this.children[0]}
}
function setup(){
 const ids=["pit-evidence-v50","factor-qualification","indicator-independence","source-status","overview-kpis",
  "macro-table-body","indicator-search","indicator-filter","indicator-count","headline",
  "asset-grid","asset-insights","history-status"];
 const nodes=Object.fromEntries(ids.map(x=>[x,new Element()]));
 const document={body:{dataset:{page:"v50-test"}},querySelector:q=>nodes[q.slice(1)]||null,
  querySelectorAll:()=>[],createElement:tag=>new Element(tag)};
 const ctx=vm.createContext({document,Date,Number,Object,Set,String,Array,Math,Intl,URL,console});
 vm.runInContext(source,ctx,{filename:"compass-pages.js"});
 vm.runInContext(v50,ctx,{filename:"asset-compass-evidence-v50.js"});
 ctx.ledger=JSON.parse(JSON.stringify(registry));ctx.scores=scores;
 return{ctx,nodes};
}
const run=(ctx,code)=>vm.runInContext(code,ctx);
const textTree=x=>[x.textContent,...x.children.map(textTree)].join(" ");
const test=(name,fn)=>{try{fn();console.log("PASS",name)}catch(e){console.error("FAIL",name);throw e;}};
test("all 14 canonical V49 IDs and cadence match the V50 provenance registry",()=>{
 const{ctx}=setup();
 const indicators=run(ctx,"OVERVIEW_INDICATORS.map(x=>({id:x.id,cadence:x.cadence}))");
 assert.equal(indicators.length,14);
 assert.equal(registry.entries.length,14);
 assert.deepEqual(registry.entries.map(x=>x.id).sort(),Array.from(indicators,x=>x.id).sort());
 for(const def of indicators){
  assert.equal(registry.entries.find(x=>x.id===def.id).cadence,def.cadence);
 }
});
test("official discovery links are not initial publication or revision PIT evidence",()=>{
 const{ctx}=setup();
 const state=run(ctx,"auditPitEvidenceV50(ledger)");
 assert.equal(state.valid,true);
 assert.equal(state.entries.length,14);
 assert.equal(state.firstReceipts,0);assert.equal(state.revisionReceipts,0);
 assert.equal(state.publicationCertified,0);assert.equal(state.revisionCertified,0);
 assert.equal(state.scoringEnabled,false);
 assert.equal(readiness.eligible_for_point_in_time_backtest,false);
 for(const item of registry.entries){
  assert.equal(item.first_publication_verified,false);
  assert.equal(item.revision_chain_verified,false);
  assert.equal(item.point_in_time_qualified,false);
  assert.deepEqual(item.first_publication_records,[]);
  assert.deepEqual(item.revision_records,[]);
 }
});
test("live V50 panel offers 28 official source links and shows evidence gap per source",()=>{
 const{ctx,nodes}=setup();
 run(ctx,"renderPitEvidenceV50(ledger)");
 const panel=nodes["pit-evidence-v50"];
 assert.equal(panel.children.length,4);
 const rows=panel.children[2].children[0].children[1].children;
 assert.equal(rows.length,14);
 for(const row of rows){
  assert.equal(row.children.length,6);
  for(const cell of [row.children[2],row.children[3]]){
   assert.equal(cell.children.length,1);
   assert.match(cell.children[0].href,/^https:\/\//);
   assert.equal(cell.children[0].rel,"noopener noreferrer");
  }
  assert.match(row.children[4].textContent,/未核实/);
  assert.ok(row.children[5].textContent.length>15);
 }
 assert.match(textTree(panel),/首发PIT认证：0/);
 assert.match(textTree(panel),/FRED当前值/);
 assert.match(textTree(panel),/评分准入：0/);
});
test("bad schema, missing source, unsafe host or forged approval fail closed",()=>{
 const{ctx,nodes}=setup();
 for(const mutation of [
  l=>l.entries.pop(),
  l=>l.entries[0].id="not-real",
  l=>l.entries[0].first_publication_verified=true,
  l=>l.entries[0].point_in_time_qualified=true,
  l=>l.entries[0].release_reference.url="https://evil.example/release",
  l=>l.entries[0].release_reference.status="verified",
  l=>l.evidence_policy.no_model_admission_from_registry=false
 ]){
  const modified=JSON.parse(JSON.stringify(registry));mutation(modified);ctx.corrupted=modified;
  assert.equal(run(ctx,"auditPitEvidenceV50(corrupted).valid"),false);
  run(ctx,"renderPitEvidenceV50(corrupted)");
  assert.match(textTree(nodes["pit-evidence-v50"]),/校验失败/);
 }
 run(ctx,"renderPitEvidenceV50(null)");
 assert.match(textTree(nodes["pit-evidence-v50"]),/继续关闭/);
});
test("unverified receipts and inflated history cannot unlock scores or certifications",()=>{
 const{ctx,nodes}=setup();
 ctx.forgedHistory=JSON.parse(JSON.stringify(readiness));
 ctx.forgedHistory.archived_observations=999999;
 for(const r of Object.values(ctx.forgedHistory.series))r.distinct_observation_periods=999999;
 const fake=JSON.parse(JSON.stringify(registry));
 fake.entries[0].first_publication_records=[{observation_period:"2025-01-01",publisher_released_at:"2025-01-01T20:00:00Z",
  captured_at:"2025-01-01T20:01:00Z",sha256:"a".repeat(64),version_id:"dummy",
  publisher_document_url:"https://home.treasury.gov/treasury-daily-interest-rate-xml-feed"}];
 ctx.fake=fake;
 const state=run(ctx,"auditPitEvidenceV50(fake)");
 assert.equal(state.valid,true);
 assert.equal(state.firstReceipts,1);
 assert.equal(state.publicationCertified,0);
 assert.equal(state.scoringEnabled,false);
 run(ctx,"overview(scores,forgedHistory,null);renderPitEvidenceV50(fake)");
 assert.ok(nodes["asset-grid"].children.every(c=>c.children[1].textContent==="— / 100"));
 assert.match(textTree(nodes["pit-evidence-v50"]),/评分准入：0/);
});
console.log("V50 release/revision provenance safety gates passed.");
