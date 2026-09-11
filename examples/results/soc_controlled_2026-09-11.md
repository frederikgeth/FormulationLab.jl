# Controlled Clarabel SOC comparison

Evidence baseline: `cdeefe933e8f7cb62891feb31e5f36be094c935f`. Julia 1.12.6, Clarabel 0.11.1, apple-m4, 1 BLAS thread, 3 serial repeats.

Fresh solver setup and default starts on every run; model construction is reused. Profile order rotates between repeats. Small-case warm-up precedes measurements. Native solve time is Clarabel's internal `solve!` timer; setup, JuMP/MOI attachment, result extraction and original-network reconstruction are excluded. KKT update time includes matrix updates, refactorization and the constant-RHS solve; the separate KKT solve timer covers predictor/corrector solves. Both can include iterative refinement, which is not separately instrumented.

All variants use fixed SOC/power cones, the same source-import objective, fixed taps, source-bus generator removal, BMOPFTools-compatible reduction and per-unit preparation. Tolerances: feasibility 1e-7, absolute gap 1e-6, relative gap 1e-7. Static regularization is 1e-7 and refinement limit 30 except `refine5`. Every solve is capped at 90 seconds. No incumbent-dependent strengthening is used.

Objective differences use the freshly evaluated reduced-network BMOPFTools/Ipopt local solution, not a global optimum. Accepted rows require the package's publishable status. Raw values and residuals remain in the JSON, including failures.

## network_9_Feeder_4.json

Buses: 24 → 24. Per-phase base: 8000.000000 VA. Original NLP: LOCALLY_SOLVED; reduced NLP: LOCALLY_SOLVED.

| Profile | Accepted / runs | Native median s [min, max] | Iterations | KKT update s | KKT solve s | NLP − SOC W |
|:--|--:|--:|--:|--:|--:|--:|
| linear32 | 3/3 | 16.907 [16.903, 17.597] | 33 | 15.824 | 0.566 | 0.104 |
| physical32 | 3/3 | 19.167 [18.190, 20.395] | 37 | 18.016 | 0.619 | 0.104 |
| kim32_8 | 3/3 | 30.953 [30.915, 31.992] | 41 | 29.318 | 0.845 | 0.066 |
| kim12_8 | 3/3 | 30.946 [30.728, 31.300] | 41 | 29.301 | 0.843 | 0.066 |
| sparse_basis32 | 3/3 | 0.875 [0.867, 0.892] | 20 | 0.746 | 0.080 | 25.462 |
| refine5 | 3/3 | 17.505 [17.323, 18.342] | 33 | 16.376 | 0.565 | 0.104 |

| Profile | Actual layout / basis | Moment block orders | Variables | nnz(A) | nnz(KKT L) | Extraction median s |
|:--|:--|:--|--:|--:|--:|--:|
| linear32 | dense / physical | 28×1 | 1640 | 1008105 | 2446244 | 0.093 |
| physical32 | dense / physical | 28×1 | 1640 | 991641 | 2429780 | 0.094 |
| kim32_8 | dense / physical | 28×1 | 1928 | 1234617 | 3124844 | 0.094 |
| kim12_8 | dense / physical | 28×1 | 1928 | 1234617 | 3124844 | 0.093 |
| sparse_basis32 | dense / sparse | 28×1 | 1304 | 241391 | 399609 | 0.010 |
| refine5 | dense / physical | 28×1 | 1640 | 1008105 | 2446244 | 0.094 |

## network_18_Feeder_6.json

Buses: 45 → 45. Per-phase base: 8000.000000 VA. Original NLP: LOCALLY_SOLVED; reduced NLP: LOCALLY_SOLVED.

| Profile | Accepted / runs | Native median s [min, max] | Iterations | KKT update s | KKT solve s | NLP − SOC W |
|:--|--:|--:|--:|--:|--:|--:|
| linear32 | 3/3 | 58.371 [56.164, 64.228] | 45 | 55.675 | 1.284 | 20.697 |
| physical32 | 3/3 | 57.275 [56.775, 59.384] | 44 | 54.641 | 1.284 | 20.746 |
| kim32_8 | 3/3 | 77.581 [76.041, 84.128] | 48 | 74.188 | 1.667 | 10.188 |
| kim12_8 | 3/3 | 78.350 [76.101, 81.335] | 48 | 74.934 | 1.665 | 10.188 |
| sparse_basis32 | 3/3 | 2.215 [2.166, 2.250] | 25 | 1.918 | 0.194 | 57.434 |
| refine5 | 3/3 | 59.848 [59.762, 61.944] | 45 | 57.092 | 1.285 | 20.697 |

