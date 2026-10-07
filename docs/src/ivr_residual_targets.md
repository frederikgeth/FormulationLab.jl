# Accuracy-triggered native refinement

## Question and decision

Can stricter residual targets obtain the recovery benefit of
[forced minimum corrections](ivr_opf_refinement_policy.md) without requesting
extra work on every direction? Twelve controlled per-unit OPF solves test
`residual_ratio_max=1e-10,1e-11,1e-12`, always with one mandatory correction.

**Keep the existing general policy.** No target reduces iterations on this panel.
The strictest target avoids two recovery restarts and two factorizations in the
eliminated-current powers profile, but adds 27 linear solves. Its 153 solves also
exceed the previous minimum-three candidate's 148, at the same iteration and
factorization counts. This is not a runtime comparison, and the stricter native
residual criterion is not equivalent to improved physical endpoint accuracy.
Timing remains deferred; defaults and all transformation options are unchanged.

## Design and controls

The declared 333-bus exchange-tracking scenario, four zero-load-reduced profiles,
regional per-unit bases, objective, starts and validation gates are unchanged
from the previous experiment. Powers-only/broad bounded observations are crossed
with explicit/eliminated ordinary transformer currents. Broad profiles are
predeclared controls, not selected after outcomes. Within each profile, targets
are run in the order ``10^{-10},10^{-11},10^{-12}``.

