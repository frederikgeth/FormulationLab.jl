"""Render implementation measurements and verify their basic invariants."""
from pathlib import Path
import json
import statistics

root=Path(__file__).resolve().parent.parent
path=root/'examples/results/soc_profiles_2026-09-11.json'
x=json.loads(path.read_text())
assert x['complete'] and len(x['cases'])==5
lines=['# Implemented SOC profiles: fixed comparison', '',
       'Three serial repeats with fresh solver instances and the controlled-study settings: '
       'feasibility 1e-7, absolute gap 1e-6, relative gap 1e-7, regularization 1e-7, '
       'refinement cap 30, 90-second solver limit, one BLAS thread. '
       'Native time excludes build/setup/extraction/reconstruction. '
       'CHOLMOD is an explicit experimental override; the default remains QDLDL.', '',
       'All variants share prepared inputs, power bases, objective and static electrical semantics. '
       'NLP differences use fresh BMOPFTools/Ipopt local solutions. '
       'They are not certified optimality gaps. Non-publishable runs remain visible.', '']
for c in x['cases']:
    assert len(c['runs'])==len(x['variants'])*3
    assert c['nlp']['status'] in ('OPTIMAL','LOCALLY_SOLVED')
    assert not any(f['severity']=='ERROR' for f in c['nlp']['findings'])
    lines += [f"## {c['name']}", '',
              '| Variant | Accepted | Native median s [min, max] | Iterations | NLP − SOC W | First-repeat KCL A | nnz(KKT L) |',
              '|:--|--:|--:|--:|--:|--:|--:|']
    for v in x['variants']:
        rs=[r for r in c['runs'] if r['profile']==v['name']]
        assert len(rs)==3 and all('error' not in r for r in rs)
        assert all(all('PSD' not in k for k in r['solver_cones']) for r in rs)
        assert len({r['A_nnz'] for r in rs})==1
        good=[r for r in rs if r['publishable']]
        times=[r['native_solve_seconds'] for r in rs]
        gap=f"{statistics.median(r['nlp_minus_soc_W'] for r in good):.6f}" if good else '—'
        for r in good:
            assert r['status']=='OPTIMAL' and r['nlp_minus_soc_W']>-.1
        kcl=f"{rs[0]['max_kcl_A']:.3f}" if 'max_kcl_A' in rs[0] else '—'
        lines.append(f"| {v['name']} | {len(good)}/3 | {statistics.median(times):.4f} [{min(times):.4f}, {max(times):.4f}] | "
                     f"{statistics.median(r['iterations'] for r in rs):.0f} | {gap} | {kcl} | {rs[0]['linear_solver']['nnzL']} |")
    d=c['models']['physical_sparse']['numerics']
    assert not d['basis_fallback']
    lines += ['', f"Physical basis: {d['basis_structural_components']} dependent components; "
              f"relative map difference {d['basis_map_difference']:.3g}; "
              f"relative electrical residual {d['basis_relative_residual']:.3g}; no fallback.", '']
lines += ['## Interpretation', '',
          'The structural physical basis is the main improvement. Automatic selection now uses it '
          'only for small independent-state dimensions; selecting it explicitly on larger cases can '
          'change SOC strength and severely worsen voltage-tree recovery (notably ENWL 96). '
          'The sparse fast/balanced presets remain alternatives, not uniformly faster choices.', '',
          'Kim4 fails acceptance on 45 buses. CHOLMOD is slower than QDLDL on this panel and '
          'is not promoted. Budget-dependent primal objectives are not consistently monotone '
          'in these numerically sensitive models; small conic residuals should not be treated '
          'as rigorous accuracy certificates or used to assert that a smaller cut set is stronger.', '',
          '## Reproduction', '', '```sh',
          'JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test/integration examples/benchmark_soc_profiles.jl examples/results/soc_profiles_2026-09-11.json 3',
          'python3 examples/summarize_soc_profiles.py', '```', '',
          '[Raw measurements](soc_profiles_2026-09-11.json). '
          'The automatic-policy change was made after this sweep; its `physical_sparse` variant '
          'explicitly selects the same small-state algorithm. Wider-panel runs exercise the new automatic policy.', '']
path.with_suffix('.md').write_text('\n'.join(lines))
print('Implementation sweep: 90 complete runs validated.')
