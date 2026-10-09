# Selecting an exact-IVR formulation

This page gives a decision procedure for a new workload. The
[performance guide](ivr_performance.md) retains detailed numerical evidence;
the [scope contract](ivr_nlp.md) and [equivalence arguments](ivr_theory.md)
determine whether a representation is applicable. There is no universal fastest
profile, and package defaults are not a declaration of an empirically optimal
configuration.

The [validation evidence map](ivr_validation.md) connects these claims to
repository tests, independent checks and reproducible commands.
The [retained-evidence recheck](ivr_evidence_recheck.md) reproduces the four
historical campaigns supporting the main conditional recommendations, without
running new timing experiments.

## Establish the physical reference

Use full `IVRNLP` as the general reference for the declared static AC scope.
Keep the objective, equipment ratings, terminal conventions and input data fixed
before comparing numerical representations. Explicitly request
`transformer_nameplate=:bmopftools` when those nameplate limits belong to the
problem: its default `:ignore` is not a safe substitute for that modelling
decision. Similarly, an inferred equipment cap changes the physical problem and
must not be introduced as a scaling experiment.

For explicit power objectives, use `objective=:power` with declared
`IVRPowerTerm` channels, coefficients and units. This replaces legacy cost;
it does not add missing prices automatically. Keep the distinction between
signed source import, energy cost, loss minimization and exchange tracking.
See [power objectives](ivr_objectives.md).

Full IVR is a correctness reference, not a global optimization certificate.
Unknown electrical fields and unsupported controls require an explicit refusal.
Optimized taps, external DC and dynamic/time-series controls are outside this
static contract. An inapplicable reduction should retain supported physics via
its documented fallback, not remove a component or its bound.

## General starting formulation for power objectives

Use **full IVR with powers-only lifting and retained transformer currents** as
the general numerical control. Set `lifting=:powers`, leave `specialization`,
`linear_elimination` and `device_elimination` at `:off`, and declare the physical
power objective and nameplate policy explicitly. This retains the general
electrical state while introducing exact power definitions for selected
nonlinear observations. Keep the unlifted full model available for independent
representation comparisons.

The `full_powers` arm in `examples/benchmark_ivr_mixed_devices.jl` supplies a
reproducible version with nominal transformer coordinates, composed circuit rows
and explicit power units. Its core tests cover cost and tracking on two-, three-
and four-conductor mixed-device circuits under both tested NLP scaling policies.
The [three-phase transfer study](ivr_threephase_transfer.md) also retains a
full-power control when some reduced voltage-dependent-load profiles fail strict
acceptance. These support a general starting control, not convergence on every
feasible input or a universal fastest formulation.

Choose finite positive bases appropriate to the declared circuit and record
them. Transformer-local voltage units can be useful across MV/LV transitions;
regional current, dispatch and auxiliary power bases are separate choices.
Keep the physical objective divisor fixed when comparing bases. The subsequent
candidate table identifies exact reductions and alternative observations to
compare with this control; promote them only after physical and objective
admission and workload-specific timing evidence.

## Build a small candidate set from physical structure

| Observed structure or workload | Candidate to compare with the reference | Required qualification |
|:---|:---|:---|
| Eligible two-/three-/four-wire leaf regions | `specialization=:conductor_regions` | Use the zero-sum connection certificate; retain earth paths and device boundaries. Delta circulation is not silently deleted. |
| Impedance loads and passive interiors | `linear_elimination=:passive_blocks` with a bounded component size | Retain physical observation maps and all bounds; compare the resulting expression support, not only variable count. |
| Exactly zero nominal P and Q on load coils | `zero_load_elimination=true` | A nonzero voltage on the same coil must be certified. Rebuild before changing an eliminated coil to nonzero demand. |
| MV/LV transformer transitions and finite grounding | Nominal transformer coordinates, voltage-ground scaling, composed rows and explicit regional current bases | Positive coordinate changes preserve the physical problem; inspect actual NLP scaling and initialization. Smaller bases are not universally faster. |
| Power-based cost or tracking | Powers-only lifting and explicit power-unit controls | Match physical coefficients and objectives. Separate assembly, dispatch and auxiliary-power units. |
| Many bounded affine coil observations | Broad or selective bounded-observation lifting | Include a powers-only control. Benefits depend on the network, objective and other reductions. |
| Ordinary or multiwinding transformer currents | Applicable exact device-current elimination | Retain winding, excitation, grounding and nameplate observations. Test both current representations. |
| Repeated demand, generator-bound or price updates | Reuse through the supported update APIs | Equipment/topology changes and invalidated certificates require rebuilding. Build savings do not count toward the Ipopt-only speed criterion. |

