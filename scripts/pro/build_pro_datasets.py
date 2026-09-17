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

SUPPLY_CHAIN_PREVIEW_COMPANIES = 10
SUPPLY_CHAIN_PREVIEW_COVERAGE_KEYS = (
    "claimComplete",
    "chainsTotal",
    "chainUnclassified",
    "chainLinksTotal",
    "chainDepth",
    "nodesTotal",
    "nodesWithEdges",
    "edgesTotal",
)


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


def coverage_summary(coverage: object) -> dict:
    """Return only aggregate coverage metrics safe for the compact public preview."""
    if not isinstance(coverage, dict):
        return {}
    return {
        key: coverage.get(key)
        for key in SUPPLY_CHAIN_PREVIEW_COVERAGE_KEYS
        if key in coverage
    }


def build_supply_chain() -> None:
    nodes = load("apps/supply-chain/nodes.json")
    rows = nodes.get("nodes") or []
    sample = sorted(
        (x for x in rows if isinstance(x, dict)),
        key=lambda x: (x.get("marketCap") is not None, x.get("marketCap") or 0),
        reverse=True,
    )[:SUPPLY_CHAIN_PREVIEW_COMPANIES]

    preview = {
        "schemaVersion": 1,
        "product": "supply_chain",
        "mode": "preview",
        "updatedAt": nodes.get("updatedAt"),
        "asOf": nodes.get("asOf"),
        "coverage": coverage_summary(nodes.get("coverage")),
        "sampleNodes": [node_summary(x) for x in sample],
        "limits": {
            "sampleCompanies": len(sample),
            "fullCompanyData": False,
            "fullChainMap": False,
            "deepRelationshipData": False,
        },
    }

    supplemental = {}
    for name in ("identity", "peers", "history", "foreign", "domestic", "smelters"):
        p = ROOT / f"apps/supply-chain/{name}.json"
        if p.exists():
            supplemental[name] = json.loads(p.read_text(encoding="utf-8"))

    names_zh = ROOT / "apps/supply-chain/names-zh.json"
    if names_zh.exists():
        supplemental["namesZh"] = json.loads(names_zh.read_text(encoding="utf-8"))

    # The original company detail page loads one edge shard per company. Embed
    # them in the private bundle so OWNER/PRO can use the original page without
    # exposing those shards as public static files.
    edges = {}
    edge_dir = ROOT / "apps/supply-chain/edges"
    if edge_dir.exists():
        for p in sorted(edge_dir.glob("*.json")):
            rel = f"edges/{p.name}"
            try:
                edges[rel] = json.loads(p.read_text(encoding="utf-8"))
            except Exception as exc:
                raise SystemExit(f"failed to read {p}: {exc}") from exc
    supplemental["edges"] = edges

    full = {
        "schemaVersion": 2,
        "product": "supply_chain",
        "mode": "full",
        "primary": nodes,
        "supplemental": supplemental,
        "note": "Original rich Supply Chain page contract, including company edge shards, is embedded for protected OWNER/PRO access.",
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
