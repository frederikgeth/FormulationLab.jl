# Common physical results and JSON export

`result_dict(network, result)` converts every public formulation result to one
component/ID/terminal dictionary in SI units. `result_dict(build, result)` is a
convenience form; LinDist3Flow also supports `result_dict(result)` because its
result owns the network. Existing typed results and solve acceptance remain
available. Exporting does not optimize, change a limit, or certify feasibility.
The input may also be a `BMOPFInput`, PowerIO module or BMOPF JSON path/text,
using the same parsing and normalization as the formulation builders.

```julia
build = build_opf(net, IVRNLP(specialization=:conductor_regions,
    linear_elimination=:passive_chains); optimizer=Ipopt.Optimizer)
result = solve_ivr_nlp_opf(build)
output = result_dict(build, result)
write_result(output, "result.json")
restored = read_result("result.json")
@assert isequal(restored, output) # isequal also compares NaNs
```

## Compatibility contract

The reference is BMOPFTools revision
`39523e8a5cc5543e0f644ab2d135dd43ef4d8c01`, specifically its result extractor,
result documentation and JSON I/O. BMOPFTools is an optional integration-test
dependency, not a FormulationLab runtime dependency. The top-level dictionary
and the following shared static-AC fields follow its names and conventions:

| Path | Fields and meaning |
|:--|:--|
| `bus[id][terminal]` | `vr`, `vi`, `vm` [V], `va` [rad], phase to ground |
| `line[id][from_terminal]` | `cr_fr`, `ci_fr`, `cm_fr`, `cr_to`, `ci_to`, `cm_to` [A]; total currents leaving each bus into the line, including charging |
| `switch[id][from_terminal]` | `cr`, `ci`, `cm` [A]; from-side through current leaving the bus, following the reference implementation |
| `load[id][phase]` | `crd`, `cid` [A], `pd` [W], `qd` [var]; absorbed coil power |
| `generator[id][phase]` | `crg`, `cig` [A], `pg` [W], `qg` [var]; produced coil power |
| `ibr[id][phase]` | `cri`, `cii` [A], `pg`, `qg`; topology-specific coil current/power |
| `voltage_source[id][phase]` | `cr`, `ci`, `cm`, `ps`, `qs`; injected current and phase-to-neutral imported power |
| `transformer[id][fr/to][position]` | `cr`, `ci`, `cm`; series currents, with the reference's subtype-dependent terminal/winding indexing |
| `transformer[id][w1/w2/…][position]` | Multiwinding coil currents; explicit winding `s_max` adds `s`/`s_max` |
| `capacitor[id]` | `terminals[terminal][cr/ci/cm]` and delivered reactive power `q` |
| `ground[bus][terminal]` | `cg_r`, `cg_i`, `cgm`; identifiable ideal-ground reaction, positive into the bus |
| `line/transformer[id][ground]` | `cg_r`, `cg_i`, `cgm`; device net current into earth |
| `line/transformer[id][loss]` | `p_loss`, `q_loss`, `s_through`; sum of terminal powers and throughput scale |
| `losses` | `p_loss`, `q_loss` summed over lines and transformers, as in the reference |
| `initialisation[bus][terminal]` | `vr_init`, `vi_init`, `vm_init`, `va_init`; physical starts when available |

Top-level `termination_status`, `primal_status`, `result_count`, `feasible`,
`objective` and `solve_time` describe the solver result. `feasible` follows the
reference's feasible/nearly-feasible primal-status convention; it is **not** an
independent physical assessment. `solve_time` is the solver's reported wall time,
not export or compilation time. Objective units appear in
`_formulationlab.objective_units` (`W`, `currency/h`, or `dimensionless`).

Terminal ordering follows the original input, including permutations. The
from-side terminal labels key lines even when the to-side labels differ.
Transformer IDs are flattened like BMOPFTools: duplicate IDs across subtype
tables cause an explicit error rather than silent overwriting. Single-phase
and regulator transformer positions refer to coils; other two-bus transformer
positions refer to the series-current terminal image. Terminal currents including
excitation, internal grounding and bonds are separately retained in the extension.

For exact-IVR multiwinding results, exported `s_max` is the applied **per-coil VA
cap**. Under `transformer_nameplate=:bmopftools`, scalar winding input is divided
by coil count; under `:ignore` it is broadcast unchanged. Explicit vectors stay
per-coil. `s` always uses physical coil voltage and series-coil current. The
extension `_formulationlab.nwinding_power_limit_report` records the interpretation
and resolved caps. A policy change can change dispatch; a numerical formulation
change with the same policy preserves the physical-variable contract. The
[live unit-parity study](ivr_nwinding_limits.md) checks the scalar case against
BMOPFTools, including SI JSON reader compatibility.

