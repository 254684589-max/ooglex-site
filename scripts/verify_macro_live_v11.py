#!/usr/bin/env python3
"""V11 production smoke with explicit build identity and machine-readable diagnosis.

This is run AFTER GitHub Pages deployment. A GitHub commit cannot certify live HTTP.
All checks fail closed. No speculative remote status or synthetic source values.
"""
import argparse
import json
import os
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

PATHS = {
    "/macro/operations.html": ("text", ('id="ops-loading"', 'operations-v9.js')),
    "/macro/operations-v9.js": ("text", ("asset-compass-monitor-v8.json", "asset-compass-history-readiness.json")),
    "/macro/indicator-ratings.html": ("text", ('id="v8-heading"', 'indicator-monitor-v8.js')),
    "/data/asset-compass-monitor-v8.json": ("json", "asset_compass_monitor_v8"),
    "/data/asset-compass-provenance-v7.json": ("json", "asset_compass_v7_treasury_provenance"),
    "/data/asset-compass-history-readiness.json": ("json", "asset_compass_history_readiness"),
}

def classify(exc):
    if isinstance(exc, urllib.error.HTTPError):
        return ("http_"+str(exc.code),str(exc))
    cause=exc.reason if isinstance(exc,urllib.error.URLError) else exc
    while getattr(cause,"__cause__",None) is not None:
        cause=cause.__cause__
    if isinstance(cause,socket.gaierror):
        return ("dns",str(cause))
    if isinstance(cause,(TimeoutError,socket.timeout)):
        return ("timeout",str(cause))
    if isinstance(cause,ssl.SSLError):
        return ("tls",str(cause))
    if isinstance(exc,(ValueError,UnicodeDecodeError,json.JSONDecodeError)):
        return ("invalid_content",str(exc))
    return ("connection_error",str(exc))

def get(url,timeout=12):
    req=urllib.request.Request(url,headers={"User-Agent":"Ooglex-V11-Production-Smoke/1.0","Cache-Control":"no-cache"})
    with urllib.request.urlopen(req,timeout=timeout) as response:
        return response.read(1000000).decode("utf-8")

def validate_manifest(value,sha):
    if not isinstance(value,dict) or value.get("schema_version")!=1 or value.get("report_type")!="ooglex_macro_public_deploy_v11":
        raise ValueError("not a V11 deployment identity manifest")
    if value.get("source_commit")!=sha:
        raise ValueError("deployed source SHA does not match expected build commit")
    if value.get("validated_for_live_scoring") is not False:
        raise ValueError("scoring gate not disabled")
    return value

def examine(base,sha,attempts=3,delay=5):
    paths={"/data/asset-compass-deploy-v11.json":("manifest",None),**PATHS}
    findings=[]
    for path,(kind,expected) in paths.items():
        url=base.rstrip("/") + path + "?deploy="+urllib.parse.quote(sha,safe="")
        result=None
        for attempt in range(max(1,attempts)):
            try:
                payload=get(url)
                if kind=="manifest":
                    validate_manifest(json.loads(payload),sha)
                elif kind=="json":
                    doc=json.loads(payload)
                    if doc.get("report_type")!=expected or doc.get("validated_for_live_scoring") is not False:
                        raise ValueError("report schema/gate mismatch")
                else:
                    for token in expected:
                        if token not in payload:
                            raise ValueError("required marker missing: "+token)
                result={"path":path,"status":"pass","code":"ok"}
                break
            except (urllib.error.URLError,TimeoutError,ValueError,UnicodeDecodeError,ssl.SSLError,json.JSONDecodeError) as err:
                code,message=classify(err)
                if kind=="manifest" and isinstance(err,ValueError) and "source SHA" in str(err):
                    code="version_mismatch"
                result={"path":path,"status":"fail","code":code,"details":message[:320]}
                if attempt+1<max(1,attempts):
                    time.sleep(max(0,delay))
        findings.append(result)
        print("V11",result["status"].upper(),path,result["code"],flush=True)
    return findings

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--base",default="https://www.ooglex.com")
    p.add_argument("--sha",default=os.environ.get("GITHUB_SHA"))
    p.add_argument("--report",type=Path,default=Path("/tmp/ooglex-v11-live-report.json"))
    p.add_argument("--attempts",type=int,default=3)
    p.add_argument("--delay",type=int,default=5)
    args=p.parse_args()
    if not args.base.startswith("https://") or not args.sha or len(args.sha)<7:
        raise SystemExit("HTTPS and a real expected Git SHA are required")
    results=examine(args.base,args.sha,args.attempts,args.delay)
    passed=all(x["status"]=="pass" for x in results)
    report={"schema_version":1,"report_type":"ooglex_v11_live_deployment_acceptance",
            "checked_at":datetime.now(timezone.utc).isoformat(),
            "expected_source_commit":args.sha,"deployment_base":args.base,
            "status":"pass" if passed else "fail",
            "checks":results,
            "model_eligibility_inferred":False}
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    summary=os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary,"a",encoding="utf-8") as f:
            f.write("\n### V11 Macro Production Acceptance\n")
            f.write("Expected source commit: `"+args.sha+"`  \n")
            f.write("Result: **"+report["status"]+"**  \n")
            for item in results:
                f.write("- "+item["path"]+": "+item["code"]+"\n")
    if not passed:
        raise SystemExit("V11 live deployment not accepted. Inspect categorized report artifact.")
    print("V11 live HTML, JavaScript, source reports and matching build identity verified")

if __name__=="__main__":main()
