"use strict";
const assert=require("node:assert/strict");
const {validLei,auditRegistry}=require("../scripts/audit-cds-mapping-v3.js");
const data=require("../macro/nasdaq100-cds.json");
const clone=()=>JSON.parse(JSON.stringify(data));
const checks=[
 ["real registry",()=>assert.deepEqual(auditRegistry(data),{issuerIdentities:7,referenceEntities:0,verifiedUPIs:0,publicationEnabled:false})],
 ["checksum",()=>assert.equal(validLei("INR2EJN1ERAN0W5ZP975"),false)],
 ["format",()=>assert.equal(validLei("not-an-lei"),false)],
 ["duplicate LEI",()=>{const d=clone(),r=d.issuers.filter(x=>x.issuer_identity);r[1].issuer_identity=r[0].issuer_identity;assert.throws(()=>auditRegistry(d));}],
 ["ticker not mapping",()=>{const d=clone();d.issuers[0].reference_entity_id=d.issuers[0].tickers[0];assert.throws(()=>auditRegistry(d));}],
 ["candidate cannot become verified",()=>{const d=clone();d.issuers.find(x=>x.issuer_identity).mapping_status="verified";assert.throws(()=>auditRegistry(d));}],
 ["UPI not admitted",()=>{const d=clone();d.issuers[0].cds_mapping_evidence={upi:"QZ1234567890"};assert.throws(()=>auditRegistry(d));}],
 ["wrong coverage",()=>{const d=clone();d.mapping_audit_v3.issuer_identity_count=100;assert.throws(()=>auditRegistry(d));}],
 ["publication locked",()=>{const d=clone();d.publication.enabled=true;assert.throws(()=>auditRegistry(d));}],
 ["quotes locked",()=>{const d=clone();d.issuers[0].quote=100;assert.throws(()=>auditRegistry(d));}]
];
for(const [name,fn] of checks){fn();console.log("PASS "+name);}
console.log(checks.length+" checks passed");
