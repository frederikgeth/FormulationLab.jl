# Structural reduction interactions

Signed observation sharing, bounded hybrid condensation and generator-definition
reuse each preserve the physical model, but their runtime effects need not add.
This study crosses the three choices explicitly, retaining their individual
controls and full/reduced power-only baselines. It adds a benchmark composition;
production equations, defaults and every previous option remain unchanged.

## Design and interpretation

Eight factorial arms use bounded-observation lifting and cross:

- unrestricted passive blocks versus hybrid cap four;
- coefficient-exact versus signed observation sharing;
- generator power-definition reuse off versus on.

Within those eight arms, each factor changes only its named option. The sharing
comparison is **exact versus signed within bounded-observation lifting**. It does
not simultaneously turn observation lifting on. The two additional controls,
`full_powers` and `reduced_powers`, retain power lifting without bounded-observation
lifting. They measure whether a combination improves on that simpler baseline.

All profiles use assembly/dispatch units 10 kVA, power-lift units 1 kVA, support
threshold two, physical objective divisor one, nominal transformer coordinates,
composed circuit rows and voltage-ground scaling. Reduced profiles retain
conductor regions and transformer-current elimination. A cap value of four is
fixed; unrestricted profiles ignore it. Existing alternative caps, proportional
sharing and all earlier formulations remain available outside this panel.

For one factor, the conditional effect is the same-sweep treatment/control
Ipopt time ratio with the other two factors held fixed. There are four contexts
per factor and twelve conditional contrasts per scenario/workload/policy/batch
cell. Pairwise interaction uses the within-sweep ratio of ratios

```math
R_{ij\mid k}=\frac{t_{11}/t_{01}}{t_{10}/t_{00}},
```

with the third factor fixed. A value of one indicates multiplicative independence
of the observed effects in that context. Values above one mean the first factor's
time ratio increases when the second is enabled; they do not by themselves mean
that the combined formulation is slower than the baseline. Each pair has two
contexts, giving six pairwise interactions per cell. Report medians of paired
ratios separately from quotients of profile medians. No global marginal effect
or statistical-significance claim is inferred from these selected runs.

## Cases, objectives and admission

BASE265, VOLTAGE265 and URBAN1220 retain byte-identical inputs and DER/voltage
addition manifests from the [hybrid transfer study](ivr_hybrid_transfer.md).
There are 74 bounded generators in each 265-bus scenario and 268 in the urban
scenario. VOLTAGE265 keeps the explicitly added 216–242.5 V phase-neutral limits
at original load buses; these are scenario choices, not claimed statutory limits.
No source field is silently normalized or removed.

Economic cost and source P/Q tracking cross both `none` and `gradient-based`
Ipopt scaling. Tracking targets are 37 kW on the two smaller scenarios and
134 kW urban, with zero reactive exchange. The objective terms and normalization
are identical across profiles within each workload. The common physical start
is the unloaded linear-circuit solution, including all retained electrical
stamps; it is an initialization, not an extra operating constraint.

The focused suite checks the full factorial option differences and independent
option ownership. Single-phase/delta cases exercise every combination under
both objectives and solver policies. Tightened original voltage, current and
apparent-power limits must reject both physically and in the encoded model.
Source-safe runner tests verify input preservation and provenance. The initial
reuse-count test incorrectly expected one reuse per delta device; the contract
counts native power channels, so the expected count was corrected to three.
The physical acceptance and bound tests were already passing. Original logs
remain and no solver or acceptance tolerance was relaxed.

Preflight checks all 120 profile/workload/policy combinations, physical and
own/full/reverse model membership, complete starts and SI export round trips.
All cost preflights tighten a generator capability limit at the recovered point;
VOLTAGE265 cost preflights also tighten an original voltage limit. Both physical
and encoded checks must reject each witness. Active voltage slacks, actual
component caps, shared-observation factors and generator reuse counts are saved.

## Timing protocol

