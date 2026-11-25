#!/usr/bin/env python3
"""SEC EDGAR TLT monthly fund-return pilot. No live scoring or investor-cost claims."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from datetime import date
from decimal import Decimal, InvalidOperation
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SERIES = "S000004360"
CLASS = "C000012090"
FILINGS = {
    "000207169126008193": "2026-02-28",
    "000207169126016714": "2026-05-31",
}
MAX_BYTES = 4_000_000

def source_url(accession, registry=FILINGS):
    if accession not in registry:
        raise ValueError("Unreviewed filing accession")
    return f"https://www.sec.gov/Archives/edgar/data/1100663/{accession}/primary_doc.xml"

def parse_filing(raw, accession, registry=FILINGS, *, series_id=SERIES, class_id=CLASS):
    url = source_url(accession, registry)
    if not raw or len(raw) > MAX_BYTES or re.search(br"<!\s*(DOCTYPE|ENTITY)", raw, re.I):
        raise ValueError("Unsafe or oversized XML")
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as exc:
        raise ValueError("Invalid filing XML") from exc
    # SEC N-PORT uses a default namespace; retain local schema names.
    for element in root.iter():
        element.tag = element.tag.rsplit("}", 1)[-1]
    if root.tag != "edgarSubmission":
        raise ValueError("Not an EDGAR submission")
    def single(name):
        # The header may repeat the series identity. Only Part A genInfo
        # defines the reporting series and period.
        values = root.findall("./formData/genInfo/" + name)
        if len(values) != 1 or not values[0].text:
            raise ValueError("Missing or ambiguous " + name)
        return values[0].text.strip()
    if single("seriesId") != series_id or single("repPdDate") != registry[accession]:
        raise ValueError("Wrong fund or reporting period")
    rows = root.findall("./formData/fundInfo/returnInfo/monthlyTotReturns/monthlyTotReturn")
    if len(rows) != 1 or rows[0].get("classId") != class_id:
        raise ValueError("Wrong or ambiguous fund class")
    end = date.fromisoformat(registry[accession])
    out = []
    for i in range(1, 4):
        try:
            value = Decimal(rows[0].attrib[f"rtn{i}"])
        except (KeyError, InvalidOperation) as exc:
            raise ValueError("Missing or invalid return") from exc
        if not value.is_finite() or value < -100:
            raise ValueError("Invalid return percentage")
        month_index = end.year * 12 + end.month - 1 - (3-i)
        out.append({"month": f"{month_index//12:04d}-{month_index%12+1:02d}",
                    "reported_fund_total_return_percent": str(value)})
    return {"accession": accession, "source_url": url,
            "report_period_end": end.isoformat(), "series_id": series_id, "class_id": class_id,
            "local_input_sha256": hashlib.sha256(raw).hexdigest(),
            "local_xml_parsed_not_independently_authenticated": True,
            "monthly_observations": out}

def assemble(filings):
    observations = {}
    for filing in filings:
        for row in filing["monthly_observations"]:
            month = row["month"]
            if month in observations:
                raise ValueError("Overlapping periods require amendment/revision review")
            observations[month] = {**row, "accession": filing["accession"]}
    return {"report_type": "asset_compass_v63_sec_fund_return_research_pilot",
            "asset": "us_long_bonds", "ticker": "TLT", "frequency": "monthly",
            "source": "SEC EDGAR N-PORT Item B.5",
            "filings": filings, "observations": [observations[k] for k in sorted(observations)],
            "historical_pit_certified": False, "investor_costs_reconciled": False,
            "investable_total_return_certified": False, "eligible_for_live_scoring": False,
            "official_score": None}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--feb-xml", type=Path, required=True)
    p.add_argument("--may-xml", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    if args.output.resolve().is_relative_to(ROOT):
        p.error("Research output must remain outside the public website repository")
    files = [args.feb_xml, args.may_xml]
    filings = []
    for accession, file in zip(FILINGS, files):
        with file.open("rb") as stream:
            filings.append(parse_filing(stream.read(MAX_BYTES + 1), accession))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(assemble(filings), indent=2, allow_nan=False)+"\n", encoding="utf-8")

if __name__ == "__main__":
    main()
