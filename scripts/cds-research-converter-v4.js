"use strict";
// Independent simplified 5Y research model. NOT the ISDA standard model.
// Units: rate and recovery are decimals, coupon in bps, clean upfront as
// signed fraction of notional (positive = protection buyer pays).
// Idealized 20 equal quarters, flat continuous discount and hazard,
// nonnegative flat rates, immediate default settlement, accrued coupon on default within
// each quarter. No real calendar, day count, settlement lag or curve bootstrap.
const MODEL="research_flat_hazard_5y_v1";
const DT=0.25, N=20, MAX_HAZARD=20;
function validate(p) {
 if (!p || ![100,500].includes(p.coupon_bps) ||
     !Number.isFinite(p.flat_discount_rate) || p.flat_discount_rate<0 || p.flat_discount_rate>0.3 ||
     !Number.isFinite(p.recovery) || p.recovery<0 || p.recovery>0.95)
  throw Error("explicit research inputs required");
}
function integrals(k,t){
 const x=k*t;
 if(Math.abs(x)<1e-4) {
  // Integral of exp(-k u), and of u exp(-k u), via Taylor expansion.
  return [t*(1-x/2+x*x/6-x*x*x/24+x**4/120),t*t*(0.5-x/3+x*x/8-x*x*x/30+x**4/144)];
 }
 return [-Math.expm1(-x)/k,(-Math.expm1(-x)-x*Math.exp(-x))/(k*k)];
}
function legs(p,hazard){
 validate(p);
 if(!Number.isFinite(hazard)||hazard<0||hazard>MAX_HAZARD)throw Error("invalid hazard");
 const k=p.flat_discount_rate+hazard;
 const [i0,i1]=integrals(k,DT);
 let annuity=0,protection=0;
 for(let j=0;j<N;j++){
  const s=Math.exp(-k*j*DT);
  annuity+=s*(DT*Math.exp(-k*DT)+hazard*i1);
  protection+=s*(1-p.recovery)*hazard*i0;
 }
 if(!Number.isFinite(annuity)||annuity<=0||!Number.isFinite(protection))throw Error("invalid valuation");
 return {annuity,protection,upfront_fraction:protection-p.coupon_bps/10000*annuity,spread_bps:10000*protection/annuity};
}
function convert(p){
 validate(p);
 if(!Number.isFinite(p.signed_clean_upfront_fraction)||p.upfront_unit!=="fraction_of_notional"||p.upfront_sign!=="positive_buyer_pays"||p.input_class!=="synthetic_research")
  throw Error("only explicit synthetic research inputs accepted");
 const target=p.signed_clean_upfront_fraction;
 let lo=0,hi=MAX_HAZARD;
 if(target<legs(p,lo).upfront_fraction||target>legs(p,hi).upfront_fraction)throw Error("upfront outside model bracket");
 for(let i=0;i<100;i++){
  const mid=(lo+hi)/2;
  if(legs(p,mid).upfront_fraction<target)lo=mid;else hi=mid;
 }
 const hazard=(lo+hi)/2,v=legs(p,hazard);
 if(Math.abs(v.upfront_fraction-target)>1e-10)throw Error("root residual too large");
 return {model:MODEL,market_quote:false,official_isda_validated:false,publication_enabled:false,hazard,model_spread_bps:v.spread_bps,risky_annuity_years:v.annuity,upfront_residual:v.upfront_fraction-target};
}
module.exports={MODEL,legs,convert};
