#!/usr/bin/env python3
"""Build Ooglex Pro preview/full payloads into .pro-build/.

The output directory is gitignored by design. Full payloads are intended for a
private Cloudflare R2 bucket behind the entitlement Worker; they must never be
committed to the public repository or deployed as static Pages assets.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".pro-build"


def load(path: str):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def write(rel: str, obj) -> None:
    path = OUT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size:,} bytes)")


def node_summary(node: dict) -> dict:
    keys = (
        "symbol", "name", "nameZh", "stage", "stageLabel", "stageLabelEn",
        "sector", "industry", "sic", "sicMajor", "marketCap", "country",
        "chains", "chainIds", "basis", "basisLabel", "sourceUrl", "quoteAsOf"
    )
    return {k: node.get(k) for k in keys if k in node}


def build_supply_chain() -> None:
    nodes = load("apps/supply-chain/nodes.json")
    rows = nodes.get("nodes") or []
    sample = sorted(
        (x for x in rows if isinstance(x, dict)),
        key=lambda x: (x.get("marketCap") is not None, x.get("marketCap") or 0),
        reverse=True,
    )[:40]

    preview = {
        "schemaVersion": 1,
        "product": "supply_chain",
        "mode": "preview",
        "updatedAt": nodes.get("updatedAt"),
        "asOf": nodes.get("asOf"),
        "coverage": nodes.get("coverage"),
        "stages": nodes.get("stages") or [],
        "chains": nodes.get("chains") or [],
        "chainLinks": nodes.get("chainLinks") or [],
        "chainCrossCutting": nodes.get("chainCrossCutting") or {},
        "sampleNodes": [node_summary(x) for x in sample],
        "limits": {
            "sampleCompanies": len(sample),
            "fullCompanyData": False,
            "deepRelationshipData": False,
        },
    }

    supplemental = {}
    for name in ("identity", "peers", "history", "foreign", "domestic", "smelters"):
        p = ROOT / f"apps/supply-chain/{name}.json"
        if p.exists():
            supplemental[name] = json.loads(p.read_text(encoding="utf-8"))

    full = {
        "schemaVersion": 1,
        "product": "supply_chain",
        "mode": "full",
        "primary": nodes,
        "supplemental": supplemental,
        "note": "Company edge shards remain separate migration resources and are not embedded in this bundle.",
    }

    write("supply-chain/preview.json", preview)
    write("supply-chain/full.json", full)


def signal_preview(signal: dict) -> dict:
    keys = ("key", "en", "zh", "score", "status", "statusZh")
    return {k: signal.get(k) for k in keys if k in signal}


def build_macro_risk() -> None:
    data = load("apps/macro-radar/data.json")
    signals = data.get("signals") or []
    preview = {
        "schemaVersion": 1,
        "product": "macro_risk",
        "mode": "preview",
        "updatedAt": data.get("updatedAt"),
        "asOf": data.get("asOf"),
        "live": data.get("live"),
        "source": data.get("source"),
        "regime": data.get("regime"),
        "signals": [signal_preview(x) for x in signals[:3] if isinstance(x, dict)],
        "limits": {
            "visibleSignals": min(3, len(signals)),
            "fullSignals": False,
            "history": False,
            "crisisReplay": False,
        },
    }

    full = {
        "schemaVersion": 1,
        "product": "macro_risk",
        "mode": "full",
        "data": data,
        "history": load("apps/macro-radar/history.json"),
        "series": load("apps/macro-radar/series.json"),
        "curve": load("apps/macro-radar/curve.json"),
        "curveMonthly": load("apps/macro-radar/curve-monthly.json"),
    }

    write("macro-risk/preview.json", preview)
    write("macro-risk/full.json", full)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    build_supply_chain()
    build_macro_risk()


if __name__ == "__main__":
    main()
