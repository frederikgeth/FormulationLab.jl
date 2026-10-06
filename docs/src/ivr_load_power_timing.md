# Paired timing of voltage-law power lifting

This study compares the original and auxiliary-power voltage-law formulations
on the same French MV/LV feeder. It follows the [correctness and convergence
study](ivr_load_power_lifting.md). Compilation, model construction, extraction
and audits are excluded from the primary metric: **Ipopt wall time**.

## Controlled design and admission

The low/high finite-filter scenarios retain the original input records and the
declared three-phase DER/parallel-demand additions. Only the voltage-dependent
scenarios are timed: the constant-power scenarios are known no-op controls for
this option and remain in the prior 96-combination preflight. Six retained
profiles each have an original and a `load_power_lifting=true` arm. The only
within-pair option change is load-power lifting.

Both power objectives and both Ipopt scaling policies remain: quadratic cost
and source tracking at 500 kW/0 var; `none` and `gradient-based`. Assembly and
dispatch units are 10 kVA, power-lift units 1 kVA. Nominal transformer scaling,
composed equation rows, voltage-ground scaling, MUMPS AMD, one Julia/BLAS thread
and STRICT `1e-10` settings are fixed. Every trial encodes the same unloaded
physical start. The nameplate policy is `:bmopftools` throughout.

The shared benchmark now requires matching transformer-nameplate policies and
builds its full membership reference with that policy. This strengthens the
reference check for the augmented physical problem; it does not change the
candidate equations, solver timer or historical timing records. Mixed physical
bound policies are rejected before a report is written.

Two prespecified fresh-process batches each contain eight cells: two filter
levels × two objectives × two solver scaling policies. Each cell warms all
12 candidates once and measures one randomized cyclic block of 12 sweeps. Every
candidate occupies every position once; the design is not predecessor-balanced.
Batches are neither pooled nor selectively rerun. Timing is isolated from tests,
documentation builds, diagnostics and other solver work.

A profile qualifies only if its warm-up and every measured trial pass strict
solver admission, independent physical and own/full membership checks, reverse
membership of a full-feasible anchor, finite timing and objective comparability.
A single failed repeat makes that profile ineligible. Failed rows and their
statuses remain available; no median of surviving trials is reported. Paired
ratios use corresponding sweeps only when both complete profiles qualify.

## Results

Across both batches, **1728 of 2304 measured trials** and **144 of 192 warm-ups**
pass. All **1152 lifted trials and 96 lifted warm-ups** pass. The original mode
passes 576 of 1152 measured trials and 48 of 96 warm-ups. Its 576 measured
rejections comprise 336 `ALMOST_LOCALLY_SOLVED`, 144 `NUMERICAL_ERROR`, 72
`OTHER_ERROR` and 24 `LOCALLY_INFEASIBLE` statuses. Including warm-ups, there are
624 retained rejections, all in the original mode. Eligibility is identical
between batches in every cell; each eligible original profile passes all repeats.

Some original admission outcomes differ from the earlier one-shot preflight,
even though the declared physical data, numerical options and physical starts
are preserved. The cause of that sensitivity is not established here. Do not
pool the preflight and timing admission counts or claim a generally reliable
original full control from its earlier success. All lifted profiles qualify in
both batches, providing a complete robust comparison within this experiment.

The independent audit verifies 2304 trials, 192 warm-ups, source/input hashes,
recorded options, position balance, admission/ranking gates and **128 eligible
paired contrasts**. Maximum objective reconstruction discrepancy is below
5.92e-10; within-cell accepted objective spread is below 1.91e-10. Timing ran
02:03:16–02:16:05 UTC on 6 October, isolated from tests, docs and diagnostic solves.
The full regression suite passes **97,223 assertions**, including 129 new checks
for matched factors, independent option ownership, physical reference policy,
strict admission and mixed-policy refusal.

### low_voltage_dependent

Median Ipopt wall time in milliseconds. “Rejected” means the entire profile is ineligible.

