# Matched-state current-unit diagnostics

The [refinement study](ivr_refinement_diagnostics.md) accounts for the additional
linear solves, but does not explain why the formulations need different numbers
of corrections. A first scaling diagnostic compares Jacobians at the **same SI
physical state**, while changing only regional circuit-current units. It calls
no optimizer and supplies no new timing evidence.

## Controlled change at transformer boundaries

The existing 333-bus profiles already use nominal transformer voltage units,
100 kVA source-region current power bases and 1 kVA LV-region current power bases.
They are not unscaled SI models. This diagnostic compares the existing 1 kVA LV
choice with 10 kVA, holding source-region bases, voltage units, all physical data,
power-auxiliary units, dispatch units and the objective fixed. Seeds propagate
through lines and closed switches and stop at transformers.

The panel retains certified zero-load elimination and crosses powers/broad
lifting with explicit/eliminated ordinary-transformer currents. All eight builds
encode one retained powers-only SI endpoint. These are four pairwise scaling
comparisons; Jacobians from differently lifted or reduced formulations are not
identified as the same matrix.

`examples/ivr_matched_jacobian.jl` supplies coordinate maps and covariance checks.
The optional local NLPDiagnostics package evaluates exact symbolic or constructed
AD derivatives. Unsupported derivative methods and incomplete point mappings
are rejected. The helper permits only `current_power_bases` to differ between a
reference and candidate build, checks original network equality, variable and row
identities, positive diagonal maps, circuit provenance, lifting identities and
transformed scalar bounds. It does not change the compiled model.

## Coordinate and row covariance

Let ``x_a=D x_b`` map candidate coordinates to reference coordinates, and let
``f_b(x_b)=R f_a(Dx_b)`` describe the corresponding residual rows. Positive diagonal
``D`` follows from the compiler's projection maps; ``R`` accounts for composed
circuit-row normalization and explicit variable-domain rows. Other row units
remain unchanged. The expected Jacobian relation is

```math
J_b(x_b)=R J_a(x_a)D.
```

Fixed values and lower/upper bounds must transform by the same row multipliers.
The audit checks the coordinate relation, residual values, physical objective
and every Jacobian entry. Its mixed absolute/relative error divides a difference
by ``\max(1,|a|,|b|)``; the acceptance threshold is ``10^{-10}``. Sparse duplicate
entries are summed, and the comparison includes positions absent from either
matrix. No dense whole-model matrix is formed.

This executable example shows why a raw matrix change need not mean a physical
change:

```@example matched_current_units
include(joinpath(@__DIR__, "..", "..", "examples", "ivr_matched_jacobian.jl"))
using SparseArrays
M = IVRMatchedJacobian
rows = [(1, "f", "s"), (2, "f", "s")]
a = (J=sparse([1.0 2.0; 3.0 4.0]), x=[2.0, 3.0], rows=rows,
     names=["x", "y"], values=[4.0, 5.0], objective=8.0)
scaling = (column=[0.1, 10.0], row=Dict(rows .=> [2.0, 0.5]))
b = (; a..., J=spdiagm(0 => [2.0, 0.5])*a.J*spdiagm(0 => scaling.column),
     x=a.x ./ scaling.column, values=[8.0, 2.5])
check = M.compare(a, b, scaling)
@assert check.passed
check
```

For an actual pair of builds and a common `ACPoint`, supply NLPDiagnostics
explicitly. This keeps the research dependency optional:

```julia
using NLPDiagnostics
include("examples/ivr_matched_jacobian.jl")
M = IVRMatchedJacobian
a = M.evaluate(reference_build, physical_point, NLPDiagnostics)
b = M.evaluate(candidate_build, physical_point, NLPDiagnostics)
check = M.compare(a, b, M.maps(reference_build, candidate_build))
@assert check.passed
```

## Observed matched-state results

All eight builds pass original SI physics (through the common endpoint),
full-model membership, their own model membership and emitted-inventory coverage.
The largest scaled Jacobian-entry discrepancy is ``5.97\times10^{-16}``; point,
row-value and physical-objective discrepancies remain below ``3.3\times10^{-15}``.
The exposed rows include variable-domain constraints and therefore differ from
Ipopt's internal constraint counts.

