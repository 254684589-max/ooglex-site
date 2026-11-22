#!/usr/bin/env python3
"""V13 read-only SOFR GitHub schedule registration preflight.

Checks configured YAML against registered active workflows on the default
branch. Registration != execution. The report does not contain market prices.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

ROOT = Path(__file__).resolve().parents[1]
REPO = "254684589-max/ooglex-site"
API = "https://api.github.com/repos/" + REPO
SPECS = {
    "ingestion": {
        "path": ".github/workflows/asset-compass-sofr-spreads.yml",
        "cron": "35 3 * * 2-6",
    },
    "watchdog": {
        "path": ".github/workflows/asset-compass-sofr-v12-watchdog.yml",
        "cron": "35 7 * * 2-6",
    },
}


def api_get(url, token):
    request=Request(url,headers={
        "Accept":"application/vnd.github+json",
        "Authorization":"Bearer "+token,
        "X-GitHub-Api-Version":"2022-11-28",
        "User-Agent":"Ooglex-SOFR-V13-Preflight",
    })
    with urlopen(request,timeout=25) as response:
        return json.load(response)


def examine(specs, files, metadata, default_branch, now):
    """Pure function; never conflates workflow active status with a completed run."""
    if default_branch!="main":
        raise ValueError("Repository default branch is not main")
    result={
        "schemaVersion":1,
        "type":"sofr-schedule-registration-preflight",
        "checkedAt":now.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00","Z"),
        "defaultBranch":default_branch,
        "runsVerified":False,
        "marketDataChanged":False,
        "workflows":{},
        "status":"verified_active_registration",
    }
    for label,spec in specs.items():
        path=spec["path"]
        source=files.get(path)
        record=metadata.get(path)
        faults=[]
        if not isinstance(source,str):
            faults.append("source_file_missing")
        else:
            if not re.search(r"(?m)^on:\s*$",source):
                faults.append("event_configuration_missing")
            if not re.search(r"(?m)^  schedule:\s*$",source):
                faults.append("schedule_configuration_missing")
            if not re.search(r"(?m)^  workflow_dispatch:\s*$",source):
                faults.append("manual_dispatch_missing")
            if not re.search(r"(?m)^\s*- cron:\s*['\"]?"+re.escape(spec["cron"])+r"['\"]?\s*$",source):
                faults.append("cron_mismatch")
            if "github.ref == 'refs/heads/main'" not in source:
                faults.append("main_branch_guard_missing")
        if not isinstance(record,dict):
            faults.append("github_workflow_not_registered")
            name=None
            state=None
        else:
            name=record.get("name")
            state=record.get("state")
            if record.get("path")!=path:
                faults.append("registered_path_mismatch")
            if state!="active":
                faults.append("workflow_not_active")
        result["workflows"][label]={
            "path":path,"expectedCronUTC":spec["cron"],
            "registeredName":name,"registeredState":state,
            "verified":not faults,"errors":faults,
        }
        if faults:
            result["status"]="registration_blocked"
    return result


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--fixture",type=Path,help="Offline metadata fixture, no network")
    args=parser.parse_args()
    if args.output.resolve().is_relative_to(ROOT.resolve()):
        parser.error("Report must be outside the public repository")
    files={v["path"]:(ROOT/v["path"]).read_text(encoding="utf-8") for v in SPECS.values()}
    if args.fixture:
        payload=json.loads(args.fixture.read_text(encoding="utf-8"))
        default=payload["default_branch"]
        registered=payload["workflows"]
    else:
        token=os.environ.get("GITHUB_TOKEN")
        if not token:
            raise ValueError("GITHUB_TOKEN required for live registration check")
        repo=api_get(API,token)
        default=repo["default_branch"]
        registered={}
        for spec in SPECS.values():
            path=spec["path"]
            try:
                registered[path]=api_get(API+"/actions/workflows/"+Path(path).name,token)
            except HTTPError as err:
                if err.code==404:
                    registered[path]=None
                else:
                    raise
    result=examine(SPECS,files,registered,default,datetime.now(timezone.utc))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(result,ensure_ascii=False,indent=2))
    return 0 if result["status"]=="verified_active_registration" else 2


if __name__=="__main__":
    try:sys.exit(main())
    except (HTTPError,URLError,OSError,ValueError,KeyError,TypeError,json.JSONDecodeError) as error:
        print("SOFR V13 PREFLIGHT FAILED:",str(error)[:200],file=sys.stderr)
        sys.exit(1)
