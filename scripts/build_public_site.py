#!/usr/bin/env python3
"""Build the deployable Ooglex public site into .site/.

Production builds are protected by default: complete Supply Chain and Macro Risk
payloads are excluded from the static site. Full data remains in the private R2
bucket and is served only through the entitlement Worker.

For local research only, --include-pro-private can recreate the old unprotected
layout. Never use that flag for production deployment.
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".site"
PRO_BUILD = ROOT / ".pro-build"

EXCLUDED_DIR_NAMES = {
    ".git", ".github", ".claude", ".pro-build", ".site", "scripts", "docs",
    "cloudflare", "node_modules", "__pycache__",
}

EXCLUDED_SUFFIXES = {
    ".md", ".py", ".pyc", ".sql", ".yml", ".yaml", ".toml", ".sh",
}

EXCLUDED_FILES = {
    ".gitignore",
    "AGENTS.md",
    "CHANGELOG.md",
    "README.md",
}

# These paths may remain in the research repository for the existing generation
# pipeline, but must never be copied into the public deployment artifact.
PRO_PRIVATE_PATHS = {
    "apps/supply-chain/nodes.json",
    "apps/supply-chain/identity.json",
    "apps/supply-chain/peers.json",
    "apps/supply-chain/history.json",
    "apps/supply-chain/foreign.json",
    "apps/supply-chain/domestic.json",
    "apps/supply-chain/smelters.json",
    "apps/supply-chain/names-zh.json",
    "apps/supply-chain/edges",
    "apps/macro-radar/data.json",
    "apps/macro-radar/history.json",
    "apps/macro-radar/series.json",
    "apps/macro-radar/curve.json",
    "apps/macro-radar/curve-monthly.json",
}


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def under_private_path(path: Path) -> bool:
    r = rel(path)
    for item in PRO_PRIVATE_PATHS:
        if r == item or r.startswith(item.rstrip("/") + "/"):
            return True
    return False


def should_skip(path: Path, protect_pro: bool) -> bool:
    if any(part in EXCLUDED_DIR_NAMES for part in path.relative_to(ROOT).parts):
        return True
    if path.name in EXCLUDED_FILES:
        return True
    if path.suffix.lower() in EXCLUDED_SUFFIXES:
        return True
    if protect_pro and under_private_path(path):
        return True
    return False


def install_public_compatibility_preview() -> None:
    """Keep legacy public macro consumers alive without exposing full data.

    The homepage and some public terminal views still read
    apps/macro-radar/data.json. During the cutover we replace that file in the
    deployment artifact with the same FREE preview payload served by the Pro API.
    The repository source file is not modified.
    """
    src = PRO_BUILD / "macro-risk" / "preview.json"
    if not src.exists():
        raise SystemExit(
            "missing .pro-build/macro-risk/preview.json; run "
            "python scripts/pro/build_pro_datasets.py before the public build"
        )
    dst = OUT / "apps" / "macro-radar" / "data.json"
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def build(protect_pro: bool) -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    copied = 0
    skipped = 0
    for src in ROOT.rglob("*"):
        if src == OUT or OUT in src.parents:
            continue
        if should_skip(src, protect_pro):
            skipped += 1
            continue
        if not src.is_file():
            continue
        dst = OUT / src.relative_to(ROOT)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied += 1

    # Pages does not need the old GitHub Pages CNAME file in an artifact build.
    cname = OUT / "CNAME"
    if cname.exists():
        cname.unlink()

    # Never allow the server-side account schema into the static output.
    schema = OUT / "account" / "schema.sql"
    if schema.exists():
        raise SystemExit("account/schema.sql leaked into public build")

    if protect_pro:
        install_public_compatibility_preview()
        leaked = [
            p for p in OUT.rglob("*")
            if p.is_file()
            and under_private_path(ROOT / p.relative_to(OUT))
            and p.as_posix() != (OUT / "apps/macro-radar/data.json").as_posix()
        ]
        if leaked:
            raise SystemExit(
                "PRO private data leaked into public build: "
                + ", ".join(str(p) for p in leaked[:10])
            )

    if not (OUT / "index.html").exists():
        raise SystemExit("index.html missing from public build")

    print(f"Public site ready: {copied} files copied, {skipped} paths skipped")
    print(f"PRO protection: {'ON' if protect_pro else 'OFF (LOCAL ONLY)'}")


def main() -> None:
    ap = argparse.ArgumentParser()
    # Kept for compatibility with commands already used during the V0.1 rollout.
    ap.add_argument(
        "--pro-cutover", action="store_true",
        help="deprecated compatibility flag; protected mode is now the default",
    )
    ap.add_argument(
        "--include-pro-private", action="store_true",
        help="LOCAL ONLY: include legacy full PRO datasets in .site",
    )
    args = ap.parse_args()
    build(protect_pro=not args.include_pro_private)


if __name__ == "__main__":
    main()
