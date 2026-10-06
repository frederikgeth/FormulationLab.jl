# Independent load-power equation units

The [load-column study](ivr_load_power_units.md) found limited benefit from
matching auxiliary-variable units to local nominal demand. This experiment
separates equation-row units from those column units. It asks which equalities
benefit from normalization across the existing MV/LV circuit, while keeping the
physical network and power objectives fixed.

## Exact transformation and API

Let ``C_d`` be the VA unit of the complex auxiliary ``w_{d,k}``, ``S_b`` the
assembly power unit, and ``R_d`` the independent row unit. The electrical
power-definition and voltage-law residuals in assembly units are

```math
g^{\mathrm{def}}_{d,k}=\frac{C_d w_{d,k}-u_{d,k}\overline{i_{d,k}}}{S_b},\qquad
g^P_{d,k}=\frac{C_d\Re(w_{d,k})-P_{n,d,k}f_P(x_{d,k})}{S_b},\qquad
g^Q_{d,k}=\frac{C_d\Im(w_{d,k})-Q_{n,d,k}f_Q(x_{d,k})}{S_b}.
```

The first complex residual denotes two real equalities. Selected rows become
``\widetilde g=\mu_d g``, where ``\mu_d=S_b/R_d>0``. This preserves their exact
zero sets and requires no change to the primal inverse map. The normalized
squared-voltage definition, engineering domains, operating bounds, all other
power auxiliaries and objectives remain unchanged. Constant-power and impedance
loads are unaffected. Signed or zero nominal P/Q need no special division.

Use `load_power_row_scaling=:definitions`, `:laws`, or `:both`; `:off` is the
default. An active mode requires `load_power_lifting=true`.
`load_power_row_bases=Dict(load_id=>VA, ...)` overrides `load_power_row_base`,
which falls back to `s_base`. Row units **do not inherit column units**. Explicit
row-unit declarations require an active mode; per-load IDs must identify loads
that receive voltage-law power auxiliaries. Nonpositive/nonfinite units,
nonrepresentable base ratios, and overflowing/underflowing composed auxiliary
coefficients are rejected. Builds own their mutable declarations.
Diagnostics expose `:load_power_row_scaling` and effective `:load_power_row_bases`.

Equality scaling changes raw residual magnitudes and dual multipliers. Identical
Ipopt tolerances therefore do not, by themselves, imply identical SI accuracy.
This study retains independent physical and original full-model membership
audits. For dual comparisons at a common objective scale, a selected row's
multiplier would transform inversely, ``\widetilde\lambda=\lambda/\mu_d``.
This feature does not introduce a physical-dual export contract. Physical SI
primal values and BMOPFTools-compatible exports keep their existing contract.

## Factorial design

The formulation choices are fixed from earlier evidence: reduced power lifting
for quadratic cost; reduced power lifting with generator reuse for 500 kW source
exchange tracking. Each uses the following eight numerical treatments:

| Factor | Values |
|:--|:--|
| Load auxiliary column units | Uniform 1 kVA; maximum nominal channel apparent power with a 1 VA floor |
| Row scope | Off; electrical definitions; voltage laws; both |
| Active row units | Maximum nominal channel apparent power with a 1 VA floor, independent of columns |

The existing full-model and other transformation runners remain available. This
experiment ranks row treatments within these objective-specific finalists; it
does not establish the best row policy for every formulation. The two off arms
are the preceding study's column-only controls.

The runner also accepts explicit `column_treatments` and `row_modes` collections;
its original eight-arm default is unchanged. The subsequent
[multiple-MV-site transfer](ivr_mv_scale_transfer.md) uses three column rules
crossed with `(:off,:laws)`. All treatments remain available, and reports retain
the selected factorial and resolved units.

Use the unchanged low/high-filter voltage-dependent French MV/LV scenarios,
with 37 added LV loads and one added MV load. Assembly and generator units stay
10 kVA, other power lifts 1 kVA, transformer coordinates nominal, circuit rows
composed, and finite-ground scaling voltage. Physical fields, transformer
nameplates, complete unloaded starts, STRICT `1e-10`, MUMPS AMD, one Julia/BLAS
thread, `max_iter=500` and `max_cpu_time=30` remain fixed. Both objectives and
`none`/`gradient-based` Ipopt scaling give eight cells per batch.

Two fresh-process batches use eight excluded warm-ups and eight position-balanced
randomized cyclic sweeps per cell, for 1024 measured solves and 128 warm-ups.
Seeds 20261013/20262013, incremented for the second scenario, are prespecified.
The design is not predecessor-balanced. Primary ranking uses only Ipopt wall
time; compilation, construction, extraction and audit costs are excluded. No
other solver work, tests, diagnostics or document builds overlap timing.
Failures, raw tails and both batches are retained without selective reruns,
trimming, pooling or survivor-only medians. Eligibility requires all warm-ups and
repeats to pass the unchanged solver, physical, membership and objective gates.

