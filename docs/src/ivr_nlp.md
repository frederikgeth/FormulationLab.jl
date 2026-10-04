# Exact IVR

`IVRNLP` is an experimental exact static AC formulation. It retains conductor
voltages and component currents and uses the exact products `S = U*conj(I)`.
It applies no approximate network reduction. Optional conductor-difference
specialization preserves the supported full-IVR problem.
`formulation_kind(IVRNLP()) == :exact` describes these equations; Ipopt normally
returns a local solution, not a global optimality certificate.

## Usage and repeated operating points

```julia
using FormulationLab, Ipopt

build = build_opf(input, IVRNLP(objective=:source_import);
                  optimizer=Ipopt.Optimizer)
result = solve_ivr_nlp_opf(build; solver_options=(print_level=0,))
audit = physical_residuals(build.network,
    ACPoint(voltage=result.voltage_candidate, currents=result.current_candidate);
    delta_dispatch=:coil)

# SI watts and vars, with one entry per connection channel.
update_ivr_loads!(build, Dict("load_id" => (p=[1000.0], q=[200.0])))
next_result = solve_ivr_nlp_opf(build; solver_options=(print_level=0,))
```

`build_opf(input, IVRNLP())` builds without an optimizer. The one-shot
`solve_opf(input, IVRNLP(); optimizer=Ipopt.Optimizer)` requires an explicit
optimizer; there is no implicit conic optimizer fallback. Ipopt remains a test
or caller dependency, not a package runtime dependency.

Updates change constant-power load constraint right-hand sides and the owned
network snapshot. The full update is validated before mutation. Unknown loads,
impedance-load changes, wrong arity and nonfinite values are rejected. Invalid
input leaves the existing instance usable; optimizer failures are not covered
by a transactional rollback guarantee. Equipment coefficients, source phasors
and per-unit bases remain fixed. Diagnostics record assembly and update counts.
There is no automatic warm-start transfer or solver-factorization reuse claim.

Generator P/Q boxes and linear prices can also change on the same instance:

```julia
update_ivr_generators!(build, Dict("generator_id" =>
    (p_min=[0.0], p_max=[5000.0], q_min=[-2000.0], q_max=[2000.0], cost=[0.12])))
# Omitted fields stay unchanged; nothing removes one bound.
update_ivr_generators!(build, Dict("generator_id" => (q_min=nothing,)))
```

Bounds use SI W/var and `cost` uses currency/kWh, with one value per native
connection channel; delta uses coil powers. Fixed boxes (`min == max`) can become
dispatchable and return to fixed values without replacing the electrical power
equations. Explicit generator P/Q variables carry the bounds and prices and are
included when evaluating supplied physical points. Variable-bound constraints
may be added or removed, and solver preprocessing can change; this is not a
promise of constant factorization structure.

All entries and resulting boxes are checked before mutation. Unknown generators,
inverted boxes, nonfinite values, wrong arity and unsupported fields are rejected.
An empty update dictionary is a no-op. Only `cost` is accepted as the price-update
field; an existing `energy_cost_rate` alias is kept consistent. Price updates
affect the objective only in `:cost` mode. Source bounds/prices and equipment
ratings are outside this update API. Diagnostics include `:generator_update_count`
and `:dispatch_variable_count`; `:update_count` counts successful nonempty calls
to either update API. Each call validates its own batch; two separate calls are
not one transaction. Use the APIs rather than modifying the owned snapshot.

## Supported scope

The initial implementation supports mutually coupled lines, endpoint shunts,
ideal bus grounds, finite grounding admittances, fixed source phasors,
constant-power and constant-impedance loads, and generator P/Q boxes. Wye,
delta and single-phase connection maps are retained. Physical limits include
conductor current, apparent power, phase-ground, phase-neutral, phase-phase,
neutral and supported sequence-voltage magnitudes. Lower voltage magnitudes
are exact nonconvex inequalities. Delta device dispatch and ratings use coil
semantics consistently with `physical_residuals(...; delta_dispatch=:coil)`.
Line current limits apply to total endpoint currents including shunts.

