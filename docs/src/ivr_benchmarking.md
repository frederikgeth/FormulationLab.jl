# Benchmarking exact-IVR formulations

This page describes the benchmark method that replaced the per-campaign timing
protocols of September–October 2026. The [findings](ivr_findings.md) page reports
what it measured. Earlier campaign pages are kept under *Archive* in the
navigation. They remain valid records, but no new work extends them.

## What is measured, and why

For a sparse interior-point method, solve time is approximately

```math
T \approx N_{\mathrm{iter}} \times \left(\frac{N_{\mathrm{fact}}}{N_{\mathrm{iter}}}\, c_{\mathrm{fact}} + c_{\mathrm{eval}}\right),
```

where ``N_{\mathrm{iter}}`` is the number of iterations and ``N_{\mathrm{fact}}``
is the number of KKT factorizations. Ipopt refactorizes when inertia is wrong or
pivots are too small, so ``N_{\mathrm{fact}}/N_{\mathrm{iter}}`` can exceed one.
``c_{\mathrm{fact}}`` grows with the factor size (fill) and ``c_{\mathrm{eval}}``
is the derivative evaluation cost. A formulation choice is useful only if it
moves one of these terms. The harness therefore records every term:

| Quantity | Source |
|:---|:---|
| Optimizer wall time | `JuMP.solve_time` (excludes model build, which is recorded separately) |
| Iterations, status | MOI attributes |
| Function-evaluation vs internal time, primal-dual solve time | Ipopt `print_timing_statistics` |
| Jacobian and Hessian nonzeros, variable and constraint counts | Ipopt problem statistics |
| Number of factorizations and largest MUMPS factor (INFO(9)) | Ipopt output at file print level 6, from a separate untimed diagnostic solve |
| Physical correctness | `physical_residuals` in SI units, with the default tolerances |

A trial *succeeds* when the solver reports local optimality and the SI residuals
pass. An arm *solves* an instance only if every timed repetition succeeds.
Failures are kept, and they count against the arm.

## Design

- **Arms** are named option sets in `examples/ivrbench/IVRBench.jl`. Each changes
  one factor relative to the `powers` control (power lifting only) or the
  `reduced` arm. Use as few arms as answer the question.
- **Noise floor**: `powers_dup` builds the same model as `powers`. The spread of
  their median ratio is the smallest difference worth interpreting. At the
  smallest sizes it is about 1% for Ipopt and up to about 10% for MadNLP.
- **Repetitions**: one untimed compile warm-up per process, one diagnostic solve
  per arm, then three to five timed cold solves on fresh builds. Arm order
  rotates between repetitions. Report medians and interquartile ranges.
- **Solver settings**: rankings use near-default Ipopt (`tol=1e-8`, acceptable
  termination enabled, default bound relaxation), because users run with those
  settings. The historical strict settings (`tol=constr_viol_tol=1e-10`,
  `bound_relax_factor=0`, no acceptable exit) are a separate `ipopt_strict`
  configuration for comparison. Endpoint correctness is checked independently
  in SI, so the solver tolerance need not carry it.
- **Solvers**: Ipopt 3.14 with MUMPS, and MadNLP with MUMPS on the same JuMP
  models. A licensed HSL library was not available. Rankings may differ with
  MA27/MA57/MA86 and should be rechecked there.
- **External baseline**: `baseline.jl` times BMOPFTools' independent IVR-EN model
  (PowerModelsDistribution convention) on the same instance and settings.
- **Workloads**: unmodified French MV/LV feeders from 110 to 1,583 buses, plus
  larger SAPN networks. Priced DER generators are added at every fifth
  three-phase load (`IVRBench.instance`), and loads are scaled to
  0.5/1.0/1.5/2.0× for robustness. Instances no arm can solve (for example,
  nominal loads beyond a feeder's limits) are excluded from performance
  profiles and reported.
- **Analysis**: `analyze.jl` reports the noise floor, geometric-mean time and
  iteration ratios against the control, Dolan–Moré performance profiles,
  Ipopt's time shares, a log-linear cost model, objective spread across arms,
  and MadNLP/Ipopt ratios.

## Running it

```sh
julia --project=examples/ivrbench -e 'using Pkg; Pkg.instantiate()'
julia --project=examples/ivrbench examples/ivrbench/run.jl results.jsonl CASE1.json CASE2.json \
    --reps 5 --factors 1.0,1.5 --solvers ipopt,madnlp
julia --project=examples/ivrbench examples/ivrbench/analyze.jl results.jsonl > report.md
julia --project=examples/ivrbench examples/ivrbench/baseline.jl baseline.jsonl CASE1.json --reps 3
```

Run independent jobs on separate cores with `JULIA_NUM_THREADS=1` and
`OPENBLAS_NUM_THREADS=1`. The duplicate arm shows whether concurrent jobs
disturbed the timings.

## What this deliberately omits

Earlier campaigns used SHA-bound preparation freezes, authorization-gated
launchers, Williams-balanced orderings, parent-lineage exposure reviews and
isolation snapshots. Those controls targeted single-digit effects on sub-second
solves. The effects that matter here (2–4×, below) are large compared with the
measured noise floor, and they recur across sizes and solvers. Raw JSON lines
and the analysis script are enough to reproduce them. Use heavier protocol only
when a decision really depends on an effect close to the noise floor.
