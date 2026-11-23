"""V57 actual published Treasury/NFCI overlap: descriptive only, no PIT."""
import copy
import json
import unittest
from datetime import datetime,timezone,timedelta
from pathlib import Path
from scripts.audit_asset_compass_cross_source_v57 import audit,pearson,align
from scripts.build_asset_compass_asset_specific_v57 import build,parse_gold,parse_treasury,combine_auction_sources
from test_asset_compass_asset_specific_v57 import gold_raw,treasury_raw,ROOT,NOW

class V57CrossSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cfg=json.loads((ROOT/"macro/model-config.json").read_text())
        cls.v56=json.loads((ROOT/"data/asset-compass-new-sources-v56.json").read_text())
        cls.treasury=json.loads((ROOT/"data/asset-compass-treasury-history.json").read_text())
        # The treasury dataset is refreshed asynchronously after the V57 fixture date.
        cls.audit_now=max(NOW,datetime.fromisoformat(cls.treasury["retrieved_at"].replace("Z","+00:00"))+timedelta(seconds=1))
        gold=parse_gold(gold_raw(),now=NOW)
        bond=parse_treasury(treasury_raw(),now=NOW)
        cls.v57=build(gold,bond,cfg,cls.v56,now=NOW,
                      source_hashes={"cftc_gold":"a"*64,"treasury_30y":"b"*64})

    def test_three_genuine_source_series_comparisons_without_scoring(self):
        report=audit(self.v57,self.v56,self.treasury,now=self.audit_now)
        self.assertEqual(report["source_comparison_count"],4)
        self.assertFalse(report["available_for_investment_scoring"])
        self.assertFalse(report["historical_pit_qualified"])
        self.assertFalse(report["out_of_sample_return_calibration_passed"])
        self.assertIsNone(report["score"])
        for v in report["results"].values():
            self.assertGreaterEqual(v["aligned_weekly_observations"],52)
            self.assertFalse(v["causal_predictive_independence_qualified"])
            self.assertFalse(v["historical_available_at_verified"])
            self.assertFalse(v["oos_predictive_significance_tested"])

    def test_latest_revised_pearson_bounded(self):
        r=audit(self.v57,self.v56,self.treasury,now=self.audit_now)
        self.assertTrue(all(v["contemporaneous_pearson_latest_revised"] is None or
             -1<=v["contemporaneous_pearson_latest_revised"]<=1
             for v in r["results"].values()))

    def test_no_variance_yields_no_pearson_not_a_neutral_0(self):
        self.assertIsNone(pearson([(str(i),7,2*i) for i in range(54)]))
        self.assertIsNone(pearson([(str(i),i,3) for i in range(54)]))
        self.assertIsNone(pearson([("2026-01-01",1,1)]))

    def test_price_or_pit_certification_silent_mutation_refused(self):
        x=copy.deepcopy(self.v57);x["approved_asset_scores"]=1
        with self.assertRaises(ValueError):
            audit(x,self.v56,self.treasury,now=self.audit_now)
        y=copy.deepcopy(self.v56);y["validated_for_live_scoring"]=True
        with self.assertRaises(ValueError):
            audit(self.v57,y,self.treasury,now=self.audit_now)

    def test_inconsistent_lineage_rejected(self):
        x=copy.deepcopy(self.v57);x["v56_observed_at"]="2023-01-01"
        with self.assertRaisesRegex(ValueError,"lineage"):
            audit(x,self.v56,self.treasury,now=self.audit_now)

    def test_weekly_align_can_use_prior_treasury_market_day_only(self):
        src=[{"date":"2026-11-15","value":0.7}]
        matched=align(src,self.treasury["observations"],"real10y","value","date")
        self.assertEqual(len(matched),1)
        self.assertEqual(matched[0][0],"2026-11-15")
        self.assertNotEqual(matched[0][2],None)

    def test_source_sample_too_short_does_not_fabricate_correlation(self):
        x=copy.deepcopy(self.v57)
        x["sources"]["cftc_gold"]["recent_observations"]=x["sources"]["cftc_gold"]["recent_observations"][:20]
        with self.assertRaisesRegex(ValueError,"insufficient"):
            audit(x,self.v56,self.treasury,now=self.audit_now)

    def test_asof_reported_not_verified_for_CFTC_tuesday_publication(self):
        r=audit(self.v57,self.v56,self.treasury,now=self.audit_now)
        self.assertTrue(any("days later" in s for s in r["warnings"]))
        self.assertFalse(r["historical_pit_qualified"])


if __name__=="__main__":
    unittest.main()
