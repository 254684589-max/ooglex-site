"""V12 deterministic digest-manifest and live mismatch regression tests."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from scripts.verify_macro_live_v12 import FILES,manifest,inspect

SHA="1234567890abcdef1234567890abcdef12345678"

class V12Tests(unittest.TestCase):
    def test_build_manifest_hashes_actual_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for i,path in enumerate(FILES):
                p=root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(f"actual-{i}".encode())
            doc=manifest(root,SHA,123,1)
            self.assertEqual(len(doc["files"]),len(FILES))
            self.assertEqual(doc["source_commit"],SHA)
            self.assertFalse(doc["validated_for_live_scoring"])
            self.assertEqual(len(set(doc["files"].values())),len(FILES))
    def test_live_modified_content_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for i,path in enumerate(FILES):
                p=root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(f"actual-{i}".encode())
            doc=manifest(root,SHA,123,1)
        def fake(url):
            path=url.split("?")[0].replace("https://test.example/","")
            if path=="data/asset-compass-deploy-v12.json":return json.dumps(doc)
            return "wrong" if path==FILES[0] else "actual-"+str(FILES.index(path))
        with patch("scripts.verify_macro_live_v12.get",side_effect=fake):
            result=inspect("https://test.example",SHA,attempts=1,delay=0)
        self.assertEqual(result["status"],"fail")
        self.assertEqual(result["issues"][0]["category"],"content_hash_mismatch")
    def test_live_unavailable_manifest_blocks(self):
        with patch("scripts.verify_macro_live_v12.get",side_effect=OSError("offline")):
            result=inspect("https://test.example",SHA,attempts=1,delay=0)
        self.assertEqual(result["status"],"fail")
        self.assertFalse(result["checks"])

if __name__=="__main__":unittest.main()
