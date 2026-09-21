#!/usr/bin/env python3
"""Build the Ooglex Tech Leaders NYSE/Nasdaq issuer universe.

V1.1 expands the old 300-company pilot to a 1,000-company research universe.

Priority sources:
1) apps/companies/data.json — existing Ooglex market-cap ranking.
2) apps/supply-chain/domestic.json — large SEC-backed 10-K issuer pool used to
   extend coverage beyond the site's quoted company board.

The supplemental SEC pool is ranked by filer category (public-float tier) and
annual-filing recency. This is deliberately labelled as a proxy, not market cap.

This stage does not discover X accounts.
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
DEFAULT_DOMESTIC_PATH = "apps/supply-chain/domestic.json"
DEFAULT_UA = os.getenv(
    "SEC_USER_AGENT",
    "Ooglex Tech Leaders Scanner/1.1 https://www.ooglex.com",
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
    if not isinstance(rows, list) or len(rows) < 250:
        raise RuntimeError(f"Ooglex companies dataset is unexpectedly small: {len(rows)}")
    return rows, payload


def load_domestic_supplement(path: Path) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    companies = payload.get("companies") or {}
    if not isinstance(companies, dict) or len(companies) < 1000:
        raise RuntimeError(f"SEC domestic issuer dataset is unexpectedly small: {len(companies)}")

    rows: list[dict[str, Any]] = []
    for key, raw in companies.items():
        if not isinstance(raw, dict):
            continue
        ticker = str(raw.get("symbol") or key or "").strip().upper()
        exchange = normalize_exchange(str(raw.get("exchange") or ""))
        if not ticker or exchange not in {"NYSE", "NASDAQ"}:
            continue
        company = str(raw.get("name") or ticker).strip()
        if name_exclusion_reason(company):
            continue
        try:
            cik = f"{int(raw.get('cik')):010d}"
        except (TypeError, ValueError):
            continue

        rows.append(
            {
                "cik": cik,
                "ticker": ticker,
                "company": company,
                "exchange": exchange,
                "sector": "",
                "country": str(raw.get("country") or "US"),
                "filer_category": str(raw.get("filerCategory") or "").strip(),
                "last_annual": str(raw.get("lastAnnual") or "").strip(),
                "sic": str(raw.get("sic") or "").strip(),
                "sic_description": str(raw.get("sicDescription") or "").strip(),
            }
        )
    if len(rows) < 1000:
        raise RuntimeError(f"NYSE/Nasdaq SEC supplement is unexpectedly small: {len(rows)}")
    return rows


def is_us_company(row: dict[str, Any]) -> bool:
    country = str(row.get("country") or "").strip()
    return country in {"美国", "United States", "USA", "US"}


def filer_category_rank(value: str) -> int:
    low = (value or "").lower()
    if "large accelerated" in low:
        return 0
    if "accelerated" in low and "non-accelerated" not in low:
        return 1
    if "non-accelerated" in low:
        return 2
    if "smaller reporting" in low:
        return 3
    return 4


def date_rank(value: str) -> int:
    digits = re.sub(r"[^0-9]", "", value or "")
    return -int(digits[:8]) if len(digits) >= 8 else 0


def build_universe(
    companies_path: Path,
    domestic_path: Path,
    limit: int,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    sec = load_sec_map()
    company_rows, company_meta = load_ooglex_companies(companies_path)
    domestic_rows = load_domestic_supplement(domestic_path)

    records: list[dict[str, Any]] = []
    seen_cik: set[str] = set()
    seen_ticker: set[str] = set()

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
        cik = sec_rec["cik"]
        ticker_key = normalize_symbol(sec_rec["ticker"])
        if cik in seen_cik or ticker_key in seen_ticker:
            continue
        seen_cik.add(cik)
        seen_ticker.add(ticker_key)

        records.append(
            {
                "priority_rank": len(records) + 1,
                "cik": cik,
                "ticker": sec_rec["ticker"],
                "company": company,
                "exchange": sec_rec["exchange"],
                "market_cap_usd": int(round(market_cap_b * 1_000_000_000)),
                "sector": str(row.get("sector") or "").strip(),
                "country": "US",
                "ooglex_company_rank": int(row.get("rank") or 0),
                "market_data_as_of": str(company_meta.get("asOf") or ""),
                "priority_method": "market_cap",
                "filer_category": "",
                "last_annual": "",
                "sec_identity_source": SEC_URL,
                "market_priority_source": DEFAULT_COMPANIES_PATH,
            }
        )
        if len(records) >= limit:
            break

    if len(records) < limit:
        supplemental = sorted(
            domestic_rows,
            key=lambda r: (
                filer_category_rank(r["filer_category"]),
                date_rank(r["last_annual"]),
                r["company"].lower(),
                r["ticker"],
            ),
        )
        for row in supplemental:
            ticker_key = normalize_symbol(row["ticker"])
            if row["cik"] in seen_cik or ticker_key in seen_ticker:
                continue
            seen_cik.add(row["cik"])
            seen_ticker.add(ticker_key)
            records.append(
                {
                    "priority_rank": len(records) + 1,
                    "cik": row["cik"],
                    "ticker": row["ticker"],
                    "company": row["company"],
                    "exchange": row["exchange"],
                    "market_cap_usd": "",
                    "sector": row["sector"],
                    "country": row["country"],
                    "ooglex_company_rank": "",
                    "market_data_as_of": str(company_meta.get("asOf") or ""),
                    "priority_method": "sec_filer_category_proxy",
                    "filer_category": row["filer_category"],
                    "last_annual": row["last_annual"],
                    "sec_identity_source": SEC_URL,
                    "market_priority_source": DEFAULT_DOMESTIC_PATH,
                }
            )
            if len(records) >= limit:
                break

    minimum = max(100, int(limit * 0.90))
    if len(records) < minimum:
        raise RuntimeError(
            f"quality gate failed: only {len(records)} NYSE/Nasdaq rows; "
            f"need at least {minimum}. Existing output will not be replaced."
        )
    return records, company_meta


FIELDS = [
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
    "priority_method",
    "filer_category",
    "last_annual",
    "sec_identity_source",
    "market_priority_source",
]


def write_csv(path: Path, records: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(records)
    tmp.replace(path)


def write_meta(
    path: Path,
    records: list[dict[str, Any]],
    limit: int,
    company_meta: dict[str, Any],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    by_exchange: dict[str, int] = {}
    by_sector: dict[str, int] = {}
    by_method: dict[str, int] = {}
    for rec in records:
        by_exchange[rec["exchange"]] = by_exchange.get(rec["exchange"], 0) + 1
        sector = rec["sector"] or "Unknown"
        by_sector[sector] = by_sector.get(sector, 0) + 1
        method = rec["priority_method"]
        by_method[method] = by_method.get(method, 0) + 1

    payload = {
        "schema_version": 3,
        "stage": "v1_1_universe_1000",
        "generated_at": now,
        "requested_limit": limit,
        "record_count": len(records),
        "exchange_counts": dict(sorted(by_exchange.items())),
        "sector_counts": dict(sorted(by_sector.items(), key=lambda kv: (-kv[1], kv[0]))),
        "priority_method_counts": dict(sorted(by_method.items())),
        "market_data_as_of": company_meta.get("asOf"),
        "sources": {
            "sec_identity": SEC_URL,
            "market_cap_priority": DEFAULT_COMPANIES_PATH,
            "sec_scale_proxy": DEFAULT_DOMESTIC_PATH,
        },
        "scope": "NYSE/Nasdaq research universe. Quoted companies use market-cap order; supplemental issuers use SEC filer-category/public-float tier as a labelled proxy.",
        "next_stage": "multi-person leader discovery and X identity/activity verification",
    }
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=1000)
    ap.add_argument("--companies", default=DEFAULT_COMPANIES_PATH)
    ap.add_argument("--domestic", default=DEFAULT_DOMESTIC_PATH)
    ap.add_argument("--output", default="data/tech-leaders/issuer_master.csv")
    ap.add_argument("--meta", default="data/tech-leaders/issuer_master.meta.json")
    args = ap.parse_args()

    if args.limit < 100 or args.limit > 2000:
        ap.error("--limit must be between 100 and 2000")

    records, company_meta = build_universe(
        Path(args.companies),
        Path(args.domestic),
        args.limit,
    )
    write_csv(Path(args.output), records)
    write_meta(Path(args.meta), records, args.limit, company_meta)

    print(
        json.dumps(
            {
                "ok": True,
                "records": len(records),
                "priority_methods": {
                    method: sum(1 for r in records if r["priority_method"] == method)
                    for method in sorted({r["priority_method"] for r in records})
                },
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
