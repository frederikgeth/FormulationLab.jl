# Common urban finalist comparison

Earlier studies measured power units, power lifting, generator-definition reuse,
signed observations and bounded hybrid condensation in separate panels. Their
absolute timings cannot establish a common ranking. This study brings selected
retained finalists and matched controls into one panel on the same urban input.
All previous options and benchmark definitions remain available; no production
equation or package default changes.

## Physical problem and objectives

URBAN1220 is the unchanged derived dispatch scenario used in the
[power-unit interaction](ivr_power_interactions.md) and
[structural interaction](ivr_structural_interactions.md) studies. It retains the
1220-bus DSuite SPD urban network, four transformers and 268 added static DERs.
Each DER is colocated with an original positive constant-power load, preserving
its connection, with P in [0, 1.5Pload], |Q| ≤ 0.5Pmax and |S| ≤ Pmax. Total
nominal demand is 268 kW and installed active capacity is 402 kW. Every original
electrical field and supplied equipment limit remains unchanged. These DERs are
declared scenario additions; they are not claimed original dataset dispatch.
The byte-identical input and additions manifest are retained outside Git.

The two power objectives use the existing explicit external-objective helper.
Cost is 0.25 times source active exchange in kW, plus 0.10 Pg + 0.02 Pg² +
0.002 Qg² per generator channel, with powers in kW/kvar. Tracking penalizes squared
source P deviation from 134 kW and Q from zero, plus 0.01 times squared generator
P deviation from its box midpoint and Q from zero. Objective divisor one and
all physical coefficients remain identical across profiles within a workload.
Legacy prices are not used; source export retains the declared exchange sign.

## Candidate provenance and controlled comparisons

`examples/benchmark_ivr_urban_finalists.jl` composes existing options. Tests compare
unchanged parents field by field and verify every declared single-factor change.
All profiles use nominal transformer voltage units, composed row scaling,
voltage-ground scaling, MUMPS AMD and strict 1e-10 solver tolerances. Reduced
profiles use conductor regions and transformer-current elimination. The default
assembly and dispatch units in this panel are 10 kVA, and lifted-power units
are 1 kVA; exceptions are explicit below. Units are coordinates, not equipment
ratings or changes to the physical objective.

| Profile | Description |
|---|---|
| `full_10k` | Full coordinates; unlifted; assembly/dispatch 10 kVA |
| `full_1k` | Full coordinates; unlifted; assembly/dispatch 1 kVA |
| `full_powers` | Full coordinates; power lifting at 1 kVA |
| `reduced_1k` | Passive blocks; unlifted; assembly/dispatch 1 kVA |
| `dispatch100_unlifted` | Passive blocks; unlifted; dispatch 100 kVA |
| `powers` | Passive blocks; power lifting; reuse off |
| `powers_reuse` | `powers` with generator reuse |
| `lifts10_reuse` | `powers_reuse` with lifted-power units 10 kVA |
| `dispatch100_lifts1` | `powers` with dispatch units 100 kVA |
| `dispatch100_lifts10` | Previous row with lifted-power units 10 kVA |
| `cap4_powers` | `powers` with hybrid cap four |
| `cap4_powers_reuse` | `powers_reuse` with hybrid cap four |
| `blocks_signed` | Passive blocks; bounded observations; signed sharing |
| `blocks_signed_reuse` | Previous row with generator reuse |
| `cap4_signed` | `blocks_signed` with hybrid cap four |
| `cap4_signed_reuse` | Previous row with generator reuse |

Bounded observations use support threshold two. Power-only arms retain exact
sharing, which is inactive without bounded-observation lifting. Comparing a
signed-observation arm to a power-only arm therefore tests the **observation
bundle**, not signed sharing in isolation. Matched reuse, lift-unit, dispatch-unit
and cap contrasts change only their named option. Full/reduced 1 kVA controls
prevent confusing a base change with a reduction benefit.

This is a selected finalist panel, not an exhaustive search or full factorial.
Other bases, caps, proportional sharing, threshold-zero lifting, nonadjacent
elimination and historical losers remain available outside this panel. In
particular, no independent causal effect is inferred from a comparison changing
several coordinates and transformations together.

## Structural activation

The cost preflight has all 268 added generator capability ratings active.
Generator reuse removes 536 real power variables. Reduced power lifting has
12,778 variables; its reuse counterpart has 12,242. Full unlifted and full
power-lifted controls have 16,404 and 16,946 variables, respectively.

