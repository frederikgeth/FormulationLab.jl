# Emitted-constraint inventory

## Question and scope

Does every scalar constraint in the current exact-IVR model have recorded
provenance? The read-only helper `examples/ivr_constraint_inventory.jl` answers
this narrower, testable question by joining the [circuit catalogue](ivr_circuit_residuals.md)
and [nonlinear catalogue](ivr_nonlinear_residuals.md), source-coordinate fixes,
load auxiliary domains, and generic lifting definitions.

This is an inventory of **emitted constraints**, not a proof that every possible
input field has been implemented. `complete_input_coverage` remains `false`.
Input coverage also requires the [schema inventory](schema_fields.md), independent
physical evaluations, and component-specific equivalence tests. Neither flag
certifies feasibility, conditioning, global optimality, or speed.

## Reconciliation criterion

Let ``E`` be all current JuMP constraints, including variable bounds and fixes.
For each recorded declaration ``d``, let ``R_d`` be its set of emitted references.
The inventory constructs

```math
C=\bigcup_d R_d,\qquad U=E\setminus C.
```

Every reference in ``C`` must be valid in the current model. Completeness is
reported exactly when ``U=\varnothing``. A missing required registry, stale
reference, duplicate reference within a declaration, inconsistent circuit
omission, changed retained circuit equation, or changed source fix raises an
error. Additional user constraints appear in ``U``; they are never silently
classified. Reusable generator updates resolve their current bound references
on each call.

The declaration-to-row relation is deliberately many-to-many. Real and imaginary
circuit equations give two scalar references. Coincident bounds can share one
equality. Tautologies and eliminated equations retain declarations with no
emitted references. Counting declarations as solver rows would therefore be
incorrect. `shared_constraints` reports multiplicity explicitly.

## Circuit units and auxiliary definitions

Circuit emission records the actual positive divisor ``d`` applied to the
original complex row ``a z``. If its assembly scale is ``s`` in amperes or volts,
the emitted scalar residuals ``r_r,r_i`` imply the complex physical residual

```math
|saz|=sd\sqrt{r_r^2+r_i^2}.
```

The live catalogue retains ``s`` and ``d`` separately. Eliminated rows have no
solver divisor and remain subject to [implied-row certification](ivr_implied_residuals.md).
Source fixes retain the original coordinate, singleton reconstruction coefficient,
native coordinate, original value, and actual real/imaginary fix references.

Generic power and observation lifts retain their definition references and
row/column scaling metadata. A shared affine observation can serve more than one
physical use; the inventory does not infer an SI unit merely from its algebra.
Use the original operating-limit and physical-residual catalogues for that
interpretation. Objective-created lifts use the same definition registry.

## Tutorial: coverage, added constraints, and JSON

No optimization is needed to inspect the inventory:

```@example constraint_inventory
using FormulationLab, JuMP, JSON3
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "ivr_compiler_cases.jl"))
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "ivr_constraint_inventory.jl"))
const Inventory = IVRConstraintInventory
net = ivr_compiler_case(conductors=2, segments=2)
b = build_opf(net, IVRNLP(lifting=:bounded_observations,
    specialization=:conductor_difference, linear_elimination=:passive_blocks))
c = Inventory.catalog(b)
@assert c.complete_emitted_coverage
@assert c.covered_constraint_count == num_constraints(b.model; count_variable_in_set_constraints=true)
@assert !c.complete_input_coverage
(covered=c.covered_constraint_count, declarations=length(c.declarations))
```

Adding a custom constraint illustrates why coverage must be recomputed:

```@example constraint_inventory
extra = @constraint(b.model, b.coordinates.real_variables[1] <= 100.)
c = Inventory.catalog(b)
@assert !c.complete_emitted_coverage
@assert c.uncovered_constraints == [extra]
delete(b.model, extra)
@assert Inventory.catalog(b).complete_emitted_coverage
nothing # hide
```

The report is a separate diagnostic JSON document:

```@example constraint_inventory
report = Inventory.report(b)
serialized = JSON3.write(report)
@assert JSON3.read(serialized).complete_emitted_coverage
report.schema
```

`catalog` exposes live JuMP references and detailed metadata. `report` exposes
JSON-compatible declaration identities, statuses, row identifiers, shared rows
and uncovered rows. Identifiers are local to one inventory and must not be
compared across rebuilds or reused as persistent solver identifiers. This
diagnostic does not extend or alter the [canonical BMOPFTools-compatible SI result
contract](results.md).

## Validation and limitations

Regression tests cover single-phase, delta and explicit-neutral circuits;
constant-current, ZIP and exponential laws; power and observation lifting;
power row/column scaling; reduced coordinates; source fixes; and filtered and
filter-free IBR references. Negative tests damage provenance and add or delete
constraints. Numerical panels additionally exercise transformer elimination,
power-based objectives and deletion/restoration of generator dispatch bounds.

Reference coverage cannot detect a declaration that was omitted from both the
model and all provenance. It also cannot, by itself, establish that an emitted
nonlinear inequality represents the intended input semantics. Those questions
remain the responsibility of independent schema, bound, physical-law and
export tests. All transformation options remain available. Inventory checks
are excluded from optimizer-call timing.
