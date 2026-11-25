import unittest
from scripts.asset_compass_sec_performance_v84 import numbers,quarterly,monthly,MONTHS,SOURCES,REFERENCES
from decimal import Decimal

class SecPerformanceTests(unittest.TestCase):
    def test_accounting_cells(self):
        self.assertEqual(numbers(["January","","(2.17",")%","3.25","%"]),[Decimal("-2.17"),Decimal("3.25")])
    def test_quarterly_frequency_and_ref(self):
        raw=b'<html>SPDR<table><tr><td>Total Return, at Net Asset Value(4)</td><td>(12.72</td><td>)%</td><td>5.43</td><td>4.94</td><td>24.63</td></tr></table></html>'
        r=quarterly("GLD",raw)
        self.assertEqual(len(r["quarterly_observations"]),2)
        self.assertTrue(r["not_monthly_labels"])
        self.assertIsNone(r["official_score"])
        with self.assertRaises(ValueError):quarterly("GLD",raw.replace(b"12.72",b"13.72"))
    def test_synthetic_month_table_and_annual_check(self):
        cfg=SOURCES["USO"]
        out={}
        text='<html>United States Oil Fund<table><tr><td>Month</td>'+''.join(f'<td>{y}</td>' for y in cfg["years"])+'</tr>'
        for i,name in enumerate(MONTHS,1):
            text+=f'<tr><td>{name}</td>'
            for y in cfg["years"]:
                key=f"{y}-{i:02d}"
                if key>cfg["last"]:continue
                v=Decimal(REFERENCES["USO"].get(key,"0.00"))
                out[key]=v;text+=f'<td>{v:.2f}</td>'
            text+='</tr>'
        text+='<tr><td>Annual Rate of Return</td>'
        for y in cfg["years"]:
            c=Decimal(1)
            for k,v in out.items():
                if k.startswith(str(y)):c*=1+v/100
            text+=f'<td>{(c-1)*100:.2f}</td>'
        text+='</tr></table></html>'
        r=monthly("USO",text.encode())
        self.assertEqual(r["parsed_months"],62)
        self.assertFalse(r["investable_total_return_certified"])
        with self.assertRaises(ValueError):monthly("USO",text.replace("17.76","17.75").encode())
