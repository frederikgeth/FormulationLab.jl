# Hybrid transfer across objectives and solver scaling

The [initial hybrid study](ivr_hybrid.md) found a roughly 1% urban cost advantage
for cap four, alongside substantial regressions on manufactured terminal chains.
This follow-up tests that candidate across two power objectives, two Ipopt
scaling policies and an existing voltage-constrained scenario. The formulations,
physical inputs and admission rules are unchanged. All alternative caps and
previous transformation options remain available.

## Question and protocol

The primary comparison is `hybrid_4` against `blocks` on urban economic cost.
The transfer comparisons add source P/Q tracking and the existing constrained
265-bus scenario. These are selected scenarios on two feeders; this is not an
independent held-out feeder sample. In particular, the voltage-constrained
scenario is the suburban feeder, not a new constrained urban variant.

The seven profiles are `full`, `blocks`, `nonadjacent` and caps 1/2/4/8, using
`examples/benchmark_ivr_hybrid.jl`. Assembly and generator dispatch units stay
at 10 kVA, power-lift units at 1 kVA, generator reuse off, exact affine sharing,
nominal transformer coordinates, composed rows and voltage-ground scaling.
Within the reduced family, only the elimination policy/cap changes. The full
control retains power lifting. This panel isolates cap effects within that
bundle; it does not retest every previously studied best profile.

BASE265, VOLTAGE265 and URBAN1220 retain byte-identical inputs and DER/voltage
addition manifests from the [interaction study](ivr_power_interactions.md).
The first two have 74 bounded generators; the urban case has 268. VOLTAGE265
retains the explicitly added 216–242.5 V phase-neutral limits at original load
buses. These are scenario choices, not claimed statutory limits. Every original
source and field is preserved. Economic coefficients and physical objective
normalization remain unchanged. Source tracking targets are 37 kW on the
265-bus cases and 134 kW on the urban case, with zero reactive exchange.

Both workloads cross `nlp_scaling_method="none"` and `"gradient-based"`.
All profiles use the same unloaded linear-circuit physical start, strict 1e-10
solver tolerances, MUMPS AMD and one Julia/BLAS thread. Preflight checks each
profile's physical, own-model, full-model and reverse membership and round-trips
its SI result export. Every cost preflight also tightens a generator capability
limit at the recovered point and requires independent physical and encoded-model
rejection. VOLTAGE265 cost preflights additionally tighten an original voltage
limit and check both rejection paths.

Each of twelve scenario/workload/policy cells has seven excluded warm-ups and
seven randomized cyclic sweeps, balancing candidate positions but not predecessor
pairs. Exploration and complete confirmation use fresh Julia processes per
scenario and batch. The declared panel contains 1176 measured solves, 168
warm-ups and 84 preflight SI exports. Only Ipopt wall time ranks candidates;
construction, start assignment, extraction and audits are excluded. No tests,
documentation builds, other solver work or native diagnostics overlap timing.
All tails and both batches remain, without pooling or winner-selective reruns.

## Results

All **1176 measured solves, 168 warm-ups and 84 preflight SI exports** pass.
All **42 capability** and **14 voltage** rejection witnesses pass both physical
and encoded checks. Every constrained cost preflight has one upper-voltage
slack below 1e-4 V. The independent audit verifies source/addition preservation,
physical export shapes, complete shared starts, full/reverse membership,
component graphs and all 240 conditional timing contrasts. Maximum recovered-
power objective discrepancy is below 1.07e-14; within-cell objective spread is
below 7.11e-15. Source snapshots agree with the unchanged production code.

The table reports **confirmation median Ipopt wall time in milliseconds**.
`none` and `gradient-based` describe Ipopt's automatic scaling; physical model
units are fixed in both. Results are not pooled across policies or batches.

