# Single-phase load scaling near voltage bounds

This experiment tests whether the retained power formulations and load-unit
rules transfer to single-phase DER and voltage-dependent demand on a three-phase
MV/LV feeder. It distinguishes physical voltage-band interventions from exact
numerical reformulations. Single-phase channels do not imply that the whole
network is single-phase.

## Selection and sequential protocol

Screen original, non-French `output/*/original/*.json` cases in BMOPFDraftData.
Require a transformer, at least three positive single-phase loads, and no
existing generators or IBRs. Sort by bus count and then path. Reject undeclared
ground terminals before choosing a case; this is an electrical-declaration
screen, followed by full compiler admission.

The seven smallest candidates have a ground terminal `"5"` absent from their
declared bus terminals. Preserve these failures without repairing the inputs.
The first remaining case is `DSuite_SPM_Rural.json`: 70 buses and an 11 kV/415 V,
200 kVA delta-wye transformer. This is a return to the earlier rural feeder
under a new bound policy and numerical panel, not an independent feeder sample.

Retain every original electrical field. Add devices at the 35 positive LV load
sites: 18 single-phase generators and 17 filtered single-phase battery IBRs.
Add 10% parallel active demand and 2% reactive demand relative to each original
nominal active load, cycling constant-current, ZIP and exponential laws. The
inherited zero-demand records remain. Filter, DC and capability limits use the
existing [mixed-device scenario](ivr_mixed_devices.md). All new fields and
records have exact before/after manifests.

At selected buses, add missing phase-neutral voltage-bound fields on every
non-neutral terminal. Existing fields remain unchanged. The declared bands are:

| Band | Added lower bound | Added upper bound |
|:--|--:|--:|
| `:wide` | 200 V | 260 V |
| `:tight` | 0.98 times unloaded voltage | 1.02 times unloaded voltage |
| `:narrow` | 0.995 times unloaded voltage | 1.005 times unloaded voltage |

These are experimental operating bands, not statutory limits. The first two
bands were specified before admission. All 72 admissions passed, but no voltage
bound was active: the smallest slack exceeded 2.31 V. The third band was then
declared, before its solves, as a sequential test of the active-boundary
hypothesis. Preserve that sequence and all original outcomes; it is not a
three-band protocol specified before seeing any results. No bound is relaxed
to obtain feasibility.

The quadratic power-cost objective is unchanged. Exchange tracking targets
17,500 W (half the original signed nominal demand) and zero var, with the same
DER tracking terms. Targets are fixed before admission, independently of the
solution. Transformer nameplates use `:bmopftools` throughout.

## Numerical factors and acceptance

Cross `full_powers`, `reduced_powers` and `reduced_reuse` with three treatments:

1. Uniform 1 kVA load-power columns and assembly-unit load rows.
2. Nominal apparent-power load columns and assembly-unit rows.
3. The same nominal columns and nominal-unit voltage-law rows.

Nominal units are the maximum channel `hypot(P_nom,Q_nom)`, with a 1 VA floor.
Here each added load receives approximately 101.98 VA. This tests a uniform
change of load-auxiliary units, not a heterogeneous MV/LV power-base assignment.
The voltage-class rule would assign 1 kVA to every added load and duplicate the
control; it remains available in the other runners.

Every arm enables exact load-power lifting. Electrical assembly and generator
units remain 10 kVA, other power lifts 1 kVA, transformer coordinates nominal,
circuit rows composed, finite-ground coordinates voltage-scaled, and objective
scale one. All models therefore use per-unit coordinates. Both `none` and
`gradient-based` Ipopt scaling are explicit factors. All other formulation and
scaling options remain available; this shortlist changes no package default.

Admission requires strict solver success, complete encoding of a common SI
unloaded start, independent physical residuals, own/full-reference membership,
reverse membership of the anchor, and independently reconstructed power
objectives. Successful endpoints receive formulation-independent SI JSON
exports and reader round trips. Nonconvex local success does not certify a
global optimum or uniqueness of the recovered dispatch.

`voltage_activity` independently computes signed SI slacks. A finite bound is
geometrically active when its slack lies in `[0, 1e-4]` V; negative slack is
reported as a violation. Added and inherited fields are identified separately.
This is not a multiplier or sensitivity test, and does not replace physical
acceptance tolerances. Benchmark JSON retains both `vpn_min_slack_V` and
`vpn_max_slack_V` for every successful trial.

