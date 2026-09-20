#!/usr/bin/env python3
"""
Build the first-stage Ooglex U.S. public-company universe for Tech Leaders.

Stage 1 deliberately uses the site's already-stable daily company ranking as the
market-cap priority source, then cross-checks identity/exchange against SEC.
This avoids depending on a fragile third-party screener during the pilot.

Sources:
- apps/companies/data.json: Ooglex daily company ranking (Yahoo-backed market cap).
- SEC company_tickers_exchange.json: CIK / ticker / exchange identity.

This script does NOT discover or scrape X accounts. X matching belongs to the
next verification stage.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

SEC_URL = "https://www.sec.gov/files/company_tickers_exchange.json"
DEFAULT_COMPANIES_PATH = "apps/companies/data.json"
DEFAULT_UA = os.getenv(
    "SEC_USER_AGENT",
    "Ooglex Tech Leaders Scanner/1.0 https://www.ooglex.com",
)

EXCLUDE_NAME_PATTERNS = [
    r"\betf\b",
    r"\betn\b",
    r"\bwarrant",
    r"blank check",
    r"acquisition corp",
    r"acquisition company",
    r"special purpose acquisition",
]


def http_json(url: str, retries: int = 3) -> Any:
    last_exc: Exception | None = None
    for attempt in range(retries):
        try:
            req = Request(
                url,
                headers={
                    "User-Agent": DEFAULT_UA,
                    "Accept": "application/json,text/plain,*/*",
                    "Accept-Language": "en-US,en;q=0.9",
                    "Referer": "https://www.sec.gov/",
                },
            )
            with urlopen(req, timeout=35) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
            last_exc = exc
            if attempt + 1 < retries:
                time.sleep(2 ** attempt)
    raise RuntimeError(f"failed to fetch {url}: {last_exc}")


def normalize_symbol(symbol: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", (symbol or "").upper())


def normalize_exchange(value: str) -> str | None:
    x = (value or "").strip().upper()
    if "NASDAQ" in x:
        return "NASDAQ"
    if x == "NYSE" or x.startswith("NYSE "):
        return "NYSE"
    return None


def name_exclusion_reason(name: str) -> str | None:
    low = (name or "").lower()
    for pattern in EXCLUDE_NAME_PATTERNS:
        if re.search(pattern, low):
            return pattern
    return None


def load_sec_map() -> dict[str, dict[str, Any]]:
    payload = http_json(SEC_URL)
    fields = payload.get("fields") or []
    data = payload.get("data") or []
    if not fields or not data:
        raise RuntimeError("SEC ticker/exchange payload was empty")

    out: dict[str, dict[str, Any]] = {}
    for row in data:
        rec = dict(zip(fields, row))
        exchange = normalize_exchange(str(rec.get("exchange") or ""))
        if exchange not in {"NASDAQ", "NYSE"}:
            continue

        ticker = str(rec.get("ticker") or "").strip().upper()
        if not ticker:
            continue

        try:
            cik = f"{int(rec.get('cik')):010d}"
        except (TypeError, ValueError):
            continue

        out[normalize_symbol(ticker)] = {
            "cik": cik,
            "ticker": ticker,
            "company": str(rec.get("name") or "").strip(),
            "exchange": exchange,
        }
    return out


def load_ooglex_companies(path: Path) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    rows = payload.get("companies") or []
    if not isinstance(rows, list) or len(rows) < 300:
        raise RuntimeError(f"Ooglex companies dataset is unexpectedly small: {len(rows)}")
    return rows, payload


def is_us_company(row: dict[str, Any]) -> bool:
    country = str(row.get("country") or "").strip()
    return country in {"美国", "United States", "USA", "US"}


def build_universe(companies_path: Path, limit: int) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    sec = load_sec_map()
    company_rows, company_meta = load_ooglex_companies(companies_path)

    records: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()

    ordered = sorted(
        company_rows,
        key=lambda r: (
            int(r.get("rank") or 10**9),
            -float(r.get("marketCap") or 0),
            str(r.get("symbol") or ""),
        ),
    )

    for row in ordered:
        if not is_us_company(row):
            continue

        symbol = str(row.get("symbol") or "").strip().upper()
        if not symbol or symbol in {"—", "-", "N/A"}:
            continue

        sec_rec = sec.get(normalize_symbol(symbol))
        if not sec_rec:
            continue

        company = str(row.get("nameEn") or sec_rec["company"] or "").strip()
        if name_exclusion_reason(company):
            continue

        try:
            market_cap_b = float(row.get("marketCap"))
        except (TypeError, ValueError):
            continue
        if market_cap_b <= 0:
            continue

        key = (sec_rec["cik"], sec_rec["ticker"])
        if key in seen:
            continue
        seen.add(key)

        records.append(
            {
                "priority_rank": len(records) + 1,
                "cik": sec_rec["cik"],
                "ticker": sec_rec["ticker"],
                "company": company,
                "exchange": sec_rec["exchange"],
                "market_cap_usd": int(round(market_cap_b * 1_000_000_000)),
                "sector": str(row.get("sector") or "").strip(),
                "country": "US",
                "ooglex_company_rank": int(row.get("rank") or 0),
                "market_data_as_of": str(company_meta.get("asOf") or ""),
                "sec_identity_source": SEC_URL,
                "market_priority_source": DEFAULT_COMPANIES_PATH,
            }
        )
        if len(records) >= limit:
            break

    minimum = min(250, max(100, int(limit * 0.80)))
    if len(records) < minimum:
        raise RuntimeError(
            f"quality gate failed: only {len(records)} verified NYSE/Nasdaq U.S. rows; "
            f"need at least {minimum}. Existing output will not be replaced."
        )

    return records, company_meta


def write_csv(path: Path, records: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "priority_rank",
        "cik",
        "ticker",
        "company",
        "exchange",
        "market_cap_usd",
        "sector",
        "country",
        "ooglex_company_rank",
        "market_data_as_of",
        "sec_identity_source",
        "market_priority_source",
    ]
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(records)
    tmp.replace(path)


def write_meta(path: Path, records: list[dict[str, Any]], limit: int, company_meta: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    by_exchange: dict[str, int] = {}
    by_sector: dict[str, int] = {}
    for rec in records:
        by_exchange[rec["exchange"]] = by_exchange.get(rec["exchange"], 0) + 1
        sector = rec["sector"] or "Unknown"
        by_sector[sector] = by_sector.get(sector, 0) + 1

    payload = {
        "schema_version": 2,
        "stage": "pilot_300",
        "generated_at": now,
        "requested_limit": limit,
        "record_count": len(records),
        "exchange_counts": dict(sorted(by_exchange.items())),
        "sector_counts": dict(sorted(by_sector.items(), key=lambda kv: (-kv[1], kv[0]))),
        "market_data_as_of": company_meta.get("asOf"),
        "sources": {
            "sec_identity": SEC_URL,
            "market_priority": DEFAULT_COMPANIES_PATH,
        },
        "scope": "Top U.S. companies in Ooglex market-cap dataset, SEC-verified as NYSE/NASDAQ",
        "next_stage": "executive role extraction and X account verification",
    }
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=300)
    ap.add_argument("--companies", default=DEFAULT_COMPANIES_PATH)
    ap.add_argument("--output", default="data/tech-leaders/issuer_master.csv")
    ap.add_argument("--meta", default="data/tech-leaders/issuer_master.meta.json")
    args = ap.parse_args()

    if args.limit < 100 or args.limit > 500:
        ap.error("--limit must be between 100 and 500 for the pilot stage")

    records, company_meta = build_universe(Path(args.companies), args.limit)
    write_csv(Path(args.output), records)
    write_meta(Path(args.meta), records, args.limit, company_meta)

    print(
        json.dumps(
            {
                "ok": True,
                "records": len(records),
                "top5": [
                    {
                        "rank": r["priority_rank"],
                        "ticker": r["ticker"],
                        "company": r["company"],
                        "market_cap_usd": r["market_cap_usd"],
                    }
                    for r in records[:5]
                ],
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
