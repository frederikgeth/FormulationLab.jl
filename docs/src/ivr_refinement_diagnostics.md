# Linear-solve refinement after exact reductions

The [joint reduction diagnostics](ivr_joint_reductions.md) found that broad
observation lifting could use larger factors but fewer MUMPS solve calls after
certified zero-load elimination. Reanalysis of the same eight verbose traces now
separates those calls into initial solves, residual corrections and recovery
restarts. **The call reduction is predominantly fewer iterative-refinement
corrections.** This explains the recorded work counts; it does not establish how
much wall time the corrections cost or why the linear systems behave differently.
No new optimizer runs or timing campaigns were performed.

## Method and scope

The input remains the declared 333-bus exchange-tracking scenario, with eight
combinations of zero-load elimination, powers/broad lifting and ordinary-current
retention/elimination. The original solves passed SI physics, own/full-model,
reverse-anchor and objective checks. Their iterations and dimensions matched
silent preflight controls. All options and starts are unchanged.

The new `examples/ivr_refinement_trace.py` reads Ipopt wrapper messages and
primal-dual solve-block boundaries. Within each block it distinguishes the first
solve, later residual-correction solves, and restarts following explicit
pivot-quality or singularity-recovery messages. It retains line numbers and
every printed residual ratio. These categories sum exactly to the wrapper totals
and to the previously reconciled MUMPS JOB=3 counts for all eight models.
Fortran report order is not used to infer the Ipopt event sequence.

The classifier supports the observed Ipopt 3.14.19 layout: one primal-dual block
per iteration, a reported residual after every in-block solve, and explicit
recovery messages. Missing or duplicate residuals, unmatched solve completions,
unknown refactorizations and post-block solves are rejected. Restoration,
second-order correction and other layouts require separate support; this parser
is not a general solver event API. A syntactically accepted trace still requires
the independent capture and physical audits.

