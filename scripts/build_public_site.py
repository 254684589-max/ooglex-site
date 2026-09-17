#!/usr/bin/env python3
"""Build the deployable Ooglex public site into .site/.

Production keeps the original rich Supply Chain and Macro Risk interfaces. Guest
and FREE users receive same-schema ~10% preview datasets at the legacy paths;
OWNER/PRO requests are intercepted in-browser and fulfilled through the protected
Worker/private R2 full bundle.
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".site"
PRO_BUILD = ROOT / ".pro-build"
RICH_PREVIEW = PRO_BUILD / "rich-preview"

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

PREVIEW_REPLACEMENTS = {
    "apps/supply-chain/nodes.json",
    "apps/supply-chain/peers.json",
    "apps/supply-chain/history.json",
    "apps/supply-chain/names-zh.json",
    "apps/supply-chain/edges",
    "apps/macro-radar/data.json",
    "apps/macro-radar/history.json",
}


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def under_private_path(path: Path) -> bool:
    r = rel(path)
    for item in PRO_PRIVATE_PATHS:
        if r == item or r.startswith(item.rstrip("/") + "/"):
            return True
    return False


def is_preview_replacement(path: Path) -> bool:
    r = path.relative_to(OUT).as_posix()
    for item in PREVIEW_REPLACEMENTS:
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


def copy_tree(src: Path, dst: Path) -> None:
    if not src.exists():
        raise SystemExit(f"missing rich preview source: {src.relative_to(ROOT)}")
    for p in src.rglob("*"):
        if not p.is_file():
            continue
        target = dst / p.relative_to(src)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, target)


def install_rich_public_previews() -> None:
    copy_tree(RICH_PREVIEW / "supply-chain", OUT / "apps" / "supply-chain")
    copy_tree(RICH_PREVIEW / "macro-risk", OUT / "apps" / "macro-radar")


def inject_rich_access_adapter() -> None:
    """Keep original HTML/UI and install entitlement interception before app.js."""
    snippet = (
        '\n<meta name="ooglex-pro-api" content="https://ooglex-pro-api.zlq6600e.workers.dev">\n'
        '<script src="/assets/pro-access.js?v=4"></script>\n'
        '<script src="/assets/pro-rich-data.js?v=3"></script>\n'
        '<script src="/assets/pro-preview-gate.js?v=1"></script>\n'
    )
    for relpath in (
        "apps/supply-chain/index.html",
        "apps/supply-chain/company.html",
        "apps/macro-radar/index.html",
    ):
        p = OUT / relpath
        if not p.exists():
            raise SystemExit(f"rich legacy page missing: {relpath}")
        text = p.read_text(encoding="utf-8")
        if "/assets/pro-rich-data.js" not in text:
            if "</head>" not in text:
                raise SystemExit(f"cannot inject rich access adapter: {relpath}")
            text = text.replace("</head>", snippet + "</head>", 1)
            p.write_text(text, encoding="utf-8")


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

    cname = OUT / "CNAME"
    if cname.exists():
        cname.unlink()

    schema = OUT / "account" / "schema.sql"
    if schema.exists():
        raise SystemExit("account/schema.sql leaked into public build")

    if protect_pro:
        install_rich_public_previews()
        inject_rich_access_adapter()

        leaked = []
        for p in OUT.rglob("*"):
            if not p.is_file():
                continue
            source_equivalent = ROOT / p.relative_to(OUT)
            if under_private_path(source_equivalent) and not is_preview_replacement(p):
                leaked.append(p)
        if leaked:
            raise SystemExit(
                "PRO private data leaked into public build: "
                + ", ".join(str(p) for p in leaked[:10])
            )

    if not (OUT / "index.html").exists():
        raise SystemExit("index.html missing from public build")

    print(f"Public site ready: {copied} files copied, {skipped} paths skipped")
    print(f"PRO protection: {'ON — original rich UI + 10% preview' if protect_pro else 'OFF (LOCAL ONLY)'}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pro-cutover", action="store_true", help="deprecated compatibility flag; protected mode is now the default")
    ap.add_argument("--include-pro-private", action="store_true", help="LOCAL ONLY: include legacy full PRO datasets in .site")
    args = ap.parse_args()
    build(protect_pro=not args.include_pro_private)


if __name__ == "__main__":
    main()
