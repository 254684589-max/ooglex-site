#!/usr/bin/env python3
"""Build safe previews for the original rich Supply Chain and Macro pages.

The FREE experience keeps the original page/UI. It is *not* implemented by shipping
full data and hiding it with CSS. Public payloads remain reduced, while the page uses
a Bloomberg-style paywall treatment after the visible preview area.
"""
from __future__ import annotations

import copy
import json
import math
import shutil
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".pro-build" / "rich-preview"
RATIO = 0.10


def load(rel: str):
    return json.loads((ROOT / rel).read_text(encoding="utf-8"))


def write(rel: str, obj) -> None:
    path = OUT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size:,} bytes)")


def count10(n: int) -> int:
    if n <= 0:
        return 0
    return max(1, math.ceil(n * RATIO))


def top_market_cap_nodes(nodes: list[dict]) -> list[dict]:
    rows = [x for x in nodes if isinstance(x, dict)]
    rows.sort(
        key=lambda x: (
            x.get("marketCap") is not None,
            x.get("marketCap") or 0,
            str(x.get("symbol") or ""),
        ),
        reverse=True,
    )
    return rows[:count10(len(rows))]


def filter_symbol_map(value, symbols: set[str]):
    if not isinstance(value, dict):
        return value
    return {k: v for k, v in value.items() if str(k).upper() in symbols}


def preview_edge_payload(obj: dict) -> dict:
    """Keep <=10% of a company edge shard; never copy a full shard to Pages."""
    out = copy.deepcopy(obj)
    full_rows = [x for x in (obj.get("edges") or []) if isinstance(x, dict)]
    keep = count10(len(full_rows))
    rows = full_rows[:keep]
    out["edges"] = rows

    by_country = Counter()
    by_mineral = Counter()
    for row in rows:
        country = row.get("country")
        if country:
            by_country[str(country)] += 1
        for mineral in row.get("minerals") or []:
            if mineral:
                by_mineral[str(mineral)] += 1
    out["byCountry"] = dict(by_country)
    out["byMineral"] = dict(by_mineral)

    parse = copy.deepcopy(out.get("parse") or {})
    parse["unique"] = len(rows)
    parse["nameOnly"] = sum(1 for r in rows if r.get("idType") == "name-only")
    parse["rowsScanned"] = len(rows)
    parse["rowsWithCid"] = sum(1 for r in rows if r.get("idType") == "rmi-cid")
    out["parse"] = parse
    out["ooglexAccess"] = {
        "mode": "preview",
        "ratio": RATIO,
        "visibleEdges": len(rows),
        "fullEdges": len(full_rows),
    }
    return out


