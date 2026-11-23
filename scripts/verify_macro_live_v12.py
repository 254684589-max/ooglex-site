#!/usr/bin/env python3
"""V12 source-to-live SHA256 acceptance for the Ooglex macro site.

A successful GitHub commit is not a website deployment. A DNS failure fails
acceptance but is NOT attributed to the domain configuration without evidence.
"""
import argparse
import hashlib
import json
import os
import time
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path
from scripts.verify_macro_live_v11 import get, classify

FILES=(
 "macro/operations.html",
 "macro/operations-v9.js",
 "macro/indicator-ratings.html",
 "macro/indicator-a10.js",
 "macro/indicator-a10-guide.js",
 "macro/indicator-bc-official.js",
 "macro/indicator-lab.html",
 "macro/indicator-monitor-v8.js",
 "data/asset-scores.json",
 "data/asset-compass-indicator-coverage-v1.json",
 "data/asset-compass-history-readiness.json",
 "data/asset-compass-provenance-v7.json",
 "data/asset-compass-monitor-v8.json",
 "data/asset-compass-monitor-events-v8.jsonl",
)

def digest(content):
    return hashlib.sha256(content).hexdigest()

def manifest(root,sha,run_id,attempt):
    root=Path(root)
    files={}
    for key in FILES:
        path=root/key
        if not path.is_file():
            raise ValueError("missing deployment artifact: "+key)
        files[key]=digest(path.read_bytes())
    if not sha or len(sha)!=40:
        raise ValueError("full Git SHA is required")
    return {
      "schema_version":1,
      "report_type":"ooglex_macro_public_digest_v12",
      "source_commit":sha,
      "workflow_run_id":str(run_id),
      "workflow_attempt":int(attempt),
      "created_at":datetime.now(timezone.utc).isoformat(),
      "hash_algorithm":"sha256",
      "files":files,
      "validated_for_live_scoring":False,
    }

def inspect(base,expected_sha,attempts=3,delay=4):
    issues=[]
    checks=[]
    manifest_url=base.rstrip("/")+"/data/asset-compass-deploy-v12.json?deploy="+urllib.parse.quote(expected_sha,safe="")
    # Pages/CDN propagation can lag deployment. Retry a previous-commit
    # manifest, but never approve the wrong commit as an accepted deployment.
    doc=None
    manifest_failure=None
    for attempt in range(max(1,attempts)):
        try:
            candidate=json.loads(get(manifest_url))
            if not isinstance(candidate,dict):
                raise ValueError("manifest content is not an object")
            if candidate.get("source_commit")!=expected_sha:
                raise ValueError("manifest version mismatch: expected requested commit")
            if (candidate.get("report_type")!="ooglex_macro_public_digest_v12"
                or candidate.get("hash_algorithm")!="sha256"
                or candidate.get("validated_for_live_scoring") is not False
                or not isinstance(candidate.get("files"),dict)
                or set(candidate["files"])!=set(FILES)):
                raise ValueError("manifest schema or model gate mismatch")
            doc=candidate
            break
        except Exception as exc:
            manifest_failure=exc
            if attempt+1<max(1,attempts):
                time.sleep(max(0,delay))
    if doc is None:
        code,details=classify(manifest_failure)
        if isinstance(manifest_failure,ValueError) and "version mismatch" in str(manifest_failure):
            code="version_or_manifest_mismatch"
        issues.append({"path":"data/asset-compass-deploy-v12.json",
                       "category":code,"details":details[:250]})
        return {"status":"fail","checks":checks,"issues":issues}
    for path in FILES:
        expected=doc["files"][path]
        if not isinstance(expected,str) or len(expected)!=64 or any(ch not in "0123456789abcdef" for ch in expected):
            issues.append({"path":path,"category":"invalid_digest","details":"Invalid manifest digest"})
            continue
        url=base.rstrip("/")+"/"+path+"?deploy="+urllib.parse.quote(expected_sha,safe="")
        result=None
        for i in range(max(1,attempts)):
            try:
                body=get(url)
                actual=digest(body.encode("utf-8"))
                if actual!=expected:
                    raise ValueError("published artifact digest differs from expected SHA256")
                result={"path":path,"status":"pass","sha256":actual}
                break
            except Exception as exc:
                code,details=classify(exc)
                if isinstance(exc,ValueError) and "digest differs" in str(exc):
                    code="content_hash_mismatch"
                result={"path":path,"status":"fail","category":code,"details":details[:250]}
                if i+1<max(1,attempts):time.sleep(max(0,delay))
        checks.append(result)
        if result["status"]=="fail":
            issues.append({"path":path,"category":result["category"],"details":result["details"]})
    return {"status":"pass" if not issues else "fail","checks":checks,"issues":issues}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--root",type=Path,help="Build mode: produce manifest in root/data/")
    p.add_argument("--base",help="Live mode: HTTPS site URL")
    p.add_argument("--sha",default=os.environ.get("GITHUB_SHA"))
    p.add_argument("--output",type=Path,default=Path("/tmp/ooglex-v12-deployment-acceptance.json"))
    p.add_argument("--attempts",type=int,default=3)
    a=p.parse_args()
    if not a.sha or len(a.sha)!=40:
        raise SystemExit("Full Git commit SHA required")
    if bool(a.root)==bool(a.base):
        raise SystemExit("Specify exactly one of --root or --base")
    if a.root:
        result=manifest(a.root,a.sha,os.environ.get("GITHUB_RUN_ID","local"),
                        os.environ.get("GITHUB_RUN_ATTEMPT","1"))
        target=a.root/"data/asset-compass-deploy-v12.json"
        target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        print("V12 digest manifest written for",len(result["files"]),"files")
        return
    if not a.base.startswith("https://"):
        raise SystemExit("Live check requires HTTPS")
    result=inspect(a.base,a.sha,a.attempts)
    report={"schema_version":1,"report_type":"ooglex_macro_v12_live_acceptance",
            "expected_commit":a.sha,"checked_at":datetime.now(timezone.utc).isoformat(),
            **result,"model_certification_inferred":False}
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    for r in report["issues"]:
        print("::error::V12",r["path"],r["category"],r["details"])
    summary=os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary,"a",encoding="utf-8") as f:
            f.write("\n### V12 source-to-live file digest acceptance\n")
            f.write("Expected commit: `"+a.sha+"`  \n")
            f.write("Status: **"+report["status"]+"**  \n")
            for item in report["issues"]:
                f.write("- "+item["path"]+": "+item["category"]+"\n")
    if report["status"]!="pass":
        raise SystemExit("V12 live digest verification failed; consult uploaded evidence.")
    print("V12 live file SHA256 acceptance PASS")

if __name__=="__main__":main()
