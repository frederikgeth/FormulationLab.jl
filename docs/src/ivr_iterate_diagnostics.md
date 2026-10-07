# Intermediate states and linear-solve diagnostics

The [refinement audit](ivr_refinement_diagnostics.md) identifies extra linear
solves that iteration counts hide. The [matched-state Jacobian experiment](ivr_matched_jacobian.md)
does not explain those differences using endpoint column norms. The next step
is to retain intermediate primal and dual states, associate them with the native
refinement trace, and evaluate model derivatives at those states.

## Capture contract

`examples/ivr_iterate_capture.jl` uses the intermediate callback and
`GetIpoptCurrentIterate` interface of Ipopt.jl 1.16.0. It captures every regular
iteration, including iteration zero and the final endpoint. Both scaled and
unscaled arrays contain the TNLP primal vector, lower/upper variable-bound
multipliers, constraint values and constraint multipliers. Callback scalars
include the objective, infeasibilities, barrier parameter, regularization and
step lengths. No derivative evaluation occurs inside the callback.

Here **unscaled means the model's coordinates**, which are generally per-unit;
it does not mean SI. The solver's original TNLP arrays include fixed variables
even when Ipopt removes them internally. Variable-domain bounds are separate
from the constraint-value vector. The helper records a complete map from solver
columns and scalar constraint rows to JuMP identities; missing or ambiguous
rows cause a refusal. Legacy opaque NLP blocks and restoration iterations are
outside the supported scope. An existing callback is not replaced.

Post-solve evaluation verifies each captured objective and constraint vector.
For a minimization model it evaluates

```math
J = \nabla g(x), \qquad
H = \nabla^2 f(x) + \sum_i \lambda_i\nabla^2 g_i(x),
```

and reports the maximum norm of

```math
\nabla f(x) + J^\mathsf{T}\lambda - z_L + z_U.
```

These are the unscaled Ipopt multiplier signs, with objective factor one.
Hessian contributions are normalized to the lower triangle; repeated positions
must be summed. Quadratic and nonlinear MOI blocks may use opposite triangles.
The export preserves all contributions rather than discarding duplicates.

## Associate the correct solver stage

`examples/ivr_iterate_trace.py` joins the callback iteration index to the
restricted Ipopt 3.14.19 trace accepted by the refinement parser. It checks that
the callback barrier agrees with the beginning-of-iteration report, then records
the separately printed barrier parameter used after the barrier update. It
also retains every reported regularization attempt and counts factorizations,
corrections and recovery restarts in the following direction block.

This distinction matters: the barrier can decrease **after** the callback.
Similarly, the callback regularization scalar must not be substituted for the
regularization attempts printed during the following direction solve. Direction
barrier values have reduced print precision. The final callback has no following
direction block. Unsupported, incomplete or ambiguous associations are refused.

## Reproduce the workflow

An executable example checks the capture and derivative contract:

```@example iterate_capture
using JuMP, Ipopt
include(joinpath(@__DIR__, "..", "..", "examples", "ivr_iterate_capture.jl"))
C = IVRIterateCapture
m = Model(Ipopt.Optimizer)
@variable(m, 0.1 <= x <= 4, start=1.2)
@variable(m, 0.1 <= y <= 4, start=1.1)
@constraint(m, x + y == 3)
@objective(m, Min, 1000*(x-1)^2 + 2000*(y-2)^2)
set_optimizer_attribute(m, "print_level", 0)
trace = C.attach!(m)
optimize!(m)
@assert is_solved_and_feasible(m)
capture = C.finish(m, trace)
derivatives = C.derivatives(m, trace.records[end])
@assert !capture.timing_eligible
@assert derivatives.value_gap <= 1e-10
println("Complete callback coverage and endpoint derivatives verified.")
```

Run this small example from the repository root using the test environment:

```julia
using JuMP, Ipopt, JSON3
include("examples/ivr_iterate_capture.jl")
const C = IVRIterateCapture
model = Model(Ipopt.Optimizer)
@variable(model, 0.1 <= x <= 4, start=1.2)
@variable(model, 0.1 <= y <= 4, start=1.1)
@constraint(model, x + y == 3)
@objective(model, Min, 1000*(x-1)^2 + 2000*(y-2)^2)
set_optimizer_attribute(model, "print_level", 7)
trace = C.attach!(model)
optimize!(model)
@assert is_solved_and_feasible(model)
capture = C.finish(model, trace)
derivatives = C.derivatives(model, trace.records[end])
@assert !capture.timing_eligible
@assert derivatives.value_gap <= 1e-10
open(io -> JSON3.write(io, capture), "iterates.json", "w")
```