## Timing results

All **1024 measured solves and 128 warm-ups** pass in both batches, with no
ineligible candidate. Timing ran **03:09:10–03:14:19 UTC on 6 October 2026**,
after tests, documentation and diagnostics finished. Independent QA verifies
frozen source, unchanged physical inputs, exact row/column declarations, complete
starts, solver settings, position balance, membership/physical gates, **160 paired
contrasts and 48 paired interactions**. Maximum objective reconstruction
discrepancy is below ``4.53\times10^{-10}``; within-cell objective spread is below
``6.22\times10^{-11}``. The regression suite passes 121,580 assertions, including
21,531 new checks, and all 55 executable tutorial blocks pass.

### Low filter impedance

Confirmation median Ipopt wall time in milliseconds. Columns/rows identify the numerical treatment; the formulation is fixed by objective.

| Columns and row scope | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `uniform_1k__off` | 74.576 | 74.080 | 64.260 | 76.649 |
| `uniform_1k__definitions` | 73.973 | 74.774 | 63.897 | 75.870 |
| `uniform_1k__laws` | 74.754 | 73.820 | 65.166 | 76.263 |
| `uniform_1k__both` | 74.601 | 74.411 | 63.586 | 77.163 |
| `nominal_max__off` | 73.689 | 74.543 | 63.763 | 75.316 |
| `nominal_max__definitions` | 74.537 | 74.185 | 64.225 | 75.341 |
| `nominal_max__laws` | 73.719 | 73.473 | 64.149 | 77.615 |
| `nominal_max__both` | 74.062 | 74.197 | 63.268 | 75.809 |

### High filter impedance

Confirmation median Ipopt wall time in milliseconds. Columns/rows identify the numerical treatment; the formulation is fixed by objective.

| Columns and row scope | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `uniform_1k__off` | 67.778 | 70.239 | 63.259 | 75.359 |
| `uniform_1k__definitions` | 69.145 | 71.005 | 63.551 | 76.083 |
| `uniform_1k__laws` | 68.024 | 69.824 | 63.283 | 76.017 |
| `uniform_1k__both` | 67.833 | 69.087 | 63.048 | 75.608 |
| `nominal_max__off` | 68.742 | 70.202 | 63.258 | 75.739 |
| `nominal_max__definitions` | 68.659 | 69.844 | 62.732 | 76.002 |
| `nominal_max__laws` | 68.072 | 69.361 | 65.214 | 75.918 |
| `nominal_max__both` | 68.039 | 71.476 | 63.462 | 76.054 |

### Paired row effects and interactions

Entries are minimum–maximum paired median ratios across both filters, both
Ipopt scaling policies and both batches: eight cell estimates per workload.
Each row effect compares the selected row scope with off at the same column
units. The interaction is the sweep-paired ratio of the nominal-column row
effect to the 1 kVA-column row effect. These ranges are not pooled effects or
confidence intervals. Below one favours the numerator treatment. Incomplete
eligibility withholds a full-range estimate; every raw failure remains.

| Workload | Row scope | Row effect, 1 kVA columns | Row effect, nominal columns | Row/column interaction |
|:--|:--|--:|--:|--:|
| quadratic_cost | definitions | 0.9957–1.0209 | 0.9934–1.0137 | 0.9730–1.0159 |
| quadratic_cost | laws | 0.9917–1.0146 | 0.9759–1.0061 | 0.9742–1.0060 |
| quadratic_cost | both | 0.9966–1.0212 | 0.9909–1.0224 | 0.9887–1.0316 |
| exchange_tracking | definitions | 0.9876–1.0081 | 0.9676–1.0194 | 0.9462–1.0270 |
| exchange_tracking | laws | 0.9893–1.0152 | 0.9912–1.0284 | 0.9896–1.0498 |
| exchange_tracking | both | 0.9886–1.0082 | 0.9826–1.0174 | 0.9760–1.0526 |

**No consistently faster row policy emerges.** Across the declared cells, row
changes range from about 3.2% faster to 2.8% slower by paired median. Each row
scope's range crosses one at both column choices. Winning labels often change
between exploration and confirmation. These descriptive ranges do not establish
statistical equivalence or exclude benefits on other networks; they do not
justify promoting a row policy here.

**Iteration counts are identical across all eight treatments in every cell.**
Cost uses 21 iterations at low filter impedance and 19 at high; tracking uses
18 without automatic scaling and 21 with gradient scaling. Cost models retain
2592 real variables and tracking models 2364. Row scaling adds no variables or
equalities. The substantial row-norm changes below therefore do not translate
into demonstrated iteration or consistent time improvements on these finalists.

