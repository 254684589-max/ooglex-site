import unittest
from datetime import date
from scripts.update_nyfed_recession import extract
from scripts.archive_asset_compass_observations import rows_from_snapshot
class NYFedRecessionTests(unittest.TestCase):
    def test_target_date_is_not_observation_date(self):
        data=extract([(date(2027,10,1),.12415814430091168)],date(2026,11,22))
        self.assertEqual(data["observation_period"],"2026-10")
        self.assertEqual(data["target_period"],"2027-10")
        self.assertAlmostEqual(data["probability_percent"],12.415814,places=5)
        self.assertFalse(data["official_forecast"])
        self.assertFalse(data["release_timestamp_verified"])
    def test_invalid_probability_not_accepted(self):
        with self.assertRaisesRegex(ValueError,"No recent"):
            extract([(date(2027,10,1),12.4)],date(2026,11,22))
        with self.assertRaisesRegex(ValueError,"No recent"):
            extract([(date(2027,10,1),-0.1)],date(2026,11,22))
    def test_no_future_observation(self):
        with self.assertRaisesRegex(ValueError,"No recent"):
            extract([(date(2028,12,1),0.5)],date(2026,11,22))
    def test_old_observation_rejected(self):
        with self.assertRaisesRegex(ValueError,"No recent"):
            extract([(date(2023,1,1),.6)],date(2026,11,22))
    def test_archive_month_keeps_first_seen_not_release(self):
        sample=extract([(date(2027,10,1),.1241581443)],date(2026,11,22))
        rows=rows_from_snapshot({"schema_version":1,"rates":{},"source_urls":[],"nyfed_recession_model":sample},"2026-11-22T12:00:00Z")
        self.assertEqual(len(rows),1)
        self.assertEqual(rows[0]["series_id"],"nyfed_recession.probability")
        self.assertEqual(rows[0]["observation_period"],"2026-10")
        self.assertFalse(rows[0]["official_release_time_known"])
if __name__=="__main__":unittest.main()
