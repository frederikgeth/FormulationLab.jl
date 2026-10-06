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

The remaining boundary experiment concerns inherited equipment ratings. It
should use declared DER-capacity and source-export workloads to approach those
limits while retaining original equipment data. The present results do not
justify weakening or deleting any original bound, numerical option or failed
historical treatment.

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
