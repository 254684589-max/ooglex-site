import unittest
from decimal import Decimal
from scripts.asset_compass_alfred_v138 import parse,compare_one,url_for,candidates,summary

class AlfredTests(unittest.TestCase):
    def test_vintage_headers_and_no_future_values(self):
        ds=["2024-02-14","2024-03-13"]
        raw=b"observation_date,UNRATE_20240214,UNRATE_20240313\n2024-01-01,3.7,3.8\n2024-02-01,.,3.9\n2024-03-01,,\n"
        got=parse(raw,"UNRATE",ds)
        self.assertEqual(got[ds[0]],{"2024-01":Decimal("3.7")})
        self.assertEqual(got[ds[1]]["2024-02"],Decimal("3.9"))
        with self.assertRaises(ValueError):parse(raw.replace(b"UNRATE_20240214",b"UNRATE_20261125"),"UNRATE",ds)
        with self.assertRaises(ValueError):parse(raw.replace(b"2024-03-01,,",b"2024-03-01,4.0,"),"UNRATE",ds)
        self.assertIn("vintage_date=2024-02-14%2C2024-03-13",url_for("UNRATE",ds))
    def test_payroll_same_vintage_and_cpi(self):
        c={"series":"PAYEMS","period":"2024-02","vintage":"2024-03-09","archive_sha256":"a"*64,"archive_value":Decimal(200000)}
        r=compare_one(c,{"2024-01":Decimal("157000"),"2024-02":Decimal("157200")},"b"*64)
        self.assertEqual(r["status"],"within_reported_rounding")
        self.assertFalse(r["historical_pit_certified"])
        self.assertEqual(compare_one(c,{"2024-02":Decimal("157200")},"b"*64)["status"],"vintage_value_missing")
        c.update(series="CPIAUCNS",archive_value=Decimal("5.0"))
        self.assertEqual(compare_one(c,{"2023-02":Decimal(100),"2024-02":Decimal("105.04")},"b"*64)["status"],"within_reported_rounding")
    def test_date_level_candidates_and_fail_closed(self):
        row={"source":{"observation_period":"2024-01","scheduled_release_date_candidate_unverified":"2024-02-02"},
             "sha256":"a"*64,"reissue_notice_detected":False,"header":{"header_status":"publisher_header_matches_archive_date","publisher_stated_embargo_utc":"2024-02-02T13:30:00Z"},
             "metrics":[{"source_series_id":"bls.unemployment","statistic":"monthly_unemployment_rate","observation_period":"2024-01","source_document_sha256":"a"*64,"value_reported":"3.7"}]}
        c=candidates([row])
        self.assertEqual(c[0]["vintage"],"2024-02-03")
        self.assertEqual(candidates([{**row,"reissue_notice_detected":True}]),[])
        with self.assertRaises(ValueError):candidates([row,row])
        s=summary(c,[],[],{})
        self.assertEqual(s["series"]["UNRATE"]["missing_download_or_comparison"],1)
        self.assertFalse(s["eligible_for_live_scoring"])
