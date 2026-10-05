# Best-evidence exact-IVR profiles

All transformation and reformulation options remain available. A configuration
that is slower on one panel is still useful for future numerical evidence.
Recommendations here are additive; package defaults and the individual options
are unchanged. “Fastest” always refers to a declared workload, accepted physical
solutions, a candidate set, solver settings and a measured environment.

## Best measured common profile — 5 October 2026

For the five-case **feasibility** panel below, the current common recommendation
is the following explicit configuration:

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
It is a recommendation for this measured workload, not a new package default.

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

For one fresh model, compare construction plus solve/extraction time. For an
already constructed, unsolved model, compare solve/extraction time separately.
The latter is **not** a benchmark of repeated parameter updates or warm-started
solves; those require their own experiment. Compilation and warm-up costs also
matter for short-lived processes, although the studies here exclude warm-ups.

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
enter the ranking. The report gives both `fastest_total` and `fastest_solve`,
with exact options and provenance. A fast failed or incomplete profile cannot
win. The runner does not mutate a production default or silently replace the
user's chosen representation.

Profile selection itself costs time: reference construction, warm-ups, audits,
all competing runs and evidence output are excluded from each candidate's
build-and-solve score. The report separately records `total_study_s`. Tune an
intended repeated workload and reuse its explicit configuration; running the
entire portfolio before every single solve is not a speed optimization.

```julia
name = report["ranking"]["fastest_total"]
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
