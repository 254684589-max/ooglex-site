#!/usr/bin/env python3
"""
Build the first-stage Ooglex U.S. public-company universe for Tech Leaders.

Sources:
- SEC company_tickers_exchange.json for CIK / ticker / exchange identity.
- Nasdaq public stock screener for market cap / sector / industry prioritization.

The script intentionally does NOT discover or scrape X accounts. It only builds
the issuer universe used by the later executive/X verification pipeline.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

SEC_URL = "https://www.sec.gov/files/company_tickers_exchange.json"
NASDAQ_URL = "https://api.nasdaq.com/api/screener/stocks"

DEFAULT_UA = os.getenv(
    "SEC_USER_AGENT",
    "Ooglex Tech Leaders Scanner/1.0 https://www.ooglex.com",
)

EXCLUDE_NAME_PATTERNS = [
    r"\betf\b",
    r"\betn\b",
    r"\bfund\b",
    r"\bwarrant",
    r"\bright(s)?\b",
    r"\bunit(s)?\b",
    r"blank check",
    r"acquisition corp",
    r"acquisition company",
    r"special purpose acquisition",
]


def http_json(url: str, *, headers: dict[str, str] | None = None, retries: int = 3) -> Any:
    hdrs = {
        "User-Agent": DEFAULT_UA,
        "Accept": "application/json,text/plain,*/*",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://www.nasdaq.com/",
        "Origin": "https://www.nasdaq.com",
    }
    if headers:
        hdrs.update(headers)

    last_exc: Exception | None = None
    for attempt in range(retries):
        try:
            req = Request(url, headers=hdrs)
            with urlopen(req, timeout=45) as resp:
                raw = resp.read()
            return json.loads(raw.decode("utf-8"))
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


def parse_market_cap(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value) if value > 0 else None
    s = str(value).strip()
    if not s or s in {"N/A", "NA", "-", "--"}:
        return None
    s = s.replace("$", "").replace(",", "").strip()
    mult = 1
    if s[-1:].upper() in {"K", "M", "B", "T"}:
        suffix = s[-1:].upper()
        s = s[:-1]
        mult = {"K": 1_000, "M": 1_000_000, "B": 1_000_000_000, "T": 1_000_000_000_000}[suffix]
    try:
        return int(float(s) * mult)
    except ValueError:
        return None


def name_exclusion_reason(name: str) -> str | None:
    low = (name or "").lower()
    for pattern in EXCLUDE_NAME_PATTERNS:
        if re.search(pattern, low):
            return pattern
    return None


def load_sec_map() -> dict[str, dict[str, Any]]:
    payload = http_json(SEC_URL, headers={"Referer": "https://www.sec.gov/"})
    fields = payload.get("fields") or []
    data = payload.get("data") or []
    if not fields or not data:
        raise RuntimeError("SEC ticker/exchange payload was empty")

    out: dict[str, dict[str, Any]] = {}
    for row in data:
        rec = dict(zip(fields, row))
        exch = normalize_exchange(str(rec.get("exchange") or ""))
        if exch not in {"NASDAQ", "NYSE"}:
            continue
        ticker = str(rec.get("ticker") or "").strip().upper()
        if not ticker:
            continue
        key = normalize_symbol(ticker)
        cik_raw = rec.get("cik")
        try:
            cik = f"{int(cik_raw):010d}"
        except (TypeError, ValueError):
            continue
        out[key] = {
            "cik": cik,
            "ticker": ticker,
            "company": str(rec.get("name") or "").strip(),
            "exchange": exch,
        }
    return out


def load_nasdaq_rows(limit: int = 10000) -> list[dict[str, Any]]:
    params = {
        "tableonly": "true",
        "limit": str(limit),
        "offset": "0",
        "download": "true",
    }
    payload = http_json(f"{NASDAQ_URL}?{urlencode(params)}")
    rows = (((payload or {}).get("data") or {}).get("table") or {}).get("rows") or []
    if not isinstance(rows, list):
        raise RuntimeError("Nasdaq screener payload did not contain rows")
    return rows


def build_universe(limit: int) -> list[dict[str, Any]]:
    sec = load_sec_map()
    nasdaq_rows = load_nasdaq_rows()

    best: dict[tuple[str, str], dict[str, Any]] = {}
    for row in nasdaq_rows:
        ticker = str(row.get("symbol") or "").strip().upper()
        if not ticker:
            continue
        sec_rec = sec.get(normalize_symbol(ticker))
        if not sec_rec:
            continue

        exchange = normalize_exchange(str(row.get("exchange") or "")) or sec_rec["exchange"]
        if exchange not in {"NASDAQ", "NYSE"}:
            continue

        company = str(row.get("name") or sec_rec["company"] or "").strip()
        exclusion = name_exclusion_reason(company)
        if exclusion:
            continue

        market_cap = parse_market_cap(row.get("marketCap"))
        if not market_cap or market_cap <= 0:
            continue

        rec = {
            "cik": sec_rec["cik"],
            "ticker": sec_rec["ticker"],
            "company": company,
            "exchange": exchange,
            "market_cap_usd": market_cap,
            "sector": str(row.get("sector") or "").strip(),
            "industry": str(row.get("industry") or "").strip(),
            "country": str(row.get("country") or "").strip(),
            "sec_identity_source": SEC_URL,
            "market_priority_source": NASDAQ_URL,
        }

        key = (rec["cik"], rec["ticker"])
        prev = best.get(key)
        if prev is None or rec["market_cap_usd"] > prev["market_cap_usd"]:
            best[key] = rec

    records = sorted(best.values(), key=lambda r: (-r["market_cap_usd"], r["ticker"]))
    records = records[:limit]

    minimum = min(800, max(100, int(limit * 0.75)))
    if len(records) < minimum:
        raise RuntimeError(
            f"quality gate failed: only {len(records)} matched NYSE/Nasdaq operating-company rows; "
            f"need at least {minimum}. Existing output will not be replaced."
        )

    for idx, rec in enumerate(records, start=1):
        rec["priority_rank"] = idx

    return records


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
        "industry",
        "country",
        "sec_identity_source",
        "market_priority_source",
    ]
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(records)
    tmp.replace(path)


def write_meta(path: Path, records: list[dict[str, Any]], limit: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    by_exchange: dict[str, int] = {}
    by_sector: dict[str, int] = {}
    for rec in records:
        by_exchange[rec["exchange"]] = by_exchange.get(rec["exchange"], 0) + 1
        sector = rec["sector"] or "Unknown"
        by_sector[sector] = by_sector.get(sector, 0) + 1

    payload = {
        "schema_version": 1,
        "generated_at": now,
        "requested_limit": limit,
        "record_count": len(records),
        "exchange_counts": dict(sorted(by_exchange.items())),
        "sector_counts": dict(sorted(by_sector.items(), key=lambda kv: (-kv[1], kv[0]))),
        "sources": {
            "sec": SEC_URL,
            "nasdaq_screener": NASDAQ_URL,
        },
        "scope": "NYSE + NASDAQ operating-company priority universe",
        "next_stage": "executive role extraction and X account verification",
    }
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=1000)
    ap.add_argument(
        "--output",
        default="data/tech-leaders/issuer_master.csv",
        help="CSV output path",
    )
    ap.add_argument(
        "--meta",
        default="data/tech-leaders/issuer_master.meta.json",
        help="metadata JSON output path",
    )
    args = ap.parse_args()

    if args.limit < 100 or args.limit > 5000:
        ap.error("--limit must be between 100 and 5000")

    records = build_universe(args.limit)
    write_csv(Path(args.output), records)
    write_meta(Path(args.meta), records, args.limit)

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
