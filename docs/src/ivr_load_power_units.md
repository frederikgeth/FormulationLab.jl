# Independent voltage-law power units

This study isolates the numerical units of voltage-dependent load power
auxiliaries. It follows the [paired load-power study](ivr_load_power_timing.md),
which established robust convergence with these auxiliaries but found that
performance depended on objective and formulation. The question here is whether
smaller LV demands and larger MV demands benefit from different power units.

## Hypothesis and exactness

For load ``d``, set ``\rho_d=S_{\ell,d}/S_b``. Its auxiliary obeys
``\rho_d w_{d,k}=u_{d,k}\overline{i_{d,k}}/S_b``. Changing ``S_{\ell,d}`` rescales
only these auxiliary columns; the defining and voltage-law equation rows remain
in assembly units. The extension is bijective for finite positive units with
representable forward/inverse ratios. The [equivalence argument](ivr_load_power_lifting.md)
also covers signed/zero demand, starts, bounds and recovery. This experiment does
not change physical load powers, transformer ratios, nameplates, current units
or the objective.

## Declared experiment

The source is the same 52-bus French MV/LV feeder with four delta–wye transformers
and the previously declared static/IBR additions. Original equipment fields and
operating limits remain unchanged. Each low/high-filter voltage-dependent case
has 38 added current/ZIP/exponential loads (114 native coils). There are 37 LV
loads with maximum nominal channel apparent powers about 80–2613 VA and one MV
load at about 14322 VA. This asymmetry limits the evidence for an MV/LV policy.

| Treatment | Load auxiliary unit, all native channels of each load |
|:--|:--|
| `uniform_1k` | 1 kVA everywhere; previous best-evidence control |
| `uniform_10k` | 10 kVA everywhere |
| `voltage_class` | 1 kVA if all declared coil `v_nom` values are ≤1 kV; 10 kVA if all exceed 1 kV |
| `nominal_max` | Maximum channel nominal apparent power, with a 1 VA floor |

The voltage split refuses a load whose native channels straddle the threshold.
It is an explicit experimental rule, not a voltage standard or inferred
transformer partition. The nominal rule uses magnitudes of signed P/Q; zero
loads receive the positive floor. Neither rule becomes an automatic default.

The runner `examples/benchmark_ivr_load_power_units.jl` crosses these treatments
with full power lifting, reduced power lifting and reduced power lifting with
generator reuse. All 12 candidates enable load-power lifting. The earlier
six-profile and original/lifted runners, including slower or failed alternatives,
remain available. Within each formulation only `load_power_bases` changes.
Assembly/dispatch units remain 10 kVA and other power auxiliaries 1 kVA. Nominal
transformer coordinates, composed circuit rows, voltage-ground scaling and
BMOPFTools ordinary-transformer nameplate caps remain fixed.

Both filter levels, quadratic cost and 500 kW source exchange tracking, and
`none`/`gradient-based` Ipopt scaling produce eight cells. STRICT `1e-10`, MUMPS
AMD, one Julia/BLAS thread, iteration limit 500, CPU limit 30 s and complete common
unloaded physical starts are retained. Each fresh-process batch uses 12 excluded
warm-ups and 12 randomized cyclic sweeps per cell, balanced by candidate position
but not predecessor. Exploration and confirmation use prespecified seeds
20261011 and 20262011, incremented for the second scenario. The completed total is
2304 measured solves and 192 warm-ups.

Only Ipopt wall time ranks. Compilation, build, recovery and validation costs are
excluded. No other solver work, tests, diagnostics or documentation builds overlap
timing. Strict solver status, independent SI audit, own/full membership, reverse
anchor membership and reconstructed objective are required. A failed warm-up or
repeat makes the whole profile ineligible; no survivor-only median is reported.
Within-formulation treatment/control ratios pair the same sweep. Raw tails and
both batches remain separate, without selective reruns or pooling.

## Results and interpretation