All profiles use MUMPS AMD, strict tolerances 1e-10 and one Julia/BLAS thread.
Each of twelve scenario/workload/policy cells has ten excluded warm-ups followed
by ten randomized cyclic sweeps, balancing candidate positions but not predecessor
pairs. Complete exploration and confirmation run in fresh Julia processes per
scenario and batch. The declared total is **2400 measured solves and 240 warm-ups**.
Only Ipopt wall time ranks admitted candidates; construction, start assignment,
extraction and audits are excluded. Tests, documentation builds, native diagnostics
and other solver work do not overlap timing. Both batches and all slow tails
remain, without pooling or selective repeats. Source snapshots precede timing.

Independent post-run checks recompute all 288 conditional contrasts and 144
pairwise interactions from raw trials, plus the selected winner/control ratios.
These comparisons identify conditional effects in the declared panel; they do
not establish a native factorization mechanism or transfer to independent feeders.

## Admission and structural results

All **2400 measured solves, 240 warm-ups and 120 preflight SI exports pass**.
The independent audit verifies source preservation, common starts, original
physical export fields, own/full/reverse membership, component graphs and all
288 conditional contrasts plus 144 interactions. All 60 tightened-capability
and 20 tightened-voltage witnesses reject in both physical and encoded checks.
Every VOLTAGE265 cost preflight has one active upper-voltage limit. Maximum
recovered-power objective discrepancy is below 1.07e-14 and within-cell objective
spread below 2.14e-14. These are numerical checks, not a proof of global optimality.

Signed sharing saves 66 real variables relative to exact sharing under blocks
on either 265-bus scenario, and 496 urban. Under cap four it saves 68 and 498,
respectively. Generator reuse removes another 148 or 536 real variables, with
74 or 268 reused native power channels. These structural counts hold across
both objectives, policies and batches. All applied observation-sharing factors
are ±1; no non-unit proportional benefit is measured.

For example, urban blocks/exact/off has 13,782 real variables, blocks/signed/off
13,286 and blocks/signed/generators 12,750. The reduced power-only control has
12,778. Thus the signed/reuse combination has fewer variables than the power-only
control, yet is slower for cost. Auxiliary count alone does not predict runtime.

## Confirmation times

Median Ipopt wall time in milliseconds; columns distinguish objective and solver scaling.
The full/reduced power-only controls are outside the eight-arm factorial.

### BASE265

| Profile | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_powers` | 45.671 | 44.805 | 26.907 | 27.024 |
| `reduced_powers` | 42.773 | 42.454 | 24.798 | 25.104 |
| `blocks_exact_off` | 43.266 | 43.314 | 25.256 | 25.801 |
| `blocks_exact_generators` | 44.853 | 44.598 | 25.121 | 25.441 |
| `blocks_signed_off` | 41.840 | 42.375 | 25.115 | 25.202 |
| `blocks_signed_generators` | 43.189 | 43.454 | 24.779 | 24.934 |
| `cap4_exact_off` | 43.155 | 42.924 | 25.424 | 25.417 |
| `cap4_exact_generators` | 43.962 | 44.173 | 25.296 | 25.565 |
| `cap4_signed_off` | 42.360 | 43.378 | 25.662 | 25.136 |
| `cap4_signed_generators` | 43.597 | 43.945 | 24.948 | 25.047 |

### VOLTAGE265

| Profile | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_powers` | 80.476 | 80.993 | 36.212 | 36.770 |
| `reduced_powers` | 75.169 | 76.936 | 33.319 | 34.460 |
| `blocks_exact_off` | 77.172 | 77.182 | 34.083 | 33.963 |
| `blocks_exact_generators` | 80.359 | 81.202 | 36.626 | 36.636 |
| `blocks_signed_off` | 74.915 | 75.482 | 34.093 | 34.407 |
| `blocks_signed_generators` | 78.156 | 78.273 | 36.550 | 36.129 |
| `cap4_exact_off` | 77.281 | 77.122 | 34.591 | 34.119 |
| `cap4_exact_generators` | 79.310 | 79.992 | 36.981 | 37.120 |
| `cap4_signed_off` | 76.484 | 75.541 | 33.437 | 34.433 |
| `cap4_signed_generators` | 77.479 | 79.137 | 36.296 | 36.225 |

