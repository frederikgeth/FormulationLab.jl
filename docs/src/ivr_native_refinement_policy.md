# Native refinement-policy calibration

The subsequent [per-unit OPF experiment](ivr_opf_refinement_policy.md) completes
the twelve-solve transfer panel. It finds a profile-specific recovery tradeoff,
but no general advantage from increasing the minimum.

## Question and experimental boundary

The [retained-system precision control](ivr_residual_precision.md) showed that
three Float64 residual corrections resolved seven selected mixed-tolerance
misses. Those were fixed augmented systems evaluated with an independent
backward-error criterion. Before changing an optimizer policy, we must establish
what Ipopt actually counts and tests.

Four small nonlinear solves now calibrate the native `min_refinement_steps`
option: unset, explicitly one, three and four. This is **a solver-control
calibration, not evidence of an OPF speedup**. No production defaults, formulation
options or physical JSON exports change. Timing remains deferred.

## Model, initialization and reference solution

The model is

```math
\begin{aligned}
\min_{x,y,z}\quad &1000(x-1)^2+2000(y-2)^2+7xy+z^2,\\
\text{subject to}\quad &x+y+z=3.5,\quad x^2+y^2\leq8,\\
&\exp(0.1x)+y\geq1,\quad 0.1\leq x\leq4,\quad y\leq5,\quad z=0.5.
\end{aligned}
```

All controls start at ``(1.2,1.8,0.5)``. Eliminating the equality and fixed variable
gives ``y=3-x`` and

```math
f(x)=2993x^2-5979x+3000.25,\qquad
x^*=5979/5986,\quad y^*=3-x^*,\quad z^*=0.5.
```

Positive curvature and satisfaction of the remaining inequalities certify this
as the unique global minimizer. Endpoints are checked directly against the
original equations, bounds, objective and this analytic solution; solver status
alone is insufficient.

The environment uses Ipopt 3.14.19 through Ipopt.jl 1.16.0, MUMPS, one BLAS
thread, `tol=1e-10`, `acceptable_iter=0`, `bound_relax_factor=0`,
`max_iter=100`, `mumps_pivot_order=7`, `max_refinement_steps=10` and
gradient-based NLP scaling. Only the minimum-refinement option changes.
Verbosity 10 provides the diagnostic vectors. The measured objective scaling is
``100/791.6\approx0.12632642748863063``; there is no variable or constraint
scaling. Initial scaled/unscaled callback arrays and all twelve native primal,
slack, multiplier and bound-distance vectors match exactly across controls.

The older native-calibration start ``(3,3,0.5)`` produced second-order correction
steps outside the trace parser's supported layout. This experiment declares a
different, feasible start before running. It does not disable second-order
corrections or loosen the parser. The result is conditional on this small model
and start, rather than a test of every Ipopt recovery path.

## Native stopping test and observability

