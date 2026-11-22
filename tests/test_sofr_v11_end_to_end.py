"""V11 end-to-end offline release gate for the production SOFR pipeline.

All rates below are SYNTHETIC TEST FIXTURES ONLY, kept in isolated temporary
files, never written to the repository or displayed as market data.
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts"
YEARS = (2, 3, 5, 7, 10, 30)
FIELDS = {2:"BC_2YEAR",3:"BC_3YEAR",5:"BC_5YEAR",7:"BC_7YEAR",10:"BC_10YEAR",30:"BC_30YEAR"}
BASE = json.loads((ROOT/"macro/swap-spreads-history.json").read_text(encoding="utf-8"))


def swap_fixture(day, rate=4.5):
    return {"date":day,"curve":[
        {"date":day,"tenor":str(y)+"Y","rate":rate,
         "method":"close" if y!=2 else "close-thin"} for y in YEARS
    ]}


def treasury_fixture(day):
    contents="".join("<d:%s>4.70</d:%s>"%(FIELDS[y],FIELDS[y]) for y in YEARS)
    return ('<feed xmlns:d="urn:test"><entry><d:NEW_DATE>'+day+
            'T00:00:00</d:NEW_DATE>'+contents+'</entry></feed>')


def exec_py(script,*args):
    return subprocess.run([sys.executable,str(SCRIPT/script),*map(str,args)],
                          cwd=str(ROOT),capture_output=True,text=True,timeout=15)


class PipelineReleaseGate(unittest.TestCase):
    def setUp(self):
        self.work=tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.temp=Path(self.work.name)
        self.history=self.temp/"history.json"
        self.history.write_text(json.dumps(BASE),encoding="utf-8")
        self.swap=self.temp/"ois.json"
        self.xml=self.temp/"treasury.xml"
        self.log=self.temp/"ingest.log"
        self.evidence=self.temp/"evidence.json"
        self.health=self.temp/"health.json"

    def set_fixture(self,day,rate=4.5):
        self.swap.write_text(json.dumps(swap_fixture(day,rate)),encoding="utf-8")
        self.xml.write_text(treasury_fixture(day),encoding="utf-8")

    def ingest(self):
        proc=exec_py("update_swap_spreads.py","--swap-json",self.swap,
                     "--treasury-xml",self.xml,"--output",self.history)
        self.log.write_text(proc.stdout+proc.stderr,encoding="utf-8")
        return proc

    def evidence_step(self,exit_code):
        return exec_py("report_swap_spread_ingest.py","--history",self.history,
                       "--ingest-log",self.log,"--ingest-exit",exit_code,
                       "--output",self.evidence,"--run-id","v11-offline-fixture")

    def health_step(self):
        return exec_py("publish_swap_spread_health.py","--evidence",self.evidence,
                       "--output",self.health)

    def test_synthetic_new_day_end_to_end(self):
        day="2026-11-24"
        self.set_fixture(day)
        p=self.ingest()
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertIn("APPENDED "+day,p.stdout)
        obs=json.loads(self.history.read_text(encoding="utf-8"))["observations"]
        self.assertEqual(len(obs),len(BASE["observations"])+1)
        self.assertEqual(obs[-1]["asOf"],day)
        self.assertEqual(len(obs[-1]["tenors"]),6)
        self.assertEqual(self.evidence_step(0).returncode,0)
        report=json.loads(self.evidence.read_text(encoding="utf-8"))
        self.assertEqual(report["ingestionResult"],"new_observation")
        self.assertEqual(self.health_step().returncode,0)
        status=json.loads(self.health.read_text(encoding="utf-8"))
        self.assertEqual(status["lastDataAsOf"],day)
        self.assertEqual(status["runResult"],"new_observation")
        self.assertNotIn("tenors",status)

    def test_matching_prior_day_is_idempotent(self):
        old=BASE["observations"][0]
        day=old["asOf"]
        self.swap.write_text(json.dumps({"date":day,"curve":[{
            "date":day,"tenor":str(r["years"])+"Y",
            "rate":r["swap"],"method":r["method"]
        } for r in old["tenors"]]}),encoding="utf-8")
        contents="".join("<d:%s>%s</d:%s>"%
                         (FIELDS[r["years"]],r["treasury"],FIELDS[r["years"]])
                         for r in old["tenors"])
        self.xml.write_text('<feed xmlns:d="urn:test"><entry><d:NEW_DATE>'+day+
                            '</d:NEW_DATE>'+contents+'</entry></feed>',encoding="utf-8")
        before=self.history.read_bytes()
        p=self.ingest()
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertIn("UNCHANGED "+day,p.stdout)
        self.assertEqual(self.history.read_bytes(),before)
        self.assertEqual(self.evidence_step(0).returncode,0)
        self.assertEqual(json.loads(self.evidence.read_text())["ingestionResult"],"no_new_observation")
        self.assertEqual(self.health_step().returncode,0)

    def test_revision_fails_closed_and_cannot_publish_heartbeat(self):
        old=BASE["observations"][0]
        day=old["asOf"]
        self.swap.write_text(json.dumps({"date":day,"curve":[{
            "date":day,"tenor":str(r["years"])+"Y","rate":r["swap"]+0.1,
            "method":r["method"]
        } for r in old["tenors"]]}),encoding="utf-8")
        contents="".join("<d:%s>%s</d:%s>"%
                         (FIELDS[r["years"]],r["treasury"],FIELDS[r["years"]])
                         for r in old["tenors"])
        self.xml.write_text('<feed xmlns:d="urn:test"><entry><d:NEW_DATE>'+day+
                            '</d:NEW_DATE>'+contents+'</entry></feed>',encoding="utf-8")
        before=self.history.read_bytes()
        p=self.ingest()
        self.assertNotEqual(p.returncode,0)
        self.assertEqual(self.history.read_bytes(),before)
        self.assertEqual(self.evidence_step(p.returncode).returncode,0)
        report=json.loads(self.evidence.read_text())
        self.assertEqual(report["ingestionResult"],"source_revision_conflict")
        self.assertNotEqual(self.health_step().returncode,0)
        self.assertFalse(self.health.exists())

    def test_source_date_mismatch_cannot_change_data_or_health(self):
        self.set_fixture("2026-11-24")
        self.xml.write_text(treasury_fixture("2026-11-23"),encoding="utf-8")
        before=self.history.read_bytes()
        p=self.ingest()
        self.assertNotEqual(p.returncode,0)
        self.assertEqual(before,self.history.read_bytes())
        self.assertEqual(self.evidence_step(p.returncode).returncode,0)
        self.assertEqual(json.loads(self.evidence.read_text())["ingestionResult"],"date_mismatch")
        self.assertNotEqual(self.health_step().returncode,0)
        self.assertFalse(self.health.exists())


if __name__=="__main__":
    unittest.main()