The matching [Ipopt full-space solver source](https://github.com/coin-or/Ipopt/blob/releases/3.14.19/src/Algorithm/IpPDFullSpaceSolver.cpp)
performs corrections on the full primal-dual residual. Its default minimum is
one correction per solve episode and its residual-ratio target is ``10^{-10}``.
Recorded settings contain no overrides of these refinement parameters. A restart
begins another episode. Thus a correction can be required even when the initial
ratio is already below the target. The [MUMPS interface source](https://github.com/coin-or/Ipopt/blob/releases/3.14.19/src/Algorithm/LinearSolvers/IpMumpsSolverInterface.cpp)
disables MUMPS internal iterative refinement and calls JOB=3 separately for each
right-hand side. These are distinct from Ipopt's outer corrections.

Direct RHS reports agree with one RHS in 791 of 792 observed calls. One report is
split across a capture boundary and remains unavailable; it is not imputed. The
wrapper/source correspondence supports the single-RHS interpretation without
claiming that every Fortran RHS field was captured.

## Exact decomposition of observed calls

Every run has one wrapper solve before the iteration blocks. The table excludes
that call from the initial column but includes it in the total. A recovery restart
is an additional initial solve, not a residual correction. Failure counts denote
printed refinement-failure events, not failed OPF endpoints.

| Currents | Zero reduction | Lifting | Initial | Corrections | Recovery restarts | Total solves | Refinement failures |
|:---|:---|:---|---:|---:|---:|---:|---:|
| Explicit | Off | Powers | 32 | 66 | 1 | 100 | 2 |
| Explicit | On | Powers | 33 | 84 | 0 | 118 | 0 |
| Explicit | Off | Broad | 36 | 74 | 0 | 111 | 0 |
| Explicit | On | Broad | 36 | 36 | 0 | 73 | 0 |
| Eliminated | Off | Powers | 32 | 51 | 2 | 86 | 2 |
| Eliminated | On | Powers | 33 | 90 | 2 | 126 | 2 |
| Eliminated | Off | Broad | 36 | 67 | 0 | 104 | 0 |
| Eliminated | On | Broad | 36 | 37 | 0 | 74 | 0 |

With zero reduction and explicit currents, broad lifting adds three initial
solves but removes 48 correction solves: ``118 + 3 - 48 = 73``. With eliminated
currents, it adds three initial solves, removes 53 corrections and avoids two
restarts: ``126 + 3 - 53 - 2 = 74``. The corrections beyond the first per episode
fall from 51 to zero and from 55 to one, respectively.

Without zero reduction, broad lifting instead raises the correction counts
from 66 to 74 and from 51 to 67. This confirms an interaction in observed
refinement work, rather than a general advantage of broad lifting. It also shows
why iteration counts and maximum factor entries alone miss part of the work.

Three powers-only runs each report two refinement failures. Each increases the
MUMPS pivot tolerance once. The eliminated-current runs also restart after
pretending the modified system is singular. The explicit-current, unreduced run
accepts one linear solution above the refinement target after recovery; its final
OPF endpoint nevertheless passed the original physical checks. These algorithmic
recovery messages do not establish that the physical OPF is singular or infeasible.

## What the residual ratio can establish

For the matching release, let ``b`` denote the full primal-dual right-hand side,
``x`` its computed solution and ``r`` the corresponding residual. The printed test
uses maximum norms:

```math
\rho = \frac{\lVert r\rVert_\infty}
 {\min(\lVert x\rVert_\infty,10^6\lVert b\rVert_\infty)+\lVert b\rVert_\infty}.
```

If both solution and RHS norms are zero, it returns the residual norm. This
formula comes from `ComputeResidualRatio` in the linked full-space solver source.
It omits the matrix norm and depends on the model's coordinates. Consequently,
smaller values across different formulations do not prove improved conditioning,
a smaller SI circuit residual or a standard normwise backward-error bound.

The correction-count difference is now accounted for, but the explanation for
that difference remains open. Lifting changes the augmented system, scaling,
pivoting and iterate path together. Separating those effects requires additional
controlled diagnostics, ideally matrix/RHS exports at matched physical states
with explicit row and column units. Such work should retain the current strict
solver settings and physical acceptance gates.

## Reproduce the classification

For a retained per-model detailed log:

```sh
python3 examples/ivr_refinement_trace.py /path/to/model.ipopt.log /path/to/trace.json
python3 -m unittest discover -s test -p 'test_ivr_*trace.py'
```

The following small example demonstrates a mandatory correction below the
residual target. Run from the repository root. It supplies a synthetic log, not
an OPF performance result:

```python
import sys
sys.path.insert(0, "examples")
from ivr_refinement_trace import parse
call = "Calling MUMPS-3 for solve.\nDone with MUMPS-3 for solve.\n"
text = "This is Ipopt version 3.14.19, running with linear solver MUMPS.\n"
text += call
text += "*** Solving the Primal Dual System for Iteration 0:\n"
text += call + "residual_ratio = 1e-12\n"
text += call + "residual_ratio = 1e-16\n"
text += "*** Finding Acceptable Trial Point for Iteration 0:\n"
text += "Number of Iterations....: 1\nEXIT: Optimal Solution Found.\n"
result = parse(text)
assert result["counts"]["refinement"] == 1
assert result["corrections_beyond_first"] == 0
assert result["wrapper_solves"] == 3
```

Eleven new classifier tests and eleven existing factor/capture tests pass.
The audit independently verifies all 792 wrapper/JOB=3 totals and preserves the
single unavailable RHS field. Original archived evidence is unchanged; the new
analysis, copied input logs, upstream source files and hashes are retained outside
Git in `REFINEMENT_DIAGNOSTICS_20261007`. No Julia library source, formulation
option, solver tolerance or export contract changes. Timing remains deferred;
the previous admitted speed recommendations are unchanged.
