# Selecting an exact-IVR formulation

## Current recommendation (October 2026)

Start from a named profile and the recommended Ipopt options:

```julia
f = IVRNLP(profile=:scaled, objective=:power, power_terms=terms,
           transformer_nameplate=:bmopftools)
result = solve_opf(net, f; optimizer=Ipopt.Optimizer,
                   solver_options=ivr_ipopt_options())
```

| Profile | Enables | Use when |
|:---|:---|:---|
| `:scaled` | power lifting, per-zone transformer coordinates | default for performance |
| `:fast` | `:scaled` plus conductor regions, passive blocks, certified zero-load elimination | about 13% faster on the MV/LV feeders tested, slower on a 22k-bus network; benchmark first |
| `:reference` | nothing (all `IVRNLPOptions` defaults) | correctness comparisons |

The evidence, its mechanism and its limits are on the [findings](ivr_findings.md)
page. In brief:

- per-voltage-zone coordinates (`transformer_scaling=:nominal`, now the default)
  are the formulation choice that matters for Ipopt;
- `mumps_pivtol=1e-3` removes most of the remaining penalty of poor scaling;
- the solver matters as much as the formulation (MadNLP was about 3.5× faster
  than default Ipopt on the French feeders, but not at 22k buses).

The rest of this page is the earlier, campaign-era decision procedure. It is kept
for its correctness and validation guidance; its performance statements are
superseded by the findings page.

## Campaign-era guidance (archived)

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
| Exactly complex-proportional affine observations after composition | `observation_sharing=:complex_proportional` with bounded-observation lifting | Require the complete coefficient certificate and representable factor. Correctness tests include nonreal admittance; no wall-time or held-out benefit is established. See [affine sharing](ivr_affine_sharing.md). |
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

The helper also records conservative structural sampling labels. A single-phase
label requires at most one nonneutral terminal per bus; it excludes split-phase
circuits. Explicit-neutral four-wire sampling requires an actual four-terminal
line with a neutral at both ends, so three-wire variants with four-terminal bus
declarations do not qualify. MV/LV sampling uses declared transformer voltages
on either side of 1000 V. Mixed-device sampling requires at least two families
among transformers, generators, IBRs, switches and capacitors; source and grounding
records alone are insufficient. These labels are input conventions for a study,
not new compiler applicability certificates or operating-limit standards.

`select_panel(candidates, reviews)` in the same helper applies the frozen stratum
order and ascending SHA256 of source-relative paths, with at most two reviewed
parent networks per stratum and a default 3000-bus ceiling. Supply a review for
each encountered candidate containing its original byte hash, parent identity,
family-wide exposure categories, lineage/history review decisions and evidence
references. The selector checks byte identity and rejects conflicting parents
for identical JSON content. Solved/tuned exposure anywhere in the reviewed family
prevents primary held-out selection. It does not independently authenticate a
reviewer's evidence or infer all possible aliases.

An unreviewed candidate stops its stratum; a later case cannot silently leapfrog
it. An explicitly unresolved exclusion needs evidence and a recorded reason.
Already selected parents cannot fill another slot, and missing strata remain
visible gaps. The output retains the selection order, exclusions and pending
reviews and cannot authorize timing. Freeze the final reviewed case manifest
alongside the exact formulation and solver settings before running new solves.

### Power workloads on original and supplemental cases

`examples/ivr_transfer_specification.jl` constructs explicit workloads without
requiring a dispatch device. This matters when unchanged input networks contain
only fixed demand. Such cases exercise objective representation and recovery;
they do not establish transfer to economic dispatch. The returned declaration
separately records active and reactive dispatch-box freedom. Even nonzero box
width does not prove feasible freedom after all circuit constraints are applied.

For this versioned experiment, let ``P_0,Q_0`` denote aggregate source exchange,
and let ``P_j,Q_j`` denote each generator or IBR PCC coil power, all expressed in
kW/kvar. Let ``P_j^{\mathrm{int}}`` denote generator power or IBR internal power.
The declared cost is

```math
C=0.25P_0+0.02P_0^2+0.002Q_0^2+
  \sum_j\left(0.10P_j^{\mathrm{int}}+0.02P_j^2+0.002Q_j^2\right).
```

The tracking workload, for an explicitly declared source target ``P_0^\star``, is

