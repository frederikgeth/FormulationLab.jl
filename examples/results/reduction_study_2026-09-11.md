# Network reduction and fixed Clarabel SOC: 2026-09-11

BMOPFTools-compatible preparation reduces both 907-bus LV snapshots to 118 buses. With the default 32-coordinate clique-size setting and linear strengthening, Clarabel now returns OPTIMAL on both snapshots in approximately 14–15 seconds of model construction and solve time. The previous unreduced runs exceeded the 240-second process budget without a result. This is a budget comparison, not a precisely measured speedup.

## Protocol

Julia 1.12.6, Clarabel 0.11.1, Ipopt 1.16.0; one BLAS thread. All conic runs use SOC and any inherited load power cones, with an assertion rejecting semidefinite cones. One model, one solve: no iterative OA. Fixed taps, no control laws, source-bus generators removed, other generators retained; objective is net source active-power import. Per-unit base is max(total apparent nominal load, installed active generation, 3000 VA)/3. Clarabel tolerances are feasibility 1e-7, absolute gap 1e-6, relative gap 1e-7, with a 90-second solve limit. Warm-up is excluded; new component compilation can remain. Timings are single-run, indicative measurements; some verification processes ran concurrently. No claim is made about subsecond timing differences.

The NLP comparison uses BMOPFTools with Ipopt on both original and reduced inputs. NLP solutions are local optima, checked with BMOPFTools' solution checker. The objective difference below is NLP minus SOC in watts; percent divides by the absolute NLP net-import objective. Near-cancelling generation and demand can inflate this percentage (notably the 96-bus ENWL case). These are numerical comparisons, not certified gaps, especially after approximate circuit reduction. ALMOST_OPTIMAL and numerical failures remain visible and are excluded from accepted objective/state comparisons.

## Reducibility of the existing panel

| Case | Original buses | Reduced buses |
|---|---:|---:|
| ENWL 23_Feeder_3 | 5 | 5 |
| ENWL 9_Feeder_4 | 24 | 24 |
| ENWL 5_Feeder_6 | 36 | 36 |
| ENWL 18_Feeder_6 | 45 | 45 |
| ENWL 22_Feeder_4 | 54 | 54 |
| ENWL 13_Feeder_1 | 77 | 77 |
| ENWL 18_Feeder_9 | 96 | 96 |
| ENWL 19_Feeder_4 | 110 | 110 |
| ENWL 3_Feeder_2 | 140 | 140 |
| ENWL 13_Feeder_4 | 178 | 178 |
| ENWL 2_Feeder_4 | 241 | 241 |
| Network_8_Feeder_2 | 538 | 538 |
| ieee13/ieee13_pmd | 16 | 15 |
| ieee34/ieee34_pmd | 56 | 41 |
| ieee123/ieee123_pmd | 130 | 124 |
| cigre/CIGRE_test_case | 4 | 4 |
| LV t500 | 907 | 118 |
| LV t1000 | 907 | 118 |

Allowing intermediate bus-bound removal did not reduce these counts further. All 12 sampled ENWL inputs were already irreducible under the compatibility policy. IEEE13 and IEEE123 are topology scans only: their earlier conversion/missing-impedance problems were not repaired in this study.

For both LV snapshots, original and reduced NLP source objectives agree to the reported precision: 22,418.515509 W (t500) and 48,869.907839 W (t1000). No approximate-reduction events were applied there. The reduction implementation's π approximation is exercised by analytical tests; these LV results do not quantify π approximation error.

## Fixed-profile sweep

`linear32` is the existing default with clique_size=32; `linear12` uses 12. `physical12/32` removes fixed linear strengthening, retaining physical SOC projections. `kim12_8/kim32_8` enables eight data-selected triplets with the indicated clique size. The requested clique size need not change a model that selects a dense layout.

