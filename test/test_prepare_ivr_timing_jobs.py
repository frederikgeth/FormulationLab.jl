"""Finite scheduling and source-integrity tests; no solver dependencies."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "examples/prepare_ivr_timing_jobs.py"
spec = importlib.util.spec_from_file_location("timing_jobs", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def job():
    return dict(correctness_qualified=True, timing_authorized=False, executable=False,
                arms=[dict(name="control"), dict(name="candidate")], solver_settings=[{}, {}],
                sweeps=[[1, 2], [2, 1]], counts=dict(warmup=2, measured=4, total=6))


class PreparationTests(unittest.TestCase):
    def test_complete_order_and_warmup_exclusion(self):
        j = job()
        original = copy.deepcopy(j)
        rows = m.events(j)
        self.assertEqual(j, original)
        self.assertEqual([r["arm_index"] for r in rows], [1, 2, 1, 2, 2, 1])
        self.assertEqual([r["sequence"] for r in rows], list(range(1, 7)))
        self.assertEqual([r["sweep"] for r in rows], [0, 0, 1, 1, 2, 2])
        self.assertEqual(sum(r["stage"] == "warmup" for r in rows), 2)
        self.assertEqual(sum(r["stage"] == "measurement" for r in rows), 4)

    def test_refuses_ambiguous_or_incomplete_schedule(self):
        changes = [lambda j: j["sweeps"].append([1, 1]),
                   lambda j: j["sweeps"].append([True, 2]),
                   lambda j: j["sweeps"].append([1, 3]),
                   lambda j: j["sweeps"].clear(),
                   lambda j: j["solver_settings"].pop(),
                   lambda j: j["arms"][1].update(name="control"),
                   lambda j: j["counts"].update(total=7)]
        for change in changes:
            j = job()
            change(j)
            with self.assertRaises(ValueError):
                m.events(j)

    def test_not_an_authorization_adapter(self):
        for key, value in (("correctness_qualified", False), ("correctness_qualified", 1),
                           ("timing_authorized", True), ("executable", True)):
            j = job()
            j[key] = value
            with self.assertRaises(ValueError):
                m.events(j)

    def test_archive_refuses_drift_missing_and_added_files(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            f = root / "src.jl"
            f.write_text("original")
            hashes = {"src.jl": m.sha(f)}
            m.archive_check(root, hashes)
            f.write_text("changed")
            with self.assertRaises(ValueError):
                m.archive_check(root, hashes)
            f.write_text("original")
            extra = root / "injected.jl"
            extra.write_text("new include")
            with self.assertRaises(ValueError):
                m.archive_check(root, hashes)
            extra.unlink()
            f.unlink()
            with self.assertRaises(ValueError):
                m.archive_check(root, hashes)

    def test_ledger_bytes_checked_before_output(self):
        with tempfile.TemporaryDirectory() as d:
            ledger = Path(d) / "ledger.json"
            ledger.write_text('{}')
            output = Path(d) / "jobs"
            with self.assertRaisesRegex(ValueError, "changed evidence"):
                m.prepare(ledger, "wrong", output)
            self.assertFalse(output.exists())
            with self.assertRaisesRegex(ValueError, "unknown ledger schema"):
                m.prepare(ledger, m.sha(ledger), output)
            self.assertFalse(output.exists())

    def test_nested_and_symlinked_protected_outputs_refused(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d) / "archive"
            root.mkdir()
            link = Path(d) / "alias"
            link.symlink_to(root, target_is_directory=True)
            for output in (root, root / "jobs", link / "jobs"):
                with self.assertRaisesRegex(ValueError, "outside protected"):
                    m.outside_protected(output, root)
            m.outside_protected(Path(d) / "safe", root)


if __name__ == "__main__":
    unittest.main()