Compatibility of result fields does not imply identical OPFs. In particular,
the default exact-IVR policy leaves transformer `s_rating` unenforced, so it
does not report it as an enforced `s_max`. With
`transformer_nameplate=:bmopftools`, ordinary-transformer rated positions include
`s` and `s_max` in SI units. `_formulationlab.transformer_nameplate_policy` and
`transformer_nameplate_report` distinguish enforced and ignored ratings. These
fields describe the solve snapshot, independently of the numerical reduction
chosen. See the [rated-port contract](ivr_nlp.md#Explicit-transformer-nameplate-policy). Optimized taps, external DC laws and control profiles
are not added by this exporter. Empty `dc_bus`, `dc_branch` and
`modeled_volt_watt` tables preserve the reference envelope for the supported scope.
No runtime dependency or silent fallback to BMOPFTools is introduced.

## Reconstruction and additional observations

For a real connection matrix ``D``, terminal voltage vector ``v`` and coil
current vector ``j``, the adapter uses

```math
u=Dv,\qquad i=D^{\mathsf T}j,\qquad
s_{\mathrm{coil}}=u\odot\overline j,\qquad
s_{\mathrm{terminal}}=v\odot\overline i.
```

Consequently ``\sum s_{\mathrm{coil}}=\sum s_{\mathrm{terminal}}`` for that
connection alone. Loads use absorbed current; generators and IBRs use injected
current. For lines and transformers, every port current points into the device,
so ``s_{\mathrm{loss}}=\sum_{\mathrm{ports},k}v_k\overline{i_k}`` includes
charging and excitation. Series-coil currents and total port currents must not
be substituted for each other when an additional shunt or bond is present.

For three ordered phases and ``a=\exp(2\pi\mathrm{i}/3)``, the exported sequence
voltages are ``u_+=(u_a+au_b+a^2u_c)/3``,
``u_-=(u_a+a^2u_b+au_c)/3`` and ``u_0=(u_a+u_b+u_c)/3``. Sequence order follows
the operating-bound convention: use `terminal_conventions.phase` when it names
exactly the three distinct local phases; otherwise use `a,b,c` when those names are present;
otherwise use local terminal order with the neutral removed. A network-wide
phase vocabulary containing additional names therefore does not override local
`a,b,c` ordering. Merely permuting bus storage must not swap positive and
negative sequence when a named order is available. Relabelling phases changes
the interpretation and must be performed consistently in the input.
Repeated phase labels do not define a three-phase order and use the same fallback.

The `phase_to_phase` array separately retains local phase order, matching the
indexing of `vpp_min`/`vpp_max`. It is not reordered to match the sequence
convention. `test/result_sequence_tests.jl` uses independent unbalanced physical
states with nonzero positive, negative and zero components, custom names,
permuted storage and a displaced neutral. It checks full and reduced/lifted
models, both SI and model rejection of tightened sequence bounds, recovered
complex values and JSON round trips.

All exact-IVR coordinate options use the same physical observation rows.
Eliminated impedance currents, conductor currents and adjacent-chain voltages
are reconstructed before extraction. Original bus and line IDs remain present;
export does not collapse the physical topology. The same supplied physical point
therefore has the same output meaning under full, conductor-difference, regional,
passive, chain and scaled coordinates. Separate nonlinear solves can still
converge to different stationary points or different unidentifiable freedoms.

This guarantee concerns the exact compiler's internal coordinate reductions.
Separate `prepare_network` topology preprocessing changes the supplied network;
its original-network `ReconstructedSolution` adapter is not yet part of this JSON
API. Export the matching prepared dictionary for reduced-network records; use
`reconstruct_solution` separately to inspect original-network estimates.

`_formulationlab.devices` contains additional physical observations, without
changing the reference fields:

- Bus phase-to-reference, phase-pair and positive/negative/zero-sequence voltages.
- Both line-end powers, series current and each end's charging current.
- Device coil voltages/currents/powers and complete terminal currents/powers,
  including neutral return paths.
- IBR filter currents, internal voltages and internal powers.
- Transformer coil quantities, terminal currents and retained bond currents.
- Capacitor coil quantities and shunt currents/powers.

A three-leg IBR's native exact-IVR PCC output is conductor based. The adapter
recovers its coil currents from the retained filter-current observations and
known charging term; it does **not** invert delta incidence with an arbitrary
circulation choice. If the required observation is absent, coil quantities
remain unavailable while known terminal currents remain present.

An ideal source's grounded-terminal current allocation is not identified in the
common-earth model. Its current and the corresponding split ground reaction
are unavailable, rather than the solver representation's zero placeholder.
Power at an identically zero-voltage terminal is nevertheless exactly zero.
At an ideally grounded bus with all device currents observed and no unresolved
source allocation, KCL determines the aggregate ground reaction. This is not a
claim about separate parallel physical grounding conductors.

## Formulation-independent names, explicit interpretation

| Formulation | `_formulationlab.state_kind` | Interpretation of physical fields |
|:--|:--|:--|
| Exact IVR, all coordinate policies | `exact_coordinate_recovery` | Original observations reconstructed from the returned primal |
| LinIVR | `approximate_state` | Products of its approximate voltage/current state |
| LinDist3Flow | `fixed_angle_estimate` | Solved magnitudes combined with reference angles; unretained currents remain unavailable |
| SDP, SOC, branch-flow SDP | `relaxation_candidate` | Recovered phasor estimates; not an exact AC solution certificate |

For LinIVR, modeled powers differ from products of its approximate phasors.
For relaxations, lifted power moments need not equal products of reconstructed
phasors. `_formulationlab.native_powers` preserves these native values and
`native_power_kind` identifies them. Native SDP/SOC matrices and branch-flow
moments remain in `native_moments`, with their coordinate interpretation; internal
SDP/SOC blocks are not relabeled as physical phasors. LinDist3Flow's original
magnitude/flow/dispatch records remain in `native_model`.

There is no claim that arbitrary non-rank-one relaxations yield exact voltage
angles, or that terminal currents identify a delta coil circulation. Missing or
nonfinite output leaves are listed by explicit path in `_formulationlab.unavailable`.
`physical_validation="not_run"` is deliberate: use `physical_residuals` or the
relaxation validation API separately. A complete JSON dictionary is not a physics
certificate. For approximations with projected/unsupported device laws, an adapter
may refuse an unsupported connection instead of inventing values.

## Snapshot and failed-solve semantics

Every solve captures an owned network fingerprint, actual available physical
starts, result count and solver wall time. Export refuses a different input
snapshot, including exporting an old result through a build that has since been
updated. Keep the matching original network to export older results. Fingerprints
are insensitive to dictionary insertion order and numerically identical JSON
spellings such as `230`/`230.0` or signed zero, but intentionally sensitive to
changed input values and annotations. Large integers are not rounded through
floating-point conversion. Export never reads a later solution from a live
JuMP model.

The existing solve wrappers retain strict publication rules. Exact IVR and
LinIVR additionally retain a returned diagnostic primal for export after, for
example, an iteration limit. This does not promote the typed result to success.
No primal means unavailable physical values, and an infeasibility certificate
is not treated as a primal point. Other formulations retain their existing
candidate-publication limits; unavailable fields remain explicit even if the
solver reported a diagnostic result. A full failed-candidate adapter for every
relaxation is not yet implemented.

Lifted models do not necessarily have physical voltage start variables, and
LinIVR may have no explicit starts. Their unavailable start values are not
replaced with an assumed flat profile. `initialisation_available` reports whether
all physical start fields were captured.

## JSON conventions and verification

`write_result(dict, path_or_io; indent=2, nonfinite=:preserve)` and
`read_result(path_or_io)` match BMOPFTools' NaN/Inf-tolerant JSON convention.
`indent=nothing` selects compact output. `read_result(text; from_string=true)`
reads JSON text. Numeric signed zeros in exported dictionaries are canonicalized
to positive zero, avoiding a parser round-trip discrepancy without changing any
physical quantity.

For strict JSON consumers, explicitly select `nonfinite=:null`. This writes nulls
instead of NaN/Inf and intentionally changes the numeric round-trip representation;
unavailability paths remain available. No native complex values, tuple dictionary
keys or JuMP objects appear in the exported dictionary.

The default tests cover full/reduced field-path and numerical parity, JSON round
trips, stale-input refusal, unsuccessful exact-IVR diagnostic candidates, all six
formulation result types and derived physical records. The optional integration
compares bus, line, load, source and loss records with the inspected BMOPFTools
implementation and exercises both writers/readers:

```sh
julia --project=test/integration test/integration/result_export_parity.jl
```

That live panel does not establish numerical parity for every transformer,
inverter or control model. It uses the scalar `vn_max` spelling accepted by both
implementations; the reference currently rejects the equivalent one-entry vector.
