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

## Best-evidence starting configuration: regional IVR with AMD

The current measured starting configuration adds **MUMPS AMD ordering** to
regional conductor coordinates, passive elimination and finite-ground scaling:

```julia
formulation = IVRNLP(objective=:feasibility,
    specialization=:conductor_regions, linear_elimination=:passive,
    series_selection=:all, ground_scaling=:voltage)
solver_options = merge(IVRProfileStudy.STRICT,
    (linear_solver="mumps", mumps_pivot_order=0))
```

Here `IVRProfileStudy` comes from `examples/benchmark_ivr_profiles.jl` and its
strict settings define the measured experiment, not a new package default.
Use the required objective for the intended workload; the feasibility evidence
does not replace an economic objective. All transformations and ordering
alternatives remain available. This recommendation concerns solver wall time;
construction cost does not enter it.

For the longer manufactured dispatch sequences and the two external-feeder
demand sequences studied below, explicitly carrying the previous primal point
improves the median sequence time. Keep
fixed starts and full IVR with AMD as comparators: the small single-phase case
regresses, and delta formulation differences can be small. See
[model reuse and initialization](@ref Model-reuse-and-previous-primal-initialization)
for the separate factors and measured domain.

The subsequent [reconstructed-dual study](@ref Explicit-reconstructed-dual-initialization)
refines initialization choices without changing that metric or removing options:

| Measured repeated workload | Current starting shortlist |
|:--|:--|
| Earlier repeat-containing single-phase cost dispatch | Regional/passive + AMD + explicit reconstructed duals |
| Earlier repeat-containing delta cost dispatch | Full or regional/passive + AMD + explicit reconstructed duals; medians within 1% |
| Distinct single-phase P/Q histories, 100 segments | Regional/passive + AMD; reconstructed duals give 1–6% median gains over previous primals, with mixed paired outcomes |
| Distinct delta P/Q histories, 100 segments | Full or regional/passive + AMD; reconstructed duals give 3–8% median gains, with near-tied formulation medians |
| ENWL 435 demand feasibility | Regional/passive + AMD + previous primals; reconstructed duals regress and zero duals fail strict acceptance |
| DSuite 1,220 demand feasibility | Full + AMD + previous primals from the earlier study; reconstructed duals not yet tested |

These are workload-specific experimental choices. New histories, changing
reactive limits and other feeders still need matched measurements. The dual
helper's validation overhead is excluded from the Ipopt score and can be large.

### Selection and transfer evidence

A prospective screen crosses three formulations (full, scaled regional passive,
and bound-support selected regional passive) with five order requests. Four
exploratory sweeps on DSuite 2,854 and ENWL 538 give **120/120 admitted solves**
and 30 admitted excluded warm-ups. Regional/passive with AMD is fastest on both
inputs. Its sum of per-input Ipopt medians is 0.324344 s, versus 0.521555 s for
the same formulation with automatic ordering and 1.159862 s for full/automatic.
These are selection-set observations, not independent performance estimates.

Freeze that choice before testing two other feeders and two delta dispatch
price regimes. Compare full/automatic, the previous regional/automatic profile,
selected-regional/automatic and the frozen winner. Eight balanced sweeps per
case give **128/128 admitted solves** and 16 admitted excluded warm-ups.

| Validation case | Full / automatic (ms) | Regional / automatic (ms) | Regional / AMD (ms) | AMD / regional automatic |
|:--|--:|--:|--:|--:|
| DSuite 1,220 | 88.986 | 80.935 | 61.416 | 0.759 |
| ENWL 435 | 200.969 | 163.216 | 131.608 | 0.806 |
| Delta, cheap DER | 14.868 | 5.522 | 5.858 | 1.061 |
| Delta, expensive DER | 6.197 | 9.841 | 5.327 | 0.541 |

The last column is a ratio of medians. The new profile wins the two feeder
cases and the expensive-DER case among these four candidates. Selected regional
with automatic ordering remains fastest for cheap DER (5.227 ms). In the
expensive-DER case, regional iterations fall from 17 to 10 when requesting AMD;
the earlier regression against full/automatic reverses. Its individual paired
ratios against full/automatic range from 0.807 to 3.692, including a timing
outlier, so the lower median is not a claim that every run is faster.

Ordering can change the nonlinear trajectory as well as factorization cost.
All objective comparisons and independent physical/model checks pass. These
are fresh solves, not parameter-update or warm-start results. Validation inputs
were excluded from this ordering screen but had appeared in earlier project
experiments; this is transfer evidence, not blind population sampling.

### Isolate reduction after fixing the ordering

Full IVR also benefits substantially from AMD. A separate comparison, declared
after the screen and before examining validation results, therefore fixes AMD
on **both** full and regional/passive models. Six new balanced pairs per case
give **48/48 admitted solves** and eight admitted excluded warm-ups.

| Matched-AMD case | Full median (ms) | Regional median (ms) | Regional/full | Individual paired ratio range |
|:--|--:|--:|--:|:--|
| DSuite 1,220 | 64.297 | 66.383 | 1.032 | 1.013–1.213 |
| ENWL 435 | 169.372 | 142.035 | 0.839 | 0.822–0.860 |
| Delta, cheap DER | 5.430 | 6.122 | 1.127 | 1.058–1.201 |
| Delta, expensive DER | 5.908 | 5.831 | 0.987 | 0.892–1.047 |

These are a separate batch; do not mix its absolute timings with the previous
table to form unmatched ratios. With ordering controlled, reduction is useful
on ENWL 435, slower on DSuite 1,220 and cheap-DER delta, and near tied on
expensive-DER delta. The common regional/AMD profile is a measured starting
point, not a universal winner over well-configured full IVR. **Full IVR + AMD
is a strong explicit alternative**. Construction remains excluded throughout.

