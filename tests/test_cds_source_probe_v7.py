import unittest
import urllib.error
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"scripts"))
from cds_source_probe_v7 import HEADERS,tullett_schema,probe

def html(rows,header=HEADERS):
    def tr(r): return "<tr>"+"".join("<td>"+x+"</td>" for x in r)+"</tr>"
    return ("<table>"+tr(header)+"".join(tr(r) for r in rows)+"</table>").encode()

class TestProbe(unittest.TestCase):
    def row(self,day="2026-11-20"):
        return [day,"SC","SYNTHETIC","SYNTHETIC","1","1","1","1","P5Y","1","100","USD","SprdBsisPts"]
    def test_shape(self):
        r=tullett_schema(html([self.row()]))
        self.assertEqual(r,{"state":"html_report_schema_confirmed","report_date":"2026-11-20","publication_enabled":False})
    def test_header_missing(self):
        self.assertEqual(tullett_schema(b"<html>Loading</html>")["state"],"schema_not_confirmed")
    def test_mixed_dates(self):
        self.assertEqual(tullett_schema(html([self.row(),self.row("2026-11-21")]))["state"],"no_single_date_report")
    def test_invalid_date(self):
        self.assertEqual(tullett_schema(html([self.row("2026-02-30")]))["state"],"schema_not_confirmed")
    def test_empty(self):
        self.assertEqual(tullett_schema(html([]))["state"],"no_single_date_report")
    def test_not_admitted(self):
        r=probe("bloomberg",lambda url:b"<html/>")
        self.assertFalse(r["publication_enabled"])
        self.assertEqual(r["state"],"entrance_reachable_report_not_verified")
    def test_failure(self):
        def fail(url): raise urllib.error.URLError("offline")
        self.assertEqual(probe("ice",fail)["state"],"network_error")
if __name__=="__main__":unittest.main()