### URBAN1220

| Profile | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_powers` | 245.646 | 243.475 | 115.064 | 115.911 |
| `reduced_powers` | 239.592 | 237.026 | 111.658 | 110.947 |
| `blocks_exact_off` | 247.898 | 248.562 | 115.560 | 114.666 |
| `blocks_exact_generators` | 266.759 | 268.926 | 111.405 | 110.756 |
| `blocks_signed_off` | 242.779 | 241.823 | 112.618 | 111.987 |
| `blocks_signed_generators` | 262.783 | 259.228 | 109.059 | 108.811 |
| `cap4_exact_off` | 242.663 | 245.319 | 116.070 | 115.322 |
| `cap4_exact_generators` | 265.897 | 270.550 | 111.562 | 111.618 |
| `cap4_signed_off` | 241.252 | 238.656 | 113.346 | 112.960 |
| `cap4_signed_generators` | 262.920 | 262.744 | 109.542 | 108.765 |

## Conditional effects

Each range spans the four **context-specific median paired ratios**, not a
confidence interval or the range of individual trials. Values below one favour
the named change. No averaging across contexts is performed.

| Case | Workload | Policy | Cap four / blocks | Signed / exact | Reuse / off |
|:--|:--|:--|--:|--:|--:|
| `BASE265` | `quadratic_cost` | `none` | 0.9801–1.0056 | 0.9657–0.9952 | 1.0176–1.0388 |
| `BASE265` | `quadratic_cost` | `gradient-based` | 0.9899–1.0283 | 0.9677–1.0080 | 1.0095–1.0288 |
| `BASE265` | `exchange_tracking` | `none` | 0.9962–1.0254 | 0.9861–0.9990 | 0.9665–0.9895 |
| `BASE265` | `exchange_tracking` | `gradient-based` | 0.9953–1.0069 | 0.9759–0.9850 | 0.9885–1.0088 |
| `VOLTAGE265` | `quadratic_cost` | `none` | 0.9865–1.0205 | 0.9732–0.9871 | 1.0207–1.0483 |
| `VOLTAGE265` | `quadratic_cost` | `gradient-based` | 0.9798–1.0178 | 0.9618–1.0040 | 1.0264–1.0449 |
| `VOLTAGE265` | `exchange_tracking` | `none` | 0.9893–1.0152 | 0.9749–0.9927 | 1.0629–1.0856 |
| `VOLTAGE265` | `exchange_tracking` | `gradient-based` | 1.0016–1.0196 | 0.9774–1.0055 | 1.0558–1.0905 |
| `URBAN1220` | `quadratic_cost` | `none` | 0.9824–1.0037 | 0.9751–0.9869 | 1.0813–1.0977 |
| `URBAN1220` | `quadratic_cost` | `gradient-based` | 0.9819–1.0090 | 0.9700–0.9813 | 1.0693–1.0972 |
| `URBAN1220` | `exchange_tracking` | `none` | 1.0028–1.0085 | 0.9718–0.9798 | 0.9611–0.9710 |
| `URBAN1220` | `exchange_tracking` | `gradient-based` | 0.9989–1.0118 | 0.9699–0.9792 | 0.9636–0.9722 |

## Pairwise interactions

Confirmation medians of within-sweep ratios of ratios, with the third factor
fixed as shown. Factor names specify treatment/control directions. Values near
one are compatible with small interactions and timing variation; these are
descriptive estimates without a significance claim.

| Case | Factor pair | Fixed third level | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|:--|:--|--:|--:|--:|--:|
| `BASE265` | `cap4_over_blocks × signed_over_exact` | off | 0.9996 | 1.0330 | 1.0049 | 0.9918 |
| `BASE265` | `cap4_over_blocks × signed_over_exact` | generators | 1.0280 | 1.0282 | 0.9970 | 0.9959 |
| `BASE265` | `cap4_over_blocks × reuse_on_over_off` | exact | 0.9711 | 0.9932 | 1.0113 | 1.0086 |
| `BASE265` | `cap4_over_blocks × reuse_on_over_off` | signed | 1.0152 | 0.9839 | 0.9735 | 0.9978 |
| `BASE265` | `signed_over_exact × reuse_on_over_off` | blocks | 0.9984 | 1.0116 | 0.9995 | 0.9857 |
| `BASE265` | `signed_over_exact × reuse_on_over_off` | cap4 | 1.0042 | 0.9835 | 0.9777 | 0.9886 |
| `VOLTAGE265` | `cap4_over_blocks × signed_over_exact` | off | 1.0179 | 1.0057 | 0.9733 | 0.9960 |
| `VOLTAGE265` | `cap4_over_blocks × signed_over_exact` | generators | 1.0103 | 1.0378 | 0.9993 | 0.9723 |
| `VOLTAGE265` | `cap4_over_blocks × reuse_on_over_off` | exact | 0.9807 | 0.9735 | 0.9966 | 1.0141 |
| `VOLTAGE265` | `cap4_over_blocks × reuse_on_over_off` | signed | 0.9729 | 0.9933 | 1.0434 | 0.9904 |
| `VOLTAGE265` | `signed_over_exact × reuse_on_over_off` | blocks | 1.0105 | 0.9762 | 0.9871 | 0.9847 |
| `VOLTAGE265` | `signed_over_exact × reuse_on_over_off` | cap4 | 0.9822 | 1.0124 | 1.0158 | 0.9691 |
| `URBAN1220` | `cap4_over_blocks × signed_over_exact` | off | 1.0097 | 1.0091 | 0.9964 | 0.9842 |
| `URBAN1220` | `cap4_over_blocks × signed_over_exact` | generators | 1.0019 | 0.9981 | 1.0039 | 0.9937 |
| `URBAN1220` | `cap4_over_blocks × reuse_on_over_off` | exact | 1.0085 | 1.0377 | 0.9963 | 0.9795 |
| `URBAN1220` | `cap4_over_blocks × reuse_on_over_off` | signed | 1.0074 | 1.0195 | 1.0055 | 0.9937 |
| `URBAN1220` | `signed_over_exact × reuse_on_over_off` | blocks | 0.9998 | 1.0060 | 0.9998 | 0.9960 |
| `URBAN1220` | `signed_over_exact × reuse_on_over_off` | cap4 | 0.9969 | 1.0004 | 1.0067 | 1.0094 |

## Interpretation

**Generator reuse is workload-dependent even after combining reductions.** All
urban cost contexts in both batches have reuse/off paired medians about 1.07–1.10;
iterations rise from 17 to 19. All urban tracking contexts instead favour reuse,
with paired medians about 0.95–0.98 and seven iterations throughout. On VOLTAGE265,
reuse increases cost iterations from 24 to 25 and tracking from nine to ten.
Its confirmation tracking penalty is 5.6–9.0% in matched contexts, and all four
contexts also lose in exploration. On BASE265, reuse hurts cost but helps tracking
more consistently when signed sharing is enabled. This is a stronger conclusion
than selecting a single fastest combination.

**Cap-four benefits are conditional on reuse and do not establish a universal
bundle.** On urban cost, all cap/blocks paired medians with reuse off are below
one in both batches and policies. With reuse on, all are above one. The cap/reuse
interaction medians are therefore consistently above one here: with exact sharing,
1.0374/1.0085 under no automatic scaling and 1.0094/1.0377 under gradient scaling
(exploration/confirmation). With signed sharing they are 1.0144/1.0074 and
1.0149/1.0195. These are small descriptive interactions with individual ratios
crossing one; they do not establish a statistically significant mechanism.
Cap/signed interactions are less stable. Separately observed gains should not
simply be multiplied to predict a combined result.

**Signed sharing usually reduces observation-lifting overhead; it does not
uniformly beat power-only lifting.** In urban confirmation, all matched signed/
exact ratios are below one, across both objectives, policies and reuse settings.
But cost's leading profile changes from `cap4_signed_off` in exploration to
`reduced_powers` in confirmation. Confirmation power-only medians are 239.592 and
237.026 ms, versus 241.252 and 238.656 ms for cap-four/signed/off. Their paired
ratios are approximately 1.0007 and 0.9988, illustrating why a ratio of profile
medians must not be substituted for the median of paired ratios. Retain both
cost candidates without claiming a robust gain over the power-only control.

**Urban tracking supports signed sharing plus reuse as a shortlist candidate.**
Both blocks and cap four have lower paired medians than reduced power-only in
both batches and scaling policies. For blocks, the ratios are 0.9718/0.9736 under
no automatic scaling and 0.9929/0.9830 under gradient scaling. Confirmation profile
medians improve about 2.3% and 1.9%, respectively. The cap winner changes between
batches: cap four/blocks for unscaled tracking, blocks/cap four for gradient-scaled
tracking. The latter confirmation medians differ by only 0.046 ms. This supports
keeping both cap choices, without promoting a cap-specific tracking winner.

**The smaller scenarios remain close to their power-only controls.** BASE265
confirmation favours blocks/signed/off for cost and blocks/signed/generators for
tracking, but the latter's paired ratios against reduced power-only are 1.0044
and 0.9982. Its small median-time lead is not a clear incremental tracking gain.
VOLTAGE265 cost favours blocks/signed/off in confirmation; tracking retains the
power-only control without scaling and changes from that control to blocks/exact/
off with gradient scaling. None justifies enabling reuse for constrained tracking.

Slow trials remain. For example, the confirmation urban unscaled tracking
reuse/exact-blocks trial ratios span 0.891–2.699; the corresponding cap/signed
interaction with reuse enabled spans 0.765–2.864. The study does not discard these
tails, pool batches, infer significance from a few percentages, or assert that
iteration changes account for the entire timing difference. Native derivative,
linear-system and factorization costs are not separately identified.

## Recommendation, limits and reproduction

Keep the earlier full/reduced power-only, cap-four and generator-reuse profiles.
Add signed observation sharing plus generator reuse to the urban tracking
shortlist. Cost retains reuse off; the combined cap-four/signed cost candidate
has not displaced the power-only control reliably. This panel does **not** include
every older finalist: cap-four power-only, power-only with reuse, other power
bases and non-unit proportional sharing are outside this factorial comparison.
It therefore cannot rank the signed/reuse combination against all those options
or establish a globally fastest formulation. Defaults remain unchanged.

The two 265-bus scenarios share a feeder; the urban scenario is a previously used
case. There is no new held-out feeder, active urban voltage validation, mixed
IBR/nonlinear-load objective transfer or non-unit transformer-sharing experiment.
Correctness tests cover a wider domain than this timing panel. Original-network
preprocessing/reconstruction coverage remains a separate roadmap item.

[Tutorial section 44](tutorial_exact_ivr.md) executes all ten profiles on a delta
chain. `examples/benchmark_ivr_structural_interactions.jl` exposes `profiles` and
`benchmark`, preserving the source-safe runner and complete admission reports.
Protocol, frozen source, raw JSON, SI exports, all audit scripts and planning
artifacts are stored outside Git in `STRUCTURAL_INTERACTIONS_20261006`.

Next, construct a physical transformer fixture that actually activates a non-unit
exact sharing factor and checks both original winding limits and native powers.
Then broaden the retained shortlist to independent feeders and mixed device
workloads. Any direct comparison with earlier power-only/reuse finalists needs
a new common timing panel; timings from separate campaigns should not be spliced
into a definitive ranking.

The subsequent [physical transformer study](ivr_nonunit_transformers.md)
demonstrates non-unit winding sharing and checks its lifting-threshold tradeoff.
Broader feeder transfer and the common finalist comparison remain open.
