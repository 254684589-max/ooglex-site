#!/usr/bin/env python3
"""Build a deployable static site into .site/.

This is intended for Cloudflare Pages. It keeps the public website structure but
excludes repository-only material. With --pro-cutover it also removes the legacy
public copies of the two PRO datasets; use that mode only after the frontend has
been switched to the protected Worker API and R2 data is live.
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".site"

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

# Full copies that must not be present in the public Pages output after the
# entitlement API has been cut over. Some are currently public legacy assets,
# therefore they remain in normal builds until --pro-cutover is deliberately used.
PRO_PRIVATE_PATHS = {
    "apps/supply-chain/nodes.json",
    "apps/supply-chain/identity.json",
    "apps/supply-chain/peers.json",
    "apps/supply-chain/history.json",
    "apps/supply-chain/foreign.json",
    "apps/supply-chain/domestic.json",
    "apps/supply-chain/smelters.json",
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


def should_skip(path: Path, pro_cutover: bool) -> bool:
    if any(part in EXCLUDED_DIR_NAMES for part in path.relative_to(ROOT).parts):
        return True
    if path.name in EXCLUDED_FILES:
        return True
    if path.suffix.lower() in EXCLUDED_SUFFIXES:
        return True
    if pro_cutover and under_private_path(path):
        return True
    return False


def build(pro_cutover: bool) -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    copied = 0
    skipped = 0
    for src in ROOT.rglob("*"):
        if src == OUT or OUT in src.parents:
            continue
        if should_skip(src, pro_cutover):
            skipped += 1
            continue
        if not src.is_file():
            continue
        dst = OUT / src.relative_to(ROOT)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied += 1

    # Pages does not need the old GitHub Pages CNAME file. Keeping it is harmless
    # but omitting it makes ownership of the production hostname explicit.
    cname = OUT / "CNAME"
    if cname.exists():
        cname.unlink()

    # Never allow the server-side account schema into the static output even if
    # file-extension policy changes later.
    schema = OUT / "account" / "schema.sql"
    if schema.exists():
        raise SystemExit("account/schema.sql leaked into public build")

    if pro_cutover:
        leaked = [p for p in OUT.rglob("*") if p.is_file() and under_private_path(ROOT / p.relative_to(OUT))]
        if leaked:
            raise SystemExit("PRO private data leaked into Pages build: " + ", ".join(str(p) for p in leaked[:10]))

    if not (OUT / "index.html").exists():
        raise SystemExit("index.html missing from public build")

    print(f"Cloudflare Pages build ready: {copied} files copied, {skipped} paths skipped")
    print(f"PRO cutover mode: {'ON' if pro_cutover else 'OFF'}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pro-cutover", action="store_true",
                    help="exclude legacy public copies of Supply Chain and Macro Risk PRO datasets")
    args = ap.parse_args()
    build(args.pro_cutover)


if __name__ == "__main__":
    main()
