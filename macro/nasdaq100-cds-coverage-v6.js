"use strict";
(function(root){
  const classes=["contract_excluded","missing_product_identifier","unmatched_label","invalid_price_or_count","incompatible_price_format","coupon_collision","price_semantics_unverified"];
  function summarize(d){
    if(d?.schema_version!==1||d.source!=="tradeweb_sbsef_dmdr"||d.publication_enabled!==false||d.admitted_par_spreads!==0||!d.reports||typeof d.reports!=="object"||Array.isArray(d.reports))throw Error("ledger");
    const days=Object.keys(d.reports).sort();
    const totals=Object.fromEntries(classes.map(k=>[k,0]));
    const issuers=new Map();let rows=0,versions=0;
    for(const day of days){
      const entries=d.reports[day];
      if(!/^\d{4}-\d{2}-\d{2}$/.test(day)||!Array.isArray(entries)||!entries.length)throw Error("date/version");
      for(const v of entries){
        const counts=v.classification_counts;
        if(v.admitted_par_spreads!==0||v.verified_reference_entities!==0||!Number.isInteger(v.report_rows)||v.report_rows<=0||!counts||Object.keys(counts).some(k=>!classes.includes(k))||Object.values(counts).some(n=>!Number.isInteger(n)||n<0)||Object.values(counts).reduce((a,b)=>a+b,0)!==v.report_rows||!Array.isArray(v.candidate_issuer_ids)||v.candidate_issuer_ids.some(x=>typeof x!=="string"||!x)||new Set(v.candidate_issuer_ids).size!==v.candidate_issuer_count||v.candidate_issuer_ids.length!==v.candidate_issuer_count||v.candidate_issuer_count>100)throw Error("version");
      }
      const v=entries.at(-1);versions+=entries.length;rows+=v.report_rows;
      for(const k of classes)totals[k]+=v.classification_counts[k]||0;
      for(const id of v.candidate_issuer_ids){
        const x=issuers.get(id)||{id,report_days:0,first_day:day,last_day:day};
        x.report_days++;x.last_day=day;issuers.set(id,x);
      }
    }
    return {days:days.length,versions,rows,totals,candidates:[...issuers.values()].sort((a,b)=>a.id.localeCompare(b.id)),first:days[0]||null,last:days.at(-1)||null,admitted:0};
  }
  if(typeof module==="object"&&module.exports)module.exports={summarize};
  else root.OoglexCdsCoverageV6={summarize};
})(globalThis);
