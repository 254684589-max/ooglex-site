#!/usr/bin/env python3
"""V10 verify actual public Ooglex deployment over HTTPS, not GitHub source.
Only network evidence counts. A failed request is a failed deployment check.
"""
import argparse
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

ENDPOINTS={
    "/macro/operations.html":("text",'id="ops-loading"','operations-v9.js'),
    "/macro/indicator-ratings.html":("text",'id="v8-heading"','indicator-monitor-v8.js'),
    "/macro/operations-v9.js":("text","asset-compass-monitor-v8.json","asset-compass-history-readiness.json"),
    "/data/asset-compass-monitor-v8.json":("json","asset_compass_monitor_v8"),
    "/data/asset-compass-provenance-v7.json":("json","asset_compass_v7_treasury_provenance"),
    "/data/asset-compass-history-readiness.json":("json","asset_compass_history_readiness"),
}
def fetch(url,attempts,delay):
    last=None
    for i in range(attempts):
        try:
            request=urllib.request.Request(url,headers={"Cache-Control":"no-cache","User-Agent":"Ooglex-Macro-V10-Deployment-Smoke/1.0"})
            with urllib.request.urlopen(request,timeout=15) as r:
                if r.status!=200:raise ValueError("HTTP "+str(r.status))
                return r.read(400000).decode("utf-8")
        except (urllib.error.URLError,TimeoutError,ValueError,UnicodeDecodeError) as exc:
            last=exc
            if i<attempts-1:time.sleep(delay)
    raise RuntimeError(str(last))
def inspect(base,sha,attempts=4,delay=4):
    issues=[]
    for path,spec in ENDPOINTS.items():
        url=base.rstrip("/")+path+"?v="+urllib.parse.quote(sha,safe="")
        try:
            content=fetch(url,attempts,delay)
            if spec[0]=="text":
                for token in spec[1:]:
                    if token not in content:raise ValueError("required marker missing: "+token)
            else:
                obj=json.loads(content)
                if obj.get("report_type")!=spec[1]:raise ValueError("wrong report_type")
                if obj.get("validated_for_live_scoring") is not False:
                    raise ValueError("model gating not confirmed")
            print("LIVE OK",path)
        except (RuntimeError,ValueError,TypeError,json.JSONDecodeError) as exc:
            print("LIVE FAIL",path,str(exc))
            issues.append(path+": "+str(exc))
    return issues
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--base",default="https://www.ooglex.com")
    p.add_argument("--sha",default=os.environ.get("GITHUB_SHA","v10"))
    p.add_argument("--attempts",type=int,default=4)
    p.add_argument("--delay",type=int,default=4)
    a=p.parse_args()
    if not a.base.startswith("https://"):raise SystemExit("Production verification requires HTTPS")
    issues=inspect(a.base,a.sha,a.attempts,a.delay)
    if issues:raise SystemExit("V10 LIVE DEPLOYMENT FAILED: "+" | ".join(issues))
    print("V10 LIVE DEPLOYMENT VERIFIED: public HTML, JS and source audit JSON")
if __name__=="__main__":main()