```math
T=(P_0-P_0^\star)^2+Q_0^2+
  0.01\sum_j\left[(P_j-\bar P_j)^2+Q_j^2\right],
\qquad \bar P_j=(P_j^{\min}+P_j^{\max})/2.
```

The implementation converts these coefficients to W/var and uses physical
objective divisor one. These are experimental coefficients, not imported tariffs.
Both sums over dispatch devices are empty for original fixed-load cases. Source
quadratics act on the **aggregate** exchange, not separately on each source
terminal. IBR internal active-power cost includes filter losses; its quadratic
and tracking terms use PCC power. Legacy `cost` fields do not alter these declared
workloads. Compared with the earlier mixed-device driver, this definition adds
source P/Q quadratic terms to cost; historical objective values are therefore
not directly comparable and existing drivers remain unchanged.

For example, after loading an input dictionary as `net`:

```julia
include("examples/ivr_transfer_specification.jl")
S = IVRTransferSpecification
common = IVRNLPOptions(s_base=1e5,
    transformer_nameplate=:bmopftools, transformer_scaling=:nominal,
    row_scaling=:composed, ground_scaling=:voltage,
    observation_sharing=:signed, lifted_power_base=500.,
    load_power_lifting=true)
declaration = S.profiles(net, :exchange_tracking;
    common, exchange_target_W=350.) # illustrative target; freeze a case-specific value
```

The declaration contains a full powers-only control and the eight combinations
of transformer-current elimination, powers/broad lifting and zero-load
elimination. Each arm owns its options and shares the objective and unit policy.
An additional unlifted full reference is for representation checks. Supplied
unrelated reductions are rejected to avoid hidden experimental factors. This
constructor has no transformer-kind filter and does not certify applicability;
compiler refusals must remain recorded outcomes. Explicit regional bases can be
supplied through `common`, and must be frozen with the other settings.

Manufactured tests compare both objectives with closed-form single-bus solutions,
including a binding generator active-power limit, common-start encoding,
full/reduced membership, physical residuals and canonical SI export round trips.
They distinguish aggregate-source and internal/PCC accounting. These correctness
checks are not evidence of external-network transfer or runtime improvement.

### Explicit supplemental dispatch scenarios

`examples/ivr_transfer_scenarios.jl` defines a bounded mixed-device experiment
when unchanged inputs lack dispatch. Within each of WYE and DELTA demand, it
selects the first two positive three-coil loads in ascending SHA256 of load ID.
The first receives a generator and the second an IBR: four added devices per
parent. Missing configurations make this particular recipe inapplicable; they
do not justify selecting a later parent after observing solver outcomes.

Every original record, annotation and bound is retained. For a selected demand
with nominal coil powers ``p_k``, each added coil receives active bounds
``[0,c]``, reactive bounds ``[-c/2,c/2]`` and apparent-power cap ``c``, where
``c=2\sum_{k=1}^3p_k/3``. An explicit positive voltage vector supplied by the
experiment defines ``Z_k=V_k^2/c`` for the new IBR filters. Their resistance and
reactance are ``0.005Z_k`` and ``0.002Z_k``; shunt susceptance is
``0.002/\operatorname{mean}(Z)``. Internal DC active power has bounds
``[0,0.6(3c)]`` and availability ``0.8(3c)``. These are scenario parameters;
the voltage vector does not replace any original voltage limit or per-unit base.

The returned manifest records the four sites, all added records, and which
component tables were previously absent. Tests replay and reverse the additions,
and check physical residuals, declared-bound coverage, internal/PCC filter-loss
accounting, and canonical result recovery on a manufactured mixed-device circuit.
The bounds create opportunities for active-limit tests; activity must be measured
at accepted endpoints and is not guaranteed by this construction.

Supplementals remain separate physical problems with shared parentage. They do
not increase the number of independent held-out parents, repair invalid original
inputs, or establish missing external single-phase/multiwinding coverage. Freeze
the selected parents, voltage vectors, complete augmented inputs and objectives
before any supplemental solve.

### Preparing and executing correctness checks

