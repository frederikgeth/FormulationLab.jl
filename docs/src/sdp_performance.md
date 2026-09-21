# SDP structure and scaling study, 12 September 2026

## Next reliability and scale ladder

The next ENWL panel extends the radial ladder to 96, 134, 178, 244, 302, 376,
and 538 buses. Unlike the earlier gated experiment, a numerical failure at one
size does not suppress structurally different later cases. Each case selects a
per-phase base from the larger of nominal apparent load, installed active
generation and 3 kVA, then tests factors one third, one and three. The primary
base is repeated three times after normal execution-path warm-up; sensitivity
bases run once. A 250,000-variable guard and per-solve time limit bound the
experiment.

Rows now distinguish the relaxation's primal objective, the solver's numerical
lower bound, and the feasible BMOPFTools/Ipopt objective. Publication requires
the common `validate_relaxation_solution` audit; recovered AC feasibility is a
separate diagnostic. The BranchFlow profile also exercises opt-in exact affine
preprocessing, which exposes complex rows to shared row scaling and exact
duplicate elimination. Native ENWL feeders remain radial, so a separate
controlled-mesh panel is still required to measure sparse global voltage
completion at these sizes.

## Initial chordal completion pilot, 21 September 2026

A one-thread Mosek 11.2 experiment on the prepared 96-bus ENWL feeder compares
the two chordal orderings and the new `BranchFlowSDP` voltage-closure
decomposition. It is a single-run structural experiment, not a timing
distribution. All rows terminated `OPTIMAL`; maximum scaled JuMP residuals were
below ``8\times10^{-9}``.

For IVR, minimum-fill reduced added chordal edges from 901 to 780, scalar
variables from 9,530 to 9,007, and solve time from 1.73 s to 0.52 s. Recorded
build time also fell from 10.99 s to 7.33 s. This single ordered run includes
Julia compilation/cache effects and is not enough to replace the established
minimum-degree default, but it makes minimum-fill a worthwhile target-specific
option for repeated or larger solves.

The untouched ENWL feeder is radial and does not require BFM's global voltage
closure. To exercise that code path without hiding the intervention, the
benchmark duplicates one named line as a parallel circuit and records both IDs
in the result artifact. The comparison is then:

| BFM closure | Variables | Constraints | Build (s) | Solve (s) | Objective (W) | Residual |
|:--|--:|--:|--:|--:|--:|--:|
| dense, order 288 | 176,802 | 6,418 | 2.49 | 5.10 | -1371.049575 | ``2.10\times10^{-9}`` |
| chordal/minimum-degree, 43 cliques, max order 12 | 19,608 | 6,838 | 0.49 | 0.99 | -1371.048299 | ``7.03\times10^{-9}`` |
| chordal/minimum-fill, same cover | 19,608 | 6,838 | 0.57 | 0.92 | -1371.048299 | ``7.03\times10^{-9}`` |

The chordal representation uses about one ninth as many scalar variables and
solves about five times faster in this run. The dense/chordal objective
difference is 0.0013 W (less than one part per million of its magnitude), which
is consistent with floating-point solve accuracy but is not an exact arithmetic
proof. The two BFM ordering heuristics find the same zero-fill chordal graph, so
their small timing difference has no structural interpretation here.

The reproducible driver is `examples/benchmark_sdp_sparsity.jl`; the retained
records are `examples/results/sdp_sparsity_2026-09-21.json` and
`examples/results/sdp_sparsity_2026-09-21.md`.
Inputs and reported results use SI units; both formulations use per-unit model
coordinates on a 10 kVA base.

## Repeated chordal panel, 22 September 2026

The follow-up runs three fresh builds and solves for each profile on 10-, 11-,
24-, 45-, and 96-bus prepared ENWL feeders. Mosek 11.2 uses one thread and
``10^{-9}`` interior-point feasibility/gap tolerances. Times below are medians.
IVR uses the radial input; BFM uses the recorded parallel-circuit copy described
above, so compare formulations only within their own profile pairs.

| Buses | BFM dense / auto / cap-12 variables | BFM dense / auto / cap-12 solve (s) | BFM statuses | IVR degree / fill edges | IVR degree / fill solve (s) | IVR statuses |
|---:|---:|---:|---|---:|---:|---|
| 10 | 2,958 / 2,958 / 1,926 | 0.191 / 0.190 / 0.165 | slow / slow / slow | 57 / 57 | 0.028 / 0.029 | optimal / optimal |
| 11 | 3,354 / 2,619 / 2,085 | 0.103 / 0.081 / 0.066 | optimal / optimal / optimal | 66 / 66 | 0.013 / 0.013 | optimal / optimal |
| 24 | 13,506 / 5,988 / 4,926 | 0.374 / 0.250 / 0.188 | optimal / optimal / optimal | 549 / 549 | 0.818 / 0.938 | slow / slow |
| 45 | 41,514 / 11,817 / 9,132 | 1.185 / 0.508 / 0.430 | optimal / optimal / optimal | 333 / 324 | 0.143 / 0.147 | optimal / optimal |
| 96 | 176,802 / 26,076 / 19,608 | 4.700 / 1.112 / 0.920 | optimal / optimal / optimal | 901 / 780 | 0.634 / 0.518 | optimal / optimal |