Cap four retains eight candidate buses relative to unrestricted blocks and increases
the power-only model by 82 variables. Signed-observation blocks have 358 shared
observations; cap four has 357 and 84 more variables than the block counterpart.
The largest eliminated hybrid component has four buses. Thus the cap factor
activates on this urban network, unlike the identical block/cap graphs in the
[rural mixed-device study](ivr_mixed_devices.md). Counts establish structural
changes, not a runtime or native factorization mechanism.

## Admission and timing protocol

Cost and tracking cross Ipopt `none` and `gradient-based` scaling, while retaining
physical per-unit coordinates. All candidates encode the same unloaded linear-
circuit physical point, including eliminated coordinates and auxiliary values.
It is an initial point, not an extra operating constraint. One Julia/BLAS thread
is used throughout. Preflight checks all 64 profile/workload/policy combinations:
physical residuals, own/full-model membership, reverse membership of the full
solution, recovered physical objective, complete starts and SI JSON round trips.
The physical quantity fields must have identical shapes across formulations.
Each recovered endpoint must also fail an independently tightened generator
capability bound through both physical and encoded-model checks.

There are 16 excluded warm-ups followed by 16 randomized cyclic sweeps in each
of four cells. Exploration and confirmation run in separate fresh Julia processes
with seeds 20261008 and 20262008. Candidate positions are balanced within each
cell; predecessor pairs are not. The complete panel has 2048 measured solves,
128 warm-ups and 64 preflight exports. No tests, documentation builds, other
solver work or native diagnostics overlap timing. Source and inputs are frozen
before timing. Every trial and slow tail is retained; batches are not pooled and
no winner receives a selective rerun.

The initial first cell was interrupted before inspecting rankings because
per-trial whole-report rewrites had grown beyond 100 MiB. Its partial files are
retained separately and excluded from comparisons. The entire panel restarts
with `checkpoint=:sweep`: warm-ups still save individually, and each completed
sweep saves every accumulated trial. An interrupted sweep may have unsaved rows.
The existing harness default remains `:trial` for prior runners. This changes
reporting frequency outside the timer, not solver settings, input, seeds or
admission rules. Tests verify complete accepted and rejected reports in sweep
mode. Both final batches use the same checkpoint policy.

Only Ipopt wall time ranks admitted candidates. Construction, compilation,
start assignment, extraction and audits are excluded. Paired contrasts use the
median of within-sweep treatment/control ratios, reported separately by batch;
they need not equal ratios of separate profile medians. A ratio below one
favours treatment. Winner labels alone do not establish a meaningful difference.

## Confirmation results

All **2048 measured solves, 128 warm-ups and 64 preflight exports** pass.
All **64 tightened capability witnesses** reject through both checks. An
independent audit verifies frozen source, input/addition preservation, starts,
physical/full/reverse membership, actual component graphs and 120 paired
contrasts. Maximum recovered-objective discrepancy is 4.97e-14;
within-cell objective spread is 2.91e-13.

The table gives confirmation median **Ipopt wall milliseconds**. All raw trials,
including tails, remain in `URBAN_FINALISTS_20261006` outside Git.

| Profile | Cost / none | Cost / gradient | Tracking / none | Tracking / gradient |
|---|---:|---:|---:|---:|
| `full_10k` | 274.176 | 279.363 | 124.299 | 143.546 |
| `full_1k` | 287.305 | 295.891 | 151.176 | 155.836 |
| `full_powers` | 251.264 | 259.479 | 121.335 | 122.068 |
| `reduced_1k` | 260.800 | 270.025 | 132.674 | 146.532 |
| `dispatch100_unlifted` | 262.080 | 271.054 | 118.066 | 148.172 |
| `powers` | 248.204 | 253.114 | 116.217 | 117.436 |
| `powers_reuse` | 270.191 | 277.340 | 114.519 | 115.175 |
| `lifts10_reuse` | 267.677 | 275.766 | 111.876 | 125.600 |
| `dispatch100_lifts1` | 242.751 | 252.417 | 116.011 | 115.506 |
| `dispatch100_lifts10` | 245.792 | 253.324 | 115.038 | 140.302 |
| `cap4_powers` | 244.057 | 252.566 | 116.548 | 117.453 |
| `cap4_powers_reuse` | 268.528 | 277.698 | 114.077 | 114.181 |
| `blocks_signed` | 248.343 | 255.722 | 118.046 | 119.056 |
| `blocks_signed_reuse` | 269.074 | 276.634 | 113.104 | 114.645 |
| `cap4_signed` | 245.498 | 252.366 | 117.910 | 121.235 |
| `cap4_signed_reuse` | 269.906 | 278.627 | 115.511 | 118.164 |

