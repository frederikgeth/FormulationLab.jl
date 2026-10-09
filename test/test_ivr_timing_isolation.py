"""Isolation admission tests use fabricated process traces, not solver timing."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("isolation", Path(__file__).resolve().parents[1] / "examples/ivr_timing_isolation.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
WORKER = dict(pid=42, parent_pid=7)


def sample(start, end, processes=None, error=None):
    return dict(start_ns=start, end_ns=end, julia_processes=[] if processes is None else processes, error=error)


def worker_fixture():
    # Fabricated data only. No solver, timer or real experimental endpoint.
    events = []
    groups = []
    for sweep, order in enumerate(([1, 2], [2, 1])):
        stage = 'warmup' if sweep == 0 else 'measurement'
        for position, arm in enumerate(order, 1):
            events.append(dict(sequence=len(events)+1, stage=stage, sweep=sweep, position=position, arm_index=arm))
        groups.append(dict(stage=stage, sweep=sweep, correctness_admitted=True,
                           comparison=dict(passed=True, physical_export_shape_equal=True, objectives_comparable=True,
                                           control_in_each_arm=[True, True], each_arm_in_control=[True, True])))
    job = dict(events=events, admission=dict(arms=[{}, {}], sweeps=[[2, 1]]),
               tolerances=dict(objective_atol=1e-6, objective_rtol=1e-8))
    trials = []
    for event in events:
        row = {k: True for k in m.GATES}
        row.update(objective=100., timing=dict(schema='FormulationLab.native_trial_timing.v1', mode='native',
                   sample_status='completed', native_ipopt_wall_s=1., synthetic_elapsed_ns=None, clock_error=None))
        trials.append(dict(event=event, trial=row, excluded_warmup=event['stage']=='warmup'))
    report = dict(schema='FormulationLab.native_timing_worker.v1', mode='native', status='completed', job=job,
                  pending_event=None, trials=trials, groups=groups, julia_threads=1, blas_threads=1, worker_pid=42)
    process = dict(WORKER, command='julia')
    trace = dict(observations=[sample(0, 10, [process]), sample(100, 110, [process])],
                 expected_worker=WORKER, max_gap_ns=500, closed=True)
    return job, report, trace


class IsolationTests(unittest.TestCase):
    def test_process_parser_handles_paths_and_rejects_partial_tables(self):
        rows = m.parse_processes("1 0 /sbin/launchd\n42 7 /Applications/Julia App/bin/julia\n43 7 julia-debug\n44 7 python3\n")
        self.assertEqual([r['pid'] for r in rows], [42, 43])
        for text in ("", "42 7", "not-a-pid 7 julia", "42 7 julia\n42 7 julia\n"):
            with self.assertRaises(ValueError):
                m.parse_processes(text)

    def test_single_worker_and_irreversible_contamination(self):
        worker = dict(WORKER, command="/usr/bin/julia")
        trace = [sample(0, 10, [worker]), sample(100, 110, [worker])]
        self.assertTrue(m.audit(trace, WORKER, 500, closed=True)['admitted'])
        other = dict(pid=99, parent_pid=8, command="julia")
        trace.append(sample(200, 210, [worker, other]))
        trace.append(sample(300, 310, [worker]))
        a = m.audit(trace, WORKER, 500, closed=True)
        self.assertFalse(a['admitted'])
        self.assertTrue(any('other_julia_process' in x for x in a['errors']))
        # Same pid, different parent is not the authorized worker.
        trace = [sample(0, 10, [dict(worker, parent_pid=9)]), sample(100, 110)]
        self.assertFalse(m.audit(trace, WORKER, 500, closed=True)['admitted'])
        self.assertFalse(m.audit([sample(0, 10), sample(100, 110)], WORKER, 500, closed=True)['admitted'])
        self.assertFalse(m.audit([sample(0, 10, ['broken']), sample(100, 110)], None, 500, closed=True)['admitted'])

    def test_missing_gaps_query_failures_and_clock_errors_fail_closed(self):
        traces = [[], [sample(0, 10)], [sample(0, 10), sample(1000, 1010)],
                  [sample(0, 600), sample(650, 660)], [sample(100, 110), sample(10, 20)],
                  [sample(0, 10), sample(100, 110, error="permission denied")],
                  [sample(0, 10), sample(None, None)]]
        for trace in traces:
            self.assertFalse(m.audit(trace, None, 500, closed=True)['admitted'])
        self.assertFalse(m.audit([sample(0, 10), sample(100, 110)], None, 500, closed=False)['admitted'])

    def test_monitor_lifecycle_and_reader_error(self):
        tick = iter(range(0, 1000, 10))
        monitor = m.Monitor(interval_s=0.1, max_gap_s=1, reader=lambda: [], clock=lambda: next(tick))
        monitor.start()
        result = monitor.stop()
        self.assertTrue(result['admitted'])
        with self.assertRaises(RuntimeError):
            monitor.start()
        with self.assertRaises(RuntimeError):
            monitor.stop()
        def broken():
            raise PermissionError('process query refused')
        monitor = m.Monitor(reader=broken)
        monitor.start()
        self.assertFalse(monitor.stop()['admitted'])

    def test_entire_campaign_rejected_not_clean_subset(self):
        clean = m.audit([sample(0, 10), sample(100, 110)], None, 500, closed=True)
        dirty = copy.deepcopy(clean)
        dirty['admitted'] = False
        self.assertTrue(m.campaign_isolation({'a': clean, 'b': clean}, ['a', 'b'])['admitted'])
        self.assertFalse(m.campaign_isolation({'a': clean, 'b': dirty}, ['a', 'b'])['admitted'])
        self.assertFalse(m.campaign_isolation({'a': clean}, ['a', 'b'])['admitted'])
        self.assertFalse(m.campaign_isolation({'a': clean}, ['a', 'a'])['admitted'])
        self.assertFalse(m.campaign_isolation({}, [])['admitted'])

    def test_worker_audit_recomputes_gates_not_aggregate_flags(self):
        job, report, _ = worker_fixture()
        self.assertTrue(m.audit_worker(report, job)['admitted'])
        changes = [lambda r: r['trials'].pop(),
                   lambda r: r['trials'].reverse(),
                   lambda r: r['trials'][0].update(excluded_warmup=False),
                   lambda r: r['trials'][2]['trial'].update(physical_passed=False),
                   lambda r: r['trials'][2]['trial']['timing'].update(native_ipopt_wall_s=float('nan')),
                   lambda r: r['trials'][2]['trial']['timing'].update(mode='synthetic'),
                   lambda r: r['groups'][1]['comparison'].update(each_arm_in_control=[True, False]),
                   lambda r: r['groups'][1]['comparison'].update(each_arm_in_control=[1, 1]),
                   lambda r: r.update(julia_threads=True)]
        for change in changes:
            bad = copy.deepcopy(report)
            change(bad)
            bad['provisional_admitted'] = True
            self.assertFalse(m.audit_worker(bad, job)['admitted'])
        # Reject a mismatch that an erroneous atol+rtol rule would admit.
        bad = copy.deepcopy(report)
        bad['trials'][2]['trial']['objective'] += 1.5e-6
        self.assertFalse(m.audit_worker(bad, job)['admitted'])

    def test_campaign_reconciles_raw_trace_worker_pid_and_complete_job_set(self):
        job, report, trace = worker_fixture()
        self.assertTrue(m.audit_campaign({'a': report}, {'a': trace}, {'a': job})['admitted'])
        dirty = copy.deepcopy(trace)
        dirty['observations'][1]['julia_processes'].append(dict(pid=99, parent_pid=8, command='julia'))
        result = m.audit_campaign({'a': report, 'b': report}, {'a': trace, 'b': dirty}, {'a': job, 'b': job})
        self.assertFalse(result['admitted'])
        self.assertTrue(result['isolation_audits']['a']['admitted'])
        self.assertFalse(m.audit_campaign({'a': report}, {'a': trace}, {'a': job, 'b': job})['admitted'])
        bad = copy.deepcopy(report)
        bad['worker_pid'] = 99
        self.assertFalse(m.audit_campaign({'a': bad}, {'a': trace}, {'a': job})['admitted'])
        self.assertFalse(m.audit_campaign({'a': report}, {'a': {}}, {'a': job})['admitted'])


if __name__ == '__main__':
    unittest.main()
