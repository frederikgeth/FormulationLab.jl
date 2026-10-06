# Scaling transfer across multiple MV load sites

The preceding [column-unit](ivr_load_power_units.md) and
[row-unit](ivr_load_power_rows.md) experiments contain only one added MV load.
This transfer panel tests the same exact coordinate and equality transformations
on a feeder with six MV sites. It compares numerical units within the previously
selected objective-specific formulations; it does not reselect the underlying
formulation on the new feeder.

## Case selection and physical scenario

Before any admission solve, screen all 150 original FrenchPowerGrids JSON files
in BMOPFDraftData. Require at least three positive, nonnegative-active-demand MV
sites, three LV sites and three transformers; choose the smallest bus count,
breaking ties by path. Screening classifies MV using inherited bus line-line
lower bounds above 1 kV. The actual load-unit assignments subsequently use
unloaded native coil voltages. No solver outcome enters selection.

This rule selects `24_MVFeeder0752.bmopf.json`: 67 buses, six transformers,
six positive MV sites and twenty positive LV sites. The larger combined feeder
was also inspected: it has 33 transformers but only single-phase LV loads, so
it does not meet this three-phase, multiple-MV-site experiment's scope. It
remains a possible separate single-phase transfer case.

Use the existing three-phase scenario factory, retaining every original
electrical field and limit. Add colocated dispatchable DER and 10% parallel
demand at the 26 selected sites: ten static generators and sixteen IBRs. Added
loads cycle through constant-current,
ZIP and exponential laws; all 78 channels receive power auxiliaries. Low/high
finite filter impedances differ by a factor of ten, with the same shunt and DC
limits. These are declared experimental additions, not original feeder data.

The original signed nominal active demand is 3,836,652.479314411 W. Fix source
exchange tracking at half this value, **1,918,326.2396572055 W**, and zero var
before admission. Retain the earlier quadratic-cost objective and all DER
terms. The target changes only with the declared input, never with a solve
outcome. Exact additions, original hashes and screened cases are retained in
the external evidence archive.

## Controlled numerical comparison

Cross three auxiliary-column rules with two row scopes:

| Factor | Treatments |
|:--|:--|
| Load columns | Uniform 1 kVA; 1/10 kVA by native coil voltage; maximum nominal channel apparent power with a 1 VA floor |
| Load rows | Assembly units (`:off`); nominal-demand voltage-law rows (`:laws`) |
| Active row unit | Maximum nominal channel apparent power with a 1 VA floor, independently of columns |

The voltage threshold is the same experimental 1 kV rule as before; it is not a
topology-based region certificate. Power-definition rows keep assembly units.
Cost uses `reduced_powers`; tracking uses `reduced_reuse`; both enable
`load_power_lifting=true`. Assembly and dispatch units stay 10 kVA, other power
lifts 1 kVA, transformer coordinates nominal, circuit rows composed, finite
ground scaling voltage and objective scale one. All other options, bounds and
physical inputs are held fixed. All excluded options remain available in the
original runners, including definition/both row scopes and uniform 10 kVA.

The admission panel contains 48 solves: six candidates, two objectives, two
filter levels and `none`/`gradient-based` Ipopt scaling. It checks complete
common unloaded starts, independent SI equations and objectives, full-reference
and own/reverse membership, identical physical export structure, JSON round
trips, filter losses, and deliberately tightened voltage, line, transformer
nameplate and internal-DC limits. These limits must reject the previous point;
the experiment does not weaken bounds to obtain admission.

Timing uses two fresh-process batches, six excluded warm-ups and six randomized
cyclic sweeps per cell: **576 measured solves and 96 warm-ups**. Each candidate
occupies each position once per batch and cell. Seeds are 20261014/20262014,
incremented for high filters. The design is not predecessor-balanced. Use
STRICT `1e-10`, zero acceptable iterations and bound relaxation, 500 iterations,
30 CPU seconds, MUMPS AMD, and one Julia/BLAS thread. No other solver, test,
documentation build or derivative diagnostic overlaps timing.

