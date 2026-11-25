"use strict";
const assert=require("node:assert/strict");
const {legs,convert}=require("../scripts/cds-research-converter-v4.js");
const p={coupon_bps:100,flat_discount_rate:0.04,recovery:0.4,upfront_unit:"fraction_of_notional",upfront_sign:"positive_buyer_pays",input_class:"synthetic_research"};
function approx(a,b,tol=1e-8){assert.ok(Math.abs(a-b)<=tol,"expected "+a+" ~= "+b);}
function run(name,fn){fn();console.log("PASS "+name);}
run("zero hazard analytic premium",()=>{const v=legs(p,0);let sum=0;for(let i=1;i<=20;i++)sum+=0.25*Math.exp(-0.04*i*0.25);approx(v.annuity,sum);approx(v.protection,0);});
run("zero discount and hazard",()=>{const v=legs({...p,flat_discount_rate:0},0);approx(v.annuity,5);approx(v.upfront_fraction,-0.05);});
run("independent protection integral",()=>{const h=0.05,k=h+p.flat_discount_rate,v=legs(p,h);approx(v.protection,(1-p.recovery)*h/k*(1-Math.exp(-k*5)));});
run("roundtrip hazard grid",()=>{for(const coupon_bps of [100,500])for(const flat_discount_rate of [-0.02,0,0.04,0.1])for(const h of [0,0.005,0.02,0.1,0.5,2]){const q={...p,coupon_bps,flat_discount_rate};const v=legs(q,h),r=convert({...q,signed_clean_upfront_fraction:v.upfront_fraction});approx(r.hazard,h);approx(r.model_spread_bps,v.spread_bps);}});
run("zero upfront equals coupon",()=>{for(const coupon_bps of [100,500])approx(convert({...p,coupon_bps,signed_clean_upfront_fraction:0}).model_spread_bps,coupon_bps);});
run("upfront sign",()=>{assert.ok(convert({...p,signed_clean_upfront_fraction:0.02}).model_spread_bps>100);assert.ok(convert({...p,signed_clean_upfront_fraction:-0.02}).model_spread_bps<100);});
run("monotonic spread and upfront",()=>{let prev=legs(p,0);for(let i=1;i<=200;i++){const v=legs(p,i/100);assert.ok(v.upfront_fraction>prev.upfront_fraction);assert.ok(v.spread_bps>prev.spread_bps);prev=v;}});
run("invalid recovery or rate",()=>{for(const q of [{recovery:1},{recovery:-0.1},{flat_discount_rate:NaN},{coupon_bps:37}])assert.throws(()=>legs({...p,...q},0));});
run("unsupported units or sign",()=>{for(const q of [{upfront_unit:"bps"},{upfront_sign:"unknown"},{input_class:"actual_trade"}])assert.throws(()=>convert({...p,...q,signed_clean_upfront_fraction:0}));});
run("missing and out of bracket upfront",()=>{for(const v of [undefined,NaN,-1,1])assert.throws(()=>convert({...p,signed_clean_upfront_fraction:v}));});
run("no market publication",()=>{const r=convert({...p,signed_clean_upfront_fraction:0.01});assert.equal(r.market_quote,false);assert.equal(r.official_isda_validated,false);assert.equal(r.publication_enabled,false);});
console.log("11 checks passed");
