"""Launcher refusals and hold/release tests; never launches a Julia solver."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

EXAMPLES = Path(__file__).resolve().parents[1] / 'examples'
sys.path.insert(0, str(EXAMPLES))
import ivr_timing_launcher as L


def jobs():
    return {key: dict(admission=dict(family='C_candidates', id='fixture', workload='power', contrast='fixed', batch=batch))
            for key, batch in [('job_001.json', 'exploration'), ('job_002.json', 'confirmation')]}


class LauncherTests(unittest.TestCase):
    def test_authorization_is_explicit_hash_bound_complete_and_ordered(self):
        record = dict(schema='FormulationLab.timing_authorization.v1', authorized=True, freeze_sha256='frozen',
                      human_instruction_reference='FABRICATED UNIT TEST ONLY', output='/tmp/fixture', jobs=list(jobs()))
        self.assertEqual(L.authorize(record, 'frozen', jobs(), '/tmp/fixture'), list(jobs()))
        for change in [dict(authorized=False), dict(authorized=1), dict(freeze_sha256='other'),
                       dict(human_instruction_reference=''), dict(output='/tmp/other'),
                       dict(jobs=['job_001.json']), dict(jobs=list(reversed(jobs()))),
                       dict(jobs=['job_001.json', 'job_001.json']), dict(jobs=['unknown'])]:
            with self.assertRaises(ValueError):
                L.authorize(dict(record, **change), 'frozen', jobs(), '/tmp/fixture')

    def test_native_refusal_precedes_process_creation(self):
        with patch.object(L.subprocess, 'Popen') as spawn:
            with self.assertRaisesRegex(ValueError, 'frozen authorization'):
                L.launch_one('missing', 'hash', 'env', 'julia', '/tmp/never-created', mode='native')
            spawn.assert_not_called()
        with tempfile.TemporaryDirectory() as d, patch.object(L.subprocess, 'Popen') as spawn:
            root = Path(d)
            freeze = root/'freeze.json';auth = root/'authorization.json'
            L.save(freeze, dict(schema='FormulationLab.native_execution_freeze.v1', execution_ready=False))
            with self.assertRaisesRegex(ValueError, 'not ready'):
                L.run_campaign(freeze, L.sha(freeze), auth, root/'out')
            L.save(freeze, dict(schema='FormulationLab.native_execution_freeze.v1', execution_ready=True, jobs={}))
            L.save(auth, dict(authorized=False))
            with self.assertRaisesRegex(ValueError, 'explicit human'):
                L.run_campaign(freeze, L.sha(freeze), auth, root/'out')
            self.assertFalse((root/'out').exists())
            spawn.assert_not_called()

    def test_runtime_bytes_membership_and_aliases_are_bound(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d).resolve();tree = root/'source';tree.mkdir();source = tree/'src.jl';source.write_text('source')
            runtime = dict(schema='FormulationLab.timing_runtime.v1', julia_threads=1, blas_threads=1,
                           files_sha256={str(source): L.sha(source)}, path_aliases={}, trees={str(tree): ['src.jl']})
            L.verify_runtime(runtime, copy.deepcopy(runtime))
            source.write_text('drift')
            with self.assertRaisesRegex(ValueError, 'frozen bytes'):
                L.verify_runtime(runtime)
            source.write_text('source');extra = tree/'injected.jl';extra.write_text('injected')
            with self.assertRaisesRegex(ValueError, 'membership'):
                L.verify_runtime(runtime)
            extra.unlink()
            alias=root/'alias';alias.symlink_to(source)
            runtime['path_aliases'][str(alias)] = str(source)
            L.verify_runtime(runtime)
            alias.unlink();alias.symlink_to(root/'elsewhere')
            with self.assertRaisesRegex(ValueError, 'alias'):
                L.verify_runtime(runtime)

    def test_bootstrap_cannot_exec_before_release_and_preserves_pid(self):
        with tempfile.TemporaryDirectory() as d:
            marker = Path(d)/'executed'
            command = [sys.executable, '-c', 'import os,sys;open(sys.argv[1],"w").write(str(os.getpid()))', str(marker)]
            with subprocess.Popen([sys.executable, str(EXAMPLES/'ivr_timing_launcher.py'), '_bootstrap', json.dumps(command)],
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as child:
                with self.assertRaises(subprocess.TimeoutExpired):
                    child.wait(timeout=0.1)
                self.assertFalse(marker.exists())
                stdout, stderr = child.communicate('exec\n', timeout=10)
                self.assertEqual(child.returncode, 0, stderr)
                self.assertEqual(int(marker.read_text()), child.pid)
            marker.unlink()
            result = subprocess.run([sys.executable, str(EXAMPLES/'ivr_timing_launcher.py'), '_bootstrap', json.dumps(command)],
                input='run\n', capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(marker.exists())


if __name__ == '__main__':
    unittest.main()
