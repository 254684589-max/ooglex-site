"""V29 prevent verified auxiliary data from vanishing during Treasury rebuilds."""
import unittest
from datetime import datetime, timedelta, timezone

from scripts.update_asset_scores import retain_recent_auxiliary


class RetentionV29Tests(unittest.TestCase):
    NOW=datetime(2026,11,22,8,0,tzinfo=timezone.utc)

    def base(self, **fields):
        return {"schema_version":1, **fields}

    def stamp(self, hours=2):
        return (self.NOW-timedelta(hours=hours)).isoformat()

    def pce(self, **kwargs):
        return {"retrieved_at":self.stamp(),
                "core_pce":{"observation_period":"2026-10","value":126.4},
                **kwargs}

    def h41(self, **kwargs):
        return {"retrieved_at":self.stamp(),
                "total_assets":{"observation_date":"2026-11-18",
                                "value_millions_usd":7000000},**kwargs}

    def liquid(self, **kwargs):
        return {"retrieved_at":self.stamp(),
                "reserves":{"observation_date":"2026-11-18","value":3000000},
                "tga":{"observation_date":"2026-11-18","value":700000},
                "overnight_rrp":{"observation_date":"2026-11-20","value":0},
                **kwargs}

    def recession(self, **kwargs):
        return {"retrieved_at":self.stamp(),"observation_period":"2026-10",
                "probability_percent":18.7,**kwargs}

    def test_all_four_recent_verified_sections_survive(self):
        sections=self.base(bea=self.pce(),fed_h41=self.h41(),
                           liquidity=self.liquid(),
                           nyfed_recession_model=self.recession())
        result=retain_recent_auxiliary(sections,self.NOW)
        self.assertEqual(set(result),{"bea","fed_h41","liquidity",
                                      "nyfed_recession_model"})
        self.assertEqual(result["liquidity"]["overnight_rrp"]["value"],0)

    def test_old_fetch_is_dropped_even_with_recent_observation(self):
        old=self.pce(retrieved_at=self.stamp(73))
        self.assertEqual(retain_recent_auxiliary(self.base(bea=old),self.NOW),{})

    def test_unknown_fetch_timestamp_cannot_be_used(self):
        block=self.pce(retrieved_at="unknown")
        self.assertEqual(retain_recent_auxiliary(self.base(bea=block),self.NOW),{})

    def test_future_fetch_is_rejected(self):
        block=self.h41(retrieved_at=self.stamp(-2))
        self.assertEqual(retain_recent_auxiliary(self.base(fed_h41=block),self.NOW),{})

    def test_naive_fetch_timestamp_is_rejected(self):
        block=self.h41(retrieved_at="2026-11-22T06:00:00")
        self.assertEqual(retain_recent_auxiliary(self.base(fed_h41=block),self.NOW),{})

    def test_stale_pce_month_rejected(self):
        block=self.pce(core_pce={"observation_period":"2026-01","value":123.4})
        self.assertEqual(retain_recent_auxiliary(self.base(bea=block),self.NOW),{})

    def test_stale_h41_observation_rejected(self):
        block=self.h41(total_assets={"observation_date":"2026-10-01",
                                     "value_millions_usd":7000000})
        self.assertEqual(retain_recent_auxiliary(self.base(fed_h41=block),self.NOW),{})

    def test_only_fresh_liquidity_components_survive(self):
        block=self.liquid(tga={"observation_date":"2026-10-01","value":700000},
                          overnight_rrp={"observation_date":"2026-11-01","value":0})
        retained=retain_recent_auxiliary(self.base(liquidity=block),self.NOW)
        self.assertEqual(set(retained["liquidity"]),{"retrieved_at","reserves"})

    def test_empty_liquidity_dropped(self):
        block=self.liquid(reserves={"observation_date":"2026-10-01","value":10},
                          tga={"observation_date":"2026-10-01","value":20},
                          overnight_rrp={"observation_date":"2026-10-01","value":0})
        self.assertEqual(retain_recent_auxiliary(self.base(liquidity=block),self.NOW),{})

    def test_unknown_schema_fails_closed(self):
        r=self.base(bea=self.pce())
        r["schema_version"]=999
        self.assertEqual(retain_recent_auxiliary(r,self.NOW),{})

    def test_missing_retrieval_provenance_not_preserved(self):
        record=self.pce()
        del record["retrieved_at"]
        self.assertEqual(retain_recent_auxiliary(self.base(bea=record),self.NOW),{})

    def test_old_recession_observation_rejected(self):
        block=self.recession(observation_period="2025-11")
        self.assertEqual(retain_recent_auxiliary(
            self.base(nyfed_recession_model=block),self.NOW),{})


if __name__=="__main__":
    unittest.main()
