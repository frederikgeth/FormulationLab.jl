# Multiwinding nominal coordinates

## Motivation and declared contract

The existing `transformer_scaling=:nominal` propagates ordinary transformer
ratios but skips multiwinding devices. In the manufactured network family,
this leaves 115 V, 57.5 V and 28.75 V secondary regions at the 2300 V assembly
base. The opt-in `:nominal_multiwinding` policy adds a nominal units convention
for these devices. It preserves the existing policy, physical model and defaults.
This is a numerical coordinate experiment, not a network approximation.

Let ``U_k`` be the declared coil nominal `v_nom` of winding ``k``. Define its
characteristic voltage unit

```math
h_k=\begin{cases}
U_k,&\text{WYE or SINGLE\_PHASE},\\
U_k/\sqrt{3},&\text{DELTA}.
\end{cases}
```

The nominal-base graph connects winding 1 to winding ``k`` with ratio
``h_k/h_1``. For a balanced delta, ``U_k/\sqrt{3}`` is the phase-equivalent
magnitude. For unbalanced or corner-grounded circuits it remains a declared
characteristic unit: it is **not** a claim about an actual conductor-to-ground
voltage. A single-phase unit uses its coil nominal without a three-phase factor.
Taps, delta roll, winding resistance, pair leakage and excitation remain in
the physical equations. No phase rotation or neutral connection is inferred.

Every winding unit and ratio must be positive and finitely invertible before
any edge of that device is installed. Invalid contracts skip the whole device.
Inconsistent nominal cycles or source magnitudes retain the global base for
the affected connected component. Components without a nonzero source anchor
also retain the global base. Diagnostics record these reasons in
`transformer_scaling_report`. An assignment failure is not an infeasibility
certificate for the physical circuit.

## Equivalence and composition

For assembly units ``V_b,S_b``, assigned local voltage unit ``V_r`` and regional
current-power unit ``S_r``, the additional diagonal factors are

```math
y_V=(V_b/V_r)z_V,\qquad
y_I=(V_r/V_b)(S_b/S_r)z_I.
```

If the preceding maps are ``z=Ry`` and ``y=Pz``, applying an invertible diagonal
matrix ``D`` gives reconstruction ``RD^{-1}`` and projection ``DP``.
Substitution preserves the original feasible set and every original observation
and bound in exact arithmetic. A retained coordinate is scaled only when all
original coordinates in its support agree on one factor. Mixed or unclassified
coordinates retain their preceding scale. Nonrepresentable floating-point map
coefficients reject the entire coordinate intervention.

The policy does not change P/Q dispatch, auxiliary power or objective units.
`current_power_bases` is supported with either nominal policy and still propagates
only through lines and closed switches. Composed row normalization responds to
the changed columns. The optional [KCL row cap](ivr_kcl_residuals.md) is a separate
factor; neither intervention replaces the independent SI acceptance audit.

`ground_scaling=:regional_voltage` deliberately retains its independent
ordinary-transformer base policy. Enabling multiwinding coordinates does not
silently change finite-ground multipliers. The separate opt-in
[`ground_scaling=:regional_multiwinding_voltage`](ivr_nwinding_ground.md) now
provides that extension, with its own finite-ground controls.

A floating delta illustrates the distinction between units and physical
references. Adding the same complex voltage to its three terminals leaves coil
voltages and winding physics unchanged. The base graph may assign a unit, but
the existing no-load initializer still refuses an unresolved common-mode degree
of freedom. This policy does not expand that initialization domain.

## Reproducible usage

```@example multiwinding_units
using FormulationLab
options = IVRNLPOptions(
    transformer_scaling=:nominal_multiwinding,
    row_scaling=:composed,
    kcl_row_max_base=1000.0,
    current_power_bases=Dict("lv"=>1000.0),
)
@assert options.transformer_scaling == :nominal_multiwinding
@assert options.kcl_row_max_base == 1000.0
nothing # hide
```

Use actual bus IDs for current-power seeds. On a network `net`, build with
`build_opf(net, IVRNLP(options); optimizer=Ipopt.Optimizer)`. Inspect
`build.numerical_diagnostics[:transformer_scaling_report].bases` before solving;
a requested policy does not guarantee every coordinate can be scaled.
For a controlled comparison, clone the options and change only
`transformer_scaling` between `:nominal` and `:nominal_multiwinding`. Encode the
same SI start through `ivr_nlp_point_report` for each build. After solving,
check physical residuals, membership in the unreduced model, objective agreement
and JSON recovery, as in the [exact-IVR tutorial](tutorial_exact_ivr.md).

