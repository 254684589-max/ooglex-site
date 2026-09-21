#!/usr/bin/env python3
"""Build the first Tech Leaders V1.1 research batch.

The batch is issuer-led research, but explicitly multi-person: represented
companies stay eligible so additional founders, former CEOs and other active
legacy leaders can be discovered. No role or X identity is auto-verified.
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
    if rank <= 300:
        return 30
    if rank <= 650:
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


def proxy_points(row: dict[str, str]) -> int:
    low = (row.get("filer_category") or "").lower()
    if "large accelerated" in low:
        return 10
    if "accelerated" in low and "non-accelerated" not in low:
        return 6
    if "non-accelerated" in low:
        return 3
    return 0


def tags_for(row: dict[str, str]) -> list[str]:
    ticker = row["ticker"].upper()
    tags = ["上市公司", row["exchange"]]
    sector_tag = SECTOR_CATEGORY.get(row.get("sector", ""))
    if sector_tag:
        tags.append(sector_tag)
    for tag, tickers in STRATEGIC_TICKERS.items():
        if ticker in tickers:
            tags.append(tag)
    seen: set[str] = set()
    out: list[str] = []
    for tag in tags:
        if tag and tag not in seen:
            seen.add(tag)
            out.append(tag)
    return out


def score_row(row: dict[str, str]) -> tuple[int, list[str], str]:
    rank = int(row["priority_rank"])
    bucket = market_cap_bucket(row.get("market_cap_usd", ""))
    tags = tags_for(row)
    score = rank_points(rank) + cap_points(bucket)
    score += proxy_points(row)
    score += SECTOR_WEIGHT.get(row.get("sector", ""), 4)
    score += min(
        10,
        2
        * sum(
            tag
            in {
                "AI",
                "芯片",
                "云计算",
                "网络安全",
                "软件",
                "航空航天",
                "金融科技",
            }
            for tag in tags
        ),
    )
    if row.get("existing_catalog_match") == "yes":
        score += 3
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
    "priority_method",
    "filer_category",
    "last_annual",
    "recommended_categories",
    "cik",
    "existing_catalog_match",
    "existing_leader_count",
    "existing_leader_names",
    "existing_x_handles",
    "source_research_priority",
    "discovery_mode",
    "target_roles",
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
    enriched: list[dict[str, Any]] = []
    for row in rows:
        score, tags, bucket = score_row(row)
        enriched.append(
            {
                **row,
                "research_score": score,
                "review_tier": review_tier(score),
                "market_cap_bucket": bucket,
                "recommended_categories": "|".join(tags),
            }
        )

    priority_order = {
        "research_now": 0,
        "research_next": 1,
        "research_later": 2,
    }
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
        "schema_version": 2,
        "status": "review_only",
        "mode": "multi_person_current_and_legacy",
        "count": len(rows),
        "candidates": [{k: r.get(k, "") for k in OUT_FIELDS} for r in rows],
    }
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def write_meta(path: Path, rows: list[dict[str, Any]]) -> None:
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    exchange = Counter(r["exchange"] for r in rows)
    sector = Counter(r.get("sector") or "Unknown" for r in rows)
    tiers = Counter(r["review_tier"] for r in rows)
    tags = Counter()
    for r in rows:
        tags.update(filter(None, r["recommended_categories"].split("|")))

    payload = {
        "schema_version": 2,
        "generated_at": now,
        "status": "review_only",
        "mode": "multi_person_current_and_legacy",
        "count": len(rows),
        "existing_issuer_rows": sum(
            1 for r in rows if r.get("existing_catalog_match") == "yes"
        ),
        "exchange_counts": dict(sorted(exchange.items())),
        "sector_counts": dict(sorted(sector.items(), key=lambda kv: (-kv[1], kv[0]))),
        "review_tier_counts": dict(sorted(tiers.items())),
        "category_counts": dict(sorted(tags.items(), key=lambda kv: (-kv[1], kv[0]))),
        "rules": {
            "existing_catalog_matches_are_eligible": True,
            "multi_person_per_issuer": True,
            "legacy_leaders_allowed": True,
            "no_auto_verified_x": True,
            "no_auto_role_verification": True,
            "production_file_untouched": "apps/tech-leaders/leaders.json",
        },
        "next_stage": "Resolve named people for each issuer/role target, verify role history + personal X identity + activity, then create leaders-v250-preview.json from approved people only.",
    }
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--input",
        default="data/tech-leaders/executive_candidate_queue.csv",
    )
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

    print(
        json.dumps(
            {
                "ok": True,
                "count": len(batch),
                "existing_issuer_rows": sum(
                    r.get("existing_catalog_match") == "yes" for r in batch
                ),
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
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
