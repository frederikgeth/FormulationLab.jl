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
| `objective` | `:cost` | `:cost`, `:source_import`, `:feasibility` or `:power` |
| `power_terms` | Empty | Explicit `IVRPowerTerm` vector for `:power`; physical W/var targets and coefficients |
| `specialization` | `:off` | `:conductor_difference` certifies one complete section; `:conductor_regions` certifies pendant regions behind retained boundaries |
| `linear_elimination` | `:off` | `:impedance_loads` substitutes impedance-load currents; `:passive` additionally eliminates nonadjacent eligible degree-two buses; `:passive_chains` permits adjacent candidates; `:passive_blocks` also admits charged π sections through conditioned local block solves; `:passive_hybrid` caps connected groups of eliminated buses |
| `passive_component_limit` | `4` | Positive maximum number of original buses per eliminated connected component in `:passive_hybrid`; ignored by other modes |
| `series_selection` | `:all` | With any passive policy, `:bound_support` rejects a candidate when an affected operating bound gains solver-coordinate dependencies |
| `transformer_scaling` | `:off` | `:nominal` composes local voltage/current units from ordinary transformer ratios; `:nominal_multiwinding` additionally uses declared coil-voltage conventions; uncertain assignments retain global units |
| `row_scaling` | `:legacy` | `:composed` normalizes linear circuit rows after all coordinate transformations, independently of local voltage/current scaling |
| `kcl_row_max_base` | `nothing` | Optional positive ampere cap on the numerical unit of each retained KCL row; preserves existing smaller row units and every physical bound |
| `ground_scaling` | `:off` | `:voltage` uses global-base shunt multipliers; `:regional_voltage` uses ordinary regional units; `:regional_multiwinding_voltage` also crosses multiwinding transitions; all preserve finite grounds |
| `objective_scale` | `nothing` | Divide the physical objective by this positive scalar; `nothing` preserves division by `s_base` |
| `current_power_bases` | empty dictionary | Explicit bus-to-VA seeds for regional current coordinates; requires `transformer_scaling=:nominal` or `:nominal_multiwinding` |
| `generator_power_bases` | empty dictionary | Generator-ID-to-VA dispatch units for both P and Q; unspecified generators use `s_base` |
| `lifted_power_base` | `nothing` | VA unit for power auxiliaries; defaults to `s_base`, without enabling lifting |
| `power_sharing` | `:off` | `:generators` reuses exactly matching generator P/Q definitions when lifting is enabled |
| `observation_selection` | `:all` | With bounded-observation lifting, restrict to `:coil_voltages`, `:coil_currents` or `:coils`; original bounds remain enforced |
| `observation_support_threshold` | `2` | Lift affine observations only when their distinct real-variable support is strictly larger; nonnegative integer |
| `observation_sharing` | `:off` | `:exact` shares identical composed affine observations; `:signed` also shares opposite rows; `:proportional` admits certified real multiples, including constants |
| `coincident_voltage_bounds` | `:separate` | `:equality` replaces exactly coincident positive bus-voltage bounds by one magnitude equality; explicitly fixed source rows retain their original representation. `:guarded_equality` additionally shares identical normalized affine observations and retains inequalities on structurally circuit-fixed voltages; see [scope and evidence](ivr_voltage_dependencies.md) |
| `lifting` | `:off` | `:powers` adds exact P/Q definitions at apparent-power limits; `:bounded_observations` additionally materializes compound bounded voltage/current expressions |
| `device_elimination` | `:off` | `:transformer_currents` removes ordinary from-side coil currents; `:all_transformer_currents` also attempts complete multiwinding current blocks, retaining unsafe blocks. See [scope and solver qualifications](ivr_nwinding_elimination.md) |
| `zero_load_elimination` | `false` | Remove exactly zero-P/Q load-coil currents only on a certified nonzero voltage domain; retain original bounds and SI observations. Nonzero demand updates require rebuilding. See [equivalence, recovery and reuse](ivr_zero_loads.md) |

The [coincident-voltage study](ivr_voltage_equalities.md) gives the equality
rewrite, its scope and retained numerical controls. It matches the same bus,
voltage family, channel and electrical row. It neither rounds nearly equal
bounds nor merges different voltage declarations that happen to be equivalent
after grounding. Zero limits retain their existing component equalities.
Diagnostics and SI export metadata record the policy and every matched pair.

`IVRNLPResult.voltage_candidate` maps `(bus, terminal)` to complex volts;
`current_candidate` and `powers` map `(family::Symbol, id::String)` to channel
vectors in A and VA. See the component paragraphs below for coil/terminal
conventions. `objective` is W in source-import mode, currency/h in cost mode,
zero in feasibility mode, and user-defined units for explicit power terms.
See [power objectives](ivr_objectives.md) for quadratic costs, P/Q tracking,
curtailment, aggregate exchange and loss accounting. A snapshot objective has no time integration.
`solve` records solver status; `numerical_diagnostics` records bases,
specialization/fallback, assembly/update counts and unobserved grounded-source
current entries. If strict solver acceptance fails, candidate maps are empty
and the objective is `NaN`. An accepted local result still needs independent
physical assessment. See [the API reference](api.md).

