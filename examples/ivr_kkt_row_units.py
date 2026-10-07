"""Exact positive row-unit changes for parsed native Ipopt KKT systems.

No optimization or factorization is performed. The objective scale and x units
are fixed. Targets are absolute NLP row scales relative to the model rows.
"""
import copy
import math

from ivr_native_kkt import multiply, relative_gap


def positive(values, size, name):
    values = list(values)
    if len(values) != size or any(not math.isfinite(v) or v <= 0 for v in values):
        raise ValueError('invalid ' + name)
    return values


def coordinate_map(k, target_c, target_d):
    """Return T with q_old = T q_new and K_new = T K_old T.

    If A = R_new/R_old, T = diag(I, A_d^-1, A_c, A_d).
    Slack/dual pairing keeps the -I block unchanged.
    """
    nx, ns, nc, nd = k['dimensions']
    if ns != nd:
        raise ValueError('slack/inequality dimensions differ')
    ratios = []
    for key, target, n in [('J_c', target_c, nc), ('J_d', target_d, nd)]:
        old = positive(k[key]['row_scaling'], n, 'source row scale')
        new = positive(target, n, 'target row scale')
        ratios.append(positive((b/a for a, b in zip(old, new)), n, 'row-scale ratio'))
    ac, ad = ratios
    inverse = positive((1/a for a in ad), nd, 'inverse row-scale ratio')
    return [1.]*nx + inverse + ac + ad


def change_units(k, target_c, target_d):
    """Copy all KKT blocks into target units, including regularization."""
    target_c, target_d = list(target_c), list(target_d)
    t = coordinate_map(k, target_c, target_d)
    result = copy.deepcopy(k)
    nx, ns, nc, nd = k['dimensions']
    offsets = [0, nx, nx+ns, nx+ns+nc]
    for offset, key in zip(offsets, ('x_diagonal', 's_diagonal', 'c_diagonal', 'd_diagonal')):
        result[key] = [v*t[offset+i]*t[offset+i] for i, v in enumerate(k[key])]
    for offset, key, target in [(offsets[2], 'J_c', target_c), (offsets[3], 'J_d', target_d)]:
        result[key]['values'] = [v*t[offset+i-1] for i, v in zip(k[key]['rows'], k[key]['values'])]
        result[key]['row_scaling'] = target
    # Catch overflow/underflow of coordinate arithmetic, including squared scales.
    for key in ('x_diagonal', 's_diagonal', 'c_diagonal', 'd_diagonal'):
        if any(not math.isfinite(v) or (old != 0 and v == 0) for old, v in zip(k[key], result[key])):
            raise ValueError('unrepresentable transformed diagonal')
    for key in ('J_c', 'J_d'):
        if any(not math.isfinite(v) or (old != 0 and v == 0) for old, v in zip(k[key]['values'], result[key]['values'])):
            raise ValueError('unrepresentable transformed Jacobian')
    return result


def map_vector(values, t, *, inverse=False):
    if len(values) != len(t) or any(not math.isfinite(v) for v in values):
        raise ValueError('invalid vector')
    positive(t, len(t), 'coordinate map')
    result = [v/a if inverse else a*v for v, a in zip(values, t)]
    if any(not math.isfinite(v) for v in result):
        raise ValueError('unrepresentable transformed vector')
    return result


