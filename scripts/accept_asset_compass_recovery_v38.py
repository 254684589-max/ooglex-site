#!/usr/bin/env python3
"""V38 one-command local/offsite recovery acceptance for PRIVATE BLS custody.

No remote action is attempted without --offsite and R2 credentials. No
automatic upload of plaintext; fail closed and write a status-only report.
This verifies custody since capture, not historical availability or PIT.
"""
import argparse
import json
import os
import secrets
import stat
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import ROOT
from scripts.backup_asset_compass_private_v37 import (
    _checked_location, restore_bytes, write_backup,
)
from scripts.verify_asset_compass_private_custody_v36 import (
    private_directory, record_batch, verify_journal,
)


def private_backup_directory(path):
    original=Path(path).expanduser()
    if original.is_symlink():
        raise ValueError("Backup directory must not be a symlink")
    dest=_checked_location(original)
    if dest.exists() and not dest.is_dir():
        raise ValueError("Backup destination must be a directory")
    dest.mkdir(mode=0o700,parents=True,exist_ok=True)
    os.chmod(dest,0o700)
    return dest


def execute(*, private_dir, backup_dir, secret, capture=False, offsite=False,
            batch_fetcher=None, r2_client=None, r2_bucket=None, now=None):
    checked=now or datetime.now(timezone.utc)
    if checked.tzinfo is None:
        raise ValueError("Verification time must include timezone")
    checked=checked.astimezone(timezone.utc)
    report={
        "schema_version":1,"report_type":"asset_compass_v38_recovery_acceptance",
        "checked_at":checked.isoformat(),"status":"not_started",
        "capture_attempted":False,"capture_successful":False,
        "private_custody_verified":False,"encrypted_backup_created":False,
        "local_restore_verified":False,"offsite_copy_verified":False,
        "offsite_restore_verified":False,
        "historical_release_time_verified":False,
        "eligible_for_point_in_time_backtest":False,
        "validated_for_live_scoring":False,
        "automatic_investment_alerts_enabled":False,
    }
    stage="preflight"
    try:
        if not isinstance(secret,str) or len(secret)<16:
            raise ValueError("Encryption password must contain at least 16 characters")
        source=_checked_location(private_dir)
        backup=private_backup_directory(backup_dir)
        if source==backup or source.is_relative_to(backup) or backup.is_relative_to(source):
            raise ValueError("Evidence directory and backup directory must be separate")
        if capture:
            stage="capture"
            report["capture_attempted"]=True
            if batch_fetcher is None:
                from scripts.capture_asset_compass_bls_batch_v35 import collect
                batch=collect(private_dir=source)
            else:
                batch=batch_fetcher(private_dir=source)
            report["capture_requested"]=batch["requested_archives"]
            report["capture_downloaded"]=batch["fetched_archives"]
            report["capture_failed"]=batch["failed_archives"]
            # Save all successfully captured files before marking incomplete.
            record_batch(batch,source)
            if batch["failed_archives"]:
                raise ValueError("Not all BLS source documents were captured")
            report["capture_successful"]=True
        stage="custody_check"
        initial=verify_journal(private_directory(source))
        if not initial["entries"]:
            raise ValueError("No real private custody records exist")
        report["private_custody_verified"]=True
        report["custody_entries"]=initial["entries"]
        report["custody_last_hash"]=initial["last_hash"]
        stage="encrypted_backup"
        name=(f"bls-evidence-v38-{checked.strftime('%Y%m%dT%H%M%SZ')}-"
              f"{secrets.token_hex(4)}.enc")
        archive=backup/name
        created=write_backup(source,archive,secret)
        report["encrypted_backup_created"]=True
        report["encrypted_archive_sha256"]=created["archive_sha256"]
        report["encrypted_archive_filename"]=name
        stage="local_restore"
        with tempfile.TemporaryDirectory(prefix="v38-local-check-",dir=backup) as temp:
            result=restore_bytes(archive.read_bytes(),Path(temp)/"restore",secret)
            if not result["hash_chain_verified"] or result["last_hash"]!=initial["last_hash"]:
                raise ValueError("Local recovery differs from original custody")
        report["local_restore_verified"]=True
        if offsite:
            stage="r2_preflight"
            from scripts.sync_asset_compass_r2_v37 import (
                client, config, download_verified, upload_verified,
            )
            if r2_client is None:
                endpoint,bucket=config()
                api=client(endpoint)
            else:
                if not r2_bucket:
                    raise ValueError("R2 bucket is required for injected transport")
                api,bucket=r2_client,r2_bucket
            key="ooglex-private/v37/"+name
            stage="r2_upload_roundtrip"
            remote=upload_verified(api,bucket,key,archive)
            report["offsite_copy_verified"]=remote["offsite_copy_verified"]
            report["remote_key"]=key
            stage="r2_restore"
            with tempfile.TemporaryDirectory(prefix="v38-r2-check-",dir=backup) as temp:
                downloaded=Path(temp)/"retrieved.enc"
                download_verified(api,bucket,key,downloaded)
                recovered=restore_bytes(downloaded.read_bytes(),
                                        Path(temp)/"recovered",secret)
                if recovered["last_hash"]!=initial["last_hash"]:
                    raise ValueError("Remote restore does not match original custody")
            report["offsite_restore_verified"]=True
        report["status"]="offsite_recovery_verified" if offsite else "local_recovery_verified_only"
    except Exception as exc:
        report["status"]="failed"
        report["failed_stage"]=stage
        report["failure_type"]=type(exc).__name__
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--private-dir",type=Path,required=True)
    p.add_argument("--backup-dir",type=Path,required=True)
    p.add_argument("--capture",action="store_true",
                   help="Explicitly download three actual BLS releases first")
    p.add_argument("--offsite",action="store_true",
                   help="Explicitly upload and verify encrypted backup via private R2")
    p.add_argument("--output",type=Path,default=Path("/tmp/ooglex-v38-acceptance.json"))
    args=p.parse_args()
    output=_checked_location(args.output)
    secret=os.environ.get("OOGLEX_BACKUP_PASSPHRASE")
    if not secret:
        # Prompt interactively, never pass a secret as a CLI argument or store
        # it in the GitHub repository.
        import getpass
        secret=getpass.getpass("V38 backup passphrase (>=16 characters): ")
    result=execute(private_dir=args.private_dir,backup_dir=args.backup_dir,
                   secret=secret,capture=args.capture,offsite=args.offsite)
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",
                      encoding="utf-8")
    os.chmod(output,0o600)
    print(json.dumps({k:v for k,v in result.items()
                      if k not in ("remote_key","encrypted_archive_filename")},
                     ensure_ascii=False))
    if result["status"]=="failed":
        raise SystemExit(2)

if __name__=="__main__":
    main()
