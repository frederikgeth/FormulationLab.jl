# Independent current and voltage restrictions on power dispatch

The [shunt-boundary study](ivr_shunt_boundaries.md) verified separate line-end
current limits. This experiment asks whether a receiving-voltage bound can
restrict the same dispatch simultaneously, and whether each bound still matters
when the other is present. All inputs here are manufactured; no inherited
external feeder limit is changed or newly claimed active.

## Physical intervention and controls

Reuse the passive, coupled π-line fixture with its unequal shunts, length 0.5,
230 V source phase magnitude and 200 A line-level rating. Retain the 250 A
linecode rating, which the line-level value overrides. Three-wire receiving
terminal names remain cyclically permuted. Add the same two single-phase or
delta dispatch devices with 1.2 MVA total apparent-power capability each.
Extend only their active-power boxes to the symmetric interval already used
for reactive capability. Negative generator active power represents consumption.

For positive from-end reactive requests, tighten the receiving bus's lower
voltage bound to nominal; for negative requests, tighten its upper bound.
Nominal means 230 V phase-neutral for two wires and ``230\sqrt{3}`` V
phase-phase for three. This is an explicit physical intervention, recorded with
exact before/after records. The manifest therefore does **not** claim every
original field is preserved. Matrices, shunts, demand and source remain fixed.

Prespecify three treatments:

| Treatment | Line rating | Receiving-voltage restriction |
|:--|:--|:--|
| joint | 200 A | nominal lower or upper bound |
| wide_voltage | 200 A | original 180–260 V phase-neutral or 300–440 V phase-phase band |
| loose_current | 250 A | same nominal bound as joint |

For ``m`` native coils per device, minimize

```math
F=\sum_{s\in\{f,t\}}\sum_{k=1}^{m}
\left[\left(\frac{p_{sk}}{1000\;\mathrm W}\right)^2+
\left(\frac{q_{sk}-\sigma_sQ/m}{1000\;\mathrm{var}}\right)^2\right],
\qquad \sigma_f=1,\quad\sigma_t=-1.
```

Use total targets ``Q=\pm600`` kvar. Active-power tracking requests zero while
allowing dispatch to trade active and reactive injection to satisfy both
boundaries. Objective comparisons below are within a conductor count and
direction; the per-coil weighting does not define comparable economic costs
between the single-phase and delta panels.

Cross two conductor counts, two directions, three treatments, six retained
formulations and both Ipopt scaling policies: **144 cells**. All use the existing
per-unit units, strict solver settings, complete common physical starts and
BMOPFTools nameplate policy. No transformation or numerical default is removed.

## Results and separate restriction witnesses

All **144/144 admissions pass** optimal-status, own/full/reverse membership,
independent physical, recovered-objective and SI JSON round-trip gates. In all
48 joint cells, every conductor at the expected line end and every selected
receiving-voltage channel lies within ``10^{-5}`` of its boundary, in A and V
respectively. The opposite line end retains more than 1 A slack. Positive
targets approach the receiving current cap and lower voltage bound; negative
targets approach the sending current cap and upper voltage bound.

| Conductors | From-end Q target (kvar) | Receiving device P (kW) | Receiving device Q (kvar) | Receiving voltage (V) |
|:--|--:|--:|--:|--:|
| 2 | +600 | 21.862 | −40.473 | 230.000 |
| 2 | −600 | −22.333 | 37.526 | 230.000 |
| 3 | +600 | 65.501 | −121.465 | 398.372 |
| 3 | −600 | −67.088 | 112.529 | 398.372 |

The receiving device consumes active power for the upper-voltage cases and
produces it for the lower-voltage cases. Soft targets are not dispatch
equalities; neither opposite achieved reactive injections nor zero source
exchange is required.

| Conductors | Q target (kvar) | Joint objective | Improvement from voltage relaxation | Improvement from current relaxation |
|:--|--:|--:|--:|--:|
| 2 | +600 | 313548.257 | 6560.219 | 10796.534 |
| 2 | −600 | 316875.462 | 7088.833 | 10892.855 |
| 3 | +600 | 77762.170 | 6584.127 | 8426.936 |
| 3 | −600 | 80709.751 | 7125.051 | 8608.661 |

For every arm and policy, each relaxed solution is feasible in its own model,
has a smaller objective, and is rejected by the original joint model and
independent physical auditor. **All 48 voltage-relaxation witnesses violate
only the selected voltage-bound family; all 48 current-relaxation witnesses
violate only line-current bounds.** Conversely, each joint solution remains
feasible in both relaxed models. These witnesses establish that neither bound
is redundant on this declared dispatch problem. They do not certify global
optimality, uniqueness or multipliers.

## Signed slack and numerical proximity

Retain the existing geometric convention: a bound is labelled active only when
its signed slack is nonnegative and at most the activity tolerance. Negative
slacks remain labelled violations, even when smaller than the independent
physical acceptance tolerance. Do not clamp, discard or relabel them.

Among the 48 joint endpoints, 11 reported current-port slacks and 17 selected
voltage-channel slacks are negative. Their minima are approximately
``-2.56\times10^{-13}`` A and ``-1.14\times10^{-13}`` V. These roundoff-sized
values are retained in the raw records. Consequently, the claim common to all
cells is **simultaneous boundary proximity**, not identical strictly nonnegative
activity flags. Independent Python and Julia arithmetic can differ in the sign
of an almost-zero slack; the audit checks the signed values within numerical
tolerance and each report's classification against its own recorded value.

## Recovery and reproducibility

The independent SI export audit checks 720 line-port margins, 288 selected
voltage margins, full coupled π-line equations, complex losses, native P/Q
products and objective values. All 144 exports have matching physical and
native-device structures within each conductor count. Manifest replay reproduces
each declared intervention. Maximum voltage-drop error is below
``2.33\times10^{-13}`` V, current-balance error below ``6.05\times10^{-14}`` A,
and objective reconstruction error below ``1.17\times10^{-10}``.

Use `examples/benchmark_ivr_joint_boundaries.jl` and the self-contained
[joint-boundary tutorial](tutorial_joint_boundaries.md). The 1,985 focused
assertions cover manifests, reporting and the independent restrictions across
all arms. Protocols, initial admissions, final exports, 96 restriction
certificates, audits and validation logs remain outside Git in
`JOINT_BOUNDARY_20261006`. No timing is ranked. Active inherited shunt limits on
another valid feeder and broader transformer-connection parity remain open.
