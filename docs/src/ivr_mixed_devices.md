# Mixed-device transfer on a rural feeder

A formulation that helps constant-power demand and ideal dispatch need not help
filtered converters or voltage-dependent demand. This study extends the recent
power-objective panels to another feeder and explicitly distinguishes converter
terminal power from internal power. Every existing transformation remains
available; no production equation or package default changes.

## Physical scenarios and scope

The source is `output/DSuite/original/DSuite_SPM_Rural.json` from BMOPFDraftData:
70 buses, one lossy delta/wye MV/LV transformer and 56 single-phase loads, of which
35 have nonzero demand totalling 35 kW. It is new to these recent timing panels;
it is a selected transfer case, not a random held-out population sample. The
66-bus SPD rural file was inspected first and rejected before timing because its
load powers were all zero. No supplied IBR was identified in the inspected output
networks, so both scenarios declare their added dispatch explicitly.

`IVRMixedDeviceStudy.scenario` in `examples/benchmark_ivr_mixed_devices.jl` selects
positive single-phase loads whose unloaded coil voltage lies in 200–260 V,
sorted by load identifier. CP70 adds one generator at each of the 35 selected
loads. Each has P in [0, 2] kW, Q in [−1, 1] kvar, 2 kVA apparent-power rating and
10 A current limit. MIXED70 replaces every second added generator with a
single-phase filtered IBR, yielding 18 generators and 17 IBRs. Each IBR has
0.2 + j0.08 Ω series filter impedance, 0.001 S shunt susceptance, a coupled
0–1.2 kW internal DC-link budget and 1.6 kW PCC availability limit.

MIXED70 also adds a parallel load at each selected original load, with nominal
100 W and 20 var. The added load laws cycle through constant current, ZIP and
exponential. ZIP active fractions are (0.2, 0.3, 0.5), reactive fractions
(0.4, 0.5, 0.1), ordered impedance/current/power. Exponential exponents are
0.4 for P and −0.5 for Q. Nominal voltage is that load's unloaded physical coil
voltage. Missing phase-neutral bounds of 200–260 V are added at selected buses,
including the strictly positive domain needed by the voltage-dependent laws.
These are experimental limits, not statutory values.

Every original electrical field, original load and supplied equipment limit is
preserved. A before/after manifest records each added or extended record; the
source file is unchanged. Known legacy provenance is relocated on an owned
copy, using the existing importer. Inherited preprocessing is not reversed.
Comparisons between formulations are made **within a physical scenario**.
Differences between CP70 and MIXED70 cannot identify an isolated filter or load-law
effect because several declared physical changes occur together.

## Power objectives and conventions

Let S₀ = P₀ + jQ₀ be total voltage-source exchange, with positive P₀ meaning
supply to the network. Let D contain generator and IBR PCC channels. Powers in
the equations below are measured in kW/kvar. The declared cost is

```math
J_c = 0.25 P_0 + \sum_{d\in D}
\left(0.10\widehat P_d + 0.02P_d^2 + 0.002Q_d^2\right),
```

where P̂ is generator active power for a generator and **internal active power**
for an IBR. Internal IBR power includes resistive filter losses. The independent
recovered-power check verifies that summed internal minus PCC active power equals
Σ R|I_filter|². For a three-leg IBR, native PCC channels are conductor powers,
whereas internal channels are filter-coil powers; only their totals obey this
loss identity. No per-phase equality is assumed.

The tracking objective uses PCC power throughout:

```math
J_t=(P_0-10)^2+Q_0^2+
0.01\sum_{d\in D}\left[(P_d-P_d^{\mathrm{mid}})^2+Q_d^2\right].
```

Pmid is the midpoint of the declared P box. Source tracking is 10 kW/0 kvar in
both rural scenarios. Coefficients are explicit experimental choices; legacy
price fields are ignored. The objective divisor stays one. The previous
external-generator runner still rejects IBRs; this separate runner provides the
required objective design instead of silently changing earlier studies.

## Controlled numerical profiles

All profiles use 10 kVA assembly and generator dispatch units, 1 kVA lifted-power
units, nominal transformer coordinates, composed row scaling, voltage-ground
scaling, MUMPS AMD and one Julia/BLAS thread. Reduced profiles use conductor
regions and transformer-current elimination. Signed observation sharing uses
support threshold two; generator reuse does not imply IBR reuse.