## Supported scope

### Local linear elimination

`linear_elimination` is independent of `specialization`; the two coordinate
passes compose. Both are opt-in. The original network snapshot, electrical
rows and physical observation channels remain available. The solver variables
and defining equalities are reduced; no network preparation or topology merge
is applied. Use `:linear_elimination_report` in `numerical_diagnostics` to inspect
`impedance_loads`, `series_buses`, `selected_series_lines`, `retained_series_buses` and
`eliminated_complex_coordinates`.

`:impedance_loads` substitutes each exact law `I = Y*U`, including constant
impedance, pure-Z ZIP and exponent-two load models. It removes one complex
current coordinate and its defining complex equality per coil. It preserves
zero and signed admittances without division by admittance. Other load laws,
generator currents and inverter circulation freedoms are not eliminated.

`:passive` performs the same load substitution, then considers degree-two buses
with no attached source, load, generator, inverter, switch, transformer,
capacitor or shunt and no ideal ground. Both incident lines must have exactly
zero end-shunt matrices, cover every bus terminal and lead to distinct other
buses. Self-loops and parallel pairs are retained. Nonadjacent eligible buses
are selected deterministically in sorted bus order; neighbours of a selected
bus are retained for this pass. This keeps reconstruction local, rather than
substituting along arbitrarily long chains. The rule also applies inside meshes.
It uses unit-coefficient KCL/KVL pivots, not impedance inversion or a numerical
rank/PSD threshold; zero series impedance is allowed. It does not certify
positive dissipation or improve the existing line-passivity classification.

`:passive_chains` keeps the same structural requirements but permits adjacent
candidates. At each bus, it tries incident lines in sorted ID order whose defining
rows have not already been omitted. It resolves every row through prior
substitutions, requires a complete set of exact unit pivots, and rolls back an
incomplete or support-rejected attempt before trying the next line. The report's
`selected_series_lines` maps each eliminated bus to its consumed line. Retention
reasons include `no_surviving_line_equations` and `no_local_unit_pivot`.
This greedy single pass is not a maximal chain-reduction algorithm: ordering can
leave a bus when both original incident equations have been consumed, even if
a more global elimination could remove it. It also applies to eligible local
sections inside meshes; it does not remove a cycle by assuming radial KCL.

Every original removed-bus voltage limit and segment current/apparent-power
limit is still evaluated on its reconstructed physical expression. Transformer,
switch, generator and IBR observations/bounds are unchanged. A supplied physical
point must include the eliminated observations: `ivr_nlp_point_report` rejects
any reconstruction mismatch instead of fitting a replacement point. Pure-Z
equipment/nominal-demand changes still require rebuilding; the supported CP
load and generator updates reuse the existing maps. Initial eliminated currents
are determined by their defining laws, so the reduced starting point need not
equal the full model's independently assigned current starts.

The name `:passive` identifies this device-free series policy, not the separate
approximate compatibility reduction pipeline. Charged π sections remain outside
the unit-pivot policies; junctions above degree two and device-boundary
elimination remain outside all current passive policies. Adjacent elimination is opt-in
through `:passive_chains`; the original `:passive` policy is unchanged. The [theory](ivr_theory.md)
states the equivalence argument; [verification](verification.md) records the
tests and performance limitations.

### Charged π-section block elimination

`linear_elimination=:passive_blocks` retains the chain pass's topology, terminal
and device-boundary checks but admits nonzero line-end shunts. At each candidate,
it forms a square linear block from surviving KCL and one incident line's KVL,
targeting that line's current coordinates and the candidate bus's voltages.
It substitutes the block solution only if the target set is complete, the
row-equilibrated 2-norm condition estimate is at most `1e8`, all coefficients are
finite, and the normalized linear-solve residual is at most `1e-12`.
No series-impedance inverse, pseudoinverse, regularization or coefficient cutoff
is used. Singular/ill-conditioned attempts retain their original equations.

`linear_elimination_report.block_diagnostics` records each accepted block's
dimension, condition estimate and residual. These are numerical acceptance
checks, not a rigorous floating-point error certificate. Every physical
observation, charging contribution, endpoint rating and interior voltage limit
is reconstructed. `series_selection=:bound_support` checks all original bounds
after each tentative composition and rolls back a rejected block completely.
Earth-connected charging can prevent conductor specialization even when local
block elimination remains eligible; the two policies have separate certificates.

### Bounded hybrid condensation

`linear_elimination=:passive_hybrid, passive_component_limit=K` uses the same
local block certificate and original-bound reconstruction as `:passive_blocks`.
It additionally retains a candidate if adding it would make a connected component
of eliminated **original buses** contain more than `K` members. The cap is a
positive integer (default four); other modes ignore it. Buses and incident line
candidates retain the existing sorted traversal. This deterministic greedy policy
is not invariant to renaming bus IDs and does not maximize the number eliminated.