def backward_errors(k, x, b):
    """Componentwise backward errors |Kx-b|/(|K||x|+|b|).

    Duplicate sparse entries are accumulated before taking absolute values;
    the separate W and x diagonal contributions are combined as well.
    """
    from ivr_native_kkt import entries
    n = sum(k['dimensions'])
    if len(x) != n or len(b) != n:
        raise ValueError('vector dimensions differ')
    nx, ns, nc, nd = k['dimensions']
    offsets = [0, nx, nx+ns, nx+ns+nc]
    rows = {}
    def add(i, j, value):
        rows[i, j] = rows.get((i, j), 0.) + value
        if i != j:
            rows[j, i] = rows.get((j, i), 0.) + value
    for (i, j), v in entries(k['W']).items():
        add(i-1, j-1, k['W_factor']*v)
    for offset, key in [(offsets[2], 'J_c'), (offsets[3], 'J_d')]:
        for (i, j), v in entries(k[key]).items():
            add(offset+i-1, j-1, v)
    for offset, key in zip(offsets, ('x_diagonal', 's_diagonal', 'c_diagonal', 'd_diagonal')):
        for i, v in enumerate(k[key]):
            add(offset+i, offset+i, v)
    for i in range(ns):
        add(offsets[3]+i, offsets[1]+i, -1.)
    denominator = [abs(v) for v in b]
    for (i, j), v in rows.items():
        denominator[i] += abs(v)*abs(x[j])
    residual = [a-v for a, v in zip(multiply(k, x), b)]
    if any(not math.isfinite(v) for v in denominator+residual):
        raise ValueError('nonfinite residual arithmetic')
    return [abs(r)/d if d else (0. if r == 0 else math.inf)
            for r, d in zip(residual, denominator)]


def backward_error(k, x, b):
    return max(backward_errors(k, x, b), default=0.)


def audit_call(call, target_c, target_d):
    """Algebraic covariance audit; mapped native solutions are not new solves."""
    target_c, target_d = list(target_c), list(target_d)
    k = call['matrix']
    t = coordinate_map(k, target_c, target_d)
    transformed = change_units(k, target_c, target_d)
    b = map_vector(call['rhs'], t)
    restored = change_units(transformed, k['J_c']['row_scaling'], k['J_d']['row_scaling'])
    gaps = []
    # Deterministic dense probes cover all columns, independently of solver RHSs.
    for probe in range(3):
        x = [math.sin((i+1)*(probe+1)) for i in range(len(t))]
        expected = map_vector(multiply(k, map_vector(x, t)), t)
        gaps.append(relative_gap(multiply(transformed, x), expected))
        gaps.append(relative_gap(multiply(restored, x), multiply(k, x)))
    report = dict(passed=max(gaps, default=0.) < 1e-9, timing_eligible=False,
                  dimension=len(t), coordinate_min=min(t, default=1.),
                  coordinate_max=max(t, default=1.), action_gap=max(gaps, default=0.),
                  rhs_roundtrip_gap=relative_gap(map_vector(b, t, inverse=True), call['rhs']),
                  independently_refactorized=False)
    if report['rhs_roundtrip_gap'] > 1e-12 or not report['passed']:
        raise ValueError('coordinate covariance failed')
    if call['solution'] is not None:
        q = call['solution']
        new_q = map_vector(q, t, inverse=True)
        old_r = [a-v for a, v in zip(multiply(k, q), call['rhs'])]
        new_r = [a-v for a, v in zip(multiply(transformed, new_q), b)]
        # Normalize by the matrix action/RHS, not a cancellation-small residual.
        expected_r = map_vector(old_r, t)
        scales = [max(1., abs(a), abs(v)) for a, v in zip(multiply(transformed, new_q), b)]
        residual_gap = max((abs(a-v)/s for a, v, s in zip(new_r, expected_r, scales)), default=0.)
        if residual_gap > 1e-9:
            raise ValueError('residual covariance failed')
        old_be = backward_errors(k, q, call['rhs'])
        new_be = backward_errors(transformed, new_q, b)
        if any(not math.isfinite(v) for v in old_be+new_be):
            raise ValueError('nonfinite componentwise backward error')
        be_gap = max((abs(a-v) for a, v in zip(old_be, new_be)), default=0.)
        if be_gap > 1e-12:
            raise ValueError('componentwise backward-error covariance failed')
        worst = max(range(len(t)), key=lambda i: old_be[i]) if t else None
        report.update(residual_covariance_gap=residual_gap,
                      backward_error_component_gap=be_gap,
                      largest_backward_error_row=worst,
                      largest_backward_error_row_rescaled=worst is not None and t[worst] != 1.,
                      original_residual_max=max(map(abs, old_r), default=0.),
                      transformed_residual_max=max(map(abs, new_r), default=0.),
                      original_backward_error=max(old_be, default=0.),
                      transformed_backward_error=max(new_be, default=0.))
    return report
