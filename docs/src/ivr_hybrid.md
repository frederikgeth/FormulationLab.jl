# Bounded hybrid condensation

An exact elimination can make a model smaller while making its reconstructed
operating-bound expressions less sparse. The optional hybrid policy retains
additional boundaries along otherwise eliminable line sections. It offers a
controlled family of exact formulations for numerical comparison, with every
existing elimination mode preserved.

## Definition and equivalence domain

Select `linear_elimination=:passive_hybrid` and a positive integer
`passive_component_limit=K` (default four). The existing block policy supplies
eligible device-free degree-two buses, surviving line equations and local
condition/residual checks. The hybrid additionally limits each connected
component of eliminated **original buses** to at most `K` members. It is not a
limit on total eliminated buses or local matrix dimension.

Before attempting a candidate, merge its singleton with the already accepted
components containing its original-line neighbours. A component touched by both
neighbours is counted once. If the union exceeds `K`, retain the bus with reason
`eliminated_component_limit`. Otherwise attempt the existing local substitution
and optional bound-support check. Commit component membership only when all
checks succeed. Failed attempts consume neither equations nor component capacity.

By induction, each accepted component satisfies the cap. Algebraic equivalence
has a separate justification: each accepted local block has an invertible target
matrix, and all remaining equations, objectives, limits and observations use its
reconstruction. Composing these substitutions preserves the original feasible
set and recovered physical outputs, subject to the existing numerical gates and
independent residual checks. See the [block-substitution proof](ivr_theory.md).
There is no approximation, pseudoinverse, coefficient truncation or deletion of
interior operating limits.

Buses and candidate lines retain the existing sorted traversal. This greedy
policy is deterministic under dictionary insertion permutations, but renaming
IDs can change its selections. It does not optimize a partition or maximize the
number eliminated. `K=1` still admits charged local blocks, so it is not identical
to the older unshunted unit-pivot `:passive` mode. A sufficiently large cap recovers
unrestricted block maps. Component membership describes the original line graph;
conductor-region and subsequent device substitutions can introduce dependencies
beyond those groups. The cap does not certify expression width, matrix fill,
conditioning improvement or faster solves.

The [API](ivr_nlp.md) describes report fields, boundary rules and composition with
`series_selection=:bound_support`. Physical JSON fields and units are independent
of the policy. No package default or existing transformation is removed.

## Correctness checks

The focused suite contains **5337 assertions**. It covers single-phase, delta
and four-wire circuits, charging, reversed/permuted ports, all tested caps,
independent graph traversal, arbitrary-coordinate projection/reconstruction,
vanishing eliminated equations, forward/reverse feasible-point membership,
physical power objectives and SI JSON round trips. A large cap reproduces the
unrestricted projection and reconstruction exactly in the tested cases.

Every tested eliminated interior bus is subjected to tightened phase, pair,
neutral and sequence voltage bounds where defined and nonzero. Each original
line end is subjected to tightened current and apparent-power limits. Additional
reversed-power witnesses place an apparent-power ceiling strictly between the
two endpoint magnitudes, requiring the independent physical audit to report only
the intended endpoint violation. Both endpoint directions are exercised.

Mesh/junction boundaries, dictionary permutations, singular resonant blocks,
bound-support rollback and supported load/generator updates are covered. Rejected
blocks leave no stale component membership. These tests support the declared
static domain; they are not a claim that every possible element/control model
is supported or that floating-point equivalence has an interval proof.

## Timing protocol

Seven candidates share assembly/dispatch units of 10 kVA, power-lift units of
1 kVA, generator reuse off, exact affine sharing, nominal transformer coordinates,
composed rows, voltage-ground scaling and physical objective divisor one:

- `full`: full circuit coordinates, with power lifting retained.
- `blocks`: conductor regions, unrestricted passive blocks and transformer-current elimination.
- `nonadjacent`: the same reduced settings with the older `:passive` policy.
- `hybrid_1`, `hybrid_2`, `hybrid_4`, `hybrid_8`: the reduced settings with the corresponding component cap.

The full control retains the same power lifting as the reduced candidates. It
is not a claim that this is the fastest of all previously studied full-IVR
profiles. Within the reduced candidates only the line-elimination policy/cap
changes. Construction time is excluded from ranking.

Six manufactured cases cross two-wire single-phase and three-wire delta with
uncharged terminal loading, charged terminal loading and uncharged alternating
loading. Each has 20 segments, total length one, fixed total demand and fixed
per-length line parameters. A terminal DER has native-channel active capacity
1.5 times demand, reactive bounds ±0.5 times that capacity, and an apparent-power
rating equal to the active capacity. Original intermediate voltage and line-end
limits remain. Alternating cases have isolated eligible buses and serve as a
control with no adjacent-component opportunity. Circuit charging and DER placement
are explicit fixture choices, not equivalent preprocessing of another input.

