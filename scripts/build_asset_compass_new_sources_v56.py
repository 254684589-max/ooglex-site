#!/usr/bin/env python3
"""V56 two real US primary-source indicators, observational research only.

Chicago Fed NFCI (FRED hosted, credit/risk/financial conditions COMPOSITE).
US EIA WCESTUS1 commercial crude inventories excl. SPR (OIL asset only).
They are not independent certified model signals or vintage-correct backtests.
No ICE BofA high-yield spreads are fetched or publicly redistributed.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import re
import statistics
import urllib.parse
import urllib.request
from datetime import date, datetime, timezone
from html import unescape
from html.parser import HTMLParser
from pathlib import Path

from scripts.score_macro_assets import score_one, validate_config

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data" / "asset-compass-new-sources-v56.json"
MODEL = ROOT / "macro" / "model-config.json"
FRED_URL = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=NFCI&cosd=2019-01-01"
EIA_URL = "https://www.eia.gov/dnav/pet/hist/LeafHandler.ashx?f=W&n=PET&s=WCESTUS1"
ASSETS = ("gold", "us_equities", "us_long_bonds", "usd", "bitcoin", "oil")
SERIES_NAMES = ("nfci", "oil_inventory")
MAX_BYTES = 2_500_000
WEEKS = 104
NFCI_RECENT = 156
OIL_RECENT = 156


class EiaRows(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth = 0
        self.cell_depth = 0
        self.cells = []
        self.rows = []
        self.current = []
        self.current_cell = []

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            if self.depth == 0:
                self.cells = []
            self.depth += 1
        if tag in ("td", "th") and self.depth:
            if self.cell_depth == 0:
                self.current_cell = []
            self.cell_depth += 1

    def handle_data(self, data):
        if self.cell_depth:
            self.current_cell.append(data)

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self.cell_depth:
            self.cell_depth -= 1
            if self.cell_depth == 0:
                self.cells.append(re.sub(r"\s+", " ", unescape(
                    "".join(self.current_cell))).strip())
        if tag == "tr" and self.depth:
            self.depth -= 1
            if self.depth == 0:
                self.rows.append(self.cells)


def parse_nfci(raw: bytes):
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValueError("NFCI CSV encoding invalid") from exc
    reader = csv.DictReader(io.StringIO(text))
    if reader.fieldnames not in (["DATE", "NFCI"], ["observation_date", "NFCI"]):
        raise ValueError("NFCI CSV must have exact date,NFCI columns")
    dates, values = set(), []
    for row in reader:
        day = date.fromisoformat(row[reader.fieldnames[0]])
        value = row["NFCI"]
        if value == ".":
            continue
        try:
            val = float(value)
        except (TypeError, ValueError) as exc:
            raise ValueError("NFCI nonnumeric index") from exc
        if (day in dates or (values and day <= date.fromisoformat(values[-1]["date"]))
                or day.weekday() != 4 or not math.isfinite(val) or not -20 < val < 20):
            raise ValueError("NFCI invalid weekly observation/order")
        dates.add(day)
        values.append({"date": day.isoformat(), "value": val})
    if len(values) < WEEKS + 8:
        raise ValueError("NFCI genuine weekly history insufficient")
    return values


def parse_eia(raw: bytes):
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValueError("EIA HTML encoding invalid") from exc
    parser = EiaRows()
    parser.feed(text)
    if not re.search("Weekly U.S. Ending Stocks excluding SPR of Crude Oil",
                     unescape(re.sub("<[^>]+>", " ", text)), flags=re.I):
        raise ValueError("EIA page is not official crude-ex-SPR stock history")
    output = {}
    for cells in parser.rows:
        mark = next((re.search(r"\b((?:19|20)\d{2})-([A-Z][a-z]{2})\b", c)
                     for c in cells if re.search(r"\b(?:19|20)\d{2}-[A-Z][a-z]{2}\b", c)), None)
        if mark is None:
            continue
        year = int(mark.group(1))
        month = datetime.strptime(mark.group(2), "%b").month
        for i, cell in enumerate(cells[:-1]):
            clean = cell.strip()
            if not re.fullmatch(r"\d{2}/\d{2}", clean):
                continue
            next_cell = cells[i + 1].strip().replace(",", "")
            if not re.fullmatch(r"\d{5,7}", next_cell):
                continue
            observed = date(year, *map(int, clean.split("/")))
            if observed.month != month or observed.weekday() != 4:
                raise ValueError("EIA weekly date not in year-month row or not Friday")
            value = int(next_cell)
            if not 50_000 < value < 2_000_000 or observed.isoformat() in output:
                raise ValueError("EIA duplicate or impossible stock level")
            output[observed.isoformat()] = value
    rows = [{"date": dt, "value": val} for dt, val in sorted(output.items())]
    if len(rows) < WEEKS + 8:
        raise ValueError("EIA stock history missing, empty, or changed layout")
    return rows


def fetch_official(url, hostname, *, opener=None):
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != "https" or parsed.hostname != hostname
            or parsed.username or parsed.password or parsed.fragment):
        raise ValueError("Unapproved source URL")
    opener = opener or urllib.request.urlopen
    req = urllib.request.Request(
        url, headers={"User-Agent": "Ooglex-AssetCompass-Research/1.0",
                      "Accept": "text/csv,text/html;q=0.9,*/*;q=0.5"})
    with opener(req, timeout=35) as response:
        resolved = urllib.parse.urlsplit(response.geturl())
        if resolved.scheme != "https" or resolved.hostname != hostname:
            raise ValueError("Unapproved redirect/source host")
        raw = response.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES or len(raw) < 64:
        raise ValueError("Official response empty/oversized")
    return raw


def numeric_summary(rows, *, kind, now):
    if len(rows) < WEEKS + 8:
        raise ValueError("Insufficient valid real weekly series")
    first, last = date.fromisoformat(rows[0]["date"]), date.fromisoformat(rows[-1]["date"])
    if first >= last or last > now.date():
        raise ValueError("Future/invalid weekly observation")
    stale_days = (now.date() - last).days
    last_n = rows[-(NFCI_RECENT if kind == "nfci" else OIL_RECENT):]
    if kind == "nfci":
        # NFCI index is itself a standardized financial conditions COMPOSITE.
        baseline = [x["value"] for x in rows[-(WEEKS+1):-1]]
        current = rows[-1]["value"]
        prior = rows[-2]["value"]
        raw_change = current - prior
    elif kind == "oil_inventory":
        # 4-week stock CHANGE, in million barrels; overlapping windows are
        # descriptive and SEASONAL. No crude price or oil forecast implied.
        if len(rows) < WEEKS + 5:
            raise ValueError("Oil 4-week change needs longer baseline")
        def delta(i):
            return (rows[i]["value"]-rows[i-4]["value"])/1000.0
        baseline = [delta(i) for i in range(len(rows)-WEEKS-1, len(rows)-1)]
        current = delta(len(rows)-1)
        prior = delta(len(rows)-2)
        raw_change = current - prior
    else:
        raise ValueError("Unknown official source")
    mu = statistics.fmean(baseline)
    std = statistics.pstdev(baseline, mu=mu)
    z = None if std <= 1e-10 else (current-mu)/std
    return {
        "observation_count": len(rows),
        "first_observation_date": first.isoformat(),
        "latest_observation_date": last.isoformat(),
        "latest_level": rows[-1]["value"],
        "previous_week_level": rows[-2]["value"],
        "latest_week_delta": rows[-1]["value"]-rows[-2]["value"],
        "research_4week_change_million_barrels": round(current, 4) if kind == "oil_inventory" else None,
        "reference_104week_count": len(baseline),
        "rolling_reference_mean": round(mu, 6),
        "rolling_reference_std": round(std, 6),
        "research_z_score": round(z, 6) if z is not None else None,
        "normalized_research_pressure": round(math.tanh(z/2), 6) if z is not None else None,
        "age_calendar_days": stale_days,
        "current_observation_fresh": stale_days <= 21,
        "recent_observations": last_n,
        "first_publication_vintages_verified": False,
        "independent_scoring_signal_qualified": False,
        "out_of_sample_calibration_passed": False,
    }


def build(nfci_rows, oil_rows, config, *, nfci_sha, oil_sha, now=None):
    now = now or datetime.now(timezone.utc)
    if now.utcoffset() is None:
        raise ValueError("Time must include UTC offset")
    now = now.astimezone(timezone.utc)
    validate_config(config)
    if set(config["weights"]) != set(ASSETS):
        raise ValueError("Unknown model asset set")
    risk = numeric_summary(nfci_rows, kind="nfci", now=now)
    oil = numeric_summary(oil_rows, kind="oil_inventory", now=now)
    for name in (nfci_sha, oil_sha):
        if not re.fullmatch(r"[a-f0-9]{64}", name or ""):
            raise ValueError("Missing exact source-body digest")
    risk.update(
        series_id="NFCI", label="芝加哥联储全国金融条件指数",
        group="risk", owner="Federal Reserve Bank of Chicago",
        proxy_role="financial_conditions_composite_includes_risk_credit_rates",
        source_url=FRED_URL,
        citation_url="https://fred.stlouisfed.org/series/NFCI",
        source_raw_sha256=nfci_sha,
        latest_level_unit="index",
        permission_status="FRED_copyrighted_citation_required_not_ICE",
        limitations=[
            "NFCI includes interest-rate, credit, equities and banking indicators; NOT a standalone HY OAS.",
            "Composite overlaps existing rates/liquidity indicators; cannot count as independent vote.",
            "Weekly data values are historical latest-revised, NOT certified first-publication vintages.",
        ])
    oil.update(
        series_id="WCESTUS1", label="美国商业原油库存（不含战略石油储备）",
        group="asset_specific", asset_id="oil",
        owner="U.S. Energy Information Administration",
        proxy_role="oil_commercial_inventory_level_not_supply_demand_or_price",
        source_url=EIA_URL,
        citation_url="https://www.eia.gov/dnav/pet/hist/LeafHandler.ashx?f=W&n=PET&s=WCESTUS1",
        source_raw_sha256=oil_sha,
        latest_level_unit="thousand_barrels",
        limitations=[
            "EIA week-ending Friday is not Wednesday publication date.",
            "Crude stocks are seasonal; four-week changes are not seasonally adjusted.",
            "Inventory changes alone do not identify crude-price response or six-asset investing forecasts.",
        ])
    if any(not x["current_observation_fresh"] for x in (risk, oil)):
        status = "research_only_one_or_more_sources_stale"
    else:
        status = "research_only_two_official_sources_current"
    assets = {}
    for aid in ASSETS:
        # Deliberately no automatic conversion to price-direction signals.
        blocked = score_one(aid, {}, config, {})
        if blocked["score"] is not None:
            raise ValueError("V56 can never authorize published score")
        assets[aid] = {
            "asset_id": aid,
            "risk_proxy_source_count": 1,
            "asset_specific_source_count": int(aid == "oil"),
            "independent_model_signal_coverage_pct": 0,
            "research_price_direction_signal": None,
            "score": None,
            "historical_calibration_passed": False,
            "out_of_sample_validation_passed": False,
            "validated_for_live_scoring": False,
            "blocked_by": blocked["blocked_by"],
        }
    return {
        "schema_version": 1,
        "report_type": "asset_compass_v56_official_risk_and_oil_research",
        "generated_at": now.isoformat(),
        "status": status,
        "sources": {"nfci": risk, "oil_inventory": oil},
        "actual_observation_groups_added": ["risk", "asset_specific"],
        "groups_with_any_observation_across_v54_and_v56": 6,
        "assets_with_asset_specific_source_observations": ["oil"],
        "ice_bofa_high_yield_oas_research": "not_collected_permission_pending",
        "source_licensing_review_status": "source_specific_citation_required_not_a_general_redistribution_license",
        "source_vintages_qualified": 0,
        "independent_scoring_factor_groups_qualified": 0,
        "approved_asset_scores": 0,
        "validated_for_live_scoring": False,
        "eligible_for_point_in_time_backtest": False,
        "automated_trading_alerts_enabled": False,
        "assets": assets,
        "limitations": [
            "6/6 groups have some current historical observations somewhere, but only oil has a V56 asset-specific source.",
            "No independently verified asset direction, no licensed HY OAS, no PIT revision chain.",
            "NFCI overlaps rates, liquidity and credit; EIA stock level is seasonal, not WTI price prediction.",
            "Public website must cite Chicago Fed via FRED and EIA. No ICE-proprietary source rehosted.",
            "Official 0-100 asset scores remain null for every asset.",
        ],
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--fetch", action="store_true", help="Fetch two real HTTPS official sources, no test data")
    p.add_argument("--nfci-csv", type=Path, help="Local actual CSV for offline verification")
    p.add_argument("--eia-html", type=Path, help="Local actual official HTML for offline verification")
    p.add_argument("--output", type=Path, default=OUTPUT)
    p.add_argument("--config", type=Path, default=MODEL)
    args = p.parse_args()
    if args.fetch == bool(args.nfci_csv or args.eia_html):
        p.error("Choose --fetch or BOTH --nfci-csv and --eia-html")
    if args.fetch:
        raw_nfci = fetch_official(FRED_URL, "fred.stlouisfed.org")
        raw_oil = fetch_official(EIA_URL, "www.eia.gov")
    else:
        if args.nfci_csv is None or args.eia_html is None:
            p.error("Both --nfci-csv and --eia-html required")
        raw_nfci, raw_oil = args.nfci_csv.read_bytes(), args.eia_html.read_bytes()
    nfci, oil = parse_nfci(raw_nfci), parse_eia(raw_oil)
    config = json.loads(args.config.read_text(encoding="utf-8"))
    report = build(nfci, oil, config,
                   nfci_sha=hashlib.sha256(raw_nfci).hexdigest(),
                   oil_sha=hashlib.sha256(raw_oil).hexdigest())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n",
                           encoding="utf-8")
    print(json.dumps({
        "status": report["status"],
        "nfci_weeks": report["sources"]["nfci"]["observation_count"],
        "eia_oil_weeks": report["sources"]["oil_inventory"]["observation_count"],
        "risk_research_observation": report["sources"]["nfci"]["latest_level"],
        "oil_inventory_thousand_barrels": report["sources"]["oil_inventory"]["latest_level"],
        "qualified_factor_groups": 0, "official_asset_scores": 0
    }, ensure_ascii=False))
    if report["status"] != "research_only_two_official_sources_current":
        raise SystemExit("V56 source stale: file retained, but not current")


if __name__ == "__main__":
    main()
