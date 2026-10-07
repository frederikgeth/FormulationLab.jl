# Original nonlinear laws and operating-limit residuals

## Purpose and scope

A small residual in one normalized nonlinear row does not, by itself, establish
that the original physical law is satisfied. Exact auxiliary definitions must
also hold. This matters when power columns, load-law rows and voltage observations
use different units. The read-only helper
`examples/ivr_nonlinear_residual_trace.jl` reports the native residual, the
original SI residual and the auxiliary discrepancies that connect them.

This is a **partial provenance catalogue**. It covers constant-power,
constant-current, ZIP and exponential load power laws, plus every original bus
voltage-bound declaration, equipment current/apparent-power limits, dispatch
boxes, generator power definitions and IBR operating limits. Constant-impedance loads are identified separately;
their equations belong to the [linear circuit catalogue](ivr_circuit_residuals.md).
Other constraints are enumerated as outside this catalogue. These include
KCL, other circuit rows, fixed native coordinates and generic lifting definitions.
“Outside scope” does not mean that a constraint is absent from the model.
`complete_model_coverage` is deliberately `false`.

The separate [combined inventory](ivr_constraint_inventory.md) joins this catalogue
to circuit rows, source fixes and auxiliary definitions, and checks coverage
against every current emitted solver constraint.

Recording provenance introduces no variables, constraints, coefficients,
objectives or starts. It changes neither feasibility nor the physical result
export schema. Every transformation option remains available. This work is
about residual interpretation and coverage, not a performance ranking.

## Load-law correspondence

For original coil voltage and current rows ``a_v,a_i`` and reconstructed native
state ``z=Ry``, the physical quantities are

```math
U=V_b a_vz,\qquad I=I_b a_iz,\qquad S=U\overline I.
```

Let ``P`` denote either ``\Re S`` or ``\Im S``, with units W or var, respectively.
The declared demand is ``P_0 f(x)`` where ``x=|U/V_0|^2``. The functions are

| Law | ``f(x)`` |
|:--|:--|
| Constant power | ``1`` |
| Constant current | ``\sqrt{x}`` |
| ZIP | ``a_zx+a_i\sqrt{x}+a_p`` |
| Exponential | ``x^{\gamma/2}`` |

P and Q use their own declared coefficients. No nominal-voltage floor, epsilon
or clipped observation is introduced. Nonlinear evaluations outside their
finite nonnegative voltage-square domain are refused. The compiler's existing
positive engineering voltage-domain requirement remains unchanged.

For row multiplier ``\lambda>0``, a native load-law equality has the form

```math
r_n=\lambda\left(\widetilde P/S_b-P_0f(\widetilde x)/S_b\right).
```

Here ``\widetilde P`` may be a power auxiliary and ``\widetilde x`` a voltage-square
auxiliary. The stored row has the exact declared SI conversion ``S_b/\lambda``.
This is a row conversion, not a bound on the entire reconstructed physical law.
Define the discrepancies

```math
\Delta_P=\widetilde P-P,\qquad
\Delta_D=P_0\left[f(\widetilde x)-f(x)\right].
```

Then, in exact arithmetic,

```math
r_{\mathrm{physical}}
=P-P_0f(x)
=(S_b/\lambda)r_n-\Delta_P+\Delta_D.
```

The trace evaluates all four terms and reports their numerical reconciliation
error. It computes physical power from the original voltage/current rows,
bypassing observation and power auxiliaries. At an assignment violating an
auxiliary definition, the physical and native residuals can therefore differ.
For example, an auxiliary of 1,000 W can satisfy a 1,000 W native load law while
the reconstructed electrical power is 1,150 W. The missing 150 W appears in the
power-definition discrepancy. Such an assignment violates the complete model;
checking the native law alone would overlook it.

These are Float64 diagnostics of the stored model. They are not interval
certificates, bounds over a coordinate domain, proofs of global optimality or
bounds on pre-rounding physical data. In particular, a nonlinear demand error
cannot be replaced by a universal voltage-to-power multiplier without a justified
domain and derivative bound. The separate
[implied-row certificates](ivr_implied_residuals.md) have a narrower linear scope.

## Original voltage declarations and emitted constraints