Component membership commits only after the numerical block and optional
`series_selection=:bound_support` checks accept. Rejected attempts leave the
original equations and component bookkeeping unchanged. Source/device and
perfect-ground boundaries, terminal compatibility and degree-two restrictions
remain. A cap of one still admits charged local blocks, unlike `:passive`.
A sufficiently large cap reproduces unrestricted block maps.

For this mode the elimination report adds `component_limit`, sorted
`eliminated_components`, `max_component_buses`, and `component_limit_rejections`
(mapping a rejected bus to its proposed component size at the time of the attempt).
Such retained candidates have reason `eliminated_component_limit`. In other modes
`component_limit` is `nothing` and these component records are empty, not a claim
that unrestricted elimination has zero-sized components. The cap bounds graph
cardinality, not reconstruction support, matrix fill or runtime. See the
[hybrid study](ivr_hybrid.md) for the proof, controls and measured limitations.

### Exact transformer coil-current substitution

`device_elimination=:transformer_currents` applies after line elimination and
before finite-ground scaling. The supported fixed two-sided transformer and
regulator stamps impose ``j_f+R^Hj_t=0``. A surviving unit pivot substitutes
``j_f=-R^Hj_t``; the pass does not invert leakage, terminal incidence or the
possibly rectangular ratio matrix. Zero leakage and center-tap connections
therefore require no special regularization. Voltage-coupling equations, to-side
coil currents, bonds and grounding reactions remain. Delta circulation is not
inferred from terminal currents or fixed to zero.

The pass is atomic per transformer. Missing/consumed balance equations,
nonunit pivots or nonfinite substitutions retain that device with a diagnostic
reason. In this mode `n_winding` remains explicit. The additional
[`device_elimination=:all_transformer_currents` option](ivr_nwinding_elimination.md)
uses a square local solve for recorded multiwinding coil-current blocks, with
condition, residual and reconstruction-gain gates and atomic fallback.
Inspect `numerical_diagnostics[:device_elimination_report]` for
selected/retained transformer IDs, removed equation indices and complex-coordinate
counts. All original terminal/coil limits, powers and JSON observations are
evaluated through the composed reconstruction. `series_selection=:bound_support`
still selects line eliminations only; it does not reject device substitutions
whose bound expressions grow. This option is independent of all line modes,
conductor specialization, lifting and supported load/generator updates.

### Transformer-local coordinates and composed-row normalization

`transformer_scaling=:nominal` propagates voltage levels from nonzero source
magnitudes through lines, closed switches and fixed-transformer nominal ratios.
The common power base stays fixed. For a local voltage base `Vr`, solver voltage
coordinates are multiplied by `Vb/Vr` and current coordinates by `Vr/Vb`, relative
to the original global per-unit coordinates. The resulting physical voltage and
current bases are `Vr` and `s_base/Vr`. Taps, incidence matrices and leakage remain
in the original physical equations; they are not absorbed into a different circuit.

Ordinary single-phase, center-tap, delta-wye and wye-delta nominal ratios are
supported. Fixed regulators connect the same nominal voltage level; tap deviations
remain explicit. Open switches do not propagate a base. The existing `:nominal` policy skips multiwinding transformers. The opt-in
`:nominal_multiwinding` policy extends propagation using WYE/SINGLE_PHASE coil
nominals and DELTA coil nominals divided by √3. This chooses characteristic
units without imposing a physical neutral or ground voltage; see
[the contract and tutorial](ivr_nwinding_coordinates.md). Components with inconsistent
nominal cycles or source-base assignments, or without a nonzero source seed, keep
the global base with a recorded reason. This is a units-selection fallback, not
a conclusion that the physical network is infeasible. Nominal cycle/source
consistency uses a relative 1e-10 comparison; no physical coefficient is discarded.

The pass follows conductor, line/device elimination and finite-ground maps.
A retained projection coordinate is rescaled only when every original coordinate
in its support has the same uniquely assigned factor. Mixed or unclassified
coordinates retain their previous scale. Overflow/underflow in the coefficient
maps rejects the entire new coordinate intervention. Fixed-source values, supplied
points and physical recovery all use the composed map. P/Q dispatch units,
objective scaling, original bounds and load/generator update semantics are unchanged.

`row_scaling=:composed` independently normalizes linear circuit equations using
their coefficient norms in final solver coordinates. `:legacy` preserves the old
rule: use original norms unless finite-ground scaling actually changed a coordinate.
It does not normalize nonlinear rows by their start-point gradients. Nonfinite
circuit-row norms are refused rather than turning equations into zero rows.
Diagnostics report `transformer_scaling_report` (bus bases, scaled and retained
coordinates, and fallback reasons), `row_scaling`, `composed_row_normalization`
and `per_unit_bases`. Separate Ipopt scaling options are controlled by the caller.

