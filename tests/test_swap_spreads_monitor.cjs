"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const monitor=require("../macro/swap-spreads-monitor.js");
const years=[2,3,5,7,10,30];
function row(index,offset=0){
  const asOf=new Date(Date.UTC(2026,0,1+index*2)).toISOString().slice(0,10);
  const tenors=years.map(y=>({years:y,swap:4+index*.001+offset,treasury:4.5,
    spreadBp:Math.round(((4+index*.001+offset)-4.5)*10000)/100,method:"close"}));
  return {asOf,tenors};
}
test("singleton does not imply change or anomaly",()=>{
  const r=monitor.analyze([row(0)],10,"2026-01-03T12:00:00Z");
  assert.equal(r.deltaBp,null);assert.equal(r.classification,"insufficient");
});
test("two samples describe direction only",()=>{
  const r=monitor.analyze([row(0),row(1)],10,"2026-01-04T12:00:00Z");
  assert.equal(r.deltaBp,.1);assert.equal(r.direction,"widening");
  assert.equal(r.classification,"descriptive_only");assert.equal(r.thresholdBp,null);
});
test("requires 30 preceding changes and adequate calendar span",()=>{
  const history=Array.from({length:31},(_,i)=>row(i));
  const r=monitor.analyze(history,10,"2026-03-03T00:00:00Z");
  assert.equal(r.baseline,null);
  const extended=monitor.analyze([...history,row(31)],10,"2026-03-05T00:00:00Z");
  assert.equal(extended.baseline.count,30);
  assert.equal(extended.classification,"normal_observed_change");
});
test("big change classified as unusual once history sufficient",()=>{
  const history=Array.from({length:31},(_,i)=>row(i));
  const r=monitor.analyze([...history,row(31,.25)],2,"2026-03-05T00:00:00Z");
  assert.equal(r.classification,"unusual_observed_change");
  assert.ok(r.thresholdBp>=10);
});
test("stale observations cannot generate active alert",()=>{
  const history=Array.from({length:31},(_,i)=>row(i));
  const r=monitor.analyze([...history,row(31,.25)],2,"2026-05-05T00:00:00Z");
  assert.equal(r.status,"stale");assert.equal(r.classification,"stale");
});
test("median is robust and rejects malformed history",()=>{
  assert.equal(monitor.median([1,100,2]),2);
  assert.equal(monitor.median([1,2,3,4]),2.5);
  const bad=row(0);bad.tenors[0].spreadBp=999;
  assert.throws(()=>monitor.analyze([bad],2),/Inconsistent/);
});
