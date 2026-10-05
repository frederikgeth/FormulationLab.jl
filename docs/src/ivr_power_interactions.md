# Interactions between dispatch units, lifted units and generator reuse

This experiment asks whether individually promising changes can be combined.
Independent scaling and exact generator reuse preserve the physical feasible
set, but they change different coordinates and equations in the solver model.
A speedup observed for one factor need not survive a change in another factor.

## Mathematical controls

Let ``S_b`` denote the fixed assembly power base, ``S_g`` a generator dispatch
base and ``S_l`` the lifted-power base. Native generator dispatch uses
``S_g(p_g+\mathrm{i}q_g)`` in SI units. A separate power lift ``z`` satisfies
``(S_l/S_b)z=u\overline{i}`` in assembly coordinates. Generator reuse replaces an
exactly matching native voltage/current power observation by
``(S_g/S_b)(p_g+\mathrm{i}q_g)``. The generator defining equation and all original
ratings remain. Consequently, when reuse is enabled, ``S_l`` no longer scales
those removed generator auxiliaries; it still scales the remaining power lifts.
See the [coordinate proof](ivr_theory.md) and [API contract](ivr_nlp.md).

The eight reduced arms cross three binary factors:

| Factor | Control | Treatment |
|:--|:--|:--|
| Generator dispatch units | 10 kVA | 100 kVA |
| Lifted-power units | 10 kVA | 1 kVA |
| Exact native generator reuse | `:off` | `:generators` |

The assembly base is always 10 kVA. All reduced arms use conductor regions,
passive blocks, transformer-current elimination, nominal transformer voltage
coordinates, composed rows, voltage-ground scaling and exact affine sharing.
There are no regional current-base overrides. Full unlifted IVR at 10 kVA and
reduced unlifted IVR with dispatch at 100 kVA are explicit controls. All arms
retain the same physical objective with divisor one. No package default changes.

## Scenarios and protocol