| Profile | Line elimination | Lifting | Generator reuse |
|---|---|---|---|
| `full_powers` | off; full coordinates | powers | off |
| `reduced_powers` | passive blocks | powers | off |
| `reduced_reuse` | passive blocks | powers | on |
| `blocks_signed` | passive blocks | bounded observations | off |
| `blocks_signed_reuse` | passive blocks | bounded observations | on |
| `cap4_signed_reuse` | hybrid, cap four | bounded observations | on |

Cost and tracking cross Ipopt `none` and `gradient-based` scaling. Both retain
physical per-unit coordinates. A common unloaded linear-circuit physical point
is encoded completely in every formulation, including filter currents and
voltage-law auxiliaries. Strict existing 1e-10 solver tolerances are unchanged.

Each of eight scenario/workload/policy cells has six excluded warm-ups and six
randomized cyclic sweeps. Exploration and confirmation use fresh Julia processes
per scenario and batch, with seeds 20261007 and 20262007. Candidate positions are
balanced; predecessor pairs are not. The panel has 576 measured solves, 96
warm-ups and 48 preflight exports. Only `ipopt_wall_s` ranks profiles, excluding
construction, initialization, extraction and audits. Tests, documentation builds,
other solver work and native diagnostics do not overlap timed campaigns. All
trials, slow tails and both batches are retained without selective reruns or pooling.

## Verification and interpretation

Before timing, every profile must pass physical residuals, its own model,
full-model membership and reverse membership of the full-model solution. SI JSON
exports must round-trip and expose the same physical tables across formulations.
IBR filter currents, internal voltages and internal powers are retained under
`_formulationlab.devices.ibr`, alongside BMOPFTools-compatible top-level fields.

At each preflight point, independently tightened generator capability and bus
voltage limits must fail both physical and encoded checks; MIXED70 also tightens
an IBR internal DC budget. These are unchanged recovered-point rejection tests,
not new optimization runs. Cost preflights have all 35 CP70 generator ratings
active; MIXED70 has all 18 generator ratings and all 17 IBR DC budgets active.
Tracking has none of these ratings active. Existing equipment limits are retained,
but these observed active ratings are the explicitly added scenario limits.

The test suite additionally covers single-phase, three-leg delta and four-leg
IBRs under both objectives and both solver policies. It checks internal-loss
identities, original capability/DC/voltage rejection, complete starts and exact
result recovery. The first test run addressed the correct export values through
the wrong namespace; correcting the test to use the existing extension namespace
resolved it. No result schema or solver tolerance changed.

## Confirmation results

All **576 measured solves, 96 warm-ups and 48 preflight SI exports** pass.
All **120 tightened-bound witnesses** reject through both checks. An independent
audit verifies the unchanged source, exact additions, frozen code, starts,
position balance, physical membership and all 96 paired contrasts. Maximum
recovered-objective discrepancy is 3.78e-15; within-cell spread is 1.71e-14.

The table gives confirmation median **Ipopt wall milliseconds**.

| Scenario | Profile | Cost / none | Cost / gradient | Tracking / none | Tracking / gradient |
|---|---|---:|---:|---:|---:|
| CP70 | `full_powers` | 16.252 | 16.218 | 9.013 | 9.091 |
| CP70 | `reduced_powers` | 15.531 | 15.462 | 8.702 | 8.663 |
| CP70 | `reduced_reuse` | 15.997 | 16.052 | 8.444 | 8.457 |
| CP70 | `blocks_signed` | 15.777 | 15.765 | 8.819 | 8.850 |
| CP70 | `blocks_signed_reuse` | 16.207 | 16.249 | 8.540 | 8.513 |
| CP70 | `cap4_signed_reuse` | 16.181 | 16.106 | 8.561 | 8.492 |
| MIXED70 | `full_powers` | 20.743 | 20.819 | 12.271 | 12.226 |
| MIXED70 | `reduced_powers` | 20.179 | 20.191 | 11.908 | 11.832 |
| MIXED70 | `reduced_reuse` | 21.341 | 21.235 | 12.113 | 11.933 |
| MIXED70 | `blocks_signed` | 20.676 | 20.620 | 12.094 | 11.932 |
| MIXED70 | `blocks_signed_reuse` | 21.626 | 21.662 | 12.160 | 11.943 |
| MIXED70 | `cap4_signed_reuse` | 21.865 | 21.600 | 12.165 | 12.044 |

