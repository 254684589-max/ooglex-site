#!/usr/bin/env python3
"""V37 authenticated encrypted backup + validated restore for PRIVATE V36 custody.

No backup is made on GitHub Actions; only the user's explicitly configured
private filesystem and optional Cloudflare R2 bucket. No original publication
time, license approval, backtest or investment-scoring qualification is granted.
Requires: pip install cryptography
"""
import argparse
import base64
import hashlib
import json
import os
import re
import stat
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from scripts.archive_asset_compass_observations import ROOT
from scripts.verify_asset_compass_private_custody_v36 import (
    JOURNAL, private_directory, verify_journal,
)

MAX_RAW_BYTES=32_000_000
MAGIC="ooglex-v37-aes256gcm-scrypt"
KDF_N=2**14
SHA=re.compile(r"^[a-f0-9]{64}$")


def _crypto():
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError as e:
        raise RuntimeError("Install cryptography before V37 backup/restore") from e
    return AESGCM


def _key(secret, salt):
    if not isinstance(secret,str) or len(secret)<16:
        raise ValueError("Backup passphrase must contain at least 16 characters")
    return hashlib.scrypt(secret.encode("utf-8"),salt=salt,n=KDF_N,r=8,p=1,dklen=32)


def _checked_location(path):
    original=Path(path).expanduser()
    if original.is_symlink():
        raise ValueError("Symlink destination forbidden")
    p=original.resolve()
    if p.is_relative_to(ROOT.resolve()):
        raise ValueError("No private material may be stored inside website repo")
    return p


def backup_bytes(directory, secret):
    directory=private_directory(directory)
    state=verify_journal(directory)
    if state["entries"]==0:
        raise ValueError("Cannot back up an empty custody journal")
    journal=(directory/JOURNAL).read_bytes()
    documents={}
    for record in map(json.loads,journal.splitlines()):
        name=f"{record['artifact_id']}-{record['sha256']}.html"
        document=directory/name
        if document.is_symlink():
            raise ValueError("Evidence symlink forbidden")
        documents[name]=base64.b64encode(document.read_bytes()).decode("ascii")
    payload=json.dumps({
        "schema":1,"journal":base64.b64encode(journal).decode("ascii"),
        "documents":documents,
        "last_hash":state["last_hash"],"entries":state["entries"],
    },sort_keys=True,separators=(",",":")).encode()
    if len(payload)>MAX_RAW_BYTES:
        raise ValueError("Private evidence exceeds supported backup size")
    salt=os.urandom(16)
    nonce=os.urandom(12)
    header={"format":MAGIC,"salt":base64.b64encode(salt).decode("ascii"),
            "nonce":base64.b64encode(nonce).decode("ascii"),"kdf_n":KDF_N}
    aad=json.dumps(header,sort_keys=True,separators=(",",":")).encode()
    encrypted=_crypto()(_key(secret,salt)).encrypt(nonce,payload,aad)
    archive={**header,"ciphertext":base64.b64encode(encrypted).decode("ascii")}
    return json.dumps(archive,sort_keys=True,separators=(",",":")).encode()+b"\n"


