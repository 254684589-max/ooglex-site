"""Offline contract tests for source-matched SOFR/Treasury historical snapshots."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("swap_ingest", Path(__file__).resolve().parents[1] / "scripts" / "update_swap_spreads.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

ROWS = [(2, 4.46, 4.63), (3, 4.44, 4.65), (5, 4.41, 4.71), (7, 4.44, 4.80), (10, 4.51, 4.92), (30, 4.64, 5.31)]
DATE = "2026-11-20"


def swap_payload(asof=DATE):
    return {"date": asof, "curve": [
        {"date": asof, "tenor": str(y) + "Y", "rate": swap, "method": "close-thin" if y == 2 else "close"}
        for y, swap, _ in ROWS]}


def xml_fixture():
    cells = "".join("<d:%s>%.2f</d:%s>" % (mod.TREASURY_FIELDS[y], t, mod.TREASURY_FIELDS[y])
                    for y, _, t in ROWS)
    return ('<feed xmlns:d="urn:treasury-test"><entry><d:NEW_DATE>2026-11-20T00:00:00</d:NEW_DATE>'
            + cells + '</entry></feed>').encode()


class SwapHistoryTests(unittest.TestCase):
    def test_valid_matched_date_and_formula(self):
        rates = mod.treasury_by_day(xml_fixture())
        got = mod.build_observation(swap_payload(), rates)
        self.assertEqual(len(got["tenors"]), 6)
        self.assertAlmostEqual(got["tenors"][0]["spreadBp"], -17.0)
        self.assertAlmostEqual(got["tenors"][4]["spreadBp"], -41.0)

    def test_different_date_never_combined(self):
        with self.assertRaisesRegex(ValueError, "matching"):
            mod.build_observation(swap_payload("2026-11-19"), mod.treasury_by_day(xml_fixture()))

    def test_reject_derived(self):
        s = swap_payload()
        s["curve"][0]["method"] = "derived"
        with self.assertRaisesRegex(ValueError, "derived"):
            mod.build_observation(s, mod.treasury_by_day(xml_fixture()))

    def test_duplicate_tenor_is_rejected(self):
        s = swap_payload()
        s["curve"].append(s["curve"][0])
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            mod.build_observation(s, mod.treasury_by_day(xml_fixture()))

    def test_idempotent_and_append_only(self):
        observation = mod.build_observation(swap_payload(), mod.treasury_by_day(xml_fixture()))
        doc = {"observations": []}
        first, changed = mod.update_document(doc, observation, "2026-11-22T00:00:00Z")
        self.assertTrue(changed)
        _, changed = mod.update_document(first, observation, "2026-11-23T00:00:00Z")
        self.assertFalse(changed)
        corrupted = {"asOf": DATE, "quality": "indicative", "tenors": []}
        with self.assertRaisesRegex(ValueError, "changed"):
            mod.update_document(first, corrupted, "2026-11-23T00:00:00Z")

    def test_older_day_never_overwrites(self):
        observation = mod.build_observation(swap_payload(), mod.treasury_by_day(xml_fixture()))
        old = dict(observation, asOf="2026-11-19")
        with self.assertRaisesRegex(ValueError, "older"):
            mod.update_document({"observations": [observation]}, old, "2026-11-22T00:00:00Z")


if __name__ == "__main__":
    unittest.main()
