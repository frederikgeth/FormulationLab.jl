"""Read-only, fail-closed process-isolation observations for finite campaigns.

This module neither launches nor terminates workers. Polling has finite temporal
resolution: a clean trace is sampled evidence, not proof that no shorter-lived
process existed between observations. Freeze interval/gap limits before timing.
"""
from pathlib import Path
import re
import math
import subprocess
import threading
import time

JULIA = re.compile(r"julia(?:-debug|-[0-9.]+)?(?:\.exe)?", re.IGNORECASE)


def parse_processes(text):
    rows = []
    seen = set()
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.strip().split(None, 2)
        if len(parts) != 3:
            raise ValueError("incomplete process row")
        pid, parent = int(parts[0]), int(parts[1])
        if pid <= 0 or parent < 0 or pid in seen:
            raise ValueError("invalid or duplicate process identity")
        seen.add(pid)
        command = parts[2]
        if JULIA.fullmatch(Path(command).name):
            rows.append(dict(pid=pid, parent_pid=parent, command=command))
    if not seen:
        raise ValueError("empty process table")
    return rows


def read_processes():
    result = subprocess.run(["/bin/ps", "-axo", "pid=,ppid=,comm="],
                            check=True, capture_output=True, text=True, timeout=2)
    return parse_processes(result.stdout)


def audit(observations, expected_worker, max_gap_ns, *, closed):
    """Recompute admission from raw observations, never trust a cached clean flag."""
    errors = []
    if type(max_gap_ns) is not int or max_gap_ns <= 0:
        raise ValueError("positive integer gap limit required")
    if expected_worker is not None and (set(expected_worker) != {"pid", "parent_pid"} or
            any(type(expected_worker[k]) is not int or expected_worker[k] <= 0 for k in expected_worker)):
        raise ValueError("invalid expected worker identity")
    if closed is not True or len(observations) < 2:
        errors.append("incomplete_monitor")
    previous_end = None
    worker_seen = False
    for i, sample in enumerate(observations):
        start, end = sample.get("start_ns"), sample.get("end_ns")
        valid_ticks = type(start) is int and type(end) is int and 0 <= start <= end
        if not valid_ticks:
            errors.append(f"invalid_clock:{i}")
        else:
            if end - start > max_gap_ns:
                errors.append(f"slow_process_query:{i}")
            # Conservative gap: start of prior query to end of current query.
            if previous_end is not None and (start < previous_end or end - previous_start > max_gap_ns):
                errors.append(f"monitoring_gap:{i}")
            previous_start, previous_end = start, end
        if sample.get("error") is not None or not isinstance(sample.get("julia_processes"), list):
            errors.append(f"process_query_failed:{i}")
            continue
        for process in sample["julia_processes"]:
            if not isinstance(process, dict) or not all(type(process.get(k)) is int for k in ("pid", "parent_pid")):
                errors.append(f"malformed_process:{i}")
                continue
            if (expected_worker is None or
                    (process.get("pid"), process.get("parent_pid")) !=
                    (expected_worker["pid"], expected_worker["parent_pid"])):
                errors.append(f"other_julia_process:{i}:{process.get('pid')}")
            else:
                worker_seen = True
    if expected_worker is not None and not worker_seen:
        errors.append("expected_worker_not_observed")
    return dict(schema="FormulationLab.sampled_isolation_audit.v1", admitted=not errors,
                closed=closed, observations=len(observations), errors=errors,
                max_gap_ns=max_gap_ns, expected_worker=expected_worker,
                limitation="Processes whose entire lifetime falls between snapshots may be missed; sampled isolation only.")


class Monitor:
    """One fixed worker identity; unrelated Julia processes are never stopped.

    Establish the worker PID before starting native work. The calling launcher
    must keep the worker waiting until start() has completed its first query.
    Admission remains false until stop() records a final query and closes the trace.
    """
    def __init__(self, expected_worker=None, *, interval_s=0.2, max_gap_s=1.0,
                 reader=read_processes, clock=time.monotonic_ns):
        if not (0 < interval_s < max_gap_s) or max_gap_s == float("inf"):
            raise ValueError("finite positive interval below gap limit required")
        self.expected_worker = expected_worker
        self.interval_s = interval_s
        self.max_gap_ns = int(max_gap_s * 1e9)
        audit([], expected_worker, self.max_gap_ns, closed=False)
        self.reader, self.clock = reader, clock
        self.observations = []
        self.closed = False
        self._stop = threading.Event()
        self._thread = None

    def observe(self):
        start = self.clock()
        try:
            processes, error = self.reader(), None
        except Exception as exc:
            processes, error = None, f"{type(exc).__name__}: {exc}"
        end = self.clock()
        self.observations.append(dict(start_ns=start, end_ns=end, julia_processes=processes, error=error))

    def _loop(self):
        try:
            while not self._stop.wait(self.interval_s):
                self.observe()
        except Exception as exc:
            # A clock/monitor failure must be explicit, even if the worker finishes.
            self.observations.append(dict(start_ns=None, end_ns=None,
                                          julia_processes=None, error=f"monitor_failure: {exc}"))

    def start(self):
        if self._thread is not None or self.closed:
            raise RuntimeError("monitor is single-use")
        self.observe()
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()
        return self

    def stop(self):
        if self._thread is None or self.closed:
            raise RuntimeError("monitor is not active")
        self._stop.set()
        self._thread.join()
        self.observe()
        self.closed = True
        return audit(self.observations, self.expected_worker, self.max_gap_ns, closed=True)


