# BMOPF component coverage

This is an implementation inventory, not a claim of complete BMOPF conformance.
The local PowerIO 0.11 source identifies 0.1.0 as the accepted schema and 0.2.0
as a proposal. The proposal revision inspected during migration is
`fe8671a74d2fc1a15a499c5b1f66cbb80fc22e12`, SHA-256
`74d6c6de3637d52e42a26c4cb0584f51df70d69f360b236cf5e23afaf7669462`.

| Fields / behavior | LinDist3Flow | BranchFlowSDP | Dense IVRSDP / IVRSOC |
|---|---|---|---|
| `bus.terminal_names`, grounding | Neutral-reduced; guarded Kron preprocessing | Explicit aligned terminals; fixed zero-voltage grounds | Explicit terminals; ideal grounds eliminated |
| `bus.v_min`, `v_max` | Retained-terminal squared-voltage bounds | Phase/all-terminal squared-voltage bounds | Lifted phase-ground squared-voltage bounds |
| `vpn_*`, `vpp_*` | Grounded-neutral alias / affine winding closure within documented domain | Unsupported | Lifted physical voltage maps |
| `vpos_*`, `vneg_max`, `vzero_max`, `vn_max` | Restricted/refused or explicitly waived by permissive policy | Unsupported | Lifted physical voltage maps |
| Line series R/X matrices and terminal maps | Fixed-reference lossless drop | Full coupled series law; complete aligned maps on a radial tree | Full coupled linear current/voltage law |
| Line `G/B_from/to` | Endpoint-shunt lowering | Unsupported | Explicit endpoint currents |
| Line/linecode `i_max`, `s_max` | Live-voltage SOC surrogate, both endpoints | Series-current and sending/receiving power limits | Lifted current and apparent power, both endpoints |
| Load `p_nom`, `q_nom`, connections | Fixed-reference channel allocation | Wye/single-phase and two-/three-terminal delta incidence with local moments | Physical incidence and channel currents |
| Load `model`, `v_nom`, ZIP/exponents | P/Z/ZP; documented projections for I/exponential | P/Z only | P/Z current/power laws; I/ZIP/exponential power-cone envelopes |
| Generator P/Q bounds, `s_max`, `i_max`, `cost` | Affine/SOC with restricted controls | Ground-referenced P/Q/S/I capability and linear cost | Coil powers and coil/terminal currents, including neutral |
| Fixed source phasors, bounds, costs | Per radial island | Exactly one complete-map source | Multiple fixed sources; grounded-source ampacity extension rejected |
| Fixed shunt G/B matrices | Affine voltage-product closure | Full bus-map moment law | Full linear current law |
| Switches, capacitors | Documented fixed-state lowering | Unsupported | Fixed-state electrical laws |
| Transformers/regulators | Single-phase, center-tap, Yd/Dy, autotransformer, open-delta; documented restrictions/lowering | Fixed two-side winding blocks: single-phase, center-tap, Yd/Dy, autotransformer and open-delta regulator | All seven subtypes, including general multiwinding; internal grounding and explicit excitation |
| `tap_ratio*` on ordinary transformers | Normalized to migrated `tap*` spelling; conflicts rejected | Fixed setting or equal bounds; adjustable optimization rejected | Fixed setting or equal bounds; adjustable optimization rejected |
| `n_winding` | Unsupported | Unsupported | Full pairwise leakage matrix; fixed taps |
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

The branch-flow column is the conservative `:radial_matrix_kcl_v2` prototype
scope, not the intended final coverage. See the [branch-flow equations,
refusals and extension order](branch_flow_sdp.md).

See [fixed transformer equations and restrictions](sdp_transformers.md).
