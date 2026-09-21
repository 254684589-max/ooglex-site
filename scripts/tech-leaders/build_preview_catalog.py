#!/usr/bin/env python3
"""
Build a non-production Tech Leaders preview catalog from approved evidence only.

This script never writes apps/tech-leaders/leaders.json.
"""

from __future__ import annotations

import argparse
import glob
import json
import re
from copy import deepcopy
from pathlib import Path
from typing import Any
from urllib.parse import quote_plus


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def slugify(value: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return s or "candidate"


def require_url(value: str, label: str) -> None:
    if not isinstance(value, str) or not value.startswith("https://"):
        raise RuntimeError(f"{label} must be an https URL")


def validate_candidate(c: dict[str, Any]) -> None:
    if c.get("review_status") != "approved":
        return
    required = [
        "ticker", "company", "exchange", "executive_name", "executive_role",
        "role_status", "role_source_url", "x_handle", "x_identity_status",
        "x_identity_source_url", "x_activity_status", "confidence",
    ]
    missing = [k for k in required if not c.get(k)]
    if missing:
        raise RuntimeError(f"approved candidate {c.get('ticker')} missing: {missing}")
    if c["role_status"] not in {"current", "former", "retired", "founder_emeritus"}:
        raise RuntimeError(
            f"approved candidate {c['ticker']} has unsupported role_status={c['role_status']!r}"
        )
    if c["x_identity_status"] != "verified":
        raise RuntimeError(f"approved candidate {c['ticker']} X identity is not verified")
    if c["x_activity_status"] not in {"active", "intermittent"}:
        raise RuntimeError(f"approved candidate {c['ticker']} lacks usable X activity")
    if c["role_status"] != "current" and not c.get("x_last_activity_at"):
        raise RuntimeError(
            f"legacy candidate {c['ticker']} requires x_last_activity_at to prove current activity"
        )
    require_url(c["role_source_url"], f"{c['ticker']} role_source_url")
    require_url(c["x_identity_source_url"], f"{c['ticker']} x_identity_source_url")


def make_leader(c: dict[str, Any]) -> dict[str, Any]:
    handle = c["x_handle"].lstrip("@")
    company = c["company"]
    name = c["executive_name"]
    role = c["executive_role"]
    cats = [x for x in c.get("recommended_categories") or [] if x not in {"上市公司", "NYSE", "NASDAQ"}]
    primary = cats[0] if cats else "软件"
    avatar = (
        "https://pro-api.ooglex.com/v1/tech-leaders/avatar?"
        f"handle={quote_plus(handle)}&name={quote_plus(name)}&company={quote_plus(company)}"
    )
    status = c.get("role_status") or "current"
    role_low = role.lower()
    leader_types = []
    if status == "current" and "ceo" in role_low:
        leader_types.append("ceo")
    if status != "current" and "ceo" in role_low:
        leader_types.append("former_ceo")
    if "founder" in role_low:
        leader_types.append("founder")
    if status in {"former", "retired", "founder_emeritus"}:
        leader_types.append("legacy_leader")
    if not leader_types:
        leader_types.append("executive")

    if status == "current":
        note = "美国上市公司现任核心高管；个人公开 X 账号已完成身份核验。预览候选，尚未上线。"
    elif status == "retired":
        note = "美国上市公司退休创始人或前核心高管；个人公开 X 账号已完成身份核验且保持活跃。预览候选，尚未上线。"
    else:
        note = "美国上市公司前任核心高管或创始人；个人公开 X 账号已完成身份核验且保持活跃。预览候选，尚未上线。"

    return {
        "id": slugify(name + "-" + c["ticker"]),
        "name": name,
        "zh": name,
        "handle": handle,
        "role": f"{company} · {role}",
        "chips": [c["ticker"], company] + cats[:3],
        "note": note,
        "title": f"{name.upper()} · VERIFIED X TIMELINE PREVIEW",
        "category": primary,
        "name_zh": name,
        "name_en": name,
        "company_zh": company,
        "company_en": company,
        "position_zh": role,
        "categories": cats,
        "ticker": c["ticker"],
        "exchange": c["exchange"],
        "listed_company": True,
        "admission_status": "preview_approved",
        "leader_types": leader_types,
        "company_relationship_status": status,
        "themes": cats,
        "x_identity_verified": True,
        "x_check_type": c.get("x_check_type") or "uncertain",
        "x_role_source_url": c["role_source_url"],
        "x_identity_source_url": c["x_identity_source_url"],
        "x_activity_status": c["x_activity_status"],
        "x_last_activity_at": c.get("x_last_activity_at") or "",
        "review_confidence": c["confidence"],
        "avatar_url": avatar,
        "avatar_source": "Ooglex avatar pipeline · pending preview audit",
        "avatar_status": "pending_preview_audit",
        "avatar_fallback": "local_initials_svg",
        "avatar_policy": "x_original_then_verified_fallback",
        "avatar_verified": False,
        "preview_only": True,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="apps/tech-leaders/leaders.json")
    ap.add_argument("--evidence-glob", default="data/tech-leaders/verified_candidates.tranche*.json")
    ap.add_argument("--output", default="data/tech-leaders/leaders-v250-preview.json")
    args = ap.parse_args()

    base = load_json(Path(args.base))
    evidence_paths = [Path(p) for p in sorted(glob.glob(args.evidence_glob))]
    if not evidence_paths:
        raise RuntimeError(f"no evidence files matched {args.evidence_glob}")

    candidates = []
    source_evidence = []
    seen_candidate_keys = set()
    for evidence_path in evidence_paths:
        ev = load_json(evidence_path)
        source_evidence.append(str(evidence_path))
        for c in ev.get("candidates") or []:
            key = (
                str(c.get("ticker") or "").upper(),
                str(c.get("executive_name") or "").strip().lower(),
            )
            if key in seen_candidate_keys:
                raise RuntimeError(f"duplicate candidate across evidence tranches: {key}")
            seen_candidate_keys.add(key)
            validate_candidate(c)
            candidates.append(c)

    approved = [c for c in candidates if c.get("review_status") == "approved"]
    existing_handles = {str(x.get("handle") or "").lower() for x in base.get("leaders") or []}
    approved_handles = set()
    approved_already_live = 0

    additions = []
    for c in approved:
        handle = c["x_handle"].lstrip("@").lower()
        if handle in approved_handles:
            raise RuntimeError(f"duplicate approved X handle across evidence tranches: {handle}")
        approved_handles.add(handle)
        if handle in existing_handles:
            approved_already_live += 1
            continue
        leader = make_leader(c)
        additions.append(leader)

    preview = deepcopy(base)
    preview["schema_version"] = max(int(base.get("schema_version") or 0), 9)
    review_counts = {}
    for candidate in candidates:
        state = str(candidate.get("review_status") or "unknown")
        review_counts[state] = review_counts.get(state, 0) + 1

    preview["preview"] = {
        "status": "review_only",
        "source_evidence": source_evidence,
        "evidence_tranche_count": len(source_evidence),
        "reviewed_candidate_count": len(candidates),
        "review_status_counts": dict(sorted(review_counts.items())),
        "base_count": len(base.get("leaders") or []),
        "approved_already_live": approved_already_live,
        "approved_additions": len(additions),
        "preview_count": len(base.get("leaders") or []) + len(additions),
        "production_file_untouched": True,
    }
    preview["capacity"] = max(int(base.get("capacity") or 0), 250)
    preview["leaders"] = list(base.get("leaders") or []) + additions

    category_order = list(base.get("categories") or [])
    for leader in additions:
        for cat in leader.get("categories") or []:
            if cat and cat not in category_order:
                category_order.append(cat)
    preview["categories"] = category_order

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(preview, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(preview["preview"], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