| Case | Profile | Status | Build s | Solve s | NLP − SOC W | Difference % |
|---|---|---|---:|---:|---:|---:|
| ENWL 23_Feeder_3 | linear32 | OPTIMAL | 0.018 | 0.006 | -0.000015 | -0.00000 |
| ENWL 23_Feeder_3 | linear12 | OPTIMAL | 0.019 | 0.006 | -0.000015 | -0.00000 |
| ENWL 23_Feeder_3 | physical12 | OPTIMAL | 0.018 | 0.005 | -0.000073 | -0.00000 |
| ENWL 23_Feeder_3 | kim12_8 | OPTIMAL | 0.026 | 0.012 | -0.000087 | -0.00001 |
| ENWL 9_Feeder_4 | linear32 | OPTIMAL | 0.517 | 16.125 | 0.103972 | 0.00258 |
| ENWL 9_Feeder_4 | linear12 | OPTIMAL | 0.479 | 15.842 | 0.103972 | 0.00258 |
| ENWL 9_Feeder_4 | physical12 | OPTIMAL | 0.452 | 16.102 | 0.104073 | 0.00259 |
| ENWL 9_Feeder_4 | kim12_8 | OPTIMAL | 0.532 | 24.031 | 0.066255 | 0.00165 |
| ENWL 18_Feeder_6 | linear32 | OPTIMAL | 1.155 | 44.455 | 20.697014 | 0.70348 |
| ENWL 18_Feeder_6 | linear12 | OPTIMAL | 0.961 | 43.797 | 20.697014 | 0.70348 |
| ENWL 18_Feeder_6 | physical12 | OPTIMAL | 0.933 | 43.531 | 20.745508 | 0.70512 |
| ENWL 18_Feeder_6 | kim12_8 | OPTIMAL | 1.068 | 59.117 | 10.188422 | 0.34630 |
| ENWL 18_Feeder_9 | linear32 | OPTIMAL | 15.601 | 1.780 | 33.607017 | 2.56632 |
| ENWL 18_Feeder_9 | linear12 | ALMOST_OPTIMAL | 15.144 | 3.817 | — | — |
| ENWL 18_Feeder_9 | physical12 | ALMOST_OPTIMAL | 15.035 | 3.610 | — | — |
| ENWL 18_Feeder_9 | kim12_8 | OPTIMAL | 14.808 | 3.221 | 14.642407 | 1.11813 |
| LV t500 | linear32 | OPTIMAL | 14.254 | 0.876 | 86.219280 | 0.38459 |
| LV t500 | linear12 | ALMOST_OPTIMAL | 15.290 | 0.644 | — | — |
| LV t500 | physical12 | ALMOST_OPTIMAL | 13.280 | 0.666 | — | — |
| LV t500 | kim12_8 | ALMOST_OPTIMAL | 15.543 | 0.774 | — | — |
| LV t1000 | linear12 | ALMOST_OPTIMAL | 16.171 | 0.728 | — | — |
| LV t1000 | physical12 | ALMOST_OPTIMAL | 13.579 | 0.840 | — | — |
| LV t1000 | kim12_8 | ALMOST_OPTIMAL | 13.671 | 0.723 | — | — |
| ENWL 23_Feeder_3 | physical32 | OPTIMAL | 0.022 | 0.006 | -0.000073 | -0.00000 |
| ENWL 23_Feeder_3 | kim32_8 | OPTIMAL | 0.027 | 0.012 | -0.000087 | -0.00001 |
| ENWL 18_Feeder_9 | physical32 | OPTIMAL | 16.079 | 1.433 | 33.842266 | 2.58429 |
| ENWL 18_Feeder_9 | kim32_8 | OPTIMAL | 15.607 | 1.533 | 33.627019 | 2.56785 |
| LV t500 | physical32 | OPTIMAL | 13.840 | 0.813 | 86.219280 | 0.38459 |
| LV t500 | kim32_8 | OPTIMAL | 13.487 | 0.715 | 85.832190 | 0.38286 |
| LV t1000 | physical32 | OPTIMAL | 13.444 | 0.670 | 355.879001 | 0.72822 |
| LV t1000 | kim32_8 | OPTIMAL | 13.596 | 0.647 | 353.689778 | 0.72374 |

## Original-network recovery

The initial conditional-moment recovery was unstable: on LV t500 it produced a maximum voltage-magnitude difference of 357.53 V and maximum KCL residual of roughly 29,433 A despite an OPTIMAL conic solve. The new default uses diagonal voltage moments and a maximum-correlation phase forest anchored at sources. It does not invert indefinite separator Grams. Original passive branches are then reconstructed with their original circuit equations.