`examples/ivr_transfer_preflight.jl` separates preparation from optimizer calls.
`prepare(input, new_folder; common, exchange_target_W)` saves the normalized
compiler input, exact objective and option records for both workloads, and one
SI start containing named bus voltages and all modeled device currents. Known
legacy provenance is detached through the existing input boundary and retained
in metadata; the original file hash must remain unchanged. Preparation computes
an unloaded linear-circuit point with fixed source coordinates. This is a linear
calculation for initialization, not an OPF solution or a feasibility claim.
Unsupported inputs produce saved preparation refusals instead of replacements.

The preparation also records strict solver settings and explicit tolerances:
start encoding at ``10^{-10}`` per unit, model membership at ``10^{-7}``, SI
residual limits of ``10^{-5}`` V, ``10^{-6}`` A and ``10^{-3}`` VA, and objective
comparison with absolute/relative tolerances ``10^{-6}/10^{-8}``. Ipopt uses
`tol=constr_viol_tol=1e-10`, no acceptable-iterate termination, zero bound
relaxation, 500 iterations and 30 CPU seconds per trial. The declared control
uses MUMPS ordering 7, pivot tolerance `1e-6`, and gradient-based NLP scaling.
JSON numeric values are restored to Ipopt's required option types before use;
for example, a zero real-valued bound-relaxation factor must remain a real option.

After freezing the **whole study protocol**, call
`run(prepared_folder, new_output_folder; expected_preparation_sha256=digest)`.
The digest binds the preparation record and its input/start/workload file hashes;
source bytes are checked before and after execution. A digest alone does not
establish that a study completed its prospective freeze, nor does it authenticate
arbitrarily rewritten evidence. External studies must freeze code/environment,
case lineage and analysis along with these preparation artifacts.

The runner attempts the two workloads across all nine arms, preserving failed
trials and reference-model refusals. Each accepted trial needs complete declared
and emitted bound inventories, common-start encoding, independent physical
residuals, own/full model membership, reverse membership of a common accepted
anchor, physical-objective reconciliation and canonical SI export round trips.
Physical field paths and unavailable-value locations must agree across accepted
arms. An unsupported preparation records eighteen planned but unrun trials.
Unequal local objectives remain in correctness reporting and fail the separate
comparison gate. Complete emitted coverage does not assert complete input-schema
coverage. No wall times are collected or ranked by this runner.

Future schedules are recorded without executing them: eighteen cyclic/reversed
nine-arm portfolio sweeps, sixteen balanced eight-arm factorial sweeps, and
sixteen alternating two-arm pivot sweeps. Confirmation reverses the exploration
schedule. Portfolio positions are balanced; no predecessor-balance claim is made
for that schedule. These declarations do not authorize timing campaigns.

`examples/ivr_transfer_analysis.py` supplies descriptive statistics for admitted
timing sweeps. It reports per-arm medians, both ratios of medians and medians of
paired ratios, and the complete paired log-ratio samples. These estimands differ
and must retain their labels. Its eight-arm contrasts separate zero-load,
lifting and current-elimination effects from two- and three-factor interactions.
Parent summaries first average log ratios within each parent and then weight
parents equally; supplemental variants are not additional independent networks.
Domains, objectives and batches must be summarized separately. Missing, failed,
nonpositive or nonfinite timing entries are refused rather than dropped.

For the prospective general-control policy, selector regret is the median time
of the predeclared `full_powers` choice divided by the best admitted arm's median
on that case/objective/batch. The latter is a retrospective comparison, not a
prospective prediction. Conditional reduction hypotheses remain separately
testable contrasts. The analysis helper does not authenticate physical/timing
admission, promote defaults or count failed cases; retain those failures in the
study's applicability and robustness denominator before interpreting summaries.

Select validation cases from input features before solving, preserve failures,
and report uncovered network classes explicitly. Supplemental manufactured
active-limit scenarios can test a mechanism, but must retain declared parentage
and cannot fill a claim about unchanged external inputs. Compare predictions
against all admitted alternatives, report their per-case runtime regret, and
retain inconclusive and losing options. Timing authorization and the physical
admission gates above remain separate requirements.


## First frozen held-out correctness panel

The 2026-10-09 baseline campaign used source commit `126ed87`, two power objectives
and nine predeclared formulations per runnable problem. The local evidence
manifest `FREEZE_B.json` has SHA-256
`de99283d8b5f5bc8b1f440ecc2c3113351d5456e1567a6357ec7dbb9dc903784`.
It binds inputs, starts, per-unit bases, solver settings and the unchanged
selection rules. Raw evidence remains outside Git.