The bound-support policy also interacts with ordering: on screening ENWL 538,
selected-regional/AMD takes 17 iterations and 0.335763 s median, versus eight
iterations and 0.181045 s for unconditional regional/AMD. All pass physical
checks. A conservative expression-support rule is not a runtime guarantee.

### What the detailed solver logs establish

Thirty separate verbose solves and 30 excluded warm-ups pass. On these inputs,
automatic request 7 always reports actual order 2 (AMF); explicit requests
0/2/5/6 report those same requested orders. Thus the measured METIS requests
were not silently falling back in this installed build. The logs use Ipopt
3.14.19 with MUMPS 5.9.0; different builds may choose differently.

| Diagnostic case / profile | Native algorithm wall (s) | Symbolic wall (s) | Maximum reported factor doubles | Maximum reported factor integers |
|:--|--:|--:|--:|--:|
| DSuite 2,854 full / automatic | 0.484 | 0.359 | 2,845,020 | 553,724 |
| DSuite 2,854 full / AMD | 0.161 | 0.037 | 2,769,162 | 525,598 |
| DSuite 2,854 regional / automatic | 0.311 | 0.198 | 2,707,370 | 492,598 |
| DSuite 2,854 regional / AMD | 0.143 | 0.033 | 2,685,997 | 475,792 |
| ENWL 538 full / automatic | 0.761 | 0.019 | 1,785,190 | 234,368 |
| ENWL 538 full / AMD | 0.209 | 0.017 | 1,422,083 | 198,766 |
| ENWL 538 regional / automatic | 0.237 | 0.016 | 1,126,838 | 190,126 |
| ENWL 538 regional / AMD | 0.196 | 0.014 | 1,132,999 | 171,982 |

These instrumented observations are excluded from rankings. Counts are maxima
over reported factorization calls in each diagnostic, not process peak memory
or a factor-fill ratio. DSuite's symbolic-time reduction is much larger than
its reduction in factor storage; ENWL's full-model iteration count also changes
from 14 to 8. Fewer stored entries alone cannot explain the timing effects.
The earlier zero numerical-factorization timing field remains an attribution
limitation, not evidence that numerical factorization costs nothing.

### Reproduce the ordering comparison

A representation and its linear-solver ordering form a joint numerical choice.
The new `IVRProfileStudy.ordering_profiles` helper crosses explicit formulations
with ordering requests while retaining every original formulation option:

```julia
include("examples/benchmark_ivr_profiles.jl")
candidates = IVRProfileStudy.ordering_profiles(
    candidates=IVRProfileStudy.profiles()[[1,10,12]],
    orders=(7,0,2,5,6))
report = IVRProfileStudy.benchmark(network, "/tmp/ivr-ordering.json";
    candidates, repetitions=4)
name = report["ranking"]["fastest_ipopt"]
name === nothing && error("No comparable admitted ordering winner")
chosen = only(filter(p -> p.name == name, candidates))
formulation = IVRNLP(chosen.options)
settings = IVRProfileStudy.profile_solver_options(chosen, IVRProfileStudy.STRICT)
```

Apply `settings` as `solver_options` when solving this explicit formulation.
The report saves the shared settings and each candidate's **effective** settings.
Per-candidate overrides are copied and merged into the shared settings without
mutating them. For an ordering-only experiment, vary only `mumps_pivot_order`
and explicitly use `linear_solver="mumps"`; keep convergence, scaling, pivot
thresholds, starts and physical acceptance fixed.

