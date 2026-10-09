# Initial MUMPS pivot threshold and effective controls

## Question and observation boundary

The [residual-target experiment](ivr_residual_targets.md) recorded repeated
residual sequences after a message requesting increased MUMPS pivot tolerance.
Before using that message to explain solver behavior, this study checks the
**effective threshold reported by MUMPS itself** and compares two initial
thresholds. It leaves the installed solver libraries unchanged.

The matching [Ipopt 3.14.19 interface source](https://github.com/coin-or/Ipopt/blob/releases/3.14.19/src/Algorithm/LinearSolvers/IpMumpsSolverInterface.cpp)
sets `CNTL(1)` from `mumps_pivtol` during symbolic analysis. `IncreaseQuality`
updates the interface's stored value according to

```math
u^+=\min(u_{\max},\sqrt{u}),
```

and requests refactorization. In the inspected source, the numerical
factorization path does not copy that changed value to `CNTL(1)`, and symbolic
analysis is reused. A printed increase request is therefore insufficient
evidence that the numerical factorization used an increased threshold.

The historical eight-profile capture supplies independent runtime evidence:
all **325 numerical factorizations** report an effective threshold of
``10^{-6}``, including three runs with messages requesting ``10^{-3}``.
Buffered reports are reassigned using the previously declared unique matrix
signatures and reconciled against wrapper counts across the complete capture
set. This observation is specific to the retained environment and inspected
release; it does not assert how another Ipopt build behaves.

The new parser field `effective_pivot_threshold` reads the Fortran `CNTL(1)`
report inside each JOB=2 block. Missing values remain unavailable, malformed or
duplicate values are refused, and the interface message is never substituted
for the effective control. Factor-entry counts, real/integer storage and front
size remain distinct quantities; none is process peak memory.

## Calibration and controlled transfer

The [small nonlinear calibration](ivr_native_refinement_policy.md) is repeated
with initial `mumps_pivtol=1e-6` and `1e-3`, each in a fresh Julia process. Both
take seven iterations and 15 linear solves, pass the analytic endpoint checks,
and have identical initial callback arrays and twelve native state vectors.
Every numerical factorization reports its requested initial threshold. JOB=2
and JOB=3 totals reconcile with the Ipopt wrappers. This verifies that the
initial option is applied, independently of later recovery messages.

The OPF transfer crosses those two initial thresholds with the four retained
333-bus exchange-tracking profiles: powers/broad lifting and explicit/eliminated
ordinary transformer currents, with certified zero-load reduction enabled.
Every arm runs in a fresh process, with complete stdout/stderr captured through
process exit to keep buffered Fortran reports attributable to that arm.

The same per-unit bases, objective and physical starts are retained. Refinement
stays at minimum one, maximum ten, target ``10^{-10}`` and singularity threshold
``10^{-5}``. The pivot ceiling remains the native ``0.1``. Strict NLP and
physical gates, scaling, ordering request and one BLAS thread are unchanged.
Verbosity eight and MUMPS print level two supply state, wrapper and factor
reports. All timing remains excluded from assessment.

Baseline callbacks and refinement episodes must reproduce the historical
controls. Within each profile, initial callbacks, native states, layouts and
scales must match. Acceptance also requires independent SI physics,
own/full-model and reverse-anchor feasibility, objective correspondence,
emitted-constraint coverage, canonical physical field paths and JSON round trips.
The known `complete_input_coverage=false` limitation remains explicit.

## Results and interpretation

All eight OPF arms pass the declared gates. The four baseline trajectories
reproduce the historical callbacks and refinement episodes. Within each pair,
the initial callback arrays, twelve native state vectors, coordinate layout and
row scales agree exactly. Every factorization reports the requested initial
threshold; all JOB=2 and JOB=3 counts reconcile with the wrappers.

| Transformer currents | Lifting | Initial pivot threshold | Iterations | Corrections | Linear solves | Factorizations | Refinement failures | Recovery restarts |
|:---|:---|---:|---:|---:|---:|---:|---:|---:|
| Explicit | Powers | 1e-6 | 33 | 84 | 118 | 38 | 0 | 0 |
| Explicit | Powers | 1e-3 | 33 | 33 | 67 | 38 | 0 | 0 |
| Explicit | Broad | 1e-6 | 36 | 36 | 73 | 42 | 0 | 0 |
| Explicit | Broad | 1e-3 | 36 | 36 | 73 | 42 | 0 | 0 |
| Eliminated | Powers | 1e-6 | 33 | 90 | 126 | 40 | 2 | 2 |
| Eliminated | Powers | 1e-3 | 33 | 33 | 67 | 38 | 0 | 0 |
| Eliminated | Broad | 1e-6 | 36 | 37 | 74 | 42 | 0 | 0 |
| Eliminated | Broad | 1e-3 | 36 | 36 | 73 | 42 | 0 | 0 |

The panel contains **671 wrapper solves, 385 corrections and 322 numerical
factorizations**. The larger initial threshold removes all excess corrections
in this panel: each direction needs just the configured minimum one. It removes
the two refinement failures and recovery restarts in eliminated-current powers.
The largest accepted final-direction ratio under that threshold is
``6.165\times10^{-16}``, comfortably below the unchanged ``10^{-10}`` target.
Iteration counts are unchanged in every pair.

This improvement has a storage tradeoff. Maximum actual factor entries increase
by 2.815%, 2.504%, 2.627% and 2.300% for explicit powers, explicit broad,
eliminated powers and eliminated broad, respectively. These are maxima over
each trajectory, not identical-matrix factorization comparisons. Changes in
pivoting, delayed pivots and factor structure can alter factorization cost;
fewer solves alone cannot establish lower wall time.

All endpoints pass independent SI equations and limits, own/full/reverse-anchor
membership and the power objective check. Maximum audited residuals are
``1.137\times10^{-13}`` A, ``1.925\times10^{-10}`` VA and
``3.804\times10^{-12}`` V. Each export retains **25,907 physical field paths**
and passes its JSON round trip. The largest within-pair normalized numeric
export change, ``|a-b|/\max(1,|a|,|b|)``, is ``2.578\times10^{-11}``.
These results establish correspondence on this panel, not complete input-schema
coverage or global optimality.

Compared with forcing more corrections or tightening the residual target,
`mumps_pivtol=1e-3` is the stronger diagnostic candidate here: it reduces
back-solves without adding iterations, while the earlier interventions increased
back-solves. Keep both initial thresholds and every formulation option. Do not
promote the larger threshold to a general default from one network/objective
panel. **Timing remains deferred**; the next solver comparison, when authorized,
should measure these retained candidates with isolated paired Ipopt wall time.
Further solver tuning is lower priority than completing the portfolio's
coverage and reproducibility audit.

The effective-control parser and related diagnostics pass 48 Python regression
tests; re-auditing the prior analytic calibration preserves all 91 residual-norm
and ratio checks.

## Reproduce effective-control checks

For a complete, single-model process log, use both parsers:

```python
import gzip, sys
sys.path.insert(0, "examples")
from ivr_mumps_factor_trace import parse
from ivr_refinement_policy import audit_counts, verify_declared_options
with gzip.open("IPOPT.log.gz", "rt") as stream:
    text = stream.read()
verify_declared_options(text, {"mumps_pivtol": 1e-3, "mumps_pivtolmax": 0.1})
factors = parse(text)
work = audit_counts(text, minimum=1, target=1e-10)
assert factors["complete_pivot_reports"]
assert factors["observed_job_counts"]["2"] == work["trace"]["wrapper_factorizations"]
assert factors["observed_job_counts"]["3"] == work["trace"]["wrapper_solves"]
print([f["effective_pivot_threshold"] for f in factors["factors"]])
```

These assertions require complete capture and a supported wrapper layout; they
must not be applied blindly to a file containing buffered reports from other
models. Historical multi-model captures use signature-based reconciliation.
Positive option-use counts and actual effective controls answer different
questions, so retain both.

The protocol, inspected source provenance, historical reconciliation, raw logs,
calibration, OPF captures, physical exports and planning documents remain outside
Git in `MUMPS_INITIAL_PIVOT_20261009`. No installed dependency is patched, no
external issue is filed, and no timing recommendation follows from this audit.
