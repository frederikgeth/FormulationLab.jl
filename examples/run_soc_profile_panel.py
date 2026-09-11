"""Serial ENWL profile screen with explicit process budgets for the three largest inputs."""
import json
import os
from pathlib import Path
import signal
import subprocess
import time

root = Path(__file__).resolve().parent.parent
results = root / 'examples/results'
env = dict(os.environ, JULIA_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1')
panel = json.loads((results / 'nlp_soc_panel_manifest.json').read_text())[:12]
summary = {'note': 'Serial screening, one solve per completed case/profile; large-process caps include startup/build, not only optimization.', 'jobs': []}
output = results / 'soc_profiles_panel_2026-09-11.json'
jobs = [('small', panel[:9], 900)]
for case in panel[9:]:
    for profile in ('fast', 'balanced'):
        jobs.append((Path(case['path']).stem + '_' + profile, [dict(case, profiles=[profile])], 120))
for name, cases, budget in jobs:
    manifest = results / f'soc_profiles_panel_{name}_manifest.json'
    raw = results / f'soc_profiles_panel_{name}.json'
    log = results / f'soc_profiles_panel_{name}.log'
    manifest.write_text(json.dumps(cases, indent=2) + '\n')
    command = ['julia', '--project=test/integration', '--startup-file=no', 'examples/benchmark_soc_profile_panel.jl', str(manifest), str(raw)]
    row = {'name': name, 'budget_seconds': budget, 'manifest': manifest.name, 'raw': raw.name, 'log': log.name}
    summary['jobs'].append(row)
    output.write_text(json.dumps(summary, indent=2) + '\n')
    print('START', name, flush=True)
    start = time.monotonic()
    with log.open('w') as stream:
        p = subprocess.Popen(command, cwd=root, env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            row['exit_code'] = p.wait(timeout=budget)
            row['outcome'] = 'completed' if p.returncode == 0 else 'process_error'
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
            row['outcome'] = 'process_budget'
    row['wall_seconds'] = time.monotonic() - start
    if raw.exists():
        try:
            records = json.loads(raw.read_text())
            row['last_stage'] = records['cases'][-1]['stage'] if records['cases'] else 'warmup'
        except (ValueError, KeyError):
            row['last_stage'] = 'unavailable'
    output.write_text(json.dumps(summary, indent=2) + '\n')
    print('DONE', name, row['outcome'], row.get('last_stage'), flush=True)
summary['complete'] = True
output.write_text(json.dumps(summary, indent=2) + '\n')