These are candidate-generation rules, not automatic performance promises. Keep
every available transformation option, including candidates that lose on a
particular panel. A smaller model can produce denser derivatives or more costly
linear solves.

## Use measured evidence within its scope

Three existing results illustrate why selection must remain conditional:

- On the declared ordinary-transformer external panel, powers-only lifting
  outperformed broad lifting across the six case/objective cells; see the
  [external observation experiment](ivr_external_observations.md).
- Certified zero-load elimination improved all twelve matched comparisons in
  that panel, under its exact zero-power/nonzero-voltage conditions; see the
  [zero-load study](ivr_zero_loads.md).
- After zero-load reduction, the selected 333-bus tracking case favoured broad
  lifting despite more variables and iterations. Broad lifting also performed
  well on the separate manufactured multiwinding panel. These are different
  evidence domains; see [zero-reduced observations](ivr_zero_load_observations.md)
  and [coil observations](ivr_coil_observations.md).

The more recent refinement-depth and residual-target controls did not reduce
iterations or establish useful physical-accuracy gains. Keep the default native
minimum one and target ``10^{-10}`` as the general solver policy. Recovery work
and factor counts identify experiments, not speed winners. A requested native
residual target can remain unmet after recovery even when the physical endpoint
passes; see [residual-target controls](ivr_residual_targets.md).

The [initial pivot-threshold control](ivr_initial_pivot.md) subsequently reduces
linear solves from 118/126 to 67/67 in the two powers-only profiles, with unchanged
iterations and slightly larger factors. Keep `mumps_pivtol=1e-3` as a diagnostic
candidate beside the native `1e-6` control. No wall-time benefit or general default
change is established. Check effective MUMPS controls rather than inferring them
from Ipopt recovery messages.

## Validate a comparison before ranking it

Use a common physical start and record how each model encodes it. Require solver
acceptance, independent SI residuals, each endpoint in its own and the full
reference model, reverse feasibility of the reference endpoint, and agreement
with an independently evaluated physical objective. A local objective difference
must not be silently traded for runtime.

Preserve the same physical export schema and reconstruct every exactly recoverable
quantity. Intrinsically unobservable currents are explicitly unavailable; do not
invent them to fill a table. Verify JSON round trips and field paths as well as
values. Emitted-constraint completeness does not prove all input-schema fields
are supported; use the [field inventory](schema_fields.md), component scope and
negative bound tests together.

The executable comparison below uses a public two-wire teaching case, a power
objective and the same feasible physical start in both representations. It
checks bidirectional feasibility and export round trips. Its small solved
reference supplies the common start; this is an equivalence demonstration,
not a timing benchmark or evidence about an unseen network.

```@example exact_selection
using FormulationLab, JuMP, Ipopt
include(joinpath(@__DIR__, "..", "..", "examples", "tutorial_exact_ivr.jl"))
net = ExactIVRTutorial.two_wire_case()
terms = [IVRPowerTerm(channels=[(:voltage_source,"grid",1)], linear=1.0)]
common = (objective=:power, power_terms=terms, objective_scale=1.0,
          s_base=1e4, transformer_nameplate=:bmopftools)
reference = IVRNLP(;common..., lifting=:powers)
candidate = IVRNLP(;common..., specialization=:conductor_regions,
    linear_elimination=:passive_blocks, ground_scaling=:voltage,
    transformer_scaling=:nominal, row_scaling=:composed, lifting=:powers,
    observation_sharing=:signed)
settings = (print_level=0, tol=1e-10, constr_viol_tol=1e-10,
            acceptable_iter=0, bound_relax_factor=0.0)
seed_build = build_opf(net, reference; optimizer=Ipopt.Optimizer)
seed = solve_ivr_nlp_opf(seed_build; solver_options=settings)
@assert seed.solve.optimal && physical_residuals(net, seed).passed
start = ACPoint(voltage=seed.voltage_candidate, currents=seed.current_candidate)
builds = [build_opf(net, f; optimizer=Ipopt.Optimizer) for f in (reference,candidate)]
results = []
for build in builds
    encoded = ivr_nlp_point_report(build, start)
    @assert encoded.passed && isempty(encoded.missing_channels)
    @assert length(encoded.variable_values) == num_variables(build.model)
    for (variable,value) in encoded.variable_values
        set_start_value(variable,value)
    end
    result = solve_ivr_nlp_opf(build; solver_options=settings)
    @assert result.solve.optimal && physical_residuals(net,result).passed
    point = ACPoint(voltage=result.voltage_candidate, currents=result.current_candidate)
    @assert all(b -> ivr_nlp_point_report(b,point).passed, builds)
    @assert isapprox(result.objective, real(result.powers[(:voltage_source,"grid")][1]);
                     atol=1e-6, rtol=1e-8)
    exported = result_dict(build,result)
    io = IOBuffer(); write_result(exported,io); seekstart(io)
    @assert isequal(read_result(io),exported)
    push!(results,result)
end
@assert isapprox(results[1].objective,results[2].objective; atol=1e-6,rtol=1e-8)
(accepted_candidates=length(results), common_physical_start=true)
```

