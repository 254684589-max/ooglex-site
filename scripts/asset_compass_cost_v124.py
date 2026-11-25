"""V124–V130: GLD filing market/NAV reconciliation and cost sensitivity.

Market-NAV difference is not execution cost. No real trading records or scores.
"""
import re
import math
import hashlib
from decimal import Decimal
from itertools import combinations
from statistics import fmean,pstdev
from scripts.asset_compass_sec_performance_v84 import tables,row_label,numbers

# Two actual SEC filings manually checked; other periods must independently
# reconcile their reported return with their own period-end share prices.
MARKET_REFERENCES={
 "1222333/000143774926025680/gld20260630_10q.htm":["-14.39","5.79","3.63","25.41"],
 "1222333/000143774926038190/gld20260930_10k.htm":["7.14","46.25","41.77"],
}
TOLERANCE=Decimal("0.03") # percentage points, rounded reported prices/returns
SCENARIOS=(0,5,10,25)

def parse_market(doc,raw):
    ticker,path,periods,reference,annual_periods=doc
    if ticker!="GLD":raise ValueError("GLD only; other funds require their own source")
    labels={
        "nav_return":r"total return, at net asset value",
        "market_return":r"total return, at market value",
        "nav_start":r"net asset value per share, beginning of period",
        "nav_end":r"net asset value per share, end of period",
        "market_start":r"market value per share, beginning of period",
        "market_end":r"market value per share, end of period",
        "expense_ratio":r"net expenses",
    }
    found=[]
    for table in tables(raw,"SPDR"):
        data={}
        for row in table:
            label=row_label(row).lower()
            for k,pattern in labels.items():
                if re.fullmatch(pattern+r"(?:\s*\(\d+\))?",label):
                    if k in data:raise ValueError("Duplicate financial highlight row")
                    data[k]=numbers(row)
        if set(data)==set(labels) and data["nav_return"]==list(map(Decimal,reference)):
            found.append(data)
    if len(found)!=1:raise ValueError("Missing or ambiguous paired financial highlights")
    d=found[0];n=len(reference)
    if any(len(v)!=n for v in d.values()):raise ValueError("Mismatched paired columns")
    if path in MARKET_REFERENCES and d["market_return"]!=list(map(Decimal,MARKET_REFERENCES[path])):
        raise ValueError("Reviewed market return mismatch")
    errors=[]
    for i in range(n):
        for basis in ("nav","market"):
            start=d[basis+"_start"][i];end=d[basis+"_end"][i]
            if min(start,end)<=0:raise ValueError("Nonpositive share price")
            gap=abs((end/start-1)*100-d[basis+"_return"][i])
            if gap>TOLERANCE:raise ValueError("Reported return disagrees with share price change")
            errors.append(gap)
        if not Decimal(0)<=d["expense_ratio"][i]<=Decimal(10):
            raise ValueError("Implausible expense ratio")
    sha=hashlib.sha256(raw).hexdigest()
    return {"ticker":"GLD","sha256":sha,"path":path,
            "direct":dict(zip(periods,d["market_return"])),
            "cumulative":dict(zip(annual_periods,d["market_return"][len(periods):])),
            "kind":"cumulative_partial" if periods else "annual",
            "columns_reconciled":n,"maximum_rounding_gap_pct":float(max(errors)),
            "reported_annualized_expense_ratio_pct":sorted({float(v) for v in d["expense_ratio"]}),
            "realized_execution_cost_certified":False}

def paired_summary(nav,market,receipts):
    nv=nav["observations"];mv=market["observations"]
    common=sorted(set(nv)&set(mv))
    if not common:return {"paired_quarters":0,"realized_execution_cost_certified":False}
    diffs=[float(Decimal(mv[m]["value"])-Decimal(nv[m]["value"])) for m in common]
    return {"paired_quarters":len(common),"quarters":common,
            "direct_paired_quarters":sum(nv[m]["method"].startswith("reported_") and mv[m]["method"].startswith("reported_") for m in common),
            "mean_market_minus_nav_pct":round(fmean(diffs),6),
            "mean_absolute_market_minus_nav_pct":round(fmean(abs(v) for v in diffs),6),
            "maximum_absolute_gap_pct":round(max(abs(v) for v in diffs),6),
            "positive_gap_quarters":sum(v>0 for v in diffs),"negative_gap_quarters":sum(v<0 for v in diffs),
            "reconciled_filing_columns":sum(r["columns_reconciled"] for r in receipts),
            "maximum_share_price_reconciliation_gap_pct":max(r["maximum_rounding_gap_pct"] for r in receipts),
            "reported_annualized_expense_ratio_pct":sorted({v for r in receipts for v in r["reported_annualized_expense_ratio_pct"]}),
            "fund_expenses_already_reflected_do_not_deduct_twice":True,
            "market_nav_difference_is_not_execution_cost":True,
            "realized_execution_cost_certified":False}

def roundtrip_return(gross_return_pct,per_side_bps):
    r=Decimal(str(gross_return_pct));bps=Decimal(str(per_side_bps))
    if not r.is_finite() or r < -100 or bps<0 or bps>=10000:raise ValueError("Invalid return or fee scenario")
    c=bps/10000
    return float(((1+r/100)*(1-c)/(1+c)-1)*100)

def research(funds):
    common=sorted(set.intersection(*(set(v) for v in funds.values()))) if funds else []
    if not common:return {"common_quarters":[],"scenario_only":True,"realized_execution_cost_certified":False}
    values={k:[float(v[m]) for m in common] for k,v in funds.items()}
    if any(not math.isfinite(x) for r in values.values() for x in r):raise ValueError("Nonfinite return")
    cost={}
    for k,vals in values.items():
        cost[k]={str(b):{"mean_quarterly_return_pct":round(fmean(roundtrip_return(v,b) for v in vals),6),
                         "positive_quarters":sum(roundtrip_return(v,b)>0 for v in vals)} for b in SCENARIOS}
    pairs={}
    for a,b in combinations(sorted(values),2):
        x=values[a];y=values[b];sx=pstdev(x);sy=pstdev(y)
        corr=None if min(sx,sy)<1e-12 else fmean((u-fmean(x))*(v-fmean(y)) for u,v in zip(x,y))/(sx*sy)
        pairs[a+"__"+b]=None if corr is None else round(max(-1,min(1,corr)),6)
    return {"common_quarters":common,"pairwise_correlations":pairs,"observations_per_pair":len(common),
            "correlation_reliability":"very_small_descriptive_sample" if len(common)<30 else "descriptive_only",
            "per_side_cost_bps":list(SCENARIOS),"cost_scenarios":cost,"scenario_only":True,
            "assumptions":"One independent buy/sell round trip per quarter, equal hypothetical cost on each side. Not observed execution or a trading strategy.",
            "fund_expenses_not_deducted_again":True,"realized_execution_cost_certified":False,
            "formal_oos_validated":False,"eligible_for_live_scoring":False}
