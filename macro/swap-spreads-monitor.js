/* Ooglex SOFR V4: descriptive spread movement monitoring, not trading advice. */
(function(root, factory) {
  "use strict";
  const api = factory(root.OoglexSpreadAnalytics || (typeof require === "function" ? require("./swap-spreads-analytics.js") : null));
  if(typeof module === "object" && module.exports) module.exports=api;
  else root.OoglexSwapMonitor=api;
})(typeof globalThis === "object" ? globalThis : this, function(analytics) {
  "use strict";
  if (!analytics) throw new Error("Spread analytics dependency not loaded");
  const TENORS=[2,3,5,7,10,30];
  const milliseconds=86400000;
  function median(values) {
    if(!values.length) return null;
    const sorted=[...values].sort((a,b)=>a-b),i=Math.floor(sorted.length/2);
    return sorted.length%2?sorted[i]:(sorted[i-1]+sorted[i])/2;
  }
  function round(x) {return Math.round(x*100)/100;}
  function analyze(history, tenor, nowISO) {
    if(!TENORS.includes(tenor))throw new Error("Unsupported tenor");
    const points=analytics.normalize(history);
    if(!points.length)return {status:"unavailable",tenor,count:0,reason:"no_observations"};
    const latest=points[points.length-1];
    const today=nowISO ? new Date(nowISO) : new Date();
    if(!Number.isFinite(today.getTime()))throw new Error("Invalid current clock");
    const freshnessDays=(today-new Date(latest.asOf+"T00:00:00Z"))/milliseconds;
    const stale=freshnessDays>7||freshnessDays<0;
    const prev=points.length>=2?points[points.length-2]:null;
    const current=latest.byTenor[tenor];
    const delta=prev?round(current-prev.byTenor[tenor]):null;
    const direction=delta===null?"insufficient":delta>0?"widening":delta<0?"tightening":"unchanged";
    // Empirical threshold from 30 genuine observed day-to-day changes, excluding latest.
    // Calendar gaps are permitted but labeled as changes between ARCHIVED observations.
    const priorChanges=[];
    const start=Math.max(1,points.length-31);
    for(let i=start;i<points.length-1;i++)
      priorChanges.push(round(points[i].byTenor[tenor]-points[i-1].byTenor[tenor]));
    const span=points.length>=2?Math.floor((new Date(latest.asOf+"T00:00:00Z")-new Date(points[Math.max(0,points.length-32)].asOf+"T00:00:00Z"))/milliseconds):0;
    let baseline=null, threshold=null, exceptional=false;
    if(priorChanges.length>=30 && span>=45 && delta!==null) {
      const med=median(priorChanges);
      const mad=median(priorChanges.map(v=>Math.abs(v-med)));
      // 1.4826 scales median absolute deviation for normal comparison.
      baseline={medianBp:round(med),madBp:round(mad),count:priorChanges.length,spanDays:span};
      threshold=round(Math.max(10,3*1.4826*mad));
      exceptional=Math.abs(delta-med)>=threshold;
    }
    return {status:stale?"stale":"ok",tenor,asOf:latest.asOf,count:points.length,
      latestBp:current,previousAsOf:prev?prev.asOf:null,deltaBp:delta,direction,
      freshnessDays:round(freshnessDays),baseline,thresholdBp:threshold,
      classification:delta===null?"insufficient":stale?"stale":
        baseline===null?"descriptive_only":exceptional?"unusual_observed_change":"normal_observed_change"};
  }
  return {analyze,median};
});