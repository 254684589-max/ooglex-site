#!/usr/bin/env python3
"""V36 verify private BLS archive bytes and append a hash-chained custody journal.

This proves integrity since OUR capture, not original publication timestamp,
PIT validity, licensing or continuous availability since the historic date.
Never commit HTML or this private journal to the repository.
"""
import argparse
import hashlib
import json
import os
import re
import stat
from datetime import datetime, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import ROOT, utc
from scripts.capture_asset_compass_bls_release_v34 import ALLOWLIST

JOURNAL="custody-v36.jsonl"
SHA256=re.compile(r"^[0-9a-f]{64}$")


def canonical(row):
    return json.dumps(row, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":")).encode("utf-8")


def private_directory(path):
    directory=Path(path).expanduser().resolve()
    if directory.is_relative_to(ROOT.resolve()):
        raise ValueError("Evidence custody must be outside GitHub project")
    if directory.is_symlink():
        raise ValueError("Symlinked evidence directory not permitted")
    if not directory.is_dir():
        raise FileNotFoundError("Local private evidence directory missing")
    if stat.S_IMODE(directory.stat().st_mode) & 0o077:
        raise ValueError("Evidence directory permits group or other access")
    return directory


def verify_journal(directory):
    file=directory/JOURNAL
    if not file.exists():
        return {"entries":0,"last_hash":"0"*64}
    if file.is_symlink():
        raise ValueError("Custody journal symlink not permitted")
    if stat.S_IMODE(file.stat().st_mode) & 0o077:
        raise ValueError("Custody journal permissions too broad")
    prior="0"*64
    count=0
    for line in file.read_text(encoding="utf-8").splitlines():
        item=json.loads(line)
        seal=item.pop("entry_hash",None)
        if item.get("prev_hash")!=prior:
            raise ValueError("Custody journal chain broken")
        expected=hashlib.sha256(canonical(item)).hexdigest()
        if expected!=seal:
            raise ValueError("Custody journal entry tampered")
        verify_document(directory,item)
        prior=seal
        count+=1
    return {"entries":count,"last_hash":prior}


def verify_document(directory, receipt):
    ident=receipt.get("artifact_id")
    if ident not in ALLOWLIST:
        raise ValueError("Unknown artifact in custody receipt")
    declared=ALLOWLIST[ident]
    if receipt.get("source_url")!=declared["url"]:
        raise ValueError("Source URL does not match official allowlist")
    if receipt.get("historical_observation_period")!=declared["observation_period"]:
        raise ValueError("Unexpected historical period")
    digest=receipt.get("sha256")
    if not isinstance(digest,str) or not SHA256.fullmatch(digest):
        raise ValueError("Invalid evidence SHA256")
    name=f"{ident}-{digest}.html"
    document=directory/name
    if document.is_symlink() or not document.is_file():
        raise ValueError("Missing or symlinked private evidence HTML")
    if stat.S_IMODE(document.stat().st_mode) & 0o077:
        raise ValueError("Evidence file readable by group/others")
    actual=hashlib.sha256(document.read_bytes()).hexdigest()
    if digest!=actual or receipt.get("byte_size")!=document.stat().st_size:
        raise ValueError("Private historical HTML modified or mismatched")
    if receipt.get("eligible_for_point_in_time_backtest") is not False:
        raise ValueError("PIT approval cannot be claimed by captured receipt")
    if receipt.get("raw_artifact_saved_in_private_directory") is not True:
        raise ValueError("Receipt did not certify local raw file save")
    captured=utc(receipt["captured_at"])
    if captured>datetime.now(timezone.utc):
        raise ValueError("Future evidence capture time")
    return True


def record_batch(batch,directory):
    directory=private_directory(directory)
    previous=verify_journal(directory)
    previous_hash=previous["last_hash"]
    old_count=previous["entries"]
    appended=0
    if batch.get("historical_pit_series_approved")!=0 or batch.get("eligible_for_point_in_time_backtest") is not False:
        raise ValueError("Invalid batch PIT claim")
    entries=batch.get("entries",{})
    receipts=[]
    for ident,item in entries.items():
        if item["status"]!="captured_today_unverified_for_pit":
            continue
        receipt=item["receipt"]
        if ident!=receipt.get("artifact_id"):
            raise ValueError("Batch/receipt artifact mismatch")
        verify_document(directory,receipt)
        receipts.append(receipt)
    # Validate every new item before any append, to avoid partially committed batches.
    file=directory/JOURNAL
    already=set()
    if file.exists():
        for line in file.read_text(encoding="utf-8").splitlines():
            record=json.loads(line)
            already.add((record["artifact_id"],record["sha256"],record["captured_at"]))
    pending=[]
    for receipt in receipts:
        identity=(receipt["artifact_id"],receipt["sha256"],receipt["captured_at"])
        if identity in already:
            continue
        row={k:receipt[k] for k in ("artifact_id","source_url",
                "historical_observation_period","sha256","byte_size",
                "captured_at","eligible_for_point_in_time_backtest",
                "raw_artifact_saved_in_private_directory")}
        row["prev_hash"]=previous_hash
        seal=hashlib.sha256(canonical(row)).hexdigest()
        row["entry_hash"]=seal
        pending.append(row)
        previous_hash=seal
        already.add(identity)
    if pending:
        fd=os.open(file,os.O_WRONLY|os.O_CREAT|os.O_APPEND,0o600)
        try:
            with os.fdopen(fd,"a",encoding="utf-8") as output:
                for row in pending:
                    output.write(json.dumps(row,sort_keys=True,ensure_ascii=False,separators=(",",":"))+"\n")
                output.flush()
                os.fsync(output.fileno())
        finally:
            pass
        os.chmod(file,0o600)
        appended=len(pending)
    final=verify_journal(directory)
    if final["entries"]!=old_count+appended:
        raise ValueError("Unexpected journal length")
    return {"schema_version":1,"report_type":"asset_compass_v36_private_custody",
        "verified_existing_records":old_count,
        "new_custody_records":appended,
        "verified_total_records":final["entries"],
        "journal_last_hash":final["last_hash"],
        "raw_html_files_in_private_directory_verified":True,
        "permanent_backup_verified":False,
        "historic_release_time_verified":False,
        "eligible_for_point_in_time_backtest":False,
        "validated_for_live_scoring":False}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-dir",type=Path,required=True)
    parser.add_argument("--batch-manifest",type=Path)
    parser.add_argument("--output",type=Path,default=Path("/tmp/ooglex-v36-custody-audit.json"))
    args=parser.parse_args()
    if args.output.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Custody summary must remain outside site repo")
    if args.batch_manifest:
        batch=json.loads(args.batch_manifest.read_text(encoding="utf-8"))
        result=record_batch(batch,args.private_dir)
    else:
        state=verify_journal(private_directory(args.private_dir))
        result={"schema_version":1,"verified_total_records":state["entries"],
            "journal_last_hash":state["last_hash"],"historic_release_time_verified":False,
            "eligible_for_point_in_time_backtest":False,"validated_for_live_scoring":False}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(result,ensure_ascii=False))


if __name__=="__main__":
    main()
