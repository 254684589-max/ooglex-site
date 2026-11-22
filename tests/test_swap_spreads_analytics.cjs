"use strict";
const assert=require("node:assert/strict");
const test=require("node:test");
const api=require("../macro/swap-spreads-analytics.js");
const years=[2,3,5,7,10,30];
function record(index,{shift=0}={}) {
  const day=new Date(Date.UTC(2026,0,1+index));
  const asOf=day.toISOString().slice(0,10);
  const tenors=years.map((years,i)=>{
    const swap=4.0+i*0.01+shift+index*0.001;
    const treasury=4.5+i*0.01;
    return {years,swap,treasury,spreadBp:Math.round((swap-treasury)*10000)/100,method:"close"};
  });
  return {asOf,tenors};
}
test("single true matched date does not fabricate changes, percentiles or a trend",()=>{
  const a=api.analyze([record(0)],10);
  assert.equal(a.status,"ok");
  assert.equal(a.changes.one,null);
  assert.equal(a.changes.five,null);
  assert.equal(a.changes.twenty,null);
  assert.equal(a.percentile,null);
  assert.equal(api.relativeCurve([record(0)]).deltaFromPreviousBp,null);
});
test("requires at least two observed dates for change",()=>{
  const r=api.analyze([record(0),record(4)],2);
  assert.equal(r.changes.one,0.4);
  assert.equal(r.changes.five,null);
  assert.equal(r.observations,2);
});
test("percentile gated by prior sample count and calendar span",()=>{
  assert.equal(api.analyze(Array.from({length:60},(_,i)=>record(i)),10).percentile,null);
  // 61 daily records span only 60 calendar days, still not 90.
  assert.equal(api.analyze(Array.from({length:61},(_,i)=>record(i)),10).percentile,null);
  const records=Array.from({length:61},(_,i)=>record(i*2));
  const result=api.analyze(records,10);
  assert.equal(result.previousCount,60);
  assert.equal(result.percentile,100);
  assert.equal(result.changes.twenty,4);
});
test("percentiles can be at bottom of history and are not bullish signals",()=>{
  const records=Array.from({length:61},(_,i)=>record(i*2,{shift:i===60?-2:0}));
  assert.equal(api.analyze(records,10).percentile,0);
});
test("identical curve shifts cancel in relative spread 10y minus 2y",()=>{
  const result=api.relativeCurve([record(0),record(5)],10,2);
  assert.equal(result.valueBp,0);
  assert.equal(result.deltaFromPreviousBp,0);
});
test("invalid history does not produce statistics",()=>{
  assert.throws(()=>api.analyze([record(0),record(0)],10),/Duplicate/);
  const broken=record(0);broken.tenors[0].spreadBp=50;
  assert.throws(()=>api.analyze([broken],10),/Inconsistent/);
  const missing=record(0);missing.tenors.pop();
  assert.throws(()=>api.analyze([missing],10),/Incomplete/);
});
