#!/usr/bin/env python3
"""Fail deployment if PRO-only data is present in the public artifact."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / ".site"

FORBIDDEN = (
    "apps/supply-chain/nodes.json",
    "apps/supply-chain/identity.json",
    "apps/supply-chain/peers.json",
    "apps/supply-chain/history.json",
    "apps/supply-chain/foreign.json",
    "apps/supply-chain/domestic.json",
    "apps/supply-chain/smelters.json",
    "apps/supply-chain/names-zh.json",
    "apps/supply-chain/edges",
    "apps/macro-radar/history.json",
    "apps/macro-radar/series.json",
    "apps/macro-radar/curve.json",
    "apps/macro-radar/curve-monthly.json",
)


def fail(message: str) -> None:
    raise SystemExit("PRO PUBLIC CUTOVER FAILED: " + message)


def main() -> None:
    if not SITE.exists():
        fail(".site does not exist")

    leaked = [rel for rel in FORBIDDEN if (SITE / rel).exists()]
    if leaked:
        fail("private paths present: " + ", ".join(leaked))

    macro_path = SITE / "apps/macro-radar/data.json"
    if not macro_path.exists():
        fail("public macro compatibility preview missing")
    macro = json.loads(macro_path.read_text(encoding="utf-8"))
    if macro.get("mode") != "preview" or macro.get("product") != "macro_risk":
        fail("apps/macro-radar/data.json is not the FREE preview payload")
    if len(macro.get("signals") or []) > 3:
        fail("public macro preview exposes more than three signals")

    redirects = {
        "apps/supply-chain/index.html": "/pro/supply-chain/",
        "apps/supply-chain/company.html": "/pro/supply-chain/",
        "apps/macro-radar/index.html": "/pro/macro-risk/",
    }
    for rel, target in redirects.items():
        p = SITE / rel
        if not p.exists():
            fail(f"legacy redirect missing: {rel}")
        text = p.read_text(encoding="utf-8")
        if target not in text or "location.replace" not in text:
            fail(f"legacy page does not redirect safely: {rel}")

    for required in (
        "pro/index.html",
        "pro/supply-chain/index.html",
        "pro/macro-risk/index.html",
        "assets/pro-access.js",
    ):
        if not (SITE / required).exists():
            fail("protected frontend missing: " + required)

    print("PRO public cutover validation: PASS")
    print("- legacy pages redirect to protected frontends")
    print("- full Supply Chain JSON absent from artifact")
    print("- full Macro Risk history/series/curve absent from artifact")
    print("- public macro compatibility payload is FREE preview only")


if __name__ == "__main__":
    main()
