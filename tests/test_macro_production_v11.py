"""V11 acceptance regression checks with simulated HTTP bodies (no network)."""
import json
import socket
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

from scripts.verify_macro_live_v11 import classify, validate_manifest, examine, PATHS

SHA="1234567890abcdef1234567890abcdef12345678"

class ProductionV11Tests(unittest.TestCase):
    def test_manifest_commit_match_required(self):
        d={"schema_version":1,"report_type":"ooglex_macro_public_deploy_v11",
           "source_commit":SHA,"validated_for_live_scoring":False}
        self.assertEqual(validate_manifest(d,SHA),d)
        with self.assertRaises(ValueError):
            validate_manifest(dict(d,source_commit="bad"),SHA)
        with self.assertRaises(ValueError):
            validate_manifest(dict(d,validated_for_live_scoring=True),SHA)

    def test_dns_and_not_found_are_classified(self):
        self.assertEqual(classify(URLError(socket.gaierror(-2,"no name")))[0],"dns")
        self.assertEqual(classify(HTTPError("https://a",404,"Not Found",{},None))[0],"http_404")

    def test_complete_matching_simulated_deployment(self):
        d={"schema_version":1,"report_type":"ooglex_macro_public_deploy_v11",
           "source_commit":SHA,"validated_for_live_scoring":False}
        def answer(url):
            path=url.split("?")[0].replace("https://example.org","")
            if path=="/data/asset-compass-deploy-v11.json":return json.dumps(d)
            kind,expected=PATHS[path]
            if kind=="json":return json.dumps({"report_type":expected,"validated_for_live_scoring":False})
            return " ".join(expected)
        with patch("scripts.verify_macro_live_v11.get",side_effect=answer):
            checks=examine("https://example.org",SHA,attempts=1,delay=0)
        self.assertTrue(all(x["status"]=="pass" for x in checks))

    def test_live_version_drift_fails(self):
        def fake(url):
            if "asset-compass-deploy-v11.json" in url:
                return json.dumps({"schema_version":1,"report_type":"ooglex_macro_public_deploy_v11",
                                   "source_commit":"different_sha","validated_for_live_scoring":False})
            raise URLError(socket.gaierror(-2,"DNS"))
        with patch("scripts.verify_macro_live_v11.get",side_effect=fake):
            checks=examine("https://example.org",SHA,attempts=1,delay=0)
        self.assertEqual(checks[0]["code"],"version_mismatch")
        self.assertEqual(checks[1]["code"],"dns")
        self.assertTrue(all(x["status"]=="fail" for x in checks))

if __name__=="__main__":unittest.main()
