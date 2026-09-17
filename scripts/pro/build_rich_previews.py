#!/usr/bin/env python3
"""Build same-schema 10% previews for the original rich Supply Chain and Macro pages.

These outputs are intended for the public Pages artifact. They preserve the original
UI/data contracts while exposing only a deterministic subset. Full data continues
to live behind the entitlement Worker and private R2.
"""
from __future__ import annotations

import copy
import json
import math
import shutil
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
        # filingStatus is a per-symbol map and must not expose the other 90%.
        if isinstance(cov.get("filingStatus"), dict):
            cov["filingStatus"] = filter_symbol_map(cov["filingStatus"], symbols)

    write("supply-chain/nodes.json", preview)

    # History/peers preserve their original schema, filtering per-company maps where present.
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

    # Publish edge shards only for the visible 10% sample companies.
    edge_index = src.get("edgeIndex") or {}
    copied = 0
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
        dst = OUT / "supply-chain" / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src_path, dst)
        copied += 1
    print(f"copied {copied} preview edge shards")


def trim_series(value, start: int, total: int):
    if isinstance(value, list) and len(value) == total:
        return value[start:]
    if isinstance(value, dict):
        return {k: trim_series(v, start, total) for k, v in value.items()}
    return value


def build_macro_risk() -> None:
    data = load("apps/macro-radar/data.json")
    preview = copy.deepcopy(data)

    sigs = preview.get("signals") or []
    if isinstance(sigs, list):
        preview["signals"] = sigs[:count10(len(sigs))]

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

    preview["ooglexAccess"] = {"mode": "preview", "ratio": RATIO}
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