| Case | Workload | Ipopt scaling | Full | Blocks | Nonadjacent | Cap 1 | Cap 2 | Cap 4 | Cap 8 |
|:--|:--|:--|--:|--:|--:|--:|--:|--:|--:|
| `BASE265` | `quadratic_cost` | `none` | 42.600 | 40.017 | 41.943 | 42.026 | 40.397 | 40.178 | 40.019 |
| `BASE265` | `quadratic_cost` | `gradient-based` | 42.775 | 39.950 | 41.999 | 41.753 | 40.461 | 40.184 | 39.951 |
| `BASE265` | `exchange_tracking` | `none` | 25.169 | 23.535 | 24.494 | 24.741 | 23.677 | 23.522 | 23.554 |
| `BASE265` | `exchange_tracking` | `gradient-based` | 25.608 | 24.482 | 24.866 | 24.884 | 24.112 | 23.823 | 23.945 |
| `VOLTAGE265` | `quadratic_cost` | `none` | 76.440 | 71.054 | 73.925 | 73.866 | 71.283 | 71.149 | 70.985 |
| `VOLTAGE265` | `quadratic_cost` | `gradient-based` | 77.636 | 74.259 | 76.666 | 77.050 | 75.467 | 74.064 | 73.657 |
| `VOLTAGE265` | `exchange_tracking` | `none` | 33.661 | 31.696 | 32.947 | 33.123 | 31.924 | 31.904 | 31.674 |
| `VOLTAGE265` | `exchange_tracking` | `gradient-based` | 33.972 | 31.772 | 32.965 | 33.028 | 31.931 | 31.778 | 31.816 |
| `URBAN1220` | `quadratic_cost` | `none` | 233.078 | 231.465 | 235.374 | 237.701 | 230.435 | 227.652 | 229.786 |
| `URBAN1220` | `quadratic_cost` | `gradient-based` | 232.636 | 230.010 | 236.084 | 236.242 | 230.753 | 229.610 | 230.680 |
| `URBAN1220` | `exchange_tracking` | `none` | 115.162 | 111.191 | 116.129 | 116.334 | 113.265 | 111.777 | 111.876 |
| `URBAN1220` | `exchange_tracking` | `gradient-based` | 116.699 | 111.181 | 116.856 | 117.616 | 113.330 | 112.770 | 111.545 |

## Matched cap-four contrasts

For each sweep, divide the cap-four time by the block time, then take the median
of those seven ratios. A ratio below one favours cap four. This **median of paired
ratios** differs from the quotient of the two profile medians; the latter is
visible in the preceding table. Full ranges retain every slow trial.

| Case | Workload | Ipopt scaling | Exploration ratio | Confirmation ratio | Confirmation range |
|:--|:--|:--|--:|--:|:--|
| `BASE265` | `quadratic_cost` | `none` | 1.0220 | 1.0069 | 0.9901–1.6342 |
| `BASE265` | `quadratic_cost` | `gradient-based` | 1.0082 | 1.0022 | 0.9917–1.0153 |
| `BASE265` | `exchange_tracking` | `none` | 1.0076 | 0.9953 | 0.9833–1.0142 |
| `BASE265` | `exchange_tracking` | `gradient-based` | 1.0083 | 0.9625 | 0.4592–1.0283 |
| `VOLTAGE265` | `quadratic_cost` | `none` | 0.9958 | 1.0036 | 0.9976–1.0293 |
| `VOLTAGE265` | `quadratic_cost` | `gradient-based` | 1.0006 | 0.9960 | 0.9699–1.0222 |
| `VOLTAGE265` | `exchange_tracking` | `none` | 1.0046 | 1.0072 | 0.9994–1.0288 |
| `VOLTAGE265` | `exchange_tracking` | `gradient-based` | 1.0030 | 0.9998 | 0.9913–1.0160 |
| `URBAN1220` | `quadratic_cost` | `none` | 0.9864 | 0.9833 | 0.9559–0.9946 |
| `URBAN1220` | `quadratic_cost` | `gradient-based` | 0.9920 | 0.9927 | 0.8334–1.0279 |
| `URBAN1220` | `exchange_tracking` | `none` | 1.0156 | 1.0042 | 0.8024–1.0140 |
| `URBAN1220` | `exchange_tracking` | `gradient-based` | 1.0036 | 1.0174 | 0.9973–1.0589 |

### Urban cost: repeatable ordering, small magnitude

