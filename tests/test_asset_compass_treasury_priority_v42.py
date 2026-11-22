"""V42 source priority tests; network is never requested in unit tests."""
import unittest
from datetime import date
from pathlib import Path
from unittest.mock import patch

from scripts.build_asset_compass_history_resilient_v42 import build_prefer_treasury


class PriorityV42Tests(unittest.TestCase):
    def test_primary_treasury_success_never_calls_fred(self):
        called=[]
        def direct(years,output):
            called.append(("direct",tuple(years)))
            return {"source":"U.S. Department of the Treasury"}
        def fallback(**kw):
            called.append(("fallback",))
            raise AssertionError("H15 must not replace good Treasury observations")
        with patch("scripts.build_asset_compass_history_resilient_v42.validate"):
            result=build_prefer_treasury(Path("/tmp/unused.json"),today=date(2026,11,22),direct=direct,fallback=fallback)
        self.assertEqual(result["source"],"U.S. Department of the Treasury")
        self.assertEqual(called,[("direct",tuple(range(2021,2027)))])

    def test_bounded_macro_ci_window_and_fallback_year(self):
        dates=[]
        def direct(years,output):
            dates.extend(years)
            raise ConnectionResetError("peer closed")
        years=[]
        def fallback(**kwargs):
            years.append(kwargs["start_year"])
            return {"source":"Federal Reserve Board H.15 via FRED"}
        with patch("scripts.build_asset_compass_history_resilient_v42.validate"):
            build_prefer_treasury(Path("/tmp/unused.json"),today=date(2026,11,22),
                start_year=2025,direct=direct,fallback=fallback)
        self.assertEqual(dates,[2025,2026])
        self.assertEqual(years,[2025])

    def test_direct_disconnect_uses_explicit_h15_source(self):
        called=[]
        def direct(*args):
            raise ConnectionResetError("official CSV peer disconnected")
        def fallback(**kw):
            called.append(kw["start_year"])
            return {"source":"Federal Reserve Board H.15 via FRED"}
        with patch("scripts.build_asset_compass_history_resilient_v42.validate"):
            result=build_prefer_treasury(Path("/tmp/unused.json"),today=date(2026,11,22),direct=direct,fallback=fallback)
        self.assertEqual(result["source"],"Federal Reserve Board H.15 via FRED")
        self.assertEqual(called,[2024])

    def test_bad_fallback_source_never_silently_accepted(self):
        with patch("scripts.build_asset_compass_history_resilient_v42.validate"):
            with self.assertRaisesRegex(ValueError,"unexpected source"):
                build_prefer_treasury(Path("/tmp/unused.json"),today=date(2026,11,22),
                  direct=lambda *args: (_ for _ in ()).throw(OSError("blocked")),
                  fallback=lambda **kwargs:{"source":"Unverified scraper"})


if __name__=="__main__":unittest.main()
