# Exact-IVR performance findings

This page summarizes what makes the exact current–voltage OPF fast and reliable
under Ipopt-like interior-point solvers. It reports the October 2026 benchmark.
The [benchmarking method](ivr_benchmarking.md) page describes how it was run.
The raw results and generated reports are in `examples/ivrbench/results/`.

## Summary

1. **Ipopt's time is (number of KKT factorizations) × (factor size).** A
   log-linear fit over 97 (instance, arm) cells gives
   ``T \propto N_{\mathrm{fact}}^{0.95} \cdot \mathrm{fill}^{1.03}`` with
   ``R^2 = 0.994``. Derivative evaluation is 3–5% of Ipopt's time, and the
   primal-dual solve is 80–95%. A formulation helps only if it reduces the
   number of factorizations or the fill.
2. **Per-voltage-zone coordinates are the formulation choice that matters.**
   `transformer_scaling=:nominal` alone cuts Ipopt time to 0.43× and iterations
   to 0.68× of the power-lifted control. Composed rows and ground scaling add
   nothing. Without per-zone coordinates, a single base spans 20 kV and 400 V,
   MUMPS meets tiny pivots, and Ipopt refactorizes about twice per iteration.
   With them, it refactorizes about once.
3. **The solver configuration matters as much as the formulation.**
   `mumps_pivtol=1e-3` alone gives 0.50×, and MadNLP (also MUMPS) on unchanged
   models gives 0.26–0.28× on the French feeders (but not at 22k buses, see
   below). Both converge in about 20 iterations whatever the
   formulation.
4. **Reductions and lifting are second-order.** Once conditioning is fixed,
   conductor-region specialization, passive blocks and zero-load elimination
   save another 15–25% through smaller factors. Without fixed conditioning they
   are as likely to slow Ipopt down, and on the largest feeders they make it
   fail. Broad observation lifting was the slowest arm under every solver.
5. **The new `:scaled` profile** (power lifting and per-zone coordinates) is the
   recommended default. On 18 held-out instances it is 0.46× the old control
   under default Ipopt. On a 22k-bus network it was the fastest profile under
   both Ipopt settings: 3.4× faster than the control under default Ipopt.
   `:fast` adds the safe reductions. It was 13% faster than `:scaled` on the
   French feeders (0.40×, fastest on 18 of 19) but 2.1× slower than `:scaled`
   on the 22k-bus network.
6. **Wrapper overhead had swamped the solver at scale.** Hashing the network for
   result provenance took about 10 minutes per solve on the 22k-bus network,
   against 7 s in Ipopt, and one reduction made builds quadratic. Both are fixed
   (below).

| Configuration (held-out panel, 18 instances) | Time vs old control | Median time |
|:---|---:|---:|
| Ipopt, `powers` (old control) | 1.00 | 694 ms |
| Ipopt, `:reference` | 0.89 | 633 ms |
| Ipopt, `:scaled` (recommended) | 0.46 | 369 ms |
| Ipopt, `:fast` | 0.40 | 329 ms |
| Ipopt + `mumps_pivtol=1e-3`, `powers` | 0.50 | 445 ms |
| Ipopt + `mumps_pivtol=1e-3`, `:fast` | 0.36 | 311 ms |
| MadNLP, `powers` | 0.28 | 231 ms |
| MadNLP, `:fast` | 0.26 | 220 ms |

## Mechanism: conditioning, not size

The scaling ablation (5 feeders, 110–995 buses) varied one coordinate choice at
a time on top of the reduced model.

| Arm | Default Ipopt | Ipopt, `mumps_pivtol=1e-3` |
|:---|---:|---:|
| `powers` (control) | 1.00 | 1.00 |
| `reduced` (no scaling) | 1.11 | 0.84 |
| `reduced` + ground scaling | 1.11 | 0.82 |
| `reduced` + composed rows | 0.95 | 0.82 |
| `reduced` + transformer coordinates | **0.43** | **0.73** |
| `reduced` + all three | 0.46 | 0.78 |
| `powers` + all three (no reductions) | 0.50 | 0.95 |

