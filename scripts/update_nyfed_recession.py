#!/usr/bin/env python3
"""Read NY Fed's official monthly 12-month-ahead recession model XLS.

Workbook 'rec_prob' dates identify TARGET months, exactly twelve months after
the underlying term-spread observation month. Percent is fraction * 100.
Not official forecasts, not real-time historical release vintages.
"""
import json
import math
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path
from scripts.update_macro_fed_bea import FILE

URL="https://www.newyorkfed.org/medialibrary/media/research/capital_markets/allmonth.xls"
HEADERS=("Date","10 Year Treasury Yield","3 Month Treasury Yield",
         "3 Month Treasury Yield (Bond Equivalent)","Spread","Rec_prob","NBER_Rec")

def month_minus_twelve(d):
    return date(d.year-1,d.month,1)

def extract(rows,today=None):
    today=today or date.today()
    found=[]
    for target,raw in rows:
        if not isinstance(target,date) or type(raw) not in (int,float):
            continue
        if not math.isfinite(raw) or not 0<=raw<=1:continue
        observed=month_minus_twelve(target)
        if observed>today:continue
        if (today.year-observed.year)*12+today.month-observed.month>4:continue
        found.append((target,observed,raw))
    if not found:raise ValueError("No recent valid 12-month-ahead model probability")
    target,observed,raw=max(found,key=lambda r:r[0])
    return {
      "observation_period":observed.strftime("%Y-%m"),
      "target_period":target.strftime("%Y-%m"),
      "probability_percent":round(raw*100,6),
      "source":"Federal Reserve Bank of New York",
      "source_url":URL,
      "source_model_url":"https://www.newyorkfed.org/research/capital_markets/ycfaq.html",
      "model":"10Y minus 3M Treasury spread; recession in a month 12 months ahead",
      "official_forecast":False,"release_timestamp_verified":False,
      "unit":"percent"
    }

def parse_workbook(raw,today=None):
    import xlrd
    book=xlrd.open_workbook(file_contents=raw)
    if "rec_prob" not in book.sheet_names():raise ValueError("Missing official rec_prob sheet")
    sheet=book.sheet_by_name("rec_prob")
    headings=[str(sheet.cell_value(0,c)).strip() for c in range(sheet.ncols)]
    if len(headings)<7 or headings[:2]!=list(HEADERS[:2]) or headings[5]!="Rec_prob":
        raise ValueError("Official recession model workbook headers changed")
    rows=[]
    for i in range(1,sheet.nrows):
        try:
            exceldate=sheet.cell_value(i,0)
            target=xlrd.xldate_as_datetime(exceldate,book.datemode).date()
            value=sheet.cell_value(i,5)
        except (ValueError,TypeError,OverflowError):
            continue
        rows.append((target,value))
    return extract(rows,today)

def main():
    try:
        import xlrd
        req=urllib.request.Request(URL,headers={"User-Agent":"Mozilla/5.0 OoglexResearch/1.0"})
        with urllib.request.urlopen(req,timeout=25) as response:
            data=response.read(4000000)
        result=parse_workbook(data)
    except (ImportError,OSError,TimeoutError,ValueError,urllib.error.URLError) as exc:
        print("NYFED_RECESSION_PENDING:",type(exc).__name__,str(exc)[:160])
        return False
    if not FILE.is_file():raise ValueError("Treasury snapshot missing")
    snapshot=json.loads(FILE.read_text(encoding="utf-8"))
    if snapshot.get("schema_version")!=1:raise ValueError("Invalid macro snapshot")
    snapshot["nyfed_recession_model"]={**result,"retrieved_at":datetime.now(timezone.utc).isoformat()}
    FILE.write_text(json.dumps(snapshot,ensure_ascii=False,indent=2)+"\\n",encoding="utf-8")
    print("VERIFIED_NYFED_RECESSION:",result["observation_period"],result["target_period"],result["probability_percent"])
    return True
if __name__=="__main__":main()