`kcl_row_max_base` optionally limits the ampere unit of retained KCL rows by
capping their divisor at `kcl_row_max_base / current_A`. The default `nothing`
preserves existing behavior. The cap is a numerical equality multiplier, not
an operating current bound. It leaves non-KCL equations and coordinate maps
unchanged and cannot independently control omitted KCL rows. Diagnostics record
the chosen cap. See the [residual trace and validation](ivr_kcl_residuals.md)
for the connection between normalized solver errors and SI accuracy.

### Electrical power bases and objective normalization

`s_base` remains the assembly power base: it determines global current and
impedance units, P/Q variables, load equations and bound normalizations. It is
not a physical equipment rating. `objective_scale=nothing` preserves the legacy
objective divisor `s_base`. A positive explicit `objective_scale` holds that
divisor fixed while electrical bases change. The solver minimizes the physical
objective divided by this scalar; result extraction and supplied-point evaluation
multiply it back. Generator cost updates use the same divisor. The diagnostic
`objective_scale` records the effective value. Physical objective units remain
watts, currency/h or zero for source import, cost or feasibility, respectively.

`current_power_bases=Dict("mv_bus"=>1e5, "lv_bus"=>1e3)` declares **current-unit**
power bases. Seeds propagate through lines and closed switches, stopping at
transformers and open switches. Conflicting values in one such region, unknown
bus names and nonpositive/nonfinite bases are refused. Unseeded regions use
`s_base`. Nominal transformer coordinates must be enabled; their voltage-base
fallback remains in effect. The build copies the declarations to own its snapshot.

At a bus with assigned voltage and power bases ``V_r,S_r``, the intended current
base is ``S_r/V_r``. Current-coordinate classification uses the factor
``(V_r/V_b)(S_b/S_r)``; singleton/mixed-support safeguards and inverse-map recovery
remain unchanged. `transformer_scaling_report.power_bases` records the propagated
assignments, and retained-coordinate reasons show where a factor could not be
applied safely. All physical current, voltage and power observations still use
the original reconstruction. Changing declarations requires rebuilding.

This option deliberately **does not** rebase generator P/Q variables, lifted
observations/powers, voltage-law auxiliaries or ground multipliers. Generator
dispatch can be rebased separately as described below; the others retain
their assembly-unit conventions. In particular, `ground_scaling=:regional_voltage`
and `:regional_multiwinding_voltage` both use the common assembly power base,
not these current-unit declarations.
The option isolates regional current coordinates; it is not a complete regional
power normalization of every NLP variable. See the [theory](ivr_theory.md) and
[controlled experiment](ivr_performance.md) before selecting numerical settings.

### Independent generator dispatch units

`generator_power_bases=Dict("der"=>1e3)` assigns a positive finite VA base to
both active and reactive dispatch coordinates of generator `der`. All its native
channels use that base; delta dispatch remains coil-based. Unspecified generators
use `s_base`. Unknown IDs and nonpositive/nonfinite bases or unrepresentable
coordinate ratios are refused. The build owns a copy; changing the declarations
requires rebuilding. This policy does not require nominal transformer scaling.

Let ``S_b`` denote the assembly base and ``S_g`` the declared generator base.
The solver coordinates are ``\widehat P_g=P_g/S_g`` and
``\widehat Q_g=Q_g/S_g``. The generator defining equations retain assembly units:

```math
\operatorname{Re}(u_g\overline{i_g})=(S_g/S_b)\widehat P_g,\qquad
\operatorname{Im}(u_g\overline{i_g})=(S_g/S_b)\widehat Q_g.
```

Here ``u_g,i_g`` are the physical coil observations expressed in assembly units
after reconstruction. Thus only the dispatch columns change in these equations;
there is no additional equality-row normalization. Boxes divide SI bounds by
``S_g``; legacy prices multiply the active coordinate by ``S_g/1000``;
explicit power objectives recover W/var before applying targets and coefficients.
The objective divisor remains independent. `update_ivr_generators!` uses the
same fixed bases through fixed/free/one-sided bound transitions and price changes.

`ivr_nlp_point_report` derives the dispatch coordinates from the supplied SI
voltage/current products using ``S_g``. Those values can initialize every dispatch
variable. Result powers continue to be recovered from voltage/current products,
not trusted from dispatch auxiliaries. Capability limits, current limits, voltage
limits, circuit coordinates, and lifted-power units keep their existing maps.
The `generator_power_bases` diagnostic reports the effective base for every
generator, including defaults. Physical JSON keys and units are unchanged.

This is a separate invertible coordinate intervention, not a new generator
capability model or automatic base-selection rule. Hold `s_base`,
`current_power_bases`, lifting and the objective divisor fixed when measuring its
effect. See [the generator-unit experiment](ivr_objectives.md) and
[tutorial section 38](tutorial_exact_ivr.md).

### Exact selective lifting

