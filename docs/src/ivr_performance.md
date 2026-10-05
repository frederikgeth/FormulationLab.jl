# Best-evidence exact-IVR profiles

All transformation and reformulation options remain available. A configuration
that is slower on one panel is still useful for future numerical evidence.
Recommendations here are additive; package defaults and the individual options
are unchanged. “Fastest” always refers to a declared workload, accepted physical
solutions, a candidate set, solver settings and a measured environment.

## Primary assessment: Ipopt wall-clock time

The primary assessment now **excludes the cost of constructing reduced models**.
Rank profiles by `ipopt_wall_s`, obtained from `JuMP.solve_time(model)` / MOI's
`SolveTimeSec`. The installed Ipopt.jl 1.16.0 implementation measures elapsed
wall time from entry to its optimizer call through completion of `IpoptSolve`.
This includes backend setup and solver evaluations; it excludes FormulationLab
construction, JuMP cache transfer before that call, result extraction and audits.
It is not CPU time or an isolated native factorization timer.

The report's `fastest_ipopt` is the primary winner. Construction allocations,
`fastest_total` and `fastest_solve` remain secondary diagnostic fields and do not
influence it. Here `solve_s` / `fastest_solve` retain their original meaning:
the surrounding solve wrapper **including extraction**. Historical reports do
not contain isolated Ipopt timings and cannot be relabelled as such. Missing,
nonfinite or negative Ipopt timings withhold the primary winner, without
inventing a value from those older measurements.

All physical/model admission rules and objective-comparability requirements
still apply. A failed profile cannot win on time. Warm-ups are excluded and
no construction-time penalty is applied to any transformation. All options
remain available, including configurations that lose this particular comparison.

## Current Ipopt evidence and recommended starting profile

The new Ipopt-only screen selects the same common starting profile, now under
an independent timing criterion:

```julia
formulation = IVRNLP(objective=:feasibility,
    specialization=:conductor_regions,
    linear_elimination=:passive,
    series_selection=:all,
    ground_scaling=:voltage)
```

The screen reruns all 12 profiles on the original five inputs. Among profiles
admitted on every input, `scaled_regional_passive` minimizes the **sum of
per-case median Ipopt wall seconds**: 0.520009 s versus 1.128893 s for full IVR.
These are selection-set measurements, not out-of-sample estimates. Construction
and extraction contribute nothing to this score. The eight measured ENWL
failures of unscaled passive combinations remain excluded and preserved.

Freeze the common choice before testing four feeders excluded from this screen.
Compare it with full IVR and the predeclared `scaled_passive` and
`selected_regional_passive` alternatives. Eight balanced measured sweeps per
feeder give **128/128 accepted solves**, plus 16 accepted excluded warm-ups.
These feeders are held out from this profile-selection panel, not claimed to
have never been examined elsewhere in the project.

| Held-out input | Full Ipopt median (ms) | Frozen common median (ms) | Common/full | Lowest median among four profiles |
|:--|--:|--:|--:|:--|
| DSuite 66 | 2.803 | 2.676 | 0.954 | `scaled_passive`: 2.623 ms |
| DSuite 1,220 | 83.000 | 75.875 | 0.914 | `scaled_passive`: 65.984 ms |
| ENWL 241 | 125.362 | 75.256 | 0.600 | `selected_regional_passive`: 74.996 ms |
| ENWL 435 | 192.730 | 157.493 | 0.817 | `selected_regional_passive`: 143.703 ms |

The frozen common profile reduces the sum of held-out medians from 0.403894 s
to 0.311300 s (**22.9%**), with lower medians on all four inputs. This aggregate
weights slower cases more heavily; it is not a separately timed batch. Its
within-sweep ratios span 0.908–0.997, 0.901–1.313, 0.599–0.602 and 0.805–0.834
in table order. No significance or population claim follows from eight sweeps.

