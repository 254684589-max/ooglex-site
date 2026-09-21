#!/usr/bin/env python3
"""
Build the first 150-row Tech Leaders research/review batch.

This is a REVIEW artifact, not a production import.
It classifies and prioritizes uncovered NYSE/Nasdaq issuers while preserving
empty executive/X evidence fields until they are actually verified.

Inputs:
  data/tech-leaders/executive_candidate_queue.csv

Outputs:
  data/tech-leaders/review_batch_150.csv
  data/tech-leaders/review_batch_150.json
  data/tech-leaders/review_batch_150.meta.json
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SECTOR_CATEGORY = {
    "科技": "科技",
    "通信服务": "通信服务",
    "金融": "金融",
    "工业": "工业",
    "医疗健康": "医疗",
    "能源": "能源",
    "公用事业": "能源",
    "可选消费": "消费零售",
    "必需消费": "消费零售",
    "房地产": "房地产",
    "原材料": "原材料",
}

STRATEGIC_TICKERS = {
    "AI": {"PLTR", "APP", "DDOG", "ADBE", "INTU", "CDNS"},
    "芯片": {"LRCX", "AMAT", "TXN", "KLAC", "ADI", "APH", "SNDK", "WDC"},
    "云计算": {"ORCL", "DDOG", "HPE", "EQIX"},
    "网络安全": {"FTNT"},
    "软件": {"ORCL", "PLTR", "ADBE", "INTU", "CDNS", "DDOG"},
    "航空航天": {"GE", "BA", "LMT", "RTX", "GD", "HWM"},
    "金融科技": {"V", "MA", "IBKR", "CME", "ICE"},
}

SECTOR_WEIGHT = {
    "科技": 12,
    "通信服务": 10,
    "金融": 9,
    "工业": 9,
    "医疗健康": 8,
    "能源": 8,
    "公用事业": 6,
    "可选消费": 7,
    "必需消费": 6,
    "房地产": 5,
    "原材料": 5,
}


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    if len(rows) < 250:
        raise RuntimeError(f"candidate queue unexpectedly small: {len(rows)}")
    return rows


def market_cap_bucket(value: str) -> str:
    try:
        v = int(value)
    except (TypeError, ValueError):
        return "unknown"
    if v >= 500_000_000_000:
        return "mega_500b_plus"
    if v >= 100_000_000_000:
        return "large_100_500b"
    if v >= 25_000_000_000:
        return "large_25_100b"
    if v >= 10_000_000_000:
        return "mid_10_25b"
    return "sub_10b"


def rank_points(rank: int) -> int:
    if rank <= 25:
        return 60
    if rank <= 50:
        return 54
    if rank <= 100:
        return 46
    if rank <= 150:
        return 38
    if rank <= 200:
        return 30
    if rank <= 250:
        return 22
    return 14


def cap_points(bucket: str) -> int:
    return {
        "mega_500b_plus": 16,
        "large_100_500b": 13,
        "large_25_100b": 10,
        "mid_10_25b": 7,
        "sub_10b": 4,
        "unknown": 0,
    }[bucket]


def tags_for(row: dict[str, str]) -> list[str]:
    ticker = row["ticker"].upper()
    tags = ["上市公司", row["exchange"]]
    sector_tag = SECTOR_CATEGORY.get(row["sector"])
    if sector_tag:
        tags.append(sector_tag)
    for tag, tickers in STRATEGIC_TICKERS.items():
        if ticker in tickers:
            tags.append(tag)
    # Keep deterministic order, no duplicates.
    seen: set[str] = set()
    out: list[str] = []
    for tag in tags:
        if tag and tag not in seen:
            seen.add(tag)
            out.append(tag)
    return out


def score_row(row: dict[str, str]) -> tuple[int, list[str], str]:
    rank = int(row["priority_rank"])
    bucket = market_cap_bucket(row["market_cap_usd"])
    tags = tags_for(row)
    score = rank_points(rank) + cap_points(bucket) + SECTOR_WEIGHT.get(row["sector"], 4)
    score += min(10, 2 * sum(tag in {"AI", "芯片", "云计算", "网络安全", "软件", "航空航天", "金融科技"} for tag in tags))
    score = min(100, score)
    return score, tags, bucket


def review_tier(score: int) -> str:
    if score >= 85:
        return "A"
    if score >= 70:
        return "B"
    return "C"


OUT_FIELDS = [
    "batch_rank",
    "research_score",
    "review_tier",
    "priority_rank",
    "ticker",
    "company",
    "exchange",
    "market_cap_usd",
    "market_cap_bucket",
    "sector",
    "recommended_categories",
    "cik",
    "source_research_priority",
    "executive_name",
    "executive_role",
    "role_status",
    "role_source_url",
    "x_handle",
    "x_check_type",
    "x_identity_status",
    "x_identity_source_url",
    "x_activity_status",
    "x_last_activity_at",
    "sp500_member",
    "nasdaq100_member",
    "confidence",
    "review_status",
    "review_notes",
]


def build_batch(rows: list[dict[str, str]], limit: int) -> list[dict[str, Any]]:
    uncovered = [r for r in rows if r["existing_catalog_match"] == "no"]
    enriched: list[dict[str, Any]] = []
    for row in uncovered:
        score, tags, bucket = score_row(row)
        enriched.append({
            "research_score": score,
            "review_tier": review_tier(score),
            "market_cap_bucket": bucket,
            "recommended_categories": "|".join(tags),
            **row,
        })

    priority_order = {"research_now": 0, "research_next": 1, "research_later": 2}
    enriched.sort(
        key=lambda r: (
            priority_order.get(r["research_priority"], 9),
            -int(r["research_score"]),
            int(r["priority_rank"]),
            r["ticker"],
        )
    )

    batch = enriched[:limit]
    for idx, row in enumerate(batch, start=1):
        row["batch_rank"] = idx
        row["source_research_priority"] = row["research_priority"]
        # Keep evidence fields honest. No auto-promotion.
        if row.get("review_status") == "needs_research":
            row["review_status"] = "needs_research"
        row.pop("research_priority", None)
        for key in OUT_FIELDS:
            row.setdefault(key, "")
    return batch


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=OUT_FIELDS, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in OUT_FIELDS})
    tmp.replace(path)


def write_json(path: Path, rows: list[dict[str, Any]]) -> None:
    payload = {
        "schema_version": 1,
        "status": "review_only",
        "count": len(rows),
        "candidates": [{k: r.get(k, "") for k in OUT_FIELDS} for r in rows],
    }
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def write_meta(path: Path, rows: list[dict[str, Any]]) -> None:
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    exchange = Counter(r["exchange"] for r in rows)
    sector = Counter(r["sector"] for r in rows)
    tiers = Counter(r["review_tier"] for r in rows)
    tags = Counter()
    for r in rows:
        tags.update(filter(None, r["recommended_categories"].split("|")))

    payload = {
        "schema_version": 1,
        "generated_at": now,
        "status": "review_only",
        "count": len(rows),
        "exchange_counts": dict(sorted(exchange.items())),
        "sector_counts": dict(sorted(sector.items(), key=lambda kv: (-kv[1], kv[0]))),
        "review_tier_counts": dict(sorted(tiers.items())),
        "category_counts": dict(sorted(tags.items(), key=lambda kv: (-kv[1], kv[0]))),
        "rules": {
            "no_existing_catalog_matches": True,
            "no_auto_verified_x": True,
            "no_auto_role_verification": True,
            "production_file_untouched": "apps/tech-leaders/leaders.json",
            "purpose": "Human research/review ordering only.",
        },
        "next_stage": "Populate role/X evidence, then create leaders-v250-preview.json from approved candidates only.",
    }
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default="data/tech-leaders/executive_candidate_queue.csv")
    ap.add_argument("--limit", type=int, default=150)
    ap.add_argument("--csv", default="data/tech-leaders/review_batch_150.csv")
    ap.add_argument("--json", default="data/tech-leaders/review_batch_150.json")
    ap.add_argument("--meta", default="data/tech-leaders/review_batch_150.meta.json")
    args = ap.parse_args()

    if args.limit != 150:
        raise SystemExit("this first review batch is intentionally fixed at 150")

    rows = read_rows(Path(args.input))
    batch = build_batch(rows, args.limit)
    if len(batch) != 150:
        raise RuntimeError(f"expected 150 candidates, got {len(batch)}")

    write_csv(Path(args.csv), batch)
    write_json(Path(args.json), batch)
    write_meta(Path(args.meta), batch)

    print(json.dumps({
        "ok": True,
        "count": len(batch),
        "top10": [
            {
                "batch_rank": r["batch_rank"],
                "ticker": r["ticker"],
                "company": r["company"],
                "score": r["research_score"],
                "tier": r["review_tier"],
                "categories": r["recommended_categories"],
            }
            for r in batch[:10]
        ],
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