| Currents | Lifting | LV base (kVA) | Variables | Exposed rows | Max transformer row norm | Column norm ratio |
|:---|:---|---:|---:|---:|---:|---:|
| Explicit | Powers | 1 | 10242 | 17067 | 1.000 | 974 |
| Explicit | Powers | 10 | 10242 | 17067 | 1.000 | 974 |
| Explicit | Broad | 1 | 17132 | 23957 | 1.000 | 3.19e+04 |
| Explicit | Broad | 10 | 17132 | 23957 | 1.000 | 3.19e+04 |
| Eliminated | Powers | 1 | 10146 | 16971 | 1.000 | 974 |
| Eliminated | Powers | 10 | 10146 | 16971 | 1.000 | 974 |
| Eliminated | Broad | 1 | 17036 | 23861 | 1.000 | 3.19e+04 |
| Eliminated | Broad | 10 | 17036 | 23861 | 1.000 | 3.19e+04 |

Norms are Euclidean. The last column divides the largest column norm by the
smallest positive column norm; it is not a condition number. Transformer rows
already have unit norms under composed normalization. The 10 kVA change leaves
the full column spread essentially unchanged: approximately 974 for powers-only
and 31,900 for broad lifting. This does not rule out changes to coupling or
factorization behavior. In particular, broad lifting's larger norm spread is
compatible with its fewer refinement calls in the earlier diagnostic traces.

The global summary hides local changes: 4,886 current columns change units in
each pair. Their largest norm is approximately 1.225 at both bases for powers-only,
but rises from 1.414 to 7.176 for broad lifting. The global maximum is instead
determined elsewhere. This localization is more informative than treating an
unchanged global spread as evidence that the intervention had no numerical effect.

Some inequality gradients vanish or are near roundoff at this endpoint. Broad
builds have five exactly zero rows; minimum positive row norms can be around
``10^{-25}``. Raw maximum/minimum row ratios are consequently unstable summaries
and are not interpreted as poor conditioning or active-constraint rank loss.
NLPDiagnostics also returns explicit zero derivative entries for some rows;
stored-entry counts must not be interpreted as structural fill or MUMPS work.

## Validation and reproducibility

The helper passes 74 targeted assertions, including independent single-phase and
delta physical states, copied power-objective definitions, transformed bounds,
and deliberately inconsistent point/matrix/map cases. A small transformer check
also exercises the NLPDiagnostics derivative evaluator. The eight large matrices
are exported with coordinate values, row values, ordering, scaling maps and input
hashes; an independent Python audit checks the numerical covariance and norms.
No full Julia library suite or optimizer endpoint rerun is claimed.

The first large evaluation stalled in fingerprint hashing before evaluating its
Jacobian. A process sample and interruption stack identified repeated alias checks
on `codeunits(payload)` during SHA updates. The completed run uses a private copy
of NLPDiagnostics revision `097a629`, changing only this hashing input to an owned
`Vector{UInt8}`. Both paths match nine independent Python SHA-256 test digests,
including Unicode and block-boundary cases. No derivative or fingerprint content
is changed; the original checkout remains untouched. This preparation issue has
no role in Ipopt performance assessment.

Input logs, the original and patched diagnostic sources, repair records, matrices
and audits remain outside Git in `MATCHED_CURRENT_UNITS_20261007`. All formulation
options and defaults remain available. Timing remains deferred, and no new speed
recommendation follows from these derivative checks.

## Interpretation limits

These matrices are the complete exposed model Jacobians, including explicit
variable-domain rows. They precede Ipopt's internal scaling and fixed-variable
handling. They contain neither the Lagrangian Hessian nor the barrier terms,
regularization, pivoting or right-hand sides of the historical linear solves.
A common physical endpoint also differs from the intermediate iterates where
refinement failed. Thus neither coefficient ranges nor row/column norm spreads
are KKT condition estimates or explanations of the recorded correction counts.

The purpose is to verify a controlled scaling intervention and identify which
parts of the model change numerically. The next step needs matched-state
Hessian/multiplier and barrier conventions before comparing linear systems.
Keep strict physical acceptance checks and refinement settings; changing them
would be a separate experiment.
