"""Descriptive statistics for the prospectively frozen transfer comparisons.

Inputs must already pass physical, objective, provenance and campaign-isolation
admission. This module does not authenticate that admission, authorize timing or
promote a formulation. Failed/inapplicable cases belong in a separate denominator.
"""
import math
from statistics import median


def arm(current, lifting, zero):
    return f"{current}__{lifting}__zero_{str(zero).lower()}"


FACTORIAL = tuple(arm(c, l, z) for c in ("off", "transformer_currents")
                  for l in ("powers", "bounded_observations") for z in (False, True))
PORTFOLIO = ("full_powers",) + FACTORIAL


def positive(value):
    if type(value) not in (int, float) or not math.isfinite(value) or value <= 0:
        raise ValueError("positive finite Ipopt wall time/ratio required")
    return value


def contrasts(times):
    """Matched within-sweep effects, including zero/lifting and three-way interaction."""
    if set(times) != set(FACTORIAL):
        raise ValueError("exactly eight factorial arms required")
    t = {k: math.log(positive(v)) for k, v in times.items()}
    ratio = lambda a, b: math.exp(t[a] - t[b])
    zero = {f"{c}__{l}": ratio(arm(c, l, True), arm(c, l, False))
            for c in ("off", "transformer_currents") for l in ("powers", "bounded_observations")}
    lifting = {f"{c}__zero_{str(z).lower()}": ratio(arm(c, "bounded_observations", z), arm(c, "powers", z))
               for c in ("off", "transformer_currents") for z in (False, True)}
    current = {f"{l}__zero_{str(z).lower()}": ratio(arm("transformer_currents", l, z), arm("off", l, z))
               for l in ("powers", "bounded_observations") for z in (False, True)}
    interaction = {c: math.exp(t[arm(c, "bounded_observations", True)] - t[arm(c, "powers", True)]
                             - t[arm(c, "bounded_observations", False)] + t[arm(c, "powers", False)])
                   for c in ("off", "transformer_currents")}
    return dict(zero_over_retained=zero, broad_over_powers=lifting, eliminated_over_explicit=current,
                zero_lifting_interaction=interaction,
                three_way_interaction=interaction["transformer_currents"] / interaction["off"])


def summarize(sweeps, *, arms=PORTFOLIO, selected="full_powers", reference="full_powers"):
    """One case/objective/batch; preserve each pair and never pool batches here."""
    if not sweeps or len(arms) != len(set(arms)) or selected not in arms or reference not in arms:
        raise ValueError("nonempty matched sweeps and declared selected/reference arms required")
    if any(set(s) != set(arms) for s in sweeps):
        raise ValueError("missing/extra arm in matched sweep; do not discard failed rows")
    for sweep in sweeps:
        for value in sweep.values():
            positive(value)
    medians = {a: median(s[a] for s in sweeps) for a in arms}
    logs = {a: [math.log(s[a]) - math.log(s[reference]) for s in sweeps] for a in arms}
    return dict(sweep_count=len(sweeps), median_ipopt_wall_s=medians,
                ratio_of_medians={a: medians[a] / medians[reference] for a in arms},
                paired_log_ratios=logs,
                median_paired_ratio={a: math.exp(median(v)) for a, v in logs.items()},
                selected=selected, reference=reference,
                selector_regret=medians[selected] / min(medians.values()),
                timing_admission_verified=False)


def parent_summary(rows):
    """Equal-parent geometric mean after averaging log ratios within each parent.

    Supply only one explicitly separated domain/objective/batch at a time. Each
    row needs a unique case and its parent identity; derived cases do not count
    as extra independent parents. Report all case ratios and failures elsewhere.
    """
    if not rows or len({r["case"] for r in rows}) != len(rows):
        raise ValueError("nonempty unique cases required")
    cells = {(r["domain"], r["objective"], r["batch"]) for r in rows}
    if len(cells) != 1:
        raise ValueError("do not pool domains, objectives or batches")
    groups = {}
    for r in rows:
        if not isinstance(r["parent"], str) or not r["parent"]:
            raise ValueError("explicit parent identity required")
        groups.setdefault(r["parent"], []).append(math.log(positive(r["ratio"])))
    per_parent = {p: sum(v) / len(v) for p, v in groups.items()}
    return dict(independent_parents=len(groups),
                geometric_mean_ratio=math.exp(sum(per_parent.values()) / len(per_parent)),
                per_parent_ratio={p: math.exp(v) for p, v in per_parent.items()},
                maximum_case_ratio=max(r["ratio"] for r in rows),
                minimum_case_ratio=min(r["ratio"] for r in rows))