The compiler records one entry for each declared channel of `v_min`, `v_max`,
`vpn_min`, `vpn_max`, `vpp_min`, `vpp_max`, `vn_max`, `vpos_min`, `vpos_max`,
`vneg_max` and `vzero_max`. Each entry retains the original row, limit in volts,
lower/upper sense and references to the actual emitted constraints.

| Recorded form | Constraint correspondence |
|:--|:--|
| `magnitude_lower`, `magnitude_upper` | One normalized squared-magnitude inequality |
| `zero_upper` | Real and imaginary zero equalities |
| `identically_zero_upper` | No row is needed for an identically zero observation |
| `nonnegative_magnitude` | A zero lower bound is a tautology |
| `coincident_equality` | Both original bounds reference the same exact equality |
| `shared_equality` | A further coincident pair references an existing guarded equality |

Source-fixed or circuit-fixed pairs retained as inequalities still have separate
original records. Counting declarations and counting emitted constraints are
therefore different operations. Shared rows do not erase the declarations they
represent. The catalogue includes the voltage-square load definitions and their
derived variable bounds when counting covered constraints, and deduplicates
shared references.

For an original observation, the report gives its magnitude, limit, slack and
violation in volts. Positive slack denotes satisfaction. The native constraint
residuals remain separate: squared-magnitude constraints have no constant
conversion to a magnitude error in volts. A positive native violation at a
perturbed observation auxiliary can coexist with zero original voltage
violation. Conversely, inspecting an auxiliary without its defining equation
can miss a physical violation.

## Equipment declarations and rating conventions

Equipment entries are recorded when the original network is assembled, before
coordinate reduction. Each retains a `source_path` into the input network,
`source_channel` (or `nothing` for a scalar), `declared_value`, applied divisor,
physical channel, voltage/current basis, and actual emitted constraint
references. Inheritance is recorded per field: a line's explicit `i_max` can
override its linecode while its `s_max` still comes from that linecode.
Equivalent or zero rows cannot identify this provenance reliably by themselves.

| Equipment | Current limit | Apparent-power limit |
|:--|:--|:--|
| Line, both ends | Terminal current, including end shunts | Phase terminal-to-ground voltage times conjugate terminal current |
| Fixed switch, both ends | Terminal current | Terminal-to-ground voltage times conjugate terminal current |
| Generator | Declared coil or terminal arity; delta coil convention takes precedence | Connection-coil power |
| IBR | Declared coil or terminal arity | Connection-coil power for WYE/single-phase; conductor PCC power for three-leg delta |
| Voltage source | Supported terminal currents | Non-neutral terminal powers |
| Ordinary transformer | Delta series-coil current; otherwise terminal current | Existing opt-in `s_rating` convention |
| N-winding transformer | Series-coil current | Coil voltage times conjugate series-coil current |

An ordinary transformer's terminal current may include excitation, grounding
and bond contributions. It must not be substituted for a delta series-coil
current. Under the BMOPFTools nameplate policy, mixed delta–WYE nameplates use
three equal shares on the WYE side with phase terminal currents; the other
supported ordinary transformer types use the existing per-coil nameplate
interpretation. For n-winding transformers, a scalar `s_max` means equal shares
of the winding total under `:bmopftools`, and a per-coil cap under `:ignore`.
A vector is per-coil under both policies. Scalar current caps remain per-coil.
These are the compiler's existing conventions; provenance does not redefine them.

Under `transformer_nameplate=:ignore`, ordinary transformer nameplates remain
visible in `inactive_nameplates`. They are not enforced operating limits under
that policy. This differs from an enforced but identically satisfied limit.
Open-switch zero-current bounds, for example, retain equipment declarations
with `form=:identically_zero_upper` and no emitted row. A zero upper limit on
a nonzero observation references its two real/imaginary equality constraints.

For a current bound, let ``w=I_b a_i z``; for a power bound, let
``w=(V_b a_v z)\overline{(I_b a_i z)}``. The trace evaluates

```math
m=|w|,\qquad \sigma=L-m,\qquad \nu=\max(-\sigma,0).
```

Here ``L`` is the applied SI limit; ``\sigma`` and ``\nu`` are slack and
violation in A or VA. The separately reported `observation_gap_SI` is
``|\widetilde w-w|`` and includes both real and imaginary discrepancies, even
when two observations have equal magnitudes. Native normalized squared rows
remain separate: there is no constant multiplier converting their residual to
an SI magnitude violation. The original rows bypass all observation auxiliaries.
This separation helps diagnose a misleadingly small native bound residual.