## Matched paired contrasts

Below one favours the treatment. E/C means exploration/confirmation; solver
policies remain separate. Each value is the median of 16 within-sweep ratios.
The observation-bundle comparisons are not isolated signed-sharing effects.

| Objective | Control | Treatment | E / none | E / gradient | C / none | C / gradient |
|---|---|---|---:|---:|---:|---:|
| `quadratic_cost` | `full_10k` | `full_1k` | 1.0425 | 1.0496 | 1.0463 | 1.0574 |
| `quadratic_cost` | `full_1k` | `reduced_1k` | 0.9140 | 0.9134 | 0.9176 | 0.9120 |
| `quadratic_cost` | `full_powers` | `powers` | 0.9906 | 0.9770 | 0.9855 | 0.9682 |
| `quadratic_cost` | `powers` | `powers_reuse` | 1.0742 | 1.0914 | 1.0944 | 1.1002 |
| `quadratic_cost` | `powers_reuse` | `lifts10_reuse` | 0.9911 | 0.9936 | 0.9928 | 0.9954 |
| `quadratic_cost` | `powers` | `dispatch100_lifts1` | 0.9768 | 0.9831 | 0.9844 | 0.9952 |
| `quadratic_cost` | `dispatch100_lifts1` | `dispatch100_lifts10` | 1.0137 | 1.0066 | 1.0087 | 1.0006 |
| `quadratic_cost` | `powers` | `cap4_powers` | 0.9755 | 0.9971 | 0.9835 | 0.9979 |
| `quadratic_cost` | `powers_reuse` | `cap4_powers_reuse` | 1.0069 | 0.9982 | 0.9928 | 0.9964 |
| `quadratic_cost` | `powers` | `blocks_signed` | 1.0102 | 1.0083 | 1.0028 | 1.0044 |
| `quadratic_cost` | `powers_reuse` | `blocks_signed_reuse` | 0.9963 | 0.9920 | 0.9955 | 0.9970 |
| `quadratic_cost` | `cap4_powers` | `cap4_signed` | 1.0020 | 0.9950 | 1.0126 | 0.9990 |
| `quadratic_cost` | `cap4_powers_reuse` | `cap4_signed_reuse` | 0.9912 | 1.0129 | 1.0093 | 1.0003 |
| `quadratic_cost` | `blocks_signed` | `blocks_signed_reuse` | 1.0585 | 1.0854 | 1.0847 | 1.0735 |
| `quadratic_cost` | `blocks_signed_reuse` | `cap4_signed_reuse` | 1.0137 | 1.0110 | 1.0033 | 1.0056 |
| `exchange_tracking` | `full_10k` | `full_1k` | 1.2144 | 1.1213 | 1.2213 | 1.0863 |
| `exchange_tracking` | `full_1k` | `reduced_1k` | 0.8961 | 0.9428 | 0.8853 | 0.9433 |
| `exchange_tracking` | `full_powers` | `powers` | 0.9738 | 0.9628 | 0.9609 | 0.9613 |
| `exchange_tracking` | `powers` | `powers_reuse` | 0.9559 | 0.9656 | 0.9783 | 0.9709 |
| `exchange_tracking` | `powers_reuse` | `lifts10_reuse` | 1.0034 | 1.1047 | 0.9798 | 1.1004 |
| `exchange_tracking` | `powers` | `dispatch100_lifts1` | 0.9752 | 0.9818 | 0.9956 | 0.9851 |
| `exchange_tracking` | `dispatch100_lifts1` | `dispatch100_lifts10` | 1.0073 | 1.2144 | 0.9930 | 1.2130 |
| `exchange_tracking` | `powers` | `cap4_powers` | 0.9976 | 1.0011 | 1.0003 | 1.0029 |
| `exchange_tracking` | `powers_reuse` | `cap4_powers_reuse` | 1.0064 | 0.9945 | 0.9971 | 0.9978 |
| `exchange_tracking` | `powers` | `blocks_signed` | 1.0010 | 1.0052 | 1.0092 | 1.0071 |
| `exchange_tracking` | `powers_reuse` | `blocks_signed_reuse` | 1.0063 | 1.0071 | 0.9990 | 1.0013 |
| `exchange_tracking` | `cap4_powers` | `cap4_signed` | 1.0114 | 1.0072 | 1.0093 | 1.0271 |
| `exchange_tracking` | `cap4_powers_reuse` | `cap4_signed_reuse` | 0.9984 | 1.0092 | 1.0023 | 1.0151 |
| `exchange_tracking` | `blocks_signed` | `blocks_signed_reuse` | 0.9739 | 0.9778 | 0.9664 | 0.9648 |
| `exchange_tracking` | `blocks_signed_reuse` | `cap4_signed_reuse` | 0.9958 | 0.9999 | 1.0188 | 1.0096 |

