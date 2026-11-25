"use strict";
// V3: candidate identity is not product mapping. This validator does not grant publication.
function validLei(s) {
 if (typeof s!=="string"||!(/^[A-Z0-9]{18}[0-9]{2}$/).test(s)) return false;
 let n=0;
 for(const c of s) for(const digit of (/[A-Z]/.test(c)?String(c.charCodeAt(0)-55):c)) n=(n*10+Number(digit))%97;
 return n===1;
}
function auditRegistry(data) {
 if(data.publication?.enabled!==false||!Array.isArray(data.issuers)||data.issuers.length!==100) throw Error("closed universe required");
 const ids=new Set(), leis=new Set();
 let issuerIdentities=0;
 for(const row of data.issuers){
  if(ids.has(row.issuer_id)) throw Error("duplicate issuer");ids.add(row.issuer_id);
  if(row.reference_entity_id!==null||row.mapping_status!=="unverified"||row.cds_mapping_evidence!==null||row.quote!==null||!Array.isArray(row.history)||row.history.length) throw Error("unapproved mapping or quote");
  if(row.issuer_identity===null) continue;
  const i=row.issuer_identity;
  if(!i||!validLei(i.lei)||leis.has(i.lei)||typeof i.legal_name!=="string"||!i.legal_name.trim()||!/^https:\/\/(lei\.bloomberg\.com\/leis\/view\/|www\.sec\.gov\/Archives\/edgar\/data\/)/.test(i.source)||!/^\d{4}-\d{2}-\d{2}$/.test(i.checked_on)||i.status!=="issuer_identity_evidence_only") throw Error("invalid issuer evidence");
  leis.add(i.lei);issuerIdentities++;
 }
 if(data.mapping_audit_v3?.issuer_identity_count!==issuerIdentities||data.mapping_audit_v3?.verified_reference_entity_count!==0||data.mapping_audit_v3?.verified_upi_count!==0) throw Error("coverage mismatch");
 return {issuerIdentities,referenceEntities:0,verifiedUPIs:0,publicationEnabled:false};
}
if(typeof module!=="undefined"&&module.exports) module.exports={validLei,auditRegistry};
