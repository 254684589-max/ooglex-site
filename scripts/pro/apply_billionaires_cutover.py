#!/usr/bin/env python3
"""Apply Billionaires FREE/PRO cutover to an already-built .site artifact."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / ".site"
PREVIEW = ROOT / ".pro-build" / "rich-preview" / "billionaires" / "data.json"
TARGET = SITE / "apps" / "billionaires" / "data.json"
HTML = SITE / "apps" / "billionaires" / "index.html"

SNIPPET = """
<meta name="ooglex-pro-api" content="https://ooglex-pro-api.zlq6600e.workers.dev">
<script src="/assets/pro-access.js?v=5"></script>
<script src="/assets/pro-billionaires.js?v=2"></script>
"""


def main() -> None:
    if not SITE.exists():
        raise SystemExit(".site missing; run scripts/build_public_site.py first")
    if not PREVIEW.exists():
        raise SystemExit("billionaires preview missing; run build_billionaires_pro.py first")
    if not HTML.exists():
        raise SystemExit("billionaires index.html missing from .site")

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PREVIEW, TARGET)

    text = HTML.read_text(encoding="utf-8")
    if "/assets/pro-billionaires.js" not in text:
        if "</head>" not in text:
            raise SystemExit("cannot inject Billionaires PRO adapter: </head> missing")
        text = text.replace("</head>", SNIPPET + "</head>", 1)
        HTML.write_text(text, encoding="utf-8")

    preview = json.loads(TARGET.read_text(encoding="utf-8"))
    people = preview.get("people") or []
    access = preview.get("ooglexAccess") or {}
    if len(people) > 10 or access.get("mode") != "preview":
        raise SystemExit("Billionaires public artifact is not a Top 10 preview")

    print(f"Billionaires cutover ready: {len(people)} public rows; full dataset excluded from Pages artifact")


if __name__ == "__main__":
    main()
