# Physical non-unit transformer sharing

The [affine-sharing study](ivr_affine_sharing.md) verified general proportional
certificates, but its timed cases only activated factors ±1. This study supplies
physical transformer cases with non-unit factors and distinguishes successful
sharing from a useful numerical formulation. No production equation, default or
previous transformation option changes.

## Physical identity and motivating example

Consider a single-phase two-winding transformer with nominal ratio
``n=V_{\mathrm{nom,from}}/V_{\mathrm{nom,to}}``, series leakage and no extra
magnetizing branch. Native terminal currents enter the device on both sides.
The winding current balance gives

```math
i_{\mathrm{to}}=-n\,i_{\mathrm{from}}.
```

With a ratio-eight transformer, two bounded current observations can therefore
use one complex auxiliary, with reconstruction factor −8. Reversing the ports
gives −1/8. Both factors are exactly representable in binary floating point.
Leakage changes the voltage relation and losses; it does not remove this winding
current identity. Both original current ratings remain: the to-side magnitude
uses the reconstructed factor, and native powers retain their original voltage,
orientation and current. Neither rating is silently discarded.

The compiler does not accept this identity merely because nominal ratings look
proportional. It compares every composed real/imaginary coefficient and constant
as an exact binary rational and requires an exactly representable reconstruction
factor. The [existing proof and refusal rules](ivr_theory.md) still apply.

There is a second decision: whether to lift these observations at all. A simple
complex current coordinate has two real variables. Support threshold two leaves
it direct; threshold zero materializes it. Thus a non-unit sharing opportunity
can appear only after additional lifting. A speedup over that more heavily lifted
control need not beat a formulation which never introduced the extra variables.
This distinction motivates the threshold and power-only controls below.

## Cases and controlled profiles

Each manufactured case has eight parallel single-phase branches, two transformers
per branch and six two-wire line sections after the second transformer: 65 buses
and 16 transformers. Each branch has a 2 kW constant-power load, a bounded DER
with 0–4 kW and ±1 kvar dispatch, a 5 kVA capability limit, and a finite 2 Ω
terminal neutral ground. Total feeder phase/neutral resistance per branch is
0.2/0.3 Ω, independent of segmentation. Voltage, line-current, generator and
transformer limits are retained in every profile.

- `UNIT_IDEAL`: two 1:1 ideal transformers, with loose winding limits. This is an
  inactive control for **transformer non-unit sharing**, not for all proportional
  observations: finite-ground neutral voltages can also be proportional.
- `MV_IDEAL_FROM`: two 8:1 ideal transformers, 14.72 kV → 1.84 kV → 230 V.
  The downstream from-winding current rating is 1150 VA divided by that winding's
  nominal voltage.
- `MV_LEAKY_REVERSED_TO`: the same nominal levels, nonzero referred R/X leakage,
  reversed transformer ports, and the downstream to-winding rating set by the same
  nominal rule. Before port reversal, each transformer's from-winding leakage is
  ``(0.01+j0.005)n^2`` Ω and to-winding leakage is ``0.01+j0.005`` Ω.

These are declared physical stress cases, not representative feeder samples.
Differences between cases do not isolate leakage, orientation or voltage level.

Eight profiles retain `full_powers` and `reduced_powers`, plus bounded-observation
lifting with exact, signed and proportional sharing at thresholds two and zero.
Within the six observation arms, only sharing and threshold differ. All profiles
use assembly/dispatch units 10 kVA, lift units 1 kVA, objective divisor one,
nominal transformer coordinates, composed rows and voltage-ground scaling.
Reduced profiles use conductor regions, unrestricted passive blocks and
transformer-current elimination; generator-definition reuse stays off.

