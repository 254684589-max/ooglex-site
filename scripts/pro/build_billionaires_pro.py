#!/usr/bin/env python3
"""Build protected Ooglex Pro payloads for the Billionaires page.

Unregistered users receive only a ~10% same-schema preview at the legacy data.json path.
The complete dataset is wrapped into .pro-build/billionaires/full.json for private
R2 delivery through the entitlement Worker.
"""
from __future__ import annotations

import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".pro-build"
RATIO = 0.10


def load(rel: str):
    return json.loads((ROOT / rel).read_text(encoding="utf-8"))


def write(rel: str, obj) -> None:
    path = OUT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size:,} bytes)")


def build() -> None:
    src = load("apps/billionaires/data.json")
    people = [x for x in (src.get("people") or []) if isinstance(x, dict)]
    ordered = sorted(people, key=lambda x: (x.get("rank") is None, x.get("rank") or 10**9))
    visible_count = max(1, (len(ordered) + 9) // 10)
    visible = copy.deepcopy(ordered[:visible_count])

    public_preview = copy.deepcopy(src)
    public_preview["people"] = visible
    public_preview["ooglexAccess"] = {
        "mode": "preview",
        "presentation": "ratio-registration-gate",
        "ratio": RATIO,
        "visiblePeople": len(visible),
        "fullPeople": len(people),
        "registrationRequired": True,
    }

    api_preview = {
        "schemaVersion": 1,
        "product": "billionaires",
        "mode": "preview",
        "updatedAt": src.get("updatedAt"),
        "asOf": src.get("asOf"),
        "source": src.get("source"),
        "count": src.get("count", len(people)),
        "totalWorth": src.get("totalWorth"),
        "people": visible,
        "limits": {
            "ratio": RATIO,
            "visiblePeople": len(visible),
            "fullPeople": len(people),
            "fullSearch": False,
            "fullSorting": False,
            "registrationRequired": True,
        },
    }

    full = {
        "schemaVersion": 1,
        "product": "billionaires",
        "mode": "full",
        "data": src,
    }

    write("billionaires/preview.json", api_preview)
    write("billionaires/full.json", full)
    write("rich-preview/billionaires/data.json", public_preview)


if __name__ == "__main__":
    build()