## Dispatch declarations and reusable generator updates

The catalogue records each original `p_min`, `p_max`, `q_min` and `q_max`
channel of generators, voltage sources and IBR PCC ports. Generator and
single-phase/WYE IBR dispatch uses connection-coil powers; three-leg IBR
PCC dispatch uses conductor powers. Source powers use terminal-to-ground
voltage. The declaration path, array index, physical channel, quantity, units,
lower/upper sense and actual constraint reference remain explicit.

A phase-only source array is mapped to the non-neutral terminal indices,
including permuted terminal maps. Assembly fills the other entries with
unbounded sentinels; these are not original declarations and do not appear as
neutral limits. A full-terminal array does declare neutral power bounds.
User-supplied nonfinite dispatch limits are refused by the existing compiler.
Absent bounds have no declaration, and diagnostic JSON contains no artificial
infinite limits.

For sources and IBRs, equal lower/upper values share the emitted equality.
Both declarations retain that reference. Their individual SI violations remain
one-sided even though the native equality violation is two-sided. Generator
boxes use separate variable-bound references, including equal lower/upper
values. Generator power definitions are catalogued separately for every P/Q
channel, including generators without any dispatch bounds.

Reusable generator updates may delete or recreate bound constraints. A call to
`catalog` or `trace` resolves generator references from the current model and
limits from the current network data. A previously returned catalogue is a
snapshot and must not be reused after an update. `update_ivr_generators!` is the
supported mutation API; directly editing `build.network` does not update the
model. Invalid updates retain the previous catalogue and model when validation
fails before mutation, consistent with the existing update API contract.

Let ``P`` be the power reconstructed from original electrical rows and
``\widetilde P=B_g g`` the generator dispatch coordinate in SI, where ``B_g``
is its declared power-coordinate base. Define ``\Delta=\widetilde P-P``.
For a bound ``L``, its signed native residual is ``r_b=(\widetilde P-L)/B_g``;
therefore

```math
P-L=B_g r_b-\Delta.
```

The separate generator defining equation uses the assembly base ``S_b``:

```math
r_d=(P-\widetilde P)/S_b,\qquad S_b r_d+\Delta=0.
```

These two conversion factors generally differ. The trace reports the physical
power, modeled power, signed auxiliary discrepancy, SI slack/violation, native
residual and numerical reconciliation error. Source/IBR box expressions directly
use electrical powers with conversion ``S_b``. A generator auxiliary may satisfy
its native box while the physical power violates that box, or conversely; the
defining equation is essential to interpreting either observation. These are
pointwise Float64 checks, not uniform nonlinear error bounds.

## IBR availability, DC-link budgets and internal-voltage references

The catalogue records the remaining supported IBR operating fields at their
emission sites. These declarations are distinct from the per-channel P/Q boxes
and apparent-power/current caps described above.

| Field | Original physical observation | Meaning |
|:--|:--|:--|
| `p_avail` | Sum of active PCC powers | Upper bound in W; a nonnegative availability budget |
| `p_dc_min` | Sum of active internal filter powers | Lower bound in W when `dc_link_coupled=true` |
| `p_dc_max` | Sum of active internal filter powers | Upper bound in W when `dc_link_coupled=true` |
| `v_ref_internal` | Magnitude of each internal filter-coil voltage | Equality in V when `grid_forming=true` |

These are signed active-power sums, not sums of power magnitudes and not
per-channel replicas of the scalar budget. PCC powers follow the original
connection convention: conductor powers for three-leg IBRs, connection-coil
powers for WYE/single-phase IBRs. Internal powers always use filter-coil
voltages and currents. In particular, resistive filter losses separate internal
power from PCC power; substituting one port for the other changes the DC budget.

For original internal or PCC voltage/current rows, the trace reconstructs each
channel's active power and their total:

```math
P_k=\Re\{(V_ba_{v,k}z)\overline{(I_ba_{i,k}z)}\},\qquad P_\Sigma=\sum_k P_k.
```

