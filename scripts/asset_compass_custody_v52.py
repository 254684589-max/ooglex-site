#!/usr/bin/env python3
"""V52 long-lived PRIVATE custody for the seven V51 BLS/BEA archived releases.

Content changes between today's fetches are observed HTML byte differences,
NOT proven historical publisher revisions. A local SHA-256 chain can itself
be rewritten; authenticated backup and independent offsite anchors are needed.
Never store raw documents, custody journal, encryption keys in public repo.
"""
from __future__ import annotations

import argparse
import base64
import fcntl
import hashlib
import json
import os
import re
import stat
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import ROOT
from scripts.capture_asset_compass_official_v51 import (
    capture as capture_v51, load_candidates, _private_path,
)
from scripts.backup_asset_compass_private_v37 import _crypto, _key

JOURNAL = "v52-custody.jsonl"
LOCK = ".v52-custody.lock"
FORMAT = "ooglex-v52-aes256gcm-scrypt"
MAX_BACKUP = 64_000_000
ZERO = "0" * 64
HASH = re.compile(r"^[a-f0-9]{64}$")
ID = re.compile(r"^[a-z0-9-]{8,72}$")
REMOTE_KEY = re.compile(r"^ooglex-private/v52/[A-Za-z0-9][A-Za-z0-9._-]{0,110}\.enc$")


def canonical(item):
    return json.dumps(item, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":")).encode("utf-8")


def secure_directory(path, *, create=False):
    source = Path(path).expanduser()
    if source.is_symlink():
        raise ValueError("Private directory symlink prohibited")
    target = _private_path(source)
    if target.exists() and not target.is_dir():
        raise ValueError("Private custody path must be a directory")
    if create:
        target.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(target, 0o700)
    if not target.is_dir():
        raise FileNotFoundError("Private directory missing")
    if stat.S_IMODE(target.stat().st_mode) & 0o077:
        raise ValueError("Private directory permissions too broad")
    return target