def write_backup(directory,destination,secret):
    dst=_checked_location(destination)
    if dst.exists() or dst.is_symlink():
        raise FileExistsError("Backup destination already exists; use a new name")
    if not dst.parent.is_dir():
        raise FileNotFoundError("Backup output parent directory must exist")
    payload=backup_bytes(directory,secret)
    fd=os.open(dst,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
    try:
        with os.fdopen(fd,"wb") as writer:
            writer.write(payload)
            writer.flush()
            os.fsync(writer.fileno())
    except BaseException:
        dst.unlink(missing_ok=True)
        raise
    return {"archive_sha256":hashlib.sha256(payload).hexdigest(),
            "encrypted_bytes":len(payload),"encrypted":True,
            "offsite_copy_verified":False,
            "restore_test_verified":False,"pit_eligible":False}


def _decrypt(data,secret):
    if len(data)>MAX_RAW_BYTES*2:
        raise ValueError("Encrypted backup too large")
    envelope=json.loads(data)
    if (envelope.get("format")!=MAGIC
        or envelope.get("kdf_n")!=KDF_N):
        raise ValueError("Unsupported backup format")
    salt=base64.b64decode(envelope["salt"],validate=True)
    nonce=base64.b64decode(envelope["nonce"],validate=True)
    if len(salt)!=16 or len(nonce)!=12:
        raise ValueError("Invalid crypto parameters")
    header={k:envelope[k] for k in ("format","salt","nonce","kdf_n")}
    aad=json.dumps(header,sort_keys=True,separators=(",",":")).encode()
    plaintext=_crypto()(_key(secret,salt)).decrypt(
        nonce,base64.b64decode(envelope["ciphertext"],validate=True),aad)
    return json.loads(plaintext)


def restore_bytes(data,target,secret):
    target=_checked_location(target)
    if target.exists() or target.is_symlink():
        raise FileExistsError("Restore requires a nonexistent directory")
    payload=_decrypt(data,secret)
    if payload.get("schema")!=1:
        raise ValueError("Unsupported original evidence schema")
    entries=payload.get("entries")
    docs=payload.get("documents")
    if type(entries) is not int or entries<=0 or not isinstance(docs,dict):
        raise ValueError("Invalid private archive manifest")
    journal=base64.b64decode(payload["journal"],validate=True)
    if len(journal)>MAX_RAW_BYTES:
        raise ValueError("Custody journal too large")
    records=[json.loads(line) for line in journal.splitlines()]
    expected={f"{r['artifact_id']}-{r['sha256']}.html" for r in records}
    if set(docs)!=expected:
        raise ValueError("Backup has missing or extra evidence files")
    if any("/" in s or "\\" in s or not s.endswith(".html")
           or not SHA.fullmatch(s[-69:-5]) for s in docs):
        raise ValueError("Unsafe archive file path")
    if not target.parent.is_dir():
        raise FileNotFoundError("Restore parent directory missing")
    target.mkdir(mode=0o700)
    os.chmod(target,0o700)
    try:
        (target/JOURNAL).write_bytes(journal)
        os.chmod(target/JOURNAL,0o600)
        for name,value in docs.items():
            raw=base64.b64decode(value,validate=True)
            if len(raw)>MAX_RAW_BYTES:
                raise ValueError("Evidence too large")
            file=target/name
            file.write_bytes(raw)
            os.chmod(file,0o600)
        state=verify_journal(private_directory(target))
        if state["entries"]!=entries or state["last_hash"]!=payload["last_hash"]:
            raise ValueError("Restored custody journal mismatch")
    except BaseException:
        # Leave failed restore quarantined for inspection, never claim success.
        raise
    return {"restored_entries":state["entries"],"last_hash":state["last_hash"],
            "hash_chain_verified":True,"raw_files_verified":True,
            "historical_release_timestamp_verified":False,
            "eligible_for_point_in_time_backtest":False,
            "offsite_copy_verified":False}


def _passphrase():
    secret=os.environ.get("OOGLEX_BACKUP_PASSPHRASE","")
    if not secret:
        raise ValueError("OOGLEX_BACKUP_PASSPHRASE environment variable is required")
    return secret


def main():
    p=argparse.ArgumentParser(description=__doc__)
    sub=p.add_subparsers(dest="action",required=True)
    b=sub.add_parser("backup")
    b.add_argument("--private-dir",type=Path,required=True)
    b.add_argument("--output",type=Path,required=True)
    r=sub.add_parser("restore")
    r.add_argument("--archive",type=Path,required=True)
    r.add_argument("--target",type=Path,required=True)
    args=p.parse_args()
    if args.action=="backup":
        result=write_backup(args.private_dir,args.output,_passphrase())
    else:
        src=_checked_location(args.archive)
        if not src.is_file() or src.is_symlink():
            raise ValueError("Local encrypted archive missing")
        result=restore_bytes(src.read_bytes(),args.target,_passphrase())
    print(json.dumps(result,ensure_ascii=False))


if __name__=="__main__":
    main()