## Paired contrasts

Each entry is the median of six within-sweep treatment/control ratios; below
one favours treatment. E/C means exploration/confirmation, reported separately.
R/F compares reduced/full power lifting; reuse compares power lifting with/without
generator reuse; cap compares cap-four/block signed-observation profiles with
reuse. Ratio medians need not equal ratios of the separate timing medians.

| Scenario | Objective | Policy | R/F E | R/F C | Reuse E | Reuse C | Cap E | Cap C |
|---|---|---|---:|---:|---:|---:|---:|---:|
| CP70 | quadratic_cost | none | 0.9549 | 0.9567 | 1.0269 | 1.0305 | 0.9924 | 0.9991 |
| CP70 | quadratic_cost | gradient-based | 0.9475 | 0.9545 | 1.0098 | 1.0448 | 1.0021 | 1.0035 |
| CP70 | exchange_tracking | none | 0.9576 | 0.9593 | 0.9723 | 0.9656 | 1.0014 | 0.9939 |
| CP70 | exchange_tracking | gradient-based | 1.0002 | 0.9544 | 0.9314 | 0.9683 | 0.9944 | 0.9973 |
| MIXED70 | quadratic_cost | none | 0.9564 | 0.9773 | 1.0600 | 1.0528 | 0.9831 | 1.0085 |
| MIXED70 | quadratic_cost | gradient-based | 0.9735 | 0.9690 | 1.0552 | 1.0552 | 0.9687 | 0.9920 |
| MIXED70 | exchange_tracking | none | 0.9664 | 0.9699 | 1.0103 | 1.0097 | 1.0311 | 0.9990 |
| MIXED70 | exchange_tracking | gradient-based | 0.9286 | 0.9650 | 1.0026 | 1.0096 | 1.0376 | 1.0087 |

## Interpretation

Reduced power lifting wins all four mixed-device confirmation cells. Its paired
improvements over the full control range from 2.3–4.4% for cost and 3.0–7.1% for
tracking across both batches and policies. The gradient-scaled tracking winner
changes from signed observations to power lifting between batches, indicating
that the much smaller difference between those reduced candidates is uncertain.

Generator reuse removes 70 real variables in CP70 and 36 in MIXED70. Nevertheless,
it adds an iteration on cost (15→16 and 17→18 respectively). Mixed cost slows
5.3–6.0% in the matched power-only comparison. CP70 tracking benefits by 2.8–6.9%,
whereas mixed tracking has reuse/control medians 1.003–1.010. Reduced power lifting
without reuse is the mixed-case shortlist; CP70 tracking retains reuse. These
results reinforce objective- and device-dependent selection, not a universal
reuse rule or a claim that fewer variables must solve faster.

Bounded observations add 24 real variables relative to reduced power lifting in
CP70 and mixed tracking, and 92 in mixed cost. They do not establish a repeatable
advantage here. The cap-four versus block arms eliminate the same series buses;
the largest hybrid component contains only two buses. An independent audit checks
identical MOI algebra and coordinate maps in all eight cells. Their timing
variation therefore cannot be interpreted as a benefit from capping components.
All arms and tails remain available for a feeder where that factor activates.

All mixed tracking profiles take nine iterations; constant-power tracking takes
seven. This does not identify a specific filter/load-law effect because the
physical scenarios differ in several ways. Neither native factorization time,
KKT fill, global optimality nor population generalization is established. The
next common urban panel should retain power-only/reuse controls alongside the
signed-observation candidates and older power-base finalists.

## Reproduce and extend

Use `IVRMixedDeviceStudy.scenario(original; mixed=true)` to obtain an owned
network and an exact additions manifest. Save both outside Git. Then call
`IVRMixedDeviceStudy.benchmark(input_path, output_path;
workload=:exchange_tracking, exchange_target_W=10000.,
nlp_scaling_method="gradient-based")`, with a distinct output path for each cell.
The original dataset is not bundled. The [executable tutorial](tutorial_exact_ivr.md)
uses a small manufactured network without external data.

This panel does not retest all power bases or proportional-sharing thresholds.
Single-phase IBRs supply the external timing evidence; three-leg and four-leg
IBRs have correctness evidence here. Larger independent feeders, three-phase IBR
timing, separate load/filter interventions and original-network preprocessing
reconstruction remain further transfer questions. Local solutions and matching
objectives provide no global AC optimality certificate.
