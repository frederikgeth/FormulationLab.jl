"""Audit a restricted Ipopt 3.14.19 detailed MUMPS trace, without using timers.

Supported traces have one primal-dual solve block per iteration, explicit recovery
messages and residual reports after every in-block wrapper solve. Unsupported or
incomplete traces fail closed. This is not a general Ipopt event API.
"""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re


NUMBER = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"


def parse(text):
    """Classify wrapper calls by primal-dual block and residual/recovery sequence.

    Fortran JOB reports may be buffered across files. This function only uses
    Ipopt wrapper messages; independently reconcile their counts against the
    complete MUMPS capture set before interpreting model-level results.
    """
    versions = re.findall(r"^This is Ipopt version ([^,]+),", text, re.M)
    iterations = re.findall(r"^Number of Iterations\.\.*:\s*(\d+)\s*$", text, re.M)
    if versions != ["3.14.19"] or len(iterations) != 1 or not re.search(r"^EXIT: .+$", text, re.M):
        raise ValueError("one complete Ipopt 3.14.19 run required")
    blocks = []; outside = []; active = None; pending = None; recovery = None
    factors = 0; events = []; calls = []

    def finish_block():
        if pending is not None or recovery is not None or not active['solves']:
            raise ValueError("unfinished primal-dual block")
        if any(s.get('residual_ratio') is None for s in active['solves']):
            raise ValueError("missing residual after solve")

    for line, raw in enumerate(text.splitlines(), 1):
        s = raw.strip()
        start = re.fullmatch(r"\*\*\* Solving the Primal Dual System for Iteration (\d+):", s)
        stop = re.fullmatch(r"\*\*\* Finding Acceptable Trial Point for Iteration (\d+):", s)
        if start:
            if active is not None or pending is not None or int(start[1]) != len(blocks):
                raise ValueError("unsupported iteration/block ordering")
            active = dict(iteration=int(start[1]), line=line, solves=[], events=[])
            blocks.append(active)
        elif stop:
            if active is None or active['iteration'] != int(stop[1]):
                raise ValueError("unmatched end of primal-dual block")
            finish_block(); active = None
        elif s == 'Calling MUMPS-2 for numerical factorization.':
            factors += 1
            if active and active['solves'] and recovery is None:
                raise ValueError("unclassified refactorization after an in-block solve")
        elif s == 'Calling MUMPS-3 for solve.':
            if pending is not None:
                raise ValueError("nested or missing solve completion")
            if active is None:
                if blocks:
                    raise ValueError("unsupported solve outside primal-dual block after iterations began")
                kind = 'before_iterations'
            elif not active['solves']:
                kind = 'initial'
            elif recovery is not None:
                kind = recovery; recovery = None
            else:
                if active['solves'][-1].get('residual_ratio') is None:
                    raise ValueError("missing residual before correction solve")
                kind = 'refinement'
            pending = dict(line=line, kind=kind)
            (outside if active is None else active['solves']).append(pending)
            calls.append(pending)
        elif s == 'Done with MUMPS-3 for solve.':
            if pending is None:
                raise ValueError("unmatched solve completion")
            pending['done_line'] = line; pending = None
        elif s.startswith('residual_ratio ='):
            m = re.fullmatch(rf"residual_ratio = ({NUMBER})", s)
            if not m or active is None or pending is not None or not active['solves']:
                raise ValueError("unmatched or invalid residual report")
            solve = active['solves'][-1]; value = float(m[1])
            if 'residual_ratio' in solve or not math.isfinite(value) or value < 0:
                raise ValueError("duplicate or invalid residual report")
            solve.update(residual_ratio=value, residual_line=line)
        elif any(s.startswith(prefix) for prefix in (
                'Iterative refinement failed', 'Asking augmented system solver',
                'Increasing pivot tolerance for MUMPS', 'Pretend that the current system',
                'Just accept current solution.')):
            if active is None or pending is not None or not active['solves'] or 'residual_ratio' not in active['solves'][-1]:
                raise ValueError("unmatched recovery event")
            event = dict(line=line, text=s); events.append(event); active['events'].append(event)
            if s.startswith('Increasing pivot tolerance for MUMPS'):
                if recovery is not None:
                    raise ValueError("ambiguous recovery restart")
                recovery = 'quality_restart'
            elif s.startswith('Pretend that the current system'):
                if recovery is not None:
                    raise ValueError("ambiguous recovery restart")
                recovery = 'singularity_restart'
    if active is not None or pending is not None or recovery is not None or len(blocks) != int(iterations[0]):
        raise ValueError("incomplete run or unsupported iteration coverage")
    counts = Counter(s['kind'] for s in calls)
    for kind in ('before_iterations', 'initial', 'quality_restart', 'singularity_restart', 'refinement'):
        counts.setdefault(kind, 0)
    episodes = []
    for block in blocks:
        for solve in block['solves']:
            if solve['kind'] != 'refinement':
                episodes.append(dict(iteration=block['iteration'], kind=solve['kind'],
                                     initial_ratio=solve['residual_ratio'], corrections=[]))
            else:
                episodes[-1]['corrections'].append(solve['residual_ratio'])
    return dict(schema='FormulationLab.ipopt_refinement_trace.v1', source_sha256=hashlib.sha256(text.encode()).hexdigest(),
                ipopt_version=versions[0], iterations=int(iterations[0]), wrapper_factorizations=factors,
                wrapper_solves=len(calls), classification_complete=True, counts=dict(counts),
                episodes=episodes, blocks=blocks, before_iterations=outside, events=events,
                corrections_beyond_first=sum(max(0, len(e['corrections'])-1) for e in episodes),
                timing_eligible=False,
                qualification='Restricted message-sequence classification, requiring independent MUMPS capture reconciliation. '
                'Residual ratios are coordinate-dependent algorithmic tests, not condition numbers or SI accuracy certificates. '
                'No timing or causal speed claim; other trace layouts are unsupported.')


if __name__ == '__main__':
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('log', type=Path); cli.add_argument('output', type=Path)
    args = cli.parse_args()
    args.output.write_text(json.dumps(parse(args.log.read_text()), indent=2, allow_nan=False) + '\n')