| Role | Problems | Optimizer trials | Accepted trials | Other outcomes |
|:--|--:|--:|--:|:--|
| Original held-out French feeders | 6 | 108 | 0 | All locally infeasible |
| Declared mixed-device supplements | 2 | 36 | 0 | 32 locally infeasible; 4 iteration limits |
| Original LV inputs refused at preparation | 2 | 0 | 0 | 36 planned cells unrun: undeclared ground terminals |
| Known training scenario | 1 | 18 | 18 | Comparable objectives and passed validation gates |

All runnable cases passed the known declared-bound and emitted-row inventories;
these checks do not certify complete input-schema coverage. The held-out result
supports **no speed ranking or transfer claim**. Local infeasibility statuses are
not proofs that the physical problems have no feasible solution. No timing
campaign was run, and the original failures remain in the denominator.

One subsequent diagnostic replay of the first original feeder, quadratic cost
and `full_powers`, preserved the original problem/start/settings and saved its
failed endpoint. Eight significant load active-power mismatches occur downstream
of transformer `11_MVLV04468_Transformer`; a separate line voltage-drop row also
fails. The transformer's phase ratings are 91.667 kVA. Declared downstream phase
demands have magnitudes 60.397, 93.204 and 97.477 kVA, while total demand is
251.078 kVA against a 275 kVA nameplate. Phases 2 and 3 are saturated at the failed
endpoint. This identifies a per-phase capacity hypothesis missed by an aggregate
screen; it is not a certificate, since phase coupling, losses and alternative
feasible states have not been bounded. It must not be generalized to the other
failed cases without inspecting their evidence.

The next correctness priority is to diagnose these failures, rather than promote
any arm. Separately, [certified fixed-bound removal](ivr_fixed_bounds.md) is an
opt-in candidate with explicit equivalence and update conditions. Its initial
training applicability does not supply a held-out performance result. The frozen
baseline artifacts retain their original option schema; reproduce them with
their bound source snapshot, and declare any new candidate configuration separately.

## Finite post-baseline candidate follow-up

`examples/ivr_candidate_followup.jl` defines a correctness-only paired follow-up.
Baseline admission is recorded separately from execution eligibility: every
preparation-ready problem remains eligible for a correctness attempt, including
those on which the baseline failed. This permits observation of convergence
improvements without discarding the original failures. These networks have now
been examined; follow-up outcomes are post-baseline evidence, not a newly blind
held-out cohort. Original preparation refusals remain explicit unrun cells.

The declared design applies both saved power objectives to six contrasts:

| Contrast | Shared configuration | Control → candidate |
|:--|:--|:--|
| Fixed bounds, power lifting | Full power-lifted model | `fixed_bound_elimination=false` → `true` |
| Fixed bounds, broad lifting | Broad observations; fixed observations inlined | Same fixed-bound toggle |
| Complex sharing | Broad observations; fixed observations retained | `proportional` → `complex_proportional` |
| Expression support | Power lifting; passive-block elimination | `bound_support` → `expression_support` |
| MUMPS pivot, retained currents | Saved `off__powers__zero_true` profile | `mumps_pivtol=1e-6` → `1e-3` |
| MUMPS pivot, eliminated transformer currents | Saved `transformer_currents__powers__zero_true` profile | Same pivot contrast |

The first four controls derive from the saved `full_powers` configuration with
only the stated common changes. Both arms retain identical objective terms,
physical starts, per-unit bases, bounds and solver controls except for the
declared contrast. The earlier option schema is migrated explicitly by adding
`fixed_bound_elimination=false`; unknown schemas are refused. No baseline artifact
is overwritten. Nine ready problems yield 216 planned optimizer calls; two
preparation refusals account for another 48 planned but unrun cells. The original
zero-load × lifting × current-elimination factorial remains a separate design.

Before external execution, the calling study must authenticate the baseline
reports and freeze the complete pair plans, code, environment and inputs. The
helper does not perform that study-level freeze. It attempts both arms regardless
of either solve status, writes each trial outcome separately, and saves failed
diagnostic primals and independent physical checks when available. Such primals
never become accepted solutions or common anchors. Cross-model check errors
prevent comparison admission and remain explicit in the pair report.

