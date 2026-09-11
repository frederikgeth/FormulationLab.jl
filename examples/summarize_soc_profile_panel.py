"""Validate and render the wider screen, retaining external budget outcomes."""
from pathlib import Path
import json

root=Path(__file__).resolve().parent.parent
folder=root/'examples/results'
p=folder/'soc_profiles_panel_2026-09-11.json'
x=json.loads(p.read_text())
assert x['complete'] and len(x['jobs'])==7
lines=['# Wider ENWL profile screen', '',
       'One serial screening run per completed profile. Same per-unit preparation and '
       'study tolerances as the implementation sweep. The nine cases up to 140 buses '
       'use the new automatic default, fast and balanced profiles. The three larger '
       'cases attempt fast and balanced separately with 120-second external process '
       'budgets, including warm-up, parsing and building. Native solve times exclude '
       'these stages. External timeouts are not solver failures.', '',
       '| Case | Profile | Outcome | Build s | Native solve s | NLP − SOC W |',
       '|:--|:--|:--|--:|--:|--:|']
accepted=0;completed=0;budgets=0
fmt=lambda v:'—' if v is None else f'{v:.4f}'
for job in x['jobs']:
    manifest=json.loads((folder/job['manifest']).read_text())
    raw=folder/job['raw']
    data=json.loads(raw.read_text()) if raw.exists() else {'cases':[]}
    if job['outcome']=='completed':
        assert data['complete']
    elif job['outcome']=='process_budget':
        budgets+=1
    else:
        raise AssertionError(job)
    for case in data['cases']:
        if 'nlp' in case:
            assert case['nlp']['status'] in ('LOCALLY_SOLVED','OPTIMAL')
            assert not any(f['severity']=='ERROR' for f in case['nlp']['findings'])
        for r in case['runs']:
            status=r.get('status',f"PROCESS_BUDGET ({case['stage']})")
            if 'status' in r:
                completed+=1;accepted+=bool(r['publishable'])
                assert all('PSD' not in k for k in r['solver_cones'])
                if r['publishable']:
                    assert status=='OPTIMAL' and r['nlp_minus_soc_W']>-.1
                else:
                    assert r['objective_W'] is None
            lines.append(f"| {case['name']} | {r['profile']} | {status} | {fmt(r.get('build_seconds'))} | {fmt(r.get('native_solve_seconds'))} | {fmt(r.get('nlp_minus_soc_W'))} |")
    if job['outcome']=='process_budget' and not any(c['runs'] for c in data['cases']):
        c=manifest[0]
        lines.append(f"| {c['name']} | {c['profiles'][0]} | PROCESS_BUDGET ({job.get('last_stage','unknown')}) | — | — | — |")
lines += ['', f'{accepted}/{completed} completed solves were accepted; {budgets} external process-budget outcomes. '
          'The limited screen is not a guarantee of performance or coverage on all BMOPF inputs.', '',
          '## Reproduction', '', '```sh', 'python3 examples/run_soc_profile_panel.py',
          'python3 examples/summarize_soc_profile_panel.py', '```', '',
          '[Job index, manifests and raw-file locations](soc_profiles_panel_2026-09-11.json).', '']
p.with_suffix('.md').write_text('\n'.join(lines))
print(accepted, 'accepted of', completed, 'completed solves;', budgets, 'process budgets')
