#!/usr/bin/env python3
"""Build the Tech Leaders V1.1 multi-person research queue.

Unlike the old pilot, an issuer is NOT considered complete merely because one
leader is already present in leaders.json. Existing leaders are retained as
seeds, while every issuer can still contribute additional current, former or
retired leaders.

The queue remains research-only: it never guesses X handles and never mutates
apps/tech-leaders/leaders.json.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

TARGET_ROLES = [
    "CEO",
    "Founder & CEO",
    "Co-founder & CEO",
    "Founder",
    "Co-founder",
    "Executive Chair",
    "President",
    "C-suite",
    "Former CEO",
    "Former Chair",
    "Former President",
    "Former C-suite",
    "Retired Founder",
    "Founder Emeritus",
]


def norm_token(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", (value or "").lower())


def leader_tickers(leader: dict[str, Any]) -> set[str]:
    vals: set[str] = set()
    for key in ("ticker", "sp500_ticker"):
        v = str(leader.get(key) or "").strip().upper()
        if v:
            vals.add(v)
            vals.add(v.replace(".", "-"))
            vals.add(v.replace("-", "."))
    for chip in leader.get("chips") or []:
        v = str(chip or "").strip().upper()
        if re.fullmatch(r"[A-Z]{1,6}(?:[-.][A-Z])?", v):
            vals.add(v)
            vals.add(v.replace(".", "-"))
            vals.add(v.replace("-", "."))
    return vals


def leader_company_tokens(leader: dict[str, Any]) -> set[str]:
    vals: set[str] = set()
    for key in ("company_en", "company_zh", "role"):
        raw = str(leader.get(key) or "")
        for part in re.split(r"[/·|,&()]+", raw):
            tok = norm_token(part)
            if len(tok) >= 4:
                vals.add(tok)
    return vals


def load_leaders(path: Path) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    rows = payload.get("leaders") or []
    if not isinstance(rows, list) or len(rows) < 50:
        raise RuntimeError(f"leaders catalog unexpectedly small: {len(rows)}")
    return rows


def load_issuers(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    if len(rows) < 250:
        raise RuntimeError(f"issuer universe unexpectedly small: {len(rows)}")
    return rows


def existing_matches(
    issuer: dict[str, str],
    leaders: list[dict[str, Any]],
) -> list[dict[str, str]]:
    ticker = str(issuer.get("ticker") or "").strip().upper()
    ticker_vars = {ticker, ticker.replace(".", "-"), ticker.replace("-", ".")}
    company_tok = norm_token(issuer.get("company") or "")

    matches: list[dict[str, str]] = []
    for leader in leaders:
        by_ticker = bool(ticker_vars & leader_tickers(leader))
        by_company = False
        if company_tok:
            for tok in leader_company_tokens(leader):
                if tok == company_tok or (
                    len(tok) >= 6 and (tok in company_tok or company_tok in tok)
                ):
                    by_company = True
                    break
        if not (by_ticker or by_company):
            continue

        matches.append(
            {
                "id": str(leader.get("id") or ""),
                "name": str(leader.get("name_en") or leader.get("name") or ""),
                "handle": str(leader.get("handle") or ""),
                "role": str(leader.get("position_zh") or leader.get("role") or ""),
            }
        )
    return matches


def research_priority(rank: int) -> str:
    if rank <= 300:
        return "research_now"
    if rank <= 650:
        return "research_next"
    return "research_later"


FIELDS = [
    "priority_rank",
    "ticker",
    "company",
    "exchange",
    "market_cap_usd",
    "sector",
    "cik",
    "priority_method",
    "filer_category",
    "last_annual",
    "existing_catalog_match",
    "existing_leader_count",
    "existing_leader_ids",
    "existing_leader_names",
    "existing_x_handles",
    "research_priority",
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
    "recommended_categories",
    "sp500_member",
    "nasdaq100_member",
    "confidence",
    "review_status",
    "review_notes",
]


def build_rows(
    issuers: list[dict[str, str]],
    leaders: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for issuer in issuers:
        rank = int(issuer["priority_rank"])
        matches = existing_matches(issuer, leaders)
        represented = bool(matches)

        out.append(
            {
                "priority_rank": rank,
                "ticker": issuer["ticker"],
                "company": issuer["company"],
                "exchange": issuer["exchange"],
                "market_cap_usd": issuer.get("market_cap_usd", ""),
                "sector": issuer.get("sector", ""),
                "cik": issuer["cik"],
                "priority_method": issuer.get("priority_method", ""),
                "filer_category": issuer.get("filer_category", ""),
                "last_annual": issuer.get("last_annual", ""),
                "existing_catalog_match": "yes" if represented else "no",
                "existing_leader_count": len(matches),
                "existing_leader_ids": "|".join(m["id"] for m in matches),
                "existing_leader_names": "|".join(m["name"] for m in matches),
                "existing_x_handles": "|".join(
                    m["handle"] for m in matches if m["handle"]
                ),
                "research_priority": research_priority(rank),
                "discovery_mode": "multi_person_current_and_legacy",
                "target_roles": "|".join(TARGET_ROLES),
                "executive_name": "",
                "executive_role": "",
                "role_status": "",
                "role_source_url": "",
                "x_handle": "",
                "x_check_type": "",
                "x_identity_status": "",
                "x_identity_source_url": "",
                "x_activity_status": "",
                "x_last_activity_at": "",
                "recommended_categories": "",
                "sp500_member": "",
                "nasdaq100_member": "",
                "confidence": "",
                "review_status": "expand_existing" if represented else "needs_research",
                "review_notes": "",
            }
        )
    return out


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    tmp.replace(path)


def write_meta(path: Path, rows: list[dict[str, Any]]) -> None:
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    represented = [r for r in rows if r["existing_catalog_match"] == "yes"]
    research_now = [r for r in rows if r["research_priority"] == "research_now"]
    research_next = [r for r in rows if r["research_priority"] == "research_next"]

    by_exchange: dict[str, int] = {}
    by_method: dict[str, int] = {}
    for r in rows:
        by_exchange[r["exchange"]] = by_exchange.get(r["exchange"], 0) + 1
        method = r["priority_method"] or "unknown"
        by_method[method] = by_method.get(method, 0) + 1

    payload = {
        "schema_version": 2,
        "generated_at": now,
        "issuer_count": len(rows),
        "represented_issuers": len(represented),
        "unrepresented_issuers": len(rows) - len(represented),
        "research_now_count": len(research_now),
        "research_next_count": len(research_next),
        "research_later_count": len(rows) - len(research_now) - len(research_next),
        "research_now_existing_count": sum(
            1 for r in research_now if r["existing_catalog_match"] == "yes"
        ),
        "exchange_counts": dict(sorted(by_exchange.items())),
        "priority_method_counts": dict(sorted(by_method.items())),
        "policy": {
            "current_role_required": False,
            "legacy_leaders_allowed": True,
            "existing_issuer_considered_complete": False,
            "multi_person_per_issuer": True,
            "target_roles": TARGET_ROLES,
            "identity_rule": "Blue check is status only. Require authoritative role/company evidence plus personal X ownership evidence.",
            "activity_rule": "Meaningful public X activity <=180d may pass automatic activity gate; 181-365d requires manual review; >365d is hold/exclude unless exceptional.",
            "dedupe_rule": "Deduplicate people/X handles, not issuers.",
            "production_file_untouched": "apps/tech-leaders/leaders.json",
        },
        "next_stage": "Resolve each issuer into one or more named people, verify role history, personal X identity and activity, then build approved V250 preview.",
    }
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--issuers", default="data/tech-leaders/issuer_master.csv")
    ap.add_argument("--leaders", default="apps/tech-leaders/leaders.json")
    ap.add_argument(
        "--output",
        default="data/tech-leaders/executive_candidate_queue.csv",
    )
    ap.add_argument(
        "--meta",
        default="data/tech-leaders/executive_candidate_queue.meta.json",
    )
    args = ap.parse_args()

    issuers = load_issuers(Path(args.issuers))
    leaders = load_leaders(Path(args.leaders))
    rows = build_rows(issuers, leaders)
    write_csv(Path(args.output), rows)
    write_meta(Path(args.meta), rows)

    print(
        json.dumps(
            {
                "ok": True,
                "issuers": len(rows),
                "represented": sum(
                    r["existing_catalog_match"] == "yes" for r in rows
                ),
                "research_now": sum(
                    r["research_priority"] == "research_now" for r in rows
                ),
                "mode": "multi_person_current_and_legacy",
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
