# Fixed-input observation substitution

## Motivation and exactness

The [KKT provenance study](ivr_kkt_residuals.md) identified six scalar observation
auxiliaries per broad model whose inputs were fixed source voltages. A relative
linear-system residual of one on one of these rows corresponded to an absolute
residual of about ``5\times10^{-36}``. Removing the redundant graph extension
is a useful structural control; that residual alone does not establish a
conditioning problem or predict faster optimization.

Set `fixed_observation_elimination=true` to enable this optional substitution.
The default remains `false`, so the original formulation stays available.
For an affine observation ``u=Ax+c``, the graph formulation and its substitution
are

```math
\{(x,u):u=Ax+c,\ h(x,u)\le0\}
\quad\longleftrightarrow\quad
\{x:h(x,Ax+c)\le0\}.
```

Projection onto ``x`` and reconstruction by ``u=Ax+c`` are inverse maps of
the feasible sets. Objectives that use the same substitution agree. This is
an algebraic statement, not a guarantee of identical floating-point solver
trajectories or multipliers.

The implementation substitutes the **original affine expression**, not a
numerical value evaluated at construction. It applies only to observations
that the lifting policy would otherwise lift, after selection and support
threshold checks. Every variable with a nonzero coefficient in either real or
imaginary part must be explicitly fixed to a finite value. Circuit equations
are not used to infer fixedness. Power lifts are unaffected. The substitution
precedes exact, signed or proportional observation sharing.

## Bounds, recovery and updates

Every operating-limit declaration remains present. A squared-magnitude upper
or lower bound continues to constrain the substituted expression; a zero
magnitude upper bound continues to emit its two real equalities. An inconsistent
fixed bound therefore remains infeasible. The rule neither drops that bound nor
adds a new build-time rejection policy.

Retaining the expression preserves dependencies if a fixed JuMP value changes;
even unfixing an input does not invalidate the algebraic substitution. This
low-level property does not extend the supported network-update contract:
directly changing a JuMP source variable does not update the physical network
data. Use the existing [update and rebuild contract](ivr_nlp.md). Supported load
and generator updates are tested with the option enabled. Physical reconstruction
and the [BMOPFTools-compatible JSON schema](results.md) are unchanged.

Diagnostics expose `fixed_observation_count` and `fixed_observation_report`.
The count measures unique original observation keys selected for substitution.
It need not equal the reduction in complex auxiliaries when several original
keys would otherwise share one lift. Measure actual variable and equation
counts separately. Reported fixed values are explicitly values **at build time**.
The emitted-constraint inventory records `:inlined_fixed_inputs` declarations
with no defining rows, while retaining the physical-bound declarations.
Complete emitted coverage does not establish complete input-schema coverage.

## Executable tutorial

This three-wire delta-load example adds upper line-to-line voltage limits at
the fixed source bus. The three complex observations would otherwise receive
six scalar auxiliaries and six defining equalities. The example checks physical
feasibility, encoding in the original formulation and JSON round-trip recovery.

```@example fixed_observations
using FormulationLab, JuMP, Ipopt
include(joinpath(@__DIR__, "..", "..", "examples", "ivr_compiler_cases.jl"))
net = ivr_compiler_case(conductors=3, segments=2)
net["bus"]["b0"] = Dict{String,Any}(net["bus"]["b0"])
net["bus"]["b0"]["vpp_max"] = fill(440.0, 3)
common = (; objective=:source_import, lifting=:bounded_observations)
reference = build_opf(net, IVRNLP(; common...))
candidate = build_opf(net, IVRNLP(; common..., fixed_observation_elimination=true);
                      optimizer=Ipopt.Optimizer)
removed = num_variables(reference.model) - num_variables(candidate.model)
@assert candidate.numerical_diagnostics[:fixed_observation_count] == 3
@assert removed == 6
result = solve_ivr_nlp_opf(candidate; solver_options=(
    print_level=0, tol=1e-10, constr_viol_tol=1e-10,
    acceptable_iter=0, bound_relax_factor=0.0))
@assert result.solve.optimal
@assert physical_residuals(net, result).passed
point = ACPoint(voltage=result.voltage_candidate, currents=result.current_candidate)
@assert ivr_nlp_point_report(reference, point).passed
data = result_dict(candidate, result)
io = IOBuffer(); write_result(data, io); seekstart(io)
@assert isequal(read_result(io), data)
(removed_scalar_variables=removed, physical_feasibility=true, original_model_feasibility=true)
```

Focused regression cases also cover single-phase two-wire and three-phase
four-wire networks, all four sharing policies, eligibility thresholds, lower
and zero-upper bounds, live dependencies and load/generator updates.

## Retained external experiment

The protocol declared four zero-load-reduced profiles of the same 333-bus
exchange-tracking case, each with substitution disabled and enabled. These are
eight formulation arms, not eight independent networks. Each uses per-unit
coordinates, the same physical start, power objective, MUMPS settings and strict
Ipopt tolerances. Model construction is outside the intended timing metric;
**timing remains deferred** and none of these runs is timing-eligible.

| Transformer currents | Lifting | Variables: retain → substitute | Equations/inequalities: retain → substitute | Ipopt iterations: retain → substitute |
|:---|:---|---:|---:|---:|
| Explicit | Powers | 10,242 → 10,242 | 15,421 → 15,421 | 33 → 33 |
| Explicit | Broad observations | 17,132 → 17,126 | 22,311 → 22,305 | 36 → 36 |
| Eliminated | Powers | 10,146 → 10,146 | 15,325 → 15,325 | 33 → 33 |
| Eliminated | Broad observations | 17,036 → 17,030 | 22,215 → 22,209 | 36 → 36 |

Constraint counts in this table exclude variable-in-set constraints. Each broad
arm substitutes the source bus's three complex line-to-line observations.
All eight solves pass local convergence, physical feasibility, own-model and
full-reference encoding, power-objective agreement and complete emitted-constraint
coverage. In addition, each substituted model accepts the corresponding retained
model's physical endpoint. Objective comparisons use absolute
tolerance ``10^{-6}`` and relative tolerance ``10^{-8}``.

All 25,907 physical export leaf paths agree across formulations, and both
FormulationLab and BMOPFTools readers accept every export. Each paired audit
preserves 1,998 bus-limit declarations and all 15,629 non-lifting declarations,
comparing labels, categories, statuses and associated row counts separately
from auxiliary rows. These are declaration checks, not independent enumeration
of every possible input-schema bound.
Raw runs, the frozen protocol, independent audits and planning documents are
retained outside Git in `FIXED_OBSERVATIONS_20261007`.

The reduction is exact and small on this panel. It provides **no observed
iteration benefit** and no demonstrated wall-time or conditioning benefit.
It remains an experimental option, without changing the best-evidence default.
A subsequent KKT study can test whether it removes the identified trivial
residual rows without worsening the remaining directions. An isolated paired
Ipopt wall-time campaign is needed before any speed recommendation.