The tracked `examples/benchmark_ivr_nwinding_coordinates.jl` provides four
factorial arms: the two nominal policies crossed with uncapped/1000 A KCL row
units. It fixes assembly/grid current-power units at 100 kVA, primary and
secondary current-power seeds at 1 kVA, generator units at 1 kVA, auxiliary
power units at 500 VA and objective divisor at one. The 24 cells cross 2/8/24
units, cost/tracking objectives and four existing current/lifting representations.

Each batch uses one excluded warmup and eight measured solves per arm, with
balanced positions and immediate predecessors. Confirmation reverses the
schedule in a fresh process. Two batches total 1536 measured solves and 192
excluded warmups. `run(folder, batch; preflight_only=true)` records just the
96 warmup endpoints, without a ranking. The caller must establish isolation
for the entire timing campaign. Failed endpoints and contaminated campaigns
remain recorded but cannot enter a speed ranking. Only Ipopt optimizer-call
wall time is the performance metric; compilation has no penalty.

## Verification scope

The regression covers all four mixed connection patterns in a live four-unit
network, both power objectives, explicit/eliminated multiwinding currents and
power/bounded-observation lifting. Checks include unchanged physical equations
and model dimensions, mutual coordinate maps, supplied SI starts, independent
winding equations, original current and apparent-power bound violations,
full-model membership and SI JSON round trips. Single-phase WYE and explicit
SINGLE_PHASE windings have an analytical power-dispatch optimum in both flow
directions. Graph tests cover conflicting cycles, source disagreement, absent
anchors, tap/roll independence and atomic invalid-device fallback.

These tests establish correspondence on their declared fixtures. They do not
establish external-feeder coverage or a general speed advantage. The legacy
nominal policy and all current-elimination/lifting choices remain available.

## Manufactured-network evidence, 6 October 2026

A matched 96-case panel held the 1000 A KCL cap fixed and changed only
`transformer_scaling`. Cases crossed 2/8/24 units, both power objectives, four
current/lifting representations and primary/secondary current-power seeds of
1/100 kVA. All **96/96** new endpoints passed the unchanged acceptance gates.
Relative to the preceding capped ordinary-only controls, iterations decreased
in 85 cases and were unchanged in 11; none increased. Maximum objective
difference was ``2.44\times10^{-10}``. Variable counts and recovered SI JSON
schemas were identical. Independent reconstruction of all 96 exports gave
maximum KCL residual ``1.83\times10^{-11}`` A (rounded upward); all 96 exports
also agreed through the FormulationLab and BMOPFTools readers.

For 24 units with primary and secondary current-power seeds both at 1 kVA:

| Objective | Current representation and lifting | Ordinary-only iterations | Multiwinding iterations |
|:--|:--|--:|--:|
| Cost | Explicit, powers | 27 | 25 |
| Cost | Explicit, bounded observations | 26 | 25 |
| Cost | Eliminated, powers | 29 | 25 |
| Cost | Eliminated, bounded observations | 28 | 25 |
| Tracking | Explicit, powers | 22 | 20 |
| Tracking | Explicit, bounded observations | 22 | 20 |
| Tracking | Eliminated, powers | 30 | 21 |
| Tracking | Eliminated, bounded observations | 26 | 20 |

A separate 96-endpoint preflight exercised the four-arm coordinate/cap runner
at fixed 1 kVA primary/secondary current-power seeds:

| Nominal policy | KCL cap | Admitted endpoints |
|:--|:--|--:|
| Ordinary only | None | 22/24 |
| Ordinary only | 1000 A | 24/24 |
| Multiwinding | None | 24/24 |
| Multiwinding | 1000 A | 24/24 |

The two rejected ordinary-only uncapped endpoints are the previously observed
8- and 24-unit tracking cases with eliminated currents and power lifting.
Both remain recorded. The new nominal policy passed those cases without the
cap, but this finite panel does not make the cap redundant in general.
Nor does it establish whether combining the interventions is faster.

These are correctness and convergence observations, **not eligible wall-time
measurements**: the runs overlapped other computation. The next performance
step is the declared balanced factorial under whole-campaign isolation.
No default or best-evidence timing recommendation is changed by iteration
counts alone. External multiwinding feeder transfer remains untested.

## Isolated timing attempt and residual follow-up

The first isolated coordinate/cap campaign completed 16 exploration cells before
the two-second process monitor detected an external Julia workload. It interrupted
only its own benchmark session. Confirmation did not run. The **entire campaign**,
including completed cells, is excluded from speed claims and preserved in
`NWINDING_COORDINATE_TIMING_20261006`. No timing recommendation changes.

The subsequent [physical-row trace](ivr_circuit_residuals.md) compares retained
and implied voltage/current equations. It supports reduced normalization
amplification under the new nominal policy, while explicitly distinguishing
convergence evidence from an eligible wall-time comparison.
