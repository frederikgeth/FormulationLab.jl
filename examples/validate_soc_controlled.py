"""Check completeness and interpretation invariants of the recorded experiments."""
import json
import math
import sys

for path in sys.argv[1:]:
    data = json.load(open(path))
    assert data['complete'], path
    assert len(data['cases']) == 5
    assert data['blas_threads'] == data['julia_threads'] == 1
    profiles = {p['name'] for p in data['profiles']}
    for case in data['cases']:
        assert case['complete']
        assert len(case['runs']) == len(profiles) * data['repeats']
        assert {(r['profile'], r['repeat']) for r in case['runs']} == {
            (p, i) for p in profiles for i in range(1, data['repeats']+1)}
        for nlp in ('nlp_original', 'nlp_reduced'):
            assert case[nlp]['status'] in ('OPTIMAL', 'LOCALLY_SOLVED')
            assert not any(f['severity'].upper() == 'ERROR' for f in case[nlp]['findings'])
        for r in case['runs']:
            assert 'error' not in r, (case['name'], r)
            assert all('PSD' not in name for name in r['solver_cones'])
            t = r['timers']['children']['solve!']
            assert math.isclose(t['seconds'], r['native_solve_seconds'])
            assert r['reported_solve_seconds'] >= r['native_solve_seconds']
            assert r['extraction_seconds'] >= 0
            if r['publishable']:
                assert r['status'] == 'OPTIMAL'
                assert math.isclose(r['nlp_minus_soc_W'], case['nlp_reduced']['source_W'] - r['objective_W'],abs_tol=1e-8)
                # A large negative difference would signal a semantic/containment problem.
                assert r['nlp_minus_soc_W'] > -0.1
            else:
                assert r['objective_W'] is None
        # These duplicate controls should have identical conic matrices and solutions.
        for p in profiles:
            rs = [r for r in case['runs'] if r['profile'] == p]
            assert len({r['A_nnz'] for r in rs}) == 1
            assert len({str(r['A_shape']) for r in rs}) == 1
    print(path, ': complete, coherent, SOC/power cones only')
