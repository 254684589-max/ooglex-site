"""All 40 catalog research grades must be separated from live-data completeness."""
import copy
import json
import unittest
from datetime import datetime,timezone
from pathlib import Path
from scripts.build_40_indicator_coverage_v1 import build,catalog_items,ROOT

class CoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows=catalog_items((ROOT/"macro/indicator-ratings.html").read_text(encoding="utf-8"))
        cls.snapshot=json.loads((ROOT/"data/asset-scores.json").read_text(encoding="utf-8"))
        cls.sofr=json.loads((ROOT/"data/asset-compass-a10-sofr.json").read_text(encoding="utf-8"))
        cls.now=datetime(2026,11,23,9,tzinfo=timezone.utc)

    def test_forty_rows_and_ten_per_grade(self):
        report=build(self.rows,self.snapshot,self.sofr,now=self.now)
        self.assertEqual(len(report["items"]),40)
        self.assertEqual({g:sum(report["counts_by_grade"][g].values()) for g in "ABCD"},
                         {g:10 for g in "ABCD"})
        self.assertFalse(report["validated_for_live_scoring"])
        self.assertTrue(report["not_an_asset_score"])
        self.assertFalse(report["historical_pit_certification"])

    def test_sofr_remains_partial_without_forward_curve(self):
        report=build(self.rows,self.snapshot,self.sofr,now=self.now)
        statuses={x["name"]:x["status"] for x in report["items"]}
        self.assertEqual(statuses["SOFR及SOFR远期曲线"],"partial")
        self.assertEqual(statuses["联邦基金目标利率及FOMC指引"],"partial")
        self.assertEqual(statuses["美国国债远期收益率曲线"],"missing")
        self.assertEqual(statuses["高收益债OAS信用利差"],"missing")
        self.assertEqual(statuses["美国非农就业与失业率"],"current")

    def test_no_fabricated_scores_or_data(self):
        broken=copy.deepcopy(self.snapshot)
        broken["assets"]["gold"]["score"]=73
        with self.assertRaises(ValueError):
            build(self.rows,broken,self.sofr,now=self.now)
        no_sofr=build(self.rows,self.snapshot,{},now=self.now)
        statuses={x["name"]:x["status"] for x in no_sofr["items"]}
        self.assertEqual(statuses["SOFR及SOFR远期曲线"],"missing")

    def test_old_observations_are_stale_not_missing(self):
        old=build(self.rows,self.snapshot,self.sofr,
                  now=datetime(2027,2,1,tzinfo=timezone.utc))
        status={x["name"]:x["status"] for x in old["items"]}
        self.assertEqual(status["美国10年期国债收益率"],"stale")
        self.assertEqual(status["SOFR及SOFR远期曲线"],"stale")

    def test_duplicate_catalog_or_rank_count_rejected(self):
        with self.assertRaises(ValueError):
            catalog_items('const indicators=[["A","rates","duplicate","x","y","z"]];')

if __name__=="__main__":unittest.main()
