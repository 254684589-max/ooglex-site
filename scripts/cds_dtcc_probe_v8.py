#!/usr/bin/env python3
"""Bounded one-day SEC public dissemination ZIP diagnostic; no prices emitted."""
import argparse
import collections
import csv
import datetime as dt
import decimal
import hashlib
import io
import json
import re
import urllib.request
import urllib.error
import zipfile

MAX_ZIP=16*1024*1024
MAX_CSV=64*1024*1024
MAX_ROWS=200000
BASE="https://pddata.dtcc.com/ppd/api/report/cumulative/sec/SEC_CUMULATIVE_CREDITS_"
GROUPS={
    "dissemination_id":("dissemination identifier",),
    "original_id":("original dissemination identifier",),
    "action":("action type",),
    "event":("event type",),
    "execution_time":("execution timestamp","execution date time"),
    "effective_date":("effective date",),
    "maturity_date":("expiration date","maturity date"),
    "product_id":("unique product identifier","upi"),
    "underlier":("underlier id","underlier id other","underlying asset id","underlier id leg 1","underlier id other leg 1"),
    "fixed_rate":("fixed rate leg 1","fixed rate leg 2","fixed rate"),
    "notional":("notional amount leg 1","notional amount leg 2","notional amount"),
    "notional_currency":("notional currency leg 1","notional currency leg 2","notional currency"),
    "other_payment_type":("other payment type",),
    "other_payment_amount":("other payment amount",),
    "other_payment_currency":("other payment currency",),
    "payment_direction":("other payment payer","other payment receiver"),
    "spread":("spread leg 1","spread leg 2","spread"),
    "spread_notation":("spread notation leg 1","spread notation leg 2","spread notation"),
    "price":("price",),
    "price_notation":("price notation",),
    "package_flag":("package indicator","package transaction indicator"),
    "nonstandard_flag":("non standard flag","non standard indicator","non standard terms indicator"),
    "postpriced_flag":("post priced swap indicator",)
}
def norm(s):
    return " ".join(re.sub(r"[^a-z0-9]+"," ",s.lower()).split())
def number(s):
    try:
        x=decimal.Decimal(s.strip().replace(",",""))
        return x if x.is_finite() else None
    except decimal.InvalidOperation:
        return None
def audit_zip(raw,day):
    if len(raw)>MAX_ZIP:
        raise ValueError("zip size")
    date=dt.date.fromisoformat(day)
    filename="SEC_CUMULATIVE_CREDITS_"+date.strftime("%Y_%m_%d")+".csv"
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        members=z.infolist()
        if len(members)!=1 or members[0].filename.lower()!=filename.lower() or members[0].file_size>MAX_CSV or members[0].flag_bits&1:
            raise ValueError("unexpected ZIP member")
        with z.open(members[0]) as f:
            payload=f.read(MAX_CSV+1)
    if len(payload)>MAX_CSV:
        raise ValueError("csv size")
    reader=csv.DictReader(io.StringIO(payload.decode("utf-8-sig"),newline=""))
    fields=reader.fieldnames or []
    index={norm(k):k for k in fields}
    if len(index)!=len(fields) or not fields:
        raise ValueError("duplicate or missing columns")
    matched={key:[index[a] for a in aliases if a in index] for key,aliases in GROUPS.items()}
    if not matched["dissemination_id"] or not matched["action"]:
        raise ValueError("not a recognized dissemination schema")
    counts=collections.Counter()
    populated=collections.Counter()
    actions=collections.Counter()
    for row in reader:
        if None in row or any(v is None for v in row.values()):
            raise ValueError("malformed CSV row")
        counts["rows"]+=1
        if counts["rows"]>MAX_ROWS:
            raise ValueError("too many rows")
        def values(key):
            return [row[k].strip() for k in matched[key] if row[k].strip()]
        for key in GROUPS:
            if values(key): populated[key]+=1
        action=values("action")
        a=action[0].upper() if len(action)==1 else ""
        actions[a if a in {"NEWT","MODI","CORR","TERM","EROR","REVI","POSC"} else "OTHER"]+=1
        if any(v.upper() in {"UFRO","UPFRONT","UPFRONT PAYMENT"} for v in values("other_payment_type")):
            counts["upfront_type_rows"]+=1
            if any(number(v) is not None for v in values("other_payment_amount")):
                counts["upfront_numeric_rows"]+=1
                if values("fixed_rate") and values("notional"):
                    counts["upfront_fixed_notional_present_rows"]+=1
        if any("+" in v or (number(v) is not None and number(v)>=5000000) for v in values("notional")):
            counts["potentially_capped_or_large_notional_rows"]+=1
        if any(number(v) is not None for v in values("spread")):
            counts["numeric_spread_rows"]+=1
    return {"state":"zip_csv_schema_verified","report_date":day,"sha256":hashlib.sha256(raw).hexdigest(),
            "column_count":len(fields),"field_groups_present":{k:bool(v) for k,v in matched.items()},
            "nonempty_field_group_rows":dict(populated),"row_counts":dict(counts),"action_counts":dict(actions),
            "verified_reference_entities":0,"admitted_spreads":0,"publication_enabled":False}
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs): return None
def fetch(day):
    suffix=dt.date.fromisoformat(day).strftime("%Y_%m_%d")+".zip"
    req=urllib.request.Request(BASE+suffix,headers={"User-Agent":"Ooglex CDS regulatory report diagnostic","Accept":"application/zip,application/octet-stream"})
    with urllib.request.build_opener(NoRedirect()).open(req,timeout=30) as r:
        if r.status!=200: raise ValueError("http status")
        return r.read(MAX_ZIP+1)
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--date",required=True)
    args=p.parse_args()
    day=dt.date.fromisoformat(args.date)
    if not dt.datetime.now(dt.timezone.utc).date()-dt.timedelta(days=366)<=day<dt.datetime.now(dt.timezone.utc).date():
        p.error("only a single past report date within 366 days")
    try:
        result=audit_zip(fetch(args.date),args.date)
    except urllib.error.HTTPError as e:
        result={"state":"http_error","status":e.code}
    except (urllib.error.URLError,TimeoutError,OSError):
        result={"state":"network_error"}
    except (ValueError,UnicodeError,zipfile.BadZipFile,csv.Error,RuntimeError):
        result={"state":"schema_or_validation_error"}
    result.update({"report_date":args.date,"publication_enabled":False,"admitted_spreads":0})
    print(json.dumps(result,indent=2,sort_keys=True))
if __name__=="__main__": main()
