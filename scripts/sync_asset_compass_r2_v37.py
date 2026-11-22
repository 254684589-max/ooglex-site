#!/usr/bin/env python3
"""V37 optional Cloudflare R2 transport for already AES-GCM-encrypted backups.

This script never uploads plaintext. Requires boto3 and configured private R2
credentials. Upload -> read back -> bytewise SHA256 check is required to claim
an off-site copy; existence of a bucket or merely issuing PUT is not proof.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
from urllib.parse import urlsplit

from scripts.backup_asset_compass_private_v37 import _checked_location, MAGIC

BUCKET=re.compile(r"^[a-z0-9][a-z0-9.-]{2,62}$")
KEY=re.compile(r"^ooglex-private/v37/[A-Za-z0-9][A-Za-z0-9._-]{0,120}\\.enc$")
ACCOUNT=re.compile(r"^[a-f0-9]{32}$")


def endpoint_for(account):
    if not ACCOUNT.fullmatch(account or ""):
        raise ValueError("Expected 32-character Cloudflare R2 account ID")
    return f"https://{account}.r2.cloudflarestorage.com"


def config():
    account=os.environ.get("CLOUDFLARE_ACCOUNT_ID","")
    bucket=os.environ.get("OOGLEX_R2_PRIVATE_BUCKET","")
    if not BUCKET.fullmatch(bucket):
        raise ValueError("Private R2 bucket name missing or invalid")
    if not all(os.environ.get(n) for n in ("AWS_ACCESS_KEY_ID","AWS_SECRET_ACCESS_KEY")):
        raise ValueError("Explicit R2 S3 API credentials are required")
    return endpoint_for(account),bucket


def client(endpoint):
    try:
        import boto3
    except ImportError as e:
        raise RuntimeError("Install boto3 for V37 Cloudflare R2 transport") from e
    return boto3.client("s3",endpoint_url=endpoint,
                        region_name="auto",
                        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
                        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"])


def remote_key(name):
    if not KEY.fullmatch(name or "") or ".." in name:
        raise ValueError("R2 object key must be ooglex-private/v37/<filename>.enc")
    return name


def upload_verified(client,bucket,key,archive):
    key=remote_key(key)
    source=_checked_location(archive)
    if source.is_symlink() or not source.is_file():
        raise FileNotFoundError("Encrypted local archive required")
    data=source.read_bytes()
    if json.loads(data).get("format")!=MAGIC:
        raise ValueError("Only authenticated encrypted V37 packages may be uploaded")
    digest=hashlib.sha256(data).hexdigest()
    client.put_object(Bucket=bucket,Key=key,Body=data,
                      ContentType="application/octet-stream",
                      Metadata={"sha256":digest,"format":"ooglex-v37"})
    remote=client.get_object(Bucket=bucket,Key=key)["Body"].read()
    if hashlib.sha256(remote).hexdigest()!=digest or remote!=data:
        raise ValueError("R2 round-trip integrity check failed")
    return {"offsite_copy_verified":True,"remote_sha256":digest,
            "encrypted_bytes":len(data),"original_pit_eligible":False,
            "restore_test_verified":False}


def download_verified(client,bucket,key,destination):
    key=remote_key(key)
    target=_checked_location(destination)
    if target.exists() or target.is_symlink():
        raise FileExistsError("Encrypted download target already exists")
    response=client.get_object(Bucket=bucket,Key=key)
    data=response["Body"].read()
    metadata=response.get("Metadata",{})
    actual=hashlib.sha256(data).hexdigest()
    if metadata.get("sha256")!=actual:
        raise ValueError("R2 content does not match uploaded SHA256 metadata")
    if json.loads(data).get("format")!=MAGIC:
        raise ValueError("Remote object is not a V37 encrypted backup")
    fd=os.open(target,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
    try:
        with os.fdopen(fd,"wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
    except BaseException:
        target.unlink(missing_ok=True)
        raise
    return {"encrypted_file_downloaded":True,
            "remote_sha256":actual,
            "restored_and_verified":False,
            "original_pit_eligible":False}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    sub=p.add_subparsers(dest="action",required=True)
    up=sub.add_parser("upload")
    up.add_argument("--archive",type=Path,required=True)
    up.add_argument("--key",required=True)
    down=sub.add_parser("download")
    down.add_argument("--key",required=True)
    down.add_argument("--output",type=Path,required=True)
    args=p.parse_args()
    endpoint,bucket=config()
    api=client(endpoint)
    result=(upload_verified(api,bucket,args.key,args.archive)
            if args.action=="upload"
            else download_verified(api,bucket,args.key,args.output))
    print(json.dumps(result,ensure_ascii=False))


if __name__=="__main__":
    main()
