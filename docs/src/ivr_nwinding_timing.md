# Isolated lifted multiwinding timing

The [guarded multiwinding current elimination](ivr_nwinding_elimination.md)
has a modest, repeatable average benefit on the four-winding panel, with important
exceptions. Across 112 matched physical/base cases, elimination reduces the
geometric mean of Ipopt wall-time ratios by about 5%. Uncapped cases improve by
about 10.5%; capped cases average approximately a tie. Capped, excited cases at
the 100 kVA assembly base become slower on average. Keep explicit currents with
power lifting as the control; these results do not justify automatic selection
or a new default.

## Question and controlled experiment

Does removing a nonsingular coil-current block reduce optimizer time after
accounting for wider recovered current expressions and their nonlinear bounds?
The experiment repeats every physical input from the preceding non-star panel:
YYYY and both rolls of YDYY/YYYD/DYYY, both flow directions, absent/present winding
caps, absent/present winding-4 excitation and 1/100 kVA assembly bases. Four arms
cross explicit/eliminated multiwinding currents with `:powers`/
`:bounded_observations` lifting. The previous unlifted failures remain archived
and implemented; they are outside this lifted comparison.

All arms retain the same linear generator power cost, physical engineering
limits, per-unit coordinates, nominal transformer scaling, composed rows,
500 VA power auxiliaries and signed observation sharing. The objective is
``\sum_g c_g P_g/1000`` with the fixture's declared forward/reverse coefficients;
source power is unpriced. This is a manufactured local-optimizer experiment,
not evidence of global optimality or an economic feeder study.

Two fresh Julia processes run the same frozen candidate set. Confirmation
reverses case order and the full trial schedule. Each case has one excluded
warm-up per arm followed by eight measured sweeps. Two four-sweep Williams
blocks balance positions and within-sweep immediate predecessors. Starts are
complete encodings of the same unloaded SI circuit point, never previous OPF
solutions. The unloaded point need not satisfy demand equations; its maximum
model violation is 0.2. Binding and reconstruction errors must be at most
``10^{-10}``, and all encoded coordinates must be finite.

Settings are `tol=constr_viol_tol=1e-10`, `acceptable_iter=0`,
`bound_relax_factor=0`, `max_iter=500`, `max_cpu_time=30`, gradient-based NLP
scaling, MUMPS with automatic ordering request 7, and one Julia/BLAS thread.
The CPU limit is a stopping guard. The **sole ranking metric** is Ipopt.jl
optimizer-call wall time from `JuMP.solve_time`/`MOI.SolveTimeSec`. It includes
backend setup and native `IpoptSolve`, while excluding compilation, model build,
preceding JuMP cache transfer, start encoding, extraction, audits and derivative
queries. No compilation cost penalizes a reduced model.

Every endpoint must pass strict solver status, physical residuals, own/full
model membership, reference feasible-point membership, independent ampere-turn
and leakage equations, the complex-loss identity and SI power-cost reconstruction.
Equation thresholds are ``10^{-6}`` A/V and ``10^{-3}`` VA; objective agreement
uses ``10^{-7}`` absolute and ``10^{-6}`` relative tolerances. A failed warm-up or
measured trial excludes that arm/case. All trials, failures and outliers are
retained; there are no relaxed retries or substituted cases.

## Admission and timing results — 6 October 2026

All **7,168 measured solves and 896 warm-ups** pass. All 224 batch/case cells have
four eligible, objective-comparable arms. Maximum within-case objective spread
is ``1.181\times10^{-12}``; independent cost reconstruction error is below
``8.327\times10^{-17}``. Independent ampere-turn, leakage and loss errors are
below ``3.148\times10^{-12}`` A, ``1.893\times10^{-13}`` V and
``2.458\times10^{-9}`` VA, respectively. All physical inputs equal the prior
panel and all 260 frozen source/environment hashes remain unchanged.

A two-second process monitor records 54 snapshots without detecting competing
Julia work. This establishes sampled Julia isolation, not absence of all system
load or jobs shorter than the sampling interval. Individual case medians span
approximately 0.888–3.818 ms; small differences must be interpreted accordingly.

The following are unweighted geometric means of **within-case median time
ratios**, over all 112 cases. Values below one favor the numerator. They describe
this panel; they are not confidence intervals for a population of networks.

| Numerator / denominator | Exploration | Confirmation | Numerator faster in both batches |
|:--|--:|--:|--:|
| Eliminated / explicit, power lifting | 0.946 | 0.947 | 84/112 |
| Eliminated / explicit, bounded observations | 0.952 | 0.952 | 78/112 |
| Bounded observations / powers, explicit currents | 1.007 | 1.006 | 14/112 |
| Bounded observations / powers, eliminated currents | 1.013 | 1.011 | 13/112 |