Economic cost and source P/Q tracking cross `none` and `gradient-based` Ipopt
scaling. Tracking targets 4 kW total active import and zero reactive exchange.
The power objective terms follow the [existing external objective definition](ivr_objectives.md).
The same unloaded linear-circuit physical start is completely encoded in every
model. Solver settings are MUMPS AMD, strict tolerances 1e-10 and one Julia/BLAS
thread. Electrical units and Ipopt automatic scaling are separate choices.

## Physical and numerical admission

The focused suite passes **5143 assertions**. It exercises both orientations,
ideal and leaky transformers, both objectives and scaling policies, original
current limits on both winding sides, interior neutral/phase-neutral voltage
limits, native physical powers, SI JSON fields and round trips, and live load/
generator updates. An independent ideal-cascade calculation verifies fixed-DER
source power and line currents. The initial analytical test constructed profiles
after fixing dispatch, triggering the benchmark's intended dispatch-freedom
guard. Constructing profiles before that analytical restriction corrected the
test; the guard and all physical tolerances remain unchanged. Original logs remain.

All **96 preflight solves and SI exports** pass physical, own/full/reverse model
membership and complete-start checks. All **384 tightened winding-current** and
**96 tightened neutral-voltage** witnesses reject both physically and in the
encoded formulation. In both constrained cases, cost activates the declared
downstream winding bound on every branch. Tracking is a separate workload.

A named-port audit checks the actual from/to observation rows and whether their
lifted expressions use the same auxiliary variables. This distinguishes winding
sharing from other matches. Every cached observation is also checked at three
arbitrary coordinate assignments, with auxiliary definitions populated in order;
these assignments test graph identities, not physical feasibility. The reported
maximum relative error is zero on this preflight panel.

## Timing protocol

Two complete batches run in fresh Julia processes per case/batch. Each of twelve
case/objective/policy cells has eight excluded warm-ups and eight randomized
cyclic sweeps. There are **1536 measured solves and 192 warm-ups**. Candidate
positions are balanced, predecessor pairs are not. Frozen source and physical
inputs precede timing. Only Ipopt wall time ranks accepted profiles; construction,
start assignment, extraction and audits are excluded. Tests, documentation,
other solver jobs and native diagnostics do not overlap timing. Both batches
and every slow trial remain, without pooling or selective reruns.

Within each cell, same-sweep paired ratios compare signed/exact and proportional/
signed at each threshold, threshold zero/two for each sharing rule, and
proportional threshold-zero/reduced-power-only: eight contrasts per cell and
192 across both batches. Ratios below one favour the numerator. Their medians
are not generally quotients of profile medians. No population significance or
native factorization mechanism is inferred from these selected experiments.

## Admission results

All **1536 measured solves and 192 warm-ups pass**, in addition to the 96
preflights. The independent audit verifies all 192 declared timing contrasts,
source hashes, original physical export fields, complete common starts, own/full/
reverse membership, named winding factors and sharing reports. Maximum recovered-
power objective discrepancy is below 3.34e-15; within-cell spread below 1.78e-15.
All **44,280 arbitrary-coordinate identity evaluations** pass. The source-safe
runner adds an empty `_meta.detached_legacy_provenance` dictionary to its sidecar;
the audit verifies that exact addition and otherwise requires identical input
fields. The original input files remain unchanged.

## Structural counts

### Variables

Real variable counts are constant across the tested objectives, policies and batches.

| Profile | UNIT_IDEAL | MV_IDEAL_FROM | MV_LEAKY_REVERSED_TO |
|:--|--:|--:|--:|
| `full_powers` | 550 | 550 | 550 |
| `reduced_powers` | 198 | 198 | 198 |
| `exact_t2` | 294 | 294 | 294 |
| `signed_t2` | 294 | 294 | 294 |
| `proportional_t2` | 294 | 294 | 294 |
| `exact_t0` | 538 | 602 | 602 |
| `signed_t0` | 474 | 506 | 506 |
| `proportional_t0` | 394 | 394 | 394 |

### Named winding activation