Power-budget rows use the assembly power base ``S_b``. For a limit ``L``, the
trace compares ``P_\Sigma-L`` with the native signed residual multiplied by
``S_b``, explicitly reporting any numerical difference between evaluating the
stored expression and reconstructing the original rows. Equal DC bounds retain
two declarations pointing to one equality. Their separate lower/upper SI
violations remain one-sided. Absent budgets have no declaration; invalid
nonfinite values, negative availability, uncoupled DC budgets and inconsistent
control flags retain the compiler's existing refusals.

Internal-voltage entries retain each original coil row, the scalar reference
and the actual normalized squared-magnitude equality. They report voltage
magnitude, signed error and absolute violation in volts; native squared-row
residuals stay separate. A dimensionless reconciliation compares the physical
normalized square with the stored row. There is no constant conversion from
squared-row residual to voltage error.

If an internal-voltage row depends only on prescribed source coordinates, the
compiler checks consistency during construction and emits no duplicate voltage
row. The catalogue labels it `source_fixed_check`. This is conditional on the
separate source-coordinate fixes, not an unconditional identity at every native
assignment. The trace evaluates its physical voltage even when its constraint
list is empty. A deliberately perturbed source coordinate must therefore show
a voltage error. Conflicting references continue to be refused at build time;
the existing relative comparison tolerance is unchanged.

## Tutorial

The following single-phase example solves a ZIP load, then inspects an
auxiliary-only perturbation without changing the physical state or re-solving.

```@example nonlinear_trace
using FormulationLab, JuMP, Ipopt
include(joinpath(pkgdir(FormulationLab), "examples", "ivr_compiler_cases.jl"))
include(joinpath(pkgdir(FormulationLab), "examples", "ivr_nonlinear_residual_trace.jl"))
T = IVRNonlinearResidualTrace
net = ivr_compiler_case(conductors=2, segments=1)
d = net["load"]["d1"]
d["model"] = "zip"
d["v_nom"] = [230.0]
for prefix in ("alpha", "beta"), (suffix, coefficient) in zip(("z", "i", "p"), (0.2, 0.3, 0.5))
    d[prefix * "_" * suffix] = [coefficient]
end
options = IVRNLPOptions(s_base=1e5, load_power_lifting=true,
    load_power_base=500.0, load_power_row_scaling=:both, load_power_row_base=100.0)
build = build_opf(net, IVRNLP(options); optimizer=Ipopt.Optimizer)
result = solve_ivr_nlp_opf(build; solver_options=(print_level=0, tol=1e-10,
    constr_viol_tol=1e-10, acceptable_iter=0, bound_relax_factor=0.0))
@assert result.solve.optimal && physical_residuals(net, result).passed
original = T.trace(build)
@assert !original.complete_model_coverage
assignment = Dict(v => value(v) for v in all_variables(build.model))
coordinate = first(values(build.model.ext[:ivr_load_law_rows])).voltage_coordinate
assignment[coordinate] *= 1.01
perturbed = T.trace(build; variable_values=assignment)
@assert [q.physical_residual_SI for q in original.loads] ==
        [q.physical_residual_SI for q in perturbed.loads]
@assert maximum(abs(q.native_residual_SI) for q in perturbed.loads) > 1.0
@assert maximum(abs(q.reconciliation_error_SI) for q in perturbed.loads) < 1e-7
(length(original.loads), length(original.bounds), original.complete_model_coverage)
```

`T.catalog(build)` provides original row and constraint references for inspection.
`T.trace(build, point)` instead encodes a supplied `ACPoint`; missing channels
are refused. A complete assignment can be infeasible, which is useful when
investigating auxiliary discrepancies. Constant-power load updates read current
network targets and current constraint right-hand sides, so the trace does not
retain stale demand values. An absent upper engineering voltage bound is
reported as `nothing`, allowing strict JSON serialization of the diagnostic
report. These reports are separate from BMOPFTools-compatible physical results.


The same catalogue explains an inherited line-current rating in this solved
single-phase model. This diagnostic is separate from the canonical result JSON.

```@example nonlinear_trace
using JSON3
line_limits = filter(q -> q.family == :line && q.field == "i_max", original.equipment)
@assert length(line_limits) == 4 # two conductors at both ends
@assert all(q -> q.source_path == ("linecode", "wire", "i_max"), line_limits)
@assert all(q -> q.violation_SI < 1e-8, line_limits)
@assert all(q -> q.observation_gap_SI < 1e-8, line_limits)
encoded = JSON3.write(original)
@assert length(JSON3.read(encoded).equipment) == length(original.equipment)
[(label=q.label, origin=q.source_path, limit_A=q.limit_SI,
  current_A=q.magnitude_SI, slack_A=q.slack_SI) for q in line_limits]
```