Values are geometric-mean ratios of median Ipopt time. The noise floor (the
identical-model duplicate arm) was at most 2.7%.

Transformer coordinates carry the whole effect, with or without reductions.
Raising the MUMPS pivot tolerance removes most of the penalty of poor scaling,
and all arms then converge in about 21 iterations. That is the signature of a
conditioning problem: with the default threshold of `1e-6`, Ipopt keeps raising
the pivot tolerance and refactorizing. On the 498-bus feeder, `powers` needed
92 factorizations for 47 iterations, while the scaled model needed 31 for 25.

The repository's earlier refinement, residual-precision and pivot-threshold
studies were circling the same effect. Its earlier observation that a 1e-3
pivot threshold cuts linear solves from 118 to 67 is the same mechanism seen
from the solver side.

## Scale and failures

The 6-feeder scaling sweep runs from 110 to 1,583 buses, with priced DER at
every fifth load. The results:

- **Time ratio.** Per-zone coordinates were 0.42× under Ipopt, and the gap
  widens with size. At 995 buses, `full` took 11.8 s (82 iterations) while
  `reduced_scaled` took 1.35 s (20 iterations).
- **Failures.** At 995 and 1,583 buses, several unscaled arms stopped at
  `ALMOST_LOCALLY_SOLVED` or worse in every repetition. These include
  `powers` at 995 buses and all unscaled reduced arms at 1,583. The scaled
  model solved every instance.
- **MadNLP.** It solved every arm at every size. At 1,583 buses most
  formulations took 1.4–1.5 s; broad lifting and zero-load elimination alone
  were slower.
- **Iterations.** For `full`, Ipopt's iteration count grew from 20 at 110 buses
  to 82 at 995 buses. The scaled model stayed at 20.

## External baseline

BMOPFTools' independent IVR-EN implementation (PowerModelsDistribution
convention, per-unit, same Ipopt settings) ran at 0.86× the `powers` control
and was faster than FormulationLab's `:reference` model. The scaled reduced
model was 0.43×, between 1.35× and 3.4× faster than BMOPFTools. At 1,583 buses
it took 2.2 s, against 7.5 s for BMOPFTools and 15.5 s for `:reference`.
Before this work, FormulationLab's default exact IVR model was slower than an
existing implementation.

## Historical strict settings

The campaign settings (`tol=constr_viol_tol=1e-10`, `bound_relax_factor=0`, no
acceptable exit) leave the main conclusion unchanged: `reduced_scaled` ran at
0.37×. They do reorder the unscaled arms (`full` beat `powers`, for example),
which shows how fragile the earlier single-digit rankings were. Strict
tolerances shrink the objective spread between arms from about 1e-4 to 1e-9.
Use them for correctness checks, not for ranking formulations.

## Robustness

Loads were scaled to 0.5/1.0/1.5/2.0× on 10 feeders. Most 1.5× and 2.0× instances
are infeasible for every arm under both solvers, and BMOPFTools agrees on the
scaling-sweep feeders. That leaves 20 feasible instances:

| Arm | Ipopt solved | Ipopt time ratio | MadNLP solved | MadNLP time ratio |
|:---|---:|---:|---:|---:|
| `powers` (control) | 19/20 | 1.00 | 20/20 | 1.00 |
| `full` | 20/20 | 0.88 | 20/20 | 1.01 |
| `powers` + zero loads | 19/20 | 1.20 | 20/20 | 0.88 |
| `reduced` | 20/20 | 1.19 | 20/20 | 0.95 |
| `reduced` + transformer-current elimination | 20/20 | 1.25 | 20/20 | 1.01 |
| `reduced` + broad lifting | 15/20 | 1.74 | 20/20 | 1.62 |
| `reduced` + all scaling | **20/20** | **0.40** | 20/20 | 0.80 |