## Admission evidence

All **108 admission solves** pass: nine arms, three bands, two objectives and
two Ipopt policies. Both initial bands are inactive at every endpoint. Under
`:narrow`, every cost endpoint reaches two added upper bounds (`14487267/c`
and `14488442/b`); every tracking endpoint reaches five added lower bounds
(`14487258/b`, `14487261/a`, `14487267/c`, `14488442/b`, `14489659/c`).
The active sets agree across numerical treatments and solver policies.

A separate Python audit recomputes voltage slacks and power objectives from
the 108 SI exports. It verifies equal physical export structures, exact
preservation of original fields, filter-loss identities, 44,064 inherited line
current slacks and 324 inherited transformer nameplate slacks. Maximum objective
reconstruction error is below 2.23e-15; maximum filter-loss error is below
5.24e-13 W. Inherited line and nameplate margins exceed 561 A and 57.4 kVA,
respectively. This panel therefore establishes admitted operation at added
voltage boundaries, not at inherited equipment boundaries.

The 452 targeted assertions cover exact scenario-manifest replay, unchanged
input fields, preservation of existing voltage bounds, invalid-ground refusal,
voltage activity/violation distinction, numerical factor isolation, ownership,
and strict full/reduced comparisons on a separate two-wire fixture. This adds
evidence for single-phase load channels without extending the supported element
or control inventory.

## Timing design

For timing, use two fresh Julia processes, each with all three bands, both
objectives and both Ipopt policies. Each cell has nine excluded warm-ups and
nine randomized cyclic sweeps: 1,944 measured solves and 216 warm-ups in the
complete design. Each candidate occupies each position once per cell and batch;
the design is not predecessor-balanced. Seeds are 20261016/20262016 plus the
zero-based band index. Use one Julia/BLAS thread, MUMPS AMD, strict `1e-10`
tolerances, zero acceptable iterations and bound relaxation, 500 iterations,
and a 30 CPU-second solve limit.

Rank only Ipopt wall time. Compilation, model construction, extraction and
audits are excluded. Retain every trial and tail, with no survivor-only medians;
eligibility requires every warm-up and repeat to pass. Compare ratios within
the same sweep. Nine repeats give descriptive comparisons, not independent
sample confidence intervals. Sample active Julia processes every ten seconds
and disqualify timing if a competing Julia job is observed. This monitor cannot
certify absence of all system load or jobs shorter than its sampling interval.

### Completed campaign and isolation failure

Both fresh-process batches completed: **1,944/1,944 trials** and **216/216
warm-ups** pass every solver and physical gate. All 2,160 endpoints reproduce
the expected voltage active sets. Independent SI objective reconstruction error
is below 1.78e-15, and maximum within-cell objective spread is below 2.44e-13.
All 253 frozen source/input hashes are unchanged.

However, another Julia workload started during the campaign and was detected by
the process monitor. **The entire campaign is ineligible for performance
claims**, including the raw benchmark JSON's provisional ranking fields.
The performance-analysis script refuses these data. Retain all raw timings,
statuses and isolation records as evidence of the attempted experiment and its
successful solve validation; do not promote a fastest profile or selectively
reuse apparently quiet portions. A complete repeat in a separately named
archive is required before drawing a new speed conclusion.

The separately archived `SINGLEPHASE_ISOLATED_REPEAT_20261006` repeat uses the
same input bytes, archived benchmark modules, seeds and strict gates, with the
current package source verified against the original freeze. A competing Julia
job also starts during this repeat. Its entire campaign is likewise excluded
from speed claims and retained separately; the isolation criterion is unchanged.
All 1,944 repeat trials and 216 warm-ups pass the solver, physical and active-set
gates. This additional validation does not restore timing eligibility.

A third attempt, `SINGLEPHASE_ISOLATED_CONFIRMATION_20261006`, again detects an
external Julia process. The task interrupts only its own benchmark and retains
882 completed measured trials and 99 warm-ups, all accepted in their saved
reports. Ten cells are complete and one is partial; the confirmation process
never starts. All 142 frozen hashes are verified before subsequent development.
The entire partial campaign is excluded, including provisional ranking fields.
No other workload is terminated. The original inputs and source-at-stop snapshot
remain available, so later code changes do not obscure the attempted protocol.