| Profile | Cost none | Cost gradient | Tracking none | Tracking gradient |
|---|---:|---:|---:|---:|
| `full_powers__original` | Rejected | Rejected | 63.565 | Rejected |
| `reduced_powers__original` | Rejected | Rejected | 70.279 | 79.020 |
| `reduced_reuse__original` | Rejected | Rejected | Rejected | Rejected |
| `blocks_signed__original` | Rejected | Rejected | Rejected | 136.681 |
| `blocks_signed_reuse__original` | Rejected | Rejected | Rejected | 195.671 |
| `cap4_signed_reuse__original` | Rejected | Rejected | Rejected | 196.631 |
| `full_powers__load_power` | 73.762 | 73.181 | 75.717 | 89.536 |
| `reduced_powers__load_power` | 75.189 | 73.083 | 62.213 | 80.000 |
| `reduced_reuse__load_power` | 78.602 | 77.366 | 61.728 | 72.897 |
| `blocks_signed__load_power` | 92.569 | 90.025 | 78.577 | 105.057 |
| `blocks_signed_reuse__load_power` | 93.952 | 92.270 | 78.398 | 128.883 |
| `cap4_signed_reuse__load_power` | 92.522 | 91.877 | 78.215 | 128.843 |

### high_voltage_dependent

Median Ipopt wall time in milliseconds. “Rejected” means the entire profile is ineligible.

| Profile | Cost none | Cost gradient | Tracking none | Tracking gradient |
|---|---:|---:|---:|---:|
| `full_powers__original` | 113.001 | 114.619 | 67.873 | 88.393 |
| `reduced_powers__original` | 128.355 | 128.356 | 63.599 | Rejected |
| `reduced_reuse__original` | 181.699 | 183.506 | 123.419 | 76.330 |
| `blocks_signed__original` | 91.031 | Rejected | 198.799 | 217.308 |
| `blocks_signed_reuse__original` | Rejected | Rejected | 250.243 | 365.485 |
| `cap4_signed_reuse__original` | Rejected | Rejected | 251.449 | 365.896 |
| `full_powers__load_power` | 66.349 | 67.005 | 69.221 | 119.026 |
| `reduced_powers__load_power` | 66.352 | 66.937 | 64.229 | 99.519 |
| `reduced_reuse__load_power` | 70.840 | 71.232 | 62.944 | 74.707 |
| `blocks_signed__load_power` | 87.390 | 88.263 | 81.078 | 95.586 |
| `blocks_signed_reuse__load_power` | 89.751 | 89.848 | 78.053 | 118.852 |
| `cap4_signed_reuse__load_power` | 88.266 | 89.980 | 77.841 | 119.115 |

### Paired load-power contrasts

Ratio is lifted/original wall time, paired by sweep. Below one favours the auxiliary representation. Only complete eligible pairs are shown; “—” denotes an ineligible original arm.

| Scenario | Objective | Scaling | Full E/C | Reduced E/C | Reuse E/C | Signed E/C | Signed reuse E/C | Cap-four E/C |
|---|---|---|---:|---:|---:|---:|---:|---:|
| `low_voltage_dependent` | `quadratic_cost` | `none` | — / — | — / — | — / — | — / — | — / — | — / — |
| `low_voltage_dependent` | `quadratic_cost` | `gradient-based` | — / — | — / — | — / — | — / — | — / — | — / — |
| `low_voltage_dependent` | `exchange_tracking` | `none` | 1.1785 / 1.1831 | 0.8866 / 0.8872 | — / — | — / — | — / — | — / — |
| `low_voltage_dependent` | `exchange_tracking` | `gradient-based` | — / — | 1.0048 / 1.0113 | — / — | 0.7789 / 0.7634 | 0.6514 / 0.6567 | 0.6655 / 0.6580 |
| `high_voltage_dependent` | `quadratic_cost` | `none` | 0.5895 / 0.5860 | 0.5259 / 0.5118 | 0.3920 / 0.3894 | 0.9553 / 0.9627 | — / — | — / — |
| `high_voltage_dependent` | `quadratic_cost` | `gradient-based` | 0.5748 / 0.5823 | 0.5168 / 0.5202 | 0.3949 / 0.3885 | — / — | — / — | — / — |
| `high_voltage_dependent` | `exchange_tracking` | `none` | 1.0269 / 1.0190 | 1.0057 / 1.0070 | 0.5157 / 0.5096 | 0.4018 / 0.4077 | 0.3106 / 0.3104 | 0.3069 / 0.3110 |
| `high_voltage_dependent` | `exchange_tracking` | `gradient-based` | 1.3918 / 1.3498 | — / — | 0.9698 / 0.9825 | 0.4354 / 0.4397 | 0.3291 / 0.3256 | 0.3245 / 0.3252 |

