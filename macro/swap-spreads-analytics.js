/* Ooglex fixed-income analytics V3. Pure, deterministic, no network. */
(function(root, factory) {
  "use strict";
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.OoglexSpreadAnalytics = api;
})(typeof globalThis === "object" ? globalThis : this, function() {
  "use strict";
  const TENORS = [2, 3, 5, 7, 10, 30];
  function assert(condition, message) { if (!condition) throw new Error(message); }
  function day(s) {
    assert(typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s), "Invalid observation date");
    const d = new Date(s + "T00:00:00Z");
    assert(Number.isFinite(d.getTime()) && d.toISOString().slice(0,10) === s, "Invalid calendar date");
    return d;
  }
  function normalize(history) {
    assert(Array.isArray(history), "History must be an array");
    const seen = new Set();
    const observations = history.map(record => {
      const asOf = record && record.asOf;
      day(asOf);
      assert(!seen.has(asOf), "Duplicate observation date");
      seen.add(asOf);
      assert(Array.isArray(record.tenors) && record.tenors.length === TENORS.length, "Incomplete tenor curve");
      const byTenor = {};
      for(const item of record.tenors) {
        assert(TENORS.includes(item.years) && !Object.prototype.hasOwnProperty.call(byTenor,item.years), "Invalid/duplicate tenor");
        assert(Number.isFinite(item.spreadBp) && Number.isFinite(item.swap) && Number.isFinite(item.treasury), "Non-numeric rate");
        assert(Math.abs((item.swap-item.treasury)*100-item.spreadBp)<0.011, "Inconsistent swap spread");
        byTenor[item.years] = item.spreadBp;
      }
      assert(Object.keys(byTenor).length===6,"Incomplete tenor curve");
      return { asOf, byTenor };
    });
    return observations.sort((a,b) => a.asOf.localeCompare(b.asOf));
  }
  function fixed(value) { return Math.round(value*100)/100; }
  function analyze(history, tenor, lookback=252) {
    assert(TENORS.includes(tenor), "Unsupported tenor");
    const observations = normalize(history);
    if (!observations.length) return {status:"unavailable",tenor,observations:0};
    const last = observations.length-1;
    const asOf = observations[last].asOf;
    const latest = observations[last].byTenor[tenor];
    // "Previous N observations" means N ACTUALLY collected valid dated snapshots,
    // not necessarily the previous N consecutive U.S. trading days.
    function change(n) {return last >= n ? fixed(latest-observations[last-n].byTenor[tenor]) : null;}
    const previous = observations.slice(Math.max(0,last-lookback),last).map(o=>o.byTenor[tenor]);
    // Require >=60 previous true observations AND >=90 calendar days of span
    // before publishing the empirical percentile; never guess from a singleton.
    const coverageDays = previous.length ? Math.floor((day(asOf)-day(observations[Math.max(0,last-lookback)].asOf))/86400000):0;
    const percentile = previous.length >= 60 && coverageDays >= 90
      ? fixed(previous.filter(v=>v<=latest).length*100/previous.length):null;
    const min = previous.length ? Math.min(...previous) : null;
    const max = previous.length ? Math.max(...previous) : null;
    return {
      status:"ok", tenor, asOf, latest, observations:observations.length,
      changes:{one:change(1),five:change(5),twenty:change(20)},
      previousCount:previous.length,coverageDays,percentile,
      observedRange:previous.length>=20?{min,max}:null,
      percentileMinPrior:60,spanMinDays:90
    };
  }
  function relativeCurve(history, longTenor=10,shortTenor=2) {
    assert(TENORS.includes(longTenor) && TENORS.includes(shortTenor),"Unsupported tenor");
    const records = normalize(history);
    if (!records.length) return {status:"unavailable"};
    const latest=records[records.length-1],previous=records.length>=2?records[records.length-2]:null;
    const value=fixed(latest.byTenor[longTenor]-latest.byTenor[shortTenor]);
    return {status:"ok",asOf:latest.asOf,longTenor,shortTenor,
      valueBp:value,deltaFromPreviousBp:previous?fixed(value-(previous.byTenor[longTenor]-previous.byTenor[shortTenor])):null,
      observations:records.length};
  }
  return {TENORS, normalize, analyze, relativeCurve};
});