The inputs are unchanged copies of the [previous finalist scenarios](ivr_objectives.md#Matched-finalists-and-external-transfer-—-6-October-2026):
BASE265 with 74 DERs; VOLTAGE265 with the same DERs and explicitly added
216–242.5 V phase-neutral bounds at original load buses; and URBAN1220 with 268
DERs and four transformers. All original equipment fields, source hashes and
addition manifests are retained. The voltage additions define a new OPF; they
are neither equivalent preprocessing nor a statement of statutory limits.

Economic cost and source-exchange tracking retain their previous physical
coefficients. Tracking targets are 37 kW and 134 kW, respectively, with zero
reactive exchange. Solver policies `none` and `gradient-based` are separate
panels. MUMPS AMD, one Julia/BLAS thread, strict ``10^{-10}`` solver tolerances
and the complete unloaded physical start remain fixed.

`examples/benchmark_ivr_power_interactions.jl` measures ten sweeps after ten
excluded warm-ups per scenario/objective/policy cell. Randomized cyclic orders
put each profile in each position once; predecessor pairs are not balanced.
A complete second batch runs in fresh processes per case. Only Ipopt wall time
ranks candidates, excluding construction, extraction and audits. No timing
campaign overlaps tests, documentation builds or diagnostics. Raw failures and
tails are retained; batches are not pooled.

## Conditional effects and interactions

For a factor at fixed settings of the other two factors, report the median of
same-sweep ratios ``t_{\mathrm{treatment}}/t_{\mathrm{control}}``. Ratios below one
favour the treatment. This gives twelve conditional contrasts per panel.
For two factors with binary levels ``a,b``, the interaction statistic is

```math
I_s=\frac{t_{11,s}/t_{01,s}}{t_{10,s}/t_{00,s}},
```

with the third factor fixed and ``s`` identifying the sweep. Report its median
and full range, calculated from the within-sweep ratios. A value near one means
little observed multiplicative interaction in that panel; it is not a statistical
null test. Percentages from independently measured winners must not be added.
The full factorial does not identify a native factorization or conditioning
mechanism and does not establish a universal scaling prescription.

## Confirmation results

All **2400 measured solves, 240 excluded warm-ups and 120 separate preflight
solves** pass physical, own/full-model, reverse-membership and objective checks.
The preflight SI JSON exports round-trip with identical physical quantity fields.
Six tightened capability limits and two tightened voltage limits reject the
solved endpoints independently and algebraically. The constrained cost case has
one active voltage upper bound in every preflight profile. Input/source hashes,
actual coordinate bases, reuse counts and complete starts agree with the frozen
protocol. Maximum recovered-power objective discrepancy is below ``4.98\times10^{-14}``; within-cell objective spread is below ``3.59\times10^{-13}``.

The following are **confirmation medians of Ipopt wall time in milliseconds**.
Columns separate cost/tracking and `none`/`gradient-based` solver scaling. Names
encode dispatch base, lift base and generator reuse; all bases in names are kVA.
All raw sweeps and separate exploratory results remain in the external evidence
record `POWER_INTERACTIONS_20261006`. Absolute times are not pooled across batches.

### BASE265

| Profile | Cost: none | Cost: gradient | Tracking: none | Tracking: gradient |
|:--|--:|--:|--:|--:|
| `full_10k` | 50.106 | 50.401 | 25.594 | 25.750 |
| `reduced_dispatch_100k` | 40.898 | 41.278 | 24.139 | 26.660 |
| `dispatch_10k_lifts_1k_off` | 40.352 | 40.325 | 23.882 | 23.825 |
| `dispatch_10k_lifts_1k_generators` | 41.227 | 41.447 | 23.478 | 23.579 |
| `dispatch_10k_lifts_10k_off` | 45.281 | 45.354 | 24.047 | 24.149 |
| `dispatch_10k_lifts_10k_generators` | 40.753 | 41.077 | 23.440 | 23.523 |
| `dispatch_100k_lifts_1k_off` | 40.801 | 41.152 | 23.941 | 24.024 |
| `dispatch_100k_lifts_1k_generators` | 51.728 | 51.847 | 28.252 | 28.121 |
| `dispatch_100k_lifts_10k_off` | 41.353 | 41.571 | 24.116 | 26.586 |
| `dispatch_100k_lifts_10k_generators` | 51.529 | 51.756 | 23.233 | 25.460 |

### VOLTAGE265

| Profile | Cost: none | Cost: gradient | Tracking: none | Tracking: gradient |
|:--|--:|--:|--:|--:|
| `full_10k` | 86.935 | 87.237 | 34.790 | 42.516 |
| `reduced_dispatch_100k` | 80.912 | 80.661 | 37.651 | 45.675 |
| `dispatch_10k_lifts_1k_off` | 71.906 | 71.998 | 31.911 | 33.689 |
| `dispatch_10k_lifts_1k_generators` | 75.433 | 74.959 | 34.484 | 35.774 |
| `dispatch_10k_lifts_10k_off` | 79.895 | 79.265 | 32.256 | 38.893 |
| `dispatch_10k_lifts_10k_generators` | 74.302 | 74.449 | 31.460 | 37.498 |
| `dispatch_100k_lifts_1k_off` | 75.241 | 75.260 | 37.364 | 38.675 |
| `dispatch_100k_lifts_1k_generators` | 82.218 | 81.635 | 39.366 | 40.686 |
| `dispatch_100k_lifts_10k_off` | 78.792 | 78.672 | 37.556 | 44.106 |
| `dispatch_100k_lifts_10k_generators` | 81.529 | 81.437 | 41.944 | 47.659 |

### URBAN1220

| Profile | Cost: none | Cost: gradient | Tracking: none | Tracking: gradient |
|:--|--:|--:|--:|--:|
| `full_10k` | 276.697 | 283.343 | 127.305 | 139.982 |
| `reduced_dispatch_100k` | 267.110 | 268.100 | 120.471 | 147.473 |
| `dispatch_10k_lifts_1k_off` | 241.804 | 253.317 | 120.696 | 119.583 |
| `dispatch_10k_lifts_1k_generators` | 272.377 | 273.251 | 113.855 | 115.338 |
| `dispatch_10k_lifts_10k_off` | 249.637 | 255.265 | 122.405 | 132.485 |
| `dispatch_10k_lifts_10k_generators` | 267.318 | 272.223 | 115.216 | 125.977 |
| `dispatch_100k_lifts_1k_off` | 243.932 | 250.282 | 116.849 | 119.582 |
| `dispatch_100k_lifts_1k_generators` | 279.880 | 288.444 | 118.938 | 130.423 |
| `dispatch_100k_lifts_10k_off` | 253.521 | 252.476 | 116.139 | 144.132 |
| `dispatch_100k_lifts_10k_generators` | 283.001 | 286.192 | 119.403 | 144.498 |

## What the matched comparisons establish

**Cost retains the earlier small-lift profile on the 265-bus cases.** Assembly
and dispatch at 10 kVA, lifts at 1 kVA, reuse off, leads both smaller scenarios
under both policies in both batches. Confirmation median gains over full 10 kVA
are 19.5–20.0% on BASE265 and 17.3–17.5% on VOLTAGE265. These are whole-profile
comparisons, not the isolated contribution of one transformation.

**Combining separately useful changes can reverse a benefit.** At 10 kVA lifts
on BASE265 cost, reuse's same-sweep median ratio is 0.902/0.907 with dispatch at
10 kVA, but 1.246/1.253 with dispatch at 100 kVA (`none`/`gradient-based`).
With 1 kVA lifts and 100 kVA dispatch, reuse ratios are 1.269/1.263. Reused
100 kVA dispatch takes 19 iterations against 14 in its unreused controls.
The dispatch-by-reuse interaction at 10 kVA lifts is 1.386/1.374, with all
within-sweep ratios above one in these two confirmation panels. This is strong
descriptive evidence of interaction on this scenario, not a population-level
significance claim or identification of a solver-internal cause.

**Lower lift units cease to help cost when generator definitions are reused.**
At 10 kVA dispatch, changing 10 to 1 kVA lifts has cost ratios 0.896/0.893 without
reuse on BASE265 but 1.012/1.006 with reuse. VOLTAGE265 shows the same pattern:
0.899/0.907 versus 1.016/1.009. At 1 kVA lifts, enabling reuse loses about 2%
on BASE265 and 4–5% on VOLTAGE265. The options remain exact; their solver runtime
benefits are conditional.

**Urban cost has a group of close unreused candidates.** The lowest median
switches between 10 and 100 kVA dispatch and between 1 and 10 kVA lifts across
batches/policies. Confirmation favours 10 kVA dispatch/1 kVA lifts with scaling
off, and 100 kVA dispatch/1 kVA lifts with gradient scaling. All unreused lifted
arms take 17 iterations. Reuse takes 19 iterations at 10 kVA dispatch and 20 at
100 kVA; its conditional cost ratios range from 1.064 to 1.155 in confirmation.
Keep the unreused arms in the shortlist; the changing narrow winners do not
justify promoting one urban power base as uniformly fastest. Absolute urban
medians also vary between batches, which are kept separate.

**Urban gradient-scaled tracking benefits from the combination.** Dispatch
10 kVA, lifts 1 kVA and reuse has the lowest median in both batches. Its matched
reuse effect at 1 kVA lifts is 0.978 in exploration and 0.961 in confirmation;
its matched smaller-lift effect with reuse is 0.916 and 0.914. The latter reduces
iterations from eight to seven. The confirmation combination is 115.338 ms
versus 139.982 ms for full IVR (17.6% lower median). The incremental reuse gain
is modest; individual paired ratios cross one. Without automatic scaling, the
urban winner switches between 1 and 10 kVA lifts with 10 kVA dispatch/reuse.

**Tracking recommendations remain scenario- and policy-specific.** VOLTAGE265
retains 10 kVA dispatch/10 kVA lifts/reuse for `none` and 10 kVA dispatch/1 kVA
lifts/no reuse for gradient scaling in both batches. Adding reuse to the latter
loses about 7%, despite the combination helping urban tracking. On BASE265 with
`none`, 100 kVA dispatch/10 kVA lifts/reuse leads both batches, but its confirmed
matched dispatch effect versus 10 kVA is only 0.992 and its range crosses one.
With gradient scaling, 10 kVA dispatch/reuse is the shortlist and the 1/10 kVA
lift ordering reverses between batches. There is no universal combined profile.

## Limitations and next experiment

All twelve conditional contrasts and six pairwise interactions per panel are
retained, with individual ratios and ranges; the independent audit recomputes
288 contrasts and 144 interactions across the two batches. Slow tails remain:
VOLTAGE265 exploratory tracking reuse ratios include 0.185 and 4.841, and urban
confirmation cost reuse at 100 kVA dispatch/1 kVA lifts reaches 2.428. No trial
was discarded, and median gains are not claims that every run is faster.
Small read-only JSON progress summaries ran during exploration; confirmation
had only text-log progress reads. Tests, documentation execution, native solver
diagnostics and other solver campaigns did not overlap any timing panel.

The cases and discrete unit levels were selected from prior evidence, not held
out as population samples. No global AC optimum, statistical significance,
continuous best base or native factorization mechanism is certified. This runner
requires bounded generators and an explicitly designed power objective; mixed
IBR/nonlinear-load transfer remains separate work. No equations, package defaults
or transformation options are removed or altered by this study.

The next structural priority is a bounded-size hybrid condensation policy with
complete original-bound reconstruction, charged-chain controls and explicit
retained boundaries. The present work records its design only; it does not
implement or benchmark that new policy. Broader independent transfer and the
signed/proportional affine-sharing extension also remain open.