## Interpretation

**Cost.** `dispatch100_lifts1` has the lowest median without automatic
scaling in both batches. Its matched dispatch-unit effect relative to `powers`
is modest: paired ratios 0.9768 and 0.9844. Under gradient scaling,
`cap4_signed` has the lowest median in both batches, but the confirmation
medians of `cap4_signed`, `dispatch100_lifts1` and `cap4_powers` are 252.366,
252.417 and 252.566 ms. Their separation is under 0.1%; this panel does not
establish a practically meaningful ordering among them. Retain the unreused
1 kVA power-lift shortlist, including the original `powers` control.

Generator reuse has a much clearer cost penalty. The power-only paired ratios
are 1.0742–1.1002 across the four batch/policy cells, with 19 rather than 17
iterations despite 536 fewer real variables. Signed-observation reuse likewise
loses, with ratios 1.0585–1.0854. A smaller model is therefore insufficient to
predict solve time. Full 1 kVA is 4.2–5.7% slower than full 10 kVA, unlike some
earlier smaller-feeder results. Matched reduction at 1 kVA helps, but does not
beat the leading lifted profiles on this scenario.

**Tracking.** Generator reuse remains a useful shortlist choice at assembly,
dispatch and lift units 10, 10 and 1 kVA. Its matched power-only ratios are
0.9559–0.9783, with seven iterations in all four cells. However, the absolute
winner changes: `powers_reuse` leads both exploration cells; `lifts10_reuse`
leads confirmation without automatic scaling, and `cap4_powers_reuse` leads
confirmation with gradient scaling. Thus the common panel does not demonstrate
that the signed-observation bundle displaces power-only reuse. Its matched
ratios against power-only reuse are 0.9990–1.0071. Preserve nearby alternatives,
including the older 10 kVA lift/reuse profile when automatic scaling is off.

Power-unit effects interact with solver policy. Raising lift units from 1 to
10 kVA with reuse adds an iteration under gradient scaling and gives paired
ratios 1.1047 and 1.1004. At 100 kVA dispatch without reuse, raising lift units
adds two iterations and gives ratios 1.2144 and 1.2130. These penalties do not
appear consistently with automatic scaling off. Full 1 kVA tracking is slower
than full 10 kVA in both batches and policies. Neither a uniformly smaller
power base nor a single lift base is supported as a universal rule.

**Reduction and observation effects.** Cap four is structurally active here.
Against unreused power blocks it improves cost without automatic scaling by
about 1.7–2.4%, but is nearly neutral under gradient scaling; tracking paired
ratios are also near one. Signed observations do not consistently improve the
matched power-only arms. Reduction beyond full power lifting contributes
paired ratios 0.9682–0.9906 on cost and 0.9609–0.9738 on tracking. Consequently,
full power lifting is an essential control: the entire full-unlifted/reduced
bundle gain must not be attributed to network elimination alone.

These are descriptive comparisons on one reused feeder with 16 sweeps per
cell, not population estimates or a formal significance test. Batch wall times
shift, reinforcing the use of within-batch matched ratios instead of pooling
absolute times or comparing older panels. Changes in iterations are observed
correlates; no unmeasured factorization mechanism is asserted. The next useful
experiment is independent feeder transfer with three-phase filtered devices
and inherited active limits, while keeping load and filter changes separate.
Original-network preprocessing recovery and complete export parity remain
separate correctness work. No option is removed and no package default changes.

## Reproduction and limits

Use `IVRUrbanFinalistStudy.benchmark(input_path, output_path;
workload=:exchange_tracking, exchange_target_W=134000.,
nlp_scaling_method="gradient-based")`, with a distinct output path for every cell.
The source-safe runner saves the owned input, manifest, actual orders, warm-ups,
all trials and rankings. Retain the original dataset and DER additions manifest
separately. The [executable tutorial](tutorial_exact_ivr.md) uses a manufactured
case without the external dataset.

This panel revisits an existing urban feeder, not independent transfer. Local AC
solutions and matching objectives are not global-optimality certificates.
Derivative counts are not native KKT fill or factorization-memory measurements.
The shortlist is conditional on this scenario, objective, solver policy and
candidate set. Broader mixed-device transfer and original-network preprocessing
reconstruction remain separate priorities.