| Profile | Actual layout / basis | Moment block orders | Variables | nnz(A) | nnz(KKT L) | Extraction median s |
|:--|:--|:--|--:|--:|--:|--:|
| linear32 | dense / physical | 29×1 | 2373 | 2016645 | 4682117 | 0.194 |
| physical32 | dense / physical | 29×1 | 2373 | 1998143 | 4663615 | 0.194 |
| kim32_8 | dense / physical | 29×1 | 2661 | 2259572 | 5409962 | 0.194 |
| kim12_8 | dense / physical | 29×1 | 2661 | 2259572 | 5409962 | 0.196 |
| sparse_basis32 | dense / sparse | 29×1 | 1781 | 520295 | 699572 | 0.023 |
| refine5 | dense / physical | 29×1 | 2373 | 2016645 | 4682117 | 0.192 |

## network_18_Feeder_9.json

Buses: 96 → 96. Per-phase base: 17594.105263 VA. Original NLP: LOCALLY_SOLVED; reduced NLP: LOCALLY_SOLVED.

| Profile | Accepted / runs | Native median s [min, max] | Iterations | KKT update s | KKT solve s | NLP − SOC W |
|:--|--:|--:|--:|--:|--:|--:|
| linear32 | 3/3 | 1.351 [1.350, 1.365] | 64 | 1.028 | 0.249 | 33.607 |
| physical32 | 3/3 | 1.301 [1.300, 1.309] | 62 | 0.991 | 0.238 | 33.842 |
| kim32_8 | 3/3 | 1.424 [1.423, 1.447] | 65 | 1.086 | 0.261 | 33.627 |
| kim12_8 | 3/3 | 3.131 [3.120, 3.183] | 63 | 2.374 | 0.576 | 14.642 |
| sparse_basis32 | 3/3 | 1.355 [1.352, 1.355] | 64 | 1.031 | 0.250 | 33.607 |
| refine5 | 3/3 | 1.349 [1.347, 1.367] | 64 | 1.028 | 0.249 | 33.607 |

| Profile | Actual layout / basis | Moment block orders | Variables | nnz(A) | nnz(KKT L) | Extraction median s |
|:--|:--|:--|--:|--:|--:|--:|
| linear32 | chordal / sparse | 5×1, 6×17, 7×12, 8×7, 9×4, 10×2, 11×3 | 4688 | 289779 | 534132 | 0.057 |
| physical32 | chordal / sparse | 5×1, 6×17, 7×12, 8×7, 9×4, 10×2, 11×3 | 4688 | 287551 | 531736 | 0.056 |
| kim32_8 | chordal / sparse | 5×1, 6×17, 7×12, 8×7, 9×4, 10×2, 11×3 | 4976 | 305432 | 551803 | 0.056 |
| kim12_8 | chordal / sparse | 4×14, 5×120, 6×81, 7×48, 8×36, 9×5, 10×5, 11×1 | 14238 | 317449 | 1137839 | 0.027 |
| sparse_basis32 | chordal / sparse | 5×1, 6×17, 7×12, 8×7, 9×4, 10×2, 11×3 | 4688 | 289779 | 534132 | 0.057 |
| refine5 | chordal / sparse | 5×1, 6×17, 7×12, 8×7, 9×4, 10×2, 11×3 | 4688 | 289779 | 534132 | 0.057 |

## lvtestcase/snapshots/lvtestcase_pmd_t500.dss

Buses: 907 → 118. Per-phase base: 7805.964912 VA. Original NLP: LOCALLY_SOLVED; reduced NLP: LOCALLY_SOLVED.

| Profile | Accepted / runs | Native median s [min, max] | Iterations | KKT update s | KKT solve s | NLP − SOC W |
|:--|--:|--:|--:|--:|--:|--:|
| linear32 | 3/3 | 0.715 [0.713, 0.746] | 81 | 0.494 | 0.170 | 86.219 |
| physical32 | 3/3 | 0.705 [0.695, 0.717] | 81 | 0.487 | 0.167 | 86.219 |
| kim32_8 | 3/3 | 0.666 [0.666, 0.673] | 72 | 0.459 | 0.159 | 85.832 |
| kim12_8 | 0/3 | 0.703 [0.699, 0.707] | 63 | 0.432 | 0.199 | — |
| sparse_basis32 | 3/3 | 0.710 [0.699, 0.714] | 81 | 0.490 | 0.168 | 86.219 |
| refine5 | 3/3 | 0.710 [0.708, 0.723] | 81 | 0.490 | 0.168 | 86.219 |

