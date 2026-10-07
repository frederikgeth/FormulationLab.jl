# Native refinement policy on per-unit OPF

## Question and scope

Does increasing Ipopt's minimum number of residual corrections improve the
retained OPF profiles? The [small native calibration](ivr_native_refinement_policy.md)
verified the option and printed residual-ratio convention. This experiment
transfers the control to twelve OPF solves: four formulations, each with minimum
one, three and four corrections.

**There is no general benefit demonstrated.** Minimum three avoids recovery and
two factorizations in one profile, at the cost of 22 additional linear solves.
Minimum four loses that recovery advantage and adds an iteration. Broad lifting
retains its iteration and factorization counts while mandatory corrections
increase. These are work-count observations, not runtime rankings. Timing
remains deferred; production defaults and all formulation options are unchanged.

## Controlled design and acceptance

The input is the existing 333-bus `32_MVFeeder3323` DER scenario with 16 ordinary
delta–wye transformers and the declared exchange-tracking power objective.
The four profiles cross explicit/eliminated ordinary transformer currents with
powers-only/broad bounded-observation lifting. Certified zero-load elimination
is enabled throughout. This is the selected panel from the
[joint reduction study](ivr_joint_reductions.md), not a new network sample or
validation across objectives.

All runs use **per-unit coordinates**. The existing regional current and power
bases, voltage bases, lifting bases, physical starts, objective, layout and NLP
scaling are unchanged. The only numerical-policy intervention is
`min_refinement_steps=1,3,4`, in that order within each profile.
`max_refinement_steps=10` explicitly retains the native default. Settings remain
Ipopt 3.14.19/MUMPS, one BLAS thread, gradient-based scaling,
`tol=constr_viol_tol=1e-10`, `acceptable_iter=0`, `bound_relax_factor=0`,
`max_iter=500`, `mumps_pivot_order=7` and the existing diagnostic CPU limit of
300 seconds. Verbosity eight captures native initialization and wrapper events;
there is no full residual-vector or KKT-matrix dump in this experiment.

The four minimum-one controls reproduce their historical complete callback
trajectories and refinement-episode sequences exactly. Within each profile,
all three policies have identical initial scaled/unscaled callbacks and twelve
native primal, slack, multiplier and bound-distance vectors. Constraint scales
and layouts match the historical controls. Scaled/unscaled callback relations
are checked at every iterate.

All twelve solves pass independent SI physics, own/full-model feasibility,
baseline-anchor feasibility in each arm, direct physical objective recomputation,
historical objective comparison and complete emitted-constraint coverage.
Objective comparisons use the predeclared absolute ``10^{-6}`` and relative
``10^{-8}`` tolerances. The [inventory limitation](ivr_constraint_inventory.md)
remains explicit: `complete_input_coverage=false` does not certify all possible
input fields. Local solution status and objective correspondence do not certify
a global OPF optimum.

Each endpoint has a BMOPFTools-compatible JSON export with an exact read/write
round trip. All 25,907 physical leaf paths match both the historical exports and
every formulation/policy arm. Values need not coincide exactly: the largest
normalized change from its minimum-one endpoint is ``1.073\times10^{-6}``, at
an IBR active-power field, with an absolute change of about ``1.073`` microwatts.
The normalization is ``|a-b|/\max(1,|a|,|b|)`` in the exported units; it is a
descriptive discrepancy, not an additional acceptance tolerance.

The initial setup was rejected before any optimization because the historical
option record predates `fixed_observation_elimination`. The comparison now
explicitly supplies its unchanged disabled value, `false`, and requires every
other field to match. The original rejection and correction are archived. No
solver setting or acceptance gate was relaxed.

## Linear-solver work

Totals include one initialization solve per run. A recovery restart is a new
initial solve, not a correction. Numerical factorization counts include the
wrapper's inertia/recovery work; they are not iteration counts.

| Currents | Lifting | Minimum | Iterations | Corrections | Total solves | Factorizations | Refinement failures | Recovery restarts |
|:---|:---|---:|---:|---:|---:|---:|---:|---:|
| Explicit | Powers | 1 | 33 | 84 | 118 | 38 | 0 | 0 |
| Explicit | Powers | 3 | 33 | 108 | 142 | 38 | 0 | 0 |
| Explicit | Powers | 4 | 33 | 134 | 168 | 38 | 0 | 0 |
| Explicit | Broad | 1 | 36 | 36 | 73 | 42 | 0 | 0 |
| Explicit | Broad | 3 | 36 | 108 | 145 | 42 | 0 | 0 |
| Explicit | Broad | 4 | 36 | 144 | 181 | 42 | 0 | 0 |
| Eliminated | Powers | 1 | 33 | 90 | 126 | 40 | 2 | 2 |
| Eliminated | Powers | 3 | 33 | 114 | 148 | 38 | 0 | 0 |
| Eliminated | Powers | 4 | 34 | 152 | 189 | 43 | 2 | 2 |
| Eliminated | Broad | 1 | 36 | 37 | 74 | 42 | 0 | 0 |
| Eliminated | Broad | 3 | 36 | 108 | 145 | 42 | 0 | 0 |
| Eliminated | Broad | 4 | 36 | 144 | 181 | 42 | 0 | 0 |

