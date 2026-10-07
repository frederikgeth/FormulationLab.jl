"""Run with python3 -m unittest discover -s test -p 'test_ivr_mumps_factor_trace.py'."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("trace", Path(__file__).parents[1] / "examples/ivr_mumps_factor_trace.py")
trace = importlib.util.module_from_spec(spec); spec.loader.exec_module(trace)


def report(job=2, entries=100):
    header = f"Entering DMUMPS 5.9.1 from C interface with JOB, N, NNZ = {job} 20 {entries}\n"
    # Literal observed labels, independent of the parser's field mapping.
    fields = """ INFOG  (9) Real space for factors = 350
 INFOG (10) Integer space for factors = 40
 INFOG (11) Maximum front size = 12
 INFOG (29) Number of entries in factors = 250
 INFOG (12) Number of negative pivots = 9
 INFOG (13) Number of delayed pivots = 3"""
    return header + fields + "\n"


class FactorTraceTests(unittest.TestCase):
    def test_actual_is_not_storage(self):
        r = trace.parse(report())
        self.assertTrue(r["complete_factor_reports"])
        self.assertEqual(r["factors"][0]["factor_to_input_entry_ratio"], 2.5)
        self.assertEqual(r["maxima"]["real_storage"], 350)
        self.assertEqual(r["maxima"]["factor_entries"], 250)

    def test_job_counts_and_variable_matrix_size(self):
        r = trace.parse(report() + report(3) + report(entries=200))
        self.assertEqual(r["observed_job_counts"], {"2": 2, "3": 1})
        self.assertEqual([q["factor_to_input_entry_ratio"] for q in r["factors"]], [2.5, 1.25])

    def test_estimates_and_short_summaries_are_not_actuals(self):
        r = trace.parse(" -- (20) Number of entries in factors (estim.) = 999\n"
                        "Number of doubles for MUMPS to hold factorization (INFO(9)) = 999\n")
        self.assertFalse(r["available"])
        self.assertFalse(r["complete_factor_reports"])
        self.assertIsNone(r["maxima"]["factor_entries"])

    def test_truncated_report_is_retained(self):
        r = trace.parse(report() + report().split(" INFOG")[0])
        self.assertTrue(r["available"])
        self.assertFalse(r["complete_factor_reports"])
        self.assertEqual(len(r["factors"]), 2)
        self.assertIsNone(r["factors"][1]["factor_entries"])

    def test_encoded_negative_counter_is_not_interpreted(self):
        r = trace.parse(report().replace("= 250", "= -250"))
        self.assertEqual(r["factors"][0]["reported"]["factor_entries"], -250)
        self.assertIsNone(r["factors"][0]["factor_to_input_entry_ratio"])
        self.assertFalse(r["complete_factor_reports"])

    def test_zero_denominator_is_unavailable(self):
        r = trace.parse(report(entries=0))
        self.assertIsNone(r["factors"][0]["factor_to_input_entry_ratio"])
        self.assertFalse(r["complete_factor_reports"])

    def test_duplicate_counter_refuses(self):
        with self.assertRaises(ValueError):
            trace.parse(report() + " INFOG (29) Number of entries in factors = 123\n")

    def captures(self):
        second = lambda job: report(job, entries=200).replace(" 20 200", " 30 200")
        captures = {"a": report() + report(3), "b": report(3) + second(2), "process": second(3)}
        models = {"A": dict(input_order=20, input_entries=100, wrapper_factorizations=1,
                            wrapper_solves=2, primary_capture="a"),
                  "B": dict(input_order=30, input_entries=200, wrapper_factorizations=1,
                            wrapper_solves=1, primary_capture="b")}
        return captures, models

    def test_buffered_jobs_follow_signature_not_filename(self):
        captures, models = self.captures()
        r = trace.reconcile_captures(captures, models)
        self.assertTrue(r["passed"])
        self.assertFalse(r["timing_eligible"])
        self.assertEqual(r["models"]["A"]["observed_job_counts"], {"2": 1, "3": 2})
        self.assertEqual(r["models"]["B"]["observed_job_counts"], {"2": 1, "3": 1})
        self.assertEqual(r["models"]["A"]["displaced_jobs"][0]["capture"], "b")
        self.assertEqual(r["models"]["B"]["displaced_jobs"][0]["capture"], "process")
        self.assertEqual(r["models"]["A"]["maxima"]["factor_entries"], 250)
        self.assertEqual(set(r["capture_sha256"]), set(captures))

    def test_ambiguous_signatures_refuse(self):
        captures, models = self.captures()
        models["B"]["input_order"] = 20; models["B"]["input_entries"] = 100
        with self.assertRaises(ValueError): trace.reconcile_captures(captures, models)

    def test_missing_extra_and_duplicated_reports_refuse(self):
        captures, models = self.captures()
        with self.assertRaises(ValueError): trace.reconcile_captures({"a": captures["a"], "b": captures["b"]}, models)
        with self.assertRaises(ValueError): trace.reconcile_captures(dict(captures, extra=report(3)), models)
        with self.assertRaises(ValueError): trace.reconcile_captures(dict(captures, extra=report(3, entries=999)), models)
        with self.assertRaises(ValueError): trace.reconcile_captures(dict(captures, extra=report().split(" INFOG")[0]), models)

    def test_invalid_declarations_refuse(self):
        captures, models = self.captures()
        for bad in (0, -1, True, 1.0, None):
            altered = {k: dict(v) for k, v in models.items()}
            altered["A"]["wrapper_solves"] = bad
            with self.assertRaises(ValueError): trace.reconcile_captures(captures, altered)
        with self.assertRaises(ValueError): trace.reconcile_captures({}, models)
        with self.assertRaises(ValueError): trace.reconcile_captures(captures, {})


if __name__ == "__main__":
    unittest.main()