## Isolated confirmation — 6 October 2026

A fourth, separately frozen attempt, `SINGLEPHASE_ISOLATED_R4_20261006`, completes
both batches without a detected competing Julia process. It uses package commit
`df9ca4a28af9e9e4f742a7e7e0b8646d4403b771`, the unchanged three physical inputs,
archived current benchmark modules and the original seeds and acceptance gates.
All **1,944 measured solves and 216 warm-ups pass**. Every profile is eligible
in all 24 batch/cell combinations, with the same expected voltage active sets.
All 276 frozen source/input/control hashes are verified unchanged. None of the
three excluded campaigns contributes to these timing statistics.

The monitor samples Julia processes every two seconds and records 142 snapshots.
This establishes absence of *detected competing Julia processes*, not absence
of all operating-system load or jobs shorter than the sampling interval. Runs
use Julia 1.12.6, JuMP 1.31.2 and Ipopt.jl 1.16.0 on Apple M4, one Julia/BLAS
thread, and the settings specified above. Both batches are fresh processes on
the same machine and day; they are not independent hardware or feeder samples.

The primary metric is `MOI.SolveTimeSec`, exposed by `JuMP.solve_time`: Ipopt.jl
optimizer-call wall time, including backend setup and native `IpoptSolve`.
FormulationLab construction/compilation, preceding JuMP cache transfer, result
extraction and audits do not enter the ranking. Every arm receives an excluded
warm-up in each cell. The design controls candidate position but not predecessor
or all machine-load effects. No confidence interval or universal fastest claim
is inferred from these short repeated runs.

### Leaders and repeatability

`RP` denotes reduced power lifting without generator reuse; `RG` additionally
reuses generator power definitions. The suffix is `U` for uniform 1 kVA load
columns with assembly-unit rows, `C` for nominal load columns with assembly-unit
rows, or `R` for nominal columns and nominal voltage-law rows. These are exactly
the nine previously declared arms, including the three full-IVR controls.

| Band | Objective | Ipopt scaling | First-batch leader | Confirmation leader | Confirmation median (ms) |
|:--|:--|:--|:--|:--|--:|
| wide | Cost | none | RP-R | RP-U | 21.057 |
| wide | Cost | gradient-based | RP-R | RP-R | 20.718 |
| wide | Tracking | none | RG-U | RG-C | 12.020 |
| wide | Tracking | gradient-based | RG-C | RG-R | 12.167 |
| tight | Cost | none | RP-R | RP-R | 23.696 |
| tight | Cost | gradient-based | RP-R | RP-R | 23.715 |
| tight | Tracking | none | RG-U | RG-U | 13.423 |
| tight | Tracking | gradient-based | RG-U | RG-R | 13.414 |
| narrow | Cost | none | RG-R | RG-R | 27.099 |
| narrow | Cost | gradient-based | RG-R | RG-R | 27.433 |
| narrow | Tracking | none | RG-U | RG-C | 25.413 |
| narrow | Tracking | gradient-based | RG-U | RG-R | 25.356 |

The leading **formulation family repeats in all 12 cells**, while the complete
formulation/scaling choice repeats in only **6/12**. Tracking consistently favors
the reuse family, but its load-unit winner changes in five of six cells. The
wide cost cell with scaling off also changes its winning load treatment. These
changes counsel retaining nearby alternatives rather than treating every small
median difference as a reproducible benefit. All tails remain in the archive;
for example, the narrow cost/gradient winner ranges from 27.061 to 42.339 ms in
confirmation despite its 27.433 ms median.

### Matched effects

For each measured sweep, divide treatment Ipopt time by the matched control
time. The table reports the range of the resulting *within-cell median ratios*
over the 18 conditions per objective and change. A ratio below one favors the
treatment. Conditions combine three bands, two solver policies and three other
factor settings; they are not 18 independent networks. “Faster in both batches”
records repeated direction, not a significance test. Ratios are not ratios of
the separately reported candidate medians.

The column change compares nominal with uniform columns while keeping rows at
assembly units. The row change adds nominal voltage-law row scaling with nominal
columns held fixed. Reduction compares reduced power lifting with full power
lifting at the same load-unit treatment. Reuse compares generator reuse with
unreused reduced power lifting.

