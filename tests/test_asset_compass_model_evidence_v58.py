"""V58 official H10 USD parsing and complete research scoring evidence matrix."""
import copy
import hashlib
import json
import math
import unittest
import io
import zipfile
from datetime import date,datetime,timedelta,timezone
from pathlib import Path

from scripts.build_asset_compass_usd_v58 import build,parse_csv,parse_fed_xml,URL,FED_XML_URL
from scripts.build_asset_compass_model_evidence_v58 import produce,PATHS

ROOT=Path(__file__).resolve().parents[1]
NOW=datetime(2026,11,23,9,0,tzinfo=timezone.utc)


def usd_series(n=570):
    first=date(2024,1,2)
    rows=[]
    d=first
    while len(rows)<n:
        if d.weekday()<5:
            i=len(rows)
            rows.append({"date":d.isoformat(),"index":round(120+0.018*i+math.sin(i/17),6)})
        d+=timedelta(days=1)
    return rows

def as_csv(rows,header="observation_date,DTWEXBGS"):
    return (header+"\n"+"\n".join(f"{r['date']},{r['index']}" for r in rows)+"\n").encode()


class V58EvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg=json.loads((ROOT/"macro/model-config.json").read_text())
        cls.inputs={k:json.loads(p.read_text(encoding="utf-8"))
                    for k,p in PATHS.items() if k!="v58_usd"}

    def validated_usd(self):
        rows=usd_series()
        now=datetime.fromisoformat(rows[-1]["date"]+"T12:00:00+00:00")
        return build(rows,self.cfg,raw_sha="a"*64,now=now)

    def docs(self):
        d=copy.deepcopy(self.inputs)
        d["v58_usd"]=self.validated_usd()
        return d

    def test_original_federal_reserve_sdmx_zip_series_attribute(self):
        rows=usd_series()
        xml="<Root><Series SERIES_NAME='JRXWTFB_N.B'>"+ "".join(
          f"<Obs TIME_PERIOD='{r['date']}' OBS_VALUE='{r['index']}'/>" for r in rows
        )+"</Series><Series SERIES_NAME='JRXWTFN_N.B'><Obs TIME_PERIOD='2026-11-13' OBS_VALUE='101.0'/></Series></Root>"
        out=io.BytesIO()
        with zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED) as z:
            z.writestr("H10.xml",xml)
        self.assertEqual(parse_fed_xml(out.getvalue()),rows)

    def test_original_federal_reserve_nested_sdmx_key_and_source_disclosure(self):
        rows=usd_series()
        xml="<Root><Series><SeriesKey><Value id='SERIES_NAME' value='JRXWTFB_N.B'/></SeriesKey>"+ "".join(
          f"<Obs TIME_PERIOD='{r['date']}' OBS_VALUE='{r['index']}'/>" for r in rows
        )+"</Series></Root>"
        out=io.BytesIO()
        with zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED) as z:
            z.writestr("h10_data.xml",xml)
        self.assertEqual(parse_fed_xml(out.getvalue()),rows)
        result=build(rows,self.cfg,raw_sha="a"*64,source_kind="fed_original_xml",now=NOW)
        self.assertEqual(result["original_source_format"],"fed_original_xml")
        self.assertEqual(result["source_url"],FED_XML_URL)
        self.assertIsNone(result["official_asset_score"])

    def test_original_frb_h10_nd_missing_minus9999_is_not_an_index_value(self):
        rows=usd_series()
        xml="<Root><Series SERIES_NAME='JRXWTFB_N.B'>"
        xml+="<Obs TIME_PERIOD='2007-01-02' OBS_VALUE='-9999' OBS_STATUS='ND'/>"
        xml+="".join(f"<Obs TIME_PERIOD='{r['date']}' OBS_VALUE='{r['index']}' OBS_STATUS='A'/>" for r in rows)
        xml+="</Series></Root>"
        out=io.BytesIO()
        with zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED) as z:z.writestr("H10.xml",xml)
        self.assertEqual(parse_fed_xml(out.getvalue()),rows)

    def test_original_frb_h10_undocumented_negative_sentinel_must_fail(self):
        rows=usd_series()
        xml="<Root><Series SERIES_NAME='JRXWTFB_N.B'>"
        xml+="<Obs TIME_PERIOD='2007-01-02' OBS_VALUE='-9999' OBS_STATUS='A'/>"
        xml+="".join(f"<Obs TIME_PERIOD='{r['date']}' OBS_VALUE='{r['index']}'/>" for r in rows)
        xml+="</Series></Root>"
        out=io.BytesIO()
        with zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED) as z:z.writestr("H10.xml",xml)
        with self.assertRaisesRegex(ValueError,"Invalid Federal Reserve XML"):
            parse_fed_xml(out.getvalue())

    def test_unrelated_original_sdmx_series_is_not_mislabeled_usd(self):
        raw=io.BytesIO()
        with zipfile.ZipFile(raw,"w",zipfile.ZIP_DEFLATED) as z:
            z.writestr("H10.xml","<Root><Series SERIES_NAME='JRXWTFN_N.B'><Obs TIME_PERIOD='2026-11-13' OBS_VALUE='100'/></Series></Root>")
        with self.assertRaisesRegex(ValueError,"missing"):
            parse_fed_xml(raw.getvalue())

    def test_source_csv_parses_correct_official_series(self):
        a=usd_series()
        self.assertEqual(parse_csv(as_csv(a)),a)

    def test_source_csv_date_header_compatibility(self):
        a=usd_series()
        self.assertEqual(parse_csv(as_csv(a,"DATE,DTWEXBGS")),a)

    def test_foreign_series_must_be_refused(self):
        with self.assertRaisesRegex(ValueError,"Required"):
            parse_csv(as_csv(usd_series(),"DATE,BAMLH0A0HYM2"))

    def test_future_pit_or_infinite_index_cannot_enter(self):
        v=as_csv(usd_series()).replace(b"120.0\n",b"nan\n")
        with self.assertRaises(ValueError):
            parse_csv(v)

    def test_duplicate_daily_record_rejected(self):
        a=usd_series();a.append(copy.deepcopy(a[-1]))
        with self.assertRaisesRegex(ValueError,"duplicate"):
            parse_csv(as_csv(a))

    def test_no_fabricated_history_short_series(self):
        with self.assertRaisesRegex(ValueError,"Insufficient"):
            parse_csv(as_csv(usd_series()[:100]))

    def test_only_h10_authentic_index_is_not_dollar_total_return(self):
        r=self.validated_usd()
        self.assertEqual(r["source_series_id"],"DTWEXBGS")
        self.assertEqual(r["asset_id"],"usd")
        self.assertEqual(r["prior_baseline_count"],252)
        self.assertIsInstance(r["research_z_score"],float)
        self.assertIsNone(r["official_asset_score"])
        self.assertFalse(r["historical_first_publication_vintages_verified"])
        self.assertFalse(r["independent_signal_verified"])
        self.assertFalse(r["sample_out_of_sample_calibration_passed"])
        self.assertFalse(r["eligible_for_point_in_time_backtest"])

    def test_21_session_calculation_matches_input(self):
        data=usd_series();r=self.validated_usd()
        self.assertAlmostEqual(r["daily_observed_last_21_session_change_points"],
                          data[-1]["index"]-data[-22]["index"],6)

    def test_zero_std_does_not_invent_z_score(self):
        data=usd_series()
        for row in data:row["index"]=120.0
        r=build(data,self.cfg,raw_sha="b"*64,now=NOW)
        self.assertIsNone(r["research_z_score"])
        self.assertIsNone(r["research_normalized_candidate"])

    def test_source_hash_and_future_rejected(self):
        data=usd_series()
        with self.assertRaisesRegex(ValueError,"digest"):
            build(data,self.cfg,raw_sha="",now=NOW)
        with self.assertRaisesRegex(ValueError,"Future"):
            build(data,self.cfg,raw_sha="a"*64,now=datetime(2022,1,1,tzinfo=timezone.utc))

    def test_real_v54_to_v57_inputs_produce_four_source_assets(self):
        r=produce(self.docs(),now=NOW)
        self.assertEqual(r["asset_specific_observed_count"],4)
        self.assertEqual(r["asset_specific_missing_count"],2)
        self.assertEqual(set(r["asset_specific_observed_assets"]),
                         {"gold","us_long_bonds","usd","oil"})
        self.assertEqual(set(r["asset_specific_missing_assets"]),
                         {"us_equities","bitcoin"})
        self.assertEqual(r["macro_observation_group_count"],6)
        self.assertEqual(r["audited_asset_total_return_count"],0)
        self.assertEqual(r["oos_validated_assets"],0)
        self.assertEqual(r["official_0_to_100_scores_published"],0)
        self.assertFalse(r["qualified_for_live_scoring"])

    def test_every_asset_retains_null_score_and_four_real_blockers(self):
        r=produce(self.docs(),now=NOW)
        for asset,row in r["research_assets"].items():
            self.assertIsNone(row["official_score"])
            self.assertEqual(row["model_qualified_weight_pct"],0)
            self.assertFalse(row["point_in_time_provenance_verified"])
            self.assertFalse(row["investable_total_return_verified"])
            self.assertFalse(row["out_of_sample_backtest_verified"])
            self.assertIn("historical_calibration_not_passed",row["blocked_by"])
        self.assertEqual(r["historical_first_release_certified_source_count"],0)

    def test_fake_v57_asset_score_cannot_self_approve(self):
        d=self.docs();d["v57"]["assets"]["gold"]["score"]=70
        with self.assertRaises(ValueError):
            produce(d,now=NOW)

    def test_fake_v56_pit_approval_is_rejected(self):
        d=self.docs();d["v56"]["source_vintages_qualified"]=4
        with self.assertRaises(ValueError):
            produce(d,now=NOW)

    def test_fake_h10_approval_is_rejected(self):
        d=self.docs();d["v58_usd"]["independent_signal_verified"]=True
        with self.assertRaises(ValueError):
            produce(d,now=NOW)

    def test_fake_v54_lineage_rejected(self):
        d=self.docs();d["v54"]["source_snapshot_generated_at"]="2024-01-01T00:00:00Z"
        with self.assertRaises(ValueError):
            produce(d,now=NOW)

    def test_fake_v57_upsized_coverage_rejected(self):
        d=self.docs();d["v57"]["asset_specific_source_available_assets"].append("bitcoin")
        with self.assertRaises(ValueError):
            produce(d,now=NOW)

    def test_old_snapshot_cannot_be_declared_calibrated(self):
        d=self.docs();d["snapshot"]["scoring"]["out_of_sample_verified"]=True
        with self.assertRaises(ValueError):
            produce(d,now=NOW)

    def test_missing_return_or_pit_license_not_implicitly_promoted(self):
        r=produce(self.docs(),now=NOW)
        self.assertIn("legal_rights",r["blockers"])
        self.assertIn("total_returns",r["blockers"])
        self.assertIn("point_in_time_history",r["blockers"])
        self.assertIn("out_of_sample",r["blockers"])

if __name__=="__main__":
    unittest.main()
