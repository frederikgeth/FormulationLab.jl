# Tutorial: build, verify and reuse an exact IVR model

This tutorial starts with a two-wire feeder whose solution can be calculated by
hand. It then checks conductor specialization, demand reuse, generator prices
an inverter's internal budget, a fixed regulator and voltage-dependent demand. Finally it deliberately violates a bound and
adds an earth-current path that invalidates the reduction certificate.

The learning objective is to distinguish **physical correctness**, **equivalent
representation** and **computational reuse**. None implies global optimality.
Read [the motivating examples](ivr_examples.md) for the engineering questions
and [the equations](ivr_theory.md) for the mathematical assumptions.

![Two-wire service with a grounded source neutral and floating load neutral.](assets/ivr_two_wire.svg)

*Figure 1. Analytical operating point of the tutorial service. Values are rounded;
all equation checks use unrounded phasors.*

## 1. Reproduce the environment and case

From a checkout of FormulationLab, prepare the test environment and run the
standalone tutorial:

```sh
julia --project=test -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=test examples/tutorial_exact_ivr.jl
```

The examples use FormulationLab, JuMP and Ipopt. Ipopt is a caller/test dependency;
loading FormulationLab alone does not select a nonlinear solver. No proprietary
solver, external feeder file or service is needed. Documentation builds execute
the same teaching functions. The outputs below come from execution, rather than
manually maintained result tables. Last digits may vary by solver version.

```@example exactivr
using FormulationLab, Ipopt, JuMP
include(joinpath(pkgdir(FormulationLab), "examples", "tutorial_exact_ivr.jl"))
const T = ExactIVRTutorial
net = T.two_wire_case()
net["line"]["service"]
```

There are two ordered terminals, `["a", "n"]`, at both buses. Only the **source**
neutral is ideally grounded. Source phasors are 230 V and 0 V with zero angles
(angles are radians). The service has inline absolute conductor resistances
0.2 Ω and 0.3 Ω, zero reactances/mutual terms/shunts, and 40 A ratings on both
conductors. The load consumes 2000 W and 0 var between phase and neutral.
Downstream bounds are 180–260 V phase-neutral and at most 30 V neutral-ground.

The example uses a native dictionary. Dictionary acceptance does not imply
external schema validation. For file input, use `read_bmopf("network.json")`,
inspect its retained parser diagnostics, then check formulation applicability.
No example repairs a real feeder's source accounting or unsupported controls.

## 2. Build and solve the declared problem

```@example exactivr
full = build_opf(net, IVRNLP(objective=:source_import);
                 optimizer=Ipopt.Optimizer)
result = solve_ivr_nlp_opf(full; solver_options=T.SOLVER_OPTIONS)
@assert result.solve.optimal
(status=result.solve.termination_status, source_import_W=result.objective)
```

The script uses `tol=constr_viol_tol=1e-10`, `acceptable_iter=0` and
`max_iter=600`. These are explicit settings for these small examples, not
recommended defaults for every network. `LOCALLY_SOLVED` meets this API's strict
solver acceptance; `ALMOST_LOCALLY_SOLVED` does not. Unaccepted results publish
empty candidate dictionaries and a `NaN` objective. Check status before using
the candidate. A local solver status is not a global certificate.

To read Ipopt's wall-clock solve time separately from model construction and
result extraction:

```@example exactivr
ipopt_seconds = JuMP.solve_time(full.model)
@assert isfinite(ipopt_seconds) && ipopt_seconds >= 0
(ipopt_wall_seconds=ipopt_seconds,)
```

This is the solver-interface timer described in the
[performance guide](ivr_performance.md), including solver-side setup. This
single tutorial observation has no excluded warm-up and is not a comparative
performance estimate. A proper ranking still requires repeated accepted solves.

## 3. Check the physics and the analytical answer

```@example exactivr
physical = physical_residuals(full.network, result)
point = ACPoint(voltage=result.voltage_candidate, currents=result.current_candidate)
encoded = ivr_nlp_point_report(full, point)
@assert physical.passed && encoded.passed
(SI_maxima=physical.maxima,
 model_violation=encoded.max_constraint_violation,
 reconstruction_error_pu=encoded.max_reconstruction_residual_pu)
```

These checks answer different questions. `physical_residuals` evaluates the SI
network equations and assessed limits independently of the formulation's
stamping. Its default tolerances are ``10^{-5}`` V, ``10^{-6}`` A and
``10^{-3}`` VA (W/var residuals share the power tolerance); unassessed items
prevent `passed=true`. `ivr_nlp_point_report` binds observations and evaluates
the actual JuMP constraints, using a default ``10^{-7}`` tolerance in the
model's normalization. These residuals have different units and are not
interchangeable. Neither check certifies the objective is globally minimal.

For this resistive unity-power-factor case,
``u^2-230u+0.5(2000)=0``. The high-voltage root gives the load phase-neutral
voltage; the 180 V lower bound excludes the other root.

```@example exactivr
u_exact = (230 + sqrt(230^2 - 4*0.5*2000))/2
I_exact = 2000/u_exact
U_n_exact = 0.3I_exact
loss_exact = 0.5I_exact^2
v = result.voltage_candidate
@assert isapprox(v[("demand","a")]-v[("demand","n")], u_exact; atol=1e-6)
@assert isapprox(v[("demand","n")], U_n_exact; atol=1e-6)
@assert isapprox(result.objective, 2000+loss_exact; atol=1e-5)
(phase_neutral_V=u_exact, neutral_ground_V=U_n_exact,
 current_A=I_exact, loss_W=loss_exact)
```

Line currents are available under `(:line_from,"service")` and
`(:line_to,"service")`; they are positive **into** the line at each endpoint.
The grounded source-neutral current uses an explicitly unobserved placeholder.
Do not interpret that placeholder as the return-conductor current: the latter
is the neutral entry in the line current vector.

## 4. Compare full and specialized representations

```@example exactivr
reduced = build_opf(net, IVRNLP(objective=:source_import,
                              specialization=:conductor_difference);
                    optimizer=Ipopt.Optimizer)
r_reduced = solve_ivr_nlp_opf(reduced; solver_options=T.SOLVER_OPTIONS)
T.check_result(reduced, r_reduced)
@assert reduced.numerical_diagnostics[:specialization] == :conductor_difference
@assert ivr_nlp_point_report(reduced, point).passed
@assert ivr_nlp_point_report(full, T.point(r_reduced)).passed
@assert isapprox(result.objective, r_reduced.objective; atol=1e-5, rtol=1e-7)
(full_real_variables=num_variables(full.model),
 reduced_real_variables=num_variables(reduced.model),
 certificate=reduced.numerical_diagnostics[:specialization_report].code)
```

The specialized model retains the neutral voltage and all original operating
limits. Each solved state is tested in the opposite model without optimizing
or fitting it. Run the same comparison for two-, three- and four-wire cases:

```@example exactivr
T.reduction_examples()
nothing # hide
```

The three-/four-wire examples are three-line unbalanced trees built by
`examples/ivr_compiler_cases.jl`. Their total nominal load is 3000 W + 750 var;
the three-wire loads are delta, while the four-wire loads are wye with explicit
neutral returns. Line mutual impedances are retained. These are distinct
physical cases, so their source-import values need not be equal. The meaningful
comparison is full versus reduced **within** each case.

## 5. Reuse the model for a changed demand

Changing demand defines a new operating problem with the same equipment.
Use the update API rather than editing `reduced.network` by hand:

```@example exactivr
update_ivr_loads!(reduced, Dict("house" => (p=[3000.0], q=[0.0])))
r_3000 = solve_ivr_nlp_opf(reduced; solver_options=T.SOLVER_OPTIONS)
T.check_result(reduced, r_3000)
@assert net["load"]["house"]["p_nom"] == [2000.0]
(import_W=r_3000.objective,
 assemblies=reduced.numerical_diagnostics[:assembly_count],
 updates=reduced.numerical_diagnostics[:update_count])
```

P and Q must both be supplied, in watts and vars, with the existing channel
arity. The build owns its snapshot: `net` remains unchanged. The following
experiment uses 1, 2 and 3 kW and compares each reused solution against a fresh
build of an independently edited input copy. It checks variable identity,
objective agreement and both supplied-point directions.

```@example exactivr
T.reuse_example()
nothing # hide
```

The API avoids electrical reassembly; it makes no automatic warm-start or
factorization-reuse promise. Equipment, source phasors and per-unit bases remain
fixed. A failed input-validation batch does not mutate the build, but backend
failures do not have a transactional rollback guarantee.

## 6. Change generator prices and inspect an inverter budget

For generators, the corresponding API accepts partial P/Q-box and price updates:

```julia
update_ivr_generators!(build, Dict("der" => (cost=[0.5],)))
```

`T.dispatch_example()` attaches a 0–600 W single-phase generator, with Q fixed
to zero, to the original service. The source is explicitly priced at
0.2 currency/kWh. The example changes the generator price from 0.1 to
0.5 currency/kWh on the same build and independently reconstructs the objective
from source and generator powers.

```@example exactivr
T.dispatch_example()
nothing # hide
```

With `objective=:cost`, the snapshot objective is a **cost rate**, currency/h;
there is no implicit time step. Price changes do not affect a `:source_import`
objective. Inverters are a different component family: their capability and
price changes currently require a fresh build.

