import copy
import math
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "examples"))
import ivr_transfer_analysis as A


class TransferAnalysis(unittest.TestCase):
    def test_factorial_distinguishes_interaction_from_main_effects(self):
        times = {A.arm(c, l, z): (1 if c == "off" else .9) *
                 (1 if l == "powers" else 1.2) * (.8 if z else 1)
                 for c in ("off", "transformer_currents")
                 for l in ("powers", "bounded_observations") for z in (False, True)}
        for scale in (1e-6, 1, 1e6):
            r = A.contrasts({k: v * scale for k, v in times.items()})
            self.assertTrue(all(math.isclose(v, .8) for v in r["zero_over_retained"].values()))
            self.assertTrue(all(math.isclose(v, 1.2) for v in r["broad_over_powers"].values()))
            self.assertTrue(all(math.isclose(v, .9) for v in r["eliminated_over_explicit"].values()))
            self.assertTrue(all(math.isclose(v, 1) for v in r["zero_lifting_interaction"].values()))
        times[A.arm("off", "bounded_observations", True)] *= .75
        times[A.arm("transformer_currents", "bounded_observations", True)] *= .5
        self.assertAlmostEqual(A.contrasts(times)["three_way_interaction"], 2/3)

    def test_paired_ratios_are_not_ratios_of_medians(self):
        rows = [dict(a=1., b=2.), dict(a=10., b=1.), dict(a=100., b=30.)]
        r = A.summarize(rows, arms=("a", "b"), selected="a", reference="a")
        self.assertAlmostEqual(r["ratio_of_medians"]["b"], .2)
        self.assertAlmostEqual(r["median_paired_ratio"]["b"], .3)
        self.assertAlmostEqual(r["selector_regret"], 5.)
        self.assertFalse(r["timing_admission_verified"])
        self.assertEqual(len(r["paired_log_ratios"]["b"]), 3)

    def test_parent_weighting_does_not_count_variants_as_new_networks(self):
        base = dict(domain="supplemental", objective="cost", batch="exploration")
        rows = [dict(base, case="a", parent="A", ratio=.5),
                dict(base, case="a_variant", parent="A", ratio=.5),
                dict(base, case="b", parent="B", ratio=2.)]
        r = A.parent_summary(rows)
        self.assertEqual(r["independent_parents"], 2)
        self.assertAlmostEqual(r["geometric_mean_ratio"], 1.)
        for key in ("domain", "objective", "batch"):
            bad = copy.deepcopy(rows); bad[0][key] = "other"
            with self.assertRaises(ValueError): A.parent_summary(bad)

    def test_missing_failed_nonfinite_or_boolean_times_are_refused(self):
        for value in (0., -1., float("nan"), float("inf"), True, None):
            with self.assertRaises(ValueError): A.summarize([dict(a=value)], arms=("a",), selected="a", reference="a")
        with self.assertRaises(ValueError): A.summarize([])
        with self.assertRaises(ValueError): A.contrasts({})
        with self.assertRaises(ValueError): A.summarize([dict(a=1.)])
        with self.assertRaises(ValueError): A.parent_summary([])


if __name__ == "__main__":
    unittest.main()