Power-lifted elimination improves by more than 5% in both batches in 77 cases,
but worsens by more than 5% in both in 17. Its confirmation ratios range from
0.790 to 1.664. Bounded-observation elimination has 75 such improvements and
19 such regressions, with ratios 0.791–1.704. The near-tie between lifting
choices is not a reliable universal winner.

Post-hoc factor summaries identify a useful next hypothesis. In confirmation,
power-lifted elimination has ratios 0.895 without winding caps and 1.002 with
caps. Breaking capped cases down further gives the following descriptive
subgroups, each containing 14 connections/orientations/flow cases:

| Capped-case excitation | Assembly base | Eliminated / explicit, powers | Eliminated / explicit, bounded observations |
|:--|--:|--:|--:|
| Absent | 1 kVA | 0.948 | 0.965 |
| Absent | 100 kVA | 0.887 | 0.889 |
| Present | 1 kVA | 0.954 | 0.975 |
| Present | 100 kVA | 1.257 | 1.266 |

These interactions are exploratory, not a selection rule. For example, capped,
excited YDYY(+1), reverse flow at 100 kVA takes 12 iterations with explicit power
lifting and 20 after elimination; confirmation medians are 1.875 and 3.120 ms.
Changing coordinates alters nonlinear convergence even though every endpoint
passes the physical and objective gates. A well-conditioned local elimination
block alone cannot predict that behavior.

## Model structure and separate factorization diagnostics

Removing electrical state does not guarantee a sparser nonlinear program. Across
the 112 cases, the changes below are candidate minus explicit-current control
at the same lifting setting. Unique Jacobian/Hessian entries are counted before
Ipopt fixed-variable preprocessing; they are not factor fill.

| Elimination with | Real variables | Unique Jacobian entries | Unique Hessian entries |
|:--|--:|--:|--:|
| Power lifting | -24 | -12 to +144 | 0 to +84 |
| Bounded-observation lifting | -24 or -12 | -12 to +204 | 0 |

Power-lifted elimination adds Hessian entries in all 56 capped cases and none in
uncapped cases. Bounded-observation lifting prevents that Hessian growth, while
introducing more auxiliaries and Jacobian entries. It still does not consistently
beat power lifting. These are distinct costs that primitive state dimension hides.

Sixteen separate verbose solves, each with an excluded warm-up, examine YDYY(-1),
forward flow and excitation, crossing both bases and cap settings. All pass and
report actual MUMPS pivot order 2 for request 7. In the capped 1 kVA illustration,
all arms take 12 iterations:

| Current/lifting choice | Variables | Jacobian | Hessian | Maximum reported INFO(9) |
|:--|--:|--:|--:|--:|
| Explicit, powers | 118 | 540 | 120 | 5115 |
| Eliminated, powers | 94 | 604 | 192 | 4248 |
| Explicit, bounded observations | 120 | 538 | 120 | 5116 |
| Eliminated, bounded observations | 108 | 666 | 120 | 5189 |

INFO(9) is the raw MUMPS factor double-storage counter, not process peak memory or
a measured fill ratio. Here power-lifted elimination lowers it despite derivative
growth; bounded-observation elimination raises it slightly. Native factorization
timers round to 0.000 s in these tiny diagnostics, so they cannot resolve a
factorization-time mechanism. Diagnostic wall times never enter the rankings.

## Reproduction and next tests

The tracked runner preserves the complete protocol's four-arm comparison and
independent endpoint checks:

```sh
julia --project=test examples/benchmark_ivr_nwinding_timing.jl /tmp/nwinding-timing/exploration exploration
julia --project=test examples/benchmark_ivr_nwinding_timing.jl /tmp/nwinding-timing/confirmation confirmation
```

Use fresh processes with `JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1`; avoid
concurrent Julia jobs and record isolation separately. An optional third argument
`preflight` checks all start encodings without solving. The JSON reports retain
every trial, settings, order, admission gate, model/derivative count and timing.
They are benchmark reports, distinct from BMOPFTools-compatible physical result
exports. This pass does not claim a new on-disk physical export audit or rerun
the reference package; that evidence remains in the preceding study.

The external archive `NWINDING_ELIMINATION_TIMING_20261006` contains frozen source,
both complete batches, preflight, probes, isolation samples, raw verbose logs,
analysis and validation scripts. Plans and raw evidence remain outside Git.

The [mixed-device network extension](ivr_nwinding_network.md) constructs larger
coupled cases with additional power objectives and independent recovery checks.
External-feeder validation remains open because the supplied plain JSON inputs
contain no explicit multiwinding records. Larger-model timing must still satisfy
the isolation protocol before supplying a speed recommendation.
Separately test whether retaining selected coil-current observations can reduce
the capped-case derivative growth without sacrificing the uncapped benefit.
Vary reconstruction gain, winding placement and power base in controlled
experiments before introducing automatic policy. Preserve the explicit, fully
eliminated, bounded-observation and unlifted options throughout.