Pair admission requires both accepted endpoints, membership in each other's
model, matching physical-export availability, and comparable objective values.
Acceptance includes the original physical, bound-inventory, start, unreduced-model,
objective and JSON round-trip checks. A status of local infeasibility remains a
solver outcome rather than an infeasibility certificate. An option that changes
no eligible structure supplies no evidence for its proposed mechanism; retain
and identify such no-op contrasts when interpreting compiler diagnostics.

This helper records no timing ranking. Correctness admission is a prerequisite
for later timing and does not authorize it. Future authorized timing uses two
isolated batches, an excluded warmup per arm and sixteen alternating paired
sweeps per contrast/objective, with Ipopt wall time as the primary metric.
Compilation is excluded. Retain each candidate as an opt-in option and report
performance as undetermined until admitted measurements support a recommendation.
The missing external single-phase slot and failed external admissions remain
explicit limitations on transferable selection rules.

## Completed post-baseline follow-up

The finite follow-up completed at source commit `ab39d32`, with freeze-C SHA-256
`7cd4281c3dd35c977cb772dafd8b36c8fef08657fb48d7101054ec87a00591ad`.
The terminal audit verified all 590 frozen repository files and their archived
copies, 989 protected evidence/environment paths, the complete pair set and both
original preparation refusals. Raw evidence remains outside Git. These already
examined networks provide post-baseline evidence; they are not a new blind cohort.

| Role | Runnable problems | Optimizer outcomes | Accepted outcomes | Comparable pairs |
|:--|--:|--:|--:|--:|
| Original French feeders | 6 | 144 | 0 | 0 |
| Declared mixed-device supplements | 2 | 48 | 0 | 0 |
| Known training scenario | 1 | 24 | 24 | 12 |

All 192 external outcomes were `LOCALLY_INFEASIBLE`; all 24 training outcomes were
`LOCALLY_SOLVED` and passed the physical/model, objective and export gates. The two
original LV input refusals account for another 48 planned but unrun cells. No
input was repaired or replaced. Every runnable arm passed common-start encoding
and the known declared-bound/emitted-row inventories. Failed primals were retained,
and physical audits reported no unassessed channels. These facts do not establish
exhaustive input-schema coverage or global infeasibility of the external problems.

### Applicability and candidate decisions

A separate optimizer-free census rebuilt the 36 complex-sharing and
expression-selection pairs. It compared indexed constraint functions and sets,
the objective and variable names, in addition to compiler diagnostics. All 36
pairs produced identical indexed models. This is stronger than equal row counts;
it is not a graph-isomorphism test or an independent recovery certificate.

| Candidate | Observed mechanism in this panel | Decision supported by present evidence |
|:--|:--|:--|
| Certified fixed-bound removal | Six certified rows removed in each of 36 candidate arms across two lifting contexts | Retain opt-in; applicable, but no external convergence rescue and no measured speed benefit |
| Complex-proportional sharing | Zero shared observations in both arms of all 18 pairs | Retain opt-in; added mechanism unexercised in this configuration |
| Expression-support selection | Zero eliminated complex coordinates in both arms of all 18 pairs | Retain opt-in; added selector changes no generated model in this configuration |
| MUMPS pivot `1e-6` → `1e-3` | Four training pairs pass; all 32 external pairs fail admission | Retain experimental setting; no promotion or runtime conclusion |

The sharing contrast uses broad lifting with fixed-observation, device-current
and zero-load elimination off. The expression-selection contrast uses power
lifting and passive-block elimination with device-current and zero-load
elimination off. Both retain the original scaling and power-objective definitions.
Absence of a change in these isolation contexts does not exclude benefits after
other compositions. In particular, this study does not test the new sharing mode
after transformer-current elimination. The earlier factorial supplies evidence
for its own declared factors, not for that missing interaction.

On the first feeder, the bound-support and expression-support selectors both
reject three candidate reductions because voltage-bound factors would depend on
more coordinates. Thus the new objective-aware check adds no restriction there.
The manufactured interior-line-power counterexample remains a valid mechanism
test, but the external panel does not exercise that distinction.

### Failure diagnosis and selection procedure

