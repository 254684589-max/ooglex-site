#!/usr/bin/env python3
"""Cut a small SEC companyfacts subset for the financial Sankey page.

Reads /tmp/sec/{nvda,msft,tickers}.json when present, otherwise downloads the
public SEC files once. Does not use an API key. Output is real XBRL, not a
simulated dataset.
"""
from __future__ import annotations

import json
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
UA = "Ooglex financial-sankey (https://www.ooglex.com)"
KEEP_FORMS = {"10-K", "10-K/A", "10-Q", "10-Q/A", "20-F", "20-F/A"}
MIN_END = "2024-01-01"
CONCEPTS = [
    "Revenues",
    "RevenueFromContractWithCustomerExcludingAssessedTax",
    "RevenueFromContractWithCustomerIncludingAssessedTax",
    "SalesRevenueNet",
    "CostOfRevenue",
    "CostOfGoodsAndServicesSold",
    "CostOfGoodsSold",
    "CostOfServices",
    "GrossProfit",
    "ResearchAndDevelopmentExpense",
    "SellingGeneralAndAdministrativeExpense",
    "SellingAndMarketingExpense",
    "GeneralAndAdministrativeExpense",
    "OperatingExpenses",
    "OperatingIncomeLoss",
    "NonoperatingIncomeExpense",
    "OtherNonoperatingIncomeExpense",
    "InterestExpense",
    "InterestExpenseNonoperating",
    "InvestmentIncomeInterest",
    "IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest",
    "IncomeTaxExpenseBenefit",
    "NetIncomeLoss",
    "Assets",
    "LiabilitiesAndStockholdersEquity",
    "AssetsCurrent",
    "CashAndCashEquivalentsAtCarryingValue",
    "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents",
    "MarketableSecuritiesCurrent",
    "ShortTermInvestments",
    "AvailableForSaleSecuritiesDebtMaturitiesWithinOneYearFairValue",
    "AvailableForSaleSecuritiesDebtMaturitiesAfterOneThroughFiveYearsFairValue",
    "AccountsReceivableNetCurrent",
    "InventoryNet",
    "PrepaidExpenseAndOtherAssetsCurrent",
    "OtherAssetsCurrent",
    "PropertyPlantAndEquipmentNet",
    "Goodwill",
    "IntangibleAssetsNetExcludingGoodwill",
    "FiniteLivedIntangibleAssetsNet",
    "LongTermInvestments",
    "MarketableSecuritiesNoncurrent",
    "EquitySecuritiesFVNINoncurrent",
    "EquitySecuritiesWithoutReadilyDeterminableFairValueAmount",
    "OtherAssetsNoncurrent",
    "OperatingLeaseRightOfUseAsset",
    "Liabilities",
    "LiabilitiesCurrent",
    "AccountsPayableCurrent",
    "AccruedLiabilitiesCurrent",
    "ContractWithCustomerLiabilityCurrent",
    "LongTermDebtCurrent",
    "DebtCurrent",
    "ShortTermBorrowings",
    "CommercialPaper",
    "LongTermDebtNoncurrent",
    "OtherLiabilitiesNoncurrent",
    "StockholdersEquity",
    "StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest",
    "RetainedEarningsAccumulatedDeficit",
    "AdditionalPaidInCapital",
    "CommonStockValue",
    "CommonStocksIncludingAdditionalPaidInCapital",
    "AccumulatedOtherComprehensiveIncomeLossNetOfTax",
    "TreasuryStockValue",
    "NetCashProvidedByUsedInOperatingActivities",
    "NetCashProvidedByUsedInInvestingActivities",
    "NetCashProvidedByUsedInFinancingActivities",
    "DepreciationDepletionAndAmortization",
    "DepreciationAndAmortization",
    "DepreciationAmortizationAndAccretionNet",
    "Depreciation",
    "AmortizationOfIntangibleAssets",
    "ShareBasedCompensation",
    "PaymentsToAcquirePropertyPlantAndEquipment",
    "PaymentsToAcquireProductiveAssets",
    "PaymentsOfDividends",
    "PaymentsOfDividendsCommonStock",
    "PaymentsForRepurchaseOfCommonStock",
    "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalentsPeriodIncreaseDecreaseIncludingExchangeRateEffect",
    "EffectOfExchangeRateOnCashAndCashEquivalents",
    "EffectOfExchangeRateOnCashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents",
    "EffectOfExchangeRateOnCashCashEquivalentsRestrictedCashAndRestrictedCashEquivalentsIncludingRestrictedCash",
]


def fetch(url: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 0:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as res:
        dest.write_bytes(res.read())


def slim_facts(doc: dict) -> dict:
    gaap = doc.get("facts", {}).get("us-gaap", {})
    out = {}
    for concept in CONCEPTS:
        node = gaap.get(concept)
        if not node:
            continue
        rows = []
        for row in node.get("units", {}).get("USD", []):
            if row.get("form") not in KEEP_FORMS:
                continue
            end = row.get("end")
            if not end or end < MIN_END:
                continue
            item = {
                "end": end,
                "val": row.get("val"),
                "form": row.get("form"),
                "filed": row.get("filed"),
                "fy": row.get("fy"),
                "fp": row.get("fp"),
            }
            if row.get("start"):
                item["start"] = row["start"]
            if row.get("frame"):
                item["frame"] = row["frame"]
            rows.append(item)
        if rows:
            out[concept] = {"label": node.get("label") or concept, "units": {"USD": rows}}
    return out


def main() -> None:
    cache = Path("/tmp/sec")
    fetch("https://data.sec.gov/api/xbrl/companyfacts/CIK0001045810.json", cache / "nvda.json")
    fetch("https://data.sec.gov/api/xbrl/companyfacts/CIK0000789019.json", cache / "msft.json")
    fetch("https://www.sec.gov/files/company_tickers.json", cache / "tickers.json")
    extracted = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    companies = {
        "nvda": ("0001045810", "https://data.sec.gov/api/xbrl/companyfacts/CIK0001045810.json"),
        "msft": ("0000789019", "https://data.sec.gov/api/xbrl/companyfacts/CIK0000789019.json"),
    }
    snap_dir = ROOT / "snapshots"
    snap_dir.mkdir(parents=True, exist_ok=True)
    for key, (cik, url) in companies.items():
        doc = json.loads((cache / f"{key}.json").read_text())
        payload = {
            "cik": int(doc.get("cik") or cik),
            "entityName": doc.get("entityName"),
            "extract": {
                "demo": False,
                "source": "SEC EDGAR companyfacts",
                "sourceUrl": url,
                "extractedAt": extracted,
                "frequency": "annual",
                "status": "ok",
                "note": "Subset of public us-gaap facts for recent 10-K/10-Q/20-F rows. Not a simulated dataset.",
            },
            "facts": {"us-gaap": slim_facts(doc)},
        }
        path = snap_dir / f"{key}.json"
        path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        print(key, path.stat().st_size, "concepts", len(payload["facts"]["us-gaap"]))

    raw = json.loads((cache / "tickers.json").read_text())
    compact = {}
    dupes = 0
    for item in raw.values():
        ticker = str(item["ticker"]).upper()
        entry = [int(item["cik_str"]), item["title"]]
        if ticker in compact:
            dupes += 1
            continue
        compact[ticker] = entry
    tick_path = ROOT / "tickers.json"
    tick_path.write_text(json.dumps(compact, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("tickers", len(compact), "dupes_skipped", dupes, "bytes", tick_path.stat().st_size)


if __name__ == "__main__":
    main()