def secure_regular(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError("Missing, symlinked or non-regular evidence file")
    if stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise ValueError("Private file has group/other permissions")
    return path.read_bytes()


@contextmanager
def custody_lock(directory):
    lock = directory / LOCK
    if lock.is_symlink():
        raise ValueError("Custody lock may not be symlinked")
    fd = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        if stat.S_IMODE(os.fstat(fd).st_mode) & 0o077:
            raise ValueError("Custody lock too permissive")
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _load_journal(directory, registry):
    target = directory / JOURNAL
    if not target.exists():
        return [], ZERO
    raw = secure_regular(target)
    sources = {x["artifact_id"]: x for x in registry["entries"]}
    rows = []
    previous = ZERO
    if raw and not raw.endswith(b"\n"):
        raise ValueError("Truncated custody journal")
    for line in raw.splitlines():
        row = json.loads(line)
        seal = row.pop("entry_hash", None)
        if row.get("prev_hash") != previous or not HASH.fullmatch(seal or ""):
            raise ValueError("Custody hash chain broken")
        if hashlib.sha256(canonical(row)).hexdigest() != seal:
            raise ValueError("Custody entry hash invalid")
        ident, digest = row.get("artifact_id"), row.get("sha256")
        src = sources.get(ident)
        if not src or not isinstance(digest, str) or not HASH.fullmatch(digest):
            raise ValueError("Unknown source or hash in custody")
        if (row.get("source_url") != src["source_url"]
                or row.get("observation_period") != src["observation_period"]
                or row.get("publisher") != src["publisher"]
                or row.get("release_kind") != src["release_kind"]):
            raise ValueError("Custody source provenance mismatch")
        captured = row.get("captured_at")
        if not isinstance(captured, str) or not captured.endswith("Z"):
            raise ValueError("Invalid capture timestamp")
        when = datetime.fromisoformat(captured.replace("Z", "+00:00"))
        if when.tzinfo is None or when > datetime.now(timezone.utc):
            raise ValueError("Custody timestamp invalid")
        if any(row.get(k) is not False for k in (
            "historical_pit_verified", "historical_release_time_verified",
            "historical_revision_chain_verified", "validated_for_live_scoring")):
            raise ValueError("Unauthorized PIT or asset scoring claim")
        name = f"{ident}-{digest}.html"
        body = secure_regular(directory / name)
        if hashlib.sha256(body).hexdigest() != digest or len(body) != row.get("byte_size"):
            raise ValueError("Evidence raw bytes were replaced or truncated")
        row["entry_hash"] = seal
        rows.append(row)
        previous = seal
    return rows, previous


def audit(directory, *, registry=None):
    registry = registry or load_candidates()
    directory = secure_directory(directory)
    with custody_lock(directory):
        records, last = _load_journal(directory, registry)
    versions = {}
    for row in records:
        versions.setdefault(row["artifact_id"], set()).add(row["sha256"])
    return {
        "schema_version": 1, "report_type": "asset_compass_v52_custody_audit",
        "status": "verified_since_v52_capture",
        "verified_capture_events": len(records),
        "distinct_source_documents": len(versions),
        "distinct_content_versions": sum(len(s) for s in versions.values()),
        "documents_with_observed_byte_changes": sum(len(s) > 1 for s in versions.values()),
        "custody_chain_last_sha256": last,
        "local_custody_verified": len(records) > 0,
        "offsite_restore_verified": False,
        "publication_time_independently_verified": False,
        "historical_pit_series_approved": 0,
        "validated_for_live_scoring": False,
    }


def capture_and_record(directory, *, registry=None, fetcher=capture_v51, now=None):
    registry = registry or load_candidates()
    directory = secure_directory(directory, create=True)
    checked = now or datetime.now(timezone.utc)
    if checked.tzinfo is None:
        raise ValueError("Capture time must have timezone")
    checked = checked.astimezone(timezone.utc)
    results = {}
    with custody_lock(directory):
        existing, prior = _load_journal(directory, registry)
        known = {(r["artifact_id"], r["sha256"], r["captured_at"]) for r in existing}
        prior_by_source = {}
        for row in existing:
            prior_by_source[row["artifact_id"]] = row["sha256"]
        pending = []
        for item in registry["entries"]:
            ident = item["artifact_id"]
            try:
                receipt = fetcher(item, now=checked, private_dir=directory)
                digest = receipt.get("sha256")
                if (receipt.get("artifact_id") != ident or
                    receipt.get("source_url") != item["source_url"] or
                    receipt.get("observation_period") != item["observation_period"] or
                    receipt.get("publisher") != item["publisher"] or
                    receipt.get("release_kind") != item["release_kind"] or
                    not isinstance(digest, str) or not HASH.fullmatch(digest) or
                    type(receipt.get("byte_size")) is not int or receipt["byte_size"] < 1 or
                    receipt.get("raw_bytes_saved_privately") is not True or
                    any(receipt.get(k) is not False for k in (
                        "raw_bytes_publicly_exported",
                        "exact_original_publication_time_verified",
                        "historical_artifact_identity_verified",
                        "historical_release_value_verified",
                        "full_revision_chain_verified",
                        "eligible_for_point_in_time_backtest",
                        "validated_for_live_scoring"))):
                    raise ValueError("Untrusted or mismatched V51 receipt")
                body = secure_regular(directory / f"{ident}-{digest}.html")
                if hashlib.sha256(body).hexdigest() != digest or len(body) != receipt["byte_size"]:
                    raise ValueError("Captured source bytes don't match receipt")
                when = datetime.fromisoformat(receipt["captured_at"].replace("Z", "+00:00"))
                if when.tzinfo is None or when > datetime.now(timezone.utc):
                    raise ValueError("Capture clock invalid")
                status = ("first_observed_custody_content" if ident not in prior_by_source
                          else "same_html_bytes_rechecked" if prior_by_source[ident] == digest
                          else "changed_html_bytes_observed_not_certified_revision")
                identity = (ident, digest, receipt["captured_at"])
                if identity not in known:
                    record = {
                        "artifact_id": ident, "publisher": item["publisher"],
                        "release_kind": item["release_kind"],
                        "observation_period": item["observation_period"],
                        "source_url": item["source_url"], "sha256": digest,
                        "byte_size": receipt["byte_size"], "captured_at": receipt["captured_at"],
                        "comparison": status,
                        "prior_observed_sha256": prior_by_source.get(ident),
                        "historical_pit_verified": False,
                        "historical_release_time_verified": False,
                        "historical_revision_chain_verified": False,
                        "validated_for_live_scoring": False,
                        "prev_hash": prior,
                    }
                    record["entry_hash"] = hashlib.sha256(canonical(record)).hexdigest()
                    prior = record["entry_hash"]
                    pending.append(record)
                    known.add(identity)
                prior_by_source[ident] = digest
                results[ident] = {"status": status, "sha256": digest}
            except (ValueError, OSError, TimeoutError, RuntimeError) as error:
                results[ident] = {"status": "capture_failed", "error_type": type(error).__name__}
        if pending:
            journal = directory / JOURNAL
            if journal.is_symlink():
                raise ValueError("Custody journal symlink forbidden")
            fd = os.open(journal, os.O_CREAT | os.O_APPEND | os.O_WRONLY, 0o600)
            with os.fdopen(fd, "ab") as writer:
                for record in pending:
                    writer.write(canonical(record) + b"\n")
                writer.flush()
                os.fsync(writer.fileno())
        verified, last = _load_journal(directory, registry)
        if len(verified) != len(existing) + len(pending):
            raise ValueError("Custody append verification failed")
    success = sum(x["status"] != "capture_failed" for x in results.values())
    return {
        "schema_version": 1, "report_type": "asset_compass_v52_capture_and_custody",
        "requested": len(registry["entries"]), "retrieved_now": success,
        "failed": len(registry["entries"]) - success,
        "verified_custody_events": len(verified),
        "new_custody_events": len(pending),
        "last_hash": last,
        "results": results,
        "original_html_retained_in_private_directory": True,
        "offsite_backup_created": False, "offsite_restore_verified": False,
        "historical_release_time_verified": False,
        "historical_pit_series_approved": 0,
        "validated_for_live_scoring": False,
    }


def encrypted_backup(directory, secret):
    registry = load_candidates()
    folder = secure_directory(directory)
    with custody_lock(folder):
        records, last = _load_journal(folder, registry)
        if not records:
            raise ValueError("Refusing to back up empty custody records")
        journal = secure_regular(folder / JOURNAL)
        documents = {}
        for row in records:
            name = f"{row['artifact_id']}-{row['sha256']}.html"
            documents[name] = base64.b64encode(secure_regular(folder / name)).decode("ascii")
        payload = canonical({"schema": 1, "journal": base64.b64encode(journal).decode("ascii"),
                             "documents": documents, "last_hash": last,
                             "entries": len(records)})
    if len(payload) > MAX_BACKUP:
        raise ValueError("Evidence backup payload too large")
    salt, nonce = os.urandom(16), os.urandom(12)
    header = {"format": FORMAT, "salt": base64.b64encode(salt).decode("ascii"),
              "nonce": base64.b64encode(nonce).decode("ascii"), "kdf_n": 2 ** 14}
    encrypted = _crypto()(_key(secret, salt)).encrypt(nonce, payload, canonical(header))
    return canonical({**header, "ciphertext": base64.b64encode(encrypted).decode("ascii")}) + b"\n"


def restore_encrypted(data, target, secret):
    target = _private_path(Path(target).expanduser())
    if target.exists() or target.is_symlink():
        raise FileExistsError("Restore target must not exist")
    if len(data) > MAX_BACKUP * 2:
        raise ValueError("Encrypted backup exceeds maximum size")
    envelope = json.loads(data)
    if envelope.get("format") != FORMAT or envelope.get("kdf_n") != 2 ** 14:
        raise ValueError("Unsupported encrypted custody package")
    header = {k: envelope[k] for k in ("format", "salt", "nonce", "kdf_n")}
    salt = base64.b64decode(header["salt"], validate=True)
    nonce = base64.b64decode(header["nonce"], validate=True)
    if len(salt) != 16 or len(nonce) != 12:
        raise ValueError("Invalid encryption parameters")
    decrypted = _crypto()(_key(secret, salt)).decrypt(
        nonce, base64.b64decode(envelope["ciphertext"], validate=True),
        canonical(header))
    payload = json.loads(decrypted)
    if payload.get("schema") != 1 or not isinstance(payload.get("documents"), dict):
        raise ValueError("Invalid custody payload")
    raw_journal = base64.b64decode(payload["journal"], validate=True)
    if len(raw_journal) > MAX_BACKUP or not raw_journal.endswith(b"\n"):
        raise ValueError("Invalid journal bytes in backup")
    records = [json.loads(l) for l in raw_journal.splitlines()]
    expected = {f"{r['artifact_id']}-{r['sha256']}.html" for r in records}
    if (not expected or expected != set(payload["documents"])
            or payload.get("entries") != len(records)
            or not HASH.fullmatch(payload.get("last_hash", ""))):
        raise ValueError("Backup document inventory mismatch")
    if not target.parent.is_dir():
        raise FileNotFoundError("Restore parent directory missing")
    folder = secure_directory(target, create=True)
    try:
        (folder / JOURNAL).write_bytes(raw_journal)
        os.chmod(folder / JOURNAL, 0o600)
        for name, content in payload["documents"].items():
            if ("/" in name or "\\" in name or ".." in name
                    or not ID.fullmatch(name.split("-")[0] if "-" not in name else name[:name.rfind("-")])
                    or not HASH.fullmatch(name[-69:-5]) or not name.endswith(".html")):
                raise ValueError("Unsafe archive filename")
            body = base64.b64decode(content, validate=True)
            if len(body) > MAX_BACKUP:
                raise ValueError("Decompressed historical evidence too large")
            dest = folder / name
            fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(body)
        checked = audit(folder)
        if (checked["verified_capture_events"] != len(records)
                or checked["custody_chain_last_sha256"] != payload["last_hash"]):
            raise ValueError("Restored original journal/hash mismatch")
    except BaseException:
        # Untrusted partial restore is left for inspection and never accepted.
        raise
    return {"restored_events": len(records), "verified_original_bytes": True,
            "custody_chain_last_sha256": payload["last_hash"],
            "restored_and_verified": True, "historical_pit_series_approved": 0,
            "validated_for_live_scoring": False}


def backup_and_restore_check(directory, backup_dir, secret, *, now=None):
    folder = secure_directory(directory)
    backup_folder = secure_directory(backup_dir, create=True)
    if (folder == backup_folder or folder in backup_folder.parents
            or backup_folder in folder.parents):
        raise ValueError("Backup path must be separate from evidence directory")
    content = encrypted_backup(folder, secret)
    stamp = (now or datetime.now(timezone.utc)).astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    dest = backup_folder / f"v52-source-evidence-{stamp}-{os.urandom(4).hex()}.enc"
    fd = os.open(dest, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "wb") as output:
        output.write(content)
        output.flush()
        os.fsync(output.fileno())
    with tempfile.TemporaryDirectory(prefix="v52-restore-", dir=backup_folder) as temp:
        restored = restore_encrypted(content, Path(temp) / "recovered", secret)
    return {"encrypted_archive": str(dest), "encrypted_sha256": hashlib.sha256(content).hexdigest(),
            "encrypted_bytes": len(content), "local_restore_verified": restored["restored_and_verified"],
            "last_hash": restored["custody_chain_last_sha256"],
            "offsite_restore_verified": False, "historical_pit_series_approved": 0,
            "validated_for_live_scoring": False}


def r2_upload_verified(archive, secret, *, remote_key=None, api=None, bucket=None):
    from scripts.sync_asset_compass_r2_v37 import client, config
    source = _private_path(Path(archive).expanduser())
    if source.is_symlink() or not source.is_file():
        raise FileNotFoundError("Local encrypted V52 archive is required")
    body = secure_regular(source)
    if json.loads(body).get("format") != FORMAT:
        raise ValueError("Cannot upload non-V52 plaintext or arbitrary file")
    key = remote_key or ("ooglex-private/v52/" + source.name)
    if not REMOTE_KEY.fullmatch(key):
        raise ValueError("Invalid private R2 object key")
    if api is None:
        endpoint, bucket = config()
        api = client(endpoint)
    elif not bucket:
        raise ValueError("Explicit R2 bucket required with injected transport")
    # R2 conditional write prevents unintended replacement of an existing key.
    api.put_object(Bucket=bucket, Key=key, Body=body, IfNoneMatch="*",
                   ContentType="application/octet-stream",
                   Metadata={"sha256": hashlib.sha256(body).hexdigest(), "format": "ooglex-v52"})
    downloaded = api.get_object(Bucket=bucket, Key=key)
    remote = downloaded["Body"].read(MAX_BACKUP * 2 + 1)
    if (len(remote) > MAX_BACKUP * 2 or remote != body
            or downloaded.get("Metadata", {}).get("sha256") != hashlib.sha256(body).hexdigest()):
        raise ValueError("Encrypted R2 readback mismatch")
    with tempfile.TemporaryDirectory(prefix="ooglex-v52-r2-recovery-") as temp:
        recovered = restore_encrypted(remote, Path(temp) / "restore", secret)
    if recovered["historical_pit_series_approved"] != 0:
        raise ValueError("Unexpected PIT approval after restore")
    return {"offsite_copy_verified": True, "offsite_restore_verified": True,
            "encrypted_sha256": hashlib.sha256(body).hexdigest(),
            "remote_key": key, "historical_pit_series_approved": 0,
            "validated_for_live_scoring": False}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("action", choices=("capture", "audit", "backup", "restore"))
    p.add_argument("--private-dir", type=Path)
    p.add_argument("--backup-dir", type=Path)
    p.add_argument("--archive", type=Path)
    p.add_argument("--restore-target", type=Path)
    p.add_argument("--offsite", action="store_true",
                   help="Upload only encrypted artifact to configured private R2 and verify restore")
    p.add_argument("--output", type=Path, default=Path("/tmp/ooglex-v52-private-custody-report.json"))
    args = p.parse_args()
    output = _private_path(args.output)
    if args.action in ("capture", "audit", "backup") and not args.private_dir:
        p.error("--private-dir required")
    if args.action == "capture":
        report = capture_and_record(args.private_dir)
    elif args.action == "audit":
        report = audit(args.private_dir)
    elif args.action == "restore":
        if not args.archive or not args.restore_target:
            p.error("--archive and --restore-target required")
        secret = os.environ.get("OOGLEX_BACKUP_PASSPHRASE")
        if not secret:
            raise ValueError("OOGLEX_BACKUP_PASSPHRASE required")
        report = restore_encrypted(secure_regular(_private_path(args.archive)),
                                   args.restore_target, secret)
    else:
        if not args.backup_dir:
            p.error("--backup-dir required")
        secret = os.environ.get("OOGLEX_BACKUP_PASSPHRASE")
        if not secret:
            raise ValueError("OOGLEX_BACKUP_PASSPHRASE required")
        report = backup_and_restore_check(args.private_dir, args.backup_dir, secret)
        if args.offsite:
            report.update(r2_upload_verified(report["encrypted_archive"], secret))
    output.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(output, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as writer:
        json.dump(report, writer, ensure_ascii=False, indent=2)
        writer.write("\n")
    safe = {k: v for k, v in report.items()
            if k not in ("encrypted_archive", "remote_key")}
    print(json.dumps(safe, ensure_ascii=False))
    if args.action == "capture" and report["failed"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