[Ipopt documents](https://coin-or.github.io/Ipopt/OPTIONS.html#OPT_mumps_pivot_order)
this option as MUMPS `ICNTL(7)`. The
[MUMPS guide](https://mumps-solver.org/doc/userguide_5.8.2.pdf) identifies requests
7/0/2/5/6 as automatic/AMD/AMF/METIS/QAMD. Optional ordering packages can fall
back, so a requested policy is not proof of the actual ordering. The helper
also accepts requests 3 and 4; request 1 requires a supplied permutation that
this helper does not provide. Custom solver settings remain available.

Use a **separate**, verbose diagnostic solve to inspect actual choices and
storage. `mumps_diagnostics(log)` reads the ordering reported by Ipopt, raw
signed `INFO(9)` and `INFO(10)` storage counts, and selected native wall timers.
The [Ipopt MUMPS interface](https://github.com/coin-or/Ipopt/blob/stable/3.14/src/Algorithm/LinearSolvers/IpMumpsSolverInterface.cpp)
emits these fields. Missing fields remain missing, signed counts are preserved,
and nested timers are not added together. These are solver-reported factor
storage counts, not process peak memory or a measured fill ratio. Verbose
instrumented runs do not enter the timing ranking.

## Earlier Ipopt evidence with automatic ordering

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

## Model reuse and previous-primal initialization

Model reuse and initialization are separate experimental factors. The runner
`examples/benchmark_ivr_reuse.jl` crosses fresh/reused models with fixed starts
and explicit previous-primal starts, for full and regional/passive IVR. Every
sequence begins from the formulation's unloaded start. Later solves either
reset that same start or receive all primal variable values from the preceding
accepted solve in that sequence. Starts never cross repetitions.

This is **primal-only initialization**: `warm_start_init_point="no"` and no dual
starts are supplied. The installed Ipopt.jl wrapper reads variable start
attributes on every solve; retaining a JuMP model alone does not request the
previous solution as its next initial point. Ipopt's
[primal-dual warm-start option](https://coin-or.github.io/Ipopt/OPTIONS.html#OPT_warm_start_init_point)
is a different treatment, left for a separate experiment. Nor does JuMP model
reuse establish reuse of the native solver's factorization.

For workflow ``w``, repetition ``r`` and ordered scenario ``k``, the score is

```math
T_w = \operatorname{median}_r \left(\sum_{k=1}^{K}
 t^{\mathrm{Ipopt}}_{w,r,k}\right).
```

It is the median **complete-sequence sum**, not a sum of scenario medians.
Construction, updates, start assignment, extraction and audits are excluded.
Rank only workflows with an admitted warm-up and every complete requested
repetition. Objectives must agree across workflows **within each scenario**;
price or demand changes can legitimately change the objective between scenarios.

Each reused solve is checked against independently edited input dictionaries,
a fresh full model and a fresh model of the same formulation, in addition to
physical and own-model checks. Reverse mapping uses a separate full-feasible
anchor for each scenario. The report preserves variable identity checks,
start/solution digests, effective solver settings, update counts, failures and
partial sequences. A failed sequence is ineligible and is not repaired.

A reproducible invocation uses absolute updates with cumulative semantics:

```julia
include("examples/benchmark_ivr_reuse.jl")
schedule = [
    (label="base", loads=Dict{String,Any}(), generators=Dict{String,Any}()),
    (label="lower demand",
     loads=Dict(id => (p=0.8d["p_nom"], q=0.8d["q_nom"])
                for (id,d) in net["load"]), generators=Dict{String,Any}()),
]
report = IVRReuseStudy.benchmark(net, schedule, "reuse.json";
    repetitions=4, solver_options=IVRReuseStudy.SETTINGS)
report["ranking"]["fastest_ipopt"]
```

Here `net` must satisfy the supported constant-power update contract. Configure
the intended objective and any objective scaling identically for all candidates.
Four reversed/rotated sweeps over eight workflows are exploratory, not fully
position-balanced; independently confirm a promising choice. With this runner's
rotation rule, **16 sweeps** place every one of eight workflows in each position
twice; eight sweeps do not. Audit the actual order table rather than inferring
balance from the number of repetitions. Numerical
objective agreement is not a certificate of global optimality.

### Measured sequence evidence — 5 October 2026

The prospective screen uses manufactured two-wire single-phase and three-wire
delta chains, each with 20 and 100 segments. Removing odd-position loads leaves
passive intermediate buses while retaining every operating bound. The base
active demand is 1,000 W (single-phase) or 1,500 W (delta). A terminal DER has
active capacity 600 W or [500, 150, 50] W respectively, with reactive power fixed
to zero. The six scenarios are: cheap DER, identical repeat, expensive DER,
expensive DER at 80% demand, cheap DER with zero availability at original demand,
and restored cheap availability. DER prices are 0.2 or 2 against grid price 1.

All candidates use strict controls, AMD, `obj_scaling_factor=1000` and normal
dual initialization. Julia 1.12.6, JuMP 1.31.2 and Ipopt.jl 1.16.0 run on an
Apple M4 with one Julia and BLAS thread. The frozen source, scenario digests,
settings and individual measurements accompany the raw evidence.

The four-case screen admits **768/768 measured solves** and **192/192 excluded
warm-ups**. A fresh eight-sweep replication on the two longer cases admits
another **768/768** and 96 warm-ups. Its order audit identifies that the intended
position balance was not achieved; those data remain a separate preliminary
replication. A new, prospectively corrected **16-sweep confirmation** admits
**1,536/1,536 measured solves** and 96 warm-ups, with each workflow in each
position exactly twice. The following table uses only that final batch.

| 100-segment case / formulation | Fresh, fixed (ms) | Reused, fixed (ms) | Fresh, previous primal (ms) | Reused, previous primal (ms) | Previous/fixed, reused |
|:--|--:|--:|--:|--:|--:|
| Single-phase / full | 100.077 | 99.455 | 70.840 | 70.663 | 0.711 |
| Single-phase / regional passive | 60.995 | 60.882 | 50.130 | 49.994 | 0.821 |
| Delta / full | 127.908 | 127.109 | 118.243 | 117.787 | 0.927 |
| Delta / regional passive | 136.881 | 137.236 | 115.643 | 115.417 | 0.841 |

Times are median complete-sequence sums; ratios are ratios of those medians.
All measured scenarios pass objective agreement, independent physics, fresh-model and
reverse-anchor checks. Start digests and per-scenario iteration counts agree
between fresh and reused treatments with the same representation/start policy.
Within each such matched comparison, reuse/fresh median ratios range from
0.994 to 1.003. This establishes no material median Ipopt benefit from model
reuse alone on this panel; construction savings are deliberately excluded.
Individual paired ratios span 0.285–1.143 because timing outliers are retained.
No statistical-significance or every-run speedup claim is made.

Previous-primal initialization has the larger effect on the longer feeders.
Regional/passive sequence time falls about 18% (single-phase) and 16% (delta);
its reused paired previous/fixed ratios range 0.798–0.846 and 0.838–0.870.
However, the small single-phase screen regresses by about 4% in regional/reused
mode. Price reversal and restored availability require ten iterations from the
previous primal versus eight from the unloaded start. The longer single-phase
case also has a regression within its sequence: lower demand takes 17 rather
than 14 regional iterations, despite a lower total sequence time.

Within this primal-only comparison on longer dispatch sequences, regional/passive
IVR with AMD and explicit previous-primal initialization is the fastest measured choice. Full IVR
with AMD remains a strong comparator, especially for delta: its previous-primal
median is only about 2% higher. Do not automatically carry primal values for
all workloads, infer benefits from compilation savings, or remove fixed starts
and alternative formulations. These are new timing measurements on selected
existing manufactured inputs, not transfer evidence on unseen feeders or a
primal-dual warm-start result. That manufactured panel does not assess real feeder update sequences or
explicit dual initialization; the next section addresses feeder transfer.

The untracked evidence bundle retains `REUSE_PROTOCOL.md`, all three batches,
`REUSE_SOURCE`, `REUSE_HASHES.txt`, `REUSE_ANALYZE.py` and `REUSE_SUMMARY.json`.
The independent audit checks actual order counts, frozen-source/input hashes,
start digests, model identity, iteration agreement, completeness and timing
aggregation. The preliminary design mistake and all timing outliers are retained.

## Transfer to external feeder demand sequences

`examples/benchmark_ivr_feeder_reuse.jl` applies the same admission and Ipopt
wall-time metric to external feeder JSON files:

```sh
julia --project=test examples/benchmark_ivr_feeder_reuse.jl input.json output.json
```

The default experiment holds a **feasibility objective**, source phasors,
equipment, generator/source accounting and every operating bound fixed. It
sets constant-power P and Q to absolute factors `(1, 1, 0.9, 1)` of the original
data: base, identical repeat, lower demand and restoration. This is an explicit
demand-change experiment, not an equivalence-preserving input transformation.
Other load laws remain unchanged; the manifest lists both updated and unchanged
load IDs. Known legacy provenance is relocated on an owned copy. The input file
is unchanged and its digest is recorded before measurement.

The default four workflows cross full/regional-passive reused models with
fixed/previous-primal starts. Eight reversed/rotated sweeps give two observations
in each workflow position; use the actual order table to verify any custom
candidate list. The companion `output.json.input.json` is written before solves
so interrupted experiments retain source and scenario provenance. Completed
reports also embed this manifest. Physical and fresh-model checks apply to each
independently edited scenario, with incomplete sequences retained and excluded
from the ranking. No economic-dispatch inference follows from this feasibility
experiment, especially where generators and ideal sources share a bus.

A separate matched lifecycle contrast can use all four fixed-start workflows:

```julia
include("examples/benchmark_ivr_feeder_reuse.jl")
F = IVRFeederReuseStudy
workflows = F.R.workflows(profiles=F.R.P.profiles(objective=:feasibility)[[1,10]])
report = F.benchmark("input.json", "lifecycle.json";
    candidates=filter(w -> w.start == :fixed, workflows), repetitions=8)
```

Do not combine timing ratios from separate batches: compare reused/fresh within
the lifecycle batch, and previous/fixed within the initialization batch.

### External-feeder initialization evidence — 5 October 2026

The first declared contrast uses DSuite SPD Urban (1,220 buses, 325 CP loads)
and the already-reduced ENWL network 17 feeder 6 (435 buses, 223 CP loads).
Their stored topology is inherited. All 256 measured solves and 32 excluded
warm-ups pass the independent physical/model checks. The eight sweeps balance
all four workflow positions. The four-step demand sequence and candidate choices
were declared before measurement. These are new sequence measurements on
previously studied files, not blind held-out network samples.

| Reused model / feeder | Fixed-start sequence (ms) | Previous-primal sequence (ms) | Previous/fixed median ratio | Paired ratio range |
|:--|--:|--:|--:|:--|
| Full / DSuite 1,220 | 256.244 | 209.818 | 0.819 | 0.772–0.832 |
| Regional passive / DSuite 1,220 | 257.925 | 214.211 | 0.831 | 0.812–0.913 |
| Full / ENWL 435 | 678.012 | 573.501 | 0.846 | 0.838–0.859 |
| Regional passive / ENWL 435 | 563.220 | 472.929 | 0.840 | 0.834–0.844 |

Each time is the median sum of Ipopt wall seconds over all four scenarios,
converted to milliseconds. Construction and updates do not enter the score.
DSuite iterations change from `[3,3,3,3]` with fixed starts to `[3,1,2,2]` with
previous primals; ENWL changes from `[8,8,8,8]` to `[8,6,6,6]`. Both formulations
have these iteration patterns. The previous-primal treatment improves the
complete sequence in every paired repetition on these two feeders, but this
is not evidence that every scenario or arbitrary demand sequence will improve.

Full IVR with AMD is slightly faster on DSuite; regional/passive with AMD is
faster on ENWL. The result supports previous-primal initialization for these
specific demand sequences and reinforces the need to keep both formulations.
All objective values are zero by design, so physical and cross-model admission,
rather than objective equality alone, establishes meaningful feasibility checks.
The separate lifecycle batch below isolates reuse without changing starts.

### Matched fresh/reused feeder evidence

The separately declared fixed-start lifecycle batch admits another **256/256
measured solves** and 32 excluded warm-ups. It uses the same source/scenario
hashes and strict settings as the initialization batch. Every workflow again
occupies every position twice. The following estimates use only lifecycle runs.

| Feeder / formulation | Fresh sequence (ms) | Reused sequence (ms) | Reused/fresh median ratio | Paired ratio range |
|:--|--:|--:|--:|:--|
| DSuite 1,220 / full | 254.082 | 254.677 | 1.002 | 0.989–1.219 |
| DSuite 1,220 / regional passive | 258.823 | 258.355 | 0.998 | 0.929–1.012 |
| ENWL 435 / full | 658.711 | 642.620 | 0.976 | 0.771–1.007 |
| ENWL 435 / regional passive | 527.261 | 529.583 | 1.004 | 0.963–1.083 |

Start digests and per-scenario iteration counts agree across each fresh/reused
pair. Reuse alone has a small and inconsistent median effect: full ENWL improves
about 2.4%, while two comparisons regress slightly. Timing outliers remain in
the samples, and some paired ratios cross one. No statistical-significance or
every-run benefit claim is made. These effects are smaller than those of
initialization in its own matched batch; do not compute a cross-batch speed ratio.

All **512 measured solves and 64 excluded warm-ups** pass. The independent audit
checks source-file digests, scenario correspondence, admission, objective values,
start policies, timing sums and actual order balance. `FEEDER_REUSE_PROTOCOL.md`,
`FEEDER_REUSE_SOURCE`, all raw reports and input manifests, the analysis script
and summary remain outside Git. The raw manifests retain an inherited nested
accounting note referring to cost; the recorded objective is feasibility
throughout, and the final runner corrects that prose. Timed sources and the
metadata-only correction are both preserved. The existing transformation and
initialization choices are all retained.

### What is reused inside the installed solver wrapper?

A separate 14-solve diagnostic uses two-wire and delta fixtures with demand,
price, fixed-zero availability, release, bound removal and bound restoration.
All solves pass physical and fresh-full checks. All observed constraint types
support dual-start attributes and all returned duals are finite. Non-variable-
bound constraint references remain unchanged; removing/restoring active lower
bounds removes/adds one row for single-phase and three for delta. Changing a
box to fixed zero and releasing it retains its lower/upper references, so
reference identity alone cannot detect the changed bound geometry.

For all 12 transitions after the initial solves, the installed Ipopt.jl wrapper
marks `needs_new_inner` after the update and creates a different `inner` problem
object on the next solve. Source inspection confirms that JuMP's constant-power
RHS update reaches the wrapper's affine/quadratic `ConstraintSet` path, which
requests this reconstruction. This is version-specific diagnostic evidence,
not a public API contract or an attribution of how much wall time reconstruction
costs. Its setup work lies inside the chosen MOI Ipopt timer; FormulationLab
construction remains excluded. It explains why JuMP model retention must not
be described as retaining the native solver problem or its factorization.

The diagnostic uses normal dual initialization and explicitly records
`fixed_variable_treatment="make_parameter"`. It transfers no dual starts and
makes no performance claim. The inspected wrapper, script and results are
retained in `FEEDER_REUSE_SOURCE` and `DUAL_START_LAYOUT_AUDIT.*`. The JSON field
`kept_equations` checks all non-variable-bound constraints, including inequalities.

### Design requirements for reconstructed-dual starts

Carrying duals requires an explicit correspondence and reset policy. Cache all
solution values before any model update; JuMP documents this ordering in its
[primal/dual start example](https://jump.dev/JuMP.jl/stable/tutorials/conic/start_values/).
Load updates retain their constraint references and change right-hand sides.
Generator boxes can change value, become coincident, lose a side or regain one.
Treat both sides of a changed box together, rather than assuming an unchanged
lower-bound reference makes its old multiplier suitable after an upper-bound
change. Newly introduced sides need a declared initialization policy.

The installed Ipopt.jl 1.16.0 wrapper reports lower/upper variable-bound duals
from the signed reduced cost ``r=z_L-z_U`` as ``\max(r,0)`` and ``\min(r,0)``.
Thus reading those two JuMP duals does not in general recover both native
multipliers, particularly when bounds coincide. A future public-API experiment
must describe these as **reconstructed dual starts**, or separately validate
access to native multipliers. It must also record Ipopt's
[fixed-variable treatment](https://coin-or.github.io/Ipopt/OPTIONS.html#OPT_fixed_variable_treatment)
and hold that policy constant across the compared starts. Changing fixed-variable
handling or warm-start push/barrier options at the same time would confound the
comparison.

Begin within one reused model: most equation constraints are anonymous, so
fresh-model dual correspondence needs more than matching variable names or
constraint positions. Preserve every existing fixed and primal-only treatment.
Check supplied starts, failures, objective comparability and independent physical
admission before any timing claim. Enabling `warm_start_init_point="yes"` alone is not evidence that the preceding
complete native iterate has been transferred. The following experiment implements
a restricted reconstructed-dual policy and retains these limitations.

## Explicit reconstructed-dual initialization

The experimental `IVRReuseStudy.dual_workflows()` shortlist adds two policies
to the existing previous-primal treatment, for the same reused models:

| Policy | Subsequent primal start | Subsequent dual start | Ipopt initializer |
|:--|:--|:--|:--|
| `previous_primal` | Previous accepted primal | None supplied | Normal |
| `zero_dual` | Previous accepted primal | Zero for every current constraint | Warm |
| `reconstructed_dual` | Previous accepted primal | Cached JuMP duals, with changed-box resets | Warm |

The **zero-dual control** distinguishes the warm initializer's effect from the
information in carried multipliers. All three start the first scenario normally,
from the same unloaded start. Caches never cross models, workflows or repetitions.
Fixed starts, fresh models and all previous formulations remain available through
the original `workflows()` shortlist. No production behavior changes.

`examples/ivr_dual_starts.jl` captures all dual values before updates and retains
variable references while copying affine, quadratic and nonlinear expression
containers. Before assigning any dual starts, it checks model identity, variable
layout, non-variable-bound constraint identities, canonical functions, set types,
all non-CP constraint sets, non-generator boxes and the objective after removing
permitted generator-price coefficients. The cache is refused if those invariants
change. Supported CP right-hand sides and generator prices/boxes may vary.
The caller must admit the preceding solution before capture: the helper checks
dual availability and finiteness, while the benchmark additionally requires the
physical, own-model, independent fresh-model, reverse-anchor and objective checks.

For a current bound on variable ``x_j``, use the cached JuMP dual only if its
entire box is unchanged and the bound existed in the snapshot. If either endpoint
changes, reset **both current bound sides** to zero, including an unchanged side.
New sides start at zero and removed sides are discarded. This covers fixed-zero
availability, release and removed/restored bounds. Every current dual-start
attribute is read back and checked against its declared assignment. The report
records changed boxes, carried/reset/zeroed counts, added/removed rows and
source/start/solution digests. Backend errors during assignment do not have a
rollback guarantee; the benchmark retains the failed sequence.

The shared `DUAL_CONTROLS` fix AMD's surrounding initialization policy:
`fixed_variable_treatment="make_parameter"`, `warm_start_same_structure="no"`,
`mu_strategy="monotone"`, `mu_init=0.1`, and warm-start bound/slack pushes,
fractions and multiplier push at `0.001`. The initial solve uses
`warm_start_init_point="no"` in every arm. Subsequent zero/reconstructed-dual
solves use `"yes"`, while the previous-primal control stays at `"no"`.
Per-scenario effective settings are saved; all other controls are shared.
The [Ipopt option reference](https://coin-or.github.io/Ipopt/OPTIONS.html#OPT_warm_start_init_point)
defines the two initializers. This experiment does not tune the push/barrier
parameters or claim to copy both native bound multipliers.

```julia
include("examples/benchmark_ivr_reuse.jl")
R = IVRReuseStudy
report = R.benchmark(net, schedule, "dual-study.json";
    candidates=R.dual_workflows(), repetitions=12,
    solver_options=merge(R.SETTINGS, (obj_scaling_factor=1000.,)))
```

Here `net` and `schedule` describe the intended cost-dispatch sequence. For a
feasibility study, pass profiles with `objective=:feasibility` and omit the cost
scaling. Twelve sweeps balance six workflows with two observations per position;
three workflows need six sweeps for the same balance. Check the saved order table.
Use complete admitted sequences and per-scenario objective agreement, as before.
The Ipopt wall score excludes dual capture, correspondence checks and assignment,
as well as construction, updates and extraction.

### Declared screen and confirmation design

A prospective screen uses the same manufactured single-phase two-wire and
three-wire delta cost-dispatch fixtures as the preceding reuse experiment,
with 20 and 100 line segments. The six steps are cheap generation, an identical
repeat, expensive generation, lower demand, zero generator availability at the
original demand, and restored availability. Six workflows cross full/regional
formulations with the three initialization policies. Four exploratory sweeps
are reversed/rotated but not fully position-balanced. All **576/576 measured
solves** and **144/144 excluded warm-ups** pass the admission checks, and all
six workflows have comparable objectives in every scenario. Reconstructed-dual
initialization has the lowest median in each case; regional leads on the two
single-phase inputs and full leads on the two delta inputs. These observations
are a screen, not a population-level performance estimate.

The protocol separately declares twelve new sweeps on each 100-segment case,
placing every workflow in every position twice. This repeats known inputs; it
is not unseen-network validation. A third, separate transfer study uses the
ENWL 435 feeder, regional/passive formulation, all three start treatments and
six balanced sweeps. All 223 CP loads follow factors `(1,1,0.9,1)`, preserving
source/generator accounting and equipment. Its feasibility objective does not
establish economic-dispatch performance. Batches are not pooled. The protocol,
raw samples, driver, frozen sources and source/input hashes remain outside Git.

### Balanced synthetic confirmation

The separately declared confirmation admits **864/864 measured solves** and
**72/72 excluded warm-ups**. Every workflow occupies every order position twice;
objectives agree across eligible workflows within every scenario. The entries
below are medians of complete six-scenario sums, in milliseconds of Ipopt wall
time. They are not sums of scenario medians.

| 100-segment case / formulation | Previous primal (ms) | Zero dual (ms) | Reconstructed dual (ms) | Reconstructed/previous | Paired ratio range |
|:--|--:|--:|--:|--:|:--|
| Single-phase / full | 73.893 | 77.153 | 62.902 | 0.851 | 0.841–0.864 |
| Single-phase / regional passive | 52.556 | 56.326 | 47.202 | 0.898 | 0.889–0.915 |
| Delta / full | 121.485 | 119.576 | 90.244 | 0.743 | 0.681–0.774 |
| Delta / regional passive | 119.896 | 118.594 | 90.990 | 0.759 | 0.341–0.871 |

Ratios use matched workflows in the same batch; the final column retains all
twelve repetition-paired ratios, including timing outliers. Reconstructed duals
reduce median sequence time by 10–26% against previous primals alone on these
cases. The zero-dual initializer control regresses on single-phase and gives
only small improvements on delta, supporting a contribution from the carried
multiplier information. Regional/passive is fastest on single-phase; full and
regional with reconstructed duals differ by less than 1% on delta. This is not
a statistical-significance claim or evidence for a universally fastest formulation.

Gains are transition-dependent. In the regional single-phase sequence, the
identical repeat falls from 8 to 3 iterations and the lower-demand step from
17 to 7, but restoring availability rises from 11 to 14. Regional delta repeat
and lower-demand iterations fall from 14 to 3 and 9 to 4; restoration rises
from 12 to 13. All constraints and physical checks are retained in these solves.

A **post-hoc timing sensitivity**, subtracting only the identical-repeat step
from each complete accepted sequence, gives reconstructed/previous median ratios
of 0.906/0.965 for single-phase full/regional and 0.862/0.875 for delta
full/regional. These smaller benefits show that the repeat contributes materially
to the primary result. This subtraction does not simulate a sequence without
the repeat: the original trajectory and subsequent initial points remain intact.
It does not alter primary rankings. New histories without repeated scenarios
are needed before extrapolating to that workload.

### Feeder transfer and strict rejection

The ENWL 435 transfer study retains a feasibility objective and compares only
regional/passive formulations. Previous-primal and reconstructed-dual policies
each complete all six measured sequences and their excluded warm-up. The
zero-dual control returns `ALMOST_LOCALLY_SOLVED` at the identical repeat in
all six measured sequences and its warm-up, after 40 iterations. This fails
the declared strict solver-status gate; its physical/model point audits are
not evaluated. It is not evidence of an independently demonstrated physical
violation. The sequence stops there, without repaired retries or relaxed settings.

Thus **54/60 attempted measured solves** and **9/10 attempted warm-up solves**
are admitted. Twelve later measured scenarios and two later warm-up scenarios
are unattempted after rejection. Zero-dual initialization is ineligible for
ranking; its accepted initial steps cannot be compared as complete sequences.
The two eligible policies have comparable objectives and pass all physical,
own/fresh-model and reverse-anchor checks. Every workflow occupies every
position twice, including the failed control.

| Regional/passive policy | Median four-scenario Ipopt sum (ms) | Reconstructed/previous | Paired ratio range |
|:--|--:|--:|:--|
| Previous primal | 448.236 | — | — |
| Reconstructed dual | 470.487 | 1.050 | 1.002–1.068 |
| Zero dual | Ineligible: strict status rejection | — | — |

Reconstructed duals **regress by about 5%** on this feeder despite reducing the
repeat and lower-demand iteration counts from 6 to 5. The full iteration vectors
are `(8,6,6,6)` for previous primal and `(8,5,5,6)` for reconstructed duals.
Iteration count alone therefore does not rank Ipopt wall time. Subtracting the
repeat's time in the same post-hoc sensitivity gives a ratio of 1.054, still a
regression. There is no admitted feeder contrast against the zero-dual control.

The experimental helper also has substantial overhead outside the primary score:
median validation/assignment times across measured transferred starts are about
10.16 s for zero duals and 11.83 s for reconstructed duals on this feeder. These
include correspondence checks, assignment, read-back and start hashing, but not
cache capture. They do not enter the requested Ipopt ranking. The helper remains
a research implementation, and this experiment does not claim an end-to-end
speed benefit or a production warm-start API.

Across the screen, confirmation and transfer studies, **1,494/1,500 attempted
measured solves** and **225/226 attempted excluded warm-ups** are admitted.
There are six measured and one warm-up strict-status rejections, all retained.
The original plan had 1,512 measured scenarios and 228 warm-up scenarios; early
stopping accounts for the unattempted remainder. The independent audit checks
source/input hashes, effective settings, correspondence and reset digests,
complete-sequence sums, eligibility, objective agreement and actual position
balance. Failed feeder attempts still undergo start/settings correspondence
checks, without being relabelled as accepted physical points. Raw reports,
`DUAL_PROTOCOL.md`, `DUAL_RUN.jl`, `DUAL_SOURCE`, `DUAL_HASHES.txt`,
`DUAL_ANALYZE.py` and `DUAL_SUMMARY.json` remain outside Git.

### Interpretation of the transferred multipliers

No feasibility or optimality certificate is transferred. After a demand or price
update, the previous multipliers need not satisfy the new KKT equations. They
are initial guesses in identical equation and variable coordinates. All electrical
and operating constraints remain in the new solve and every returned point must
pass the independent audits. Resetting both sides of a changed box avoids
pretending that a reconstructed signed reduced cost identifies its two native
bound multipliers, particularly as a generator becomes fixed or is released.
The zero-dual arm holds the warm initializer constant while removing carried
multiplier information; its contrast with reconstructed duals is therefore more
informative than a normal-versus-warm comparison alone.

## Distinct operating histories and changing reactive limits

`examples/benchmark_ivr_histories.jl` provides reproducible manufactured inputs
without relying on a local historical driver. Both single-phase two-wire and
three-wire delta cases use 100 chain segments, loads on even-position buses and
one terminal generator. Source accounting, equipment, voltage/current/apparent-
power limits and objective definition remain fixed. Two histories share the
following absolute demand and generator-price path:

| Step | P-demand factor | Q-demand factor | Generator price | P-cap fraction in changing boxes | Q lower fraction | Q upper fraction |
|--:|--:|--:|--:|--:|:--|--:|
| 1 | 1.00 | 1.00 | 0.20 | 1.00 | −1.00 | 1.00 |
| 2 | 0.92 | 1.10 | 0.35 | 0.75 | −1.00 | 0.40 |
| 3 | 1.06 | 0.85 | 1.60 | 0.50 | 0.00 | 0.00 |
| 4 | 0.88 | 0.70 | 1.80 | 0.00 | −1.00 | 0.80 |
| 5 | 1.12 | 1.25 | 0.25 | 0.90 | absent | 1.00 |
| 6 | 1.02 | 0.95 | 1.20 | 1.00 | −1.00 | 1.00 |

Prices use the input schema's cost units. P caps are `[600]` W for single-phase
and `[500,150,50]` W for delta; Q caps are `[80]` var and `[70,30,15]` var.
`fixed_boxes` keeps ``P\in[0,P_{cap}]`` and ``Q\in[-Q_{cap},Q_{cap}]`` at all
steps. `changing_boxes` applies the final three columns, retaining a zero P
lower bound. It fixes/releases Q, fixes/releases P and removes/restores the Q
lower side. No consecutive operating points repeat. All updates are absolute
relative to the original demand, not multiplicative on the preceding state.

These are different feasible sets; objectives are compared across workflows
within each history/scenario, never between histories. The new paths also change
Q capability, demand and prices relative to the earlier experiment. They test
broader-history transfer, not the isolated causal effect of removing its repeat.
They are new operating histories on known manufactured topologies, not unseen
network validation or field time-series observations.

The prospective protocol crosses full/scaled-regional-passive with the same
three initialization treatments and shared controls as the reconstructed-dual
study. Each of four inputs has twelve reversed/rotated sweeps, placing every one of
six workflows in every position exactly twice. If all sequences complete, this
requests 1,728 measured and 144 excluded warm-up solves. There is no subsequent
independent confirmation batch. Admit complete sequences using the existing
strict solver, independent physical/model/fresh-model, reverse-anchor and
scenario-objective checks; retain failures without tuning or fallback retries.

A driver keyword typo stopped the first launch before any optimization. After
its correction, the first case completed six sweeps, but the balance gate caught
that six paired/reversed sweeps do not balance all six workflows. That original
case's 216 measured and 36 warm-up solves, source snapshots and log are preserved
in `HISTORY_ABORTED_BALANCE/` and excluded from the balanced results. The corrected
wrapper uses twelve sweeps, exposes/tests the unchanged order generator and
records planned balance before solving. No observed solve time guided the
scheduling correction, and no fixture, solver setting or acceptance rule changed.
The amended batch reruns all four inputs; batches are not pooled.

The runner now records generator dispatch in W/var after solving. Together with
independently reconstructed scenario limits, this distinguishes actual bound
activity from a box merely changing in the input. Those records and the helper's
correspondence/reset checks are outside the primary Ipopt wall-time score.
The [tutorial](tutorial_exact_ivr.md) shows input construction and reproduction.

### Balanced history results

All **1,728/1,728 measured solves** and **144/144 excluded warm-ups** pass the
strict solver and independent physical/model/fresh-model checks. Every measured
scenario has an accepted reverse anchor. Objectives agree across all six
workflows within every scenario, and every workflow occupies every position
twice. The independent audit also verifies frozen sources, network snapshots,
shared demand/price paths, settings, primal/dual correspondence, all changed-box
resets, removed/restored sides, physical-unit dispatch and sequence sums. The
archived six-sweep case is excluded from these figures and all comparisons.

The table reports median complete six-scenario sums of Ipopt wall milliseconds.
The ratio column divides medians; the final column retains all twelve paired
sequence ratios, including timing outliers.

| Circuit / boxes / formulation | Previous primal (ms) | Zero dual (ms) | Reconstructed dual (ms) | Reconstructed/previous | Paired ratio range |
|:--|--:|--:|--:|--:|:--|
| Single-phase / fixed / full | 94.652 | 99.264 | 89.137 | 0.942 | 0.919–1.268 |
| Single-phase / fixed / regional | 71.577 | 76.362 | 68.263 | 0.954 | 0.885–1.178 |
| Single-phase / changing / full | 89.910 | 88.306 | 87.936 | 0.978 | 0.895–1.142 |
| Single-phase / changing / regional | 67.871 | 67.366 | 66.903 | 0.986 | 0.962–1.013 |
| Delta / fixed / full | 165.959 | 165.061 | 159.711 | 0.962 | 0.523–1.857 |
| Delta / fixed / regional | 164.626 | 165.196 | 159.630 | 0.970 | 0.955–1.827 |
| Delta / changing / full | 163.495 | 156.520 | 150.200 | 0.919 | 0.830–0.984 |
| Delta / changing / regional | 161.418 | 156.251 | 150.386 | 0.932 | 0.837–0.996 |

Reconstructed-dual median gains are **1.4–8.1%** across these inputs and
formulations. They are smaller than the earlier repeat-containing confirmation's
10–26% gains, but the new paths also change Q capability, prices and demand;
that difference cannot be attributed solely to removing repeated scenarios.
For single-phase, fixed-box gains are about 5–6%, while changing-box gains are
only 1–2%. The zero-dual control is within 1% of reconstructed duals in the
changing-box case, so carried multiplier information adds little there.
For delta, fixed-box gains are 3–4% and changing-box gains 7–8%; changing boxes
do not uniformly reduce the benefit. In the latter case, zero-dual initialization
already improves the median by 3–4%, with carried multipliers contributing
approximately another 4% relative to that control.

Six of eight paired ranges cross one, and several contain substantial outliers. Even
where every paired reconstructed/previous ratio is below one, these twelve
measurements do not establish general or statistical-significance claims.
No samples are deleted or settings tuned after examining times. Regional/passive
with reconstructed duals is about 24% faster than full with the same starts on
both single-phase histories. Full and regional reconstructed-dual medians differ
by less than 0.2% on both delta histories; retain both as practical comparators.
Thus representation has the larger measured effect for single-phase, while the
initialization policy remains workload-dependent.

### Active limits and transition evidence

An active bound is labelled diagnostically when dispatch is within ``10^{-3}``
W or var of that bound; this does not change solver or physical admission
tolerances. The single-phase Q upper bound is active throughout the fixed-box
history. In the delta fixed-box history, the third Q channel moves from its
+15 var upper bound at step 2 to its −15 var lower bound at step 3. That lower
bound is also active at steps 4 and 6 in every measured workflow; the largest
observed distance from −15 var is below ``6.2\times10^{-6}`` var. At step 3,
reconstructed-dual initialization takes 17 iterations versus 15 for previous
primals alone. The bound reversal and iteration regression coincide; this does
not isolate their causal relationship from the simultaneous price/P-dispatch
changes. It illustrates why a previous multiplier need not be a useful guess
at every transition.

In the changing-box histories, both Q sides bind at the fixed-zero step and both
P sides bind at the zero-availability step. Removed/restored Q-lower sides and
both-side resets are verified against independently reconstructed scenario
limits. These observations extend exercised bound coverage; they are not a
proof that every possible operating history or unsupported model edit is safe.
The helper remains restricted to its declared same-model update contract.

`HISTORY_PROTOCOL.md`, `HISTORY_SOURCE/`, `HISTORY_HASHES.txt`,
`HISTORY_RUN.jl`, raw input/report/manifest files, `HISTORY_ANALYZE.py` and
`HISTORY_SUMMARY.json` retain the amended design and evidence outside Git.
`HISTORY_PREFLIGHT*` and `HISTORY_ABORTED_BALANCE/` preserve both harness issues.
The next structural priority is an additive adjacent-chain certificate, with
surviving-equation selection and independent interior-bound witnesses; no such
extension is included in this initialization study.

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

A best-evidence recommendation must name its measured domain. The initial
feeder portfolio uses selected inputs with an explicit feasibility objective;
the subsequent dispatch studies use cost objectives. This cannot establish the
fastest formulation for general dispatch, different optimizers, nonlinear-load
mixtures or untested transformers. The repeated-update evidence covers manufactured single-phase/delta dispatch
and selected external feeder demand sequences, not arbitrary operating histories.
Broader mixed-port certificates and factorization-aware selection remain
separate priorities.
