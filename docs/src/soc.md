# SOC outer approximation

`IVRSOC` uses the same electrical equations, nullspace elimination, fixed taps,
component laws, voltage bounds and optional LNCs as `IVRSDP`. It replaces each
**complex Hermitian** moment cone, before any real embedding, by

```math
H_{ii}\geq0,\qquad
\left\|[2\Re H_{ij},2\Im H_{ij},H_{ii}-H_{jj}]\right\|_2
\leq H_{ii}+H_{jj}.
```

This is exact for blocks of order at most two. Larger blocks need not be PSD.
The formulation retains any power cones used by voltage-dependent load
relaxations; neither construction nor separation introduces PSD cones.
The choice of coordinates and clique cover affects SOC strength. Keep the
`SDPOptions` layout and electrical cuts fixed when comparing relaxations.

## Physical projections

By default, every device and rating voltage–current pair gets an additional
SOC constraint. For physical maps `a` and `b`, define

```math
w=aHa^H,\quad \ell=bHb^H,\quad s=aHb^H,\qquad
|s|^2\leq w\ell,\quad w,\ell\geq0.
```

Here the maps include the electrical nullspace transformation. These cones
retain PSD consequences that coordinate-wise minors alone lose, including
for delta windings and explicit neutral currents. Auxiliary cone variables separate these dense projections from the conic
coordinates. Their two diagonal entries
are independently scaled, with the cross term scaled by the geometric mean.
Terminal and bus voltage maps also receive nonnegative squared magnitudes.
Lines whose series impedance and both shunt admittances have positive
semidefinite Hermitian parts receive nonnegative total active-loss constraints.
These are outer constraints, not diagonal-dominance restrictions.

## Usage and separation

```julia
using FormulationLab, Clarabel
f = IVRSOC(s_base=10_000.0, objective=:source_import)
build = build_opf(network, f)
result = solve_soc_opf(build; solver_options=(verbose=false,))

# Optional tightening of the same inspectable JuMP model:
result = solve_soc_opf(build;
    separation=PSDSeparationOptions(max_rounds=20, max_cuts=2000,
                                   time_limit=60.0, tolerance=1e-6),
    solver_options=(verbose=false,))
```

After each accepted solve, separation diagonalizes the target reduced moment
blocks. A negative eigenvector `u` supplies the valid linear cut

```math
u^H H u\geq0.
```

Cuts are ordered by relative violation, batched, and deduplicated up to complex
phase. They remain in the model. Budgets limit additional solve rounds, total
cuts added by the call, and elapsed time; the remaining time is also passed to
the optimizer. Compilation and optimizer setup can exceed a time budget.
The spectral residual is the largest
`max(0, -λmin(H)) / max(1, maximum(abs, eigvals(H)))` over target blocks.

`SOCResult` returns the block values, relaxed component powers, solver bound,
iteration history, stop reason, and spectral residual. `solve_diagnostics`
also preserves omitted-control, load-envelope, LNC and numerical metadata. It deliberately does
not perform PSD completion or return a recovered AC voltage. Meeting the
spectral tolerance is a numerical check, not an AC-feasibility certificate.
With exact solves and exact PSD feasibility, an outer-approximation optimum
also solves the matching SDP. Finite tolerances and ill-conditioning prevent
using this statement as a rigorous bound certificate.

Only fully optimal, feasible solver outcomes publish objectives. A failed
later round returns `:solver_failure` and `NaN` objective; earlier accepted
objectives and bounds remain in `history`. A time expiry between rounds
returns the last accepted iterate and its own cut count. `:round_limit`,
`:cut_limit` and `:stalled` do not claim PSD feasibility.

For pairwise cones without physical strengthening, use
`IVRSOC(physical_projections=false, ...)`. Explicit optimizer factories and
attributes remain under caller control, including optional alternative
solvers. ExaModels and nonconvex recovery are outside this backend.

The default Clarabel SOC profile uses static regularization `1e-7` and up to
30 iterative-refinement steps, without PSD chordal decomposition. Passing an
optimizer explicitly bypasses this profile. The default separation tolerance
is `1e-6`; tightening it can trigger numerical stagnation near a rank-deficient
PSD face even after the objective has stabilized.

## ENWL Clarabel measurements

The four reduced ENWL feeders below use the same source-import objective,
source-bus generator removal, voltage bases, current bounds and LNC setting
(`:off`) as the SDP comparison. The finite `-1e10 S` source-neutral shunt is
retained. Per-phase power bases are 1333.333, 1829.474, 6865.263 and 14666.667 VA.
The comparison used Julia 1.12.6, Clarabel 0.11.1, one BLAS thread, and a small
feeder warmup. Times are one run, not statistical averages.

| Buses | SDP import (W) | Physical SOC import (W) | SDP solve (s) | SOC solve (s) | SOC build (s) |
|---:|---:|---:|---:|---:|---:|
| 5 | -1705.610445 | -1705.610437 | 0.0050 | 0.0056 | 0.017 |
| 8 | 1221.897996 | 1221.887564 | 0.0083 | 0.0125 | 0.026 |
| 23 | -406.697689 | -406.992800 | 5.6562 | 13.3429 | 0.557 |
| 87 | -2664.267679 | -2668.336806 | 1.7378 | 0.4998 | 13.342 |

All four one-shot physical SOC solves returned `OPTIMAL`. The objective
differences from the cached Ipopt solutions are numerical noise, 0.01043 W,
0.29511 W and 4.06910 W respectively. These are objective comparisons, not
certified AC optimality gaps. Physical SOC's maximum scaled constraint
violations were `5.46e-8`, `1.20e-5`, `1.31e-10` and `1.83e-6`; solver status
alone should not replace residual inspection.

Pairwise SOC without physical projections is faster, but gives import
objectives of -1715.652, 1211.303, -5118.673 and -2733.684 W. Its 23-bus
solution also has a `5.49e-3` maximum scaled constraint violation.
The physical projections are therefore enabled by default.

The optional separator used a 90-second budget, at most 30 additional rounds
and a relative spectral tolerance of `1e-6`:

| Buses | Outcome | Import (W) | Cuts | Relative PSD residual | Total solve/separation (s) |
|---:|---|---:|---:|---:|---:|
| 5 | `psd_tolerance` | -1705.610445 | 6 | 5.24e-07 | 0.038 |
| 8 | `round_limit` | 1221.897995 | 41 | 1.77e-06 | 0.454 |
| 23 | `time_limit` | -406.981390 | 65 | 2.47e-01 | 102.764 |
| 87 | `solver_failure` | — | 111 | — | 1.000 |

The 87-bus cut solve returned `ALMOST_OPTIMAL`; its objective is not published.
Accepted earlier rounds remain in the raw history. The 23-bus time includes
optimizer rebuilding/setup, which can overrun the solver's remaining-time
limit. A stricter `1e-7` spectral target also caused the 5-bus cut loop to
return `ALMOST_OPTIMAL`, despite an already stabilized objective.

Physical SOC offers a useful solve-time tradeoff on the 87-bus case, but the
shared electrical build takes about 13 seconds for both formulations. Its
end-to-end advantage is consequently small. On the 23-bus case the current
SOC representation is slower than SDP. Eigenvector separation remains an
optional research tool; it is not yet a reliable replacement for direct SDP
on these feeders.

Reproduce the measurements with:

```sh
julia --project=test examples/benchmark_soc_enwl.jl /path/to/ENWLbenchmark/reduced output.json
```

The full record, including solver bounds, per-round histories, input hashes,
cone types and residuals, is in
`examples/results/enwl_soc_clarabel_2026-09-11.json`.