Cap four has the smallest median on urban cost under both solver policies in
both batches. Without automatic scaling, confirmation medians are 227.652 versus
231.465 ms, a 1.65% reduction in the profile median. Same-sweep median ratios
are 0.9864 and 0.9833 in exploration and confirmation. Twelve of fourteen paired
observations favour cap four; all seven confirmation pairs do. The earlier
[unscaled panel](ivr_hybrid.md) also favoured it, but remains a separate study.

With gradient scaling, the paired median ratios are 0.9920 and 0.9927. Ten of
fourteen pairs favour cap four, and both batches have individual pairs above
one. Confirmation profile medians differ by only 0.400 ms: 229.610 versus
230.010 ms, or 0.17%. Thus the ordering repeats, but the size of the apparent
benefit depends on the summary and is small. This supports an additional
urban-cost candidate under both policies, not a practically substantial or
population-level improvement claim.

Cap four eliminates 297 buses versus 304 for blocks and uses 12,860 real
variables versus 12,778. Both take 17 iterations. The gain cannot be attributed
to fewer variables or iterations. No native factorization or derivative-cost
mechanism has been established.

### Tracking and active voltage limits: no consistent transfer

Urban tracking does not favour cap four. Its paired median ratios exceed one
in both batches and policies: 1.0156/1.0042 without automatic scaling and
1.0036/1.0174 with gradient scaling. Confirmation medians are 111.777 versus
111.191 ms without scaling and 112.770 versus 111.181 ms with gradient scaling.
Blocks lead confirmation in both policies. Retain unrestricted blocks for this
tracking comparison; it does not support carrying a cost-specific cap into a
tracking recommendation. The earlier generator-reuse tracking candidates remain
available and are not re-ranked by this unreused panel.

BASE265 cost favours unrestricted blocks in both policies and batches. Its cap-four
tracking ratios change sides between batches, so the confirmation ranking does
not establish a repeatable benefit. VOLTAGE265 cost ratios likewise change sides
between batches under both policies, and its tracking differences are near zero
or favour blocks. The presence of an active voltage limit therefore does not
make the hybrid generally preferable in this case. Active urban voltage limits,
other objectives and genuinely independent feeders remain untested transfers.

### Structural controls and limits

The separate untimed audit compares projection/reconstruction dictionaries
exactly and saves canonical coefficient hashes. On **all three scenarios**,
cap eight equals unrestricted blocks, and cap one equals the old nonadjacent
policy. A narrow cap-eight lead is not a benefit from a binding cap. These
controls also show the practical variability of timings for identical maps.
In BASE265 gradient tracking, the confirmation paired median ratio is about
0.963 for both cap four and map-identical cap eight; exploration instead favours
blocks. Treat that fluctuation cautiously.

All seven profiles have identical iteration counts within each of the 24 cells.
Reduced variable counts alone do not predict runtime, and iterations do not
explain the within-cell timing differences. Slow tails remain: BASE265 unscaled
cost has a confirmation cap-four/block ratio of 1.634, and BASE265 gradient
tracking spans 0.459–1.028. Urban gradient tracking exploration includes a
cap-four/block ratio of 0.415 despite its median ratio exceeding one. No trial
was discarded or rerun to improve a ranking.

The panel balances positions but not predecessors, has seven sweeps per cell,
and uses selected related scenarios rather than a random or held-out population.
No global AC optimality or statistical significance is certified. The study
does not establish that gradient scaling generally helps: that would require
a separately designed policy comparison. Retain every cap and existing mode;
keep unrestricted blocks as the general starting candidate and cap four as an
additional urban-cost experiment. Production code and defaults are unchanged.

## Reproduction and next experiments

[Tutorial section 42](tutorial_exact_ivr.md) shows a matched comparison under
both solver policies. For feeder runs, select a separate output for each policy
and objective with `IVRHybridStudy.benchmark`; preserve the scenario's physical
target and addition manifests. Raw JSON, SI exports, protocol, frozen sources,
map audit and validation are stored outside Git in `HYBRID_TRANSFER_20261006`.

The next exact-algebra priority is signed/proportional affine sharing, with an
explicit inverse map, constant terms, native channels and every original bound.
Coefficient-exact sharing remains its control. Further hybrid-specific work
should first separate evaluation and native linear-system costs in untimed
diagnostics, then test independent feeders or active urban limits. Repeating
small cap grids on these same inputs alone would not establish general benefit.