Failures do not share a single established cause. The first feeder retains power
residual maxima near 4 kVA. The second instead fails voltage checks while all
power residual maxima remain below `6e-9` VA. On the third, power-oriented and
broad-observation profiles terminate with different power or lower-voltage
violations. These describe failed endpoints, not isolated causal effects of a
single option. Residual relocation can occur between exact representations of
the same feasible set; it does not demonstrate resolution of a physical limit.

The supported procedure therefore has three distinct checks:

1. **Applicability:** inspect realized substitutions, shared observations and
   bound certificates. A candidate that produces no additional mechanism in the
   declared context supplies no evidence of that mechanism's benefit.
2. **Correctness and comparability:** require the common physical start, all
   declared physical/model/bound/export gates, reverse membership and comparable
   objective values. Preserve failures and refusals in the denominator.
3. **Performance:** only after explicit timing authorization, compare admitted
   pairs using measured Ipopt wall time excluding compilation. Keep objectives,
   parents, domains and batches separate; apply the frozen promotion criteria.

No new transferable speed rule or default follows from this follow-up. The
prospective `full_powers` control remains a control, not a newly established
universal winner. Training correctness permits preparation of its finite timing
comparisons; it does not establish external transfer. The original factorial's
held-out runtime interactions, bounded-pivot runtime benefit and external
single-phase coverage remain unresolved. All options are retained, and no timing
campaign was run.

## Native solver timing boundary

Future authorized comparisons distinguish two measurements. In the inspected
Ipopt.jl 1.16.0 wrapper, `JuMP.solve_time` returns `MOI.SolveTimeSec`: elapsed wall
time from entry into `MOI.optimize!` through the return from `IpoptSolve`. That
interval includes wrapper setup, option transfer and starting-point assignment.
Historical example reports call it `ipopt_wall_s`; retain those reports and
interpret that field as **wrapper-inclusive optimizer time**. It excludes the
separate FormulationLab model build, but is not a measurement of only the native
solver call. Do not pool the two timing definitions or relabel historical data.

For the stricter measurement, `examples/prepare_ivr_native_timer.py` creates a
separate copy of the inspected Ipopt package and inserts an opt-in recorder
immediately around `Ipopt.IpoptSolve(inner)`. The generator refuses unsupported
wrapper bytes, existing output directories and outputs inside the installed
package. It verifies byte-exact restoration of the original wrapper after
removing its three insertions, inventories every copied file (including `ext/`),
and verifies that the installed source has not changed. Only the copied wrapper
and added timer helper differ. The provenance JSON records those inventories;
it is not included in its own file-hash inventory.

The recorder in `examples/ivr_native_timer.jl` is disabled by default. When
enabled, it uses monotonic nanosecond ticks around that call. The interval
includes Ipopt's internal initialization, numerical work and callbacks. It
excludes wrapper preparation, FormulationLab construction, result extraction
and physical audits. Clock reads and dispatch introduce instrumentation overhead;
declared warmups must also exclude first-use compilation on the callback path.
This is an instrumented call measurement, not an assertion of zero overhead.

A sample is cleared at each optimizer entry, including before setup failures or
an invalid-model early return. Exceptions from the native call propagate and
leave no admissible duration. Ordinary clock errors, noninteger ticks and
nonpositive intervals invalidate the sample. A `completed` timer status means
only that the call returned; it does not imply an accepted optimizer outcome.
Physical, objective, bound, export and solve-status gates remain mandatory.
The recorder is intended for one serial study process and does not enforce
campaign authorization or process isolation itself.

Preparation and focused tests can be run without a timing campaign:

```sh
python3 -m unittest discover -s test -p test_prepare_ivr_native_timer.py
julia --project=test --startup-file=no test/ivr_native_timer_tests.jl
python3 examples/prepare_ivr_native_timer.py /path/to/Ipopt /new/external/Ipopt-copy
```

Load the copy through a separate, pinned Julia environment, retaining the
original dependency versions and changing only the Ipopt manifest entry to its
copied path. Do not modify the project test environment or installed package.
The explicit integration check verifies which package loaded and solves a
manufactured scalar quadratic with recording disabled and with a synthetic
clock:

```sh
julia --project=/path/to/pinned-environment --startup-file=no --threads=1 \
    test/ivr_native_timer_integration.jl /new/external/Ipopt-copy
```