For a representative workload, use the retained
`examples/benchmark_ivr_profiles.jl` runner and the objective/network study
drivers linked from the performance guide. Record the exact input, objective,
candidate options, starts, solver version, units and admission decisions. Compare
validated objectives before calling `rank_profiles`. A failed or incomplete arm
cannot win. The compact example above does not replace component coverage tests
or the representative benchmark suite.

## Separate readiness from speed claims

Correctness and diagnostic work may proceed while timing is deferred. When
timing is explicitly authorized, use isolated paired Ipopt wall-clock trials
with declared warmups, repetitions, ordering and acceptance rules. Exclude
compilation cost from the ranking. Do not substitute total Julia elapsed time,
iterations, matrix dimension or factor storage for optimizer-call wall time.

Promote a profile only within the network/objective domain its evidence covers.
Retain the full reference and close alternatives. Extend a promising candidate
to additional power objectives and network structures before broadening the
recommendation. Stop adding solver knobs when diagnostics no longer change the
candidate decision; consolidate the reproducible portfolio instead.

## Prospective transfer and prior exposure

A rule supported by previously studied feeders is a hypothesis for new feeders.
Freeze that rule before observing new outcomes, then freeze the exact inputs,
objectives, physical starts, candidate options, solver controls and analysis
procedure before solving the selected validation cases. A revised rule informed
by those outcomes needs a separate validation set. Repeated timings improve
within-case precision; they do not increase the number of independent networks.

Use parent-network lineage as the unit of separation. Renamed copies, reduced
versions and new operating scenarios of a previously solved feeder are not
independent held-out feeders. Record structural inventory, compiler-only,
previously solved and performance-tuning exposure separately. A compiler-only
case can be held out from numerical solves while still having influenced the
compiler. Missing history is unresolved exposure, not proof of novelty.

The read-only helper `examples/ivr_transfer_inventory.py` inventories JSON under
the `output` and `benchmarks` directories of a supplied dataset root:

```sh
python3 -B examples/ivr_transfer_inventory.py DATA_ROOT NEW_REPORT.json
```

An optional `--census DATASET_CENSUS.json` imports the earlier structural census.
The helper records original byte hashes, complete JSON-content hashes, raw
component/connection features and groups sharing an identity-preserving topology
fingerprint. It invokes no optimizer and admits no held-out cases. Output must
be a new file; raw input files are unchanged. Keep these reports outside Git.

Content equality is insensitive to JSON object order and whitespace. Topology
fingerprints deliberately ignore impedances and operating data, so a match is
only a lineage-review signal. They cannot detect every relabelled, reduced or
expanded copy. Neither fingerprint replaces upstream provenance review. Raw
terminal counts do not establish a single-phase circuit; nominal zero load
counts do not establish the nonzero-voltage certificate for elimination; a
declared limit key does not establish activity or bound completeness.

Select validation cases from input features before solving, preserve failures,
and report uncovered network classes explicitly. Supplemental manufactured
active-limit scenarios can test a mechanism, but must retain declared parentage
and cannot fill a claim about unchanged external inputs. Compare predictions
against all admitted alternatives, report their per-case runtime regret, and
retain inconclusive and losing options. Timing authorization and the physical
admission gates above remain separate requirements.
