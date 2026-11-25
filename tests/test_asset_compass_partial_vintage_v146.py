import unittest
from decimal import Decimal
from scripts.asset_compass_partial_vintage_v146 import cutoff,pair_rows,compare,collect
from scripts.asset_compass_sec_returns_v66 import months

class PartialVintageTests(unittest.TestCase):
    def test_cutoff_and_lag(self):
        self.assertEqual(cutoff("2024-03"),"2024-02-29")
        row={"month":"2024-04","x":[1,2,3,4.5,4.0,6],"y":2}
        snap={"CPIAUCNS":{"2024-03-31":{"2024-02":Decimal("105"),"2023-02":Decimal("100")}},
              "UNRATE":{"2024-03-31":{"2024-02":Decimal("3.9")}}}
        a,b,gaps,diffs=pair_rows([row],snap)
        self.assertEqual(a[0]["x"],[1,2,3,4.5,4.0,6])
        self.assertEqual(b[0]["x"],[1,2,3,5,3.9,6])
        self.assertEqual(gaps,[])
        snap["UNRATE"]={}
        self.assertEqual(pair_rows([row],snap)[2],["2024-04"])
    def test_matched_identical_features_give_identical_results(self):
        from scripts.asset_compass_monthly_diagnostic_v69 import prev
        rows=[];snap={"CPIAUCNS":{},"UNRATE":{}}
        for i,m in enumerate(months("2022-03","2025-12")):
            p=prev(m,2);year=prev(p,12)
            c=Decimal(100+i%11);u=Decimal(3+i%13)/2
            rows.append({"month":m,"x":[float(i%3),float(i%5),float(i%7),float(c-100),float(u),float(i%17)],"y":float(i%19)})
            snap["CPIAUCNS"][cutoff(m)]={p:c,year:Decimal(100)}
            snap["UNRATE"][cutoff(m)]={p:u}
        r=compare(rows,snap)
        self.assertTrue(r["current_and_vintage_same_folds"])
        self.assertGreater(r["evaluated_months"],0)
        self.assertEqual(r["vintage_minus_current_mae_pct"],0)
        self.assertFalse(r["formal_oos_validated"])
    def test_missing_download_not_fabricated(self):
        def bad(url):raise ValueError("bad response")
        s,receipts,fail=collect(["2024-04"],fetcher=bad,wait=lambda _:None)
        self.assertEqual(s,{"CPIAUCNS":{},"UNRATE":{}})
        self.assertEqual(receipts,[])
        self.assertEqual(len(fail),2)