Keep the existing conditional recommendation: load-power lifting enabled on
this voltage-dependent panel; full/reduced powers as cost controls, reduced
powers with generator reuse for tracking, 1 kVA load auxiliary columns, and
assembly-unit load rows (`load_power_row_scaling=:off`). The full formulation
was not timed in this row study, so its earlier cost shortlist is retained
rather than re-ranked. All row modes and earlier formulations remain available.

## Targeted Jacobian checks

Before timing, NLPDiagnostics evaluates all eight profiles at the same unloaded
physical point and separately solved full-model endpoint on the high-filter
case, for both power objectives. Let ``D_c`` contain the treatment/control power
unit ratios for load auxiliary columns and one elsewhere, and ``D_r`` the
selected equality multipliers. At corresponding points,

```math
x_t=D_c^{-1}x_b,\qquad J_t=D_r J_b D_c.
```

The diagnostic compares the complete Jacobian against this identity, then groups
load-definition and voltage-law row infinity-norms by MV/LV location. This separates the
intended row/column effect from accidental changes elsewhere. Exact symbolic
and constructed nonlinear AD derivatives are used. These are model Jacobians
before Ipopt's optional gradient scaling. Row-norm ranges are not KKT
condition numbers, and cannot by themselves predict factorization cost or speed.

All **32 evaluations** pass without derivative-evaluation failures. Each
includes 222 LV and six MV rows in each of the definition/law groups. The
maximum discrepancy in ``J_t=D_rJ_bD_c`` is ``2.23\times10^{-16}``, using the
entrywise normalization ``|a-b|/\max(1,|a|,|b|)``. Both objectives use common
unloaded and full-endpoint SI states; all transformed models admit the full
endpoint. Source hashes and a runtime path check identify the local
`NLPDiagnostics.jl` checkout used for this experiment.

The following ranges are **row infinity-norms at the shared full endpoint**,
rounded to three significant digits. They are derivative magnitudes, not timing
or condition-number estimates. The raw records also retain the unloaded point
and the two isolated row scopes.

| Objective | Columns and row scope | Definition LV | Definition MV | Law LV | Law MV |
|:--|:--|--:|--:|--:|--:|
| quadratic_cost | uniform_1k__off | 0.804–1.01 | 1.5–1.73 | 0.1–0.1 | 0.268–0.48 |
| quadratic_cost | uniform_1k__both | 3.08–120 | 1.05–1.21 | 0.383–12.4 | 0.187–0.335 |
| quadratic_cost | nominal_max__off | 0.804–1.01 | 1.5–1.73 | 0.00804–0.261 | 1.43–1.43 |
| quadratic_cost | nominal_max__both | 3.08–120 | 1.05–1.21 | 1–1 | 1–1 |
| exchange_tracking | uniform_1k__off | 0.8–1.02 | 1.5–1.73 | 0.1–0.1 | 0.268–0.48 |
| exchange_tracking | uniform_1k__both | 3.1–125 | 1.05–1.21 | 0.383–12.4 | 0.187–0.335 |
| exchange_tracking | nominal_max__off | 0.8–1.02 | 1.5–1.73 | 0.00804–0.261 | 1.43–1.43 |
| exchange_tracking | nominal_max__both | 3.1–125 | 1.05–1.21 | 1–1 | 1–1 |

Nominal row and column units make the sampled voltage-law row infinity-norms
one. At the same time, normalizing the electrical definitions enlarges some LV
rows from about one to 120–125. Laws-only scaling avoids that amplification, but
still provides no consistently faster timing policy. This directly limits the
usefulness of row-norm equalization as a standalone selection criterion on this
panel; it does not identify a KKT conditioning cause.

## Remaining scope

Only one added MV load is present. Transfer to additional MV loads and transformer
regions is needed before recommending a regional rule. The experiment also does
not test row normalization of the original unlifted voltage laws, other device
equalities, dual warm starts, or every formulation. Original-mode execution-
context sensitivity and scalar multiwinding rating-unit parity remain separate
open tasks. Preserve the proven controls and original failures in further work.

## Reproduction

`examples/benchmark_ivr_load_power_rows.jl` provides
`IVRLoadPowerRowStudy.profiles(network, :quadratic_cost)` and the shared
`benchmark(input_path, output_path; workload=:exchange_tracking,
exchange_target_W=500000., nlp_scaling_method="none")` entry point. Reports retain
complete options, row/column declarations, input hashes, ordering, strict
admission and Ipopt wall times. [Tutorial section 53](tutorial_exact_ivr.md)
illustrates the API. Frozen source, diagnostics, protocol and raw evidence remain
outside Git in `LOAD_POWER_ROWS_20261006`.
