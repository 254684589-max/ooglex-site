import json
import unittest
from pathlib import Path
from scripts.audit_asset_compass_prices import audit

ROOT=Path(__file__).resolve().parents[1]

class AssetCompassPublicReadinessTests(unittest.TestCase):
    def test_current_repository_audit_has_no_price_values(self):
        source=json.loads((ROOT/"apps/asset-tracker/history.json").read_text(encoding="utf-8"))
        crypto=json.loads((ROOT/"apps/asset-ranking/crypto.json").read_text(encoding="utf-8"))
        result=audit(source,crypto)
        self.assertEqual(result["report_type"],"price_coverage_audit")
        self.assertEqual(set(result["assets"]),{"gold","us_equities","us_long_bonds","usd","bitcoin","oil"})
        self.assertFalse(result["validated_for_live_scoring"])
        self.assertGreater(result["assets"]["bitcoin"]["observation_count"],0)
        self.assertEqual(result["assets"]["bitcoin"]["source"],"CoinGecko")
        self.assertFalse(any(v["eligible_for_return_backtest"] for v in result["assets"].values()))
        published=json.dumps(result)
        self.assertNotIn('"closes"',published)
        self.assertNotIn('"dates"',published)
        self.assertNotIn('"series"',published)
    def test_page_has_fail_closed_readiness_panel(self):
        page=(ROOT/"macro/index.html").read_text(encoding="utf-8")
        self.assertIn('id="price-audit"',page)
        self.assertIn('id="price-audit-status"',page)
        self.assertIn('asset-compass-price-audit.json',page)
        self.assertIn('validated_for_live_scoring!==false',page)
        self.assertIn('尚未验证收益口径',page)
    def test_build_pipeline_prepares_report_before_site_copy(self):
        yaml=(ROOT/".github/workflows/deploy_protected_pages.yml").read_text(encoding="utf-8")
        self.assertLess(yaml.index("python3 scripts/audit_asset_compass_prices.py"),yaml.index("python scripts/build_public_site.py --pro-cutover"))
if __name__=="__main__":unittest.main()
