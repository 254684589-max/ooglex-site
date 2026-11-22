"""V39 existing-site product checks: authentic source wiring and blocked scores."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JS = (ROOT / "macro" / "compass-pages.js").read_text(encoding="utf-8")
HTML = (ROOT / "macro" / "overview.html").read_text(encoding="utf-8")
CSS = (ROOT / "macro" / "compass-pages.css").read_text(encoding="utf-8")
HOME = (ROOT / "index.html").read_text(encoding="utf-8")
DATA = json.loads((ROOT / "data" / "asset-scores.json").read_text(encoding="utf-8"))

REQUIRED = {
    "treasury.us10y", "treasury.real10y", "treasury.us2y", "nyfed.effr",
    "bls.cpi", "bls.core_cpi", "bls.unemployment", "bls.payroll",
    "bea.core_pce", "fed_h41.total_assets", "liquidity.reserves",
    "liquidity.tga", "liquidity.overnight_rrp",
    "nyfed_recession.probability",
}

class CompassFrontendV39Tests(unittest.TestCase):
    def test_fourteen_real_required_sources_in_overview_registry(self):
        section = JS.split("const OVERVIEW_INDICATORS=[", 1)[1].split("];", 1)[0]
        found = re.findall(r'\bid:"([^"]+)"', section)
        self.assertEqual(len(found), 14)
        self.assertEqual(set(found), REQUIRED)

    def test_existing_site_entry_and_pages_preserved(self):
        self.assertIn('href="macro/overview.html"', HOME)
        for route in ("index", "overview", "attribution", "research"):
            self.assertTrue((ROOT / "macro" / (route + ".html")).is_file())
            self.assertIn(f'./{route}.html', HTML)

    def test_mandatory_product_controls_and_sections_exist(self):
        for name in ("source-status", "overview-kpis", "headline",
                     "macro-table-body", "indicator-search", "indicator-filter",
                     "indicator-count", "asset-grid", "history-status"):
            self.assertIn('id="' + name + '"', HTML)
        self.assertIn("overview-controls", CSS)
        self.assertIn('aria-live="polite"', HTML)

    def test_stale_or_missing_values_not_imputed_as_zero(self):
        self.assertIn('state:present?"可用":"缺失或过期"', JS)
        self.assertIn('value:present?value:null', JS)
        self.assertIn('isoDay(period,def.cadence==="weekly"?21:11)', JS)
        self.assertIn('isoMonth(period,4)', JS)
        self.assertIn('"—"', JS)

    def test_score_gate_is_still_required(self):
        self.assertIn('data?.scoring?.calibration_verified===false', JS)
        self.assertIn('data?.scoring?.out_of_sample_verified===false', JS)
        self.assertIn('usableScore(a)', JS)
        self.assertIn('"— / 100"', JS)
        for a in DATA.get("assets", {}).values():
            self.assertIsNone(a["score"])
            self.assertEqual(a["status"], "unavailable")

    def test_original_public_snapshot_schema_is_real_and_supported(self):
        self.assertEqual(DATA["schema_version"], 1)
        self.assertIsInstance(DATA["rates"]["real10y"], (int, float))
        self.assertIn("core_cpi", DATA["bls"]["series"])
        self.assertIn("core_pce", DATA["bea"])
        self.assertIn("total_assets", DATA["fed_h41"])
        self.assertIn("overnight_rrp", DATA["liquidity"])
        self.assertIn("probability_percent", DATA["nyfed_recession_model"])
        self.assertFalse(DATA["scoring"]["calibration_verified"])
        self.assertFalse(DATA["scoring"]["out_of_sample_verified"])

    def test_other_research_sections_remain_routed(self):
        self.assertIn('page==="attribution"', JS)
        self.assertIn('page==="research"', JS)
        self.assertIn('renderFactorObservations(observations)', JS)

    def test_new_overview_disclaims_nonindependent_and_model_forecast(self):
        self.assertIn('m.official_forecast!==false', JS)
        self.assertIn('盈亏平衡通胀补偿', JS)
        self.assertIn('不直接合成买卖信号', JS)
        self.assertIn('首次观测归档', JS)

if __name__ == "__main__":
    unittest.main()