`lifting=:powers` replaces each bounded complex power expression with auxiliary
P/Q variables and exact defining equalities, then applies the same rating to
those variables. `:bounded_observations` additionally lifts affine bounded
voltage/current expressions whose number of distinct real solver variables exceeds
`observation_support_threshold` (default 2). Support is counted after coordinate
composition using exact nonzero coefficients. A threshold of 8 therefore retains
rows with at most eight variables as direct expressions; it does not remove their
bounds. At the default threshold, singleton complex coordinates are not duplicated.
Identically zero channels are never lifted. Identical original observation rows
and power-factor pairs already share definitions.

`observation_selection=:coil_voltages`, `:coil_currents` or `:coils` restricts
eligibility to rows matching stamped ordinary/multiwinding coil observations.
The default `:all` retains the existing scope. Selection precedes affine sharing;
the support threshold still applies and every unselected bound remains direct.
See the [selective coil guide](ivr_coil_observations.md) for the identity, tutorial
and structural evidence.

With `observation_sharing=:exact`, distinct original rows also share one affine
definition when their composed real and imaginary constants and coefficients are
exactly identical. Variable order and exact zero terms do not affect identity.
Opposite signs, conjugates and nearly equal coefficients remain separate. No
tolerance, coefficient truncation or fixed-variable substitution is used in this
comparison. This option does not additionally merge power definitions or generator dispatch
variables.
With `:signed`, an observation may instead reuse the negative of an existing
definition. `:proportional` permits a finite nonzero real multiplier. It interprets
all stored real/imaginary coefficients and constants as exact binary rationals,
normalizes by the first nonzero entry in deterministic coefficient order, and
matches the entire normalized tuple. The candidate-to-representative ratio must
itself be exactly representable as a finite nonzero `Float64`. Otherwise the
candidate keeps a separate definition, even in the same proportional class.
There is no tolerance or rounding in this certificate.

The first encountered representative retains its original definition and units;
each shared observation returns `factor * representative`. Thus all original
limits and native power expressions retain their sign and scale. Constants must
scale too: `2u` may share with `u`, whereas `2u + 1` generally cannot. Additive
translations, complex rotations, conjugation and equality that holds only on
circuit solutions are outside these new certificates. Fixed variables are not
substituted during matching. Different floating-point construction histories may
miss reuse; such misses preserve separate definitions.

`observation_sharing_report` has one entry per newly shared original observation,
in traversal order, giving `representative_record` (the index in the model's
internal lifting records) and its reconstruction `factor`. Repeated visits to
the same original row do not add entries. This is build diagnostic information,
not a persistent physical-variable identifier. [The affine-sharing study](ivr_affine_sharing.md)
explains the equivalence proof, numerical evidence and remaining scope.

The threshold, selection and sharing controls have no effect for `lifting=:off` or `:powers`.
Original physical power outputs remain expressions of the state.

Definitions have consistent initial values and are reconstructed uniquely when
encoding a supplied physical point. They do not create additional device
freedoms, change any rating or alter CP/generator update semantics. Diagnostics
record `lifting`, `lifted_real_variables`, `observation_support_threshold`,
`observation_selection`, `observation_selected_row_count`,
`observation_sharing` and `shared_observation_count`. The last count is the number
of distinct original rows reusing an existing composed definition, not repeated
visits to the same original row. More variables can make a nonlinear
constraint simpler, but may also make Ipopt's linear systems more expensive;
the [performance guide](ivr_performance.md) reports measured outcomes.

### Independent lifted-power units and native generator reuse

`lifted_power_base=S_l` changes only power-auxiliary coordinates, including
objective-only power lifts. Its default `nothing` uses the assembly base ``S_b``.
For an assembly-unit complex power expression ``s``, the defining equalities are

```math
(S_l/S_b)\widehat P=\operatorname{Re}(s),\qquad
(S_l/S_b)\widehat Q=\operatorname{Im}(s).
```

The expression returned to bounds and objectives is
``(S_l/S_b)(\widehat P+\mathrm{i}\widehat Q)``. Consequently all existing
operating bounds and physical objective coefficients retain their assembly/SI
interpretation. The defining rows remain in assembly-power units; this is a
column-coordinate intervention, not a simultaneous row normalization. Recorded
inverse expressions and default/shared physical starts divide by ``S_l/S_b``.
Voltage/current observation lifts keep their original units. Generator dispatch
uses its independently declared bases. Neither option changes physical ratings.
Nonpositive/nonfinite bases and unrepresentable coordinate ratios are refused.
The effective VA base is recorded in `numerical_diagnostics[:lifted_power_base]`.
With `lifting=:off`, setting this base creates no auxiliaries.

