"""Protect B/C official source display, preserved 40-item A/B/C/D catalog and no-score gating."""
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class BCCatalogFrontendTests(unittest.TestCase):
    def test_provenance_and_units(self):
        page=(ROOT/"macro/indicator-ratings.html").read_text(encoding="utf-8")
        src=(ROOT/"macro/indicator-bc-official.js").read_text(encoding="utf-8")
        self.assertIn('id="bc-heading"',page)
        self.assertIn('id="bc-rows"',page)
        self.assertIn('id="bc-history-svg"',page)
        self.assertIn("indicator-bc-official.js",page)
        self.assertIn("asset-compass-bc-official-v1.json",src)
        self.assertIn("redistribution_rights_independently_approved!==false",src)
        self.assertIn("historical_pit_certified!==false",src)
        for label in ("美国实际GDP增长率","美国工业生产指数","美国零售销售",
                      "美国初请失业金人数","美元广义贸易加权指数","WTI原油现货价格"):
            self.assertIn(label,src)
        self.assertNotIn("BAMLH0A0HYM2",src)
        self.assertNotIn("fake",src)
if __name__=="__main__":unittest.main()
