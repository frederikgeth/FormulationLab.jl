# Exact IVR

`IVRNLP` is an experimental exact static AC formulation. It retains conductor
voltages and component currents and uses the exact products `S = U*conj(I)`.
It applies no approximate network reduction. Optional conductor-difference
specialization preserves the supported full-IVR problem.
`formulation_kind(IVRNLP()) == :exact` describes these equations; Ipopt normally
returns a local solution, not a global optimality certificate.

Read the [equations and equivalence domain](ivr_theory.md) for the mathematical
model, [motivating examples](ivr_examples.md) for study design, and the
[executable tutorial](tutorial_exact_ivr.md) for an end-to-end workflow. This page
is the detailed scope, bound and update contract; it does not assert full BMOPF
coverage.

## Usage and repeated operating points

```julia
using FormulationLab, Ipopt

build = build_opf(input, IVRNLP(objective=:source_import);
                  optimizer=Ipopt.Optimizer)
result = solve_ivr_nlp_opf(build; solver_options=(print_level=0,))
@assert result.solve.optimal
audit = physical_residuals(build.network, result)
@assert audit.passed

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

### Options and returned data

| Option | Default | Meaning |
|:--|:--|:--|
| `s_base` | `1e4` | Positive finite internal power base in VA; SI inputs/results unchanged |
| `objective` | `:cost` | `:cost`, `:source_import` or `:feasibility` |
| `specialization` | `:off` | `:conductor_difference` certifies one complete section; `:conductor_regions` certifies pendant regions behind retained boundaries |

`IVRNLPResult.voltage_candidate` maps `(bus, terminal)` to complex volts;
`current_candidate` and `powers` map `(family::Symbol, id::String)` to channel
vectors in A and VA. See the component paragraphs below for coil/terminal
conventions. `objective` is W in source-import mode, currency/h in cost mode,
and zero in feasibility mode. A snapshot objective has no time integration.
`solve` records solver status; `numerical_diagnostics` records bases,
specialization/fallback, assembly/update counts and unobserved grounded-source
current entries. If strict solver acceptance fails, candidate maps are empty
and the objective is `NaN`. An accepted local result still needs independent
physical assessment. See [the API reference](api.md).

## Supported scope

The initial implementation supports mutually coupled lines, endpoint shunts,
ideal bus grounds, finite grounding admittances, fixed source phasors,
constant-power/impedance and voltage-dependent current/ZIP/exponential loads,
and generator P/Q boxes. Wye,
delta and single-phase connection maps are retained. Physical limits include
conductor current, apparent power, phase-ground, phase-neutral, phase-phase,
neutral and supported sequence-voltage magnitudes. Lower voltage magnitudes
are exact nonconvex inequalities. Delta-generator dispatch and ratings use coil
semantics; THREE_LEG IBR port limits use conductor quantities as described below.
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

Static IBRs support `SINGLE_PHASE`, explicit-neutral `FOUR_LEG`, and three-phase
`THREE_LEG`. `s_max` is a required nonnegative phase vector. P/Q boxes, total PCC
`p_avail`, conductor/return `i_max`, and linear phase prices remain active.
Missing P/Q bounds do not introduce implicit prime-mover restrictions; `prime_mover`
is descriptive. A phase-only FOUR_LEG current vector leaves its neutral unrated;
include the return entry to constrain it. THREE_LEG P/Q, apparent power, current
and prices use **PCC conductor** quantities, unlike delta-generator coil dispatch.

The internal circuit retains the shared winding-filter convention: THREE_LEG
uses delta coils, FOUR_LEG uses phase-neutral coils, and SINGLE_PHASE uses its
terminal pair (or earth return). In SI units, `Jf = Icoil + im*B*Ucoil` and
`E = Ucoil + Z*Jf`. Filter parameters and `v_ref_internal` refer to those coil
channels. `:ibr` exposes PCC port currents/powers; `:ibr_internal` exposes filter
coil currents and internal powers. `dc_link_coupled=true` applies scalar
`p_dc_min/max` to the **sum of internal active powers**, including copper loss.
It does not create a DC network. `grid_forming=true` fixes each internal coil
voltage magnitude to positive `v_ref_internal`; it is a static algebraic setpoint,
not droop, a dynamic controller or an island voltage-angle reference.

Control-profile references, voltage aggregation, external DC ports and controls
are explicitly refused. Inverter equipment, capability and price changes require
a fresh build; the generator update API does not update IBRs. Load reuse retains
the IBR equations and bounds. Use `physical_residuals(net, result)` for exact-IVR
results; for a supplied `ACPoint`, specify both `delta_dispatch=:coil` and
`ibr_delta_dispatch=:conductor`. The latter defaults to `delta_dispatch` for
backward compatibility with older formulation callers. Diagnostics expose both
conventions. This is the declared native static contract, not complete schema
or control-model coverage.

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

### Voltage-dependent load laws

Loads use physical connection coils: one terminal pair for SINGLE_PHASE,
phase-neutral (or implicit-earth) coils for WYE, and ordered phase-pair coils
for DELTA. Native `v_nom` is the nominal voltage **across that coil**. In
particular, a 230 V phase-neutral wye uses 230 V per coil, while a corresponding
delta uses approximately 398.37 V. The inspected PowerIO schema's prose calls
three-phase nominal values line-to-line; accepting a native dictionary does
not resolve that different input convention or automatically convert it.

Besides constant power and impedance, `constant_current`, `zip` and
`exponential` implement the exact [power functions](ivr_theory.md#Voltage-dependent-demand).
P/Q nominal powers are finite per-coil vectors; signed values are allowed.
Positive finite `v_nom`, ZIP coefficients and exponents accept either a scalar
broadcast or a full channel vector. Length-one vectors do not broadcast to
multiple channels. All six ZIP fractions are required, nonnegative and sum to
one separately for P and Q in each channel (absolute tolerance `1e-10`). Both
finite `gamma_p` and `gamma_q` are required for exponential loads; fractional,
zero and negative exponents are supported. Coefficients belonging to a different
law are refused. Nominal powers and fractions introduce no operating cap.

Every non-impedance voltage-dependent coil requires a **strictly positive
engineering lower voltage bound on that exact voltage map**, or a fixed
nonzero voltage derived directly from source phasors. `vpn_min` can certify a
wye coil and `vpp_min` a delta coil; separate phase-ground bounds generally
cannot certify either difference voltage. Ground elimination, polarity and
terminal-map permutations are respected. No nominal-voltage floor, epsilon,
current cutoff or extrapolation at zero is introduced. The detector is
conservative: it does not propagate lower bounds through lines or transformers.
An absent certificate causes an explicit refusal, even for zero demand or an
exponential exponent of zero. Pure-Z ZIP and all-exponent-two loads instead
use the exact linear impedance current law and need no positive-domain
certificate; at zero coil voltage that law enforces zero coil current.

For a nonfixed coil the NLP adds one normalized squared-voltage variable,
bounded by the matched engineering bounds, and equates it to the physical
squared magnitude. Coils with fixed source voltages or equal matched magnitude bounds evaluate
the power function directly, avoiding a redundant fixed auxiliary.
`:load_voltage_variable_count` reports the added variables.
`ivr_nlp_point_report` derives their values from the supplied physical voltages;
it cannot choose them to repair a mismatch. Fractional powers are evaluated
only on the positive domain. A supplied zero-voltage state rejects safely.

`update_ivr_loads!` remains restricted to declared constant-power loads. Changes
to voltage-law nominal demands, fractions or exponents require a fresh build;
a mixed invalid update is rejected before its valid constant-power entries are
changed. A constant-power load in the same network can still be reused while
all voltage-law equations remain fixed. These laws do not change the connection
identities used by conductor specialization, and their auxiliary variables and
all physical operating bounds are retained in both representations.

The OpenDSS reference tests use models 5 (current), 8 (ZIPV) and 4 (CVR powers),
with the same coil nominal voltages and a shared operating range. They set ZIP
cutoff to zero and stay inside the declared DSS voltage thresholds, because
OpenDSS uses different laws outside them. See the
[Load reference](https://dss-extensions.org/dss-format/Load.html) and
[CVR implementation](https://github.com/dss-extensions/dss_capi/blob/master/src/PCElements/Load.pas).
No equivalence with those out-of-range substitutions is claimed.

### Fixed regulators and conductive bonds

`single_phase_autotransformer` and `open_delta_regulator` use the same fixed
winding equations. Define the ideal coil voltage gain by
`E_to = g * E_from`: type A has `g = 1/tap_ratio`, type B has
`g = tap_ratio`. Leakage and excitation remain explicit; this gain is not a
loaded terminal-voltage identity. The default is type B and unity tap.
The [winding reference](sdp_transformers.md) specifies coil polarity and the
`ABBC`, `BCAC` and `CABA` open-delta connections. The single-phase common
conductor need not be a neutral. A one-terminal map uses implicit earth;
matching two-terminal maps retain an explicit common-conductor bond.

Exact-IVR results expose `(:transformer_bond, "subtype/id")` current channels,
positive from the from-side bus to the to-side bus. Their order is the common
conductor for a single-phase unit, or shared phase followed by optional neutral
for open delta. A one-terminal single-phase unit has no explicit bond channel.
Bond power uses its **voltage drop**, which is zero at a feasible point; it is
not a port-transfer-power observation. Side powers use total terminal currents.
`i_max_from` and `i_max_to` constrain every rated terminal, including the bond
and any internal neutral-ground contribution. `s_rating` adds no thermal cap.

Optional `r_neutral_from/to` and `x_neutral_from/to` are native dictionary
extensions for these regulator types. An ideal internal ground and a conductive
bond can have nonunique individual currents. `ivr_nlp_point_report` requires the
explicit bond observation before deriving the ground current from terminal
observations. It does not fit an allocation. The independent physical auditor
also accepts older points without bond channels, but checks only relations
identifiable from their terminal and coil observations. This does not establish
a unique ground/bond allocation. Controls, optimized taps and equipment updates
remain outside this fixed-setting contract.

`test/ivr_regulator_tests.jl` covers independently manufactured states, both
types, all connections, finite/ideal earth paths, reverse flow, current-channel
perturbations and individual side-current bound violations. The OpenDSS suite
compares eight equivalent fixed circuits with explicit shared nodes. It tests
circuit equivalence under the stated parameter conversion, not controller
behavior or a universal manufacturer interpretation of type A/B labels.

Supported objectives are `:cost` (linear currency/kWh coefficients),
`:source_import` (watts), and `:feasibility`. Inputs and outputs use SI units;
`s_base` controls internal scaling. Inputs are copied rather than modified.
Without transformers, switches, capacitors or IBRs, each voltage conductor must have a line path to a fixed source, ideal ground,
or finite one-terminal ground. A finite ground supplies only an initial voltage
guess in conductor components unreached by the fixed-source/ideal-ground
traversal; source-propagated phase starts take precedence. Its voltage is not fixed and its actual admittance/KCL remain enforced.
With transformers, switches, capacitors or IBRs, a sparse linear circuit solve provides starts using every
fixed source phasor. Non-impedance load, generator and IBR PCC currents are zero only
in this initialization; impedance loads, capacitors, excitation, grounds and closed switches remain active.
It requires unique no-load conductor voltages and rejects inconsistent circuits
or floating sections, including an unreferenced delta secondary. No artificial
ground or voltage gauge is inserted. Current-only freedom is allowed in the
initial solve and retained in the nonlinear model. Diagnostics distinguish
`:linear_circuit` and `:line_propagation` initialization.
An open switch cannot provide a voltage reference to a floating island;
independently supplied sections may have different source phasors.

Control profiles, DC components and load laws outside the five declared
models are explicitly refused.
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
| IBR PCC | `p_min`, `p_max`, `q_min`, `q_max`, `s_max`, `i_max`, `p_avail` | Phase-port power/current and total active availability; THREE_LEG uses conductor ports; optional FOUR_LEG neutral current entry |
| IBR internal | `p_dc_min`, `p_dc_max`, `v_ref_internal` | Coupled total internal active power including filter loss; fixed internal coil voltage magnitude when enabled |
| Voltage source | `p_min`, `p_max`, `q_min`, `q_max` | Per-phase or full-terminal power arrays |
| Voltage source | `s_max`, `i_max` | Phase apparent power; terminal current only when no source terminal is ideally grounded |
| Ordinary fixed transformer | `i_max_from`, `i_max_to` | Delta-side coil current; other-side terminal current |
| Fixed autotransformer / open-delta regulator | `i_max_from`, `i_max_to` | Total terminal current, including conductive-bond and internal grounding contributions |
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
linecode overrides, and the five isolated-winding transformer families. Existing
generator-update tests cover bound removal and fixed/free transitions; tap
alias tests cover fixed-setting bounds. This is a maintained regression
inventory, not proof of completeness for every possible input or future schema.
`test/ivr_switch_tests.jl` additionally covers fixed-switch ratings, endpoint
bindings, independent circuit witnesses, open islands, reversed terminal maps,
reverse flow, load reuse and transformer composition.

All five declared load laws and seven fixed transformer families now have
exact-IVR implementations within their stated domains. This is not full schema
or operating-mode coverage: controls, tap optimization, DC and time-series
semantics require additional contracts. Element support also does not establish
conductor-specialization eligibility.

For `:conductor_difference`, a transformer anywhere in the input causes
specialization to fall back to full IVR with `:transformer_boundary`. The
existing line-only proof has not been extended across winding boundaries.
Switches similarly cause `:switch_boundary` fallback, including open switches.
If both are present, the transformer-boundary diagnostic takes precedence.
The separate `:conductor_regions` option can specialize eligible line trees
attached to their buses while retaining the entire transformer/switch circuit
and all boundary-bus equations. It does not reduce through either device.
Capacitors participate in the existing downstream zero-sum connection check.
Delta, explicit-neutral wye and terminal-pair banks may retain eligibility;
a downstream phase-earth bank causes `:earth_return_device` fallback even
when its rating is zero. Root capacitor connections do not eliminate root KCL. In regional mode, an
earth-return device makes its bus a retained boundary; other pendant regions
can still qualify.
Capacitor regressions include full/reduced supplied states, nominal and
off-nominal rating checks, line limits with charging current, and OpenDSS banks.
IBRs also participate in the zero-sum connection proof; implicit earth-return
devices cause fallback. IBR tests hold supplied states fixed while violating
every supported limit, including internal voltage and shared-link budgets,
and cover signed dispatch, filters, neutral ratings and full/reduced forms.

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

### Pendant regions inside a larger network

`IVRNLP(specialization=:conductor_regions)` is a separate opt-in mode. It can
certify several disjoint interiors, including two-, three- and four-conductor
regions sharing a retained boundary bus. A boundary port may use only a subset
of that bus's conductors. Inside each region, every line carries the complete
consistent conductor set and has exactly zero endpoint shunts; every device
connection has a structural zero-sum terminal-current identity.

The detector repeatedly removes eligible leaf buses from an undirected
multigraph. Sources, ideal grounds, nonzero bus shunts, transformer ports,
switch ports, earth-return devices, partial conductor ports and invalid
conductor-role transitions stop removal at their buses. Nonzero shunted lines
are retained and stop removal at both endpoints. Parallel edges and cycles
remain in the graph core, but pendant trees attached to them may qualify.
No tolerance turns a small admittance or zero-demand earth-return connection
into an eligible identity. Every removed bus has exactly one remaining parent
edge when certified. Each resulting tree ends at a retained boundary bus.

The entire boundary bus stays in physical coordinates, with every original KCL,
voltage equation, device and operating limit. Its voltage need not be fixed, and
its upstream current need not sum to zero. Transformers and switches are never
transformed; their connected buses can anchor independent regions. The method
also admits multiple sources outside the interiors and mixed conductor counts
at retained ports. It does not certify through a mixed-port bus or a cycle.

A successful report has `code=:pendant_zero_sum`; `regions` records each root,
rule, boundary terminal subset, interior buses, selected lines and omitted KCL.
`components` lists all selected lines, while `retained_lines`, `retained_buses`,
`boundary_buses` and `barriers` expose what stays physical. Barriers identify
explicit stopping conditions; unpeeled cycle/core buses can remain without an
explicit device barrier. With no eligible tree, `code=:no_certified_regions`
returns the full model. Detection depends on topology and connections, not a
solved point or today's demand. Supported demand/price updates reuse the maps.

The [theory chapter](ivr_theory.md#Pendant-region-certificate) gives the subtree
argument with a free boundary. `test/compiler_region_tests.jl` checks independent
nonzero-sum boundary witnesses, mixed ports, cycles and parallel edges, multiple
sources, all fixed transformer families, switches, voltage-dependent loads,
capacitors, generators and static IBRs. Negative tests hold supplied points
fixed while violating boundary/interior voltages, sequence limits, both line-end
ratings and delta-generator limits. A region removes one complex line-current
coordinate and one implied complex KCL equation per interior bus.

### Coordinate emission and physical-point checks

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
It does not establish performance on arbitrary networks. Transformation through mixed conductor-count
junctions or device boundaries, full common-mode substitution, general family
persistence and equipment/source updates remain future work. Regional mode
retains such junctions and device ports rather than transforming through them.

Preparation can be profiled separately with a local external input:

```sh
julia --project=test examples/profile_ivr_build.jl /path/to/feeder.json /tmp/ivr-build.json
```

This reports warmed build times, allocations and sampling profiles. Circuit
assembly reuses decoded linecode matrices and neutral-role discovery within each
assembly, including winding and capacitor stamps. Standalone device plans and
reconstruction calls discover roles locally when needed. Line lengths and
per-unit scaling remain branch-specific. These caches
are not shared across builds or retained for equipment updates.

Sparse circuit rows are accumulated into fresh complex JuMP affine expressions,
avoiding a separately allocated scaled expression for each term. The input rows
and coordinate expressions remain unchanged; numeric physical reconstruction
keeps its scalar evaluator. This preparation optimization applies to full and
specialized models and introduces no new reduction or operating-domain rule.

### Matched regional experiments

Use the regional runner to distinguish variable reduction from measured cost:

```sh
julia --project=test examples/benchmark_ivr_regions.jl \
  /path/to/dataset /tmp/ivr-regions.json \
  relative/path/to/feeder.json --profiles