Counts below refer to `proportional_t0`. Other non-unit observations can include
neutral voltages; they must not all be attributed to transformer ratios.

| Case | Non-unit shared observations | Shared non-unit winding pairs | Variables saved versus signed t0 |
|:--|--:|--:|--:|
| `UNIT_IDEAL` | 40 | 0 | 80 |
| `MV_IDEAL_FROM` | 72 | 16 | 112 |
| `MV_LEAKY_REVERSED_TO` | 72 | 16 | 112 |

## Confirmation times

Median Ipopt wall milliseconds, excluding warm-ups. Construction costs do not rank.

### UNIT_IDEAL

| Profile | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_powers` | 6.258 | 6.232 | 4.798 | 4.827 |
| `reduced_powers` | 5.221 | 5.206 | 3.975 | 4.010 |
| `exact_t2` | 5.118 | 5.080 | 3.874 | 3.872 |
| `signed_t2` | 5.121 | 5.072 | 3.890 | 3.877 |
| `proportional_t2` | 5.170 | 5.072 | 3.891 | 3.878 |
| `exact_t0` | 5.609 | 5.595 | 4.266 | 4.302 |
| `signed_t0` | 5.605 | 5.594 | 4.269 | 4.326 |
| `proportional_t0` | 5.355 | 5.304 | 4.061 | 4.064 |

### MV_IDEAL_FROM

| Profile | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_powers` | 8.400 | 8.437 | 5.250 | 5.208 |
| `reduced_powers` | 6.980 | 6.919 | 4.305 | 4.264 |
| `exact_t2` | 6.920 | 6.952 | 4.244 | 4.269 |
| `signed_t2` | 6.914 | 6.942 | 4.231 | 4.233 |
| `proportional_t2` | 6.896 | 6.966 | 4.251 | 4.330 |
| `exact_t0` | 7.749 | 7.763 | 4.843 | 4.951 |
| `signed_t0` | 7.585 | 7.582 | 4.722 | 4.761 |
| `proportional_t0` | 6.998 | 7.043 | 4.360 | 4.421 |

### MV_LEAKY_REVERSED_TO