def build_supply_chain() -> None:
    src = load("apps/supply-chain/nodes.json")
    selected = top_market_cap_nodes(src.get("nodes") or [])
    symbols = {str(x.get("symbol") or "").upper() for x in selected if x.get("symbol")}

    preview = copy.deepcopy(src)
    preview["nodes"] = selected
    preview["ooglexAccess"] = {
        "mode": "preview",
        "ratio": RATIO,
        "selection": "top-market-cap",
        "visibleCompanies": len(selected),
        "fullCompanies": len(src.get("nodes") or []),
    }

    if isinstance(preview.get("edgeIndex"), dict):
        preview["edgeIndex"] = filter_symbol_map(preview["edgeIndex"], symbols)

    cov = preview.get("coverage")
    if isinstance(cov, dict):
        cov["previewRatio"] = RATIO
        cov["previewCompanies"] = len(selected)
        cov["fullNodesTotal"] = (src.get("coverage") or {}).get("nodesTotal", len(src.get("nodes") or []))
        if isinstance(cov.get("filingStatus"), dict):
            cov["filingStatus"] = filter_symbol_map(cov["filingStatus"], symbols)

    write("supply-chain/nodes.json", preview)

    for name in ("history", "peers"):
        p = ROOT / "apps" / "supply-chain" / f"{name}.json"
        if not p.exists():
            continue
        obj = json.loads(p.read_text(encoding="utf-8"))
        if isinstance(obj, dict):
            if isinstance(obj.get("companies"), dict):
                obj["companies"] = filter_symbol_map(obj["companies"], symbols)
            if isinstance(obj.get("bySymbol"), dict):
                obj["bySymbol"] = filter_symbol_map(obj["bySymbol"], symbols)
            obj["ooglexAccess"] = {"mode": "preview", "ratio": RATIO}
        write(f"supply-chain/{name}.json", obj)

    names_path = ROOT / "apps" / "supply-chain" / "names-zh.json"
    if names_path.exists():
        names = json.loads(names_path.read_text(encoding="utf-8"))
        if isinstance(names, dict) and isinstance(names.get("names"), dict):
            names["names"] = filter_symbol_map(names["names"], symbols)
            names["ooglexAccess"] = {"mode": "preview", "ratio": RATIO}
        write("supply-chain/names-zh.json", names)

    # Only visible sample companies get an edge shard, and every shard is itself
    # reduced to <=10%. This fixes the previous NVDA leak where 239/239 smelters
    # were public simply because NVDA happened to be in the company preview set.
    edge_index = src.get("edgeIndex") or {}
    written = 0
    for sym in sorted(symbols):
        meta = edge_index.get(sym) or edge_index.get(sym.upper())
        if not isinstance(meta, dict):
            continue
        rel = meta.get("file")
        if not rel:
            continue
        src_path = ROOT / "apps" / "supply-chain" / rel
        if not src_path.exists() or not src_path.is_file():
            continue
        obj = json.loads(src_path.read_text(encoding="utf-8"))
        write(f"supply-chain/{rel}", preview_edge_payload(obj))
        written += 1
    print(f"wrote {written} reduced preview edge shards")


def trim_series(value, start: int, total: int):
    if isinstance(value, list) and len(value) == total:
        return value[start:]
    if isinstance(value, dict):
        return {k: trim_series(v, start, total) for k, v in value.items()}
    return value


def build_macro_risk() -> None:
    data = load("apps/macro-radar/data.json")
    preview = copy.deepcopy(data)

    # All eight top-level regime cards remain visible in the original UI. The
    # paywall is applied to the page/deeper research layer, not by deleting seven
    # of eight headline cards. Detailed lower-page collections remain reduced.
    sigs = preview.get("signals") or []
    if isinstance(sigs, list):
        preview["signals"] = sigs

    muts = preview.get("mutations") or []
    if isinstance(muts, list):
        preview["mutations"] = muts[:count10(len(muts))]

    macro = preview.get("macro") or []
    if isinstance(macro, list):
        reduced = []
        for cat in macro:
            if not isinstance(cat, dict):
                continue
            c = copy.deepcopy(cat)
            rows = c.get("rows") or []
            if isinstance(rows, list):
                c["rows"] = rows[:count10(len(rows))]
            reduced.append(c)
        preview["macro"] = reduced

    preview["ooglexAccess"] = {
        "mode": "preview",
        "ratio": RATIO,
        "presentation": "page-paywall",
        "headlineSignalsVisible": len(preview.get("signals") or []),
    }
    write("macro-risk/data.json", preview)

    history = load("apps/macro-radar/history.json")
    if isinstance(history, dict) and isinstance(history.get("dates"), list):
        total = len(history["dates"])
        keep = count10(total)
        start = max(0, total - keep)
        history = trim_series(copy.deepcopy(history), start, total)
        history["ooglexAccess"] = {
            "mode": "preview",
            "ratio": RATIO,
            "visiblePoints": keep,
            "fullPoints": total,
        }
    write("macro-risk/history.json", history)


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True, exist_ok=True)
    build_supply_chain()
    build_macro_risk()


if __name__ == "__main__":
    main()
