"""Calibrate restricted native Ipopt refinement traces; no timing conclusions.

The norm/ratio audit checks printed full primal-dual residuals and rounding
intervals. It does not independently reconstruct the residual equations.
"""
from decimal import Decimal, localcontext
import re

from ivr_native_kkt import vector
from ivr_refinement_trace import NUMBER, parse


def printed_interval(token):
    """Enclose a nonnegative scientific-format value rounded by printf.

    Scientific-format zero denotes zero, not a fixed-decimal rounding interval.
    """
    if not re.fullmatch(r"\d+\.\d+[eE][+-]\d+", token):
        raise ValueError("nonnegative scientific-format number required")
    value = Decimal(token)
    if not value:
        return value, value
    half_unit = Decimal(5).scaleb(value.as_tuple().exponent - 1)
    return max(Decimal(0), value-half_unit), value+half_unit


def ratio_interval(rhs, solution, residual):
    """Interval of Ipopt's ratio from nonnegative norm intervals."""
    blo, bhi = rhs; xlo, xhi = solution; rlo, rhi = residual
    if any(lo < 0 or hi < lo for lo, hi in (rhs, solution, residual)):
        raise ValueError("invalid norm interval")
    if bhi + xhi == 0:
        return rlo, rhi
    dlo = min(xlo, Decimal(10)**6*blo) + blo
    dhi = min(xhi, Decimal(10)**6*bhi) + bhi
    if dlo == 0:
        raise ValueError("denominator interval includes zero")
    return rlo/dhi, rhi/dlo


def overlaps(a, b):
    return max(a[0], b[0]) <= min(a[1], b[1])


def audit(text, minimum):
    """Require supported trace, minimum counts and all eight residual blocks.

    The residual-vector maximum is checked against both the printed block norms
    and aggregate norm. RHS/solution norms cannot be recovered from those
    residual vectors; their rounded printed intervals bound the denominator.
    """
    if type(minimum) is not int or not 0 <= minimum <= 10:
        raise ValueError("minimum must be an integer between zero and ten")
    trace = parse(text)
    if any(len(e['corrections']) < minimum for e in trace['episodes']):
        raise ValueError("episode below declared minimum")
    lines = text.splitlines(); records = []
    with localcontext() as ctx:
        ctx.prec = 80
        for block in trace['blocks']:
            for solve in block['solves']:
                chunk = '\n'.join(lines[solve['done_line']:solve['residual_line']])
                if chunk.count('CompoundVector "resid" with 8 components:') != 1:
                    raise ValueError("one full eight-block residual required")
                maxima = []
                for i, name in enumerate(('x', 's', 'c', 'd', 'zL', 'zU', 'vL', 'vU')):
                    v = vector(chunk, f'resid[{i}]')
                    norm = Decimal(str(max(map(abs, v), default=0.0)))
                    reported = re.findall(rf'^max-norm resid_{name}\s+({NUMBER})$', chunk, re.M)
                    if len(reported) != 1 or not overlaps((norm, norm), printed_interval(reported[0])):
                        raise ValueError("residual block norm mismatch")
                    maxima.append(norm)
                norms = re.findall(rf'^nrm_rhs =\s*({NUMBER}) nrm_sol =\s*({NUMBER}) nrm_resid =\s*({NUMBER})$', chunk, re.M)
                ratios = re.findall(rf'^residual_ratio = ({NUMBER})$', chunk, re.M)
                if len(norms) != 1 or len(ratios) != 1:
                    raise ValueError("missing/duplicate norms or ratio")
                rhs, sol, resid = map(printed_interval, norms[0])
                maximum = max(maxima)
                if not overlaps((maximum, maximum), resid):
                    raise ValueError("aggregate residual norm mismatch")
                bounds = ratio_interval(rhs, sol, (maximum, maximum))
                if not overlaps(bounds, printed_interval(ratios[0])):
                    raise ValueError("native ratio outside rounding interval")
                records.append(dict(iteration=block['iteration'], kind=solve['kind'],
                    line=solve['residual_line'], residual_max=float(maximum),
                    ratio_interval=[str(v) for v in bounds]))
    expected = trace['wrapper_solves']-trace['counts']['before_iterations']
    if len(records) != expected:
        raise ValueError("incomplete ratio coverage")
    return dict(schema='FormulationLab.native_refinement_policy.v1', minimum=minimum,
        trace=trace, norm_ratio_checks=records, timing_eligible=False,
        qualification='Printed full primal-dual norm/ratio consistency, not an independent residual-equation audit.')
