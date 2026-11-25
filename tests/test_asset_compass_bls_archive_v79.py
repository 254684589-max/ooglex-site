import unittest
from scripts.asset_compass_bls_archive_v79 import discover,header,expected_periods,summary

class ArchiveTests(unittest.TestCase):
    def test_index_link_and_gap(self):
        raw=b'<a href="/news.release/archives/cpi_10242025.htm">September 2025 Consumer Price Index</a>'
        r=discover(raw,"cpi")
        self.assertEqual(r["2025-09"]["scheduled_release_date_candidate_unverified"],"2025-10-24")
        self.assertEqual(len(expected_periods()),23)
        self.assertNotIn("2025-10",expected_periods())
    def test_older_pdf_index_html_candidate(self):
        raw=b'<a href="/news.release/archives/empsit_01052024.pdf">December 2023 Employment Situation (PDF)</a>'
        r=discover(raw,"employment",(2022,2023,2024,2025))
        self.assertEqual(r["2023-12"]["source_url"],"https://www.bls.gov/news.release/archives/empsit_01052024.htm")
        self.assertTrue(r["2023-12"]["html_candidate_from_pdf_index"])
        self.assertEqual(len(expected_periods((2022,2023,2024,2025))),47)
        self.assertEqual(discover(raw,"employment"),{})
    def test_reject_wrong_family_and_blocked_month(self):
        for raw in [b'<a href="/news.release/archives/empsit_10242025.htm">September 2025 Consumer Price Index</a>',
                    b'<a href="/news.release/archives/cpi_11142025.htm">October 2025 Consumer Price Index</a>']:
            with self.assertRaises(ValueError):discover(raw,"cpi")
    def test_header_is_candidate_not_pit(self):
        s={"scheduled_release_date_candidate_unverified":"2025-10-24"}
        raw=b'<html>Transmission of material in this release is embargoed until 8:30 a.m. (ET) Friday, October 24, 2025 USDL-25-1502</html>'
        r=header(s,raw)
        self.assertEqual(r["publisher_stated_embargo_utc"],"2025-10-24T12:30:00+00:00")
        self.assertFalse(r["publication_time_verified"])
        s["scheduled_release_date_candidate_unverified"]="2025-10-25"
        self.assertEqual(header(s,raw)["header_status"],"archive_date_mismatch")
    def test_legacy_cpi_heading_and_header(self):
        from scripts.asset_compass_bls_archive_v79 import inspect
        s={"release_kind":"cpi","observation_period":"2022-01","artifact_id":"legacy-cpi",
           "source_url":"https://www.bls.gov/news.release/archives/cpi_02102022.htm",
           "scheduled_release_date_candidate_unverified":"2022-02-10"}
        # Synthetic fixture reproduces the legacy separator and word order.
        raw=(b"<html>Transmission of material in this release is embargoed until "
             b"8:30 a.m. (ET) February 10, 2022 USDL-22-0191 "
             b"CONSUMER PRICE INDEX \x96 JANUARY 2022 "
             b"The Consumer Price Index for All Urban Consumers (CPI-U) increased 0.6 percent in January on a seasonally adjusted basis. "
             b"Over the last 12 months, the all items index increased 7.5 percent before seasonal adjustment. "
             b"The index for all items less food and energy rose 0.6 percent in January. "
             b"The index for all items less food and energy rose 6.0 percent over the past 12 months.</html>")
        r=inspect(s,raw)
        self.assertEqual(r["metric_count"],4)
        self.assertEqual(r["header"]["publisher_stated_embargo_utc"],"2022-02-10T13:30:00+00:00")
        self.assertFalse(r["pit_qualified"])
        with self.assertRaises(ValueError):
            inspect({**s,"observation_period":"2022-02"},raw)
    def test_payroll_narrative_comparison(self):
        from scripts.asset_compass_payroll_lineage_v111 import audit_payroll
        def row(period,clock,headline,claims,reissue=False):
            return {"source":{"release_kind":"employment","observation_period":period},
                "sha256":"a"*64,"reissue_notice_detected":reissue,
                "header":{"header_status":"publisher_header_matches_archive_date","publisher_stated_embargo_utc":clock},
                "metrics":[{"source_series_id":"bls.payroll","statistic":"monthly_payroll_change","observation_period":period,"value_reported":str(headline)}],
                "revision_claims":[{"target_observation_period":p,"source_reported_prior_value":str(v),"source_reported_revised_value":str(w),"delta_persons":str(w-v)} for p,v,w in claims]}
        rows=[row("2024-01","2024-02-02T13:30:00Z",100,[]),
              row("2024-02","2024-03-08T13:30:00Z",110,[("2024-01",100,120)]),
              row("2024-03","2024-04-05T12:30:00Z",130,[("2024-01",121,125),("2023-12",100,110)]),
              row("2024-04","2024-05-03T12:30:00Z",140,[],True)]
        r=audit_payroll(rows)
        self.assertEqual(r["comparison_counts"],{"matches_previous_candidate":1,"prior_value_mismatch":1,"prior_not_observed":1})
        self.assertEqual(r["excluded_reissue_or_unmatched_header_periods"],["2024-04"])
        self.assertFalse(r["historical_revision_chain_certified"])
    def test_new_employment_headline_variants(self):
        from scripts.asset_compass_bls_archive_v79 import inspect
        s={"release_kind":"employment","observation_period":"2025-08","artifact_id":"fixture",
           "source_url":"https://www.bls.gov/news.release/archives/empsit_09052025.htm",
           "scheduled_release_date_candidate_unverified":"2025-09-05"}
        raw=(b"<html>THE EMPLOYMENT SITUATION - AUGUST 2025 "
             b"Total nonfarm payroll employment changed little in August (+22,000). "
             b"Both the unemployment rate, at 4.3 percent, and the number of unemployed people changed little.</html>")
        r=inspect(s,raw)
        self.assertEqual({m["source_series_id"]:m["value_reported"] for m in r["metrics"]},{"bls.payroll":"22000","bls.unemployment":"4.3"})
        raw=b"<html>THE EMPLOYMENT SITUATION - AUGUST 2025 Both total nonfarm payroll employment (-50,000) and the unemployment rate (4.4 percent) changed little in August.</html>"
        r=inspect(s,raw)
        self.assertEqual({m["source_series_id"]:m["value_reported"] for m in r["metrics"]},{"bls.payroll":"-50000","bls.unemployment":"4.4"})
    def test_current_comparison_not_pit(self):
        from scripts.asset_compass_archive_crosscheck_v131 import compare
        def item(family,sid,stat,v):
            return {"source":{"release_kind":family,"observation_period":"2024-01","artifact_id":family},
                "sha256":"a"*64,"reissue_notice_detected":False,
                "header":{"header_status":"publisher_header_matches_archive_date"},
                "metrics":[{"source_series_id":sid,"statistic":stat,"observation_period":"2024-01","value_reported":v,"source_document_sha256":"a"*64}]}
        rows=[item("cpi","bls.cpi","headline_yoy_rate","5.0"),item("employment","bls.unemployment","monthly_unemployment_rate","4.1")]
        data={"CPIAUCNS":[{"date":"2023-01-01","value":100},{"date":"2024-01-01","value":105.04}],"UNRATE":[{"date":"2024-01-01","value":4.3}]}
        r=compare(rows,data)
        self.assertEqual(r["series"]["CPIAUCNS"]["within_reported_rounding"],1)
        self.assertEqual(r["series"]["UNRATE"]["different_current_value"],1)
        self.assertFalse(r["eligible_for_live_scoring"])
    def test_empty_does_not_pass(self):
        r=summary([],{}, {})
        self.assertEqual(len(r["families"]["cpi"]["missing_periods"]),23)
        self.assertFalse(r["eligible_for_live_scoring"])
