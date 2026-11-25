#!/usr/bin/env python3
"""Read-only probe of publicly accessible SBSEF report entrances.
Do not save report bodies, product identifiers, prices, or trade records.
"""
import argparse
import datetime as dt
from html.parser import HTMLParser
import json
import re
import urllib.request
import urllib.error

URLS = {
    "tullett": "https://www.tullettprebon.com/swap_execution_facility/sbsef_activity_summary.aspx",
    "bloomberg": "https://data.bloombergsef.com/",
    "ice": "https://www.ice.com/report/303",
}
MAX_BYTES = 4 * 1024 * 1024
HEADERS = ["batch date","asset class","tradeable instrument","description","opening price","trade high","trade low","closing price","tenor","num of trades","total notional value","ccy","prcfrmt"]

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

class Rows(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.rows = []
        self.row = None
        self.cell = None
    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.row = []
            self.cell = None
        elif tag in ("td", "th") and self.row is not None:
            self.cell = []
    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)
    def handle_endtag(self, tag):
        if tag in ("td","th") and self.cell is not None and self.row is not None:
            self.row.append(" ".join("".join(self.cell).split()))
            self.cell = None
        elif tag == "tr" and self.row is not None:
            self.rows.append(self.row)
            self.row = None
            self.cell = None

def tullett_schema(raw):
    p = Rows()
    p.feed(raw.decode("utf-8", errors="strict"))
    heads = [i for i,r in enumerate(p.rows) if [v.lower() for v in r] == HEADERS]
    if len(heads) != 1:
        return {"state":"schema_not_confirmed","publication_enabled":False}
    dates=set()
    rows=0
    for row in p.rows[heads[0]+1:]:
        if not row or not re.fullmatch(r"\d{4}-\d{2}-\d{2}",row[0]):
            break
        if len(row)!=len(HEADERS):
            return {"state":"schema_not_confirmed","publication_enabled":False}
        try:
            day=dt.date.fromisoformat(row[0])
        except ValueError:
            return {"state":"schema_not_confirmed","publication_enabled":False}
        dates.add(day.isoformat())
        rows+=1
    if not rows or len(dates)!=1:
        return {"state":"no_single_date_report","publication_enabled":False}
    return {"state":"html_report_schema_confirmed","report_date":next(iter(dates)),"publication_enabled":False}

def fetch(url):
    req=urllib.request.Request(url,headers={"User-Agent":"Ooglex regulatory source availability probe","Accept":"text/html"})
    with urllib.request.build_opener(NoRedirect()).open(req, timeout=20) as r:
        raw=r.read(MAX_BYTES+1)
        if r.status!=200 or len(raw)>MAX_BYTES:
            raise ValueError("response not accepted")
        return raw

def probe(key, fetcher=fetch):
    try:
        raw=fetcher(URLS[key])
        if not isinstance(raw,bytes) or len(raw)>MAX_BYTES:
            raise ValueError("bad response")
        if key=="tullett":
            return tullett_schema(raw)
        return {"state":"entrance_reachable_report_not_verified","publication_enabled":False}
    except urllib.error.HTTPError as e:
        return {"state":"http_error","status":e.code,"publication_enabled":False}
    except (urllib.error.URLError,TimeoutError,OSError):
        return {"state":"network_error","publication_enabled":False}
    except (ValueError,UnicodeError):
        return {"state":"validation_failed","publication_enabled":False}

if __name__=="__main__":
    print(json.dumps({k:probe(k) for k in URLS},indent=2))
