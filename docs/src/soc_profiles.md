# SOC profiles and structural sparsity

The implementation following the [controlled comparison](soc_performance_plan.md)
adds named profiles and a sparsity-preserving physical basis. The latter is now
used by automatic basis selection for at most 32 independent coordinates, in both
SOC and SDP. Larger automatic models retain the existing sparse-QR path.

```julia
using FormulationLab, Clarabel

recommended = IVRSOC()  # automatic structural physical / sparse basis
fast = IVRSOC(profile=:fast)
balanced = IVRSOC(profile=:balanced)
legacy = IVRSOC(basis=:physical)  # previous SVD-based physical representation

# Explicit options override a preset.
custom = IVRSOC(profile=:balanced, max_triplets=4, clique_size=12)
# The basis can also be selected independently, including for SDP.
sdp = IVRSDP(basis=:physical_sparse)
```

| Public profile | Electrical profile | Basis | Strengthening | Kim budget | Requested clique size |
|:--|:--|:--|:--|--:|--:|
| `:clarabel` (default) | `:clarabel` | `:auto` | `:linear` | 16, unused unless Kim selected | 32 |
| `:fast` | `:clarabel` | `:sparse` | `:linear` | 16, unused unless Kim selected | 32 |
| `:balanced` | `:clarabel` | `:sparse` | `:kim` | 8 | 32 |
| `:reference` | `:reference` | inherited orthonormal basis | `:linear` | 16, unused unless Kim selected | 32 |

Profile names describe configurations, not a universal ordering of speed or
strength. In particular, the new automatic physical basis can be substantially
faster than the profile called `:fast`. Explicit keyword overrides can change the
configuration; inspect resolved options rather than relying on the preset label.
The old `profile=:reference` meaning remains compatible. For direct `SOCOptions`
construction, `profile` is a provenance label; `IVRSOC` resolves the presets.

Profiles preserve component equations, bounds, taps, load power cones, reduction
policy and recovery policy. Solver factories and tolerances remain separately
configurable. Every model uses fixed constraints selected before solving.

## Physical coordinates with sparse electrical solves

Start with the same row-equilibrated electrical matrix ``A`` and the same physical
coordinate selection as the legacy basis. An SVD gives a nullspace basis; pivoted
QR selects independent physical state indices ``F``. These indices, and their
order, are retained. Partition the state into free coordinates ``z_F=y`` and
dependent coordinates ``z_D``. The desired basis satisfies

```math
N_F=I,\qquad A_D N_D=-A_F.
```

Instead of forming the physical basis by a dense change of coordinates, the new
path solves this electrical system with sparse QR. Dependent columns connected
through a common nonzero row form a component. Distinct components are solved
separately. A free-coordinate column with no forcing in a component has an exactly
zero response there, so that column is never allocated a computed response.
Zeros also survive sparse factorization where the elimination preserves them.
No magnitude threshold removes a coefficient, changes a limit or deletes a device.
A regression test explicitly retains a genuine coefficient of magnitude ``10^{-16}``.

The result is compared with the legacy physical basis and checked against ``AN=0``.
Dependent-column rank disagreement falls back to the legacy representation. A
relative basis difference above `1e-8`, a relative electrical residual above
`1e-10`, or nonfinite diagnostics also causes fallback. These are numerical
checks, not interval certificates or coefficient-removal tolerances. They do not
replace the independent AC containment tests.

For a full PSD lift, retaining the same independent coordinates preserves the
intended physical moment maps. A finite SOC model is more numerically sensitive:
near-zero maps and constraint scaling can affect its strength and solver behavior.
Therefore compare objective values, conic residuals and AC containment rather than
claiming that every floating-point conic matrix is identical to the old encoding.

## Diagnostics

`build.electrical.numerical_diagnostics` on SOC builds, and
`build.numerical_diagnostics` on SDP builds, expose:

- `basis`: the selected basis algorithm; automatic small models report `:physical_sparse`.
- `basis_structural_components` and `basis_rhs_columns`: structural solve work.
- `basis_map_difference` and `basis_relative_residual`: numerical agreement checks,
  when the component solves completed.
- `basis_fallback` and `basis_fallback_reason`: whether the legacy result was retained.
- `soc_profile` and `soc_options`: the requested preset label and resolved SOC
  settings, also copied into result numerical metadata.

A fallback keeps the old physical coordinates and may lose the sparsity benefit.
Large models using the automatic sparse-QR path have no physical-basis fallback
fields. `basis=:physical` remains available for reproducibility and diagnosis.

## Validation and numerical evidence