These checks validate the measurement boundary, result preservation and stale
sample handling; they provide no speed evidence. A future execution freeze must
authenticate the instrumented source, complete dependency extensions, runner,
environment and accepted finite schedule. The package-copy manifest explicitly
sets `timing_authorized=false` and `execution_ready=false`. Preparation does not
authorize measurement, change the frozen correctness results, or promote any
formulation.

### Frozen correctness adapters and finite job preparation

The B and C studies use different compiler checkpoints. Timing preparation must
not silently move B configurations to the current compiler. The helper
`examples/ivr_timing_adapter.jl` checks that the loaded FormulationLab package is
the declared archive and authenticates the archived correctness executor against
its known SHA-256. It adds a post-solve observer to an in-memory copy of that
executor; reversing the insertions must restore the original bytes. Nested
includes resolve within the same archive. No archived file is edited.

The observer reads the native sample before the optimizer can become unreachable.
Existing physical, model, objective, bound and SI-export checks remain in the
archived executor. `disabled` mode is the default. `synthetic` mode requires an
injected test clock and writes only a separately labeled synthetic duration;
it always leaves `native_ipopt_wall_s` empty. `native` mode requires explicit
authorization from the caller. Every exit restores a disabled recorder and
clears its samples. This low-level adapter does not establish process isolation,
runtime provenance, sweep comparability or campaign admission.

`examples/prepare_ivr_timing_jobs.py` authenticates the admission ledger, its
referenced evidence, both complete source archives, prepared inputs and original
case bytes. It reconciles each arm, solver configuration and measured order with
the corresponding frozen workload or candidate plan. It then writes one job
record per admitted batch, including its reference model, tolerances and every
planned call. The previously unspecified warmup ordering is declared as ascending
arm index, one excluded warmup per arm; measured orders are unchanged.

```sh
python3 examples/prepare_ivr_timing_jobs.py \
    /path/to/admission/MANIFEST.json EXPECTED_SHA256 /new/external/jobs
```

The current ledger expands to 32 training-only jobs and 2,044 planned calls,
including 116 excluded warmups. These counts describe a finite design, not a
runtime estimate or evidence of external transfer. Preparation does not execute
the calls. Generated jobs retain `timing_authorized=false` and
`execution_ready=false`: a complete runtime freeze and the binding of the
launcher to campaign-level checks remain necessary before authorized measurement.
Synthetic-clock integration checks against each archived compiler
are available in `test/ivr_timing_adapter_integration.jl`; they use a manufactured
single-phase transformer with a power objective, not an experimental cohort.

### Worker admission and process isolation

`examples/ivr_timing_controller.jl` validates the entire event sequence before
calling an optimizer. Every event receives a separate trial record, including
failed solves; ordinary trial failures do not remove later planned calls. An
interruption leaves an explicit pending event and an incomplete worker report.
Outputs must be new directories outside the repository, frozen source archive
and prepared inputs. Non-finite numerical diagnostics are written as JSON null
and remain inadmissible; physical exports still use the archived result writer.

For each warmup group and measured sweep, the worker checks every accepted
point in the control model and the control point in every arm. It uses declared
arm identity, independently of the order in which the arms executed. It also
requires equal physical-export availability and comparable objective values.
The original physical, bound, start, model, objective and result-readback gates
remain mandatory. No previous solution replaces the declared common physical
start. Warmups exercise the same timer path as measured trials and are explicitly
excluded from every performance comparison.

Even a complete native worker produces only provisional admission. It records
its process identity and Julia/BLAS thread counts; `campaign_eligible` remains
false and no ranking is produced. A synthetic worker never supplies an admissible
native duration. Manufactured integration tests exercise a reversed two-arm
sweep and deliberately corrupt objectives, export shapes and recovered points
to test rejection. They are controller checks, not evidence about formulation speed.

`examples/ivr_timing_isolation.py` observes the macOS/POSIX process table without
stopping any process. The monitor expects one worker PID and parent PID. Other
Julia processes, failed process queries, a missing expected worker, invalid
clock records, excessive observation gaps or an unfinished trace prevent
admission. The default polling interval is 0.2 s and the maximum permitted gap
is 1 s; freeze these settings before use. The gap check conservatively spans the
start of the previous query through the end of the next query.