`power_sharing=:generators` is a separate exact reformulation. With lifting
on, a requested power whose original voltage/current row pair exactly matches a
native generator channel reuses its existing dispatch variables, converted back
by ``S_g/S_b``. The generator's defining equalities already impose the required
power identity, so adding another P/Q pair is unnecessary. The original apparent
power bound remains. Channel semantics stay native: delta uses coil powers.
Updates to boxes and prices preserve the definition. The policy does not reuse
IBR/source powers, approximate coefficients, identify proportional expressions,
or infer equivalence merely from a device name. Nonmatching powers follow the
ordinary lifting path. `:off` retains all existing alternatives; lifting off
ignores this reuse policy. `reused_generator_power_count` counts distinct reused
power definitions, not the number of bound occurrences.

Supplied-point encoding derives generator dispatch and any remaining lift
coordinates from physical observations. Results still recover SI powers from
voltage/current products, and all formulations expose the same physical quantity
keys. Scaling and reuse are compared separately in the
[matched-finalist study](ivr_objectives.md); [tutorial section 39](tutorial_exact_ivr.md)
demonstrates both controls.

### Series selection by bound support

`series_selection=:bound_support` adds a conservative selection rule to
`linear_elimination=:passive`, `:passive_chains`, `:passive_blocks` or `:passive_hybrid`. Structural
eligibility and the selected unit-pivot/block substitution are unchanged.
For each affected operating bound, count the union
of nonzero **complex solver-coordinate** indices in its transformed voltage/
current rows. A voltage or current magnitude uses one row; an apparent-power
bound uses the union from both rows. A zero factor gives support width zero.
Reject the tentative bus substitution if any affected bound's width increases.
No coefficient threshold or weighted performance score is used.

The selector indexes the compiler's shared bus-voltage bound rows and the
assembler's physical current/apparent-power limit records. Zero lower-voltage
bounds emit no constraint and are excluded. Zero upper ratings remain in the
index because their real/imaginary equalities are emitted. Source, transformer,
generator and IBR equations/objectives cannot acquire these eliminated local
coordinates: a candidate bus has no device, and its line through-current
coordinates are distinct from device-current coordinates.

A rejected tentative substitution is rolled back before considering the next
bus; it does not protect neighbouring buses from selection. Accepted candidates
retain the existing nonadjacent rule in `:passive` only. The chain mode checks
**all original operating-bound rows** after each tentative composition. A bound
at a previously eliminated bus may acquire a new dependency; indexing only the
current bus would miss it. Impedance-current substitution is unchanged.
Selection is inert for `linear_elimination=:off` and `:impedance_loads`. If no
substitution is accepted, the incoming maps are reused. The bound index is built
only after encountering a structurally eligible series candidate.

The elimination report includes `series_selection` and `bound_support_rejections`.
Each rejected bus records the bound label and before/after widths; the retention
reason is `operating_bound_support_expansion`. `limit/<record>/...` labels identify
the assembler's limit record, while `bus/<id>/<field>` identifies a bus field.

This is a local expression-support heuristic. It is **not** an exact Hessian or
KKT-fill estimator, a global sparsity guarantee, or a runtime optimizer. It
ignores output-only power-polynomial expansion, coefficient magnitudes,
solver preprocessing and factorization ordering. It can reject reductions that
would solve faster. Default `:all` preserves the existing elimination choices;
see [measured evidence](verification.md) before choosing this opt-in policy.

The [profile study](ivr_performance.md) compares complete option combinations
without removing any alternative or changing package defaults. It prioritizes
Ipopt wall time, excluding construction and result extraction; construction and
wrapper timings remain separate diagnostics. Failed, incomplete or
objective-incomparable results cannot win.

### Finite-ground numerical scaling

`ground_scaling=:voltage` is an invertible numerical policy, independent of
conductor specialization and linear elimination. For each retained, unfixed
physical voltage coordinate attached to a one-terminal shunt, let
``s=\max(1,\max_j |Y_j|Z_b)`` over eligible shunts at that terminal. The solver
uses ``w=sV_{pu}``, and every physical expression reconstructs ``V_{pu}=w/s``.
Multiple shunts remain separate electrical contributions; their admittances
are not merged or approximated. Ideal/fixed voltages, multi-terminal shunts and
coordinates already expressed through other voltages are retained unchanged.

`ground_scaling=:regional_voltage` applies the same eligibility and inverse
maps, but uses ``Z_r=V_r^2/S_b`` instead of ``Z_b`` when selecting the multiplier.
The nominal base graph and conservative global fallback are the same as for
`transformer_scaling=:nominal`. Regional base selection is independent of that
option: with transformer scaling off, the regional multiplier acts on the
global voltage coordinate; with it enabled, it acts on the corresponding local
voltage coordinate. No regional power base is introduced. The new policy refuses
nonfinite multipliers or coefficient overflow/underflow instead of discarding
nonzero terms. The existing `:voltage` policy and default remain unchanged.

`ground_scaling=:regional_multiwinding_voltage` applies the same contract using
the multiwinding characteristic-unit graph. The ordinary-only regional policy
remains unchanged. See the [scientific guide and live-ground controls](ivr_nwinding_ground.md).