The automatic BFM rows use the public defaults: dense closure through order 32,
then minimum-degree chordal completion with merge cap 32. The cap-12 rows force
chordal completion. These support graphs need zero fill before clique
amalgamation, so minimum-degree and minimum-fill produce the same BFM layout.
Dense/auto/cap-12 objectives differ by at most 0.0031 W on rows where all
variants terminate `OPTIMAL`; maximum scaled residuals are below
``3\times10^{-8}``. At 33 live voltage coordinates—the first case above the
automatic dense threshold of 32—the automatic layout is already smaller and
faster than dense. The 30-coordinate case has no trustworthy numerical
comparison because every layout terminates `SLOW_PROGRESS`. These data support
retaining the threshold at 32.

Cap 12 is smaller and faster than the cap-32 automatic layout on all four
optimal BFM cases, so it is a good measured Mosek option for similar networks.
The panel uses one solver and a controlled synthetic parallel circuit, however,
while the implicit solver profile is Clarabel. We therefore retain the
solver-agnostic cap-32 public default pending a repeated Clarabel comparison.

For IVR, minimum-fill helps the 96-bus layout, is neutral on the smallest cases,
and does not improve the 24- or 45-bus solve. Both forced-chordal variants stall
on the 24-bus case; its largest indivisible clique has order 14 even with merge
cap 12. This supports retaining `decomposition=:auto` and minimum-degree as the
defaults while keeping minimum-fill available for measured, target-specific
use.

The complete protocol, objective differences, dataset caveat, and raw-artifact
index are in `examples/results/sdp_sparsity_panel_2026-09-22.md`. The only
genuinely meshed local dataset is currently a 3,409-bus OpenDSS case whose open
switch statuses do not survive parsing without manual correction; it was not
used as a quick comparator.

The retained improvement is voltage-region preconditioning for the Clarabel SDP
profile. It improves both solve time and numerical accuracy on the two mixed
voltage LV snapshots. The three ENWL cases have a single voltage region; their
scaled and unscaled formulations are identical. Small timing differences there
are measurement variation, not speedups.

The size-based clique merger and automatic dense shortcut remain the defaults.
Reduced-rank cost merging is available for experiments, but did not establish a
consistent advantage in this panel. Smaller overlap systems alone are not a
reliable predictor of Clarabel performance.

## Protocol

We use the same 24-, 45-, and 96-bus ENWL cases and two LV snapshots as the
previous SOC studies. BMOPFTools-style preparation leaves the ENWL bus counts
unchanged and reduces each LV snapshot from 907 to 118 buses. Every variant
receives the identical prepared network. Source-bus generators are removed in
memory; other generators remain, taps are fixed, and control laws are omitted.
The objective is source active-power import. The per-phase power base is
`max(total apparent nominal load, total active generator capacity, 3000 VA)/3`.

Julia 1.12.6 and Clarabel 0.11.1 run with one Julia thread and one BLAS thread.
Each reported main-panel time is the median of three fresh-optimizer solves,
after a small-case warm-up. Native Clarabel `solve!` time excludes JuMP
attachment, model construction, and result recovery. These are serial runs;
tests and documentation builds do not run alongside the timed solves.
Feasibility, absolute-gap and relative-gap tolerances are `1e-7`, `1e-6`, and
`1e-7`. Local chordal models retain static regularization `1e-5` and up to 30
refinement iterations. Dense models retain their existing solver defaults.
No incumbent is used to select cuts, coordinates or cliques. Repeated solves
are benchmark repetitions, not an iterative outer approximation.

The original panel compares size merging/global scaling, cost merging/global
scaling, size merging/region scaling, and cost merging/region scaling. The cost
probe explicitly uses reduced cap 32 and overlap weight 8. A supplemental sweep
uses automatic decomposition, reduced cap 12, and weights 1 or 8 on the three
cases that actually use chordal decomposition. The 24- and 45-bus cases have
reduced orders 28 and 29, so their automatic layouts are dense.

## Main-panel native solve times

