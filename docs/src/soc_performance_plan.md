# Clarabel solve-time comparison and next steps

Controlled study, 11 September 2026, on implementation `cdeefe9`. The main
comparison contains 90 solves: six fixed configurations, five cases, three serial
repeats each. The strongest measured improvement is explicit sparse coordinates
on the 24- and 45-bus cases: about 19× and 26× faster native solves, respectively,
with weaker objective bounds for linear cuts alone. Adding eight fixed Kim
triplets gives the best balanced candidate: 1.36 seconds / 3.09 W difference on
24 buses and 2.92 seconds / 16.48 W on 45 buses. Neither fewer refinement steps
nor removal of the linear cuts gives a comparable benefit. No library defaults were changed.

See the [full main report](https://github.com/frederikgeth/FormulationLab.jl/blob/main/examples/results/soc_controlled_2026-09-11.md)
and [raw measurements](https://github.com/frederikgeth/FormulationLab.jl/blob/main/examples/results/soc_controlled_2026-09-11.json).
The [environment record](https://github.com/frederikgeth/FormulationLab.jl/blob/main/examples/results/soc_controlled_environment_2026-09-11.json)
pins package and input-repository versions; each run records its input hash.
Scientific lineage and the distinction between approximation and relaxation remain
in the [formulation decision record](formulation_choices.md).

## Main results

Times below are median **native Clarabel solve seconds**, excluding construction,
setup, extraction and reconstruction. All default and sparse32 runs returned
`OPTIMAL` in all three repeats. Objective differences use fresh reduced-network
BMOPFTools/Ipopt local solutions, not certified global optima.

| Case | Default linear32 s | Sparse32 s | NLP − default W | NLP − sparse32 W |
|:--|--:|--:|--:|--:|
| ENWL 24 buses | 16.907 | 0.875 | 0.104 | 25.462 |
| ENWL 45 buses | 58.371 | 2.215 | 20.697 | 57.434 |
| ENWL 96 buses | 1.351 | 1.355 | 33.607 | 33.607 |
| LV t500, 907 → 118 buses | 0.715 | 0.710 | 86.219 | 86.219 |
| LV t1000, 907 → 118 buses | 0.612 | 0.609 | 355.879 | 355.879 |

“Sparse32” means `IVRSOC(basis=:sparse, clique_size=32, strengthening=:linear)`
with the same remaining options and tolerances. On 96 buses and both LV snapshots,
the default already selects sparse coordinates: these are duplicate controls,
not evidence of further speedup. The 24-bus objective difference rises from
0.00258% to 0.63255% of absolute net import; the 45-bus difference rises from
0.70348% to 1.95212%. Absolute watts are preferable near import/export cancellation.

The 24-bus default uses one order-28 moment block but has 1,008,105 nonzeros in
Clarabel's constraint matrix and 2,446,244 in its KKT factor. Sparse coordinates
reduce these to 241,391 and 399,609. On 45 buses, the order-29 block's constraint
nonzeros fall from 2,016,645 to 520,295 and factor nonzeros from 4,682,117 to 699,572.
KKT updates account for roughly 94–95% of native time in these dense defaults.
This points to matrix structure and refactorization cost as the primary target;
the timer also includes the constant-RHS solve, so it is not a pure factorization
measurement.

Other controls:

- Reducing the refinement cap from 30 to 5 gives the same iteration counts and
  objectives on every case. Medians on 24/45 buses are 17.505/59.848 seconds,
  versus 16.907/58.371 for the default. There is no demonstrated benefit.
- Removing linear strengthening gives 19.167/57.275 seconds on 24/45 buses with
  marginally weaker bounds. The small mixed timing differences do not justify a
  general change. Retain the secants.
- Kim32 takes 30.953/77.581 seconds on 24/45 buses and reduces objective differences
  to 0.066/10.188 W. Kim12 produces the same dense layouts there.
- On 96 buses, Kim12 is useful: 3.131 seconds and 14.642 W versus the default's
  1.351 seconds and 33.607 W. Its KKT factor has 1,137,839 nonzeros, versus 534,132
  for linear32: a smaller requested clique setting can create more fill.
- Kim32 on LV t500/t1000 gives 0.666/0.602 seconds and differences of 85.832/353.690 W.
  Iterations drop from 81/73 to 72/68, but the absolute timing gains are small.
  Kim12 returns `ALMOST_OPTIMAL` on all six LV runs and remains unsuitable as a
  general default. It is not accepted merely because it finishes quickly.

On 96 buses, Kim32's approximately 0.02 W worse primal objective difference is
smaller than its roughly 0.10 W conic gap. Do not interpret such differences as
meaningful changes in relaxation strength.

## Sparse-coordinate Kim follow-up

A separate serial three-repeat sweep adds eight fixed Kim triplets to sparse
coordinates, with the same tolerances. The 32 and 12 settings still produce the
same dense layout on the two small-state cases.

| Case | Sparse linear s / difference W | Sparse Kim32_8 s / difference W | Default linear s / difference W |
|:--|--:|--:|--:|
| ENWL 24 buses | 0.875 / 25.462 | 1.358 / 3.092 | 16.907 / 0.104 |
| ENWL 45 buses | 2.215 / 57.434 | 2.917 / 16.480 | 58.371 / 20.697 |

Sparse Kim closes about 88% and 71% of the sparse-linear objective difference on
these two cases. On 24 buses it remains weaker than the default, but is about
12× faster with a 0.07682% difference from NLP. On 45 buses it is about 20× faster
and has a smaller objective difference (0.56016%). This is the leading **balanced
profile candidate**, rather than a reason to discard the stronger reference.

On 96 buses and both LV snapshots, explicit sparse Kim32 reproduces the main
Kim32 model and objective. All fifteen sparse-Kim32 runs are accepted. Sparse
Kim12 again fails acceptance on both LV snapshots (six `ALMOST_OPTIMAL` outcomes).
Therefore retain 32 as the general setting and 12 as a case-specific option.

The change of coordinates means the two SOC feasible regions are not generally
nested. A better bound on 45 buses is possible without an equivalent encoding.
These measurements justify validation of an explicit profile; they do not establish
a universal domination theorem.

See the [follow-up report](https://github.com/frederikgeth/FormulationLab.jl/blob/main/examples/results/soc_sparse_strengthening_2026-09-11.md)
and [raw results](https://github.com/frederikgeth/FormulationLab.jl/blob/main/examples/results/soc_sparse_strengthening_2026-09-11.json).

## Measurement protocol

The reproducible harness is `examples/benchmark_soc_controlled.jl`. It records
Clarabel's internal solve timer, KKT update and solve timers, setup, extraction,
actual matrix sparsity, cone inventory, accepted status, objective differences,
and first-repeat reconstructed KCL residuals. Each measurement uses a fresh
solver instance and default start. Three serial repeats rotate profile order;
the input preparation and models are reused. The follow-up harness tests fixed
Kim strengthening in sparse coordinates. No library defaults are changed.

The recorded native time excludes setup and state extraction. KKT update time includes matrix updates, refactorization and a constant-RHS solve;
the separate KKT solve timer covers predictor/corrector solves. Both can include
iterative refinement; the current solver does not separately expose its
iteration count or elapsed time. We do not infer refinement counts from barrier
iterations. Repeats in one process establish repeatability on this machine, not
confidence intervals across machines or solver versions.

## Interpretation boundaries

Changing a basis changes a finite SOC relaxation. The sparse-basis comparison
is therefore a speed–strength trade-off, not evidence of an equivalent faster
encoding. The dense physical-coordinate path currently uses an SVD nullspace
and pivoted coordinate selection; sparse coordinates come from sparse QR. The
small-dimension switch in `_sdp_basis` and the full-span dense fallback in
`_sdp_sparse_moment` explain why requested clique size alone is a poor policy.
No small coefficient was dropped in this study.

Recovered-state diagnostics remain material. The first-repeat maximum KCL
residuals for default / sparse-linear / sparse-Kim32 are approximately
25 / 85 / 21 A on 24 buses and 340 / 15 / 392 A on 45 buses. Better objective
agreement can accompany worse recovery. None of these points is an AC-feasible
dispatch; keep the full diagnostics, and assess any future AC correction separately.

A small conic primal–dual gap is different from the NLP–SOC objective difference,
and neither implies a good reconstructed AC state. All physical-state comparisons
must retain KCL residuals. First-repeat recovery is a diagnostic, outside the
native solve timer, and is not repeated as an independent statistical experiment.

## Static coefficient inspection

The no-solve census in `examples/profile_soc_coefficients.jl` inspects stored
JuMP affine constraint coefficients after formulation preprocessing, before MOI
bridging or Clarabel equilibration. It excludes constants and objective terms.
It neither removes coefficients nor uses a solution.

| Case / basis | Stored nonzero coefficients | Magnitude below 1e-14 | Magnitude below 1e-12 |
|:--|--:|--:|--:|
| 24 buses / default physical | 1,006,921 | 856,387 (85.1%) | 868,087 (86.2%) |
| 24 buses / sparse | 240,375 | 7,161 (3.0%) | 12,992 (5.4%) |
| 45 buses / default physical | 2,015,067 | 1,402,343 (69.6%) | 1,431,103 (71.0%) |
| 45 buses / sparse | 519,013 | 22,355 (4.3%) | 35,531 (6.8%) |

These are pre-bridge counts, so they differ slightly from the native matrix
counts above. Largest coefficient magnitudes are approximately 2 in the physical
basis and 1.5 in the sparse basis. The concentration of tiny coefficients supports
investigating numerical fill from elimination; it does **not** prove every tiny
coefficient is mathematically zero or safe to discard. In particular, grounding
and multivoltage scaling can produce physically meaningful small coefficients.

[Raw coefficient census](https://github.com/frederikgeth/FormulationLab.jl/blob/main/examples/results/soc_coefficient_census_2026-09-11.json).
Reproduce with `julia --project=test/integration examples/profile_soc_coefficients.jl OUTPUT.json`.

## Implementation plan

The measured priorities are:

1. **Validate explicit fast and balanced coordinate profiles.** The fast
   candidate is sparse32 with linear cuts; balanced adds eight Kim triplets.
   Retain the existing physical-coordinate option as a comparator, without
   claiming a universal ordering of strength. Preserve explicit basis
   and cut metadata. Before changing defaults, run existing AC-containment and
   transformer fixtures in both bases and extend the benchmark panel. A structural
   selector may use support sizes and symbolic fill estimates; it must not use an
   incumbent, the reference NLP solution, or a feeder-name lookup.
2. **Preserve structural zeros in the physical-coordinate representation.**
   Reconstruct the elimination using the same independent physical coordinates
   but sparse electrical solves, then propagate analytically known zeros through
   the physical maps. Compare physical product maps and AC containment against
   the existing basis before benchmarking. This could retain much of the
   existing bound strength while avoiding numerical fill; it is not yet tested.
   If exact structure cannot recover enough sparsity, investigate an explicitly
   approximate coefficient-removal mode with finite variable/moment bounds and
   a computed row-error budget. Relax affected rows by that budget when an outer
   guarantee is required. Refuse unbounded-error removals; a blanket 1e-14 cutoff
   is not a validity argument.
3. **Strengthen sparse coordinates selectively.** The eight-triplet Kim
   follow-up is already useful on the small-state cases. Compare budgets 0, 2,
   4 and 8, and a bounded set of physical voltage or winding-current pair
   projections, selected before solving from component structure and valid
   bounds. Compare marginal objective improvement with added factor nonzeros
   and native time. Keep power cones and fixed taps.
4. **Reduce factorization cost without weakening the model.** Benchmark another
   available linear-solver backend and alternative equivalent sparse encodings on
   the same matrices/constraints. Clarabel.jl includes a CHOLMOD option locally;
   any Julia-specific result needs a separate Rust/WASM portability assessment.
   Do not promise a speedup before measuring it.
5. **Defer broad numerical retuning until justified by the residuals.** A smaller
   refinement budget is useful only if it reduces time without losing accepted
   status or accuracy. Relaxed tolerances must be labeled separately and checked
   in physical watt units. No objective regularizer is silently added.

Acceptance for a proposed default requires all runs to complete at the intended
status and tolerance, a reproducible native-time improvement, documented objective
and state trade-offs, unchanged component semantics, and rank-one AC containment
checks. These five cases are a screening panel, not a universal performance claim.

## Proposed delivery sequence

Implemented in the subsequent [SOC profiles and structural sparsity](soc_profiles.md)
work: named presets, guarded structural physical elimination, updated small-state
automatic selection, containment tests, fixed-budget and backend comparisons.
The historical recommendations below explain the starting point.

First add documented fast and balanced profile constructors and retain all raw
options. Validate both against rank-one AC points and the existing transformer,
neutral, load and bound tests; run the larger ENWL panel to detect regressions.
The candidate settings are already expressible today:

```julia
fast = IVRSOC(basis=:sparse, strengthening=:linear, clique_size=32)
balanced = IVRSOC(basis=:sparse, strengthening=:kim,
                  max_triplets=8, clique_size=32)
```

Next preserve structural zeros in the physical-coordinate compiler and benchmark
fixed triplet budgets and equivalent sparse representations with
native timing and objective/state diagnostics. Use the present matrix/factor
nonzero counts as regression metrics. Test an alternative factorization backend
separately, preserving the conic model, and evaluate Rust/WASM support before
making it part of a portable profile. Leave automatic profile selection until
these choices have evidence across the wider component and network panel.

This pass adds experiments and documentation only. It does not implement a new
profile selector, remove coefficients, alter the objective, change stopping
tolerances, or add incumbent-dependent cuts.