| Profile | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_powers` | 8.554 | 8.475 | 5.234 | 5.262 |
| `reduced_powers` | 7.826 | 7.802 | 4.813 | 4.760 |
| `exact_t2` | 7.181 | 7.236 | 4.374 | 4.400 |
| `signed_t2` | 7.219 | 7.236 | 4.393 | 4.387 |
| `proportional_t2` | 7.200 | 7.244 | 4.403 | 4.423 |
| `exact_t0` | 8.176 | 8.197 | 5.198 | 5.151 |
| `signed_t0` | 7.796 | 7.809 | 4.908 | 4.907 |
| `proportional_t0` | 7.360 | 7.271 | 4.604 | 4.576 |

## Paired sharing contrasts

Each entry is a median of eight same-sweep ratios. E/C denotes exploration/
confirmation; batches stay separate. Values below one favour proportional sharing.

| Case | Workload | Policy | Prop/signed t2 E | Prop/signed t2 C | Prop/signed t0 E | Prop/signed t0 C | Prop t0/powers E | Prop t0/powers C |
|:--|:--|:--|--:|--:|--:|--:|--:|--:|
| `UNIT_IDEAL` | `quadratic_cost` | `none` | 1.0026 | 1.0210 | 0.9431 | 0.9503 | 1.0180 | 1.0255 |
| `UNIT_IDEAL` | `quadratic_cost` | `gradient-based` | 0.9983 | 0.9896 | 0.9480 | 0.9439 | 1.0182 | 1.0229 |
| `UNIT_IDEAL` | `exchange_tracking` | `none` | 0.9964 | 1.0031 | 0.9471 | 0.9519 | 1.0231 | 1.0183 |
| `UNIT_IDEAL` | `exchange_tracking` | `gradient-based` | 0.9822 | 1.0026 | 0.9554 | 0.9456 | 1.0222 | 1.0174 |
| `MV_IDEAL_FROM` | `quadratic_cost` | `none` | 1.0039 | 0.9982 | 0.9241 | 0.9243 | 1.0071 | 1.0001 |
| `MV_IDEAL_FROM` | `quadratic_cost` | `gradient-based` | 0.9880 | 0.9981 | 0.9254 | 0.9292 | 1.0195 | 1.0182 |
| `MV_IDEAL_FROM` | `exchange_tracking` | `none` | 0.9967 | 0.9954 | 0.9233 | 0.9287 | 1.0357 | 1.0140 |
| `MV_IDEAL_FROM` | `exchange_tracking` | `gradient-based` | 0.9982 | 1.0250 | 0.9254 | 0.9302 | 1.0393 | 1.0359 |
| `MV_LEAKY_REVERSED_TO` | `quadratic_cost` | `none` | 1.0023 | 0.9982 | 0.9387 | 0.9385 | 0.9395 | 0.9397 |
| `MV_LEAKY_REVERSED_TO` | `quadratic_cost` | `gradient-based` | 1.0017 | 1.0033 | 0.9373 | 0.9298 | 0.9463 | 0.9300 |
| `MV_LEAKY_REVERSED_TO` | `exchange_tracking` | `none` | 1.0004 | 0.9991 | 0.9301 | 0.9372 | 0.9638 | 0.9526 |
| `MV_LEAKY_REVERSED_TO` | `exchange_tracking` | `gradient-based` | 1.0021 | 1.0019 | 0.9324 | 0.9320 | 0.9790 | 0.9651 |

## Threshold contrasts

Confirmation paired medians for threshold zero/two, holding sharing fixed.
Values above one mean that lifting the simpler observations was slower.

| Case | Workload | Policy | Exact t0/t2 | Signed t0/t2 | Proportional t0/t2 |
|:--|:--|:--|--:|--:|--:|
| `UNIT_IDEAL` | `quadratic_cost` | `none` | 1.1076 | 1.1017 | 1.0329 |
| `UNIT_IDEAL` | `quadratic_cost` | `gradient-based` | 1.1019 | 1.1031 | 1.0576 |
| `UNIT_IDEAL` | `exchange_tracking` | `none` | 1.0997 | 1.0966 | 1.0380 |
| `UNIT_IDEAL` | `exchange_tracking` | `gradient-based` | 1.1096 | 1.1168 | 1.0416 |
| `MV_IDEAL_FROM` | `quadratic_cost` | `none` | 1.1268 | 1.0953 | 1.0153 |
| `MV_IDEAL_FROM` | `quadratic_cost` | `gradient-based` | 1.1145 | 1.0910 | 1.0086 |
| `MV_IDEAL_FROM` | `exchange_tracking` | `none` | 1.1461 | 1.1111 | 1.0317 |
| `MV_IDEAL_FROM` | `exchange_tracking` | `gradient-based` | 1.1643 | 1.1231 | 1.0259 |
| `MV_LEAKY_REVERSED_TO` | `quadratic_cost` | `none` | 1.1379 | 1.0875 | 1.0187 |
| `MV_LEAKY_REVERSED_TO` | `quadratic_cost` | `gradient-based` | 1.1320 | 1.0786 | 1.0031 |
| `MV_LEAKY_REVERSED_TO` | `exchange_tracking` | `none` | 1.1858 | 1.1150 | 1.0484 |
| `MV_LEAKY_REVERSED_TO` | `exchange_tracking` | `gradient-based` | 1.1681 | 1.1148 | 1.0374 |

## Interpretation

**Physical non-unit sharing is now demonstrated.** At threshold zero,
`proportional_t0` shares all 16 named winding pairs on each MV case, with factors
−8 or −1/8 according to orientation. Both original winding limits still reject
violating physical points. Leakage, reversed ports, native powers and SI exports
remain valid. The unity case has zero non-unit winding pairs but 40 other non-unit
observation matches. Thus a non-unit match count alone is not evidence of a
transformer mechanism. Proportional sharing saves 80 real variables versus signed
sharing in the unity case and 112 in each MV case.

**Proportional sharing helps once simple observations are lifted.** At threshold
zero, every paired-median proportional/signed comparison favours proportional
sharing in both batches, objectives and scaling policies. Ratios span
0.9431–0.9554 for unity, 0.9233–0.9302 for ideal MV, and 0.9298–0.9387 for leaky
reversed MV: roughly 4.5–7.7% lower time. Every individual pair favours proportional
sharing in the first two cases; one leaky-case pair slightly exceeds one. This
is a selected-case benefit of the broader exact matching rule, including both
winding and non-winding observations. The panel does not isolate a pure winding-
only timing contribution.

**Lowering the lifting threshold does not win this panel.** Every proportional
threshold-zero/two paired median is above one across both batches. The ranges
are 1.0329–1.0598, 1.0044–1.0431 and 1.0031–1.0484 for unity, ideal MV and leaky
reversed MV, respectively. Non-unit sharing recovers some extra lifting cost but
does not make the lower threshold faster here. The proportional threshold-zero
model still has 394 real variables, versus 294 at threshold two and 198 for
reduced power-only. No automatic threshold change is warranted.

**The power-only comparison depends on the physical case.** All proportional-
threshold-zero/power-only paired medians exceed one on unity and ideal MV
(1.0174–1.0255 and 1.0001–1.0393). On leaky reversed MV they are instead below one
(0.9300–0.9790), so this heavily lifted/shared model does beat the simpler control
there. However, threshold-two observation lifting remains faster. This distinction
prevents a true improvement against one baseline from becoming an unsupported
claim of the fastest formulation.

**Threshold-two sharing labels do not identify different formulations here.**
Exact, signed and proportional modes have no shared observations at that threshold.
An additional untimed audit compares serialized MOI constraints/objective and
coordinate maps for all twelve case/objective/policy cells. They are identical.
Winner-label changes among those three profiles therefore do not demonstrate a
sharing effect; they sample the same emitted algebra under different labels.
Their repeated timing variation is retained, including an ideal-MV tracking
confirmation proportional/signed ratio as large as 1.225 in one trial.

Iteration counts are identical across all eight profiles within every one of
24 cells: unity cost/tracking uses ten/seven; both MV cases use fourteen/eight.
Thus different iteration counts do not explain these effects. The experiment
does not separate derivative evaluation, linear-system assembly or factorization
costs. Individual ratios can cross one despite consistent median directions;
all tails remain and no significance, native-mechanism or global-optimality claim
is made.

## Recommendation and next work

Retain proportional sharing as a verified optional graph reduction. It now has
physical non-unit activation and matched timing evidence when simple observations
are lifted, including active original winding limits. Keep support threshold two
as the starting candidate for these cases; do not lower it solely to activate
more sharing. Preserve full/reduced power-only controls and every older option.
The leaky-case results also reinforce that fewer variables need not solve faster.

This manufactured single-phase panel is not independent-feeder or three-phase
non-unit timing evidence. It does not compare generator reuse, regional power
bases, alternative caps or all previous finalists. Broader mixed IBR/nonlinear-
load workloads and original-network reconstruction parity remain separate work.
The next useful step is transfer to an independent feeder with a declared power
objective and meaningful active limits, retaining the current shortlist.

[Tutorial section 45](tutorial_exact_ivr.md) executes the named winding audit.
`examples/benchmark_ivr_nonunit_transformers.jl` provides the physical case factory,
matched profiles, source-safe runner and untimed observation audit. Protocol,
frozen source, raw JSON, SI exports, analytical and rejection checks, audit scripts
and planning documents remain outside Git in `NONUNIT_TRANSFORMER_20261006`.
