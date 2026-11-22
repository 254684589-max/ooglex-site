#!/usr/bin/env python3
"""V8 operational monitoring for Ooglex macro research (no trading authorization).

Checks committed artifacts, records consecutive unhealthy MONITOR runs, and
retains append-only monitor events. It never repairs original archives.
"""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data" / "asset-compass-monitor-v8.json"
EVENTS = ROOT / "data" / "asset-compass-monitor-events-v8.jsonl"
SNAPSHOT = ROOT / "data" / "asset-scores.json"
READY = ROOT / "data" / "asset-compass-history-readiness.json"
PROVENANCE = ROOT / "data" / "asset-compass-provenance-v7.json"
LEDGER = ROOT / "data" / "asset-compass-observation-ledger.jsonl"

def instant(value):
    d = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if d.tzinfo is None:
        raise ValueError("UTC offset is required")
    return d.astimezone(timezone.utc)

def read_json(p):
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None

def digest_ledger(path):
    if not path.is_file():
        return None
    return hashlib.sha256(path.read_bytes()).hexdigest()

def evaluate(snapshot, ready, provenance, ledger_digest, now, previous=None, *, run_id=None):
    now = instant(now) if isinstance(now, str) else now.astimezone(timezone.utc)
    issues = []
    def flag(name, detail):
        issues.append({"code": name, "detail": detail})
    if not isinstance(snapshot, dict) or snapshot.get("schema_version") != 1:
        flag("snapshot_missing_or_invalid", "官方宏观快照不存在或结构无效")
    else:
        try:
            t = instant(snapshot["generated_at"])
            elapsed = (now-t).total_seconds()/3600
            if elapsed < -1:
                flag("snapshot_timestamp_in_future", "快照时间超前超过1小时")
            elif elapsed > 48:
                flag("snapshot_stale", "快照生成已超过48小时："+str(round(elapsed,1))+"小时")
        except (KeyError, ValueError, TypeError, OverflowError):
            flag("snapshot_time_invalid", "快照生成时间无效")
        if snapshot.get("status") not in ("partial_data_no_full_score", "ok_no_full_score"):
            flag("unexpected_snapshot_status", "官方宏观快照状态无效")
        if any(a.get("score") is not None for a in (snapshot.get("assets") or {}).values()
               if isinstance(a, dict)):
            flag("unguarded_asset_score", "未经授权的资产得分存在")
    if not isinstance(ready, dict) or ready.get("report_type") != "asset_compass_history_readiness":
        flag("readiness_missing", "归档准备度报告不存在或无效")
    else:
        if ready.get("validated_for_live_scoring") is not False or ready.get("eligible_for_point_in_time_backtest") is not False:
            flag("readiness_gate_unlocked", "归档报告错误地开启了模型资格")
        if not isinstance(ready.get("archived_observations"), int) or ready["archived_observations"] <= 0:
            flag("empty_archive", "归档观测数为空")
    if not isinstance(provenance, dict) or provenance.get("report_type") != "asset_compass_v7_treasury_provenance":
        flag("provenance_missing", "V7来源报告不存在或无效")
    else:
        if provenance.get("validated_for_live_scoring") is not False or provenance.get("legacy_rows_are_valid_evidence") is not False:
            flag("provenance_gate_unlocked", "V7报告错误地开启评分或认可历史错误来源")
        if provenance.get("integrity_gate_passed") is not True or provenance.get("unexpected_mismatch_rows") != 0:
            flag("provenance_unexpected", "V7来源年份审计出现未知异常")
        if ledger_digest is None or provenance.get("ledger_sha256") != ledger_digest:
            flag("provenance_digest_drift", "V7审计哈希与当前归档不一致，需要重跑归档审计")
    status = "healthy" if not issues else "alert"
    old = previous if isinstance(previous, dict) and previous.get("schema_version") == 1 and previous.get("report_type") == "asset_compass_monitor_v8" else None
    previous_streak = old.get("consecutive_alert_runs", 0) if old else 0
    if not isinstance(previous_streak,int) or previous_streak<0:previous_streak=0
    # Prevent a manual rerun of the same workflow run from counting twice.
    same_run = bool(old and run_id is not None and old.get("run_id") == str(run_id))
    streak = 0 if status == "healthy" else (previous_streak if same_run else previous_streak+1)
    return {"schema_version":1,"report_type":"asset_compass_monitor_v8",
            "checked_at":now.isoformat(),"run_id":str(run_id) if run_id is not None else None,
            "operational_status":status,"issues":issues,
            "consecutive_alert_runs":streak,
            "alert_severity":"critical" if streak>=3 or any(i["code"] in
              {"unguarded_asset_score","readiness_gate_unlocked","provenance_gate_unlocked"} for i in issues)
              else ("warning" if issues else "none"),
            "archive_ledger_sha256":ledger_digest,
            "validated_for_live_scoring":False,
            "point_in_time_backtest_eligible":False,
            "note":"Operational health is separate from PIT/model-scoring certification. No auto repair."}

def publish(report, output, events):
    output.parent.mkdir(parents=True, exist_ok=True)
    events.parent.mkdir(parents=True, exist_ok=True)
    # Event append-only: never change previously written bytes.
    event = {k:report[k] for k in ("checked_at","run_id","operational_status",
                                  "consecutive_alert_runs","alert_severity","issues")}
    if events.exists():
        old = events.read_text(encoding="utf-8")
        last = old.splitlines()[-1] if old.strip() else None
        if last:
            existing=json.loads(last)
            if existing.get("run_id")==report["run_id"] and report["run_id"] is not None:
                if existing!=event:
                    raise ValueError("Same run ID changed: refusing to overwrite immutable event")
                append=False
            else:
                if instant(existing["checked_at"])>instant(event["checked_at"]):
                    raise ValueError("Cannot backdate monitor history")
                append=True
        else: append=True
    else: append=True
    if append:
        with events.open("a",encoding="utf-8") as f:
            f.write(json.dumps(event,ensure_ascii=False,separators=(",",":"))+"\n")
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--snapshot",type=Path,default=SNAPSHOT)
    p.add_argument("--readiness",type=Path,default=READY)
    p.add_argument("--provenance",type=Path,default=PROVENANCE)
    p.add_argument("--ledger",type=Path,default=LEDGER)
    p.add_argument("--output",type=Path,default=OUTPUT)
    p.add_argument("--events",type=Path,default=EVENTS)
    p.add_argument("--run-id")
    p.add_argument("--fail-on-alert",action="store_true")
    a=p.parse_args()
    report=evaluate(read_json(a.snapshot),read_json(a.readiness),
                    read_json(a.provenance),digest_ledger(a.ledger),
                    datetime.now(timezone.utc),read_json(a.output),run_id=a.run_id)
    publish(report,a.output,a.events)
    print(json.dumps({"status":report["operational_status"],"issues":report["issues"],
                      "consecutive_alert_runs":report["consecutive_alert_runs"]},ensure_ascii=False))
    if a.fail_on_alert and report["operational_status"]!="healthy":raise SystemExit(2)

if __name__=="__main__":
    main()
