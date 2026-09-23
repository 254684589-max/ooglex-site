#!/usr/bin/env python3
"""Build the deployable Ooglex public site into .site/.

Production keeps the original rich Supply Chain and Macro Risk interfaces. Guest
and FREE users receive same-schema ~10% preview datasets at the legacy paths;
OWNER/PRO requests are intercepted in-browser and fulfilled through the protected
Worker/private R2 full bundle. Finance Column terms and causal maps use the same
preview/full split.
"""
from __future__ import annotations

import argparse
import binascii
import copy
import json
import shutil
import struct
import zlib
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
    "apps/finance-column/arch.js",
    "apps/finance-column/diagrams.js",
    "apps/whats-latest/data.json",
}

# 公开金融终端（FREE 页）一直在读美债收益率曲线：US RATES 面板、收益率曲线面板、
# 品类行情的债券品类、11 个期限的详情页，以及数据来源表里的「美债曲线」那一行。
# PRO 切分把整份 curve.json 从公开产物里删掉后，这些地方全部 404。
# 现在改成给它一个「只留当前期限结构、不含任何历史序列」的公开替身：
# 当期读数本来就是 FRED/美国财政部 H.15 的公开数据，而逐日历史与利差历史
# 仍然只在受保护的完整文件里，走 PRO 通道。
PREVIEW_REPLACEMENTS = {
    "apps/supply-chain/nodes.json",
    "apps/supply-chain/peers.json",
    "apps/supply-chain/history.json",
    "apps/supply-chain/names-zh.json",
    "apps/supply-chain/edges",
    "apps/macro-radar/data.json",
    "apps/macro-radar/history.json",
    "apps/macro-radar/curve.json",
    "apps/finance-column/arch.js",
    "apps/finance-column/diagrams.js",
    "apps/whats-latest/data.json",
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
    relative = rel(path)
    if protect_pro and relative.startswith("apps/tech-leaders/") and path.suffix.lower() == ".json":
        return True
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


def install_public_curve_snapshot() -> None:
    """把当前期限结构写成公开替身，历史序列一律不带出去。

    与 data.json / history.json 的预览替身同一套机制，只是这里不按比例抽样：
    「当前形态」要么完整要么没有，抽样会让曲线变形。因此保留全部期限的当期读数
    与当期利差，删掉 history（11 期限 × 260 天）与利差的逐日序列。
    """
    src = ROOT / "apps" / "macro-radar" / "curve.json"
    if not src.exists():
        raise SystemExit("missing source for public curve snapshot: apps/macro-radar/curve.json")
    obj = json.loads(src.read_text(encoding="utf-8"))

    tenors = []
    for row in obj.get("tenors") or []:
        if isinstance(row, dict):
            tenors.append({k: row.get(k) for k in
                           ("id", "label", "months", "value", "asOf", "current") if k in row})
    spreads = []
    for row in obj.get("spreads") or []:
        if isinstance(row, dict):
            spreads.append({k: row.get(k) for k in
                            ("id", "label", "long", "short", "value", "asOf", "inverted")
                            if k in row})

    snapshot = {
        "updatedAt": obj.get("updatedAt"),
        "asOf": obj.get("asOf"),
        "source": obj.get("source"),
        "sourceUrl": obj.get("sourceUrl"),
        "frequency": obj.get("frequency") or "daily",
        "status": obj.get("status") or "ok",
        "note": (str(obj.get("note") or "")
                 + "（公开站点只提供当期期限结构与当期利差，不含逐日历史序列；"
                   "历史序列属受保护研究数据，页面在需要历史的视图上明确说明，不以空白或推断值代替。）"),
        "tenors": tenors,
        "spreads": spreads,
        "ooglexAccess": {
            "mode": "preview",
            "ratio": 0,
            "historyIncluded": False,
            "visibleTenors": len(tenors),
            "fullTenors": len(obj.get("tenors") or []),
        },
    }
    dst = OUT / "apps" / "macro-radar" / "curve.json"
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def install_rich_public_previews() -> None:
    copy_tree(RICH_PREVIEW / "supply-chain", OUT / "apps" / "supply-chain")
    copy_tree(RICH_PREVIEW / "macro-risk", OUT / "apps" / "macro-radar")
    copy_tree(RICH_PREVIEW / "finance-column", OUT / "apps" / "finance-column")


def install_whats_latest_preview() -> None:
    """Publish only ~10% of What's Latest content to the public Pages artifact."""
    src = ROOT / "apps" / "whats-latest" / "data.json"
    dst = OUT / "apps" / "whats-latest" / "data.json"
    if not src.exists():
        raise SystemExit("What's Latest full dataset missing")

    data = json.loads(src.read_text(encoding="utf-8"))
    categories = data.get("categories") or []
    flat = []
    for category in categories:
        for item in category.get("items") or []:
            row = copy.deepcopy(item)
            row["_categoryKey"] = category.get("key")
            row["_categoryName"] = category.get("name")
            flat.append(row)

    total = len(flat)
    if total <= 0:
        raise SystemExit("What's Latest dataset has no news items")

    # Round to the nearest whole article. Current 49-item dataset => 5 public items.
    visible_target = max(1, int(total * 0.10 + 0.5))

    def key(item: dict) -> str:
        return str(item.get("link") or item.get("title") or "")

    selected = []
    selected_keys = set()

    def add_item(item: dict | None) -> None:
        if not item or len(selected) >= visible_target:
            return
        k = key(item)
        if not k or k in selected_keys:
            return
        selected.append(copy.deepcopy(item))
        selected_keys.add(k)

    # Keep the edition lead, then preserve representative high-value desks.
    lead = data.get("lead") or data.get("highlight") or {}
    lead_key = key(lead)
    if lead_key:
        for item in flat:
            if key(item) == lead_key:
                add_item(item)
                break

    by_cat = {}
    for item in flat:
        by_cat.setdefault(item.get("_categoryKey"), []).append(item)
    for items in by_cat.values():
        items.sort(key=lambda x: float(x.get("published") or 0), reverse=True)

    for category_key in ("risk", "markets", "tech", "world", "politics", "law"):
        if len(selected) >= visible_target:
            break
        items = by_cat.get(category_key) or []
        if items:
            add_item(items[0])

    for item in sorted(flat, key=lambda x: float(x.get("published") or 0), reverse=True):
        if len(selected) >= visible_target:
            break
        add_item(item)

    # Remove helper keys from public objects.
    selected_clean = []
    selected_by_key = {}
    for item in selected:
        item = copy.deepcopy(item)
        category_key = item.pop("_categoryKey", None)
        category_name = item.pop("_categoryName", None)
        item["categoryKey"] = item.get("categoryKey") or category_key
        item["category"] = item.get("category") or category_name
        selected_clean.append(item)
        selected_by_key[key(item)] = item

    preview = copy.deepcopy(data)
    preview_categories = []
    for category in categories:
        c = copy.deepcopy(category)
        c["items"] = [
            selected_by_key[key(item)]
            for item in category.get("items") or []
            if key(item) in selected_by_key
        ]
        preview_categories.append(c)
    preview["categories"] = preview_categories

    primary = selected_clean[0] if selected_clean else {}
    preview["lead"] = copy.deepcopy(primary)
    preview["highlight"] = copy.deepcopy(primary)
    preview["wires"] = copy.deepcopy(selected_clean[1:])
    preview["alsoNoted"] = copy.deepcopy(selected_clean[-2:] if len(selected_clean) > 2 else [])
    preview["watch"] = []

    overview = []
    seen_cats = set()
    for item in selected_clean:
        cat = item.get("category") or ""
        if not cat or cat in seen_cats:
            continue
        seen_cats.add(cat)
        overview.append({
            "topic": cat,
            "text": item.get("briefZh") or item.get("titleZh") or "最新进展",
            "source": item.get("source") or "",
            "sourceZh": item.get("sourceZh") or "",
        })
    preview["overview"] = overview

    # Supporting market/trend widgets are also reduced instead of leaking the full panel.
    preview["markets"] = copy.deepcopy((data.get("markets") or [])[:1])
    preview["signals"] = copy.deepcopy((data.get("signals") or [])[:1])

    visible_risk = [
        item for item in selected_clean
        if item.get("categoryKey") == "risk"
    ]
    risk_sources = {item.get("source") for item in visible_risk if item.get("source")}
    risk_streams = {item.get("riskStream") for item in visible_risk if item.get("riskStream")}
    preview["riskAnalysis"] = {
        "version": "preview-10pct",
        "level": "预览",
        "status": "公开版",
        "reliable": False,
        "lead": copy.deepcopy(visible_risk[0]) if visible_risk else None,
        "why": "公开页面仅展示约10%的风险事件；完整风险样本未发布到公共页面。",
        "dimensions": [],
        "followUp": [],
        "coverage": {
            "sampleCount": len(visible_risk),
            "sourceCount": len(risk_sources),
            "streamCount": len(risk_streams),
            "minItems": 8,
            "minSources": 3,
            "minStreams": 3,
        },
        "method": "public-10-percent-preview",
    }

    preview["preview"] = {
        "enabled": True,
        "ratio": 0.10,
        "visibleItems": len(selected_clean),
        "totalItems": total,
        "mode": "public",
    }
    base_note = str(preview.get("note") or "").strip()
    preview["note"] = (
        (base_note + " " if base_note else "")
        + f"公开页面仅发布约10%新闻内容（{len(selected_clean)}/{total} 条）；完整数据不随 Pages 公共产物发布。"
    )

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(json.dumps(preview, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"What's Latest public preview: {len(selected_clean)}/{total} news items")


def inject_rich_access_adapter() -> None:
    """Keep original HTML/UI and install entitlement interception before app.js."""
    snippet = (
        '\n<meta name="ooglex-pro-api" content="https://pro-api.ooglex.com">\n'
        '<script src="/assets/pro-access.js?v=6"></script>\n'
        '<script src="/assets/pro-rich-data.js?v=4"></script>\n'
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

    finance_snippet = (
        '\n<meta name="ooglex-pro-api" content="https://pro-api.ooglex.com">\n'
        '<script src="/assets/pro-access.js?v=6"></script>\n'
        '<script src="/assets/pro-finance-column.js?v=2"></script>\n'
    )
    for relpath in (
        "apps/finance-column/index.html",
        "apps/finance-column/layer.html",
        "apps/finance-column/diagrams.html",
    ):
        p = OUT / relpath
        if not p.exists():
            raise SystemExit(f"Finance Column page missing: {relpath}")
        text = p.read_text(encoding="utf-8")
        if "/assets/pro-finance-column.js" not in text:
            if "</head>" not in text:
                raise SystemExit(f"cannot inject Finance Column access adapter: {relpath}")
            text = text.replace("</head>", finance_snippet + "</head>", 1)
            p.write_text(text, encoding="utf-8")


def write_tech_leaders_share_cover() -> None:
    """Generate a stable static PNG for WeChat/Open Graph catalog sharing."""
    width = height = 512
    bg = (247, 247, 247)
    pixels = [list(bg) for _ in range(width * height)]

    def put(x: int, y: int, color: tuple[int, int, int]) -> None:
        if 0 <= x < width and 0 <= y < height:
            pixels[y * width + x] = list(color)

    def rect(x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
        for y in range(max(0, y0), min(height, y1)):
            base = y * width
            for x in range(max(0, x0), min(width, x1)):
                pixels[base + x] = list(color)

    def circle(cx: int, cy: int, radius: int, color: tuple[int, int, int]) -> None:
        r2 = radius * radius
        for y in range(max(0, cy - radius), min(height, cy + radius + 1)):
            dy = y - cy
            span = int((r2 - dy * dy) ** 0.5)
            for x in range(max(0, cx - span), min(width, cx + span + 1)):
                put(x, y, color)

    # Paper-like card.
    rect(18, 18, 494, 494, (248, 246, 242))
    rect(44, 50, 242, 58, (111, 107, 101))

    # Three public-leader portrait tokens.
    portrait_centers = ((118, 184), (214, 184), (310, 184))
    portrait_colors = ((35, 35, 37), (86, 92, 100), (149, 141, 132))
    for (cx, cy), tone in zip(portrait_centers, portrait_colors):
        circle(cx, cy, 50, (255, 255, 255))
        circle(cx, cy, 46, (218, 210, 201))
        circle(cx, cy, 42, (255, 255, 255))
        circle(cx, cy - 9, 15, tone)
        circle(cx, cy + 24, 27, tone)

    # Verification badge.
    circle(362, 218, 27, (255, 255, 255))
    circle(362, 218, 22, (29, 155, 240))
    for t in range(5):
        for x, y in ((351 + t, 218 + t), (356 + t, 223 - t), (361 + t, 218 - t), (366 + t, 213 - t)):
            put(x, y, (255, 255, 255))

    # Strong typographic-like bars that remain legible at tiny WeChat thumbnail size.
    rect(46, 286, 390, 324, (23, 23, 23))
    rect(48, 342, 344, 362, (23, 23, 23))
    rect(48, 402, 318, 413, (80, 84, 90))
    rect(48, 438, 280, 447, (120, 113, 105))

    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(pixels[y * width + x])

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)
        )

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    target = OUT / "assets" / "tech-leaders-share-v2.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(png)


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

    write_tech_leaders_share_cover()

    cname = OUT / "CNAME"
    if cname.exists():
        cname.unlink()

    schema = OUT / "account" / "schema.sql"
    if schema.exists():
        raise SystemExit("account/schema.sql leaked into public build")

    if protect_pro:
        install_rich_public_previews()
        install_whats_latest_preview()
        install_public_curve_snapshot()
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
