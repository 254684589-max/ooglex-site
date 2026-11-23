"""V56 official-source parsers, provenance and strict 0–100 scoring gates."""
import copy
import hashlib
import json
import math
import re
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from scripts.build_asset_compass_new_sources_v56 import (
    ASSETS, EIA_URL, FRED_URL, build, fetch_official, numeric_summary,
    parse_eia, parse_nfci,
)

ROOT=Path(__file__).resolve().parents[1]
NOW=datetime(2026,11,23,7,30,tzinfo=timezone.utc)


def series(n=160):
    last=date(2026,11,13)
    days=[(last-timedelta(weeks=n-1-i)) for i in range(n)]
    nfci=[{"date":d.isoformat(),"value":round(-0.8+0.004*i+0.05*math.sin(i/3),4)}
          for i,d in enumerate(days)]
    eia=[{"date":d.isoformat(),"value":int(415000+9000*math.sin(i/9)+i*14)}
         for i,d in enumerate(days)]
    return nfci,eia


def csv_input(rows,header="DATE,NFCI"):
    return (header+"\n"+"\n".join(f"{r['date']},{r['value']}" for r in rows)+"\n").encode()


def html_input(rows):
    grouped={}
    for r in rows:
        key=date.fromisoformat(r["date"]).strftime("%Y-%b")
        grouped.setdefault(key,[]).append(r)
    table=["<html><title>Weekly U.S. Ending Stocks excluding SPR of Crude Oil (Thousand Barrels)</title>",
           "<table>"]
    for ym,records in grouped.items():
        cells=[f"<td>{ym}</td>"]
        for r in records:
            day=date.fromisoformat(r["date"])
            cells.append(f"<td>{day:%m/%d}</td><td>{r['value']:,}</td>")
        table.append("<tr>"+"".join(cells)+"</tr>")
    return ("".join(table)+"</table></html>").encode()


def fixture():
    cfg=json.loads((ROOT/"macro/model-config.json").read_text())
    n,o=series()
    return n,o,cfg