def campaign_isolation(audits, expected_segments):
    """A single contaminated, missing or unfinished segment rejects the campaign."""
    complete = set(audits) == set(expected_segments) and len(expected_segments) == len(set(expected_segments))
    admitted = complete and bool(expected_segments) and all(a.get("admitted") is True and
                a.get("closed") is True and a.get("schema") == "FormulationLab.sampled_isolation_audit.v1"
                for a in audits.values())
    return dict(admitted=admitted, complete=complete,
                rejected_segments=[k for k, a in audits.items() if a.get("admitted") is not True],
                policy="Reject entire campaign; never retain a clean subset as the planned campaign.")


GATES = ("accepted", "complete_declared_bound_coverage", "complete_emitted_coverage",
         "start_representable", "physical_passed", "own_model_passed", "full_model_passed",
         "objective_reconciled", "native_reader_equal")


def finite_number(x):
    return type(x) in (int, float) and math.isfinite(x)


def audit_worker(report, job):
    """Reconcile a terminal native worker with an independently authenticated job.

    Physical checks are supplied by the source-pinned Julia executor, not rerun
    here. No cached aggregate 'accepted' flag can override a missing endpoint.
    """
    errors = []
    if (report.get('schema') != 'FormulationLab.native_timing_worker.v1' or
            report.get('status') != 'completed' or report.get('mode') != 'native' or
            report.get('pending_event') is not None or report.get('job') != job):
        return dict(admitted=False, errors=['worker_identity_or_completion'])
    if any(type(report.get(k)) is not int or report[k] != 1 for k in ('julia_threads', 'blas_threads')):
        errors.append('thread_settings')
    trials = report.get('trials', [])
    if not isinstance(trials, list) or [t.get('event') for t in trials] != job['events']:
        return dict(admitted=False, errors=errors + ['trial_coverage_or_order'])
    for i, entry in enumerate(trials):
        row = entry.get('trial', {})
        warmup = entry['event']['stage'] == 'warmup'
        if entry.get('excluded_warmup') is not warmup:
            errors.append(f'warmup_classification:{i}')
        if (any(row.get(k) is not True for k in GATES) or row.get('anchor_in_profile') is False or
                'error' in row or not finite_number(row.get('objective'))):
            errors.append(f'endpoint_correctness:{i}')
        timing = row.get('timing', {})
        if timing.get('mode') != 'native' or timing.get('synthetic_elapsed_ns') is not None:
            errors.append(f'measurement_mode:{i}')
        if not warmup and (timing.get('schema') != 'FormulationLab.native_trial_timing.v1' or
                timing.get('sample_status') != 'completed' or timing.get('clock_error') is not None or
                not finite_number(timing.get('native_ipopt_wall_s')) or timing['native_ipopt_wall_s'] <= 0):
            errors.append(f'invalid_native_sample:{i}')
    n = len(job['admission']['arms'])
    expected_groups = [('warmup', 0)] + [('measurement', s) for s in range(1, len(job['admission']['sweeps']) + 1)]
    groups = report.get('groups', [])
    if [(g.get('stage'), g.get('sweep')) for g in groups] != expected_groups:
        errors.append('group_coverage')
    else:
        for i, (group, key) in enumerate(zip(groups, expected_groups)):
            detail = group.get('comparison', {})
            if (group.get('correctness_admitted') is not True or detail.get('passed') is not True or
                    detail.get('physical_export_shape_equal') is not True or detail.get('objectives_comparable') is not True or
                    any(not isinstance(detail.get(k), list) or len(detail[k]) != n or
                        any(v is not True for v in detail[k]) for k in ('control_in_each_arm', 'each_arm_in_control'))):
                errors.append(f'cross_arm_comparison:{i}')
            entries = [t for t in trials if (t['event']['stage'], t['event']['sweep']) == key]
            rows = [t['trial'] for t in sorted(entries, key=lambda t: t['event']['arm_index'])]
            if len(rows) != n or any(not finite_number(r.get('objective')) for r in rows):
                errors.append(f'objective_coverage:{i}')
            else:
                tol = job['tolerances']
                # Match Julia's scalar isapprox, against declared control arm 1.
                values = [r['objective'] for r in rows]
                if any(abs(v-values[0]) > max(tol['objective_atol'], tol['objective_rtol'] * max(abs(v),abs(values[0]))) for v in values):
                    errors.append(f'objective_disagreement:{i}')
    return dict(admitted=not errors, errors=errors, trials_checked=len(trials))


def audit_campaign(reports, traces, expected_jobs):
    """All-or-nothing admission; caller authenticates jobs and runtime first."""
    complete = bool(expected_jobs) and set(reports) == set(traces) == set(expected_jobs)
    workers, isolation = {}, {}
    if complete:
        for key, job in expected_jobs.items():
            try:
                workers[key] = audit_worker(reports[key], job)
            except (ValueError, TypeError, KeyError, AttributeError) as exc:
                workers[key] = dict(admitted=False, errors=[f'malformed_worker: {exc}'])
            try:
                trace = traces[key]
                isolation[key] = audit(trace['observations'], trace['expected_worker'], trace['max_gap_ns'], closed=trace['closed'])
                expected = trace['expected_worker']
                if expected is None or reports[key].get('worker_pid') != expected['pid']:
                    isolation[key]['admitted'] = False
                    isolation[key]['errors'].append('worker_pid_mismatch')
            except (ValueError, TypeError, KeyError, AttributeError) as exc:
                isolation[key] = dict(admitted=False, errors=[f'malformed_trace: {exc}'])
    admitted = complete and all(w['admitted'] for w in workers.values()) and all(a['admitted'] for a in isolation.values())
    return dict(schema='FormulationLab.native_campaign_admission.v1', admitted=admitted,
                complete=complete, worker_audits=workers, isolation_audits=isolation,
                ranking=None, scope='Authenticated finite jobs only; no held-out inference from training jobs.')