When at least one coordinate is scaled, circuit equalities are divided by the
Euclidean norm of their coefficients **after** projection/reconstruction and
scaling. An identically cancelled row uses divisor one. This keeps a large
grounding admittance from dominating the KCL normalization while its current
error is hidden. Operating bounds, objective and original SI audit retain their
physical definitions. No new variable, omitted equation or ideal-ground
approximation is introduced. If no target is eligible, construction uses the
existing coordinates and normalization.

Inspect `:ground_scaling_report` in `numerical_diagnostics`: `scaled_terminals`
contains bus, terminal, solver coordinate and scale; `retained_shunts` gives
reasons for declarations not selected. `region_assignment` records the selected
bases and fallback reasons for either regional policy and is `nothing` for
`:off` and `:voltage`. Parameters of grounding equipment still
require rebuilding. CP and generator updates preserve the maps. Default `:off`
retains existing numerical behaviour. This limited policy does not guarantee
physical accuracy for arbitrary ill-conditioned circuits or replace independent
SI validation; see [verification](verification.md) and the
[finite-ground tutorial](tutorial_exact_ivr.md).

### Electrical elements

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
`i_max` and `s_max` apply to coil channels. By default, `s_rating` adds no
operating limit. Exact IVR also offers the explicit
`transformer_nameplate=:bmopftools` policy described below. See [Transformer winding model](sdp_transformers.md)
for coefficient and orientation conventions.

Ordinary transformers accept the schema `tap_ratio`, `tap_ratio_min` and
`tap_ratio_max` spellings through the existing BMOPF adapter, which copies them
to the internal `tap`, `tap_min` and `tap_max` fields. Both spellings are retained;
conflicting values are rejected. General multiwinding entries use `tap_ratio`
per winding. Unequal tap bounds require an explicit fixed setting.
Taps are fixed equipment data and cannot be
changed through the load/generator update APIs.

### Explicit transformer nameplate policy

`IVRNLP(transformer_nameplate=:bmopftools)` adds the positive `s_rating` cap
used by the inspected BMOPFTools implementation. This selects a physical feasible
set; it is not a numerical reformulation and must be fixed across a timing panel.
The default `:ignore` preserves the previous native problem and every older
experiment. The build's `transformer_nameplate_report` identifies every positive
ordinary-transformer rating and whether it is enforced.

| Transformer | Rated voltage/current | Per-channel limit |
|---|---|---|
| Single phase, center tap | From-side coil voltage and series current | `s_rating` |
| Delta/wye, wye/delta | Wye phase-neutral voltage and total phase-terminal current | `s_rating / 3` |
| Single-phase autotransformer, open-delta regulator | From-side through-coil voltage and series current | `s_rating` per regulator |

No aggregate three-phase norm or nominal-voltage current approximation replaces
these products. Wye phase current includes excitation; regulator bond/ground
currents are not substituted for the through-coil current. Missing ratings add
no row. A supplied zero rating is rejected in this mode, matching the reference's
input validation; the legacy mode continues to allow zero without a cap.
General multiwinding `s_rating` remains metadata. Under `:bmopftools`, scalar
winding `s_max` is the total winding VA rating and each of its ``m`` coils has
cap `s_max / m`. Under `:ignore`, the scalar retains the native per-coil cap.
Explicit `s_max` vectors remain per-coil in both policies; they are a dictionary
extension, not a live BMOPFTools vector-parity claim. Winding `i_max` remains
per-coil amperes. Zero explicit `s_max` imposes zero coil power; an absent field
adds no bound. Neither scalar interpretation is an aggregate apparent-power
constraint: the cap is applied separately to each coil's voltage/current product.
The `nwinding_power_limit_report` records winding index, coil count, interpretation,
series-coil current basis and applied SI `limits_VA`. See the
[unit-parity study](ivr_nwinding_limits.md) for independent and live checks.
This policy does not claim complete BMOPFTools multiwinding, control or
device-law equivalence; excitation-location and other declared scope differences
remain relevant.

