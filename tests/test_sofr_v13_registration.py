"""V13 local fixtures: registration metadata cannot impersonate a scheduled run."""
import importlib.util
from datetime import datetime,timezone
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("registration",ROOT/"scripts"/"audit_sofr_workflow_registration.py")
audit=importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
NOW=datetime(2026,11,23,4,0,tzinfo=timezone.utc)
FILES={v["path"]:(ROOT/v["path"]).read_text(encoding="utf-8") for v in audit.SPECS.values()}
META={path:{"path":path,"state":"active","name":"SOFR production"} for path in FILES}
class RegistrationTests(unittest.TestCase):
    def test_both_workflows_must_be_active(self):
        r=audit.examine(audit.SPECS,FILES,META,"main",NOW)
        self.assertEqual(r["status"],"verified_active_registration")
        self.assertFalse(r["runsVerified"])
        self.assertFalse(r["marketDataChanged"])
        self.assertTrue(all(v["verified"] for v in r["workflows"].values()))
    def test_disabled_cron_is_blocker(self):
        modified={k:dict(v) for k,v in META.items()}
        modified[audit.SPECS["ingestion"]["path"]]["state"]="disabled_manually"
        r=audit.examine(audit.SPECS,FILES,modified,"main",NOW)
        self.assertEqual(r["status"],"registration_blocked")
        self.assertIn("workflow_not_active",r["workflows"]["ingestion"]["errors"])
    def test_unregistered_workflow_is_not_success(self):
        modified={k:v for k,v in META.items() if "watchdog" not in k}
        r=audit.examine(audit.SPECS,FILES,modified,"main",NOW)
        self.assertIn("github_workflow_not_registered",r["workflows"]["watchdog"]["errors"])
    def test_wrong_cron_and_missing_main_guard(self):
        path=audit.SPECS["ingestion"]["path"]
        modified=dict(FILES)
        modified[path]=modified[path].replace("35 3 * * 2-6","35 2 * * 2-6")
        modified[path]=modified[path].replace("github.ref == 'refs/heads/main'","github.ref == 'refs/heads/staging'")
        r=audit.examine(audit.SPECS,modified,META,"main",NOW)
        self.assertIn("cron_mismatch",r["workflows"]["ingestion"]["errors"])
        self.assertIn("main_branch_guard_missing",r["workflows"]["ingestion"]["errors"])
    def test_wrong_default_branch_fails(self):
        with self.assertRaisesRegex(ValueError,"not main"):
            audit.examine(audit.SPECS,FILES,META,"dev",NOW)
    def test_wrong_registered_path(self):
        altered={k:dict(v) for k,v in META.items()}
        altered[audit.SPECS["watchdog"]["path"]]["path"]=".github/workflows/other.yml"
        r=audit.examine(audit.SPECS,FILES,altered,"main",NOW)
        self.assertIn("registered_path_mismatch",r["workflows"]["watchdog"]["errors"])
if __name__=="__main__":unittest.main()