The matching [Ipopt source](https://github.com/coin-or/Ipopt/blob/releases/3.14.19/src/Algorithm/IpPDFullSpaceSolver.cpp)
computes the residual on all eight primal-dual blocks:
``(x,s,y_c,y_d,z_L,z_U,v_L,v_U)``. Its test is

```math
\rho=\frac{\lVert r\rVert_\infty}
{\min(\lVert q\rVert_\infty,10^6\lVert b\rVert_\infty)+\lVert b\rVert_\infty}.
```

If both solution and RHS norms vanish, it returns the residual norm. This is
the [previously documented native criterion](ivr_refinement_diagnostics.md),
not the offline augmented-system componentwise backward error. A mandatory
correction still runs when the ratio already meets its ``10^{-10}`` target.
Recovery starts a new episode. The source's failure logic also depends on
improvement and strict counter comparisons; this calibration does not establish
that the nominal maximum is a hard cap in every recovery case.

`examples/ivr_refinement_policy.py` first requires a complete supported wrapper
trace. For each successful in-block solve it reads every residual component,
checks all eight block maxima and the aggregate residual maximum, and evaluates
an interval for the ratio. The RHS and solution norms are printed to only three
significant figures, so their decimal rounding intervals bound the denominator.
The resulting interval must intersect the rounding interval of the printed
ratio. All 91 reports pass, including 728 residual-block checks.

This audit verifies **printed norm/ratio consistency**. It does not independently
rebuild the eight-block residual equations or recover full-precision RHS and
solution norms. It must not be described as either a full residual-equation
audit or a condition estimate. Solve counts here are Ipopt wrapper counts;
there is no new independent Fortran JOB-report capture.

## Observed results

Each run has seven initial direction solves and one initialization solve. The
total includes both. No refinement failure or recovery restart occurs.

| Minimum corrections | Iterations | Corrections | Total wrapper solves | Factorizations | Ratio checks |
|:---|---:|---:|---:|---:|---:|
| Unset (default one) | 7 | 7 | 15 | 8 | 14 |
| Explicit one | 7 | 7 | 15 | 8 | 14 |
| Three | 7 | 21 | 29 | 8 | 28 |
| Four | 7 | 28 | 36 | 8 | 35 |

Every episode performs exactly its declared minimum, even though all initial
ratios are below ``1.9\times10^{-16}``. The unset and explicit-one runs have
identical complete callback captures and residual/correction episode sequences.
Increased minima can change intermediate floating-point iterates; equality of
initial states does not imply an identical subsequent path.

All four endpoints coincide in the exported primal variables and objective.
Their maximum original constraint/bound violation is ``4.45\times10^{-16}``
or less, maximum analytic primal discrepancy ``1.65\times10^{-14}``, and
objective discrepancy ``9.05\times10^{-13}``. These satisfy the predeclared
``10^{-9}`` feasibility and ``10^{-8}`` reference gates.

Thus the minimum controls the intended work, but this easy problem gives no
reason to increase it: the additional corrections increase solve counts without
improving the endpoint or iteration count. Runtime was not assessed.

## Reusable calibration example

Run the following from a Julia environment containing JuMP and Ipopt. The model
factory returns an unsolved model; the archive driver separately captures verbose
logs and every callback. This executable example verifies the analytic endpoint
using explicit minimum three. It is not a timing benchmark.

```@example native_refinement_policy
using JuMP, Ipopt
include(joinpath(@__DIR__, "..", "..", "examples", "ivr_refinement_policy.jl"))
model = refinement_policy_model(3)
set_silent(model) # The archived four-arm diagnostic uses verbosity 10.
optimize!(model)
@assert is_solved_and_feasible(model)
x, y, z = value(model[:x]), value(model[:y]), value(model[:z])
@assert maximum(abs.([x-5979/5986, y-(3-5979/5986), z-0.5])) < 1e-8
@assert abs(x+y+z-3.5) < 1e-9
@assert x^2+y^2 <= 8 && exp(0.1x)+y >= 1
(analytic_endpoint_verified=true, minimum_corrections=3)
```

For an archived diagnostic log, use the Python audit and retain its JSON output:

```python
import json, sys
from pathlib import Path
sys.path.insert(0, "examples")
from ivr_refinement_policy import audit
result = audit(Path("min3.log").read_text(), minimum=3)
Path("min3_audit.json").write_text(json.dumps(result, indent=2))
```

Six new tests check full eight-block coverage, print rounding, the denominator
cap and zero branch, incorrect minimum claims, corrupted norms/ratios and
incomplete evidence. Together with the trace and native-KKT regressions,
41 Python tests pass. The frozen protocol, logs, captures, independent analytic
checks, source hashes and planning documents are outside Git in
`NATIVE_REFINEMENT_POLICY_20261007`.

## Next experiment

The native control is ready for a bounded per-unit OPF comparison of minimum
one against three and four on the retained powers/broad-observation and
explicit/eliminated-current profiles. Preserve starts, scaling and strict solver
settings; verify original physical residuals, own/full-model feasibility,
objectives and BMOPFTools-compatible exports. Record corrections and recovery
events alongside iterations and endpoint accuracy. Reject unsupported traces
explicitly. Increased minimum corrections remain experimental until this transfer
is validated, and any speed ranking still requires an admitted isolated Ipopt
wall-clock campaign after the timing deferral is lifted.
