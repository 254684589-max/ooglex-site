import json
import unittest
from datetime import date
from pathlib import Path
from scripts.update_macro_nyfed import parse_response
from scripts.score_macro_assets import validate_config, score_one, produce

CONFIG=json.loads((Path(__file__).resolve().parents[1]/"macro"/"model-config.json").read_text(encoding="utf-8"))
def entry(v):
    return {"signal":v,"verified":True,"fresh":True,"observation_date":"2026-11-19"}

class MacroScoreTests(unittest.TestCase):
    def test_weights_total_100(self):
        validate_config(CONFIG)
        self.assertTrue(all(sum(x)==100 for x in CONFIG["weights"].values()))
    def test_unverified_signals_do_not_publish(self):
        x=score_one("gold",{"rates":entry(1)},CONFIG)
        self.assertIsNone(x["score"])
        self.assertIn("insufficient_factor_groups",x["blocked_by"])
        self.assertIn("historical_calibration_not_passed",x["blocked_by"])
    def test_full_data_still_requires_validation(self):
        s={name:entry(1) for name in CONFIG["factor_order"]}
        r=score_one("gold",s,CONFIG)
        self.assertIsNone(r["score"])
    def test_synthetic_calibrated_extremes_are_deterministic(self):
        # Unit test only; cannot be substituted for actual historical validation.
        validation={"historical_calibration_passed":True,"out_of_sample_passed":True}
        yes={n:entry(1) for n in CONFIG["factor_order"]}
        no={n:entry(-1) for n in CONFIG["factor_order"]}
        neutral={n:entry(0) for n in CONFIG["factor_order"]}
        self.assertEqual(score_one("gold",yes,CONFIG,validation)["score"],100)
        self.assertEqual(score_one("gold",no,CONFIG,validation)["score"],0)
        self.assertEqual(score_one("gold",neutral,CONFIG,validation)["score"],50)
    def test_missing_signals_not_renormalized(self):
        validation={"historical_calibration_passed":True,"out_of_sample_passed":True}
        s={n:entry(1) for n in CONFIG["factor_order"] if n!="rates"}
        r=score_one("gold",s,CONFIG,validation)
        self.assertIsNone(r["score"])
        self.assertEqual(r["coverage_pct"],70)
    def test_nan_and_boolean_are_ignored(self):
        validation={"historical_calibration_passed":True,"out_of_sample_passed":True}
        s={n:entry(0) for n in CONFIG["factor_order"]}
        s["rates"]=entry(float("nan"))
        s["growth"]=entry(True)
        r=score_one("us_equities",s,CONFIG,validation)
        self.assertIsNone(r["score"])
    def test_unvalidated_snapshot_emits_no_scores(self):
        d=produce({"schema_version":1},CONFIG)
        self.assertTrue(all(v["score"] is None for v in d["assets"].values()))
    def test_nyfed_latest_verified(self):
        feed={"refRates":[{"effectiveDate":"2026-11-18","type":"EFFR","percentRate":3.85,"targetRateFrom":3.75,"targetRateTo":4.0},
                          {"effectiveDate":"2026-11-19","type":"EFFR","percentRate":3.88,"targetRateFrom":3.75,"targetRateTo":4.0}]}
        r=parse_response(feed,date(2026,11,22))
        self.assertEqual(r["effr_percent"],3.88)
        self.assertEqual(r["observation_date"],"2026-11-19")
    def test_nyfed_stale_rejected(self):
        feed={"refRates":[{"effectiveDate":"2026-10-01","type":"EFFR","percentRate":3.88,"targetRateFrom":3.75,"targetRateTo":4.0}]}
        with self.assertRaisesRegex(ValueError,"stale"):
            parse_response(feed,date(2026,11,22))

if __name__=="__main__":unittest.main()