| Profile | Actual layout / basis | Moment block orders | Variables | nnz(A) | nnz(KKT L) | Extraction median s |
|:--|:--|:--|--:|--:|--:|--:|
| linear32 | chordal / sparse | 4×1, 5×25, 7×12, 8×4, 9×2, 10×1 | 3463 | 129368 | 246920 | 0.031 |
| physical32 | chordal / sparse | 4×1, 5×25, 7×12, 8×4, 9×2, 10×1 | 3463 | 129368 | 246920 | 0.030 |
| kim32_8 | chordal / sparse | 4×1, 5×25, 7×12, 8×4, 9×2, 10×1 | 3751 | 138524 | 258074 | 0.030 |
| kim12_8 | chordal / sparse | 1×1, 3×2, 4×74, 5×42, 6×30, 7×25, 9×3 | 6805 | 110030 | 316369 | 0.000 |
| sparse_basis32 | chordal / sparse | 4×1, 5×25, 7×12, 8×4, 9×2, 10×1 | 3463 | 129368 | 246920 | 0.030 |
| refine5 | chordal / sparse | 4×1, 5×25, 7×12, 8×4, 9×2, 10×1 | 3463 | 129368 | 246920 | 0.030 |

## lvtestcase/snapshots/lvtestcase_pmd_t1000.dss

Buses: 907 → 118. Per-phase base: 16861.403509 VA. Original NLP: LOCALLY_SOLVED; reduced NLP: LOCALLY_SOLVED.

| Profile | Accepted / runs | Native median s [min, max] | Iterations | KKT update s | KKT solve s | NLP − SOC W |
|:--|--:|--:|--:|--:|--:|--:|
| linear32 | 3/3 | 0.612 [0.611, 0.612] | 73 | 0.416 | 0.150 | 355.879 |
| physical32 | 3/3 | 0.611 [0.609, 0.616] | 73 | 0.415 | 0.150 | 355.879 |
| kim32_8 | 3/3 | 0.602 [0.597, 0.612] | 68 | 0.409 | 0.147 | 353.690 |
| kim12_8 | 0/3 | 0.624 [0.623, 0.624] | 54 | 0.382 | 0.180 | — |
| sparse_basis32 | 3/3 | 0.609 [0.608, 0.617] | 73 | 0.415 | 0.149 | 355.879 |
| refine5 | 3/3 | 0.636 [0.608, 0.643] | 73 | 0.437 | 0.150 | 355.879 |

| Profile | Actual layout / basis | Moment block orders | Variables | nnz(A) | nnz(KKT L) | Extraction median s |
|:--|:--|:--|--:|--:|--:|--:|
| linear32 | chordal / sparse | 4×1, 5×25, 7×12, 8×4, 9×2, 10×1 | 3463 | 127177 | 242544 | 0.030 |
| physical32 | chordal / sparse | 4×1, 5×25, 7×12, 8×4, 9×2, 10×1 | 3463 | 127177 | 242544 | 0.030 |
| kim32_8 | chordal / sparse | 4×1, 5×25, 7×12, 8×4, 9×2, 10×1 | 3751 | 137577 | 253514 | 0.031 |
| kim12_8 | chordal / sparse | 1×1, 3×2, 4×74, 5×42, 6×30, 7×25, 9×3 | 6805 | 113802 | 320719 | 0.000 |
| sparse_basis32 | chordal / sparse | 4×1, 5×25, 7×12, 8×4, 9×2, 10×1 | 3463 | 127177 | 242544 | 0.031 |
| refine5 | chordal / sparse | 4×1, 5×25, 7×12, 8×4, 9×2, 10×1 | 3463 | 127177 | 242544 | 0.032 |

## Reproduction

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test/integration --startup-file=no \
  examples/benchmark_soc_controlled.jl examples/results/soc_controlled_2026-09-11.json 3
python3 examples/summarize_soc_controlled.py examples/results/soc_controlled_2026-09-11.json
```

Raw data: [soc_controlled_2026-09-11.json](soc_controlled_2026-09-11.json).
Input paths/hashes, preparation changes, model layouts, internal timers, residuals, cone inventory, per-run outcomes and first-repeat reconstruction checks are in the raw data.
