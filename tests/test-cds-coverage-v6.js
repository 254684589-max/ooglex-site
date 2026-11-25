"use strict";
const assert=require("node:assert/strict");
const {summarize}=require("../macro/nasdaq100-cds-coverage-v6.js");
const actual=require("../macro/nasdaq100-cds-audit.json");
const empty=()=>({schema_version:1,source:"tradeweb_sbsef_dmdr",publication_enabled:false,admitted_par_spreads:0,reports:{}});
const row=(ids,counts)=>({candidate_issuer_ids:ids,candidate_issuer_count:ids.length,report_rows:Object.values(counts).reduce((a,b)=>a+b,0),classification_counts:counts,verified_reference_entities:0,admitted_par_spreads:0});
const cases=[
["actual ledger reconciles",()=>{const s=summarize(actual);assert.equal(s.rows,Object.values(s.totals).reduce((a,b)=>a+b,0));assert.equal(s.days,Object.keys(actual.reports).length);assert.equal(s.admitted,0);}],
["empty ledger",()=>{const s=summarize(empty());assert.equal(s.rows,0);assert.equal(s.first,null);assert.deepEqual(s.candidates,[]);}],
["latest distinct version only",()=>{const d=empty();d.reports["2026-11-18"]=[row(["a"],{coupon_collision:1}),row(["b"],{coupon_collision:2})];const s=summarize(d);assert.equal(s.rows,2);assert.equal(s.versions,2);assert.deepEqual(s.candidates.map(x=>x.id),["b"]);}],
["deduplicate across dates",()=>{const d=empty();d.reports["2026-11-18"]=[row(["a"],{coupon_collision:1})];d.reports["2026-11-19"]=[row(["a","b"],{coupon_collision:2})];const s=summarize(d);assert.equal(s.candidates.length,2);assert.equal(s.candidates[0].report_days,2);assert.equal(s.candidates[0].last_day,"2026-11-19");}],
["reject publication",()=>{const d=empty();d.publication_enabled=true;assert.throws(()=>summarize(d));}],
["reject classification mismatch",()=>{const d=empty();const r=row(["a"],{coupon_collision:1});r.report_rows=2;d.reports["2026-11-18"]=[r];assert.throws(()=>summarize(d));}],
["reject admitted quote",()=>{const d=empty();const r=row(["a"],{coupon_collision:1});r.admitted_par_spreads=1;d.reports["2026-11-18"]=[r];assert.throws(()=>summarize(d));}],
["reject duplicate candidates",()=>{const d=empty();d.reports["2026-11-18"]=[row(["a","a"],{coupon_collision:2})];assert.throws(()=>summarize(d));}]
];
for(const [name,test] of cases){test();console.log("PASS "+name);}
console.log(cases.length+" checks passed");