Both batches admit **all 2304 measured solves and 192 warm-ups**. Timing ran
02:37:35–02:47:33 UTC on 6 October 2026, after full regression and tutorial
validation, without overlapping solver work. Independent QA checks frozen code
and unchanged inputs, all 38 assignments per profile, complete starts, unchanged
non-load options, admission, position balance and **272 paired contrasts**.
The maximum reconstructed-objective discrepancy is ``5.04\times10^{-10}`` and
within-cell objective spread is below ``1.81\times10^{-10}``. The suite passes
100,049 assertions and all 54 tutorial blocks.

### Low filter impedance

Confirmation median Ipopt wall time in milliseconds. Every raw tail remains in the evidence.

| Profile and load-unit treatment | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_powers__uniform_1k` | 73.070 | 72.902 | 78.831 | 90.353 |
| `reduced_powers__uniform_1k` | 72.470 | 72.428 | 66.324 | 83.991 |
| `reduced_reuse__uniform_1k` | 77.246 | 77.046 | 64.164 | 74.552 |
| `full_powers__uniform_10k` | 73.566 | 73.802 | 69.910 | 91.634 |
| `reduced_powers__uniform_10k` | 73.267 | 73.029 | 69.086 | 82.280 |
| `reduced_reuse__uniform_10k` | 80.010 | 79.093 | 69.803 | 75.765 |
| `full_powers__voltage_class` | 73.316 | 72.660 | 69.350 | 91.560 |
| `reduced_powers__voltage_class` | 72.444 | 72.214 | 65.465 | 81.821 |
| `reduced_reuse__voltage_class` | 77.587 | 76.835 | 65.522 | 73.979 |
| `full_powers__nominal_max` | 73.139 | 72.417 | 69.730 | 94.895 |
| `reduced_powers__nominal_max` | 72.330 | 72.162 | 65.830 | 81.625 |
| `reduced_reuse__nominal_max` | 77.536 | 76.734 | 65.094 | 73.438 |

### High filter impedance

Confirmation median Ipopt wall time in milliseconds. Every raw tail remains in the evidence.

| Profile and load-unit treatment | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_powers__uniform_1k` | 67.042 | 66.698 | 66.751 | 115.410 |
| `reduced_powers__uniform_1k` | 66.118 | 66.769 | 61.908 | 96.934 |
| `reduced_reuse__uniform_1k` | 71.387 | 70.660 | 61.456 | 72.758 |
| `full_powers__uniform_10k` | 66.985 | 67.182 | 73.724 | 100.789 |
| `reduced_powers__uniform_10k` | 67.091 | 67.216 | 62.701 | 98.002 |
| `reduced_reuse__uniform_10k` | 73.661 | 73.043 | 62.869 | 75.360 |
| `full_powers__voltage_class` | 66.460 | 66.352 | 64.934 | 99.728 |
| `reduced_powers__voltage_class` | 66.974 | 66.408 | 62.190 | 96.527 |
| `reduced_reuse__voltage_class` | 71.434 | 71.386 | 61.169 | 72.916 |
| `full_powers__nominal_max` | 66.472 | 66.529 | 66.405 | 111.591 |
| `reduced_powers__nominal_max` | 65.806 | 66.053 | 61.804 | 97.117 |
| `reduced_reuse__nominal_max` | 71.062 | 70.910 | 61.390 | 73.225 |

### Paired treatment/control contrasts

Each entry is the minimum–maximum **paired median ratio** across both filters,
both solver-scaling policies and both batches for the stated workload/profile.
The control is the same formulation with `uniform_1k`. This is a range of eight
cell estimates, not a pooled effect or confidence interval. Below one favours
the treatment. Cell-level ratios and raw sweep pairs remain in `SUMMARY.json`.