This continuation uses a generator power base of 500 VA and an assembly base
of 100 kVA. It removes and restores a bound, then perturbs only the dispatch
coordinate while keeping the saved electrical state fixed.

```@example nonlinear_trace
net_dispatch = deepcopy(net)
net_dispatch["generator"] = Dict("g" => Dict("bus" => "b1",
    "terminal_map" => ["a", "n"], "configuration" => "SINGLE_PHASE",
    "p_min" => [50.0], "p_max" => [50.0], "q_min" => [0.0], "q_max" => [0.0]))
b_dispatch = build_opf(net_dispatch, IVRNLP(s_base=1e5,
    generator_power_bases=Dict("g" => 500.0), lifting=:powers); optimizer=Ipopt.Optimizer)
r_dispatch = solve_ivr_nlp_opf(b_dispatch; solver_options=(print_level=0,
    tol=1e-10, constr_viol_tol=1e-10, acceptable_iter=0, bound_relax_factor=0.0))
@assert r_dispatch.solve.optimal && physical_residuals(net_dispatch, r_dispatch).passed
saved = Dict(v => value(v) for v in all_variables(b_dispatch.model))
baseline = T.trace(b_dispatch; variable_values=saved)
@assert length(baseline.dispatch) == 4
update_ivr_generators!(b_dispatch, Dict("g" => (p_min=nothing,)))
@assert length(T.catalog(b_dispatch).dispatch) == 3
update_ivr_generators!(b_dispatch, Dict("g" => (p_min=[50.0],)))
@assert length(T.catalog(b_dispatch).dispatch) == 4
perturbed_dispatch = copy(saved)
perturbed_dispatch[only(b_dispatch.generator_variables["g"].p)] += 0.1
shifted = T.trace(b_dispatch; variable_values=perturbed_dispatch)
definition = only(q for q in shifted.definitions if q.quantity == :p)
@assert isapprox(definition.power_auxiliary_gap_SI, 50.0; atol=1e-7)
@assert isapprox(definition.native_residual_SI, -50.0; atol=1e-7)
@assert maximum(abs(q.reconciliation_error_SI) for q in shifted.dispatch) < 1e-7
@assert [q.electrical_power_SI for q in baseline.dispatch] ==
        [q.electrical_power_SI for q in shifted.dispatch]
(quantity=definition.quantity, coordinate_base_VA=definition.physical_scale,
 equation_base_VA=definition.row_scale, discrepancy_W=definition.power_auxiliary_gap_SI)
```


A zero DC-link budget does not imply zero active power at PCC. The following
single-phase example supplies 200 var through a 1 Ω resistive filter. The
converter absorbs a small amount of active power at PCC to cover the filter
loss while its internal active-power total is zero.

```@example nonlinear_trace
net_dc = Dict{String,Any}(
    "bus" => Dict("b" => Dict("terminal_names" => ["a", "n"],
        "perfectly_grounded_terminals" => ["n"])),
    "voltage_source" => Dict("s" => Dict("bus" => "b", "terminal_map" => ["a", "n"],
        "v_magnitude" => [230.0, 0.0], "v_angle" => [0.0, 0.0])),
    "ibr" => Dict("g" => Dict("bus" => "b", "terminal_map" => ["a", "n"],
        "topology" => "SINGLE_PHASE", "prime_mover" => "BATTERY", "s_max" => [2000.0],
        "p_min" => [-100.0], "p_max" => [100.0], "q_min" => [200.0], "q_max" => [200.0],
        "r_filter" => [1.0], "x_filter" => [0.0], "dc_link_coupled" => true,
        "p_dc_min" => 0.0, "p_dc_max" => 0.0, "p_avail" => 0.0)))
b_dc = build_opf(net_dc, IVRNLP(s_base=1e5, objective=:feasibility); optimizer=Ipopt.Optimizer)
r_dc = solve_ivr_nlp_opf(b_dc; solver_options=(print_level=0, tol=1e-10,
    constr_viol_tol=1e-10, acceptable_iter=0, bound_relax_factor=0.0))
@assert r_dc.solve.optimal && physical_residuals(net_dc, r_dc).passed
t_dc = T.trace(b_dc)
pcc = only(q for q in t_dc.ibr_power if q.field == "p_avail")
dc = only(q for q in t_dc.ibr_power if q.field == "p_dc_max")
@assert pcc.total_power_W < -0.1
@assert abs(dc.total_power_W) < 1e-6
shared = filter(q -> startswith(q.field, "p_dc"), T.catalog(b_dc).ibr)
@assert shared[1].constraints == shared[2].constraints
@assert all(abs(q.reconciliation_error_W) < 1e-8 for q in t_dc.ibr_power)
(pcc_W=pcc.total_power_W, internal_W=dc.total_power_W,
 filter_loss_W=dc.total_power_W-pcc.total_power_W)
```