Both economic cost and source P/Q tracking use the existing physical objective
coefficients. Tracking targets are half positive demand (1 kW single-phase,
1.5 kW delta) and zero reactive exchange. BASE265 and URBAN1220 retain byte-identical
inputs and addition manifests from the [power-interaction study](ivr_power_interactions.md),
with economic cost only in this stage. All original raw sources are preserved.

Preflight checks all 98 profile/workload combinations and SI exports. Timings use
one shared unloaded linear-circuit physical start, MUMPS AMD, one Julia/BLAS
thread, strict solver tolerances of 1e-10 and `nlp_scaling_method="none"`. A flat
zero-current start would generally violate charged-section equations; the shared
linear-circuit start remains an initialization, not an extra OPF constraint.

Each of fourteen case/workload cells has seven excluded warm-ups followed by
seven randomized cyclic sweeps, placing each profile in each position once.
Predecessor pairs are not balanced. A second fresh process repeats the complete
panel. The declared total is 1372 measured solves and 196 excluded warm-ups.
Only Ipopt wall time ranks admitted profiles; construction, start assignment,
extraction and audits are excluded. Tests, documentation builds and native solver
diagnostics do not overlap timing. Batches and all tails remain separate.

## Results

All **1372 measured solves, 196 warm-ups and 98 preflight SI exports** pass.
The independent audit checks original/source hashes, complete shared starts,
physical/own/full/reverse membership, the actual component cap and every accepted
component using a separate graph traversal. Physical output fields match across
formulations. Maximum recovered-power objective discrepancy is below 9.01e-14;
within-cell objective spread is below 7.11e-15. All 280 conditional timing
contrasts are recomputed from raw trials. The source is frozen before timing.

The table reports **confirmation median Ipopt wall time in milliseconds**.
`nonadjacent` is the existing unshunted unit-pivot policy; the cap columns use
conditioned block substitutions. Batches are not pooled and all slow trials
remain in the record.

| Case | Workload | Full | Blocks | Nonadjacent | Cap 1 | Cap 2 | Cap 4 | Cap 8 |
|:--|:--|--:|--:|--:|--:|--:|--:|--:|
| `wire2_terminal` | `quadratic_cost` | 4.447 | 2.897 | 4.042 | 4.051 | 4.198 | 4.373 | 4.319 |
| `wire2_terminal` | `exchange_tracking` | 2.624 | 1.735 | 2.409 | 2.426 | 2.496 | 2.553 | 2.507 |
| `wire2_charged` | `quadratic_cost` | 4.678 | 5.813 | 4.705 | 6.913 | 7.657 | 7.758 | 7.390 |
| `wire2_charged` | `exchange_tracking` | 2.801 | 3.372 | 2.853 | 4.112 | 4.503 | 4.566 | 4.311 |
| `wire2_alternating` | `quadratic_cost` | 4.394 | 3.962 | 3.920 | 3.907 | 3.926 | 3.951 | 3.887 |
| `wire2_alternating` | `exchange_tracking` | 2.763 | 2.514 | 2.503 | 2.489 | 2.464 | 2.502 | 2.487 |
| `wire3_terminal` | `quadratic_cost` | 11.896 | 10.232 | 14.354 | 14.472 | 15.171 | 15.206 | 15.179 |
| `wire3_terminal` | `exchange_tracking` | 8.233 | 7.132 | 9.792 | 9.810 | 10.366 | 10.494 | 10.674 |
| `wire3_charged` | `quadratic_cost` | 13.882 | 21.777 | 13.815 | 33.311 | 39.135 | 39.304 | 38.540 |
| `wire3_charged` | `exchange_tracking` | 9.802 | 15.627 | 9.874 | 23.911 | 27.385 | 27.678 | 27.323 |
| `wire3_alternating` | `quadratic_cost` | 14.044 | 14.904 | 14.979 | 14.930 | 14.788 | 14.764 | 14.947 |
| `wire3_alternating` | `exchange_tracking` | 9.776 | 10.524 | 10.399 | 10.547 | 10.465 | 10.452 | 10.401 |
| `BASE265` | `quadratic_cost` | 42.539 | 40.224 | 41.673 | 41.849 | 40.389 | 40.207 | 40.100 |
| `URBAN1220` | `quadratic_cost` | 232.082 | 228.857 | 234.925 | 235.245 | 228.635 | 226.400 | 229.288 |

### Structural controls and unchanged maps

