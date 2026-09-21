#!/usr/bin/env python3
"""
Build a deterministic review queue for the next Tech Leaders expansion stage.

Inputs:
- data/tech-leaders/issuer_master.csv
- apps/tech-leaders/leaders.json

Output:
- data/tech-leaders/executive_candidate_queue.csv
- data/tech-leaders/executive_candidate_queue.meta.json

This stage DOES NOT guess executives or X handles. It only:
1) de-duplicates issuers already represented in the live 110-person catalog;
2) assigns research priority;
3) creates a stable schema for subsequent current + former/retired leader/X verification.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


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
    vals = set()
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


def existing_matches(issuer: dict[str, str], leaders: list[dict[str, Any]]) -> list[dict[str, str]]:
    ticker = str(issuer.get("ticker") or "").strip().upper()
    ticker_vars = {ticker, ticker.replace(".", "-"), ticker.replace("-", ".")}
    company_tok = norm_token(issuer.get("company") or "")

    matches: list[dict[str, str]] = []
    for leader in leaders:
        by_ticker = bool(ticker_vars & leader_tickers(leader))
        by_company = False
        if company_tok:
            for tok in leader_company_tokens(leader):
                if tok == company_tok or (len(tok) >= 6 and (tok in company_tok or company_tok in tok)):
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
                "x_verified": "yes" if leader.get("x_identity_verified") is True else "no",
            }
        )
    return matches


def research_priority(rank: int, has_existing: bool) -> str:
    if has_existing:
        return "covered_existing"
    if rank <= 150:
        return "research_now"
    if rank <= 250:
        return "research_next"
    return "research_later"


def build_rows(issuers: list[dict[str, str]], leaders: list[dict[str, Any]]) -> list[dict[str, Any]]:
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
                "market_cap_usd": issuer["market_cap_usd"],
                "sector": issuer["sector"],
                "cik": issuer["cik"],
                "existing_catalog_match": "yes" if represented else "no",
                "existing_leader_ids": "|".join(m["id"] for m in matches),
                "existing_leader_names": "|".join(m["name"] for m in matches),
                "existing_x_handles": "|".join(m["handle"] for m in matches if m["handle"]),
                "research_priority": research_priority(rank, represented),
                "executive_name": "",
                "executive_role": "",
                "role_status": "existing" if represented else "pending",
                "role_source_url": "",
                "x_handle": "",
                "x_check_type": "",
                "x_identity_status": "existing" if represented else "pending",
                "x_identity_source_url": "",
                "x_activity_status": "",
                "x_last_activity_at": "",
                "recommended_categories": "",
                "sp500_member": "",
                "nasdaq100_member": "",
                "confidence": "existing" if represented else "",
                "review_status": "covered_existing" if represented else "needs_research",
                "review_notes": "",
            }
        )
    return out


FIELDS = [
    "priority_rank",
    "ticker",
    "company",
    "exchange",
    "market_cap_usd",
    "sector",
    "cik",
    "existing_catalog_match",
    "existing_leader_ids",
    "existing_leader_names",
    "existing_x_handles",
    "research_priority",
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


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)
    tmp.replace(path)


def write_meta(path: Path, rows: list[dict[str, Any]]) -> None:
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    covered = [r for r in rows if r["existing_catalog_match"] == "yes"]
    research_now = [r for r in rows if r["research_priority"] == "research_now"]
    by_exchange: dict[str, int] = {}
    by_sector: dict[str, int] = {}
    for r in research_now:
        by_exchange[r["exchange"]] = by_exchange.get(r["exchange"], 0) + 1
        sector = r["sector"] or "Unknown"
        by_sector[sector] = by_sector.get(sector, 0) + 1

    payload = {
        "schema_version": 1,
        "generated_at": now,
        "issuer_count": len(rows),
        "covered_existing_issuers": len(covered),
        "needs_research_issuers": len(rows) - len(covered),
        "research_now_count": len(research_now),
        "research_now_exchange_counts": dict(sorted(by_exchange.items())),
        "research_now_sector_counts": dict(sorted(by_sector.items(), key=lambda kv: (-kv[1], kv[0]))),
        "policy": {
            "current_roles": ["CEO", "Founder & CEO", "Co-founder & CEO", "Executive Chair", "President", "C-suite"],
            "legacy_roles": ["Former CEO", "Former Chair", "Former President", "Former C-suite", "Founder", "Retired Founder", "Founder Emeritus"],
            "eligibility_rule": "Current employment is not required. Former executives, former CEOs, retired founders and founder-emeritus figures may be admitted when the person-to-company relationship is verified, the personal X identity is verified, and the X account remains meaningfully active.",
            "identity_rule": "Do not infer identity from blue check alone; require authoritative company/role-history evidence plus X account ownership evidence.",
            "activity_rule": "Automatic approval requires meaningful public X activity within 180 days. Activity 181-365 days old is manual-review only; more than 365 days without meaningful activity is hold/exclude.",
            "multi_person_rule": "One issuer may contribute multiple leaders: current leadership plus notable former/retired leaders. De-duplicate by person/X handle, not by issuer.",
            "corporate_fallback": "Keep corporate-only X accounts out of the main personal-leader import batch.",
            "production_rule": "Candidate queue never changes apps/tech-leaders/leaders.json automatically.",
        },
        "next_stage": "Research current and legacy company leaders, populate verified company relationship + personal X identity/activity evidence, and allow multiple people per issuer.",
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--issuers", default="data/tech-leaders/issuer_master.csv")
    ap.add_argument("--leaders", default="apps/tech-leaders/leaders.json")
    ap.add_argument("--output", default="data/tech-leaders/executive_candidate_queue.csv")
    ap.add_argument("--meta", default="data/tech-leaders/executive_candidate_queue.meta.json")
    args = ap.parse_args()

    issuers = load_issuers(Path(args.issuers))
    leaders = load_leaders(Path(args.leaders))
    rows = build_rows(issuers, leaders)
    write_csv(Path(args.output), rows)
    write_meta(Path(args.meta), rows)

    covered = sum(r["existing_catalog_match"] == "yes" for r in rows)
    now_count = sum(r["research_priority"] == "research_now" for r in rows)
    print(json.dumps({
        "ok": True,
        "rows": len(rows),
        "covered_existing_issuers": covered,
        "needs_research_issuers": len(rows) - covered,
        "research_now_count": now_count,
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