All 1,690 wrapper solves are classified, including 1,259 residual corrections.
Every recovery episode meets its declared minimum. The 487 numerical
factorizations are wrapper observations; there is no new independent Fortran
JOB-report capture.

For explicit-current powers-only lifting, the corrections beyond the declared
minimum fall from 51 to nine to two. However, mandatory corrections rise from
33 to 99 to 132, so total work increases. Counting only corrections *beyond the
minimum* would misleadingly suggest an improvement.

For eliminated-current powers-only lifting, minimum three removes two restarts
and two factorizations, but adds 24 corrections: ``126-2+24=148`` solves. The
relative wall-clock cost of those operations is unknown here. Minimum four
uses a different floating-point trajectory, takes 34 iterations and has two
restarts again. Recovery avoidance is therefore not monotone in minimum depth.

## Residual quality and its interpretation

Every final direction meets the native ``10^{-10}`` ratio target after recovery.
Four failed recovery episodes across the panel end above it, but their later
replacement directions pass. `audit_counts` records episode-final and
direction-final tests separately, so discarded solves are not confused with
the direction used by the optimizer.

Extra corrections substantially lower some broad-profile direction ratios. With
explicit currents, the maximum final ratio falls from ``6.37\times10^{-11}``
at minimum one to ``6.16\times10^{-16}`` at minimum three. This does not reduce
iterations or establish better physical accuracy. Across all twelve endpoints,
the largest independent residuals are below

| Physical unit | Maximum over all twelve endpoints | Acceptance tolerance |
|:---|---:|---:|
| Voltage (V) | ``3.80\times10^{-12}`` | ``10^{-5}`` |
| Current (A) | ``1.14\times10^{-13}`` | ``10^{-6}`` |
| Power (VA) | ``1.93\times10^{-10}`` | ``10^{-3}`` |

Changes at these magnitudes do not establish a useful physical-accuracy gain.
The native ratio is coordinate dependent and is not a standard backward-error
bound. The earlier small calibration's 91 printed norm checks remain regression
evidence; they are not claimed as full residual-equation audits of these OPFs.
Nor does this experiment evaluate a fixed matrix along a common trajectory:
forcing corrections can alter later iterates and systems.

## Audit a retained log

The reusable helper supports verbosity-eight traces without requiring residual
vectors. Declare the minimum and residual target from the independently recorded
solver settings, and retain the complete log:

```python
import gzip, json, sys
from pathlib import Path
sys.path.insert(0, "examples")
from ivr_refinement_policy import audit_counts
with gzip.open("IPOPT.log.gz", "rt") as stream:
    report = audit_counts(stream.read(), minimum=3, target=1e-10)
assert not report["timing_eligible"]
print(report["work"]["mandatory_corrections"])
print(report["work"]["excess_corrections"])
print(report["work"]["direction_final_ratios_above_target"])
Path("REFINEMENT.json").write_text(json.dumps(report, indent=2))
```

Unsupported second-order correction/restoration layouts, missing residuals and
insufficient correction counts are refused rather than guessed. Physical and
objective acceptance remain separate from successful parsing.

The policy tests now include recovery-aware mandatory/excess work, invalid
targets, and discarded versus retained directions. Together with the trace and
native-KKT regressions, 43 Python tests pass. Protocol, driver, captures,
physical reports, JSON exports, audits and planning documents are retained
outside Git in `OPF_NATIVE_REFINEMENT_20261007`.

## Decision and next controls

Keep the native minimum of one as the general policy. Retain minimum three for
the eliminated-current powers profile as a specific factorization-versus-solve
tradeoff to measure when isolated timing is authorized. There is no evidence
here to promote minimum four or force extra corrections in broad profiles.

The next diagnostic should separate *when* corrections are requested from a
fixed mandatory count: a small, predeclared residual-target control at minimum
one can test whether accuracy-triggered corrections avoid the blanket overhead.
It must retain strict NLP/physical gates and identical initialization. This is
a hypothesis, not an inferred speedup or a reason to weaken tolerances. Broader
objective/network transfer is warranted only for a surviving candidate. Current
best-evidence formulation recommendations remain unchanged, and eventual speed
assessment must use isolated Ipopt wall time, excluding compilation.