The next example uses a single-phase inverter with 600 W PCC availability,
500 W internal active-power budget, 0.2 + j0.1 Ω series filter and zero filter
shunt. Both terminal current limits are 10 A, its apparent-power limit is
1000 VA, and PCC reactive power is fixed to zero. It checks the copper-loss
identity independently from the reported powers and filter current.

```@example exactivr
T.inverter_example()
nothing # hide
```

PCC injection must be below internal injection because of filter loss. This
example has no controller, external DC grid or battery energy state. `prime_mover`
is descriptive; it does not add an energy balance or an implicit P/Q restriction.
Three-leg PCC ratings and internal delta-coil quantities require the distinct
conventions explained in [the inverter contract](ivr_nlp.md).

## 7. Make a bound fail and observe a legitimate fallback

A useful negative check keeps the original physical state fixed while changing
one limit. Tightening the neutral cap from 30 V to 1 V must reject the state
with 2.660 V neutral displacement. This checks the retained neutral quantity
without relying on solver convergence or diagnosing global infeasibility.

The second experiment introduces a downstream phase-earth shunt of 1 mS.
This changes the physical problem: the two conductor currents no longer need
sum to zero. The requested specialization must fall back to full IVR and retain
the shunt. The full problem is then solved and independently checked.

```@example exactivr
T.refusal_examples()
nothing # hide
```

`:bus_shunt` is a specialization diagnostic, not an unsupported-component
error. Other full-IVR networks may similarly fall back for meshes, multiple
sources, switches or transformers. In contrast, unsupported load laws
or control profiles cause an applicability refusal.
See [the coverage matrix](coverage.md) before importing a new device family.

## 8. Check a fixed regulator and its output rating

Replace the service line with a `single_phase_autotransformer`, using the same
ordered phase/neutral maps at both ends. Its fixed type-B `tap_ratio = 1.04`
means an ideal voltage gain of 1.04. The example includes no leakage or
excitation, so the independently expected output is 239.2 V, current is
`2000/239.2` A, and source import is 2000 W. Both side-current ratings start at
10 A. The exact implementation and assertions are in `T.regulator_example`.

```@example exactivr
regulator = T.regulator_example(); nothing
```

