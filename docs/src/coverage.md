# BMOPF component coverage

This is an implementation inventory, not a claim of complete BMOPF conformance.

## Exact IVR scope

[`IVRNLP`](ivr_nlp.md) has its own applicability gate; sharing the circuit assembler
does not grant it every SDP or LinIVR device law. See the
[equations and equivalence domain](ivr_theory.md) and
[operating-bound inventory](ivr_nlp.md#Operating-bound-coverage).

| Element or operation | Exact IVR | Conductor specialization |
|:--|:--|:--|
| Coupled lines, endpoint shunts, explicit terminals | Supported, both-end current/apparent limits | Whole uniform radial 2/3/4-wire sections, or certified pendant regions; shunted lines remain physical in regional mode |
| Fixed sources, ideal/finite grounds and shunts | Supported, subject to voltage-reference/current-observability conditions | Whole-section mode requires one source and no downstream earth paths; regional mode retains these buses as boundaries |
| Single-phase, wye and delta constant-power/impedance loads | Supported with physical connection channels | Requires downstream zero-sum connection identities |
| Generators | P/Q/S/I capability and linear prices; delta uses coil quantities | Device currents remain explicit |
| Fixed capacitors | Scalar bank and explicit per-coil rating contracts | Zero-sum connections may qualify; phase-earth banks trigger whole-section fallback or a retained regional boundary |
| Fixed open/closed switches | Supported, explicit through current and both-end limits | Whole-section fallback; regional interiors may attach to retained switch buses |
| Fixed isolated-winding transformers | Single-phase, center-tap, delta–wye, wye–delta, general multiwinding | Whole-section fallback; regional interiors may attach to retained winding buses |
| Fixed autotransformers/regulators | Single-phase and all three open-delta connections; explicit conductive bonds and both-side current limits | Whole-section fallback; regional interiors may attach to retained winding buses |
| Static IBRs | Single-phase, explicit-neutral four-leg, three-leg; filters and internal budgets/setpoints | Zero-sum connections may qualify; THREE_LEG PCC ratings use conductor quantities |
| Constant-current/ZIP/exponential loads | Exact powers on a declared positive coil-voltage domain; pure impedance cases retain their linear current law | Same downstream zero-sum connection identities; voltage-law auxiliaries retained |
| Control profiles, optimized taps, external DC and time-series laws | Refused | Not applicable |
| Constant-power demand and generator P/Q/price updates | Supported through dedicated APIs | Existing certificate/maps reused |
| Equipment, source and IBR capability updates | Require a new build | Reassess applicability on the new build |

An independent opt-in `linear_elimination` pass substitutes impedance-load
currents, or also eliminates nonadjacent device-free degree-two buses between
unshunted lines. It composes with conductor specialization and retains every
physical observation and operating bound. This expands coordinate-reduction
choices, not element coverage. See the [contract](ivr_nlp.md#Local-linear-elimination)
and [proof](ivr_theory.md#4.-Local-linear-elimination-with-retained-observations).

With passive elimination, `series_selection=:bound_support` optionally retains
candidates that would increase an affected operating bound's coordinate support.
It selects among the same exact reductions and adds no equipment capability;
all operating bounds remain present under either selection policy.

`ground_scaling=:voltage` changes numerical coordinates for eligible retained
free voltages attached to one-terminal finite shunts. It preserves equipment,
observations and bounds and adds no element coverage. Multi-terminal grounding
equilibration is outside this numerical policy; see the
[contract](ivr_nlp.md#Finite-ground-numerical-scaling).

Regional mode retains source, earth-path and device-boundary buses and certifies
only eligible leaf regions. See [regional scope](ivr_nlp.md#Pendant-regions-inside-a-larger-network).
A supported full-IVR network may fail the narrower specialization certificate;
this triggers a diagnostic fallback, not deletion of the offending component.
Unknown electrical fields are refused. Native dictionary extensions are not
complete external-schema support. [The tutorial](tutorial_exact_ivr.md) includes
both a tightened-bound rejection and a supported earth-shunt fallback.

## Approximation and relaxation scope

Experimental [LinIVR](linivr.md) has a separately documented scope:
explicit-neutral passive circuit laws, all seven fixed transformer families,
constant-power/impedance loads, wye/delta generation and static single-phase,
three-leg and four-leg inverters, with affine power products and SOC limits. It does
not inherit the full SDP device-law coverage merely by sharing its assembler.
LinIVR's delta generator/three-leg inverter powers and current ratings use the
BMOPFTools coil convention; the existing SDP conductor convention is retained.
Its inverter filter/internal-power extensions are independently tested, but are
not implemented by the inspected BMOPFTools nonlinear comparator.
Read it after the [formulation guide](formulations.md); symbols such as series
and total endpoint current follow the shared [notation](notation.md).
The local PowerIO 0.11 source identifies 0.1.0 as the accepted schema and 0.2.0
as a proposal. The proposal revision inspected during migration is
`fe8671a74d2fc1a15a499c5b1f66cbb80fc22e12`, SHA-256
`74d6c6de3637d52e42a26c4cb0584f51df70d69f360b236cf5e23afaf7669462`.

| Fields / behavior | LinDist3Flow | BranchFlowSDP | Dense IVRSDP / IVRSOC |
|---|---|---|---|
| `bus.terminal_names`, grounding | Neutral-reduced; guarded Kron preprocessing | Explicit aligned terminals; fixed zero-voltage grounds | Explicit terminals; ideal grounds eliminated |
| `bus.v_min`, `v_max` | Retained-terminal squared-voltage bounds | Phase/all-terminal squared-voltage bounds | Lifted phase-ground squared-voltage bounds |
| `vpn_*`, `vpp_*` | Grounded-neutral alias / affine winding closure within documented domain | Lifted physical voltage maps | Lifted physical voltage maps |
| `vpos_*`, `vneg_max`, `vzero_max`, `vn_max` | Restricted/refused or explicitly waived by permissive policy | Lifted physical voltage maps | Lifted physical voltage maps |
| Line series R/X matrices and terminal maps | Fixed-reference lossless drop | Full coupled series law; complete aligned maps on radial or meshed networks | Full coupled linear current/voltage law |
| Line `G/B_from/to` | Endpoint-shunt lowering | Explicit endpoint currents and powers | Explicit endpoint currents |
| Line/linecode `i_max`, `s_max` | Live-voltage SOC surrogate, both endpoints | Total endpoint current/power limits; implied endpoint and shunt-corrected series-current bounds | Lifted current and apparent power, both endpoints |
| Valid-inequality strengthening | — | Explicit/line-derived voltage LNCs; dispatch P/Q-box port cuts; implied switch and multiwinding-coil currents | Explicit/line-derived voltage LNCs; dispatch P/Q-box port cuts; implied physical-current bounds |
| Load `p_nom`, `q_nom`, connections | Fixed-reference channel allocation | Wye/single-phase and two-/three-terminal delta incidence with local moments | Physical incidence and channel currents |
| Load `model`, `v_nom`, ZIP/exponents | P/Z/ZP; documented projections for I/exponential | P/Z exact laws; I/ZIP/exponential power-cone envelopes | P/Z current/power laws; I/ZIP/exponential power-cone envelopes |
| Generator P/Q bounds, `s_max`, `i_max`, `cost` | Affine/SOC with restricted controls | Wye/delta conductor P/Q/S/I capability and linear cost | Conductor powers for three-terminal delta; coil powers otherwise; coil/terminal current maps, including neutral |
| Fixed source phasors, bounds, costs | Per radial island | Multiple complete-map sources with shared relative phasors | Multiple fixed sources; grounded-source ampacity extension rejected |
| Fixed shunt G/B matrices | Affine voltage-product closure | Full bus-map moment law | Full linear current law |
| Switches, capacitors | Documented fixed-state lowering | Fixed-state electrical laws | Fixed-state electrical laws |
| Transformers/regulators | Single-phase, center-tap, Yd/Dy, autotransformer, open-delta; documented restrictions/lowering | All seven fixed-setting subtypes with component-local winding blocks | All seven subtypes, including general multiwinding; internal grounding and explicit excitation |
| `tap_ratio*` on ordinary transformers | Normalized to migrated `tap*` spelling; conflicts rejected | Fixed setting or equal bounds; adjustable optimization rejected | Fixed setting or equal bounds; adjustable optimization rejected |
| `n_winding` | Unsupported | Full pairwise leakage matrix; fixed taps | Full pairwise leakage matrix; fixed taps |
| IBR/control profiles | Restricted controls, explicit projection policies | Unsupported | Static capability/filter models; profiles retained but not evaluated |
| DC tables, global time series | Unsupported | Unsupported | Unsupported |
| Geometry/wire data | No geometry compiler; electrical coefficients must be supplied | Metadata accepted; electrical coefficients required | Metadata accepted; electrical coefficients required |

The L3F component documentation is the detailed contract for its existing
operational fields and policy-specific approximations. Its extra local bank
subtypes are research extensions, not schema-valid BMOPF components.

SDP accepts only its declared fields; unknown nonempty component tables and
unsupported fields raise `SDPInapplicableError`. The input adapter retains parser
diagnostics and metadata, but dictionary acceptance is not schema validation.
See the [pinned field inventory](schema_fields.md) and [static AC model contract](sdp_static.md).

The branch-flow column is the `:matrix_kcl_v3` scope. It uses local branch and
component moments plus a conditional global voltage closure for meshes,
multiple sources, switches, multiwinding hyperedges and cross-bus LNCs. See the
[branch-flow equations, refusals and extension order](branch_flow_sdp.md).

See [fixed transformer equations and restrictions](sdp_transformers.md).