| Case | Old global/size (s) | Region/size, retained default (s) | Global/cost32/w8 (s) | Region/cost32/w8 (s) |
|:--|--:|--:|--:|--:|
| ENWL 24 buses | 4.463 | 4.494 | 4.468 | 4.321 |
| ENWL 45 buses | 10.736 | 10.434 | 10.736 | 10.331 |
| ENWL 96 buses | 1.349 | 1.331 | 3.934 | 3.943 |
| LV t500 (118 buses) | 1.669 | 0.700 | 3.635 | 2.166 |
| LV t1000 (118 buses) | 1.371 | 0.539 | 3.605 | 1.636 |

## Conservative large-case sweep

| Case | Retained region/size default (s) | Global/cost12/w1 (s) | Global/cost12/w8 (s) | Region/cost12/w1 (s) |
|:--|--:|--:|--:|--:|
| ENWL 96 buses | 1.331 | 1.330 | 1.632 | 1.316 |
| LV t500 (118 buses) | 0.700 | 1.781 | 2.343 | 1.087 |
| LV t1000 (118 buses) | 0.539 | 1.989 | 2.145 | 0.754 |

## LV accuracy and iteration counts

| Snapshot | Old objective (W) | Region-scaled objective (W) | Stored NLP (W) | Iterations, old → scaled | Maximum model violation, old → scaled |
|:--|--:|--:|--:|--:|:--|
| t500 | 22462.962673 | 22418.515539 | 22418.515509 | 63 → 25 | 4.64e-06 → 3.46e-09 |
| t1000 | 48932.374871 | 48869.908008 | 48869.907839 | 49 → 17 | 7.82e-06 → 5.66e-10 |


## Numerical accuracy matters alongside time

All main-panel runs reported `OPTIMAL`. That does not make their reported
objectives equally trustworthy. The old unscaled LV solves had model violations
large enough to matter, and even their reported dual objectives exceeded the
previously stored feasible NLP objectives. They must not be used as dependable
lower bounds. Region scaling reduces these residuals and restores agreement
with the stored BMOPFTools/Ipopt results.

The NLP values are reused from `examples/results/reduction_soc_2026-09-11.json`,
not new NLP solves. The root input-file hashes match. Ipopt's locally optimal
points and the floating-point conic primal/dual reports are numerical references,
not certified global gaps. Maximum model violations are measured with JuMP's
`primal_feasibility_report`; they are not independent AC feasibility checks.

## Why we retain the existing clique defaults

On the 96-bus case, the aggressive cost probe reduced the potential real
separator dimension from 1,724 to 317, but increased the maximum reduced cone
order from 11 to 18. Factorization nonzeros rose from 1,472,194 to 2,033,756,
and median native solve time rose from 1.35 to 3.93 seconds. Removing overlap
equations traded them for more expensive cone algebra and factorization.

Forcing local chordal decomposition on the 24-bus case with the old size merger
was worse still: two pilot solves took 58.40 and 58.84 seconds, versus 4.46 seconds
for its automatic dense model. Factorization nonzeros rose from 1,374,442 to
11,259,947. A forced cost/cap-12/weight-1 pilot took 78.22 seconds. A merge cap
cannot split an original indivisible clique, and those layouts still contained
rank-22 blocks. These pilots were stopped rather than completing the entire
forced-chordal panel. The benchmark now stops repetitions after a failed solve
or a native solve longer than 30 seconds; the solver's 60-second limit is not a
strict wall-clock bound on setup or a long iteration.

Further work should estimate factorization fill and improve elimination
ordering or separator coordinates before changing the default layout. The
current cubic cone/separator surrogate is an inspectable heuristic, not a
validated Clarabel runtime predictor. The formulation details and scientific
lineage are described in [numerical profiles](sdp_numerics.md).

## Reproduction and records

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test/integration \
  examples/benchmark_sdp_structure.jl \
  examples/results/sdp_structure_manifest.json results.json 3

JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test/integration \
  examples/benchmark_sdp_structure.jl \
  examples/results/sdp_structure_large_manifest.json conservative.json 3 --conservative
```

The optional integration environment supplies the established parser/preparation
workflow; it does not add BMOPFTools to FormulationLab's runtime dependencies.
Raw records under `examples/results/` are:

- `sdp_structure_2026-09-12.json`: complete main panel.
- `sdp_structure_conservative_2026-09-12.json`: conservative large-case sweep.
- `sdp_structure_chordal_pilot_2026-09-12.json`: partial size-merger pilot.
- `sdp_structure_chordal_2026-09-12.json`: partial forced cost-merger pilot.

Records include source/input hashes, solver versions, settings, individual
repetitions, objective and dual reports, residuals, cone/separator diagnostics,
canonical constraint sparsity and factorization nonzeros. The manifests contain
local paths that need adjusting on another machine.