Rank only **Ipopt wall time**. Compilation, construction, extraction and audits
are excluded. Retain both batches, all failures and raw tails; never trim or
compute survivor-only medians. Eligibility requires every warm-up and repeat
to pass the unchanged physical, membership, objective and solver gates.
Paired ratios compare candidates within the same sweep. Six repeats provide a
descriptive comparison, not independent-sample confidence intervals.

## Results and interpretation

All 48 admission solves and 192 tightened-bound rejection witnesses pass. All
576 measured solves and 96 warm-ups are eligible. The largest absolute SI
objective reconstruction discrepancy is 2.49e-9, and the largest within-cell
objective spread is 1.94e-9. Cost models contain 2508 variables; tracking models
contain 2352, independently of the six scaling treatments. The added loads'
nominal column units range from 31.79 to 5971.71 VA in LV and from 6659.92 to
40990.08 VA in MV.

No inherited voltage, line-current or transformer-nameplate limit is active in
these admission endpoints under the recorded activity thresholds (1e-5 V/A,
1e-3 VA). Thus the panel verifies retention and rejection of those limits but
provides no timing evidence for their active-boundary behaviour. DER operating
limits remain present; the statement about inactivity concerns the recorded
inherited network-limit families only.

## Confirmation median Ipopt wall time (ms)

| Filter | Objective | Ipopt scaling | 1k off | 1k laws | Class off | Class laws | Nominal off | Nominal laws |
|:--|:--|:--|--:|--:|--:|--:|--:|--:|
| low | quadratic_cost | none | 83.097 | 82.704 | 81.736 | 82.819 | 82.958 | 83.043 |
| low | quadratic_cost | gradient-based | 84.252 | 83.112 | 83.910 | 83.708 | 85.304 | 83.739 |
| low | exchange_tracking | none | 162.782 | 163.746 | 162.533 | 163.159 | 134.170 | 130.945 |
| low | exchange_tracking | gradient-based | 115.647 | 115.235 | 116.522 | 111.867 | 113.886 | 115.206 |
| high | quadratic_cost | none | 76.919 | 80.080 | 81.347 | 78.420 | 80.691 | 78.627 |
| high | quadratic_cost | gradient-based | 78.421 | 81.861 | 80.938 | 78.700 | 78.408 | 81.226 |
| high | exchange_tracking | none | 91.532 | 92.343 | 91.096 | 92.773 | 93.914 | 92.561 |
| high | exchange_tracking | gradient-based | 131.287 | 120.601 | 117.407 | 119.244 | 121.866 | 122.177 |

## Paired column effects with assembly-unit rows

| Batch | Filter | Objective | Ipopt scaling | Class / 1k | Nominal / 1k |
|:--|:--|:--|:--|--:|--:|
| exploration | low | quadratic_cost | none | 1.0107 | 1.0132 |
| exploration | low | quadratic_cost | gradient-based | 1.0131 | 1.0116 |
| exploration | low | exchange_tracking | none | 1.0009 | 0.8121 |
| exploration | low | exchange_tracking | gradient-based | 1.0156 | 0.9877 |
| exploration | high | quadratic_cost | none | 0.9968 | 1.0074 |
| exploration | high | quadratic_cost | gradient-based | 0.9913 | 1.0146 |
| exploration | high | exchange_tracking | none | 1.0020 | 1.0055 |
| exploration | high | exchange_tracking | gradient-based | 0.9528 | 0.9202 |
| confirmation | low | quadratic_cost | none | 0.9871 | 0.9967 |
| confirmation | low | quadratic_cost | gradient-based | 0.9967 | 1.0061 |
| confirmation | low | exchange_tracking | none | 0.9967 | 0.8212 |
| confirmation | low | exchange_tracking | gradient-based | 1.0121 | 0.9887 |
| confirmation | high | quadratic_cost | none | 1.0196 | 1.0005 |
| confirmation | high | quadratic_cost | gradient-based | 1.0125 | 1.0033 |
| confirmation | high | exchange_tracking | none | 1.0054 | 1.0109 |
| confirmation | high | exchange_tracking | gradient-based | 0.9217 | 0.9551 |