| Objective | Matched change | Faster in both batches | Confirmation paired-ratio range |
|:--|:--|--:|--:|
| Cost | column | 7/18 | 0.9834–1.0166 |
| Cost | row | 16/18 | 0.9025–1.0149 |
| Cost | reduction | 17/18 | 0.9644–1.0000 |
| Cost | reuse | 4/18 | 0.9902–1.0914 |
| Tracking | column | 6/18 | 0.9886–1.0059 |
| Tracking | row | 6/18 | 0.9860–1.0305 |
| Tracking | reduction | 18/18 | 0.9570–0.9985 |
| Tracking | reuse | 17/18 | 0.9771–1.0109 |

Column rescaling alone has no consistent direction and changes these medians
by roughly 1–2%. It should remain a controlled factor, not an automatic rule that
lower LV power implies a faster smaller base. Reduction has a modest repeated
benefit, while reuse usually benefits tracking and slows cost in **12/18**
matched conditions in both batches. Fewer variables alone do not predict the
better cost formulation: cost profiles have 1,355, 1,253 and 1,217 real variables
for full, reduced and reuse, respectively.

The clearest row-scaling effect occurs in the **tight cost** band, whose voltage
bounds remain inactive. With nominal columns fixed, nominal row scaling reduces
full and unreused reduced iterations from 22 to 20, and reuse iterations from
23 to 22, under both solver policies and both batches. Confirmation matched
ratios are 0.9025–0.9158 for full/unreused reduction, and 0.9541–0.9590 for reuse.
Thus a changed iteration path appears before a voltage bound becomes active;
active-set membership alone cannot select the best numerical scaling.

In narrow cost, every arm takes 23 iterations. Reuse with nominal rows leads in
both batches under both solver policies, but its matched advantage over unreused
reduction is small (confirmation ratios 0.9912 and 0.9965). This is a conditional
candidate, not evidence that reuse universally improves economic objectives.
Tracking iteration counts remain 9/10/22 for wide/tight/narrow across every arm;
its small reduction/reuse gains occur without iteration-count changes.

### Admission and recommendation

A separate report audit rechecks every raw physical/model gate, complete common
SI-start encoding, declared bases and solver policy. Maximum difference between
the solver objective and the independently reconstructed power objective is
``1.78\times10^{-15}``; maximum within-cell objective spread, including warm-ups,
is ``2.44\times10^{-13}``. The earlier 108-export independent SI audit remains
separate: this timing audit is not a new independent current-reconstruction
study. The JSON timing reports retain objectives, statuses, physical checks,
active-bound slacks and all raw trials in the existing benchmark format.

For this single-phase mixed-device feeder, retain **unreused reduced power
lifting for wide/tight cost**, with nominal voltage-law row scaling especially
useful in tight cost. Add **reuse with nominal rows for narrow cost**, and keep
**reduced reuse for tracking**, with load-unit alternatives close enough to retain.
Full power lifting remains the reference and robust comparator. These findings
refine a workload-specific shortlist; they change no package default and remove
no transformation option. Transfer to independent feeders and mixed-winding
networks remains necessary before a broader recommendation.

The inherited equipment boundary extension has since been completed in the
[transformer-boundary study](ivr_equipment_boundaries.md) and subsequent
[line-boundary study](ivr_line_boundaries.md). Those physical interventions are
separate from the timing comparison here; their results do not justify weakening
any original bound or discarding a historical treatment.

## Reproduction

```julia
include("examples/benchmark_ivr_singlephase_transfer.jl")
S = IVRSinglePhaseTransferStudy
original, detached = S.P.compiler_feeder_input(source_path;
    detach_legacy_provenance=true)
net, additions = S.scenario(original;voltage_band=:narrow)
profiles = S.profiles(net,:exchange_tracking;
    exchange_target_W=17_500.,nlp_scaling_method="gradient-based")
```

Save the scenario and its original-source/addition manifest separately, then
call `S.benchmark(scenario_path, output_path; ...)` with the same objective and
policy. The wrapper stores its supplied input, hashes, options and balanced
orders. The external archive `SINGLEPHASE_TRANSFER_20261006` preserves screening,
the initial and extended protocols, admission outputs, source snapshots and
subsequent measurements. The executable tutorial uses a small two-wire case
that does not depend on the external dataset.
