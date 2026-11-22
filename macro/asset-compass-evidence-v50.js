"use strict";
// V50 is a public discovery ledger, not an authorization to backtest or score.
// Historical first-seen timestamps and live publisher web pages do not prove
// original as-of releases. All model admission remains V22/V33/V49 gated.
const PIT_EVIDENCE_V50="../data/asset-compass-pit-evidence-v50.json";
const PIT_V50_ORIGINS=new Set([
 "home.treasury.gov","www.bls.gov","www.bea.gov",
 "www.federalreserve.gov","www.newyorkfed.org","fred.stlouisfed.org"
]);
function validPitV50Url(value){
 try{const url=new URL(value);return url.protocol==="https:"&&
  PIT_V50_ORIGINS.has(url.hostname)&&!url.username&&!url.password}
 catch{return false}
}
function validPitV50Receipt(record,cadence){
 if(!record||typeof record!=="object")return false;
 const period=record.observation_period;
 const pattern=cadence==="monthly"?/^\d{4}-\d{2}$/:/^\d{4}-\d{2}-\d{2}$/;
 if(typeof period!=="string"||!pattern.test(period))return false;
 const published=record.publisher_released_at,archived=record.captured_at;
 if(typeof published!=="string"||typeof archived!=="string"||
  !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(published)||
  !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(archived))return false;
 const first=Date.parse(published),second=Date.parse(archived);
 return Number.isFinite(first)&&Number.isFinite(second)&&first<=second&&
  new Date(first).toISOString().replace(".000","")===published&&
  new Date(second).toISOString().replace(".000","")===archived&&
  typeof record.sha256==="string"&&/^[a-f0-9]{64}$/i.test(record.sha256)&&
  validPitV50Url(record.publisher_document_url)&&
  typeof record.version_id==="string"&&record.version_id.length>0;
}
function auditPitEvidenceV50(ledger){
 const empty={valid:false,entries:[],firstReceipts:0,revisionReceipts:0,
  publicationCertified:0,revisionCertified:0,scoringEnabled:false};
 const definitions=typeof OVERVIEW_INDICATORS==="undefined"?[]:OVERVIEW_INDICATORS;
 if(!ledger||ledger.schema_version!==1||
  ledger.report_type!=="asset_compass_pit_evidence_ledger_v50"||
  ledger.status!=="research_only"||!Array.isArray(ledger.entries)||
  ledger.entries.length!==14||definitions.length!==14)return empty;
 const flags=["reference_links_are_not_proof","archived_first_seen_is_not_publication_time",
  "exact_as_of_publication_timestamp_required","original_values_and_sha256_required",
  "complete_revision_lineage_required","independent_manual_review_required","no_model_admission_from_registry"];
 if(!flags.every(x=>ledger.evidence_policy?.[x]===true))return empty;
 const byId=new Map(ledger.entries.map(x=>[x?.id,x]));
 if(byId.size!==14||!definitions.every(x=>byId.has(x.id)))return empty;
 const entries=[];
 for(const definition of definitions){
  const x=byId.get(definition.id);
  if(x.cadence!==definition.cadence||!x.publisher||!x.evidence_gap||
   !validPitV50Url(x.release_reference?.url)||
   !validPitV50Url(x.revision_reference?.url)||
   x.release_reference.status!=="reference_only"||
   x.revision_reference.status!=="reference_only"||
   x.first_publication_verified!==false||
   x.revision_chain_verified!==false||x.point_in_time_qualified!==false||
   !Array.isArray(x.first_publication_records)||!Array.isArray(x.revision_records))return empty;
  const first=x.first_publication_records.filter(r=>validPitV50Receipt(r,x.cadence)).length;
  const revisions=x.revision_records.filter(r=>validPitV50Receipt(r,x.cadence)).length;
  entries.push({id:x.id,name:definition.name,publisher:x.publisher,
   release:x.release_reference.url,revision:x.revision_reference.url,
   firstReceipts:first,revisionReceipts:revisions,missing:x.evidence_gap,
   publicationVerified:false,revisionVerified:false,qualified:false});
 }
 return{valid:true,entries,firstReceipts:entries.reduce((n,x)=>n+x.firstReceipts,0),
  revisionReceipts:entries.reduce((n,x)=>n+x.revisionReceipts,0),
  publicationCertified:0,revisionCertified:0,scoringEnabled:false};
}
function renderPitEvidenceV50(ledger){
 const root=document.querySelector("#pit-evidence-v50");if(!root)return;
 const elem=(tag,cls,value)=>{
  const node=document.createElement(tag);
  if(cls)node.className=cls;
  if(value!==undefined)node.textContent=String(value);
  return node;
 };
 const audit=auditPitEvidenceV50(ledger);
 if(!audit.valid){
  root.replaceChildren(elem("p","insights-warning","V50证据清单缺失或校验失败：全部指标保持未核实，正式评分、回测和预警继续关闭。"));
  return;
 }
 const intro=elem("p","muted",
  "V50官方首发与修订核验台账。官方链接仅供逐期查证，并非已核实的原始发布时间证据；FRED当前值、ALFRED版本日期和网站首次归档时间不能互相替代。");
 const summary=elem("p","label","来源入口："+audit.entries.length+"/14；待复核首发证据："+audit.firstReceipts+
  "条；待复核修订记录："+audit.revisionReceipts+"条；首发PIT认证："+audit.publicationCertified+
  "；修订全链认证："+audit.revisionCertified+"；评分准入：0。");
 const wrap=elem("div","table-wrap"),table=elem("table"),head=elem("thead"),header=elem("tr");
 ["宏观源指标","发布机构","官方首发检索","修订追踪入口","历史PIT认证","仍缺少的关键证据"].forEach(s=>{
  const th=elem("th","",s);th.scope="col";header.append(th);
 });
 head.append(header);table.append(head);
 const tbody=elem("tbody");
 for(const e of audit.entries){
  const tr=elem("tr");tr.append(elem("td","",e.name),elem("td","",e.publisher));
  for(const [label,url] of [["查看官方发布",e.release],["查看修订依据",e.revision]]){
   const td=elem("td");const link=elem("a","source-link",label);
   link.href=url;link.rel="noopener noreferrer";link.target="_blank";td.append(link);tr.append(td);
  }
  tr.append(elem("td","data-unavailable","首发未核实 · 修订未核实"));
  tr.append(elem("td","",e.missing));
  tbody.append(tr);
 }
 table.append(tbody);wrap.append(table);
 const footer=elem("p","insights-warning",
  "核验必须保留每期官方发布文件、UTC发布时间、当时原值、SHA-256摘要、抓取时间与版本链，并经独立复核。即使收集到证据，仍需信息增量及严格样本外验证；V49的六资产评分锁定不变。");
 root.replaceChildren(intro,summary,wrap,footer);
}
async function loadPitEvidenceV50(){
 if(document.body?.dataset?.page!=="overview")return;
 let ledger=null;
 try{
  const response=await fetch(PIT_EVIDENCE_V50,{cache:"no-store"});
  if(response.ok)ledger=await response.json();
 }catch{}
 renderPitEvidenceV50(ledger);
}
loadPitEvidenceV50();