The observed per-case alternatives are useful refinements: `scaled_passive`
uses full conductor coordinates, passive elimination and voltage ground scaling;
`selected_regional_passive` uses regional coordinates and additionally requests
`series_selection=:bound_support`. The latter sums to 0.297022 s on the held-out
panel, but selecting it using that panel consumes the hold-out. These results
support testing those explicit alternatives for similar workloads, not deriving
an automatic rule from feeder family or bus count. No option or default changes.

### Dispatch changes can reverse the ranking

Four manufactured cost cases use 20-segment single-phase two-wire and delta
three-wire feeders, with constant-power loads at even buses and a bounded DER
at the last bus. A priced ideal source supplies the network; there is no
colocated free source/generator pair. Compare DER prices 0.2 and 2.0 currency/kWh
against source price 1.0, keeping the same physical circuit within each pair.
All four frozen profiles pass every physical/model gate and objective comparison:
**128/128 measured solves** and 16 excluded warm-ups. Solver objective scaling
is 1000 in every variant, without changing reported economic objectives.

| Circuit / DER price | Full Ipopt median (ms) | Common median (ms) | Common/full | Lowest median |
|:--|--:|--:|--:|:--|
| Single phase / 0.2 | 2.577 | 2.153 | 0.835 | Selected regional: 2.152 ms |
| Single phase / 2.0 | 2.480 | 2.078 | 0.838 | Selected regional: 2.061 ms |
| Delta / 0.2 | 13.433 | 4.934 | 0.367 | Selected regional: 4.677 ms |
| Delta / 2.0 | 5.673 | 8.901 | 1.569 | Full: 5.673 ms |

The expensive-DER delta case is a clear counterexample to universal speedup:
common/full iterations are 17/11, versus 10/18 in the cheap-DER case. Accepted
objective values agree across profiles within each case; the ranking reversal
comes with a different operating regime, not a discarded constraint or
construction-time penalty. The derivative structures are unchanged between
the two price cases: the common model has 184 real variables and 561 unique
Hessian entries, versus full IVR's 324 and 670. Even the smaller model can take
more iterations and run slower. These are fresh solves and local optima, not a
repeated-update, warm-start or global-optimality result. Millisecond differences
between the two regional variants on the single-phase cases are near ties.

### What the solver timing breakdown suggests

Four separate instrumented diagnostic solves, with fresh excluded warm-ups,
use Ipopt 3.14.19 and MUMPS 5.9.0. All pass the same admission checks. Their
native timing statistics are excluded from the primary rankings.

| Input / profile | Native algorithm wall (s) | Primal-dual system solver wall (s) | Reported symbolic-factorization wall (s) |
|:--|--:|--:|--:|
| DSuite 2,854 / full | 0.455 | 0.424 | 0.340 |
| DSuite 2,854 / common | 0.295 | 0.267 | 0.191 |
| ENWL 538 / full | 0.646 | 0.604 | 0.017 |
| ENWL 538 / common | 0.202 | 0.172 | 0.014 |

Linear-system work accounts for roughly 85–94% of native algorithm wall time
in these single observations. DSuite's reported symbolic-factorization work is
substantial. The timers are nested and need not partition the total; the
separate numerical-factorization field reports 0.000 s here, which cannot
establish absence of that work. This is useful bottleneck evidence, not measured
factor fill, memory or a complete attribution of numerical factorization.
Next experiments should target solver ordering and derivative/KKT structure,
while retaining iteration counts, physical acceptance and all alternatives.

## Historical build-plus-solve comparison — 5 October 2026

For the five-case **feasibility** panel below, the previous build-plus-solve comparison recommended
the following explicit configuration:

```julia
formulation = IVRNLP(objective=:feasibility,
    specialization=:conductor_regions,
    linear_elimination=:passive,
    series_selection=:all,
    ground_scaling=:voltage)
```

This is the runner's `scaled_regional_passive` profile. It requests certified
regional coordinates, local passive elimination and finite-ground voltage
scaling. Applicability diagnostics still determine which reductions a particular
network admits. The profile neither changes electrical data nor removes bounds.
It was a recommendation under the previous total-time criterion; it does not
by itself establish an Ipopt wall-time ranking or a new package default.