## Verification and remaining coverage

Independent manufactured states span single-phase, three-wire delta and
four-wire WYE loads; three voltage-dependent laws; direct and lifted powers;
independent row units; and full/reduced coordinates. Auxiliary perturbations
leave original physical residuals unchanged and satisfy the reconciliation
identity within the tested floating-point tolerance. Every bus voltage-bound
family is tightened and compared with the independently evaluated original
network. Further tests cover zero limits, fixed magnitude domains, shared
coincident rows, constant-power updates and strict JSON without infinite values.

The remaining task is to reconcile the circuit and nonlinear catalogues with
every emitted row, including generic auxiliary definitions and fixed native
coordinates. Covered operating fields should not be confused with a complete
solver-row inventory; `complete_model_coverage` remains `false`.

### Controlled evidence, 7 October 2026

Canonical solver-model fingerprints match the preceding commit in all **108**
cases crossing conductor count, load law, lifting/row units and interval,
coincident or duplicate voltage declarations. The fingerprints include every
scalar constraint function and set, variable identity/name/start, objective and
sense; stored numeric coefficients are compared by bit pattern. This supports
the intended metadata-only change on that panel, not a proof for all inputs.

A separate **24-case** live panel crosses two/eight non-star multiwinding units,
cost/tracking power objectives, explicit/eliminated multiwinding currents and
powers/coils/all observation lifting. All original physical, own/full-model,
reverse-anchor and independent winding-equation gates pass. It reports 2,160
load P/Q rows and 6,480 original voltage declarations. Independent checks compare
1,080 complex load residual aggregates and 2,160 voltage-bound field aggregates.
The largest load discrepancy is below ``5.6\times10^{-14}`` VA; voltage-limit
violation differences are zero. Maximum load-law reconciliation error is below
``4.8\times10^{-14}`` VA. These are observed discrepancies, not guaranteed error
bounds.

All 24 canonical SI exports pass both FormulationLab and BMOPFTools readers.
Every physical leaf path agrees across tested formulations at each network
size. The 2,160 exported load P/Q values agree with the independently reconstructed
trace powers to below ``5.7\times10^{-14}`` VA. No schema field was added to the
physical result contract by this provenance catalogue. The initial experiment
script incorrectly used a generic JSON writer on a canonical result containing
a legacy NaN; switching to `write_result` preserved the existing result contract.
That failed attempt and its partial file are retained.

All data, model fingerprints, development failures and validation logs are
outside Git in `NONLINEAR_PROVENANCE_20261007`. The live panel is deliberately
correctness evidence; it supplies no wall-time ranking and changes no numerical
recommendation.

### Equipment extension evidence, 7 October 2026

The equipment extension passes **4,420 targeted assertions**. Manufactured
states compare tightened limits against the independent original-network
auditor across two-, three- and four-conductor circuits, line shunts,
forward/reverse switch and IBR flows, all six ordinary transformer types,
scalar/vector winding ratings and both nameplate policies. Full/reduced
coordinates, two assembly power bases and direct/lifted observations are
included. Zero limits, open-switch tautologies, strict diagnostic JSON and an
auxiliary-only perturbation have separate checks.

All **222** solver-model fingerprints match commit `2924367`, including 114
additional equipment cases. The 24-case live panel retains the preceding
physical and export gates and traces **13,296 equipment declarations**.
All **4,416** aggregate equipment-violation comparisons agree with the independent
SI auditor, with zero observed discrepancy. The live solutions are feasible;
the manufactured tightened-limit tests provide the complementary nonzero
violation evidence. Every canonical export passes both readers, and physical
leaf paths remain invariant across formulations at each network size.

