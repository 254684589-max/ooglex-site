#!/usr/bin/env python3
"""Build protected Ooglex payloads for the What's Latest section."""
from __future__ import annotations

import copy
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".pro-build" / "whats-latest"
RATIO = 0.10


def write(name: str, obj) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    path.write_text(json.dumps(obj, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size:,} bytes)")


def item_key(item: dict) -> str:
    return str(item.get("link") or item.get("title") or item.get("titleZh") or "")


def make_preview(src: dict) -> dict:
    categories = src.get("categories") or []
    flat = []
    for category in categories:
        for item in category.get("items") or []:
            row = copy.deepcopy(item)
            row["_categoryKey"] = category.get("key")
            flat.append(row)

    if not flat:
        raise SystemExit("What's Latest dataset has no items")

    target = max(1, math.ceil(len(flat) * RATIO))
    selected = []
    seen = set()
    for i in range(target):
        idx = min(len(flat) - 1, math.floor(i * len(flat) / target))
        row = copy.deepcopy(flat[idx])
        key = item_key(row)
        if key and key not in seen:
            seen.add(key)
            selected.append(row)

    # Fill rare duplicate slots deterministically.
    if len(selected) < target:
        for row in flat:
            key = item_key(row)
            if key and key not in seen:
                seen.add(key)
                selected.append(copy.deepcopy(row))
                if len(selected) >= target:
                    break

    selected_by_key = {}
    for row in selected:
        row.pop("_categoryKey", None)
        selected_by_key[item_key(row)] = row

    preview = copy.deepcopy(src)
    preview_categories = []
    for category in categories:
        c = copy.deepcopy(category)
        c["items"] = [
            selected_by_key[item_key(item)]
            for item in category.get("items") or []
            if item_key(item) in selected_by_key
        ]
        preview_categories.append(c)
    preview["categories"] = preview_categories

    chosen = list(selected_by_key.values())
    primary = copy.deepcopy(chosen[0]) if chosen else {}
    preview["lead"] = primary
    preview["highlight"] = copy.deepcopy(primary)
    preview["wires"] = copy.deepcopy(chosen[1:])
    preview["alsoNoted"] = copy.deepcopy(chosen[-2:] if len(chosen) > 2 else [])
    preview["watch"] = []
    preview["markets"] = copy.deepcopy((src.get("markets") or [])[:1])
    preview["signals"] = copy.deepcopy((src.get("signals") or [])[:1])
    preview["preview"] = {
        "enabled": True,
        "ratio": RATIO,
        "visibleItems": len(chosen),
        "totalItems": len(flat),
        "registrationRequired": True,
    }
    return preview


def main() -> None:
    src = json.loads((ROOT / "apps/whats-latest/data.json").read_text(encoding="utf-8"))
    preview = make_preview(src)
    write("preview.json", {
        "schemaVersion": 1,
        "product": "whats_latest",
        "mode": "preview",
        "data": preview,
    })
    write("full.json", {
        "schemaVersion": 1,
        "product": "whats_latest",
        "mode": "full",
        "data": src,
    })


if __name__ == "__main__":
    main()