| Case | Profile | Status | Max magnitude error V | Max phasor error V | Max KCL A | Reconstruction s |
|---|---|---|---:|---:|---:|---:|
| ENWL 23_Feeder_3 | linear32 | OPTIMAL | 0.000 | 0.000 | 0.003 | 0.010 |
| ENWL 23_Feeder_3 | kim12_8 | OPTIMAL | 0.000 | 0.000 | 0.004 | 0.009 |
| ENWL 18_Feeder_9 | linear32 | OPTIMAL | 0.643 | 1.067 | 63.177 | 0.295 |
| ENWL 18_Feeder_9 | kim12_8 | OPTIMAL | 0.422 | 0.820 | 36.626 | 0.227 |
| LV t500 | linear32 | OPTIMAL | 0.700 | 0.787 | 48.624 | 2.141 |
| LV t500 | kim12_8 | ALMOST_OPTIMAL | — | — | — | — |
| LV t1000 | linear32 | OPTIMAL | 1.171 | 1.171 | 44.681 | 1.880 |
| LV t1000 | kim12_8 | ALMOST_OPTIMAL | — | — | — | — |
| ENWL 23_Feeder_3 | physical32 | OPTIMAL | 0.000 | 0.000 | 0.003 | 0.009 |
| ENWL 23_Feeder_3 | kim32_8 | OPTIMAL | 0.000 | 0.000 | 0.004 | 0.008 |
| ENWL 18_Feeder_9 | physical32 | OPTIMAL | 0.648 | 1.103 | 75.378 | 0.282 |
| ENWL 18_Feeder_9 | kim32_8 | OPTIMAL | 0.647 | 1.057 | 75.309 | 0.222 |
| LV t500 | physical32 | OPTIMAL | 0.700 | 0.787 | 48.624 | 1.889 |
| LV t500 | kim32_8 | OPTIMAL | 0.709 | 0.710 | 18.123 | 2.381 |
| LV t1000 | physical32 | OPTIMAL | 1.171 | 1.171 | 44.681 | 2.372 |
| LV t1000 | kim32_8 | OPTIMAL | 1.224 | 1.226 | 30.535 | 2.271 |

Accepted LV and 96-bus ENWL tree-recovery runs show no reconstructed bus-voltage or line-current-limit violations in the recorded checks, but sizable KCL residuals remain. These outputs are useful voltage estimates; they must not be presented as AC-feasible dispatches or assumed-accurate line loadings. Full residual diagnostics and warnings accompany reconstruction. Kim32 reduces LV KCL residuals to about 18 A and 31 A; that is still material. Objective accuracy alone is not a state-accuracy test.

Preparation takes approximately 0.2–0.5 seconds on the LV snapshots; reconstruction with the full physical check takes approximately two seconds. These are additional to build/solve times. The reduced NLP takes roughly 0.02 seconds to build and 0.01 seconds to solve, so it remains much faster locally than the present SOC compiler. This study supports reduction and the portability goal; it does not establish that SOC is the fastest local optimizer.

## Transformer diagnostic inputs

These are explicitly derived inputs: transformer s_rating fields are removed, aligning the earlier known BMOPFTools nameplate-cap disagreement. They do not replace original-input results.

| Case | Buses | Original NLP | Reduced NLP | SOC | Build + solve s | Difference W |
|---|---|---|---|---|---:|---:|
| ieee34/ieee34_pmd | 56 → 41 | LOCALLY_SOLVED | LOCALLY_SOLVED | NUMERICAL_ERROR | 2.804 | — |
| cigre/CIGRE_test_case | 4 → 4 | LOCALLY_SOLVED | LOCALLY_SOLVED | OPTIMAL | 0.088 | 1006.658 |

IEEE34 still fails numerically in Clarabel after reduction; reduction does not resolve its conditioning problem. Its reduced NLP objective is about 175.48 W below the original NLP objective, measuring a circuit-reduction effect separately from the convex relaxation. CIGRE remains solvable, with approximately 0.0548% objective difference and 5.89 V maximum reconstructed magnitude difference.

## Recommendation

Keep BMOPFTools-compatible reduction and the default linear32 SOC profile as the general starting point. Smaller cliques were less reliable on the larger networks. Kim12_8 is a useful case-specific trade-off on ENWL 96: about 14.64 W difference versus 33.61 W for linear32, for roughly 19 versus 17.5 seconds of build/solve time. Kim32_8 is reliable on both LV snapshots but offers only small objective improvements; it is optional rather than a new blanket default. Removing linear strengthening did not produce a compelling advantage.

The next performance work should target repeated model construction and cached sparse preparation. The next state-quality experiment should be a bounded AC power-flow correction at the selected dispatch, separate from the fixed conic formulation. No such correction is included or implied by the present results.

## Reproduction and raw data

Run `julia --project=test/integration examples/benchmark_reduction.jl MANIFEST OUTPUT`, using the matching reduction_manifest, reduction_recovery_manifest, reduction_strengthening_manifest, or reduction_transformer_manifest under this directory. `julia --project=test/integration examples/scan_reduction.jl` repeats the topology scan. The initial sweep manifest explicitly selects conditional recovery; later manifests use the voltage-tree default. Run `python3 examples/summarize_reduction.py` to regenerate this report.

- [reduction_soc_2026-09-11.json](reduction_soc_2026-09-11.json)
- [reduction_recovery_2026-09-11.json](reduction_recovery_2026-09-11.json)
- [reduction_strengthening_2026-09-11.json](reduction_strengthening_2026-09-11.json)
- [reduction_transformers_2026-09-11.json](reduction_transformers_2026-09-11.json)