The initial development checks exposed a switch audit-label mismatch, an
islanded open-switch test fixture and standalone-driver errors. These were
corrected without changing the electrical equations. The failures, revised
scripts, fingerprints, full test logs and raw records are retained outside Git
in `EQUIPMENT_LIMIT_PROVENANCE_20261007`. This extension supplies no performance
ranking and leaves `complete_model_coverage=false`.

### Dispatch extension evidence, 7 October 2026

The dispatch extension passes **23,952 targeted assertions**. Independent
manufactured states cover every P/Q lower/upper field and each declared
channel for generators, sources and IBRs on two-, three- and four-conductor
circuits. Tests cross full/reduced coordinates and assembly bases of 1 kVA and
100 kVA, with generator power-coordinate bases tested separately. Tightening a
single field/channel produces the expected 10 W or 10 var violation and agrees
with the independent original-network auditor.

Reusable tests cross interval, equal, one-sided and absent boxes, restoration,
price-only updates and rejected updates. They compare fresh and reused traces,
check reference validity after deletion, and deliberately perturb generator
power coordinates. Further tests cover permuted source terminal maps,
phase-only versus full-terminal arrays, scalar declarations, shared equality
references and refusal of nonfinite user limits.

All **354** prior/current solver-model fingerprints match commit `de7d3a7`.
This includes the preceding 222 cases, 84 reusable-update states and 48
source/IBR box cases. The live 24-case panel traces **2,880 dispatch declarations**
and **960 generator power definitions**. All 2,880 aggregate dispatch-violation
comparisons agree with the independent SI auditor to below
``2.9\times10^{-14}`` W/var. Bound deletion/restoration preserves the trace at
the saved electrical and dispatch assignment in every live case. All canonical
exports pass both readers with unchanged physical field paths.

Two development test errors are retained: a missing per-unit-to-SI conversion
when constructing test limits, and an untyped empty-vector comparison in the
fully unbounded case. Neither required changing the solver formulation.
Raw data, failures, scripts, source snapshots and verification logs remain
outside Git in `DISPATCH_PROVENANCE_20261007`. This is correctness evidence;
there is no new wall-time ranking or formulation recommendation.

### IBR extension evidence, 7 October 2026

The IBR extension passes **9,828 targeted assertions**. Manufactured SI states
cover every available-power/DC field, forward and reverse flow, equal and
one-sided budgets, single-phase/three-leg/four-leg devices, two assembly bases,
full/reduced coordinates and direct/lifted powers. Separate balanced witnesses
check every internal-voltage channel with shifted references, filter-free
source-fixed checks, perturbed fixed coordinates and conflict refusals.

All **534** prior/current canonical solver-model fingerprints match commit
`dbbd972`: the preceding 354 cases plus 180 additional IBR cases. The 24-case
multiwinding panel traces **720 IBR power declarations**, all agreeing with
independent aggregate physical violations. A separate **24-case grid-forming
panel** spans the three topologies, filtered/filter-free connections, two
assembly bases and two lifting modes. Its **56 internal-voltage declarations**
include **28 source-fixed checks**. Maximum observed voltage violation is below
``1.2\times10^{-13}`` V, and aggregate voltage violations agree with the independent
auditor with zero observed discrepancy.

All **48 canonical exports** pass both readers. There are 888 exported IBR
channel-power comparisons and 56 internal-voltage comparisons against the
original-row trace. Maximum discrepancies are below ``8.6\times10^{-14}`` W and
``2.9\times10^{-14}`` V, respectively. Maximum budget reconciliation error is
below ``1.5\times10^{-11}`` W. These are observed Float64 discrepancies, not
certified error bounds. Field paths remain invariant across tested lifting and
base choices at each network size/topology.

The zero-DC-budget tutorial additionally demonstrates active absorption at PCC
for reactive delivery through a resistive filter. Raw panels, scripts, model
fingerprints, source snapshots and verification logs are archived outside Git
in `IBR_PROVENANCE_20261007`. These are correctness results and do not change
any wall-time ranking, formulation default or transformation option.