## Range of per-cell paired median row effects

| Columns | Exploration | Confirmation |
|:--|--:|--:|
| uniform_1k | 0.9344–1.0276 | 0.9366–1.0200 |
| voltage_class | 0.9706–1.0109 | 0.9626–1.0184 |
| nominal_max | 0.9822–1.0271 | 0.9751–1.0176 |

Ratios below one favour the treatment. These are medians of within-sweep ratios,
which need not equal ratios of the separate median times above. Ranges in the
last table span eight cell medians within each batch, not individual trials or
confidence intervals.

For low-filter tracking with Ipopt scaling off, nominal-demand columns reduce
iterations from 37 to 29 and wall time by about **18–19%** with assembly-unit
rows in both batches. Row scaling is not necessary for this gain. The same
nominal-column treatment produces only small mixed changes elsewhere except
high-filter gradient-scaled tracking, where the uniform control takes 27
iterations and every other treatment takes 26. In that cell, voltage-class and
nominal columns with assembly-unit rows give paired median gains of roughly
5–8% and 4–8%, respectively.

These conditional gains do not override solver-policy choice. Low-filter
tracking is still faster with gradient scaling (about 112–116 ms for the leading
confirmation arms) than the improved no-scaling nominal-column arm (about
131–134 ms). High-filter tracking is faster without gradient scaling (about
91–94 ms). Nominal columns therefore improve one difficult numerical path;
they do not improve the best time across every available solver policy by 18–19%.

Cost takes 23 iterations at low filters and 21 at high filters for every arm;
its small timing differences change ordering across batches. Every row-policy
range crosses one. The evidence supports retaining nominal and voltage-class
column units as conditional candidates while keeping **1 kVA columns with
assembly-unit rows as the common control**. All alternatives and global defaults
remain unchanged. Broader feeder families, single-phase MV/LV scenarios and
active-boundary cases remain necessary for generalization.

## Derivative and regression checks

After timing, 24 NLPDiagnostics evaluations check all six arms and both
objectives at common unloaded and independently solved full-model SI endpoints
on the high-filter scenario. The entire Jacobian satisfies
``J_t=D_r J_{\mathrm{control}}D_c`` to maximum entrywise scaled discrepancy
``2.2204460492503126\times10^{-16}``, using denominator
``\max(1,|J_t|,|D_r J_{\mathrm{control}}D_c|)``. There are 120 LV and 36 MV
rows in each load-definition/law group per evaluation. All evaluations use
symbolic or constructed nonlinear automatic derivatives, with no failures or
finite-difference fallback; every full endpoint passes membership. Unloaded
points need not be feasible. This verifies the coordinate/equality scaling
identity, not KKT conditioning or a speed mechanism.

The full regression passes **121,633 assertions**, including 53 new checks for
declared subsets, unchanged controls, validation and benchmark forwarding.
The targeted runner suite passes 166 assertions; all 56 executable tutorial
blocks pass. The external archive includes diagnostic source provenance, logs
and endpoint exports as well as timing evidence.

## Reproduction

Use `IVRLoadPowerRowStudy.benchmark` with
`column_treatments=(:uniform_1k,:voltage_class,:nominal_max)` and
`row_modes=(:off,:laws)`. The original eight-arm default remains unchanged.
The [executable tutorial](tutorial_exact_ivr.md#54.-Declare-a-scaling-transfer-panel)
shows the candidate construction. Duplicate, empty and unsupported declarations
are rejected; reports retain resolved assignments and ordering.

Raw evidence, source snapshots, case-screening records, original and derived
input hashes, admission exports and logs are stored outside Git in
`MV_TRANSFER_20261006` under the local compiler evidence archive. No global
optimum is certified, and two feeders cannot establish a universal scaling
recommendation.