A separate untimed audit compares the projection/reconstruction dictionaries
exactly and saves canonical coefficient hashes. On both alternating-load cases,
all hybrid caps have exactly the same maps as unrestricted blocks: each removes
ten isolated eligible buses. Their narrow timing differences do not establish a
benefit from choosing one cap. Full IVR leads the delta alternating case in both
batches, despite the reduced models having fewer variables.

On both external feeders, cap eight has exactly the same maps as unrestricted
blocks. Its slightly smaller BASE265 median is therefore not evidence that a
cap improves this model. The unrestricted eliminated components fit within eight
buses (maximum five on BASE265, eight on URBAN1220, as measured by the equivalent
cap-eight policy). Cap one also matches nonadjacent maps exactly on these two
inputs. On the charged manufactured cases, `full` and `nonadjacent` maps are
identical because the latter declines every charged series candidate. Their
small ranking changes across batches should not be interpreted as a structural
advantage of either label.

For all four terminal-load cases, unrestricted blocks eliminate 19 buses; caps
1/2/4/8 eliminate 9/13/15/17. The count need not be an optimal partition: sorted
bus IDs determine a greedy traversal. In particular, a cap need not select a
subset of the unrestricted accepted bus set, since retained boundaries can alter
later pivots. The cap invariant and full physical reconstruction still hold.

### What works and what does not

**Uncharged terminal chains favour unrestricted condensation.** Blocks lead
both single-phase and delta terminal-load cases, both objectives and both batches.
Confirmed cap/block same-sweep median ratios range from 1.375 to 1.510: the capped
variants are approximately 38–51% slower here. Reducing the component cap is not
a reliable way to improve runtime. Within the capped family, more elimination
can also increase time; the response is not monotone in the number of variables.

**Charged terminal chains favour retaining the circuit.** Full/nonadjacent
profiles lead both charged cases in both batches; their maps are identical.
Unrestricted block substitution already loses relative to this control, and
hybrid caps lose a further 19–80% against blocks in confirmed matched medians.
For example, charged delta cost uses 522 real variables in full IVR, 294 with
blocks and 342 with cap four, yet the corresponding medians are 13.882, 21.777
and 39.304 ms. Fewer variables alone do not predict Ipopt runtime.

**BASE265 does not establish an advantage for a binding cap.** Blocks eliminate
61 buses; caps 1/2/4 eliminate 42/55/60. Their confirmation cap/block median ratios
are 1.036, 1.004 and 1.004. Cap eight removes the same 61 buses with identical
maps and a ratio of 0.997. Retain unrestricted blocks in this cost shortlist;
none of these observations identifies a useful cap improvement on this input.

**URBAN1220 offers a small, repeatable candidate improvement.** Cap four
eliminates 297 buses against 304 for unrestricted blocks and keeps 12,860 real
variables against 12,778. Its cap/block paired median ratio is 0.989 in exploration
and 0.990 in confirmation; the full ranges are 0.974–0.993 and 0.977–0.999.
All fourteen paired observations favour cap four, but the gain is only about 1%
and is not a population-level significance claim. Confirmation medians are
226.400 versus 228.857 ms, with 17 iterations in both. It is an additional
candidate for this urban cost workload under the declared settings, not a new
general default. Cap two is effectively tied; cap one is slower; cap eight is
structurally identical to unrestricted blocks.

All candidates have the same iteration count within each of the 28 case/batch/
workload cells. Thus increased iteration count does not explain these timing
regressions. The study does not separate function/derivative evaluation from
linear-system work or establish a factorization-fill mechanism. Native solver
diagnostics, if collected later, must remain separate from ranking measurements.

### Limits of the evidence and next steps

Slow tails remain. A slow unrestricted-block trial gives a single-phase terminal
cost cap/block ratio near 0.13 despite the capped median regression. BASE265's
exploratory cap-two/block ratio reaches 4.430; a charged-delta confirmation
cap-two/full ratio reaches 4.524. No run was removed or silently repeated.
Seven cyclic sweeps balance positions, not predecessors, and these are selected
cases, not a held-out population sample. No global AC optimality, statistical
significance or universal best cap is certified.

The [follow-up transfer study](ivr_hybrid_transfer.md) tests gradient scaling,
tracking and the existing constrained suburban scenario. Those comparisons are
separate from this initial panel; active urban limits and independent feeders
remain untested. The API and diagnostics support
later evidence without deleting any previous option. Broader mixed IBR/nonlinear-
load cases and signed/proportional affine sharing remain separate priorities.
For reproducibility, `examples/benchmark_ivr_hybrid.jl` contains the fixtures and
runner; frozen sources, manifests, raw JSON, SI exports, map audit, validation
logs and planning documents are retained outside Git in `HYBRID_20261006`.