The test suite covers the fast and balanced presets and the new basis with
independent forward/reverse transformer states at multiple power bases, rotated
phasors, coupled multiwinding delta connections, grounding, inverter filters,
voltage-dependent loads, shunts, capacitors and existing component regressions.
Numerical experiments use the same fixed-input protocol as the earlier study:
source-bus generators removed, fixed taps, one BLAS thread, matched per-unit bases,
and three cold-solver repeats on the five-case comparison panel.

The implementation study and wider-panel results are recorded alongside their
reproduction scripts in `examples/results`. Conic objective agreement does not
certify a recovered AC dispatch. Continue to inspect reconstruction residuals and
unassessed quantities; no new AC-feasible recovery algorithm is introduced here.

### Implementation sweep

| Case | Earlier default native s | Explicit `:physical_sparse` native s | NLP − new SOC W |
|:--|--:|--:|--:|
| ENWL 24 buses | 16.907 | 0.0405 | 0.1035 |
| ENWL 45 buses | 58.371 | 0.5091 | 20.7139 |
| ENWL 96 buses | 1.351 | 0.7380 | 33.6638 |
| Reduced LV t500 | 0.715 | 0.6284 | 71.4327 |
| Reduced LV t1000 | 0.612 | 0.4868 | 355.8459 |

New times are medians of three runs; earlier times come from the preceding
controlled batch on the same machine and tolerances. All fifteen explicit
physical-sparse runs returned `OPTIMAL`, without fallback. On 24/45 buses the
relative basis-map differences were about `1.2e-14`/`3.9e-14`, and constraint-matrix
nonzeros fell from about 1.01/2.02 million to 30,044/268,815. The new default uses
this path on those small-state cases. The 96-bus and LV rows above are **explicit
opt-in basis comparisons**, not the new automatic choice on larger states.

Retaining the larger automatic sparse-QR path is deliberate. Explicit physical
coordinates change the local SOC representation and can make recovery much worse:
the 96-bus physical-sparse run has a maximum reconstructed KCL residual around
7,751 A. The native-time improvement alone does not justify a blanket switch.
Even on 24/45 buses, residuals remain about 27/125 A; these are not feasible AC
states. Full residuals are recorded in the study.

Kim budgets 2 and 4 were also tested. Four triplets returned `ALMOST_OPTIMAL` on
all three 45-bus runs; two triplets were accepted but are not uniformly stronger
or faster across the panel. Primal objective differences were not consistently
monotone with cut budget, highlighting numerical sensitivity rather than a theorem
that fewer cuts are stronger. The balanced preset retains eight. CHOLMOD was
slower than QDLDL on all five balanced-profile comparisons, so it remains an
explicit optimizer option, with no change to the default backend.

A separate 24-bus audit checks that the two-triplet selection is a prefix of the
eight-triplet selection and that both use the same electrical basis. Evaluating
the eight-triplet point in the two-triplet model gives a largest constraint
violation of `9.3e-8`, despite an objective about 1.02 W below the two-triplet
solver result. This supports numerical sensitivity as the explanation; it is
not an exact feasibility or optimality certificate. Reproduce with
`examples/audit_soc_budget_numerics.jl OUTPUT.json`; the
[audit data](https://github.com/frederikgeth/FormulationLab.jl/blob/main/examples/results/soc_budget_numerics_2026-09-11.json)
includes residuals and the worst constraints.

[Implementation report](https://github.com/frederikgeth/FormulationLab.jl/blob/main/examples/results/soc_profiles_2026-09-11.md)
and [raw data](https://github.com/frederikgeth/FormulationLab.jl/blob/main/examples/results/soc_profiles_2026-09-11.json).
Reproduce with:

```sh
julia --project=test/integration examples/benchmark_soc_profiles.jl examples/results/soc_profiles_2026-09-11.json 3
python3 examples/summarize_soc_profiles.py
```

The wider ENWL screen uses `examples/run_soc_profile_panel.py`. It runs the nine
sampled cases up to 140 buses in one serial process, and attempts each named
profile separately on the 178-, 241- and 538-bus cases with a 120-second external
process budget. That budget includes startup and model construction. A timeout
there is a process-budget outcome, not a Clarabel solver failure or an applicability
rejection. This screen is one run per profile, not repeated timing evidence.

The completed screen accepted 21 of 27 solves: all three profiles returned
`OPTIMAL` on seven of the nine cases. All three returned `ALMOST_OPTIMAL` on
54 and 77 buses, so their objectives were excluded. All six larger-case attempts
exhausted the process budget during construction; they provide no Clarabel solve
time or objective comparison. These unresolved cases limit any claim of general
robustness.

[Wider-panel report](https://github.com/frederikgeth/FormulationLab.jl/blob/main/examples/results/soc_profiles_panel_2026-09-11.md)
records every completed solve and external-budget outcome.