We screened 12 profiles with four measured repeats on each of three external
feeders and two synthetic cases. Of 240 measured solves, 232 passed all admission
gates. The common profile was chosen among profiles admitted on **every** input
by minimizing the sum of per-case median build-plus-solve times: one fresh run
of each input. This weights the larger, slower cases more heavily than the small
ones. The common choice, each input's screen winner and full IVR were then frozen
and compared in six fresh, balanced repeats per input. All 90 confirmation
solves passed. Confirmation did not rerun the entire shortlist.

| Input | Full IVR median total (s) | Common profile median total (s) | Common/full | Lowest confirmation median total |
|:--|--:|--:|--:|:--|
| DSuite 265 | 0.036979 | 0.039432 | 1.066 | `difference_passive`: 0.035504 s |
| DSuite 2,854 | 0.820295 | 0.606483 | 0.739 | `scaled_regional_passive`: 0.606483 s |
| ENWL 538 | 0.747925 | 0.306782 | 0.410 | `selected_regional_passive`: 0.289352 s |
| Synthetic impedance | 0.009273 | 0.009898 | 1.067 | `difference`: 0.009192 s |
| Synthetic alternating loads | 0.008505 | 0.009838 | 1.157 | `full`: 0.008505 s |

Total means timed construction plus solve/extraction, excluding warm-up and
physical/model audits. Ratios here are **ratios of medians**, not medians of
within-sweep ratios. The sum is 0.972433 s for the common profile versus
1.622977 s for full IVR, a 40.1% reduction under this declared weighting. This
aggregate is not the wall time of a separately timed batch. The screen and
confirmation themselves took about 141 s and 65 s inside the runner, including
reference construction, audits and evidence output, but excluding process
startup/module loading. Screening before every solve would overwhelm the gain.

For a known DSuite 265 workload, `difference_passive` requests
`:conductor_difference` and `:passive`, with `series_selection=:all` and
`ground_scaling=:off`. For the measured ENWL input, `selected_regional_passive`
uses the common profile with `series_selection=:bound_support`. These are
workload-specific alternatives, not rules inferred solely from bus count.
The synthetic differences are small; retain full IVR as the simple reference
and collect more evidence before treating a sub-millisecond ranking as robust.

The larger DSuite winner changed between screen and confirmation, and the
synthetic alternating-load winner changed from `scaled_full` to `full`.
Garbage collection is enabled and allocation is attributed to the timed phase
where it occurs. Six repeats do not establish significance or a population
ranking. The common profile's paired total ratios against full IVR span
0.651–0.980 on DSuite 2,854 and 0.388–0.577 on ENWL 538; its small synthetic
alternating-load ratios span 1.141–3.268. These observations support further
use of the common profile on this panel while preserving every competitor.

Solve-only choices differ: `difference_passive` has the lowest confirmation
solve median on both DSuite cases, while the common profile does on ENWL and
the alternating-load synthetic case. This does not establish the fastest
warm-started or parameter-update workflow.

Two screen profiles, `difference_passive` and `regional_passive`, fail the
ENWL physical KCL gate: approximately 22.1 μA against the 1 μA tolerance.
All eight measured failures and two warm-up failures remain in the evidence.
Those options remain available for other circuits and future numerical work;
solver termination alone cannot qualify them for this input. See
[verification](verification.md) for the environment, checks and retained evidence.

## Compare the workload that matters

For the current assessment, compare Ipopt wall time for a declared initial state
and workload. Fresh and reused models, parameter updates and previous-primal
warm starts require separate controlled experiments. Recording their preparation
and extraction costs is useful for provenance, but these costs do not enter the
primary formulation ranking. The studies here exclude warm-ups.

