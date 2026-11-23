"""Protect the indicator-first site against unrelated scoring panels returning."""
import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
class IndicatorCatalogFocusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog=(ROOT/"macro/indicator-ratings.html").read_text(encoding="utf-8")
        cls.research=(ROOT/"macro/indicator-lab.html").read_text(encoding="utf-8")
        cls.center=(ROOT/"macro/index.html").read_text(encoding="utf-8")
        cls.a10=(ROOT/"macro/indicator-a10.js").read_text(encoding="utf-8")

    def test_40_indicators_and_four_equal_grades_remain(self):
        body=self.catalog.split("const indicators=[",1)[1].split("];",1)[0]
        counts={tier:len(re.findall(r'\["'+tier+r'","',body)) for tier in "ABCD"}
        self.assertEqual(counts,{"A":10,"B":10,"C":10,"D":10})

    def test_indicators_take_priority_over_legacy_experiments(self):
        self.assertIn('id="a10-rows"',self.catalog)
        self.assertIn('id="indicator-rows"',self.catalog)
        self.assertLess(self.catalog.index('id="a10-rows"'),self.catalog.index('id="indicator-rows"'))
        self.assertNotIn('id="v8-heading"',self.catalog)
        self.assertNotIn('id="quality-asset-rows"',self.catalog)
        self.assertNotIn('id="lead-heading"',self.catalog)
        self.assertNotIn('id="corr-heading"',self.catalog)
        self.assertNotIn('— / 100',self.center)
        self.assertNotIn('id="assets"',self.center)

    def test_old_research_is_preserved_and_accessible(self):
        for marker in ('id="history-heading"','id="v8-heading"','id="quality-asset-rows"','id="lead-heading"','id="corr-heading"'):
            self.assertIn(marker,self.research)
        self.assertIn('href="./indicator-lab.html"',self.catalog)
        self.assertIn('href="./indicator-ratings.html"',self.research)

    def test_a10_history_and_source_integration(self):
        handbook=(ROOT/'macro/indicator-a10-guide.js').read_text(encoding='utf-8')
        for marker in ('id="a10-guide"','id="a10-history-svg"','indicator-a10-guide.js'):
            self.assertIn(marker,self.catalog)
        self.assertIn('asset-compass-treasury-history.json',handbook)
        self.assertIn('not_valid_for_point_in_time_backtest!==true',handbook)
        for name in ('美国10年期实际收益率','SOFR及SOFR远期曲线','高收益债OAS信用利差'):
            self.assertIn(name,handbook)
        for marker in ('target_range_lower','target_range_upper','monthly_change_thousands',
                       'asset-compass-a10-sofr.json','sofr_forward_curve_available===false'):
            self.assertIn(marker,self.a10)

    def test_a10_is_exactly_ten_and_does_not_fabricate_forward_rates(self):
        self.assertEqual(len(re.findall(r'\{name:"',self.a10)),10)
        self.assertIn('id="a10-summary"',self.catalog)
        self.assertIn('indicator-a10.js',self.catalog)
        for name in ("SOFR及SOFR远期曲线","美国国债远期收益率曲线","高收益债OAS信用利差"):
            self.assertIn(name,self.a10)
        self.assertIn('待接入／数据缺失',self.a10)
        self.assertNotIn('score:',self.a10)

if __name__=="__main__":
    unittest.main()
