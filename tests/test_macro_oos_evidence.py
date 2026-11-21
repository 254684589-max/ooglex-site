import unittest
from scripts.audit_asset_compass_oos_evidence import (
    inspect_evidence, wilson, binomial_pvalue
)

def diagnostic(n=8,overlap=False):
    folds=[]
    for i in range(n):
        year=2016+i
        # Dates intentionally kept disjoint across year windows.
        start=f"{year}-01-01" if not overlap or i==0 else f"{year-1}-01-01"
        end=f"{year}-04-01"
        folds.append({"active_signal_count":12,
          "test_first_entry":start,"test_last_entry":end,
          "training_last_label_exit":f"{year-1}-12-01",
          "directional_accuracy":.5,"constant_long_accuracy":.5})
    return {"report_type":"expanding_window_research_diagnostic",
            "results":{"gold":{"status":"research_diagnostic_not_validated","folds":folds}}}

def manifest():
    return {"evidence":{
        "original_release_timestamp_archive":True,
        "independent_macro_vintage_verification":True,
        "license_for_statistical_derived_publication":True,
        "investable_total_return_conventions":True,
        "out_of_sample_not_used_for_model_selection":True,
        "multi_regime_classification_verified":True,
        "costs_slippage_rolls_documented":True},
        "independent_auditor":{"identity":"External Reviewer","reviewed_at":"2026-11-22",
                               "evidence_reference":"review-id"}}

class StatisticalEvidenceTests(unittest.TestCase):
    def test_wilson_interval(self):
        lower,upper=wilson(60,100)
        self.assertLess(lower,.6)
        self.assertGreater(upper,.6)
        self.assertAlmostEqual(lower,.502,delta=.02)
    def test_exact_binomial_half(self):
        self.assertAlmostEqual(binomial_pvalue(5,5),1/32)
        self.assertAlmostEqual(binomial_pvalue(0,5),1)
        self.assertAlmostEqual(binomial_pvalue(3,5),.5)
    def test_no_manual_self_certification(self):
        x=inspect_evidence(diagnostic(),manifest())
        self.assertFalse(x["validated_for_live_scoring"])
        self.assertFalse(x["assets"]["gold"]["eligible_for_public_scoring"])
        self.assertIn("external_evidence_and_governance_not_verified",x["assets"]["gold"]["blockers"])
    def test_no_source_evidence_fails(self):
        x=inspect_evidence(diagnostic(),{})
        self.assertIn("missing_original_release_timestamp_archive",x["assets"]["gold"]["blockers"])
        self.assertIn("missing_independent_review_evidence",x["assets"]["gold"]["blockers"])
    def test_overlapping_folds_flagged(self):
        x=inspect_evidence(diagnostic(overlap=True),manifest())
        self.assertFalse(x["assets"]["gold"]["folds_date_nonoverlap"])
        self.assertIn("overlapping_test_folds",x["assets"]["gold"]["blockers"])
    def test_insufficient_folds_flagged(self):
        x=inspect_evidence(diagnostic(n=2),manifest())
        self.assertIn("insufficient_independent_folds",x["assets"]["gold"]["blockers"])
    def test_leaky_training_label_fails(self):
        d=diagnostic()
        d["results"]["gold"]["folds"][0]["training_last_label_exit"]="2016-01-01"
        with self.assertRaisesRegex(ValueError,"leakage"):
            inspect_evidence(d,manifest())
    def test_invalid_pvalues_rejected(self):
        with self.assertRaises(ValueError):
            binomial_pvalue(6,5)
        with self.assertRaises(ValueError):
            wilson(9,4)
    def test_missing_asset_results_fail_closed(self):
        x=inspect_evidence({"report_type":"expanding_window_research_diagnostic","results":{}},manifest())
        self.assertEqual(x["assets"],{})
        self.assertFalse(x["oos_backtest_certified"])
if __name__=="__main__":unittest.main()