The intervention changes only `residual_ratio_max`. Explicit
`min_refinement_steps=1`, `max_refinement_steps=10` and
`residual_ratio_singular=1e-5` retain their native defaults. The default
`residual_improvement_factor=0.999999999` remains unchanged. The matching
[Ipopt 3.14.19 source](https://github.com/coin-or/Ipopt/blob/releases/3.14.19/src/Algorithm/IpPDFullSpaceSolver.cpp)
requires the singularity threshold to be no smaller than the refinement target;
all three controls satisfy that requirement.

All other solver settings remain fixed: one BLAS thread, MUMPS with
`mumps_pivot_order=7`, gradient-based NLP scaling,
`tol=constr_viol_tol=1e-10`, `acceptable_iter=0`, `bound_relax_factor=0`,
`max_iter=500` and the existing diagnostic CPU limit of 300 seconds. Verbosity
eight records initialization and wrapper events; it does not provide a full
eight-block residual-vector or KKT-matrix audit.

Every explicit refinement option is checked against the native options table,
including a positive reported use count. The reader supports both first-process
logs with the Ipopt banner and subsequent logs where the options table runs
directly into the version line. Missing, unused, duplicate or mismatched options
are rejected; absent defaults are never inferred by this reader. Its initial
banner-only parsing failure and correction are retained in the archive.

All four baseline full callback trajectories and refinement episodes reproduce
historical controls exactly. Within each profile, initial callback arrays,
twelve native internal state vectors, row scales and layouts are identical
across targets. Scaling relations are verified at every captured iterate. For
eliminated currents with broad observations, the complete uncompressed callback
capture is byte-identical at targets ``10^{-10}`` and ``10^{-11}``: the tighter
criterion changes no captured iterate on that run.

## Work and recovery observations

Every run has one initialization solve in addition to the direction solves.
Recovery restarts begin new episodes. Counts refer to Ipopt wrapper messages,
not a new independent Fortran JOB-report capture.

| Currents | Lifting | Target | Iterations | Corrections | Total solves | Factorizations | Refinement failures | Recovery restarts |
|:---|:---|---:|---:|---:|---:|---:|---:|---:|
| Explicit | Powers | 1e-10 | 33 | 84 | 118 | 38 | 0 | 0 |
| Explicit | Powers | 1e-11 | 33 | 101 | 135 | 38 | 0 | 0 |
| Explicit | Powers | 1e-12 | 33 | 121 | 155 | 38 | 0 | 0 |
| Explicit | Broad | 1e-10 | 36 | 36 | 73 | 42 | 0 | 0 |
| Explicit | Broad | 1e-11 | 36 | 41 | 78 | 42 | 0 | 0 |
| Explicit | Broad | 1e-12 | 36 | 53 | 90 | 42 | 0 | 0 |
| Eliminated | Powers | 1e-10 | 33 | 90 | 126 | 40 | 2 | 2 |
| Eliminated | Powers | 1e-11 | 33 | 111 | 146 | 39 | 2 | 1 |
| Eliminated | Powers | 1e-12 | 33 | 119 | 153 | 38 | 0 | 0 |
| Eliminated | Broad | 1e-10 | 36 | 37 | 74 | 42 | 0 | 0 |
| Eliminated | Broad | 1e-11 | 36 | 37 | 74 | 42 | 0 | 0 |
| Eliminated | Broad | 1e-12 | 36 | 38 | 75 | 42 | 0 | 0 |

All 1,297 wrapper solves are classified, including 868 corrections. There are
483 numerical factorizations. All episodes meet the minimum of one correction.
The effect depends strongly on formulation: the strictest target adds only one
solve to eliminated-current broad lifting, but 37 to explicit-current powers
lifting. Neither case reduces iterations or factorizations.

For eliminated-current powers lifting, the strictest target avoids two restarts
but adds 29 corrections: ``126-2+29=153`` total solves. The earlier minimum-three,
default-target control used 114 corrections and 148 solves, also with 33
iterations and 38 factorizations. The stricter target therefore supplies no
additional work-count advantage over that candidate. Their different native
accuracy requirements and subsequent trajectories preclude treating this as a
fixed-matrix comparison or a measured speed ordering.

## A requested target is not a guaranteed final bound

One final direction exceeds its run's target. At iteration 22 of eliminated
powers with target ``10^{-11}``, the initial ratio is ``6.681874\times10^{-6}``.
Nine corrections finish at ``1.190430\times10^{-11}``. Ipopt increases the MUMPS
pivot tolerance from ``10^{-6}`` to ``10^{-3}`` and restarts. The printed ratio
sequence repeats, refinement fails again, and the log reports
`Just accept current solution.` The accepted direction remains about 19% above
the requested target. Two failed episodes here correspond to one recovery
restart and one above-target final direction, not two failed OPF endpoints.

This is consistent with the source's recovery logic: after unsuccessful quality
improvement, a ratio below `residual_ratio_singular` can be accepted even when
it exceeds `residual_ratio_max`. That target controls refinement requests;
it is not an unconditional certificate of the accepted direction. All other
final directions meet their respective targets, including the separate
``10^{-12}`` run. This does not imply that a stricter target monotonically
improves the same linear solve: later iterates, matrices and recovery paths can
change together.

The audit reports both episode-final and direction-final threshold tests.
Discarded recovery attempts are not counted as accepted directions. Native
ratios remain coordinate-dependent algorithmic tests, not standard backward
errors or SI physical residuals.

## Physical and export validation

All twelve endpoints pass independent SI physics, own/full-model feasibility,
baseline reverse-anchor checks, physical objective recomputation and historical
objective correspondence. The fixed objective gate remains absolute ``10^{-6}``
and relative ``10^{-8}``. Complete emitted-constraint coverage passes;
`complete_input_coverage=false` remains the explicit
[inventory limitation](ivr_constraint_inventory.md). Local solver status does not
certify global OPF optimality.

The largest independent residuals over the panel are below
``3.79\times10^{-12}`` V, ``1.15\times10^{-13}`` A and
``1.93\times10^{-10}`` VA, against the unchanged ``10^{-5}`` V,
``10^{-6}`` A and ``10^{-3}`` VA gates. Tightening the native ratio does not show
a useful physical-accuracy improvement at these residual magnitudes.

All twelve BMOPFTools-compatible JSON exports round-trip exactly. Their 25,907
physical leaf paths match across targets, formulations and historical exports.
The largest within-profile endpoint change, normalized as
``|a-b|/\max(1,|a|,|b|)`` in the exported units, is below
``2.62\times10^{-11}``. That descriptive discrepancy is not a new acceptance
tolerance or a claim that all exported values are identical.

## Reproduce the policy audit

For a complete retained log, verify the declared options before interpreting
residual counts. Use the target actually requested by the solver configuration:

```python
import gzip, json, sys
from pathlib import Path
sys.path.insert(0, "examples")
from ivr_refinement_policy import verify_declared_options, audit_counts
with gzip.open("IPOPT.log.gz", "rt") as stream:
    text = stream.read()
target = 1e-11
options = verify_declared_options(text, {
    "min_refinement_steps": 1,
    "max_refinement_steps": 10,
    "residual_ratio_max": target,
    "residual_ratio_singular": 1e-5,
})
report = audit_counts(text, minimum=1, target=target)
print(report["work"]["direction_final_ratios_above_target"])
Path("REFINEMENT.json").write_text(json.dumps(report, indent=2))
```

Positive option-use counts confirm that Ipopt read a setting, not that its
target was attained. Unsupported trace layouts still fail closed. The options
reader and target-sensitive classification bring the policy, trace and native-KKT
regressions to 45 passing Python tests. The prior small-calibration norm audit
remains separate regression evidence. Raw logs, driver, protocol, callbacks,
physical reports, exports, hashes and planning documents remain outside Git in
`OPF_RESIDUAL_TARGET_20261007`.

## What to explore next

Keep minimum one and target ``10^{-10}`` as the general policy. Preserve the
eliminated-powers minimum-three candidate for eventual isolated timing, along
with every tested alternative. There is no basis here for a blanket tighter
target or a speed recommendation.

The observed recovery raises a more direct question: can setting the initial
MUMPS pivot tolerance to its observed recovery value avoid refactorization,
without paying excessive factor-storage or correction costs? That is the next
bounded numerical control to calibrate, with the native refinement policy held
fixed and the same initialization and physical gates. Its effects on factors,
accuracy and runtime must be measured, not inferred from the option name.
Any surviving candidate then needs additional power objectives and networks.
Timing remains deferred; eventual speed assessment must prioritize isolated
Ipopt wall time and exclude compilation.
