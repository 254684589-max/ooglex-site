import unittest
from decimal import Decimal
from scripts.asset_compass_alfred_v138 import parse,url_for
from scripts.asset_compass_full_vintage_v153 import last_in_month,triple_rows,compare

class FullVintageTests(unittest.TestCase):
    def test_daily_and_weekly_frequency(self):
        day=["2024-03-31"]
        raw=b"observation_date,DGS10_20240331\n2024-02-28,4.2\n2024-02-29,4.3\n2024-04-01,.\n"
        r=parse(raw,"DGS10",day)
        self.assertEqual(r[day[0]]["2024-02-29"],Decimal("4.3"))
        self.assertIn("id=DGS10",url_for("DGS10",day))
        with self.assertRaises(ValueError):parse(raw.replace(b"2024-04-01,.",b"2024-04-01,4.4"),"DGS10",day)
        with self.assertRaises(ValueError):parse(raw.replace(b"2024-02-28",b"2024-02-25"),"DGS10",day)
        raw=b"observation_date,NFCI_20240331\n2024-02-23,-0.5\n"
        self.assertEqual(parse(raw,"NFCI",day)[day[0]]["2024-02-23"],Decimal("-0.5"))
        with self.assertRaises(ValueError):parse(raw.replace(b"2024-02-23",b"2024-02-22"),"NFCI",day)
    def test_month_end_no_stale_and_no_future(self):
        self.assertIsNone(last_in_month({"2024-02-01":Decimal(1)},"2024-02","2024-03-31"))
        self.assertEqual(last_in_month({"2024-02-23":Decimal(1),"2024-02-29":Decimal(2)},"2024-02","2024-03-31"),("2024-02-29",Decimal(2)))
        with self.assertRaises(ValueError):last_in_month({"2024-04-01":Decimal(1)},"2024-02","2024-03-31")
    def test_six_replacements_and_missing(self):
        d="2024-03-31"
        def dec(rows):return {d:{k:Decimal(v) for k,v in rows.items()}}
        s={"CPIAUCNS":dec({"2023-02":100,"2024-02":105}),"UNRATE":dec({"2024-02":"3.9"}),
           "DGS10":dec({"2024-01-31":"4.0","2024-02-29":"4.2"}),
           "DTWEXBGS":dec({"2024-01-31":100,"2024-02-29":101}),
           "NFCI":dec({"2024-02-23":"-0.5"}),"WALCL":dec({"2024-01-31":1000,"2024-02-28":990})}
        row={"month":"2024-04","x":[0,0,0,0,0,0],"y":2}
        a,b,c,gaps,diffs=triple_rows([row],s)
        self.assertEqual(c[0]["x"],[20,1,-0.5,5,3.9,-1])
        self.assertEqual(b[0]["x"],[0,0,0,5,3.9,0])
        self.assertEqual(gaps,[])
        self.assertFalse(compare([row],s)["formal_oos_validated"])
        s["WALCL"]={}
        a,b,c,gaps,_=triple_rows([row],s)
        self.assertEqual(a+b+c,[])
        self.assertEqual(gaps,[{"month":"2024-04","missing_series":["WALCL"]}])
