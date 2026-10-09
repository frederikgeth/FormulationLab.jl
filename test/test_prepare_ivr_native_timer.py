"""Source-copy contract tests; no installed solver or optimizer is required."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "examples/prepare_ivr_native_timer.py"
spec = importlib.util.spec_from_file_location("native_timer_preparation", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class InstrumentationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.wrapper = self.source / m.WRAPPER
        self.wrapper.parent.mkdir(parents=True)
        # Algorithm fixture, deliberately not represented as the pinned Ipopt source.
        self.data = (m.INCLUDE + m.ENTRY + "    prepare_starts()\n" + m.CALL + "end\n").encode()
        self.wrapper.write_bytes(self.data)
        (self.source / "LICENSE").write_text("preserve this file\n")
        self.helper = self.root / "timer.jl"
        self.helper.write_text("module TimerFixture end\n")
        self.guard = patch.object(m, "TESTED_WRAPPER_SHA256", m.digest(self.data))
        self.guard.start()
        self.addCleanup(self.guard.stop)

    def test_guard_and_exact_restoration(self):
        patched = m.instrument(self.data).decode()
        self.assertIn("    prepare_starts()\n", patched)
        for original, instrumented in reversed([
            (m.INCLUDE, m.INSTRUMENTED_INCLUDE),
            (m.ENTRY, m.INSTRUMENTED_ENTRY),
            (m.CALL, m.INSTRUMENTED_CALL),
        ]):
            self.assertEqual(patched.count(instrumented), 1)
            patched = patched.replace(instrumented, original)
        self.assertEqual(patched.encode(), self.data)
        with self.assertRaisesRegex(ValueError, "unsupported"):
            m.instrument(self.data + b"# source drift\n")

    def test_missing_and_ambiguous_anchors_refused(self):
        for data in (self.data.replace(m.CALL.encode(), b""), self.data + m.CALL.encode()):
            with patch.object(m, "TESTED_WRAPPER_SHA256", m.digest(data)):
                with self.assertRaisesRegex(ValueError, "exactly one"):
                    m.instrument(data)

    def test_copy_inventory_and_default_permissions(self):
        before = m.source_inventory(self.source)
        output = self.root / "copy"
        result = m.prepare(self.source, output, self.helper)
        self.assertEqual(m.source_inventory(self.source), before)
        self.assertEqual(result["original_file_sha256"], before)
        copied = m.source_inventory(output)
        manifest_name = "FORMULATIONLAB_INSTRUMENTATION.json"
        copied.pop(manifest_name)  # The provenance file does not hash itself.
        self.assertEqual(copied, result["instrumented_file_sha256"])
        changed = {p for p in before.keys() | copied.keys() if before.get(p) != copied.get(p)}
        self.assertEqual(changed, {str(m.WRAPPER), str(m.WRAPPER.parent / "ivr_native_timer.jl")})
        self.assertEqual(json.loads((output / manifest_name).read_text()), result)
        self.assertEqual(result["recording_default"], "disabled")
        for key in ("optimizer_invoked", "timing_authorized", "execution_ready"):
            self.assertFalse(result[key])

    def test_existing_or_nested_output_refused_before_write(self):
        for output in (self.source, self.source / "nested", self.root):
            before = m.source_inventory(self.source)
            with self.assertRaisesRegex(ValueError, "new output directory"):
                m.prepare(self.source, output, self.helper)
            self.assertEqual(m.source_inventory(self.source), before)

    def test_drift_refused_without_output(self):
        self.wrapper.write_bytes(self.data + b"# drift\n")
        output = self.root / "copy"
        with self.assertRaisesRegex(ValueError, "unsupported"):
            m.prepare(self.source, output, self.helper)
        self.assertFalse(output.exists())

    def test_read_only_source_file_is_preserved(self):
        self.wrapper.chmod(0o444)
        original_mode = self.wrapper.stat().st_mode
        result = m.prepare(self.source, self.root / "copy", self.helper)
        self.assertEqual(self.wrapper.stat().st_mode, original_mode)
        self.assertEqual(self.wrapper.read_bytes(), self.data)
        self.assertTrue(result["numerical_source_restoration_verified"])

    def test_helper_collision_refused_without_output(self):
        (self.wrapper.parent / "ivr_native_timer.jl").write_text("existing\n")
        output = self.root / "copy"
        with self.assertRaisesRegex(ValueError, "already contains"):
            m.prepare(self.source, output, self.helper)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