The experimental runner in `examples/benchmark_ivr_profiles.jl` preserves a
12-profile shortlist: full, complete conductor difference, pendant regions,
passive elimination combined with those coordinates, finite-ground scaling,
and bound-support selection. It is not an exhaustive Cartesian search. All
other valid option combinations, including standalone impedance elimination,
remain callable and can be supplied through the runner's `candidates` argument.

```julia
include("examples/benchmark_ivr_profiles.jl")
using LinearAlgebra
BLAS.set_num_threads(1)
report = IVRProfileStudy.benchmark(network, "/tmp/ivr-profiles.json";
    repetitions=4, candidates=IVRProfileStudy.profiles(objective=:feasibility))
```

The explicit feasibility objective makes this a numerical feasibility study.
For an OPF objective, request it consistently across all profiles. The ranking
withholds a winner if accepted objective values differ beyond its declared
comparison tolerances; solving a different local optimum faster is not silently
counted as an equivalent speed improvement. Objective agreement is not a global
optimality certificate or a check of the economic meaning of the input data.

Each profile has an excluded warm-up. Measured sweeps reverse each pair's order
and rotate the starting position between pairs. Four sweeps over 12 profiles
are exploratory, not fully position-balanced. Save the raw trials and confirm
promising choices with new paired runs. Do not overlap timings with tests,
documentation builds or profiling.

## Admission before ranking

A measured trial must satisfy strict solver acceptance, the independent SI
physical audit, its own compiled model, a fresh full model, and reverse mapping
of a full-feasible anchor point into the candidate model. The first accepted
warm-up supplies that anchor. Bounds, coefficients, objective and electrical
inputs are not modified to obtain acceptance. Errors and failed trials remain
in the output; they are not retried with relaxed settings.

A profile must have an accepted warm-up and every requested measured repeat to
enter the ranking. The report gives `fastest_ipopt` as the primary winner and retains
`fastest_total` and `fastest_solve` as secondary diagnostics, with exact options
and provenance. A fast failed or incomplete profile cannot
win. The runner does not mutate a production default or silently replace the
user's chosen representation.

Profile selection itself costs time: reference construction, warm-ups, audits,
all competing runs and evidence output are excluded from each candidate's
Ipopt score. The report separately records `total_study_s`. Tune an
intended repeated workload and reuse its explicit configuration; running the
entire portfolio before every single solve is not a speed optimization.

```julia
name = report["ranking"]["fastest_ipopt"]
name === nothing && error("No comparable accepted winner")
candidate = only(filter(p -> p.name == name, IVRProfileStudy.profiles()))
formulation = IVRNLP(candidate.options)
```

Use the **same candidate list/objective** when looking up the chosen name, and
retain the reported input digest, solver settings and software versions with
any recommendation. Rerun the study when the workload or inputs change.

## Why the structural selector is still optional

The bound-support rule can avoid growth in some operating-bound expressions,
but it does not estimate actual factorization fill or runtime. It previously
added substantial preparation work even when every DSuite candidate remained
selected. Preparation now indexes only a conservative superset of coordinates
that a series candidate could remove, composes the relevant rows once, and
shares resolution caches within each before/after check. Cache lifetimes never
cross a change to the tentative substitutions.

This optimization changes no selection criterion, bound, coordinate map or
formulation option. The frozen implementation, exact model/decision audit,
paired allocation experiment and raw evidence are retained. See
[verification](verification.md) for measured results and limitations.

## Current evidence and remaining uncertainty

The earlier experiments establish useful reductions and specific accuracy
improvements, but no universal fastest exact formulation. Fewer variables or
Hessian entries alone do not establish a faster solve; normalized residuals do
not establish physical accuracy. Full IVR remains the physical reference, and
all alternative coordinates remain experimental choices supported by explicit
contracts and tests.

A best-evidence recommendation must name its measured domain. The current
portfolio uses selected feeder inputs and synthetic cases with an explicit
feasibility objective. It cannot by itself establish the fastest formulation
for general dispatch, different optimizers, nonlinear-load mixtures, untested
transformers or repeated-update workloads. Broader mixed-port certificates and
factorization-aware selection remain separate priorities.
