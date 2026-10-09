# Certified removal of fixed operating bounds

## Applicability and equivalence

`fixed_bound_elimination=true` removes an emitted operating row only when its
represented affine or quadratic function depends exclusively on explicitly
fixed, finite JuMP variables and satisfies its scalar bound exactly. The default
is `false`. Bus-voltage, equipment-current/power and IBR operating declarations
are eligible; dispatch boxes remain emitted because generator updates may
replace their bounds. Circuit equations and source-fixing constraints are never
candidates. Unsupported expressions and violated fixed rows remain emitted.

For fixed coordinates ``x_J=a``, let an eligible row be ``f(x_J)\in S``. If
``f(a)\in S``, then

```math
\{x:x_J=a,\;g(x)\le0,\;f(x_J)\in S\}
=\{x:x_J=a,\;g(x)\le0\}.
```

The implementation converts stored coefficients, bounds and fixed values to
exact `Rational{BigInt}` values and evaluates the represented polynomial. It
uses no feasibility tolerance or approximate rationalization. This distinction
matters at nearby floating-point bounds: the real square of the stored value
`0.1` exceeds the stored value `0.01`, so that upper bound is retained as violated.
Earlier rounding in model construction is part of the represented polynomial;
the certificate does not establish exact equivalence to an unrounded physical
coefficient. Independent physical validation remains required.

## Interactions, provenance and reuse

Broad observation lifting can hide fixed inputs behind unfixed auxiliary
variables. Enable `fixed_observation_elimination=true` to expose these inputs;
otherwise the certificate conservatively retains the auxiliary-dependent bounds.
It does not infer values from other equations, starts, equal lower/upper bounds,
or a returned solution. Algebraically constant expressions involving unfixed
variables may also remain uncertified.

Every original operating declaration remains in its provenance table. Removed
rows have `:certified_fixed` or `:partially_certified_fixed` status, their original
constraint objects, exact values/slacks and fixing dependencies. Shared rows are
removed once. The declared-bound and emitted-row inventories still apply. The
nonlinear residual tracer evaluates stored original rows when an emitted row
has been omitted. An empty emitted-row list alone does not mean a missing bound
or an inactive physical limit.

Supported load P/Q and generator bound/cost updates leave these immutable rows
and their fixed-coordinate dependencies unchanged; existing restrictions on
eliminated zero loads still apply. Solving, updating, encoding a physical point,
or cataloguing the model rejects changed or removed fixing dependencies.
Direct JuMP/network edits do not extend the supported update contract; rebuild
the model for changed source phasors, topology, impedances or operating ratings.

No physical coordinate, objective term or recovery equation is removed. The
[SI export](results.md) retains formulation-independent physical tables and adds
`fixed_bound_elimination` and `fixed_bound_report` under `_formulationlab`.
The report records exact rational values and slacks as strings. Dual variables
on omitted redundant rows are not uniquely reconstructed. The certificate is a
feasible-set statement, not a promise of identical solver paths or multipliers.

## Example and validation scope

For a prepared network with source voltage limits, construct a comparison as
follows. Both builds use the same physical input and per-unit power base.

```julia
using FormulationLab, Ipopt
common = (objective=:source_import, s_base=1e5,
          lifting=:bounded_observations, fixed_observation_elimination=true)
control = build_opf(network, IVRNLP(; common...); optimizer=Ipopt.Optimizer)
candidate = build_opf(network,
    IVRNLP(; common..., fixed_bound_elimination=true); optimizer=Ipopt.Optimizer)
certificates = candidate.numerical_diagnostics[:fixed_bound_report]
```

An empty report is a valid applicability outcome. The executable regression
`test/ivr_fixed_bound_tests.jl` builds single-phase, three-wire delta and four-wire
wye cases, compares retained and removed formulations, checks mutual physical-point
membership, performs supported updates and reconciles SI physical exports. It
also tests nearby bounds, stale dependencies, shared rows and retained violated
or unsupported expressions. These checks do not establish a speed benefit.

A read-only preliminary census of the known 32_MVFeeder3323 training case found
six implied source-voltage rows under power lifting; broad lifting exposed the
same six with fixed-observation substitution enabled. All other scanned bounds
remained uncertified. This training observation neither predicts the reduction
on held-out networks nor establishes lower Ipopt wall time. Retain the control
and assess this option through a separately frozen, correctness-admitted study.
