"""V16 four-page terminal contract tests; no invented asset scores."""
import json
import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MACRO=ROOT/"macro"
PAGES={"overview.html":"overview","index.html":"indicators","attribution.html":"attribution","research.html":"research"}
ASSETS={"gold","us_equities","us_long_bonds","usd","bitcoin","oil"}
FACTORS={"rates","inflation","growth","liquidity","risk","asset_specific"}

class MacroFourPagesTests(unittest.TestCase):
    def test_four_page_navigation_bidirectional(self):
        for filename in PAGES:
            html=(MACRO/filename).read_text(encoding="utf-8")
            self.assertIn('aria-label="全球资产罗盘页面导航"',html)
            for target in PAGES:
                self.assertIn('href="./'+target+'"',html,filename)
            self.assertEqual(html.count('aria-current="page">'),1,filename)
    def test_new_pages_use_one_shared_asset_loader(self):
        js=(MACRO/"compass-pages.js").read_text(encoding="utf-8")
        for filename,page in PAGES.items():
            if filename=="index.html":continue
            html=(MACRO/filename).read_text(encoding="utf-8")
            self.assertIn('data-page="'+page+'"',html)
            self.assertIn('href="./compass-pages.css"',html)
            self.assertIn('src="./compass-pages.js"',html)
        self.assertIn('../data/asset-scores.json',js)
        self.assertIn('../data/asset-compass-price-audit.json',js)
        self.assertIn('../data/asset-compass-history-readiness.json',js)
        self.assertIn('./model-config.json',js)
    def test_weights_and_six_assets_are_defined_not_improvised(self):
        cfg=json.loads((MACRO/"model-config.json").read_text(encoding="utf-8"))
        self.assertEqual(set(cfg["weights"]),ASSETS)
        self.assertEqual(set(cfg["factor_order"]),FACTORS)
        self.assertTrue(all(len(w)==6 and sum(w)==100 for w in cfg["weights"].values()))
        js=(MACRO/"compass-pages.js").read_text(encoding="utf-8")
        for a in ASSETS:self.assertIn(a+':',js)
    def test_scoring_and_backtest_fail_closed(self):
        js=(MACRO/"compass-pages.js").read_text(encoding="utf-8")
        self.assertIn('a.validation?.historical_calibration_passed===true',js)
        self.assertIn('a.validation?.out_of_sample_passed===true',js)
        self.assertIn('validated_for_live_scoring===false',js)
        self.assertIn('— / 100',js)
        html=(MACRO/"research.html").read_text(encoding="utf-8")
        self.assertIn("不发布模型收益率",html)
        self.assertIn("预警功能保持关闭",html)
    def test_render_methods_do_not_inject_external_source_html(self):
        js=(MACRO/"compass-pages.js").read_text(encoding="utf-8")
        self.assertNotIn(".innerHTML=",js)
        self.assertIn("textContent",js)
        self.assertIn("replaceChildren",js)
    def test_existing_indicator_elements_retained(self):
        html=(MACRO/"index.html").read_text(encoding="utf-8")
        for name in ('id="metrics"','id="labor"','id="nyfed-recession"',
                     'id="fed-bea"','id="liquidity-panel"','id="assets"',
                     'id="price-audit"','id="archive-total"'):
            self.assertIn(name,html)

if __name__=="__main__":unittest.main()