Retain the native stdout log of the same solve, then associate it with the
capture. The restricted parser may decline a different solver event layout.

```sh
python3 examples/ivr_iterate_trace.py solve.log iterates.json association.json
julia --project=test test/ivr_iterate_capture_tests.jl
python3 -m unittest discover -s test -p 'test_ivr_*trace.py'
```

## Interpretation limits

The exported Hessian is a **model Lagrangian Hessian**, not the internal KKT
matrix. The callback does not expose inequality slack states, internal bound
adjustments, barrier contributions, pivot permutations, regularized matrices or
historical refinement right-hand sides. Constraint multipliers from different
lifted formulations are not interchangeable. Matching iteration numbers across
formulations does not match their physical states.

An intermediate iterate need not satisfy the physical equations or lifted
defining equations. Transporting only its reconstructed electrical phasors to
another formulation can discard auxiliary residuals; it is a new intervention,
not a reproduction of the historical system. Any subsequent KKT reconstruction
must state those choices and verify the missing conventions independently.

All instrumented runs are excluded from timing recommendations. Canonical SI
endpoint exports retain their existing schema; the new diagnostic JSON files
are separate artifacts. No formulation option, solver tolerance or default is
changed.

## Declared 333-bus tracking experiment — 7 October 2026

Four zero-reduced profiles cross powers/broad lifting with explicit/eliminated
ordinary transformer currents. The physical input, unloaded starts, objective,
units and numerical settings match the earlier joint preflight. Native verbosity
and callback capture are diagnostic interventions; no times are admitted.

All four endpoints pass original SI physics, own/full-model membership, a reverse
anchor check, emitted-constraint coverage and independently evaluated power
objective checks. They retain the original iteration counts and objective
agreement. All **142 callback states** re-evaluate successfully: normalized
constraint/objective discrepancies are below ``2\times10^{-16}``. Canonical SI
endpoint exports round-trip through the native reader. Input-schema coverage
remains incomplete; this adds no new device support.

| Ordinary currents | Lifting | Callback states | Refinement corrections | Corrections beyond the first per episode | Such extra corrections in direction blocks with no reported regularization |
|:---|:---|---:|---:|---:|---:|
| Explicit | Powers | 34 | 84 | 51 | 51 |
| Explicit | Broad | 37 | 36 | 0 | 0 |
| Eliminated | Powers | 34 | 90 | 55 | 49 |
| Eliminated | Broad | 37 | 37 | 1 | 1 |

The independent Python audit finds identical per-iteration solve classifications,
printed residual-ratio sequences, recovery events and factorization totals to
the earlier traces. It also recomputes stationarity from the exported Jacobians
and multipliers. Fourteen derivative snapshots were preselected from the old
logs: the initial/final states and the two iterations with most corrections,
with ties resolved by earliest iteration and duplicates removed.

**Explicit KKT regularization cannot by itself explain the extra corrections.**
All 51 extra corrections in the explicit-current powers profile occur in blocks
whose reported regularization is zero; so do 49 of 55 in the eliminated-current
profile. This does not remove barrier diagonals, scaling, pivoting or inaccurate
factor solves as possible explanations. Several difficult iterations follow a
barrier decrease, but that association alone does not establish causality.

Broad lifting has 34,352 Hessian contributions versus 124,766 for powers-only
in these model-derivative exports. These counts include repeated structural
positions and possible numerical zeros; they are not factor nonzeros, rank or
conditioning measures. They identify a change in where nonlinear curvature is
represented, which merits a controlled comparison after the missing KKT
conventions have been supplied.

The new tests include mixed quadratic/nonlinear cross terms, duplicate Hessian
positions, fixed variables, multiplier signs and gradient-based scaling. The
initial large-case export attempt refused mixed Hessian triangles; that attempt
and its repair are retained. Final code, logs, input, selection, captures,
derivatives and independent audits are archived outside Git in
`ITERATE_DIAGNOSTICS_20261007`. Previous speed recommendations remain unchanged.

The subsequent [native augmented-system audit](ivr_native_kkt.md) obtains the
missing internal slack/bound quantities from diagnostic output and checks the
reconstructed blocks against Ipopt's printed matrix. It also makes the additional
automatic inequality-row scaling in broad lifting explicit.