## Interpretation

**Robustness is the most transferable finding within this panel.** The auxiliary
representation passes every measured repeat under both objectives and scaling
policies. The original representation qualifies in only half its profile/cell
combinations. A speed comparison is undefined for its rejected arms; these
failures are not assigned artificial runtimes or treated as slower optima.

**Cost favours the simple power formulations.** Lifted full and reduced power
models are very close: paired reduced/full medians range from 0.9923 to 1.0164
across the two batches and all cost cells. Several median winners change, so
there is no meaningful unique winner between them. Generator reuse is about
5.5–7.4% slower than the lifted full control and adds two cost iterations in
these cases. Signed observation profiles are about 22–35% slower than that
control by paired median, despite smaller reported Hessian sparsity counts.
Those counts are not a measurement of native factorization cost.

**Tracking favours reduced power lifting with generator reuse.** Its paired
median time is about 7.5–37.5% below the lifted full control across both batches.
It leads all four confirmation tracking cells (61.728–74.707 ms). At high filter
impedance without automatic scaling, the original reduced-power profile leads
the exploratory medians while lifted reuse leads confirmation; the nearby
candidates should remain on the shortlist. Signed observations and the cap-four
arm do not beat the power-only reuse profile in confirmation.

**Load-power lifting is not a universal speedup.** Among eligible matched arms,
high-filter cost improves by roughly 41–61% for full/reduced/reuse power profiles.
Several signed-observation tracking arms improve by roughly 56–69%. Conversely,
full-model low-filter tracking without automatic scaling slows about 18%, and
full-model high-filter tracking with gradient scaling slows about 35–39%.
Reduced-power tracking without reuse is nearly neutral in two other cells.
Use the table's workload-specific ratios, not one pooled speedup figure.

The passive-component elimination report is empty for every reduced arm, with
no component-limit rejection. Thus cap four is not exercised as an active
restriction here. With load-power lifting enabled, full/reduced power models
have 2616/2592 real variables; reuse reduces the latter to 2478. Signed
observations have 3846 variables without reuse or 3732 with reuse; the cap-four
arm also has 3732. The study does not establish a cap-four advantage or claim
that fewer variables alone explain runtime. All tails are retained, including
occasional large paired ratios; no repeat is trimmed.

The current conditional shortlist is therefore: enable load-power lifting on
this voltage-dependent MV/LV panel; retain full and reduced power controls for
cost; prioritize reduced power with generator reuse for tracking. Keep the
original representation and signed/cap-four variants as evidence-generating
alternatives. Package defaults do not change.

Next, separate load-power units from other lifted-power units and test declared
MV/LV-aware scaling factors. Also test a broader feeder sample and investigate
the original mode's sensitivity to execution context before promoting a default.


## Reproduction and scope

`examples/benchmark_ivr_load_power_lifting.jl` constructs the 12 matched arms
and uses the shared source-preserving benchmark with completed-sweep report
checkpoints. The previous three-phase runner remains available. The exact
source snapshot, protocol, inputs/additions, failed rows, raw timing JSON and
analysis scripts remain outside Git in `LOAD_POWER_TIMING_20261006`.

This is repeated evidence on one feeder with declared additions, not a population
sample or a global-optimality certificate. Keep every transformation option and
both load-power representations. Isolate any future change in load-lift units,
objective scaling or solver strategy as a separate experimental factor.
