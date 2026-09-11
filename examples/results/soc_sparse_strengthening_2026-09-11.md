# Controlled Clarabel SOC comparison

Evidence baseline: `cdeefe933e8f7cb62891feb31e5f36be094c935f`. Julia 1.12.6, Clarabel 0.11.1, apple-m4, 1 BLAS thread, 3 serial repeats.

Fresh solver setup and default starts on every run; model construction is reused. Profile order rotates between repeats. Small-case warm-up precedes measurements. Native solve time is Clarabel's internal `solve!` timer; setup, JuMP/MOI attachment, result extraction and original-network reconstruction are excluded. KKT update time includes matrix updates, refactorization and the constant-RHS solve; the separate KKT solve timer covers predictor/corrector solves. Both can include iterative refinement, which is not separately instrumented.

All variants use fixed SOC/power cones, the same source-import objective, fixed taps, source-bus generator removal, BMOPFTools-compatible reduction and per-unit preparation. Tolerances: feasibility 1e-7, absolute gap 1e-6, relative gap 1e-7. Static regularization is 1e-7 and refinement limit 30 except `refine5`. Every solve is capped at 90 seconds. No incumbent-dependent strengthening is used.

Objective differences use the freshly evaluated reduced-network BMOPFTools/Ipopt local solution, not a global optimum. Accepted rows require the package's publishable status. Raw values and residuals remain in the JSON, including failures.

## network_9_Feeder_4.json

Buses: 24 → 24. Per-phase base: 8000.000000 VA. Original NLP: LOCALLY_SOLVED; reduced NLP: LOCALLY_SOLVED.

| Profile | Accepted / runs | Native median s [min, max] | Iterations | KKT update s | KKT solve s | NLP − SOC W |
|:--|--:|--:|--:|--:|--:|--:|
| sparse_kim32_8 | 3/3 | 1.358 [1.351, 1.365] | 23 | 1.188 | 0.101 | 3.092 |
| sparse_kim12_8 | 3/3 | 1.360 [1.354, 1.365] | 23 | 1.188 | 0.101 | 3.092 |

| Profile | Actual layout / basis | Moment block orders | Variables | nnz(A) | nnz(KKT L) | Extraction median s |
|:--|:--|:--|--:|--:|--:|--:|
| sparse_kim32_8 | dense / sparse | 28×1 | 1592 | 364222 | 537626 | 0.009 |
| sparse_kim12_8 | dense / sparse | 28×1 | 1592 | 364222 | 537626 | 0.009 |

## network_18_Feeder_6.json

Buses: 45 → 45. Per-phase base: 8000.000000 VA. Original NLP: LOCALLY_SOLVED; reduced NLP: LOCALLY_SOLVED.

| Profile | Accepted / runs | Native median s [min, max] | Iterations | KKT update s | KKT solve s | NLP − SOC W |
|:--|--:|--:|--:|--:|--:|--:|
| sparse_kim32_8 | 3/3 | 2.917 [2.892, 2.970] | 28 | 2.594 | 0.197 | 16.480 |
| sparse_kim12_8 | 3/3 | 2.910 [2.902, 2.926] | 28 | 2.585 | 0.197 | 16.480 |

| Profile | Actual layout / basis | Moment block orders | Variables | nnz(A) | nnz(KKT L) | Extraction median s |
|:--|:--|:--|--:|--:|--:|--:|
| sparse_kim32_8 | dense / sparse | 29×1 | 2069 | 658487 | 851453 | 0.023 |
| sparse_kim12_8 | dense / sparse | 29×1 | 2069 | 658487 | 851453 | 0.023 |

## network_18_Feeder_9.json

Buses: 96 → 96. Per-phase base: 17594.105263 VA. Original NLP: LOCALLY_SOLVED; reduced NLP: LOCALLY_SOLVED.