Direct and lifted constraints share the same original rated observations, even
after transformer-current elimination and unit changes. The independent SI
auditor selects the rated port separately. `physical_residuals(net, result)`
reads the policy from the exact-IVR result; an `ACPoint` caller must pass
`transformer_nameplate=:bmopftools` explicitly. SI exports label the policy and
include `s`/`s_max` at the enforced reference-compatible transformer positions.
See the [nameplate and three-phase study](ivr_threephase_transfer.md) for active
bounds, live-reference tests, previous-study qualification and remaining gaps.

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
The opt-in `load_power_lifting=true` additionally separates electrical power
products from nonlinear voltage laws using exact power auxiliaries, in
per-load `load_power_bases` units, then `load_power_base`, `lifted_power_base`,
or `s_base` in that precedence. Explicit load units require this lifting option;
per-load overrides must identify loads that receive auxiliaries. Effective units
appear in `:load_power_bases`. It applies independently of `lifting`;
constant-power and impedance loads remain unchanged. The default is false.
See the [equivalence argument and numerical evidence](ivr_load_power_lifting.md).
`:load_power_lift_count` counts complex power auxiliaries.
`load_power_row_scaling=:definitions/:laws/:both` independently selects load
power equalities to rescale; default `:off` retains assembly units. Per-load
`load_power_row_bases` override `load_power_row_base`, then `s_base`, independently
of column units. An active mode requires load-power lifting. Explicit row units
require an active mode; invalid/inactive IDs are refused. See the
[row/column study](ivr_load_power_rows.md) for the exact residual and dual-unit
relations, diagnostics and strict physical admission.
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
and any internal neutral-ground contribution. With the default nameplate
policy, `s_rating` adds no thermal cap; the opt-in BMOPFTools policy instead
rates each from-side through coil.

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
`:source_import` (watts), `:feasibility`, and `:power` (explicit affine/quadratic
terms in physical P/Q channels). Inputs and outputs use SI units;
`s_base` controls internal scaling. Inputs are copied rather than modified.
The present exact-IVR implementation uses **one network-wide voltage base**:
the largest source voltage magnitude, with current base `s_base / voltage_base`.
All electrical assembly coordinates are per unit. Optional
`transformer_scaling=:nominal` composes separate local voltage/current coordinates
for the solver; finite-ground scaling is a separate optional transformation. The
[scaling audit](ivr_performance.md#Scaling-conventions-and-transformer-priority-—-5-October-2026)
explains the experimental implications.
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
| General multiwinding transformer | Winding `i_max`, `s_max` | Coil current and coil apparent power; scalar power divided by coil count under `:bmopftools`, broadcast under `:ignore`; vectors per-coil |

Source Q/current/apparent bounds and switch/multiwinding `s_max` are dictionary
extensions to the pinned schema. Fixed tap bounds are checked against the
equipment setting before construction; they are not optimization variables.
Load `p_nom`/`q_nom`, nominal voltages and retained geometry ratings do not imply
extra operating caps. The default `transformer_nameplate=:ignore` also leaves
`s_rating` unenforced. This differs from BMOPFTools; choose the explicit policy
below when preserving its ordinary-transformer nameplate limits.

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

A separate `examples/benchmark_ivr_reuse.jl` study now crosses fresh/reused
models with explicitly reset or previous-primal starts, with AMD fixed. It ranks
complete sequences by Ipopt wall time, excluding model construction and update
costs. Demand, generator prices and active availability vary within the sequence;
each updated state is audited against independently edited scenario data and
fresh models. This adds an experimental start policy, not an automatic update-API
behavior or a primal-dual warm-start contract. See the
[performance guide](ivr_performance.md) for the protocol and measured domain.

The separate `dual_workflows()` shortlist compares normal previous-primal
initialization with zero-dual and reconstructed-dual warm initialization on the
same reused model. `examples/ivr_dual_starts.jl` validates equation correspondence
and resets both bound sides when a generator box changes. It uses JuMP's
reconstructed bound duals; it does not recover both native Ipopt multipliers or
retain a factorization. Callers must admit the preceding solution before capture;
the helper checks availability and finiteness, while the benchmark checks physical,
model, fresh-model and objective agreement. The [tutorial](tutorial_exact_ivr.md)
shows this explicit experimental sequence. Production update behavior is unchanged.

`examples/benchmark_ivr_histories.jl` adds deterministic six-step P/Q demand and
price paths with fixed or changing generator boxes, including fixed/released Q
and a removed/restored Q lower side. Every operating point differs from its
predecessor. Physical-unit generator dispatch is saved for independent bound
activity checks. Compare complete admitted policies within each history; the
two histories change feasible sets and need not have equal objectives. This
remains an explicit experiment, with no automatic fallback or production changes.

The external-feeder counterpart `examples/benchmark_ivr_feeder_reuse.jl` uses
explicit constant-power demand sequences and a feasibility objective, preserving
source/generator accounting. It writes a provenance manifest before solving,
records changed and unchanged load IDs, and leaves input files untouched. Its
default four reused-model/start workflows use eight balanced sweeps. A separate
four-workflow fixed-start experiment isolates fresh versus reused models. These
add demand-sequence evidence, not a new production update contract.

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


### Linear electrical equation provenance

Native builds expose `electrical.equation_metadata`: original equation index,
physical label, ampere/volt unit and the multiplier needed to undo any internal
stamp normalization. These records do not change rows, maps or model dimensions.
The [physical circuit-row guide](ivr_circuit_residuals.md) explains complete
linear-row coverage, omission status, shared-assembly controls and the remaining
scope limits. Nonlinear laws, operating bounds and fixed-variable constraints
are outside that linear-row catalogue.

The [implied-row certificate guide](ivr_implied_residuals.md) constructs exact
stored-coefficient dependencies and state-dependent SI residual bounds for
omitted linear rows, without changing the optimization model.
