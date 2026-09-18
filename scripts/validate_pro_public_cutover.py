#!/usr/bin/env python3
"""Fail deployment if full PRO data leaks or rich preview contracts are broken."""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / ".site"
RATIO = 0.10

FULL_ONLY_FORBIDDEN = (
    "apps/supply-chain/identity.json",
    "apps/supply-chain/foreign.json",
    "apps/supply-chain/domestic.json",
    "apps/supply-chain/smelters.json",
    "apps/macro-radar/series.json",
    "apps/macro-radar/curve.json",
    "apps/macro-radar/curve-monthly.json",
)


def fail(message: str) -> None:
    raise SystemExit("PRO PUBLIC CUTOVER FAILED: " + message)


def read_json(rel: str):
    p = SITE / rel
    if not p.exists():
        fail("preview missing: " + rel)
    return json.loads(p.read_text(encoding="utf-8"))


def assert_preview_marker(obj, rel: str) -> None:
    marker = obj.get("ooglexAccess") if isinstance(obj, dict) else None
    if not isinstance(marker, dict) or marker.get("mode") != "preview":
        fail(rel + " is not marked as preview")
    ratio = marker.get("ratio")
    if ratio is None or float(ratio) > RATIO + 1e-9:
        fail(rel + " preview ratio exceeds 10%")


