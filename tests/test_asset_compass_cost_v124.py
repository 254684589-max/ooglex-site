import unittest
from scripts.asset_compass_cost_v124 import roundtrip_return,research,parse_market
from scripts.asset_compass_quarterly_v117 import DOCS

class CostTests(unittest.TestCase):
    def test_cost_not_subtraction(self):
        self.assertAlmostEqual(roundtrip_return(10,0),10)
        self.assertAlmostEqual(roundtrip_return(10,25),9.451371571,places=7)
        self.assertLess(roundtrip_return(0,10),0)
        self.assertEqual(roundtrip_return(-100,10),-100)
    def test_same_period_correlations_and_scenarios(self):
        r=research({"A":{"2024-03":1,"2024-06":2,"2024-09":9},"B":{"2024-03":2,"2024-06":1}})
        self.assertEqual(r["common_quarters"],["2024-03","2024-06"])
        self.assertEqual(r["pairwise_correlations"]["A__B"],-1)
        self.assertEqual(r["observations_per_pair"],2)
        self.assertFalse(r["realized_execution_cost_certified"])
        self.assertGreater(r["cost_scenarios"]["A"]["0"]["mean_quarterly_return_pct"],r["cost_scenarios"]["A"]["25"]["mean_quarterly_return_pct"])
    def test_price_reconciliation_and_no_cost_claim(self):
        doc=("GLD","fixture.htm",["2024-03"],["10.00"],[])
        rows=[("Total Return, at Net Asset Value(4)","10.00"),
              ("Total Return, at Market Value(4)","9.00"),
              ("Net asset value per Share, beginning of period","100.00"),
              ("Net asset value per Share, end of period","110.00"),
              ("Market value per Share, beginning of period","100.00"),
              ("Market value per Share, end of period","109.00"),
              ("Net expenses(3)","0.40")]
        raw=("<html>SPDR<table>"+"".join(f"<tr><td>{k}</td><td>{v}</td></tr>" for k,v in rows)+"</table></html>").encode()
        r=parse_market(doc,raw)
        self.assertEqual(r["columns_reconciled"],1)
        self.assertEqual(r["maximum_rounding_gap_pct"],0)
        self.assertFalse(r["realized_execution_cost_certified"])
        with self.assertRaises(ValueError):parse_market(doc,raw.replace(b"109.00",b"108.00"))
