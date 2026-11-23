"""B/C official-origin series parser, independent failure and no synthetic value tests."""
import unittest
from datetime import datetime,timezone
from scripts.update_macro_bc_official_v1 import parse,collect,SPEC

NOW=datetime(2026,11,23,9,tzinfo=timezone.utc)
def fixture(sid,missing=False):
    if missing:return b"<html>bad</html>"
    return (f"observation_date,{sid}\n2026-11-19,1.5\n2026-11-20,1.7\n").encode()
class BCOfficialTests(unittest.TestCase):
    def test_parse_both_fred_headers_and_missing_values(self):
        rows,last,total=parse(b"DATE,ICSA\n2026-11-19,120000\n2026-11-20,.\n","ICSA",NOW,20)
        self.assertEqual(last["date"],"2026-11-19")
        self.assertEqual(len(rows),1)
        self.assertEqual(total,1)
    def test_reject_nonfinite_duplicate_future_and_html(self):
        for raw in (b"DATE,ICSA\n2026-11-20,NaN\n",
                    b"DATE,ICSA\n2026-11-20,1\n2026-11-20,2\n",
                    b"DATE,ICSA\n2026-11-24,1\n",
                    b"<html>maintenance</html>"):
            with self.assertRaises(ValueError):
                parse(raw,"ICSA",NOW,20)
    def test_eight_fresh_series_one_error_is_explicit(self):
        def fetch(url):
            from urllib.parse import parse_qs,urlparse
            sid=parse_qs(urlparse(url).query)["id"][0]
            return fixture(sid,missing=(sid=="INDPRO"))
        d=collect(fetch,NOW)
        self.assertEqual(d["accepted_series_count"],7)
        self.assertEqual(len(d["failed_sources"]),1)
        self.assertIn("美国工业生产指数",d["failed_sources"])
        self.assertFalse(d["historical_pit_certified"])
        self.assertFalse(d["validated_for_live_scoring"])
        self.assertFalse(d["redistribution_rights_independently_approved"])
    def test_all_sources_invalid_fails_without_overwriting(self):
        with self.assertRaises(RuntimeError):
            collect(lambda url:b"maintenance",NOW)
if __name__=="__main__":unittest.main()