Fixed switches require a Boolean `open_switch`. A closed switch equates
corresponding endpoint voltages and carries an explicit through-current;
an open switch carries zero current without equating endpoint voltages.
`i_max` and the dictionary extension `s_max` apply at both ends, with one
entry per declared switch conductor (including neutral), in terminal-map
order. Apparent power is terminal-to-ground voltage times conjugate current.
Results expose `:switch_from` and `:switch_to` currents and powers; supplied-point
checks bind the through-current and check both endpoint channels. Switch state
is fixed equipment data: changing it requires a fresh build.

Fixed capacitors use exact connection-aware susceptances for single-phase,
wye and delta connections. Scalar `q_rated` is total bank vars, with three-phase
`v_nom` specified line-to-line; wye coil voltage is therefore `v_nom/sqrt(3)`.
Array `q_rated` retains the explicit per-coil rating/coil-voltage convention,
including asymmetric banks. See [capacitor contracts](sdp_static.md) for arity
and conversion details. Currents and consumed powers appear under `:capacitor`;
reactive consumption is negative and varies with squared voltage. A rating
does not create a var cap. Unknown capacitor current/power limits or controls
are refused. Rating/nominal-voltage changes require a fresh build.

Fixed isolated-winding transformers support `single_phase`, `center_tap`,
`delta_wye`, `wye_delta` and `n_winding`. The shared winding circuit retains
leakage, fixed ratios and phase shifts, excitation, neutral grounding and
side-specific current limits. Delta winding current limits apply to coils;
other side limits apply to terminal currents. General multiwinding limits
`i_max` and `s_max` apply to coil channels. `s_rating` is a schema power base,
not an implicit operating limit. See [Transformer winding model](sdp_transformers.md)
for coefficient and orientation conventions.

Ordinary transformers accept the schema `tap_ratio`, `tap_ratio_min` and
`tap_ratio_max` spellings through the existing BMOPF adapter, which copies them
to the internal `tap`, `tap_min` and `tap_max` fields. Both spellings are retained;
conflicting values are rejected. General multiwinding entries use `tap_ratio`
per winding. Unequal tap bounds require an explicit fixed setting.
Taps are fixed equipment data and cannot be
changed through the load/generator update APIs.

Supported objectives are `:cost` (linear currency/kWh coefficients),
`:source_import` (watts), and `:feasibility`. Inputs and outputs use SI units;
`s_base` controls internal scaling. Inputs are copied rather than modified.
Without transformers, switches or capacitors, each voltage conductor must have a line path to a fixed source, ideal ground,
or finite one-terminal ground. A finite ground supplies only an initial voltage
guess; its voltage is not fixed and its actual admittance/KCL remain enforced.
With transformers, switches or capacitors, a sparse linear circuit solve provides starts using every
fixed source phasor. Constant-power load and generator currents are zero only
in this initialization; impedance loads, capacitors, excitation, grounds and closed switches remain active.
It requires unique no-load conductor voltages and rejects inconsistent circuits
or floating sections, including an unreferenced delta secondary. No artificial
ground or voltage gauge is inserted. Current-only freedom is allowed in the
initial solve and retained in the nonlinear model. Diagnostics distinguish
`:linear_circuit` and `:line_propagation` initialization.
An open switch cannot provide a voltage reference to a floating island;
independently supplied sections may have different source phasors.

Autotransformers/regulators, static IBRs, control profiles, DC components
and other load laws are outside this initial scope. They are explicitly refused.
No topology or Kron reduction is run. User-supplied already-reduced data still
represent that user's input, not a recovered original network.

### Operating-bound coverage

The exact-IVR bound inventory is narrower than the shared SDP/SOC schema
inventory. The following expressions are enforced in the NLP and checked by
the independent SI auditor:

| Record | Bound fields | Physical quantity / indexing |
|---|---|---|
| Bus | `v_min`, `v_max` | Phase-ground magnitudes; phase-only or full-terminal arrays |
| Bus | `vpn_min`, `vpn_max`, `vpp_min`, `vpp_max`, `vn_max` | Phase-neutral, phase-pair and neutral-ground magnitudes |
| Bus | `vpos_min`, `vpos_max`, `vneg_max`, `vzero_max` | Three-phase sequence magnitudes of phase-neutral voltages |
| Line / linecode | `i_max`, `s_max` | Total endpoint current and phase-ground apparent power at **both** ends; array positions follow `terminal_map_from` at both ends; line fields override linecode fields |
| Fixed switch | `i_max`, `s_max` | Conductor current and terminal-ground apparent power at both ends, including neutral; zero ratings are supported |
| Generator | `p_min`, `p_max`, `q_min`, `q_max`, `s_max` | Connection-channel power, including delta **coil** power |
| Generator | `i_max` | Coil current, or terminal current when an explicit return-conductor entry is supplied; three-coil delta ratings use coil current |
| Voltage source | `p_min`, `p_max`, `q_min`, `q_max` | Per-phase or full-terminal power arrays |
| Voltage source | `s_max`, `i_max` | Phase apparent power; terminal current only when no source terminal is ideally grounded |
| Ordinary fixed transformer | `i_max_from`, `i_max_to` | Delta-side coil current; other-side terminal current |
| General multiwinding transformer | Winding `i_max`, `s_max` | Coil current and coil apparent power, including scalar broadcast |

Source Q/current/apparent bounds and switch/multiwinding `s_max` are dictionary
extensions to the pinned schema. Fixed tap bounds are checked against the
equipment setting before construction; they are not optimization variables.
`s_rating`, load `p_nom`/`q_nom`, nominal voltages and retained geometry ratings
do not imply extra operating caps under this contract.

`test/ivr_bound_coverage_tests.jl` holds feasible physical states fixed, tightens
individual bound entries, and requires both the actual NLP and the independent
auditor to reject them without a change in electrical residuals. It covers
single-phase, three-wire delta and four-wire wye networks, full and specialized
models, two power bases, signed reverse flow, both line ends with shunts,
linecode overrides, and the five supported transformer families. Existing
generator-update tests cover bound removal and fixed/free transitions; tap
alias tests cover fixed-setting bounds. This is a maintained regression
inventory, not proof of completeness for every possible input or future schema.
`test/ivr_switch_tests.jl` additionally covers fixed-switch ratings, endpoint
bindings, independent circuit witnesses, open islands, reversed terminal maps,
reverse flow, load reuse and transformer composition.

The remaining static AC element groups are autotransformers/regulators,
static IBRs, and constant-current/ZIP/exponential
load laws. Controls, tap optimization, DC and time-series semantics require
additional contracts. Each added group needs physical-state and negative-bound
tests before its scope gate is removed. Element support also does not establish
conductor-specialization eligibility.

A transformer anywhere in the input causes requested conductor-difference
specialization to fall back to full IVR with `:transformer_boundary`. The
existing line-only proof has not been extended across winding boundaries.
Switches similarly cause `:switch_boundary` fallback, including open switches.
If both are present, the transformer-boundary diagnostic takes precedence.
Capacitors participate in the existing downstream zero-sum connection check.
Delta, explicit-neutral wye and terminal-pair banks may retain eligibility;
a downstream phase-earth bank causes `:earth_return_device` fallback even
when its rating is zero. Root capacitor connections do not eliminate root KCL.
Capacitor regressions include full/reduced supplied states, nominal and
off-nominal rating checks, line limits with charging current, and OpenDSS banks.

Bus `v_declared`, `latitude` and `longitude` are retained descriptive annotations.
`v_declared` must be a positive finite scalar; it does not set source phasors,
model scaling or implicit voltage limits. Coordinates must be finite scalars
in their latitude/longitude ranges. Explicit voltage bounds remain authoritative.
A Boolean generator `_slack` is retained as a legacy label and listed in
`:legacy_slack_generators` when true. It does not remove the generator, change
its bounds/costs or suppress a colocated voltage source. Source and generator
injections remain distinct; the label does not repair unpriced-source accounting.
Unknown electrical fields and undeclared ground terminals remain errors.