| Workload | Formulation | Uniform 10 kVA | Voltage class | Nominal maximum |
|:--|:--|--:|--:|--:|
| quadratic_cost | full_powers | 1.0029–1.0230 | 0.9918–1.0196 | 0.9962–1.0042 |
| quadratic_cost | reduced_powers | 1.0071–1.0177 | 0.9906–1.0118 | 0.9921–1.0056 |
| quadratic_cost | reduced_reuse | 1.0257–1.0376 | 0.9941–1.0204 | 0.9911–1.0293 |
| exchange_tracking | full_powers | 0.8725–1.1011 | 0.8170–1.0094 | 0.8705–1.0438 |
| exchange_tracking | reduced_powers | 0.9866–1.0187 | 0.9719–1.0187 | 0.9768–1.0122 |
| exchange_tracking | reduced_reuse | 1.0159–1.0608 | 0.9779–1.0102 | 0.9823–1.0149 |

**Cost gains from local load units are small and inconsistent.** The nominal
rule changes full/reduced power timings by less than 0.8% in either direction
in paired medians across these cells. It wins all four confirmation cost cells
with reduced power lifting, but does not consistently win exploration. The
voltage split also changes the direction of the comparison across cells.
Uniform 10 kVA is consistently slower: about 0.3–2.3% for full powers,
0.7–1.8% for reduced powers, and 2.6–3.8% with reuse. No cost iteration count
changes under any load-unit treatment. Keep the uniform 1 kVA control alongside
nearby candidates; these small differences do not justify a general policy.

**Full tracking is more sensitive than the reduced finalists.** Changing only
the MV load from 1 to 10 kVA lowers the full model's paired median time by
16.9%/18.3% in low-filter tracking without automatic scaling (exploration/
confirmation), with 18 iterations throughout. In high-filter tracking with
gradient scaling, the same split improves time by about 13.8% in each batch,
with 33 iterations reduced to 29. It slightly slows low-filter gradient-scaled
full tracking. Nominal units there add one iteration (24 to 25). These effects
show that iteration counts alone do not explain timing, and that automatic
solver scaling interacts with the explicit units.

**The reduced shortlist does not inherit these large gains.** Its alternative
load-unit ratios cross one. Uniform 10 kVA consistently slows tracking with
reuse by 1.6–6.1%; the voltage split and nominal rule give smaller mixed effects.
The best profile in every tracking cell of both batches still uses reduced
power lifting with generator reuse, but the winning load-unit treatment changes.
At the common 1 kVA unit, reuse is about 8.4–36.9% below full power lifting by
paired median. For cost, full/reduced power profiles remain close (within 1.2%);
reuse costs about 5.3–7.5%. Retain these objective-specific formulation choices
and the 1 kVA common control, without promoting a new unit default.

Unit treatments preserve model size. Counts differ by objective because its
selected power observations differ:

| Formulation | Cost real variables | Tracking real variables |
|:--|--:|--:|
| Full powers | 2616 | 2502 |
| Reduced powers | 2592 | 2478 |
| Reduced with reuse | 2478 | 2364 |

The next scaling experiment should isolate **load-power equation-row units**
from these column units, including definition and voltage-law rows. Use matched
physical points for targeted NLPDiagnostics evaluation, retain row/column
factorial controls and strict admission, and include more MV loads/transformer
regions before generalizing a regional rule. Global Jacobian norm ratios alone
do not establish KKT conditioning or explain the measured effects.

## Reproduction and limits

Use `IVRLoadPowerUnitStudy.profiles(network, :quadratic_cost)` or call its
`benchmark(input_path, output_path; workload=:exchange_tracking,
exchange_target_W=500000., nlp_scaling_method="none")`. The common benchmark
records options, assignments, input hashes, complete starts, admission details,
solver settings and timing. [Tutorial section 52](tutorial_exact_ivr.md) shows the
independent-unit API. Effective per-load units are also build diagnostics.

This is one feeder and a declared demand/DER experiment, not a population sample
or a global-optimality certificate. Column magnitude and iteration counts alone
do not establish speed or KKT conditioning. Broader MV sampling and independent
row normalization remain separate research questions.

The frozen source, raw JSON reports, protocol, timing window and independent QA
are retained outside Git in `LOAD_POWER_UNITS_20261006`. Both batches, all tails,
and every earlier transformation option remain available.

The follow-up [row/column study](ivr_load_power_rows.md) implements this separate
row-normalization experiment while retaining the column-only controls.
