#!/usr/bin/env python3
"""Expand the 150-company Tech Leaders review batch into person-level research slots.

Each issuer gets three parallel discovery tracks:
1) current_primary: current CEO / President / Executive Chair / C-suite;
2) founder_legacy: founder / co-founder / retired founder / founder emeritus;
3) former_executive: former CEO / chair / president / C-suite.

Existing production leaders and previously reviewed evidence are attached as
known people, but they do not close the issuer. This artifact is research-only
and never writes apps/tech-leaders/leaders.json.
"""

from __future__ import annotations

import argparse
import glob
import json
from pathlib import Path
from typing import Any

SLOTS = [
    {
        "slot_type": "current_primary",
        "target_roles": [
            "CEO",
            "Founder & CEO",
            "Co-founder & CEO",
            "Executive Chair",
            "President",
            "C-suite",
        ],
    },
    {
        "slot_type": "founder_legacy",
        "target_roles": [
            "Founder",
            "Co-founder",
            "Retired Founder",
            "Founder Emeritus",
        ],
    },
    {
        "slot_type": "former_executive",
        "target_roles": [
            "Former CEO",
            "Former Chair",
            "Former President",
            "Former C-suite",
        ],
    },
]


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def classify_existing(leader: dict[str, Any]) -> set[str]:
    out: set[str] = set()
    types = {str(x).lower() for x in leader.get("leader_types") or []}
    status = str(leader.get("company_relationship_status") or "").lower()
    role = str(leader.get("role") or leader.get("position_zh") or "").lower()

    if "ceo" in types or status == "current" or any(
        token in role for token in ("ceo", "chief executive", "president", "chair")
    ):
        out.add("current_primary")
    if "founder" in types or "founder" in role or "co-founder" in role:
        out.add("founder_legacy")
    if (
        "former_ceo" in types
        or "legacy_leader" in types
        or status in {"former", "retired", "founder_emeritus"}
        or any(token in role for token in ("former", "retired", "emeritus"))
    ):
        out.add("former_executive")
    return out


def classify_evidence(candidate: dict[str, Any]) -> set[str]:
    out: set[str] = set()
    status = str(candidate.get("role_status") or "").lower()
    role = str(candidate.get("executive_role") or "").lower()
    if status == "current":
        out.add("current_primary")
    if "founder" in role:
        out.add("founder_legacy")
    if status in {"former", "retired", "founder_emeritus"}:
        out.add("former_executive")
    return out


def ticker_for_leader(leader: dict[str, Any]) -> str:
    for key in ("ticker", "sp500_ticker"):
        value = str(leader.get(key) or "").strip().upper()
        if value:
            return value
    for chip in leader.get("chips") or []:
        value = str(chip or "").strip().upper()
        if value and 1 <= len(value) <= 7 and value.replace("-", "").replace(".", "").isalnum():
            return value
    return ""


def known_people(
    ticker: str,
    slot_type: str,
    leaders: list[dict[str, Any]],
    evidence: list[dict[str, Any]],
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    live: list[dict[str, str]] = []
    reviewed: list[dict[str, str]] = []

    for leader in leaders:
        if ticker_for_leader(leader) != ticker:
            continue
        if slot_type not in classify_existing(leader):
            continue
        live.append(
            {
                "name": str(leader.get("name_en") or leader.get("name") or ""),
                "handle": str(leader.get("handle") or ""),
                "status": str(leader.get("company_relationship_status") or "production"),
            }
        )

    for candidate in evidence:
        if str(candidate.get("ticker") or "").upper() != ticker:
            continue
        if slot_type not in classify_evidence(candidate):
            continue
        reviewed.append(
            {
                "name": str(candidate.get("executive_name") or ""),
                "handle": str(candidate.get("x_handle") or ""),
                "status": str(candidate.get("review_status") or ""),
            }
        )

    return live, reviewed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", default="data/tech-leaders/review_batch_150.json")
    ap.add_argument("--leaders", default="apps/tech-leaders/leaders.json")
    ap.add_argument(
        "--evidence-glob",
        default="data/tech-leaders/verified_candidates.tranche*.json",
    )
    ap.add_argument(
        "--output",
        default="data/tech-leaders/person_resolution_queue.json",
    )
    ap.add_argument(
        "--meta",
        default="data/tech-leaders/person_resolution_queue.meta.json",
    )
    args = ap.parse_args()

    batch = load_json(Path(args.batch))
    leaders = load_json(Path(args.leaders)).get("leaders") or []

    evidence: list[dict[str, Any]] = []
    evidence_paths = sorted(glob.glob(args.evidence_glob))
    for path in evidence_paths:
        evidence.extend(load_json(Path(path)).get("candidates") or [])

    companies = batch.get("candidates") or []
    if len(companies) != 150:
        raise RuntimeError(f"expected 150 review companies, got {len(companies)}")

    slots: list[dict[str, Any]] = []
    for row in companies:
        ticker = str(row.get("ticker") or "").upper()
        categories = [
            x for x in str(row.get("recommended_categories") or "").split("|") if x
        ]
        for spec in SLOTS:
            live, reviewed = known_people(
                ticker, spec["slot_type"], leaders, evidence
            )
            slots.append(
                {
                    "slot_id": f"{ticker}:{spec['slot_type']}",
                    "batch_rank": row.get("batch_rank"),
                    "research_score": row.get("research_score"),
                    "review_tier": row.get("review_tier"),
                    "ticker": ticker,
                    "company": row.get("company"),
                    "exchange": row.get("exchange"),
                    "categories": categories,
                    "slot_type": spec["slot_type"],
                    "target_roles": spec["target_roles"],
                    "known_production_people": live,
                    "known_reviewed_people": reviewed,
                    "resolution_status": (
                        "expand_more"
                        if live or reviewed
                        else "needs_person_discovery"
                    ),
                    "research_notes": "",
                }
            )

    counts: dict[str, int] = {}
    covered: dict[str, int] = {}
    for slot in slots:
        st = slot["slot_type"]
        counts[st] = counts.get(st, 0) + 1
        if slot["resolution_status"] == "expand_more":
            covered[st] = covered.get(st, 0) + 1

    payload = {
        "schema_version": 1,
        "status": "research_only",
        "mode": "multi_person_current_and_legacy",
        "source_batch": args.batch,
        "source_evidence": evidence_paths,
        "company_count": len(companies),
        "slot_count": len(slots),
        "slots": slots,
    }
    meta = {
        "schema_version": 1,
        "company_count": len(companies),
        "slot_count": len(slots),
        "slot_type_counts": counts,
        "slots_with_known_people": covered,
        "rules": {
            "three_parallel_tracks_per_company": True,
            "existing_people_do_not_close_company": True,
            "dedupe_by_person_and_handle": True,
            "production_file_untouched": "apps/tech-leaders/leaders.json",
        },
        "next_stage": (
            "Resolve names + role evidence + personal X identity + activity for "
            "needs_person_discovery slots; approved people flow into evidence tranches."
        ),
    }

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    Path(args.meta).write_text(
        json.dumps(meta, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(meta, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
