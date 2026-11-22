"""V42 official historical yield validation; synthetic source rows only."""
import unittest
from copy import deepcopy
from datetime import datetime,timezone

from scripts.validate_asset_compass_treasury_trends_v42 import validate


def sample():
    observations=[]
    for i,(day,y10,y2,real) in enumerate([
        ("2026-11-18",4.55,4.1,2.2),
        ("2026-11-19",4.6,4.2,2.3),
        ("2026-11-20",4.5,4.15,2.1),
    ]):
        observations.append({"date":day,"us10y":y10,"us2y":y2,
                             "real10y":real,"breakeven10y":round(y10-real,3),
                             "spread10y2y":round(y10-y2,3)})
    url="https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/2026/all?"
    return {
        "schema_version":1,"dataset":"treasury_historical_daily_observations",
        "source":"U.S. Department of the Treasury",
        "retrieved_at":"2026-11-22T08:00:00+00:00",
        "start_date":observations[0]["date"],"end_date":observations[-1]["date"],
        "observation_count":len(observations),
        "original_release_vintages_available":False,
        "not_valid_for_point_in_time_backtest":True,
        "source_urls":[url+"type=daily_treasury_yield_curve&field_tdr_date_value=2026",
                       url+"type=daily_treasury_real_yield_curve&field_tdr_date_value=2026"],
        "observations":observations,
    }


NOW=datetime(2026,11,22,12,0,tzinfo=timezone.utc)

class TreasuryV42Tests(unittest.TestCase):
    def check(self,document):
        return validate(document,minimum=2,now=NOW)

    def test_synthetic_matched_trend_passes_only_observational_purpose(self):
        report=self.check(sample())
        self.assertEqual(report["observations"],3)
        self.assertTrue(report["safe_for_observational_chart"])
        self.assertFalse(report["historical_pit_approved"])

    def test_missing_actual_tips_source_blocked(self):
        d=sample()
        d["source_urls"]=d["source_urls"][:1]
        with self.assertRaisesRegex(ValueError,"nominal and TIPS"):
            self.check(d)

    def test_fake_pit_claim_blocked(self):
        d=sample()
        d["original_release_vintages_available"]=True
        with self.assertRaisesRegex(ValueError,"PIT"):
            self.check(d)

    def test_duplicate_date_blocked(self):
        d=sample()
        d["observations"][1]["date"]=d["observations"][0]["date"]
        with self.assertRaisesRegex(ValueError,"duplicate"):
            self.check(d)

    def test_wrong_breakeven_arithmetic_blocked(self):
        d=sample()
        d["observations"][1]["breakeven10y"]=9
        with self.assertRaisesRegex(ValueError,"breakeven"):
            self.check(d)

    def test_wrong_yield_spread_arithmetic_blocked(self):
        d=sample()
        d["observations"][1]["spread10y2y"]=9
        with self.assertRaisesRegex(ValueError,"10Y"):
            self.check(d)

    def test_future_observation_rejected(self):
        d=sample()
        d["observations"][-1]["date"]="2027-11-20"
        d["end_date"]="2027-11-20"
        with self.assertRaisesRegex(ValueError,"future"):
            self.check(d)

    def test_bad_hostname_and_redirect_like_source_rejected(self):
        d=sample()
        d["source_urls"][0]=d["source_urls"][0].replace("home.treasury.gov","home.treasury.gov.evil.example")
        with self.assertRaisesRegex(ValueError,"forged"):
            self.check(d)

    def test_nonfinite_and_boolean_values_rejected(self):
        for v in (float("nan"),True,None):
            d=sample();d["observations"][0]["real10y"]=v
            with self.subTest(v=v),self.assertRaisesRegex(ValueError,"invalid yield"):
                self.check(d)

    def test_future_retrieval_time_rejected(self):
        d=sample();d["retrieved_at"]="2099-11-22T08:00:00+00:00"
        with self.assertRaisesRegex(ValueError,"retrieval"):
            self.check(d)

    def test_bad_count_rejected(self):
        d=sample();d["observation_count"]=100
        with self.assertRaisesRegex(ValueError,"count"):
            self.check(d)

    def test_decreasing_dates_rejected(self):
        d=sample();d["observations"].reverse();d["start_date"]=d["observations"][0]["date"];d["end_date"]=d["observations"][-1]["date"]
        with self.assertRaisesRegex(ValueError,"unsorted"):
            self.check(d)


if __name__=="__main__":
    unittest.main()