Under Ipopt the scaled model was fastest on all 20 instances. No other arm
came within 1.5× of it on more than 15% of them (performance profile in
`robustness_report.md`). MadNLP solved every arm everywhere.
Its formulation differences are mostly within its noise (median 11%), except
that broad lifting was consistently slower.

## A 22k-bus network

The Texas pilot (22,081 buses, 2 transformers, about 229k variables) was run at
0.5× load with added DER. Ipopt reported local infeasibility at nominal load for
every arm.

| Profile | Default Ipopt | Ipopt, `mumps_pivtol=1e-3` | MadNLP |
|:---|---:|---:|---:|
| `powers` (control) | 26.8 s, 47 it, 98 factorizations | 7.3 s, 23 it | 12.0 s, 23 it |
| `:scaled` | **8.0 s**, 20 it, 21 factorizations | **6.3 s**, 20 it | 19.8 s, 22 it |
| `:fast` | 17.1 s, 29 it, 45 factorizations | 7.7 s, 20 it | 14.6 s, 22 it |

The conditioning mechanism appears again: under default Ipopt the control
refactorizes about twice per iteration and the scaled model about once. Here the
structural reductions in `:fast` *cost* factorizations. At this size, Ipopt with
the pivot tolerance was faster than MadNLP. MadNLP's advantage on the French
feeders therefore does not carry over to every network or size. These are single
solves per cell.

## End-to-end overhead

At scale, the solver was not the bottleneck:

- **Network digest.** Every solve hashes a canonical JSON of the network for
  result provenance. SHA.jl hashed the String through a slow `CodeUnits` path:
  4.35 s at 995 buses (three times the Ipopt solve) and about 570 s at 22k buses
  (75 times the solve). Hashing the bytes gives the same digest in 7 ms.
- **Quadratic build.** Zero-load elimination recomputed the network-wide neutral
  map for every bus: 85% of a 995-bus build, and about 15 minutes for a reduced
  build at 22k buses. Computing it once gives 0.40 s and 79 s respectively.

Both fixes are committed and the full test suite passes. Build time for the
22k-bus network is now about 75 s for every profile. That is still ten times
the solve, so reuse builds through the update APIs when solving repeatedly.

## What this does not show

- **Mostly one network family.** All but one timed network are French MV/LV
  feeders with ordinary transformers. The 22k-bus Texas pilot was run once per
  cell. SAPN networks are refused by the compiler (bus field
  `grounding_assumption`).
- **No licensed HSL, no GPU.** Rankings may change with MA27/MA57/MA86, and
  MadNLP's GPU path (condensed KKT, cuDSS) was not tested.
- **MadNLP timing is noisy** (median noise 7–10%, occasional outliers to 76%).
  Its formulation differences are mostly within that noise.
- **One objective.** All instances use linear prices on source import and DER.
  The power-objective workloads of the earlier campaigns were not rerun.
- **Local solutions.** Arms can reach slightly different objectives at default
  tolerances (relative spread up to about 2e-4). No arm was rejected for that.

## Recommendations

1. Use `IVRNLP(profile=:scaled, ...)` with `solver_options=ivr_ipopt_options()`.
   Try `:fast` on MV/LV workloads like the French feeders, and benchmark it first.
2. Make per-zone coordinates (`transformer_scaling=:nominal`) the default.
   It is a pure change of variables, and it is the one choice that matters.
3. Evaluate MadNLP as the primary solver. An ExaModels backend is the logical
   next step, now that function evaluation is shown to be cheap and the KKT
   solve dominates.
4. Retire options whose effect is below the noise floor or negative
   (`bounded_observations` lifting, ground scaling, composed rows, the
   separate power-unit bases), or keep them only behind explicit opt-in.
5. Benchmark further changes against this harness on larger, more varied
   networks, starting with closing the SAPN schema gap.