Ideal grounded terminals omit KCL in the shared common-earth representation.
Their source-versus-earth current allocation is not observable here; source
ratings requiring that allocation are refused. The result uses a zero
placeholder for those source current entries, identified by
`:unobserved_grounded_source_currents` in its diagnostics. That placeholder is
not a measured or uniquely reconstructed source-neutral current.

## Verification and limits

Fixed-transformer tests include independently manufactured loaded states,
ideal ratios, reverse supply/flow, phase shifts, winding excitation, finite and
ideal neutral grounds, binding current ratings, multiwinding circuits and
fresh/reused demand sweeps. Single-phase, centre-tap, delta–wye and wye–delta
circuits are also compared against OpenDSS with controls disabled. Supplied
transformer coil currents are bound directly; ideal winding-ground currents
are derived from terminal/coil observations and checked without fitting.

An external-data coverage panel preserves electrical inputs and records
rejections as well as physical checks:

```sh
julia --project=test examples/check_ivr_transformer_datasets.jl /path/to/BMOPFDraftData /tmp/ivr-transformers.json
```

The script relocates known provenance into metadata on owned copies, recording
the paths and input hashes. Recognized bus annotations remain in place. It leaves unsupported
electrical fields and invalid ground labels as errors. Reported timings include
compilation and are not performance evidence. Demand totals distinguish unloaded
inputs from actual load sweeps; requested reduction falls back at transformers.

The default tests include independently manufactured two-wire and three-wire
delta states, supplied-point evaluation without optimizing, coupled four-wire
circuits, endpoint shunts, parallel branches, constant-impedance loads, binding
neutral limits, infeasible limits and repeated updates through zero/reverse
flow. Physical checks use the independent SI evaluator. A successful solve
status does not override a failing physical check.

## Certified conductor specialization

`IVRNLP(specialization=:conductor_difference)` attempts a conservative reduction;
`:off` remains the default. It accepts one complete radial section of two,
three or four conductors, with a single source and ideal or finite root grounding
where needed. Root voltage/current equations are retained in full; a finite root
ground is never replaced by an ideal one. Each line must carry the complete conductor
set, with consistent terminal/neutral continuity. Downstream device connection
rows must sum to zero. The initial pass declines nonzero line shunts and downstream bus shunts,
downstream grounds, multiple sources, incomplete conductor sections, and cycles,
including parallel edges. No tolerance treats a small shunt as zero. Supported
networks that fail certification use full IVR and report a stable reason code in
`build.numerical_diagnostics[:specialization_report]`.

The certificate uses downstream subtree KCL to establish zero-sum line current.
For the local difference matrix `P`, currents become `I = transpose(P)*j`.
Each downstream bus uses `P*V` and an explicit reference-conductor voltage,
which is the neutral for four-wire and phase-neutral two-wire cases. All
original voltage-drop equations remain. One implied complex KCL equation per
downstream bus is discharged; root KCL and device current coordinates are
retained. Delta leg circulation is not eliminated. Source-boundary devices can
exchange with earth because root KCL is retained.

This representation removes one complex line-current coordinate per branch.
The complete OPF does not receive a universal one-third or one-quarter variable
reduction: common-mode voltage coordinates remain explicit to keep physical
ground-dependent constraints local. Projection and reconstruction are sparse
local maps. Ordinary load updates reuse the maps and do not rerun detection.

`ivr_nlp_point_report(build, point)` evaluates every built constraint and the
objective at supplied physical phasors without optimizing or least-squares
repair. It reports missing channels and reconstruction/binding residuals;
projection is not accepted when it changes the supplied physical state. Its
`reconstructed_point` can be checked against full IVR and independently with
`physical_residuals`. Grounded source-current allocation remains explicitly
unobserved. Small manufactured and independently solved states exercise both
mapping directions, including binding neutral, phase-ground, delta-leg current
and line-end apparent-power constraints.

The synthetic ablation and read-only input census are separate scripts:

