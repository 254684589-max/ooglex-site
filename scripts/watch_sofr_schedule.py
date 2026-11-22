#!/usr/bin/env python3
"""Read-only GitHub SOFR production run watchdog; no rate writes.

Verifies a real main-branch scheduled ingestion and its success marker.
A PR check, source probe or an unrelated Actions success NEVER counts.
"""
import argparse
from datetime import date, datetime, timedelta, timezone
import json
import os
from pathlib import Path
import sys
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_NAME = "Asset compass SOFR spread history (daily reference)"
BASE_API = "https://api.github.com/repos/254684589-max/ooglex-site"
DEFAULT_HISTORY = ROOT / "macro/swap-spreads-history.json"
DEFAULT_HEALTH = ROOT / "macro/swap-spreads-health.json"


def parse_utc(value):
    dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if dt.tzinfo is None:
        raise ValueError("Timestamp must be timezone aware")
    return dt.astimezone(timezone.utc)


def fetch_runs(token):
    url = BASE_API + "/actions/workflows/asset-compass-sofr-spreads.yml/runs?branch=main&per_page=100"
    req = Request(url, headers={
        "Accept": "application/vnd.github+json",
        "Authorization": "Bearer " + token,
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "Ooglex-SOFR-V12-Watchdog",
    })
    with urlopen(req, timeout=25) as response:
        result = json.load(response)
    if not isinstance(result.get("workflow_runs"), list):
        raise ValueError("GitHub Actions response has no workflow_runs array")
    return result["workflow_runs"]


def check(runs, history, heartbeat, now, expect_dispatch=False):
    now = parse_utc(now.isoformat() if isinstance(now, datetime) else now)
    day = now.date()
    # The regular cron is 03:35 UTC Tues-Sat; watchdog cron runs at 07:35 UTC.
    # On manual dispatch an explicit check for today's scheduled window is still useful.
    cron_day = day.weekday() in (1, 2, 3, 4, 5)
    scheduled_at = datetime(day.year, day.month, day.day, 3, 35, tzinfo=timezone.utc)
    window_start = scheduled_at - timedelta(minutes=20)
    window_end = now
    report = {
        "schemaVersion": 1,
        "type": "SOFR-production-schedule-watchdog",
        "checkedAt": now.isoformat(timespec="seconds").replace("+00:00", "Z"),
        "expectedScheduledAt": scheduled_at.isoformat(timespec="seconds").replace("+00:00", "Z"),
        "status": "unverified",
        "writesMarketData": False,
        "onlyActualGitHubRuns": True,
    }
    obs = history.get("observations")
    if history.get("schemaVersion") != 2 or history.get("demo") is not False or not isinstance(obs, list):
        raise ValueError("Invalid production historical data")
    dates = [date.fromisoformat(row["asOf"]) for row in obs]
    if len(dates) != len(set(dates)):
        raise ValueError("Duplicate dates in market archive")
    latest = max(dates).isoformat() if dates else None
    report["archiveLatestDate"] = latest
    report["archiveObservations"] = len(dates)
    if not cron_day:
        report["status"] = "not_scheduled_today"
        return report
    if now < scheduled_at:
        report["status"] = "before_schedule_window"
        return report
    candidates = []
    for run in runs:
        if run.get("name") != WORKFLOW_NAME or run.get("head_branch") != "main":
            continue
        if run.get("event") != ("workflow_dispatch" if expect_dispatch else "schedule"):
            continue
        try:
            run_at = parse_utc(run.get("created_at"))
        except (ValueError, TypeError):
            continue
        if window_start <= run_at <= window_end:
            candidates.append((run_at, run))
    if not candidates:
        report["status"] = "missing_scheduled_run" if not expect_dispatch else "missing_manual_run"
        return report
    _, run = max(candidates, key=lambda item: (item[0], item[1].get("run_attempt", 0)))
    report["runId"] = str(run.get("id") or "")
    report["runEvent"] = run["event"]
    report["runUrl"] = run.get("html_url")
    report["runStatus"] = run.get("status")
    report["runConclusion"] = run.get("conclusion")
    if run.get("status") != "completed":
        report["status"] = "run_not_complete"
        return report
    if run.get("conclusion") != "success":
        report["status"] = "run_failed"
        return report
    if not isinstance(heartbeat, dict):
        report["status"] = "success_missing_heartbeat"
        return report
    if (heartbeat.get("schemaVersion") != 1 or
        heartbeat.get("type") != "sofr-last-successful-ingestion" or
        heartbeat.get("status") != "successful" or
        str(heartbeat.get("runId")) != report["runId"]):
        report["status"] = "heartbeat_mismatch"
        return report
    if heartbeat.get("lastDataAsOf") != latest or heartbeat.get("observations") != len(dates):
        report["status"] = "archive_heartbeat_mismatch"
        return report
    try:
        succeeded = parse_utc(heartbeat["lastSuccessAt"])
    except (KeyError, TypeError, ValueError):
        report["status"] = "heartbeat_mismatch"
        return report
    if not (window_start <= succeeded <= now):
        report["status"] = "heartbeat_mismatch"
        return report
    report["status"] = "verified_scheduled_success" if not expect_dispatch else "verified_manual_success"
    report["lastSuccessAt"] = succeeded.isoformat(timespec="seconds").replace("+00:00", "Z")
    report["dataDateAgeDays"] = (day - date.fromisoformat(latest)).days if latest else None
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs-json", type=Path, help="Offline GitHub runs fixture (no API request)")
    parser.add_argument("--history", type=Path, default=DEFAULT_HISTORY)
    parser.add_argument("--heartbeat", type=Path, default=DEFAULT_HEALTH)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--today", help="UTC ISO timestamp for reproducible tests")
    parser.add_argument("--expect-dispatch", action="store_true",
                        help="Check manual rather than scheduled runs")
    args = parser.parse_args()
    if args.output.resolve().is_relative_to(ROOT.resolve()):
        parser.error("Audit output must not be in public repository")
    now = parse_utc(args.today) if args.today else datetime.now(timezone.utc)
    history = json.loads(args.history.read_text(encoding="utf-8"))
    heartbeat = json.loads(args.heartbeat.read_text(encoding="utf-8")) if args.heartbeat.exists() else None
    if args.runs_json:
        blob = json.loads(args.runs_json.read_text(encoding="utf-8"))
        runs = blob.get("workflow_runs", blob) if isinstance(blob, dict) else blob
    else:
        token = os.getenv("GITHUB_TOKEN")
        if not token:
            raise ValueError("GITHUB_TOKEN required to inspect actual GitHub Actions runs")
        runs = fetch_runs(token)
    result = check(runs, history, heartbeat, now, expect_dispatch=args.expect_dispatch)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if result["status"] not in ("verified_scheduled_success", "verified_manual_success", "not_scheduled_today", "before_schedule_window"):
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        print("V12 WATCHDOG ERROR:", error, file=sys.stderr)
        sys.exit(1)
