"""Associate captured callback states with a restricted Ipopt 3.14.19 trace.

The callback precedes the barrier update and direction solve. Record the two
barrier values separately, and retain every printed regularization attempt.
This association does not reconstruct Ipopt's KKT matrices or refinement RHSs.
"""
import argparse
import json
import math
from pathlib import Path
import re

from ivr_refinement_trace import NUMBER, parse


def associate(text, capture):
    trace = parse(text)
    if capture.get('schema') != 'FormulationLab.ipopt_iterates.v1' or capture.get('timing_eligible') is not False:
        raise ValueError('diagnostic iterate schema required')
    records = capture['records']
    if [r['iteration'] for r in records] != list(range(trace['iterations'] + 1)):
        raise ValueError('callback coverage differs from native iterations')
    if any(r['mode'] != 0 for r in records):
        raise ValueError('restoration not supported')
    lines = text.splitlines(); result = []
    for block, record in zip(trace['blocks'], records):
        iteration = block['iteration']
        begin = f'*** Beginning Iteration {iteration} from the following point:'
        starts = [i for i, s in enumerate(lines) if s.strip() == begin]
        if len(starts) != 1 or starts[0] >= block['line'] - 1:
            raise ValueError('missing/ambiguous iteration preamble')
        preamble = '\n'.join(lines[starts[0]:block['line'] - 1])
        current = re.findall(rf'^Current barrier parameter mu = ({NUMBER})$', preamble, re.M)
        updated = re.findall(rf'^Barrier Parameter: ({NUMBER})$', preamble, re.M)
        if len(current) != 1 or len(updated) != 1:
            raise ValueError('missing/ambiguous barrier report')
        current, updated = float(current[0]), float(updated[0])
        if not all(math.isfinite(v) and v > 0 for v in (current, updated, record['mu'])):
            raise ValueError('invalid barrier parameter')
        if not math.isclose(current, record['mu'], rel_tol=1e-12, abs_tol=0):
            raise ValueError('callback barrier differs from iteration preamble')
        stop = f'*** Finding Acceptable Trial Point for Iteration {iteration}:'
        stops = [i for i,s in enumerate(lines) if s.strip() == stop]
        if len(stops) != 1 or stops[0] <= block['line'] - 1:
            raise ValueError('missing/ambiguous direction end')
        body = '\n'.join(lines[block['line'] - 1:stops[0]])
        attempts = re.findall(
            rf'Solving system with delta_x=({NUMBER}) delta_s=({NUMBER})\s+'
            rf'delta_c=({NUMBER}) delta_d=({NUMBER})', body)
        if not attempts or len(attempts) != body.count('Solving system with'):
            raise ValueError('missing/incomplete regularization attempts')
        attempts = [dict(zip(('x','s','c','d'),map(float,a))) for a in attempts]
        if any(not math.isfinite(v) or v < 0 for a in attempts for v in a.values()):
            raise ValueError('invalid regularization')
        result.append(dict(iteration=iteration,callback_mu=record['mu'],
            direction_mu_printed=updated,
            barrier_updated=not math.isclose(current,updated,rel_tol=5e-7,abs_tol=0),
            callback_regularization=record['regularization'],direction_regularization_attempts=attempts,
            factorizations=body.count('Calling MUMPS-2 for numerical factorization.'),
            corrections=sum(s['kind']=='refinement' for s in block['solves']),
            recovery_restarts=sum(s['kind'].endswith('_restart') for s in block['solves']),
            residual_ratios=[s['residual_ratio'] for s in block['solves']],events=block['events']))
    return dict(schema='FormulationLab.ipopt_iterate_association.v1',timing_eligible=False,
        source_sha256=trace['source_sha256'],callback_states=len(records),iterations=result,
        counts=trace['counts'],wrapper_solves=trace['wrapper_solves'],
        qualification='Same-run iteration association only, not matched physical states across formulations. '
        'Callback regularization is not substituted for direction regularization. '
        'Printed direction barrier values have reduced precision. Final callback has no following direction.')


if __name__ == '__main__':
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument('log',type=Path);cli.add_argument('capture',type=Path);cli.add_argument('output',type=Path)
    args=cli.parse_args()
    args.output.write_text(json.dumps(associate(args.log.read_text(),json.loads(args.capture.read_text())),indent=2,allow_nan=False)+'\n')