```sh
julia --project=test examples/benchmark_ivr_compiler.jl /tmp/ivr-benchmark.json
julia --project=test examples/census_ivr_compiler.jl /path/to/inputs /tmp/ivr-census.json
```

The census optionally accepts `--detach-provenance`: legacy `_pmd`,
`_merged_from` and `_simplification_log` fields move into the metadata envelope
on an in-memory copy. Their paths and original input hashes are recorded; no
canonical electrical field or source file is changed. The strict default reports
unrecognized legacy fields as baseline import errors.

The feeder panel runs matched full/reduced models with load reuse on selected
external files, preserves physical audit failures and checks each accepted
solution in the opposite formulation:

```sh
julia --project=test examples/benchmark_ivr_feeders.jl /path/to/inputs /tmp/ivr-feeders.json small.json medium.json large.json
```

This panel relocates the same known legacy provenance fields in memory and logs
source/generator accounting. An unpriced voltage source colocated with a priced
generator can produce artificial exchanges even when the solver succeeds.
The optional `--source-zero-power` scenario adds zero P/Q bounds to each source
and requires a colocated generator to supply the feeder. This changes the OPF;
it is explicitly recorded as an experimental scenario, not an equivalent input
conversion. All original generator and network limits and finite grounds remain.
Input files are never edited. Results record hashes, every changed field,
per-case warm-up, build/update/solve time, allocations, iterations, independent
SI residuals and supplied-point checks. No previous-solution warm start is used.

Two additional scripts cover a broader data inventory and generator reuse:

```sh
julia --project=test examples/census_ivr_datasets.jl /path/to/BMOPFDraftData /tmp/ivr-datasets.json
julia --project=test examples/benchmark_ivr_dispatch.jl /path/to/feeder.json /tmp/ivr-dispatch.json --source-zero-power --hundred
```

The dataset census distinguishes network inputs from solver-result objects and
samples the smallest, median-ranked and largest input per directory. It records
unsupported components, invalid input and reduction fallback separately; it does
not establish solvability. Related original/reduced variants are not independent
feeders. An optional third argument limits the bus count for assembly and
initialization, for example `10000`; larger inputs are explicitly `not_assessed`
with `size_limit`, never marked supported or failed. The default has no size
limit. Completed samples are checkpointed, and the report's `complete` flag
distinguishes a finished census from an interrupted pass. Assembly/start times
are diagnostic and include compilation.

The dispatch experiment crosses full/reduced with fresh/reused construction at
N=1 and 10; `--hundred` also runs N=100. A ten-step cycle changes nonroot generator
active-power bounds and prices, including fixed-zero active power; existing Q
bounds and equipment limits remain. Thus zero active availability does not switch
off reactive capability. Every parameter scenario is recorded. Fresh models are
built from independently edited data, while reused models use
`update_ivr_generators!`. Physical audits, cross-formulation supplied-point checks
and objective checks are outside the workflow timer. Failed batches stop early
and must not be compared as completed timing runs. The `--source-zero-power`
flag changes supply accounting as described above; it is never applied implicitly.

The ablation compares full/reduced and fresh/reused construction at mapped
physical starts. It reports failures and physical checks as well as timings.
It does not establish performance on arbitrary networks. Mixed conductor-count
sections, pendant-region specialization, full common-mode substitution, general
family persistence and equipment/source updates remain future work.

Preparation can be profiled separately with a local external input:

```sh
julia --project=test examples/profile_ivr_build.jl /path/to/feeder.json /tmp/ivr-build.json
```

This reports warmed build times, allocations and sampling profiles. Circuit
assembly reuses decoded linecode matrices and neutral-role discovery within each
build; line lengths and per-unit scaling remain branch-specific. These caches
are not shared across builds or retained for equipment updates.

The optional BMOPFTools comparison runs separately:

```sh
julia --project=test/integration test/integration/ivr_nlp_reference.jl /tmp/ivr-reference.json
```

It compares small circuits without controllable dispatch, including supplied
BMOPFTools states in the reduced model and reconstructed reduced states in full
IVR; it is differential
verification, not field validation or a performance benchmark.