Polling provides **sampled isolation evidence**. A process whose entire lifetime
falls between observations can escape detection; a clean trace is not proof of
continuous isolation. This limitation and monitoring overhead must accompany any
later performance report. The original exclusion rule remains: any detected
overlap rejects the whole campaign, including otherwise clean jobs. Never use
those jobs as an outcome-selected replacement campaign.

The campaign auditor reconciles every expected job and trial, excludes warmups,
rechecks native-sample validity and objective comparisons, checks both directions
of model membership recorded by the worker, and recomputes isolation from raw
observations. It binds the observed worker PID to the completed report and rejects
missing or malformed records. It does not rerun the physical equations in Python;
those checks remain the responsibility of the authenticated Julia executor.
Before execution, the launcher must authenticate the jobs and full runtime,
hold each worker until monitoring begins, and enforce explicit human timing
authorization. These controller components alone do not authorize a campaign.

### Held-worker launcher and execution freeze

`examples/ivr_timing_launcher.py` supplies the remaining process boundary. A
bootstrap process waits before executing Julia, retaining the same PID across
`exec`. The parent registers that PID and starts monitoring first. Julia then
loads the declared compiler and executor, records its runtime, and waits for a
second release. No network construction or solve precedes that release. Native
release requires the authorized job digest, matching worker and parent PIDs, and
a one-use nonce passed through both the permit file and the worker's input pipe.

The launcher's `inspect` command exercises this handshake and runtime capture
without building or solving a network. It produces an inspection report, not a
native worker report, and cannot pass campaign admission:

```sh
python3 examples/ivr_timing_launcher.py inspect \
    /path/to/job.json JOB_SHA256 /path/to/pinned-environment \
    /absolute/path/to/julia /new/external/inspection
```

The Julia executable must be the actual binary, rather than a version-manager
launcher that creates a second Julia process. `examples/ivr_timing_runtime.jl`
inventories the active project and manifest, complete dependency source trees
(including extensions), selected installed host artifacts, loaded package caches
and images, the executable, system image and readable loaded libraries. It records
path aliases, tree membership, Julia/BLAS thread counts, relevant environment
variables, CPU identity and OS build. No artifact is downloaded. `.git` and Python
bytecode-cache directories are excluded from source-tree traversal. Unexpected
directory symlinks or unresolved non-system libraries require review.

On macOS, shared-cache system libraries may have no readable individual file.
Their identities are recorded with the OS build and library names; this is an
explicit limit on byte-level provenance. Inspection captures both compiler
versions separately. Manufactured correctness tests compare the runtime before
and after four synthetic-clock solves to detect newly loaded or changed files.
This checks the exercised path, not every possible future dynamic-loading path.

`examples/prepare_ivr_execution_freeze.py` authenticates the prepared job manifest,
ledger and referenced evidence, validates both successful inspection reports and
their raw process traces, and rechecks runtime files and tree membership. It binds
those records to the launcher, worker, adapter and controller sources, plus the
Python executable/build and readable loaded Python module files. It writes a new
external `FREEZE.json` and an **unauthorized** template:

```sh
python3 examples/prepare_ivr_execution_freeze.py \
    /path/to/jobs/MANIFEST.json MANIFEST_SHA256 \
    /path/to/inspection-B /path/to/inspection-C /new/external/freeze
```

`execution_ready=true` in this freeze means that the execution inputs have been
assembled and verified. It is separate from human authorization, which remains
false. Only after an explicit human instruction may an authorization record bind
that exact freeze digest, the ordered job subset, the instruction reference and
one new output directory. Both exploration and confirmation batches must remain
together for every selected comparison. The native entry point is:

```sh
python3 examples/ivr_timing_launcher.py run \
    /path/to/FREEZE.json FREEZE_SHA256 /path/to/authorization.json \
    /authorized/new/output
```

Before release, the launcher verifies protected bytes and compares the waiting
worker's runtime with its frozen capture. It rechecks the runtime after native
execution and audits the complete selected campaign. Source drift, runtime drift,
contamination, timeouts or incomplete output prevent admission. A failed launch
retains logs, its exit record and process observations; cleanup targets only its
own child. The default readiness limit is 900 s and the worker limit is 21,600 s,
recorded in the freeze as failure bounds, not runtime estimates. No timing is
authorized by preparing these artifacts, and no performance ranking follows from
inspection or synthetic-clock validation.