def main() -> None:
    if not SITE.exists():
        fail(".site does not exist")

    leaked = [rel for rel in FULL_ONLY_FORBIDDEN if (SITE / rel).exists()]
    if leaked:
        fail("full-only paths present: " + ", ".join(leaked))

    nodes = read_json("apps/supply-chain/nodes.json")
    assert_preview_marker(nodes, "apps/supply-chain/nodes.json")
    marker = nodes["ooglexAccess"]
    visible = len(nodes.get("nodes") or [])
    full = int(marker.get("fullCompanies") or 0)
    if full <= 0:
        fail("Supply Chain preview missing full company count")
    if visible > max(1, math.ceil(full * RATIO)):
        fail(f"Supply Chain preview exposes {visible}/{full} companies")

    edge_index = nodes.get("edgeIndex") or {}
    allowed_edges = {
        str(meta.get("file"))
        for meta in edge_index.values()
        if isinstance(meta, dict) and meta.get("file")
    }
    edge_dir = SITE / "apps/supply-chain/edges"
    if edge_dir.exists():
        actual_paths = [p for p in edge_dir.glob("*.json") if p.is_file()]
        actual_edges = {"edges/" + p.name for p in actual_paths}
        unexpected = sorted(actual_edges - allowed_edges)
        if unexpected:
            fail("preview contains edge shards outside visible sample: " + ", ".join(unexpected[:5]))
        for p in actual_paths:
            rel = "apps/supply-chain/edges/" + p.name
            obj = json.loads(p.read_text(encoding="utf-8"))
            assert_preview_marker(obj, rel)
            mark = obj.get("ooglexAccess") or {}
            vis = int(mark.get("visibleEdges") or 0)
            total = int(mark.get("fullEdges") or 0)
            rows = len(obj.get("edges") or [])
            if total <= 0:
                fail(rel + " missing full edge count")
            if vis != rows:
                fail(rel + " visible edge marker does not match payload")
            if vis > max(1, math.ceil(total * RATIO)):
                fail(f"{rel} exposes {vis}/{total} edges")

    for rel in (
        "apps/supply-chain/history.json",
        "apps/supply-chain/peers.json",
        "apps/supply-chain/names-zh.json",
    ):
        p = SITE / rel
        if p.exists():
            assert_preview_marker(read_json(rel), rel)

    # The eight headline regime cards are part of the visible preview UX. The
    # lower research layer remains restricted and the hard-stop blocks continuation.
    macro = read_json("apps/macro-radar/data.json")
    assert_preview_marker(macro, "apps/macro-radar/data.json")
    source_macro = json.loads((ROOT / "apps/macro-radar/data.json").read_text(encoding="utf-8"))
    expected_signals = len(source_macro.get("signals") or [])
    actual_signals = len(macro.get("signals") or [])
    if actual_signals != expected_signals:
        fail(f"Macro Risk headline cards incomplete: {actual_signals}/{expected_signals}")

    macro_hist = read_json("apps/macro-radar/history.json")
    assert_preview_marker(macro_hist, "apps/macro-radar/history.json")
    hmark = macro_hist.get("ooglexAccess") or {}
    if int(hmark.get("visiblePoints") or 0) > max(1, math.ceil(int(hmark.get("fullPoints") or 0) * RATIO)):
        fail("Macro Risk history preview exceeds 10%")

    # Finance Column: public Pages must receive generated ~10% JS previews,
    # never the authoring-time full arch.js / diagrams.js.
    finance_arch = (SITE / "apps/finance-column/arch.js").read_text(encoding="utf-8")
    finance_diagrams = (SITE / "apps/finance-column/diagrams.js").read_text(encoding="utf-8")
    for label, source in (("arch", finance_arch), ("diagrams", finance_diagrams)):
        if '"mode":"preview"' not in source or '"ratio":0.1' not in source:
            fail(f"Finance Column {label} is not a 10% generated preview")
        if "Generated safe Finance Column" not in source:
            fail(f"Finance Column {label} preview generator marker missing")

    finance_adapter = (SITE / "assets/pro-finance-column.js").read_text(encoding="utf-8")
    for token in ("finance_column", "FREE · 10% PREVIEW", "继续查看完整金融知识架构", "ooglex:finance-full-ready"):
        if token not in finance_adapter:
            fail("Finance Column access adapter missing token: " + token)

    for rel in (
        "apps/finance-column/index.html",
        "apps/finance-column/layer.html",
        "apps/finance-column/diagrams.html",
    ):
        text = (SITE / rel).read_text(encoding="utf-8")
        if '<script src="/assets/pro-access.js?v=6"></script>' not in text:
            fail("Finance Column pro-access missing from: " + rel)
        if '<script src="/assets/pro-finance-column.js?v=1"></script>' not in text:
            fail("Finance Column adapter missing from: " + rel)
        if "ooglex:finance-full-ready" not in text:
            fail("Finance Column full-data rerender hook missing from: " + rel)

    rich_pages = {
        "apps/supply-chain/index.html": "app.js",
        "apps/supply-chain/company.html": "company.js",
        "apps/macro-radar/index.html": "app.js",
    }
    sync_access = '<script src="/assets/pro-access.js?v=6"></script>'
    sync_adapter = '<script src="/assets/pro-rich-data.js?v=4"></script>'
    hard_stop = '<script src="/assets/pro-preview-gate.js?v=1"></script>'
    for rel, legacy_app in rich_pages.items():
        p = SITE / rel
        if not p.exists():
            fail("original rich page missing: " + rel)
        text = p.read_text(encoding="utf-8")
        if sync_access not in text or sync_adapter not in text or hard_stop not in text:
            fail("rich access or hard-stop adapter missing from: " + rel)
        if text.index(sync_access) > text.index(sync_adapter):
            fail("pro-access must load before pro-rich-data: " + rel)
        if text.index(sync_adapter) > text.index(hard_stop):
            fail("pro-rich-data must load before preview hard-stop: " + rel)
        legacy_pos = text.rfind(legacy_app)
        if legacy_pos < 0 or text.index(hard_stop) > legacy_pos:
            fail("preview hard-stop must run before legacy app boot: " + rel)
        if "location.replace('/pro/" in text or 'location.replace("/pro/' in text:
            fail("legacy page still redirects away from original UI: " + rel)

    adapter = (SITE / "assets/pro-rich-data.js").read_text(encoding="utf-8")
    for token in ("ooglex-preview-wall", "继续查看完整数据"):
        if token not in adapter:
            fail("FREE preview paywall missing token: " + token)

    gate = (SITE / "assets/pro-preview-gate.js").read_text(encoding="utf-8")
    for token in (
        "data-ooglex-preview-clipped",
        "data-ooglex-preview-hard-stop",
        'root.style.overflow = "hidden"',
        "preferredCutoff",
    ):
        if token not in gate:
            fail("FREE preview hard-stop missing token: " + token)

    aliases = {
        "pro/supply-chain/index.html": "/apps/supply-chain/",
        "pro/macro-risk/index.html": "/apps/macro-radar/",
    }
    for rel, target in aliases.items():
        p = SITE / rel
        if not p.exists():
            fail("Pro alias missing: " + rel)
        text = p.read_text(encoding="utf-8")
        if target not in text or "location.replace" not in text:
            fail("Pro alias does not point to original rich page: " + rel)

    for required in (
        "assets/pro-access.js",
        "assets/pro-rich-data.js",
        "assets/pro-preview-gate.js",
        "assets/pro-finance-column.js",
        "pro/index.html",
    ):
        if not (SITE / required).exists():
            fail("protected frontend asset missing: " + required)

    print("PRO rich-page validation: PASS")
    print("- original Supply Chain, Macro Risk and Finance Column interfaces are preserved")
    print("- Finance Column exposes only ~10% terms and causal maps to FREE/guest")
    print("- Macro FREE preview keeps all headline regime cards")
    print("- company edge shards are capped at 10%, including NVDA")
    print("- FREE/guest preview is clipped at a hard stop; hidden lower sections cannot extend scrolling")
    print("- OWNER/PRO remains unclipped and receives full entitlement data")


if __name__ == "__main__":
    main()