class V56SourcesTests(unittest.TestCase):
    def test_nfci_parses_realistic_weekly_fred_csv(self):
        n,_,_=fixture()
        self.assertEqual(parse_nfci(csv_input(n)),n)

    def test_fred_supports_date_header_without_remapping_other_columns(self):
        n,_,_=fixture()
        self.assertEqual(parse_nfci(csv_input(n,header="observation_date,NFCI")),n)

    def test_nfci_forbids_injected_wrong_series_id(self):
        n,_,_=fixture()
        with self.assertRaisesRegex(ValueError,"exact"):
            parse_nfci(csv_input(n,header="DATE,BAMLH0A0HYM2"))

    def test_nfci_invalid_order_or_duplicate_fails(self):
        n,_,_=fixture()
        with self.assertRaises(ValueError):
            parse_nfci(csv_input(n+[n[-1]]))

    def test_nfci_nonfinite_missing_prohibited(self):
        n,_,_=fixture()
        with self.assertRaises(ValueError):
            parse_nfci(csv_input(n).replace(b",-0.8\n",b",NaN\n"))

    def test_nfci_short_series_prohibited(self):
        n,_,_=fixture()
        with self.assertRaisesRegex(ValueError,"insufficient"):
            parse_nfci(csv_input(n[:40]))

    def test_eia_official_stock_html_table_parser(self):
        _,o,_=fixture()
        self.assertEqual(parse_eia(html_input(o)),o)

    def test_eia_wrong_title_fails(self):
        _,o,_=fixture()
        bad=html_input(o).replace(b"excluding SPR",b"including SPR")
        with self.assertRaisesRegex(ValueError,"not official"):
            parse_eia(bad)

    def test_eia_wrong_year_month_rejected(self):
        _,o,_=fixture()
        bad=html_input(o).replace(b"2026-Nov",b"2026-Oct")
        with self.assertRaisesRegex(ValueError,"year-month"):
            parse_eia(bad)

    def test_eia_duplicate_week_rejected(self):
        _,o,_=fixture()
        bad=html_input(o)+b""
        bad=bad.replace(b"</table>",b"<tr><td>2026-Nov</td><td>11/13</td><td>415,000</td></tr></table>")
        with self.assertRaisesRegex(ValueError,"duplicate"):
            parse_eia(bad)

    def test_eia_value_underflow_does_not_create_synthetic_stocks(self):
        _,o,_=fixture()
        bad=html_input(o).replace(f"{o[-1]['value']:,}".encode(),b"49,000")
        with self.assertRaisesRegex(ValueError,"impossible"):
            parse_eia(bad)

    def test_two_actual_source_groups_not_independent_scores(self):
        n,o,cfg=fixture()
        r=build(n,o,cfg,nfci_sha="a"*64,oil_sha="b"*64,now=NOW)
        self.assertEqual(r["status"],"research_only_two_official_sources_current")
        self.assertEqual(r["groups_with_any_observation_across_v54_and_v56"],6)
        self.assertEqual(r["actual_observation_groups_added"],["risk","asset_specific"])
        self.assertEqual(r["assets_with_asset_specific_source_observations"],["oil"])
        self.assertEqual(r["approved_asset_scores"],0)
        self.assertEqual(r["independent_scoring_factor_groups_qualified"],0)
        self.assertFalse(r["validated_for_live_scoring"])
        self.assertFalse(r["eligible_for_point_in_time_backtest"])
        for a in r["assets"].values():
            self.assertIsNone(a["score"])
            self.assertIsNone(a["research_price_direction_signal"])
            self.assertFalse(a["historical_calibration_passed"])
            self.assertIn("insufficient_factor_groups",a["blocked_by"])

    def test_eia_weekly_change_is_real_thousand_barrels(self):
        n,o,cfg=fixture()
        r=build(n,o,cfg,nfci_sha="a"*64,oil_sha="b"*64,now=NOW)
        w=r["sources"]["oil_inventory"]
        self.assertEqual(w["latest_week_delta"],o[-1]["value"]-o[-2]["value"])
        self.assertAlmostEqual(w["research_4week_change_million_barrels"],
                               (o[-1]["value"]-o[-5]["value"])/1000,places=4)
        self.assertEqual(w["latest_level_unit"],"thousand_barrels")
        self.assertEqual(w["reference_104week_count"],104)

    def test_nfci_positive_is_financial_tightness_not_oas(self):
        n,o,cfg=fixture()
        r=build(n,o,cfg,nfci_sha="a"*64,oil_sha="b"*64,now=NOW)
        risk=r["sources"]["nfci"]
        self.assertEqual(risk["source_raw_sha256"],"a"*64)
        self.assertEqual(risk["series_id"],"NFCI")
        self.assertEqual(r["ice_bofa_high_yield_oas_research"],
                         "not_collected_permission_pending")
        self.assertEqual(risk["proxy_role"],
                         "financial_conditions_composite_includes_risk_credit_rates")
        self.assertFalse(risk["independent_scoring_signal_qualified"])

    def test_only_oil_has_an_asset_specific_observation(self):
        n,o,cfg=fixture()
        r=build(n,o,cfg,nfci_sha="a"*64,oil_sha="b"*64,now=NOW)
        self.assertEqual(set(r["assets"]),set(ASSETS))
        self.assertEqual([k for k,v in r["assets"].items()
                          if v["asset_specific_source_count"]],["oil"])
        self.assertTrue(all(v["independent_model_signal_coverage_pct"]==0
                            for v in r["assets"].values()))

    def test_source_ages_reported_without_backdating(self):
        n,o,cfg=fixture()
        r=build(n,o,cfg,nfci_sha="a"*64,oil_sha="b"*64,now=NOW)
        self.assertEqual(r["sources"]["nfci"]["age_calendar_days"],10)
        self.assertEqual(r["sources"]["oil_inventory"]["age_calendar_days"],10)
        self.assertTrue(r["sources"]["nfci"]["current_observation_fresh"])
        self.assertTrue(r["sources"]["oil_inventory"]["current_observation_fresh"])

    def test_stale_official_source_does_not_count_current(self):
        n,o,cfg=fixture()
        r=build(n,o,cfg,nfci_sha="a"*64,oil_sha="b"*64,
                now=NOW+timedelta(days=22))
        self.assertEqual(r["status"],"research_only_one_or_more_sources_stale")
        self.assertFalse(r["sources"]["nfci"]["current_observation_fresh"])
        self.assertFalse(r["sources"]["oil_inventory"]["current_observation_fresh"])

    def test_future_data_refused(self):
        n,o,cfg=fixture()
        with self.assertRaises(ValueError):
            build(n,o,cfg,nfci_sha="a"*64,oil_sha="b"*64,
                  now=NOW-timedelta(days=20))

    def test_missing_raw_source_hash_rejected(self):
        n,o,cfg=fixture()
        with self.assertRaisesRegex(ValueError,"digest"):
            build(n,o,cfg,nfci_sha="a"*64,oil_sha="",now=NOW)

    def test_unknown_factor_model_rejected(self):
        n,o,cfg=fixture()
        bad=copy.deepcopy(cfg)
        bad["weights"]["gold"][0]+=1
        with self.assertRaises(ValueError):
            build(n,o,bad,nfci_sha="a"*64,oil_sha="b"*64,now=NOW)

    def test_rolling_z_stays_descriptive_and_finite(self):
        n,o,cfg=fixture()
        r=build(n,o,cfg,nfci_sha="a"*64,oil_sha="b"*64,now=NOW)
        for x in r["sources"].values():
            self.assertTrue(math.isfinite(x["research_z_score"]))
            self.assertTrue(-1<=x["normalized_research_pressure"]<=1)
            self.assertFalse(x["first_publication_vintages_verified"])

    def test_zero_volatility_never_generates_fake_z(self):
        n,o,cfg=fixture()
        for i,row in enumerate(n):
            row["value"]=0.1
        r=build(n,o,cfg,nfci_sha="a"*64,oil_sha="b"*64,now=NOW)
        self.assertIsNone(r["sources"]["nfci"]["research_z_score"])
        self.assertIsNone(r["sources"]["nfci"]["normalized_research_pressure"])

    def test_strict_https_source_hosts(self):
        for url,expected in (("http://fred.stlouisfed.org/graph/fredgraph.csv?id=NFCI",
                              "fred.stlouisfed.org"),
                             (FRED_URL,"www.eia.gov"),
                             ("https://evil.example/graph/fredgraph.csv?id=NFCI",
                              "fred.stlouisfed.org")):
            with self.assertRaisesRegex(ValueError,"Unapproved source"):
                fetch_official(url,expected,opener=lambda *args,**kwargs: None)

    def test_eia_and_fred_source_urls_are_original_and_attributed(self):
        n,o,cfg=fixture()
        r=build(n,o,cfg,nfci_sha=hashlib.sha256(csv_input(n)).hexdigest(),
                oil_sha=hashlib.sha256(html_input(o)).hexdigest(),now=NOW)
        self.assertIn("fred.stlouisfed.org",r["sources"]["nfci"]["source_url"])
        self.assertIn("eia.gov",r["sources"]["oil_inventory"]["source_url"])
        self.assertEqual(r["sources"]["nfci"]["owner"],"Federal Reserve Bank of Chicago")
        self.assertEqual(r["sources"]["oil_inventory"]["owner"],
                         "U.S. Energy Information Administration")


if __name__=="__main__":
    unittest.main()