The helper then lowers only the output phase-current rating to 8 A. Both the
built-model evaluator and independent physical auditor reject the unchanged
state. It also verifies full-IVR fallback when specialization is requested.
No tap is optimized. For type A, the native ideal gain is `1/tap_ratio`; see
[fixed regulator conventions](ivr_nlp.md#Fixed-regulators-and-conductive-bonds)
for conductive-bond observations and grounding ambiguity.

## 9. Compare demand laws at the same voltage

A voltage reduction changes the demand itself for current, impedance, ZIP and
exponential models. Compare them at a **fixed 207 V** coil voltage, with nominal
values 2000 W and 300 var at 230 V. This keeps the physical voltage identical
across cases, so the different powers come entirely from the load law.

```@example exactivr
load_laws = T.load_law_example(); nothing
```

The ZIP example uses active fractions `(0.2, 0.3, 0.5)` and reactive fractions
`(0.4, 0.5, 0.1)` in Z/I/P order; exponential powers use exponents 0.4 and 2.7.
The helper checks the tabulated powers and current against independently
calculated factors. These fixed nonzero source coils require no magnitude
auxiliaries or additional voltage bounds. At an unfixed bus, a positive lower
bound on the actual load-coil voltage is required; see the
[domain and data contract](ivr_nlp.md#Voltage-dependent-load-laws).

These cases share nominal demand, but represent **different physical models**.
Their objective values should not be treated as a full/reduced formulation
comparison or evidence of algorithmic improvement. Voltage-law coefficients and
nominal powers require a fresh build when changed; the existing demand-update
API applies only to declared constant-power loads.

## 10. Keep a physical boundary and reduce its pendant region

Add a 2 mS phase-earth shunt at bus `b1` of a three-line four-wire feeder.
The upstream line carries an earth-return contribution, so the whole-network
zero-sum certificate correctly declines. Lines `l2` and `l3`, downstream of
`b1`, still feed only zero-sum connections.

```@example exactivr
region = T.region_example(); nothing
```

The helper requests `specialization=:conductor_regions`, checks the selected
lines and retained boundary, and evaluates each solved point in the opposite
model. It explicitly verifies a nonzero upstream conductor-current sum while
the selected downstream line has zero sum. The model loses four real current
variables, retaining all voltages, original KVL, boundary KCL, shunt physics
and physical limits. `b1` is not fixed or grounded by the transformation.

This example demonstrates a larger applicability domain, not a timing benefit.
Inspect `region.report.regions`, `.retained_lines` and `.barriers` to see the
certificate. Transformers, switches, mesh cores and mixed conductor ports can
similarly remain physical while eligible attached trees are specialized; see
the [regional contract](ivr_nlp.md#Pendant-regions-inside-a-larger-network).

## 11. Substitute an exact impedance current

Change the two-wire load to constant impedance with 2 kW nominal consumption
at 230 V. Its conductance is `2000/230^2` S. With the same 0.5 ohm loop, the
analytical coil voltage is `230/(1 + 0.5*2000/230^2)` V. The helper requests
`linear_elimination=:impedance_loads`, verifies the analytical current, and
checks the solved physical states in both models.

```@example exactivr
impedance = T.impedance_elimination_example(); nothing
```

Two real current variables disappear, but the load-current result remains
available. This is an exact constitutive substitution. It does not apply to
constant-power loads, and nominal impedance changes still require rebuilding.

## 12. Preserve the bound at an eliminated intermediate bus

Split the original service into two equal, unshunted segments with no device at
the intermediate bus. Request `linear_elimination=:passive` together with
`specialization=:conductor_difference`. The compiler eliminates the intermediate
voltage coordinates and independent currents of one incident line, retaining
expressions for every original voltage/current/power observation.

```@example exactivr
series = T.series_elimination_example(); nothing
```

The helper tightens only the intermediate neutral-voltage limit to half its
solved magnitude. Both the compiled model and independent physical auditor
reject the unchanged state. Merely reconstructing that voltage after solving
would be insufficient: its bound must constrain the optimization itself.
Charged pi sections and device/ground boundaries are outside this certificate.

## 13. Resolve a stiff finite ground

Replace the ideal source-neutral ground with a finite susceptance of
``-10^{10}`` S, and use the impedance load from Section 11. The circuit has
the analytical current

```math
I=\frac{230}{0.5+230^2/2000+1/Y_g},\qquad V_n=I/Y_g.
```

Although ``V_n`` is very small, the ground current is finite. Request
`ground_scaling=:voltage` to express this free voltage in a numerically suitable
coordinate. The helper composes it with conductor and impedance elimination,
checks the analytical voltage, and then perturbs it by ``10^{-3}/Y_g`` V.
That perturbation creates a 1 mA KCL error without changing any supplied current.

```@example exactivr
ground = T.finite_ground_example(); nothing
```

The old normalized model check accepts this perturbed state. The scaled model
and the independent SI audit both reject it. This illustrates why solver
termination and small normalized residuals alone cannot certify physical
accuracy. Scaling retains the finite shunt and all original observations;
it does not replace it with ideal grounding or loosen a tolerance.

## 14. Retain a bus when its bounds become less sparse

Consider a four-wire, three-segment service with load only at its last bus.
Both intermediate buses retain phase-neutral and neutral-voltage limits.
Unconditional series elimination removes the first intermediate bus, but its
voltage-bound expressions acquire additional current-coordinate dependencies.
`series_selection=:bound_support` retains that bus. The helper checks both
solved physical points against both representations of this same input.

```@example exactivr
selection = T.series_selection_example(); nothing
```

The final output concerns a **separate input** whose first segment has zero
series impedance. Intermediate voltage then equals its neighbour's voltage,
and the policy can eliminate the bus while retaining its bounds without
increasing their support widths. Its physical state is checked against a full
model of that same zero-impedance input. No performance or equivalence claim
compares the two different circuits.

This is a conservative structural choice, not a guarantee of speed or global
derivative sparsity. The [verification record](verification.md) compares its
accepted/rejected choices with actual derivative counts and paired solve times.

## 15. Extend the experiment without changing its meaning

For a larger study, record the input digest and every deliberate data change;
retain failed solves and explicit fallback reasons; compare accepted objectives
and physical states before timing; and distinguish construction, update and
solve times. Use `examples/benchmark_ivr_compiler.jl` for the synthetic ablation
and `examples/benchmark_ivr_dispatch.jl` for matched dispatch-reuse experiments.
Those studies address performance; this tutorial establishes small-case
correctness and reproducibility. The remaining scope and evidence are recorded
in [the contract reference](ivr_nlp.md) and [verification](verification.md).


For an empirical choice among complete configurations, use the
[profile-comparison procedure](ivr_performance.md). First specify whether the
workload is a fresh model or a repeated-update sequence, then declare the common
objective and candidate options. Use the runner's `fastest_ipopt` ranking; model
construction cost is excluded from this assessment. The older `fastest_solve`
field includes result extraction and is a secondary diagnostic. Rank only
profiles whose warm-up and every
measured trial pass physical and model checks. Freeze the promising choices
and confirm them with fresh runs. Keep unsuccessful and slower profiles in the
study: a different grounding pattern, operating point or bound set can change
the ranking. The measured common profile is an explicit starting configuration,
not an automatic replacement for this tutorial's reference formulation.


## 16. Change solver ordering without changing the circuit

Sparse-solver ordering is a numerical policy separate from conductor or passive
elimination. This example retains the tutorial's electrical input and asks
MUMPS for AMD ordering through Ipopt's `mumps_pivot_order=0` option:

```@example exactivr
ordered = build_opf(T.two_wire_case(),
    IVRNLP(objective=:source_import, specialization=:conductor_difference);
    optimizer=Ipopt.Optimizer)
ordered_result = solve_ivr_nlp_opf(ordered;
    solver_options=merge(T.SOLVER_OPTIONS,
        (linear_solver="mumps", mumps_pivot_order=0)))
@assert ordered_result.solve.optimal
@assert physical_residuals(ordered.network, ordered_result).passed
ordered_point = ACPoint(voltage=ordered_result.voltage_candidate,
                        currents=ordered_result.current_candidate)
@assert ivr_nlp_point_report(ordered, ordered_point).passed
(source_import_W=ordered_result.objective,
 ipopt_wall_seconds=JuMP.solve_time(ordered.model))
```

This checks the result, not a speed claim from one small solve. The
[ordering study](ivr_performance.md) compares repeated admitted solves with
shared tolerances and starts. Its separate verbose diagnostics distinguish the
requested ordering from the one actually selected by the installed solver.
All formulation and solver alternatives remain available for future evidence.


## 17. Carry a previous primal point explicitly

Updating a model does not automatically select its previous solution as the
next start. Save variable values before modifying the model, then set the start
attributes explicitly. This example changes demand while preserving the
coordinate layout and uses normal Ipopt dual initialization:

```@example exactivr
repeated = build_opf(T.two_wire_case(),
    IVRNLP(objective=:source_import, specialization=:conductor_difference);
    optimizer=Ipopt.Optimizer)
reuse_settings = merge(T.SOLVER_OPTIONS,
    (linear_solver="mumps", mumps_pivot_order=0, warm_start_init_point="no"))
initial_result = solve_ivr_nlp_opf(repeated; solver_options=reuse_settings)
T.check_result(repeated, initial_result)
variables_before = JuMP.all_variables(repeated.model)
previous_primal = JuMP.value.(variables_before)
# Independent input for the post-update physical and fresh-model checks.
changed_input = T.two_wire_case()
changed_input["load"]["house"]["p_nom"] = [1800.]
update_ivr_loads!(repeated, Dict("house" => (p=[1800.], q=[0.])))
@assert JuMP.all_variables(repeated.model) == variables_before
JuMP.set_start_value.(variables_before, previous_primal)
next_result = solve_ivr_nlp_opf(repeated; solver_options=reuse_settings)
T.check_result(repeated, next_result)
@assert physical_residuals(changed_input, next_result).passed
fresh_reference = build_opf(changed_input, IVRNLP(objective=:source_import))
@assert ivr_nlp_point_report(fresh_reference, T.point(next_result)).passed
(source_import_W=next_result.objective,
 ipopt_wall_seconds=JuMP.solve_time(repeated.model))
```

This is a correctness example, not a timing comparison. No dual multipliers are
carried, and the model update does not establish native factorization reuse.
For a controlled comparison with fixed starts and freshly built models, use the
[complete-sequence study](ivr_performance.md). A changed active bound or price
can make a previous point less useful; retaining both start policies is essential.


## 18. Transfer the comparison to a feeder file

Use the external-feeder runner from the repository root with a separately
licensed input JSON file and a distinct writable result path:

```sh
julia --project=test examples/benchmark_ivr_feeder_reuse.jl /path/to/feeder.json /tmp/feeder-reuse.json
```

This runs full and regional/passive reused models, each with fixed and
previous-primal starts, through original demand, identical demand, 90% demand
and restoration. Eight sweeps balance the four workflow positions. The input
file is unchanged; only supported constant-power P/Q values vary in the owned
scenario copies. Inspect the companion `.input.json` manifest for the exact load
IDs, source digest and legacy provenance fields. Other load laws remain fixed.

Read `ranking.objective_comparable` and the complete admitted workflow list
before using `fastest_ipopt`. Inspect individual scenario iteration counts and
start digests to explain a sequence-level improvement or regression. A warm-up
or measured failure makes that workflow ineligible; retain its record. The
feasibility objective is deliberate: this example makes no claim about economic
dispatch from a feeder's potentially ambiguous source/generator accounting.
For a matched fresh/reused comparison, use the separate fixed-start candidate
set in the [performance guide](ivr_performance.md).


## 19. Transfer reconstructed duals on the same model

The experimental helper below also caches constraint duals. It validates the
same model and equation layout, then resets bound duals when a generator box
changes. This example changes only constant-power demand. Cache all primal and
dual solution data before the first model update:

```@example exactivr
include(joinpath(pkgdir(FormulationLab), "examples", "ivr_dual_starts.jl"))
const D = IVRDualStarts
dual_build = build_opf(T.two_wire_case(),
    IVRNLP(objective=:source_import, specialization=:conductor_difference);
    optimizer=Ipopt.Optimizer)
dual_controls = merge(T.SOLVER_OPTIONS,
    (linear_solver="mumps", mumps_pivot_order=0,
     fixed_variable_treatment="make_parameter", warm_start_same_structure="no",
     mu_strategy="monotone", mu_init=0.1,
     warm_start_bound_push=0.001, warm_start_bound_frac=0.001,
     warm_start_slack_bound_push=0.001, warm_start_slack_bound_frac=0.001,
     warm_start_mult_bound_push=0.001, warm_start_init_point="no"))
dual_first = solve_ivr_nlp_opf(dual_build; solver_options=dual_controls)
T.check_result(dual_build, dual_first)
dual_variables = JuMP.all_variables(dual_build.model)
primal_cache = JuMP.value.(dual_variables)
dual_cache = D.capture(dual_build)
updated_input = T.two_wire_case()
updated_input["load"]["house"]["p_nom"] = [1800.]
update_ivr_loads!(dual_build, Dict("house" => (p=[1800.], q=[0.])))
JuMP.set_start_value.(dual_variables, primal_cache)
transfer = D.apply!(dual_build, dual_cache)
@assert transfer.matches_policy && transfer.reset_bounds == 0
dual_next = solve_ivr_nlp_opf(dual_build;
    solver_options=merge(dual_controls, (warm_start_init_point="yes",)))
T.check_result(dual_build, dual_next)
@assert physical_residuals(updated_input, dual_next).passed
@assert ivr_nlp_point_report(
    build_opf(updated_input, IVRNLP(objective=:source_import)),
    T.point(dual_next)).passed
(carried_duals=transfer.carried, source_import_W=dual_next.objective)
```

These are reconstructed JuMP duals, not a copy of both native Ipopt bound
multipliers. The helper intentionally refuses a cache from another model or
changed equation functions. It is an experimental same-model policy, not an
automatic feature of `update_ivr_loads!` or `update_ivr_generators!`. The
[controlled study](ivr_performance.md) compares normal initialization, a zero-dual
warm control and reconstructed duals. One small successful example does not
establish a speed benefit, global optimality or factorization reuse.


## 20. Construct distinct P/Q operating histories

Repeated scenarios can make initialization look especially effective. The next
example constructs a path in which both active and reactive demand change at
every step. Generator P/Q boxes also change: Q becomes fixed and is released,
then its lower side is removed and restored. Each demand factor refers to the
original input, so updates do not accidentally compound.

```@example exactivr
include(joinpath(pkgdir(FormulationLab), "examples", "benchmark_ivr_histories.jl"))
const H = IVRHistoryStudy
history_net, changing_history = H.history_case(
    conductors=3, segments=4, history=:changing_boxes)
history_inputs = H.R.scenario_inputs(history_net, changing_history)
@assert all(history_inputs[k] != history_inputs[k-1] for k in 2:6)
@assert history_inputs[3]["generator"]["der"]["q_min"] == zeros(3)
@assert history_inputs[3]["generator"]["der"]["q_max"] == zeros(3)
@assert !haskey(history_inputs[5]["generator"]["der"], "q_min")
@assert history_inputs[6]["generator"]["der"]["q_min"] == [-70., -30., -15.]
[(label=step.label, p_max_W=state["generator"]["der"]["p_max"],
  q_min_var=get(state["generator"]["der"], "q_min", nothing),
  q_max_var=state["generator"]["der"]["q_max"])
 for (step, state) in zip(changing_history, history_inputs)]
```

For `history=:fixed_boxes`, the same demand and price path retains the initial
P/Q boxes. The two histories therefore represent different feasible sets.
Compare initialization policies within a history; do not demand equal objectives
between histories. The new path also differs from the preceding study in Q
capabilities and demand/price changes, so it is not an isolated test of removing
that study's identical repeat.

Run the timed experiment separately from the documentation build and other
Julia jobs:

```julia
report = H.benchmark("delta-history.json";
    conductors=3, segments=100, history=:changing_boxes, repetitions=12)
```

The six default workflows compare full/regional and previous-primal/zero-dual/
reconstructed-dual starts. Twelve sweeps put each workflow in every position twice. The manifest records
whether the requested schedule is position-balanced before solving.
Check `ranking.objective_comparable`, complete eligible sequences, saved order,
per-scenario effective settings and reset records before reading a time ranking.
`generator_dispatch[id]["p_W"]` and `["q_var"]` record physical-unit dispatch
after solving; these are not per-unit solver coordinates. Preserve failures and
unattempted later scenarios. The [performance guide](ivr_performance.md) records
the protocol, measurements and limits of inference.


## 21. Compose eliminations along an unloaded chain

Three unshunted segments connect a source to a terminal load. Both interior
buses retain their original voltage limits, and every segment has current and
apparent-power limits at both ends. The old policy selects only the first bus;
the new policy uses the next surviving line equation to eliminate the second.
This example runs both single-phase and three-wire delta cases, checks physical
states in both directions, and tightens the second interior bus's voltage bound
to demonstrate rejection of the unchanged supplied point.

```@example exactivr
T.chain_elimination_example()
```

Use `linear_elimination=:passive_chains` to request this certificate. Inspect
`selected_series_lines` as well as `series_buses`: consumed equations must be
distinct. The original physical observations remain mandatory when supplying a
point. A smaller coordinate count does not establish a runtime benefit.

For an independently timed comparison with fixed total line impedance and total
demand, run the following separately from documentation/tests:

```julia
include("examples/benchmark_ivr_chains.jl")
using LinearAlgebra
BLAS.set_num_threads(1)
report = IVRChainStudy.benchmark("delta-chain.json";
    conductors=3, segments=48, loads=:terminal, repetitions=12)
```

The six candidates cross full/regional coordinates with no elimination, the
original passive pass and adjacent-chain elimination; all request MUMPS AMD.
The manifest checks equal physical starts. Twelve sweeps balance profile position,
and warm-ups are excluded. `loads=:alternating` is a control with no additional
adjacent opportunity. The primary ranking uses Ipopt wall time only. See the
[performance evidence](ivr_performance.md) before choosing between these options.


## 22. Export physical results in the BMOPFTools layout

The dictionary describes the original network, including eliminated observations.
The extension identifies derived quantities and any unavailable current allocation.

```@example exactivr
export_case = T.two_wire_case()
export_run = T.solve_checked(export_case; specialization=:conductor_difference)
exported = result_dict(export_run.build, export_run.result)
buffer = IOBuffer()
write_result(exported, buffer)
seekstart(buffer)
@assert isequal(read_result(buffer), exported)
(exported["bus"]["demand"]["a"], exported["line"]["service"]["a"],
 exported["losses"], exported["_formulationlab"]["state_kind"])
```

Write a file with `write_result(exported, "result.json")`. Select
`nonfinite=:null` for strict JSON consumers. The default preserves BMOPFTools'
NaN convention for unavailable values. Read the [result contract](results.md)
before comparing estimates from a relaxation with exact-IVR physical outputs.

## 23. Lift an apparent-power limit without relaxing it

The auxiliary P/Q values have exact defining equalities. The physical result
dictionary continues to report products of the original voltage/current state.

```@example exactivr
lift_case = T.two_wire_case()
lift_case["line"]["service"]["s_max"] = [1e4]
lift_build = build_opf(lift_case, IVRNLP(lifting=:powers); optimizer=Ipopt.Optimizer)
lift_result = solve_ivr_nlp_opf(lift_build; solver_options=T.SOLVER_OPTIONS)
@assert lift_result.solve.optimal
@assert physical_residuals(lift_case, lift_result).passed
@assert ivr_nlp_point_report(lift_build, ACPoint(voltage=lift_result.voltage_candidate,
    currents=lift_result.current_candidate)).passed
(lift_build.numerical_diagnostics[:lifted_real_variables],
 result_dict(lift_build, lift_result)["line"]["service"]["loss"])
```

## 24. Eliminate charged sections and retain interior observations

This three-segment two-wire example has unequal endpoint charging. Both interior
bus voltages and all original line endpoint currents remain observable and bounded.

```@example exactivr
pi_case = T.ivr_compiler_case(conductors=2, segments=3)
delete!(pi_case["load"], "d1"); delete!(pi_case["load"], "d2")
pi_case["linecode"]["wire"]["B_from_1_1"] = 1e-4
pi_case["linecode"]["wire"]["B_to_2_2"] = 2e-4
for line in values(pi_case["line"])
    line["s_max"] = [1e4]
end
pi_build = build_opf(pi_case, IVRNLP(linear_elimination=:passive_blocks,
    lifting=:bounded_observations); optimizer=Ipopt.Optimizer)
pi_result = solve_ivr_nlp_opf(pi_build; solver_options=T.SOLVER_OPTIONS)
@assert pi_result.solve.optimal
@assert physical_residuals(pi_case, pi_result).passed
pi_output = result_dict(pi_build, pi_result)
@assert haskey(pi_output["bus"], "b1") && haskey(pi_output["bus"], "b2")
(pi_build.numerical_diagnostics[:linear_elimination_report].block_diagnostics,
 pi_output["line"]["l1"]["a"])
```

Neither demonstration establishes a speedup. Run
`examples/benchmark_ivr_lifting_blocks.jl` separately from tests and documentation
to compare the six declared profiles with matched physical starts and balanced
ordering. The primary score is Ipopt wall time, excluding compilation and export.

## 25. Transfer the structural comparison to an external feeder

The external runner reads one existing BMOPF JSON file and compares six frozen
profiles, with voltage ground scaling and MUMPS AMD held fixed. From the repository
root, supply your own input path and a separate output path:

```sh
julia --project=test examples/benchmark_ivr_feeder_lifting.jl input.json study.json
```

It preserves electrical fields and source/generator accounting. Known legacy
provenance moves into metadata on an owned copy; the source file is unchanged.
The objective is feasibility, so the experiment does not measure economic
dispatch. Every profile receives the same unloaded physical circuit start,
including consistent lifted auxiliaries. A failed encoding preflight is retained
in the report and prevents timing that case; it does not trigger an input edit
or relaxed retry.

`study.json` retains all warm-ups and twelve balanced sweeps, audits, options,
iterations, derivative counts and the Ipopt-wall ranking. The `.input.json`
sidecar stores the owned input; `.manifest.json` stores source hashes, relocated
provenance paths and preflight checks. Inspect `lifted_real_variables`: a lifting
option can be a no-op when its targeted bounds are absent. Retain such profiles
as controls, but do not describe their timing differences as a lifting benefit.
Run performance measurements separately from tests and documentation builds.

## 26. Eliminate winding currents while retaining physical outputs

Replace the tutorial's two-wire line by a fixed 1:1 transformer. The option
removes its from-side coil current, while both winding/terminal currents and all
declared current limits remain available.

```@example exactivr
tx_case = T.two_wire_case()
delete!(tx_case, "line")
tx_case["transformer"] = Dict("single_phase" => Dict("service" => Dict(
    "bus_from"=>"source", "bus_to"=>"demand",
    "terminal_map_from"=>["a","n"], "terminal_map_to"=>["a","n"],
    "v_nom_from"=>230., "v_nom_to"=>230., "r_series_from"=>0.2,
    "r_series_to"=>0.3, "r_neutral_to"=>0.,
    "i_max_from"=>[40.,40.], "i_max_to"=>[40.,40.])))
tx_build = build_opf(tx_case, IVRNLP(device_elimination=:transformer_currents);
    optimizer=Ipopt.Optimizer)
tx_result = solve_ivr_nlp_opf(tx_build; solver_options=T.SOLVER_OPTIONS)
@assert tx_result.solve.optimal
@assert physical_residuals(tx_case, tx_result).passed
@assert ivr_nlp_point_report(tx_build, ACPoint(voltage=tx_result.voltage_candidate,
    currents=tx_result.current_candidate)).passed
@assert tx_build.numerical_diagnostics[:device_elimination_report].eliminated_complex_coordinates == 1
(tx_build.numerical_diagnostics[:device_elimination_report],
 result_dict(tx_build, tx_result)["transformer"]["service"])
```

For matched performance measurements, include
`examples/benchmark_ivr_transformer_currents.jl` and call
`IVRTransformerCurrentStudy.benchmark(network, "study.json")`. The four candidates
cross full/block coordinates with device elimination off/on. They share an
unloaded physical start, ground scaling, AMD ordering and eight balanced sweeps.
Use `objective=:feasibility` when preserving an external feasibility workload.
This tutorial demonstrates recovery, not a speedup.


## 27. Control observation lifting without changing physical results

Use a higher explicit support threshold to retain short affine rows directly.
Enable exact sharing independently, then inspect whether any duplicates actually
occur. Zero shared observations means that option is a structural no-op on this
input, regardless of small timing differences.

```@example exactivr
selective_build = build_opf(pi_case, IVRNLP(linear_elimination=:passive_blocks,
    lifting=:bounded_observations, observation_support_threshold=8,
    observation_sharing=:exact); optimizer=Ipopt.Optimizer)
selective_result = solve_ivr_nlp_opf(selective_build; solver_options=T.SOLVER_OPTIONS)
@assert selective_result.solve.optimal
@assert physical_residuals(pi_case, selective_result).passed
@assert ivr_nlp_point_report(pi_build, ACPoint(
    voltage=selective_result.voltage_candidate,
    currents=selective_result.current_candidate)).passed
selective_output = result_dict(selective_build, selective_result)
@assert keys(selective_output["bus"]) == keys(pi_output["bus"])
(selective_build.numerical_diagnostics[:lifted_real_variables],
 selective_build.numerical_diagnostics[:shared_observation_count])
```

For independent threshold/sharing ablations, include
`examples/benchmark_ivr_observations.jl` and call
`IVRObservationStudy.benchmark(network, "study.json")`. The six profiles contain
full and direct-block controls plus thresholds 2/8 crossed with sharing off/exact.
They use the same unloaded physical start, voltage ground scaling and AMD ordering,
with twelve balanced sweeps and one excluded warm-up per profile. Set
`objective=:feasibility` for external feasibility workloads. All profiles retain
original bounds and physical JSON fields. Run this outside tests and documentation
builds and compare `ipopt_wall_s`; compilation is excluded from the assessment.


## 28. Scale a transformer transition while preserving physical outputs

Change the earlier transformer example to a 2.3 kV/230 V interface. Keep the
physical network identical between the global-base and locally scaled builds.
The local-coordinate option also preserves the original 10 kVA power base.

```@example exactivr
scaled_tx_case = deepcopy(tx_case)
scaled_tx_case["voltage_source"]["grid"]["v_magnitude"] .*= 10
scaled_tx_case["transformer"]["single_phase"]["service"]["v_nom_from"] = 2300.
scaled_tx_case["transformer"]["single_phase"]["service"]["r_series_from"] = 20.
global_tx_build = build_opf(scaled_tx_case, IVRNLP(); optimizer=Ipopt.Optimizer)
local_tx_build = build_opf(scaled_tx_case, IVRNLP(transformer_scaling=:nominal,
    row_scaling=:composed); optimizer=Ipopt.Optimizer)
global_tx_result = solve_ivr_nlp_opf(global_tx_build; solver_options=T.SOLVER_OPTIONS)
local_tx_result = solve_ivr_nlp_opf(local_tx_build; solver_options=T.SOLVER_OPTIONS)
@assert global_tx_result.solve.optimal && local_tx_result.solve.optimal
@assert physical_residuals(scaled_tx_case, local_tx_result).passed
@assert ivr_nlp_point_report(global_tx_build, T.point(local_tx_result)).passed
@assert ivr_nlp_point_report(local_tx_build, T.point(global_tx_result)).passed
@assert local_tx_build.numerical_diagnostics[:transformer_scaling_report].bases["demand"] ≈ 230.
(local_tx_build.numerical_diagnostics[:per_unit_bases],
 local_tx_build.numerical_diagnostics[:transformer_scaling_report],
 result_dict(local_tx_build, local_tx_result)["transformer"]["service"])
```

For the four-arm scaling experiment, include
`examples/benchmark_ivr_transformer_scaling.jl` and call
`IVRTransformerScalingStudy.benchmark(network, "study.json";
    nlp_scaling_method="none")`. Repeat separately with `"gradient-based"`.
Each block crosses nominal coordinates off/on with legacy/composed row norms,
uses full IVR and eight balanced sweeps, and records every effective scale.
This separates model variable scaling, model row scaling and solver scaling.
No callback instrumentation enters the timing ranking. The example above proves
physical agreement on this fixture; it does not establish a performance benefit.

## 29. Check an active limit against an independent transformer-cascade optimum

A manufactured single-phase cascade supplies a resistive feeder through ideal
11 kV/2.3 kV and 2.3 kV/230 V transformers. The feeder has total phase resistance
0.2 Ω, neutral resistance 0.3 Ω, a 2 Ω terminal neutral ground, a 2 kW load and
unity-power-factor generation. The neutral conductor and finite ground form a
parallel return path. Consequently,

```math
R=0.2+(0.3^{-1}+2^{-1})^{-1},\quad
U=230-RI,\quad P_g=2000-UI,\quad P_{\mathrm{grid}}=230I.
```

Here positive ``I`` denotes import. The current-limited case permits 5 A reverse
flow, so its optimum has ``I=-5`` A. The voltage-limited case has ``U=232`` V and
``I=-2/R`` A. The capability-limited case fixes maximum generation at 250 VA
with zero reactive power, giving ``UI=1750`` W. The 180 V lower voltage limit
excludes the other constant-power root. On the admitted branch, increasing
generation decreases source import. These scalar relations give independent
optima without solving a second OPF.

```@example exactivr
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "ivr_transformer_stress_cases.jl"))
C = IVRTransformerStressCases
stress = C.case(limit=:current, segments=12)
witness = C.expected(:current)
stress_build = build_opf(stress, IVRNLP(objective=:source_import,
    transformer_scaling=:nominal, row_scaling=:composed,
    ground_scaling=:voltage); optimizer=Ipopt.Optimizer)
stress_result = solve_ivr_nlp_opf(stress_build; solver_options=T.SOLVER_OPTIONS)
@assert stress_result.solve.optimal && physical_residuals(stress, stress_result).passed
@assert isapprox(stress_result.objective, witness.source_W; atol=1e-4)
@assert isapprox(real(only(stress_result.powers[(:generator,"der")])), witness.generator_W; atol=1e-4)
(witness, result_dict(stress_build, stress_result)["generator"]["der"])
```

The reusable cases and benchmark are in
`examples/ivr_transformer_stress_cases.jl` and
`examples/benchmark_ivr_transformer_stress.jl`. Call
`IVRTransformerStressStudy.benchmark("current.json"; limit=:current,
    nlp_scaling_method="none")` in a separate process with no concurrent work.
The runner applies the independent objective admission rule to warm-ups and
measured trials in addition to the common physical checks. Repeat with
`:capability`, `:voltage` and the explicit `"gradient-based"` solver policy.
These cases isolate active limits; ideal transformers and resistive single-phase
lines do not substitute for an unbalanced feeder study with transformer leakage.

## 30. Compose finite-ground and transformer-local units

The cascade above has a 0.5 S terminal ground and a 10 kVA common power base.
Its global-base admittance multiplier is 6050, whereas the 230 V regional-base
multiplier is 2.645. The additional `ground_scaling=:regional_voltage` option
uses the latter. It preserves the finite ground and all physical limits; the
previous `:voltage` option remains available. With nominal transformer units,
the resulting ground coordinate has a magnitude equal to ground current in local
per-unit current units when the multiplier exceeds one. See the
[derivation](ivr_theory.md) for the full inverse map and its assumptions.

```@example exactivr
regional_ground_build = build_opf(stress, IVRNLP(objective=:source_import,
    transformer_scaling=:nominal, ground_scaling=:regional_voltage,
    row_scaling=:composed); optimizer=Ipopt.Optimizer)
regional_ground_result = solve_ivr_nlp_opf(regional_ground_build; solver_options=T.SOLVER_OPTIONS)
@assert regional_ground_result.solve.optimal
@assert physical_residuals(stress, regional_ground_result).passed
@assert ivr_nlp_point_report(stress_build, T.point(regional_ground_result)).passed
@assert ivr_nlp_point_report(regional_ground_build, T.point(stress_result)).passed
@assert isapprox(regional_ground_result.objective, witness.source_W; atol=1e-4)
global_ground = only(stress_build.numerical_diagnostics[:ground_scaling_report].scaled_terminals)
regional_ground = only(regional_ground_build.numerical_diagnostics[:ground_scaling_report].scaled_terminals)
@assert isapprox(global_ground.scale, 6050.)
@assert isapprox(regional_ground.scale, 2.645)
(global_ground_multiplier=global_ground.scale, regional_ground_multiplier=regional_ground.scale,
 recovered_neutral_voltage=regional_ground_result.voltage_candidate[("b12","n")])
```

For a controlled timing experiment, include
`examples/benchmark_ivr_regional_ground.jl` and call
`IVRRegionalGroundStudy.benchmark("regional.json"; limit=:current,
    nlp_scaling_method="none")`. It crosses transformer coordinates off/nominal
with ground scaling off/voltage/regional_voltage in twelve balanced sweeps.
Every arm uses composed circuit-row norms. Repeat the other active-limit cases
and the explicit gradient-based Ipopt policy in separate blocks. Run diagnostic
instrumentation, tests and documentation outside the timing process. The smaller
multiplier is a units choice; assess its value using physical admission and
Ipopt wall time, not its magnitude alone.

## 31. Test power bases where MV aggregates LV branches

Power bases are numerical units, not equipment ratings. A shared MV supply may
carry several branches' power while each LV branch carries only its own load.
The manufactured panel below has four independent 2 kW LV branches behind one
ideal MV supply. Its analytical source-import optimum is the sum of the branch
optima; the builder refuses branch counts that would invalidate the assumed
slack upstream current rating.

Compare common assembly bases separately from explicitly regional current bases.
Hold `objective_scale` fixed so the electrical-base change does not also change
the numerical objective divisor. The regional current option keeps dispatch,
lifted observations/powers and ground multipliers on their assembly conventions;
it is deliberately not a complete rebase of all NLP variables.

```@example exactivr
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "benchmark_ivr_power_bases.jl"))
PB = IVRPowerBaseStudy
bank = PB.case(limit=:current, branches=4, segments=4)
bank_expected = 4C.expected(:current).source_W
power_base_rows = map(PB.profiles(bank)[[1,2,5]]) do profile
    b = build_opf(bank, IVRNLP(profile.options); optimizer=Ipopt.Optimizer)
    r = solve_ivr_nlp_opf(b; solver_options=merge(T.SOLVER_OPTIONS,
        (nlp_scaling_method="none", bound_relax_factor=0.)))
    @assert r.solve.optimal && physical_residuals(bank, r).passed
    @assert isapprox(r.objective, bank_expected; atol=1e-4)
    @assert isapprox(objective_value(b.model)*1e4, r.objective)
    @assert isapprox(ivr_nlp_point_report(b, T.point(r)).objective, r.objective)
    (profile=profile.name, source_W=r.objective, assembly_VA=b.electrical.sb,
     objective_divisor=b.numerical_diagnostics[:objective_scale],
     current_unit_power_VA=b.numerical_diagnostics[:transformer_scaling_report].power_bases)
end
power_base_rows
```

`current_power_bases` accepts bus-to-VA seeds. The example runner declares
1 MVA at `hv`, 100 kVA at `mv`, and either 1 or 10 kVA at each `lvN_b0` bus.
Seeds propagate along lines and closed switches, stopping at transformers.
Conflicting seeds in one region are refused. These are declared experimental
choices, not capacity estimates inferred automatically from voltage levels.

Call `PB.benchmark("power_bases.json"; limit=:current)` in an otherwise idle
process to run all six arms: common 1/10/100 kVA and 1 MVA bases plus the two
regional-current choices. The numerical objective divisor remains 10,000 in
every arm. Repeat the capability and voltage limits and explicit gradient-based
Ipopt policy. Keep instrumented diagnostics separate, retain rejected trials,
and compare physical optima and Ipopt wall time before choosing a profile.

## 32. Transfer a scaling policy across unbalanced transformer leakage

The analytical panel does not include shared leakage, phase coupling or unequal
reactive demand. The next manufactured circuit introduces these effects: a shared
three-phase MV supply feeds two delta–wye transformers, mutually coupled four-wire
LV lines, unequal constant-P/Q phase loads and finite neutral grounds. Every
transformer has nonzero series resistance and reactance. The two branches draw
12.6 kW and 3.36 kvar before generation. This example uses two line sections for
speed; the timing study uses twelve.

Keep the six power-base policies fixed when transferring them. In particular,
hold the objective divisor at 10,000 and encode the same physical start. Compare
physical solutions across formulations, including the receiving neutral and
transformer currents. The following two successful local solutions establish
agreement at their endpoints; neither constitutes a global-optimum certificate.

```@example exactivr
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "benchmark_ivr_unbalanced_power_bases.jl"))
UP = IVRUnbalancedPowerBaseStudy
unbalanced = UP.case(limit=:current, segments=2)
unbalanced_start = UP.G.H.S.L.start_point(unbalanced)
unbalanced_runs = map(UP.G.profiles(unbalanced)[[1,2]]) do profile
    b = build_opf(unbalanced, IVRNLP(profile.options); optimizer=Ipopt.Optimizer)
    encoded = ivr_nlp_point_report(b, unbalanced_start)
    @assert isempty(encoded.missing_channels)
    @assert length(encoded.variable_values)==num_variables(b.model)
    for (v,x) in encoded.variable_values; set_start_value(v,x); end
    r = solve_ivr_nlp_opf(b; solver_options=merge(UP.P.STRICT,profile.solver_options))
    @assert r.solve.optimal && physical_residuals(unbalanced,r).passed
    @assert abs(abs(r.current_candidate[(:line_from,"lv1_l2")][1])-5.)<1e-5
    (build=b,result=r)
end
u1,u2 = unbalanced_runs
@assert isapprox(u1.result.objective,u2.result.objective;atol=1e-4,rtol=0.)
@assert ivr_nlp_point_report(u1.build,T.point(u2.result)).passed
@assert ivr_nlp_point_report(u2.build,T.point(u1.result)).passed
unbalanced_json = result_dict(u2.build,u2.result)
@assert isapprox(unbalanced_json["bus"]["lv1_b2"]["a"]["vr"],
    real(u2.result.voltage_candidate[("lv1_b2","a")]))
(source_import_W=u2.result.objective,
 neutral_voltage_V=u2.result.voltage_candidate[("lv1_b2","n")],
 receiving_current_A=u2.result.current_candidate[(:transformer_to,"delta_wye/downstream1")])
```

Call `UP.benchmark("unbalanced.json"; limit=:current)` in an otherwise idle
process, then repeat the capability and voltage cases and the gradient-based
solver policy. Each call runs six excluded warm-ups and twelve balanced sweeps.
The JSON records all failures and admission checks. Repeat the full panel in a
fresh process before choosing a candidate from the [timing evidence](ivr_performance.md).
An unchanged physical objective and smaller derivative spread do not by themselves
establish a faster formulation.

## 33. Compare economic and P/Q tracking objectives

The earlier timing panels minimize signed source active power. To study economic
dispatch or power setpoints, specify the physical objective explicitly. The
[power-objective contract](ivr_objectives.md) defines affine/quadratic terms in
individual or aggregated W/var channels. Generator terms use dispatch variables;
other ports can use exact power lifting. Retain the same terms and objective
divisor while changing electrical bases or reductions.

This example compares full 10 kVA with reduced 1 kVA and lifted powers under
quadratic economic dispatch, then aggregate source P/Q tracking. The latter also
includes weaker individual dispatch penalties, so an aggregate target need not
be attained exactly. Neither case has an independent global-optimum certificate.

```@example exactivr
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "benchmark_ivr_power_objectives.jl"))
PO = IVRPowerObjectiveStudy
objective_rows = map((:quadratic_cost,:exchange_tracking)) do workload
    n = PO.case(workload;segments=2)
    start = PO.U.G.H.S.L.start_point(n)
    results = map(PO.profiles(n,workload)[[1,5]]) do profile
        b = build_opf(n,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
        enc = ivr_nlp_point_report(b,start)
        @assert length(enc.variable_values)==num_variables(b.model)
        for (v,x) in enc.variable_values;set_start_value(v,x);end
        r = solve_ivr_nlp_opf(b;solver_options=merge(PO.P.STRICT,profile.solver_options))
        @assert r.solve.optimal && physical_residuals(n,r).passed
        physical_value = PO.physical_objective(n,workload,r.powers)
        @assert isapprox(r.objective,physical_value;atol=1e-7)
        exported = result_dict(b,r)
        @assert exported["_formulationlab"]["objective_units"]=="user_defined"
        @assert length(exported["_formulationlab"]["objective_definition"])==length(profile.options.power_terms)
        (build=b,result=r)
    end
    a,b = results
    @assert isapprox(a.result.objective,b.result.objective;atol=1e-6)
    @assert ivr_nlp_point_report(a.build,T.point(b.result)).passed
    @assert ivr_nlp_point_report(b.build,T.point(a.result)).passed
    (workload=workload,objective=b.result.objective,
     source_power_VA=sum(b.result.powers[(:voltage_source,"grid")]))
end
objective_rows
```

The runner also supplies linear cost, individual P/Q tracking, curtailment and
active-loss objectives. Call `PO.benchmark("quadratic_cost.json";
workload=:quadratic_cost)` in an otherwise idle process. Every candidate must
share the complete physical objective definition. The benchmark separately
recomputes custom objective values from recovered SI powers, records all failures,
and ranks only admitted, comparable solutions by Ipopt wall time. A loss-only
workload has an explicitly different generation-availability bound; compare
formulations within that workload rather than pooling different objectives.

## 34. Change one formulation option at a time

A winning bundle does not identify which option produced its benefit. The
factorial runner crosses regional current units, passive-block elimination,
transformer-current elimination and three lifting policies, giving 24 candidates.
It holds the assembly base, objective divisor, conductor specialization, exact
observation-sharing policy and all electrical data fixed.

Here we select two quadratic-cost candidates that differ only in `lifting`.
They share regional current units and both elimination options. The example
checks the complete option records before solving and requires physical objective
agreement and bidirectional physical-point representability. Its two-section
case is a correctness example, not performance evidence.

```@example exactivr
using JSON3
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "benchmark_ivr_objective_factors.jl"))
OF = IVRObjectiveFactorStudy
factor_net = OF.S.case(:quadratic_cost;segments=2)
factor_profiles = filter(OF.profiles(factor_net,:quadratic_cost)) do p
    f = p.factors
    f.regional_current && f.passive_blocks && f.transformer_currents &&
        f.lifting in (:off,:bounded_observations)
end
@assert length(factor_profiles)==2
changed_fields = [key for key in fieldnames(IVRNLPOptions)
    if JSON3.write(getfield(factor_profiles[1].options,key)) !=
       JSON3.write(getfield(factor_profiles[2].options,key))]
@assert changed_fields==[:lifting]
factor_reference = build_opf(factor_net,IVRNLP(objective=:power,
    power_terms=OF.S.terms(factor_net,:quadratic_cost)))
factor_start = OF.S.U.G.H.S.L.start_point(factor_net)
factor_anchor = Ref{Any}(nothing)
factor_rows = map(factor_profiles) do profile
    row,point = OF.S.P.trial(factor_net,profile,factor_reference,factor_anchor[];
        initial_point=factor_start)
    @assert row["accepted"]
    factor_anchor[]===nothing && (factor_anchor[]=point)
    (profile=profile.name,objective=row["objective"],variables=row["variables"])
end
@assert isapprox(factor_rows[1].objective,factor_rows[2].objective;atol=1e-6)
factor_rows
```

Call `OF.benchmark("factors.json"; workload=:quadratic_cost)` in an otherwise
idle process for the 24-candidate study. Repeat for `:exchange_tracking` and
`nlp_scaling_method="gradient-based"`, then confirm in a fresh process. Four
seeded random permutations are each followed by their reverse. This gives equal
mean position in every two-sweep block; it does not occupy every possible position
with every candidate. The realized orders are saved. Assess matched contrasts
with all other factors fixed and retain their variation across contexts. A
small aggregate average does not exclude a large benefit or regression in a
particular combination. See the [objective evidence](ivr_objectives.md).

## 35. Declare an external dispatch experiment

An external feeder is useful for economic testing only when it contains actual
bounded dispatch decisions. `IVRExternalObjectiveStudy` refuses an empty or fixed
active-generator panel, missing finite P/Q boxes, and IBRs requiring a separate
objective design. It retains the network's electrical data and uses explicit
experimental objective coefficients. Legacy prices are not added implicitly.
The battery label, if present, denotes static dispatch here; it does not provide
an energy or time-coupling model.

The executable example uses a manufactured input so the documentation does not
depend on private data. It selects full 10 kVA and reduced 1 kVA formulations,
while keeping the same physical exchange target and objective divisor.

```@example exactivr
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "benchmark_ivr_external_objectives.jl"))
EO = IVRExternalObjectiveStudy
external_demo = EO.S.case(:quadratic_cost;segments=2)
external_bases = Dict("hv"=>1e5,"mv"=>1e4,"lv1_b0"=>1e3,"lv2_b0"=>1e3)
external_profiles = EO.profiles(external_demo,:exchange_tracking;
    regional_bases=external_bases,exchange_target_W=4500.)[[1,5]]
@assert external_profiles[1].options.s_base==1e4
@assert external_profiles[2].options.s_base==1e3
@assert all(p.options.objective_scale==1. for p in external_profiles)
@assert JSON3.write(external_profiles[1].options.power_terms)==
        JSON3.write(external_profiles[2].options.power_terms)
external_reference = build_opf(external_demo,IVRNLP(objective=:power,
    power_terms=first(external_profiles).options.power_terms))
external_start = EO.S.U.G.H.S.L.start_point(external_demo)
external_anchor = Ref{Any}(nothing)
external_rows = map(external_profiles) do profile
    row,point = EO.P.trial(external_demo,profile,external_reference,external_anchor[];
        initial_point=external_start)
    @assert row["accepted"]
    external_anchor[]===nothing && (external_anchor[]=point)
    (name=profile.name,objective=row["objective"])
end
@assert isapprox(external_rows[1].objective,external_rows[2].objective;atol=1e-6)
external_rows
```

For a local external file, inspect its generators, supply accounting and physical
limits first. Then supply explicit bus seeds and exchange targets, for example:

```julia
EO.S.P.BLAS.set_num_threads(1)
report = EO.benchmark("/path/to/feeder.json", "/path/to/study.json";
    workload=:exchange_tracking, exchange_target_W=10000.,
    regional_bases=Dict("source_bus"=>1e5,"lv_bus"=>1e3),
    nlp_scaling_method="none", repetitions=12)
```

Replace the illustrative bus names with actual buses separated by transformers;
conflicting region assignments are refused by the builder. The runner writes the
owned input and provenance manifest beside the report. It refuses to overwrite
the source, preserves its hash, records original prices/accounting, and saves the
custom objective definition. Twelve sweeps place each of six candidates twice in
each position. Repeat in a fresh process, separately under `gradient-based`
scaling; never overlap timing with tests, diagnostics or a documentation build.
A profile is eligible only after physical/objective and cross-formulation checks.
The [external objective evidence](ivr_objectives.md) also records target errors:
a soft target need not be achievable within the original equipment limits.

## 36. Add a declared DER scenario without changing the source

A feeder with only fixed loads cannot establish controllable economic-dispatch
performance. `IVRDERScenario.augment` creates an explicitly different physical
scenario by adding bounded static generation at positive constant-power loads.
It preserves the native single-phase, wye or delta connection, all original
fields, and a record of every addition. Existing generator/IBR panels are refused
so their dispatch assumptions cannot be mixed silently with the new scenario.

For each native load channel, the defaults are
\(0\le P_g\le1.5P_d\), \(|Q_g|\le0.5P_g^{\max}\),
\(P_g^2+Q_g^2\le(P_g^{\max})^2\). Zero-load sites are skipped; zero-demand
channels in a multi-channel device stay fixed at zero. These are illustrative
DER capabilities, not inferred equipment ratings or an equivalence transform.

```@example exactivr
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "ivr_der_scenario.jl"))
DER = IVRDERScenario
load_only_demo = EO.P.ivr_compiler_case(conductors=2,segments=2)
load_only_before = deepcopy(load_only_demo)
der_demo, der_manifest = DER.augment(load_only_demo)
@assert load_only_demo==load_only_before
@assert all(der_demo[k]==v for (k,v) in load_only_demo)
@assert length(der_manifest.changes)==2
@assert der_manifest.total_active_capacity_W==1.5der_manifest.total_load_W
for addition in der_manifest.changes
    @assert der_demo["generator"][addition.generator_id]==addition.after
    @assert addition.before===nothing
end
der_profiles = EO.profiles(der_demo,:quadratic_cost;
    regional_bases=Dict("b0"=>1e3))[[1,4]]
der_reference = build_opf(der_demo,IVRNLP(objective=:power,
    power_terms=first(der_profiles).options.power_terms))
der_start = EO.S.U.G.H.S.L.start_point(der_demo)
der_anchor = Ref{Any}(nothing)
der_rows = map(der_profiles) do profile
    row,point = EO.P.trial(der_demo,profile,der_reference,der_anchor[];
        initial_point=der_start)
    @assert row["accepted"]
    der_anchor[]===nothing && (der_anchor[]=point)
    (profile=profile.name,objective=row["objective"])
end
@assert isapprox(der_rows[1].objective,der_rows[2].objective;atol=1e-6)
der_rows
```

`DER.write_scenario(source_path, new_path)` writes the derived input and a
`.manifest.json` sidecar containing the raw source hash, scenario hash, load
associations and added device declarations. It refuses to overwrite the source.
Pass the new file to `EO.benchmark` as in section 35 and retain both provenance
layers: the original feeder and the derived dispatch case. Keep its manifest
with the timing report. A benchmark that preserves the derived file is still an
experiment on modified physics relative to the original feeder.

The [265-bus transfer evidence](ivr_objectives.md) uses all original ratings and
adds no bus-voltage limits where none were supplied. It therefore tests a specific
DER capability regime; further voltage-constrained operating cases need separately
declared scenarios. Source-target tracking remains a soft objective, not an exact
exchange constraint.

## 37. Compare bases without confounding power lifting

The preceding cost winner changed both the formulation and its power base.
`IVRBaseFormulationStudy` crosses three bases (1, 10, 100 kVA), full/reduced
representations and power lifting off/on. Its reduction switch controls the
existing conductor-region/passive-block/transformer-current bundle; it does not
separate those three reductions. Other options and physical objective terms are
fixed. Every candidate has exact observation sharing, which is distinct from
introducing bounded-observation lifts.

Here two full models differ only in assembly base. The executable example uses
the existing manufactured network, not external performance data.

```@example exactivr
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "benchmark_ivr_base_formulations.jl"))
BF = IVRBaseFormulationStudy
base_demo = EO.S.case(:quadratic_cost;segments=2)
base_controls = filter(BF.profiles(base_demo,:quadratic_cost)) do p
    !p.factors.reduced && p.factors.lifting==:off && p.factors.s_base in (1e3,1e4)
end
@assert length(base_controls)==2
base_changes = [key for key in fieldnames(IVRNLPOptions)
    if JSON3.write(getfield(base_controls[1].options,key)) !=
       JSON3.write(getfield(base_controls[2].options,key))]
@assert base_changes==[:s_base]
base_reference = build_opf(base_demo,IVRNLP(objective=:power,
    power_terms=first(base_controls).options.power_terms))
base_start = EO.S.U.G.H.S.L.start_point(base_demo)
base_anchor = Ref{Any}(nothing)
base_rows = map(base_controls) do profile
    row,point = BF.P.trial(base_demo,profile,base_reference,base_anchor[];
        initial_point=base_start)
    @assert row["accepted"]
    base_anchor[]===nothing && (base_anchor[]=point)
    (profile=profile.name,objective=row["objective"])
end
@assert isapprox(base_rows[1].objective,base_rows[2].objective;atol=1e-6)
base_orders = BF.orders(12)
@assert all(count(o->o[position]==candidate,base_orders)==1
    for position in 1:12 for candidate in 1:12)
base_rows
```

Use `BF.benchmark(input_path, output_path; workload=:quadratic_cost)` for the
external panel, or provide an explicit `exchange_target_W` with
`workload=:exchange_tracking`. Repeat under `nlp_scaling_method="gradient-based"`
and in a fresh process. Preserve any derived-input addition manifest beside the
report. The default cyclic block measures twelve sweeps, excluding twelve
warm-ups; every profile occupies each position once. Candidate labels and sweep
order are randomized with a saved seed and realized orders. This does not balance
all predecessor pairs or turn repeated solves into independent feeder samples.

Analyze base changes at fixed representation/lifting, reduction at fixed
base/lifting, and lifting at fixed base/reduction. Keep the physical objective
divisor independent of the base. [Matched-base evidence](ivr_objectives.md)
reports all contexts and retains the counterexamples; construction time does not
enter the Ipopt ranking.


## 38. Change dispatch units without changing the circuit base

The assembly base also scales circuit currents, so a common-base experiment does
not isolate dispatch scaling. Give each generator explicit units while keeping
the assembly base and objective divisor fixed. The following uses the same
manufactured economic case as section 37 and a shared physical start.

```@example exactivr
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "benchmark_ivr_generator_units.jl"))
GU = IVRGeneratorUnitStudy
generator_demo = EO.S.case(:quadratic_cost;segments=2)
generator_profiles = filter(p->!p.factors.reduced,
    GU.profiles(generator_demo,:quadratic_cost))
generator_reference = build_opf(generator_demo,IVRNLP(objective=:power,
    power_terms=first(generator_profiles).options.power_terms))
generator_anchor = Ref{Any}(nothing)
generator_rows = map(generator_profiles) do profile
    @assert profile.options.s_base==1e4 && profile.options.objective_scale==1.
    row,point = GU.P.trial(generator_demo,profile,generator_reference,generator_anchor[];
        initial_point=EO.S.U.G.H.S.L.start_point(generator_demo))
    @assert row["accepted"]
    generator_anchor[]===nothing && (generator_anchor[]=point)
    (profile=profile.name,objective=row["objective"])
end
@assert maximum(r.objective for r in generator_rows)-minimum(r.objective for r in generator_rows)<1e-6
generator_rows
```

For one device, use `IVRNLP(generator_power_bases=Dict("generator_id"=>1e3))`.
Other generators retain the assembly base. Both P and Q on all native channels
use the declared units. Bounds and updates remain W/var; prices and targets retain
their physical interpretation. SI result exports keep the same quantity fields.
This option does not rebase IBR ports or lifted-power auxiliaries.

`GU.benchmark(input_path, output_path; workload=:quadratic_cost)` compares six
profiles: three dispatch bases crossed with full/reduced models. Its default two
cyclic blocks measure twelve sweeps after six excluded warm-ups. For tracking,
set `workload=:exchange_tracking` and an explicit `exchange_target_W`. Repeat
with `nlp_scaling_method="gradient-based"` and in a fresh process. Keep all tails
and failures. The [evidence](ivr_objectives.md) concerns one declared scenario;
this executable example establishes consistency, not a speed recommendation.


## 39. Separate power-lift units, generator reuse and condensation

Power lifting adds exact P/Q definitions. Its variable units can change without
changing circuit currents or generator dispatch units. Reusing an existing
generator definition is another intervention. Compare each against the same
power-lifted control before combining choices.

```@example exactivr
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "benchmark_ivr_power_finalists.jl"))
PF = IVRPowerFinalistStudy
finalist_demo = EO.S.case(:quadratic_cost;segments=2)
finalist_profiles = filter(p->p.name in ("reduced_lifts_1k","reduced_lifts_10k",
    "reduced_lifts_100k","reduced_reuse"), PF.profiles(finalist_demo,:quadratic_cost))
finalist_reference = build_opf(finalist_demo,IVRNLP(objective=:power,
    power_terms=first(finalist_profiles).options.power_terms))
finalist_anchor = Ref{Any}(nothing)
finalist_rows = map(finalist_profiles) do profile
    row,point = PF.P.trial(finalist_demo,profile,finalist_reference,finalist_anchor[];
        initial_point=EO.S.U.G.H.S.L.start_point(finalist_demo))
    @assert row["accepted"]
    finalist_anchor[]===nothing && (finalist_anchor[]=point)
    (profile=profile.name,variables=row["variables"],objective=row["objective"])
end
@assert maximum(r.objective for r in finalist_rows)-minimum(r.objective for r in finalist_rows)<1e-6
@assert last(finalist_rows).variables < finalist_rows[2].variables
finalist_rows
```

Use `IVRNLP(lifting=:powers, lifted_power_base=1e3)` to alter power-lift units.
Add `power_sharing=:generators` to reuse exactly matching native generator P/Q
pairs. Bounds, targets, price/bound updates and JSON powers remain physical.
These settings do not change voltage/current observation-lift units.

`PF.benchmark(input_path, output_path; workload=:quadratic_cost)` compares ten
explicit profiles in ten balanced sweeps after ten excluded warm-ups. It includes
full and reduced prior finalists, the three isolated lift bases, a matched reuse
arm, and nonadjacent passive elimination as a less aggressive alternative to
block condensation. For exchange tracking, supply its explicit W target. Repeat
both solver-scaling policies and confirm in a fresh process. This example proves
representation agreement; use the [recorded study](ivr_objectives.md) for timings.
New voltage bounds or DER additions define a new physical scenario and need their
own manifest; they must not be presented as equivalent preprocessing.


## 40. Test combined choices with matched controls

The smaller-lift and generator-reuse choices from section 39 affect overlapping
power definitions. Compare their combinations explicitly before using both.
The interaction runner also crosses dispatch units and retains full/unlifted
controls. This example verifies physical agreement on a small circuit; it does
not estimate feeder runtime benefits.

```@example exactivr
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "benchmark_ivr_power_interactions.jl"))
PI = IVRPowerInteractionStudy
interaction_profiles = filter(p -> p.factors.reduced && p.options.lifting==:powers &&
    p.factors.generator_base==1e4, PI.profiles(finalist_demo,:quadratic_cost))
@assert length(interaction_profiles)==4
interaction_rows = map(interaction_profiles) do profile
    row,_ = PI.P.trial(finalist_demo,profile,finalist_reference,finalist_anchor[];
        initial_point=EO.S.U.G.H.S.L.start_point(finalist_demo))
    @assert row["accepted"]
    (profile=profile.name,objective=row["objective"],variables=row["variables"])
end
@assert maximum(r.objective for r in interaction_rows)-minimum(r.objective for r in interaction_rows)<1e-6
interaction_rows
```

Run `PI.benchmark(input_path, output_path; workload=:quadratic_cost)` for the
complete ten-profile panel. For tracking, set `workload=:exchange_tracking` and
an explicit `exchange_target_W`; run both solver-scaling policies separately.
The [interaction study](ivr_power_interactions.md) defines the conditional
contrasts, admission rules and limits of the evidence. The result schema and
physical SI quantities remain the same for every profile.


## 41. Retain boundaries with a bounded hybrid policy

A long unloaded run can be condensed exactly, yet its reconstructed bound
expressions may be costly. The hybrid mode retains additional boundaries by
limiting connected groups of eliminated original buses. This cap does not bound
expression support or guarantee faster solves. This example compares a charged
single-phase chain with unrestricted blocks while retaining every original limit.

```@example exactivr
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "benchmark_ivr_hybrid.jl"))
HY = IVRHybridStudy
hybrid_demo = HY.case(conductors=2,segments=8,charged=true)
hybrid_profiles = filter(p -> p.name in ("full","blocks","hybrid_1","hybrid_2"),
    HY.profiles(hybrid_demo,:quadratic_cost))
hybrid_reference = build_opf(hybrid_demo,IVRNLP(objective=:power,
    power_terms=first(hybrid_profiles).options.power_terms))
hybrid_anchor = Ref{Any}(nothing)
hybrid_rows = map(hybrid_profiles) do profile
    row,p = HY.P.trial(hybrid_demo,profile,hybrid_reference,hybrid_anchor[];
        initial_point=HY.E.S.U.G.H.S.L.start_point(hybrid_demo))
    @assert row["accepted"]
    hybrid_anchor[]===nothing && (hybrid_anchor[]=p)
    rep=row["elimination"]
    if profile.options.linear_elimination==:passive_hybrid
        @assert rep.max_component_buses<=profile.options.passive_component_limit
    end
    (profile=profile.name,variables=row["variables"],eliminated=rep.series_buses,
        components=rep.eliminated_components)
end
hybrid_rows
```

Use `IVRNLP(linear_elimination=:passive_hybrid, passive_component_limit=2)` to
select the policy directly. Inspect `numerical_diagnostics[:linear_elimination_report]`
for accepted groups and retained candidates. Add `series_selection=:bound_support`
to decline expansions of original bound support as well. The two selection tests
are independent of algebraic correctness and both can reduce condensation.
`HY.benchmark(input_path, output_path; workload=:quadratic_cost)` compares full,
unrestricted blocks, nonadjacent elimination and caps 1/2/4/8. For tracking supply
an explicit `exchange_target_W`. The [scientific study](ivr_hybrid.md) reports
which comparisons were actually timed and which transfers remain untested.