| Profile | Accepted / runs | Native median s [min, max] | Iterations | KKT update s | KKT solve s | NLP − SOC W |
|:--|--:|--:|--:|--:|--:|--:|
| sparse_kim32_8 | 3/3 | 1.428 [1.426, 1.442] | 65 | 1.087 | 0.263 | 33.627 |
| sparse_kim12_8 | 3/3 | 3.160 [3.158, 3.160] | 63 | 2.395 | 0.581 | 14.642 |

| Profile | Actual layout / basis | Moment block orders | Variables | nnz(A) | nnz(KKT L) | Extraction median s |
|:--|:--|:--|--:|--:|--:|--:|
| sparse_kim32_8 | chordal / sparse | 5×1, 6×17, 7×12, 8×7, 9×4, 10×2, 11×3 | 4976 | 305432 | 551803 | 0.059 |
| sparse_kim12_8 | chordal / sparse | 4×14, 5×120, 6×81, 7×48, 8×36, 9×5, 10×5, 11×1 | 14238 | 317449 | 1137839 | 0.028 |

## lvtestcase/snapshots/lvtestcase_pmd_t500.dss

Buses: 907 → 118. Per-phase base: 7805.964912 VA. Original NLP: LOCALLY_SOLVED; reduced NLP: LOCALLY_SOLVED.

| Profile | Accepted / runs | Native median s [min, max] | Iterations | KKT update s | KKT solve s | NLP − SOC W |
|:--|--:|--:|--:|--:|--:|--:|
| sparse_kim32_8 | 3/3 | 0.666 [0.665, 0.668] | 72 | 0.460 | 0.157 | 85.832 |
| sparse_kim12_8 | 0/3 | 0.694 [0.693, 0.697] | 63 | 0.425 | 0.199 | — |

| Profile | Actual layout / basis | Moment block orders | Variables | nnz(A) | nnz(KKT L) | Extraction median s |
|:--|:--|:--|--:|--:|--:|--:|
| sparse_kim32_8 | chordal / sparse | 4×1, 5×25, 7×12, 8×4, 9×2, 10×1 | 3751 | 138524 | 258074 | 0.030 |
| sparse_kim12_8 | chordal / sparse | 1×1, 3×2, 4×74, 5×42, 6×30, 7×25, 9×3 | 6805 | 110030 | 316369 | 0.000 |

## lvtestcase/snapshots/lvtestcase_pmd_t1000.dss

Buses: 907 → 118. Per-phase base: 16861.403509 VA. Original NLP: LOCALLY_SOLVED; reduced NLP: LOCALLY_SOLVED.

| Profile | Accepted / runs | Native median s [min, max] | Iterations | KKT update s | KKT solve s | NLP − SOC W |
|:--|--:|--:|--:|--:|--:|--:|
| sparse_kim32_8 | 3/3 | 0.603 [0.598, 0.651] | 68 | 0.408 | 0.149 | 353.690 |
| sparse_kim12_8 | 0/3 | 0.623 [0.623, 0.626] | 54 | 0.382 | 0.181 | — |

| Profile | Actual layout / basis | Moment block orders | Variables | nnz(A) | nnz(KKT L) | Extraction median s |
|:--|:--|:--|--:|--:|--:|--:|
| sparse_kim32_8 | chordal / sparse | 4×1, 5×25, 7×12, 8×4, 9×2, 10×1 | 3751 | 137577 | 253514 | 0.029 |
| sparse_kim12_8 | chordal / sparse | 1×1, 3×2, 4×74, 5×42, 6×30, 7×25, 9×3 | 6805 | 113802 | 320719 | 0.000 |

## Reproduction

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test/integration --startup-file=no \
  examples/benchmark_soc_sparse_strengthening.jl examples/results/soc_sparse_strengthening_2026-09-11.json 3
python3 examples/summarize_soc_controlled.py examples/results/soc_sparse_strengthening_2026-09-11.json
```

Raw data: [soc_sparse_strengthening_2026-09-11.json](soc_sparse_strengthening_2026-09-11.json).
Input paths/hashes, preparation changes, model layouts, internal timers, residuals, cone inventory, per-run outcomes and first-repeat reconstruction checks are in the raw data.