```

The CLI explicitly minimizes source import and retains all electrical input
data. It relocates only known provenance on owned copies. It excludes one
warm-up pair per case and measures six pairs in balanced alternating order,
using fresh builds and unloaded starts. Each accepted pair must satisfy strict
solver acceptance, independent physical checks, both model mappings and
objective agreement. Failed warm-ups are recorded and not repeatedly timed;
later failures remain in the raw trials and counts. Summaries describe accepted
pairs only, so inspect the entire output before drawing comparisons.

The output records per-trial build/solve-and-extraction time, Julia allocated
bytes and GC time; variable/constraint counts; iterations; backend Jacobian and
Hessian structures; input hashes, versions and source-accounting diagnostics.
Ratios are calculated within pairs. Minima, quartiles, medians and maxima describe
this sample, not a confidence interval or population estimate. Validation and
derivative queries are outside the timers. Allocation counts omit native solver
and peak resident memory. Derivative structures precede solver preprocessing;
they do not measure KKT fill. Separate build-stage measurements and optional
sampling profiles are diagnostics and must not be added to public build times.

For a separate feasibility experiment, include the script and call
`benchmark_ivr_regions(directory, output, files; objective=:feasibility)` with
a different output file. A zero objective can distinguish physical feasibility
from an unbounded or difficult supply-accounting objective; it does not repair
or validate the original optimization result. See the [dated comparison](verification.md).

The optional BMOPFTools comparison runs separately:

```sh
julia --project=test/integration test/integration/ivr_nlp_reference.jl /tmp/ivr-reference.json
```

It compares small circuits without controllable dispatch, including supplied
BMOPFTools states in the reduced model and reconstructed reduced states in full
IVR; it is differential
verification, not field validation or a performance benchmark.
