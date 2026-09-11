# Implemented SOC profiles: fixed comparison

Three serial repeats with fresh solver instances and the controlled-study settings: feasibility 1e-7, absolute gap 1e-6, relative gap 1e-7, regularization 1e-7, refinement cap 30, 90-second solver limit, one BLAS thread. Native time excludes build/setup/extraction/reconstruction. CHOLMOD is an explicit experimental override; the default remains QDLDL.

All variants share prepared inputs, power bases, objective and static electrical semantics. NLP differences use fresh BMOPFTools/Ipopt local solutions. They are not certified optimality gaps. Non-publishable runs remain visible.

## network_9_Feeder_4.json

| Variant | Accepted | Native median s [min, max] | Iterations | NLP − SOC W | First-repeat KCL A | nnz(KKT L) |
|:--|--:|--:|--:|--:|--:|--:|
| fast | 3/3 | 0.8567 [0.8504, 0.8760] | 20 | 25.461939 | 84.772 | 399609 |
| balanced | 3/3 | 1.3285 [1.3271, 1.3378] | 23 | 3.092263 | 20.855 | 537626 |
| physical_sparse | 3/3 | 0.0405 [0.0405, 0.0411] | 19 | 0.103533 | 26.847 | 51562 |
| kim2 | 3/3 | 1.1528 [1.1466, 1.1556] | 26 | 2.077024 | 116.097 | 430416 |
| kim4 | 3/3 | 1.2039 [1.2035, 1.2051] | 25 | 2.953474 | 37.505 | 462374 |
| balanced_cholmod | 3/3 | 1.5862 [1.5766, 1.5906] | 23 | 3.092893 | 20.865 | 608271 |

Physical basis: 1 dependent components; relative map difference 1.17e-14; relative electrical residual 9.19e-17; no fallback.

## network_18_Feeder_6.json

| Variant | Accepted | Native median s [min, max] | Iterations | NLP − SOC W | First-repeat KCL A | nnz(KKT L) |
|:--|--:|--:|--:|--:|--:|--:|
| fast | 3/3 | 2.1754 [2.1722, 2.2566] | 25 | 57.433546 | 14.945 | 699572 |
| balanced | 3/3 | 2.9277 [2.9159, 3.0960] | 28 | 16.480493 | 392.151 | 851453 |
| physical_sparse | 3/3 | 0.5091 [0.5002, 0.5124] | 19 | 20.713857 | 124.712 | 349318 |
| kim2 | 3/3 | 2.4098 [2.3901, 2.4198] | 27 | 19.961975 | 62.722 | 737789 |
| kim4 | 0/3 | 3.3260 [3.3114, 3.3263] | 30 | — | — | 844527 |
| balanced_cholmod | 3/3 | 4.3455 [4.3414, 4.3949] | 28 | 16.464575 | 509.746 | 1159913 |

Physical basis: 2 dependent components; relative map difference 3.85e-14; relative electrical residual 1.11e-16; no fallback.

## network_18_Feeder_9.json

| Variant | Accepted | Native median s [min, max] | Iterations | NLP − SOC W | First-repeat KCL A | nnz(KKT L) |
|:--|--:|--:|--:|--:|--:|--:|
| fast | 3/3 | 1.3538 [1.3335, 1.3558] | 64 | 33.607017 | 63.177 | 534132 |
| balanced | 3/3 | 1.4102 [1.4085, 1.4302] | 65 | 33.627019 | 75.309 | 551803 |
| physical_sparse | 3/3 | 0.7380 [0.7379, 0.7452] | 34 | 33.663817 | 7751.118 | 545464 |
| kim2 | 3/3 | 1.3859 [1.3824, 1.3993] | 65 | 33.592746 | 76.548 | 542147 |
| kim4 | 3/3 | 1.4475 [1.4348, 1.6779] | 67 | 33.672369 | 63.530 | 545851 |
| balanced_cholmod | 3/3 | 1.6876 [1.6271, 1.7990] | 65 | 33.603729 | 78.672 | 551803 |

Physical basis: 1 dependent components; relative map difference 3.66e-14; relative electrical residual 1.11e-16; no fallback.

## lvtestcase/snapshots/lvtestcase_pmd_t500.dss

| Variant | Accepted | Native median s [min, max] | Iterations | NLP − SOC W | First-repeat KCL A | nnz(KKT L) |
|:--|--:|--:|--:|--:|--:|--:|
| fast | 3/3 | 0.6965 [0.6945, 0.6969] | 81 | 86.219280 | 48.624 | 246920 |
| balanced | 3/3 | 0.6534 [0.6507, 0.6577] | 72 | 85.832190 | 18.123 | 258074 |
| physical_sparse | 3/3 | 0.6284 [0.6271, 0.6325] | 73 | 71.432691 | 102.364 | 254769 |
| kim2 | 3/3 | 0.6487 [0.6447, 0.6494] | 74 | 86.049839 | 18.505 | 250267 |
| kim4 | 3/3 | 0.5968 [0.5869, 0.6000] | 67 | 85.777230 | 58.203 | 252274 |
| balanced_cholmod | 3/3 | 0.7793 [0.7618, 0.7877] | 74 | 86.040862 | 18.684 | 258074 |

Physical basis: 26 dependent components; relative map difference 5.78e-15; relative electrical residual 2.54e-16; no fallback.

## lvtestcase/snapshots/lvtestcase_pmd_t1000.dss

| Variant | Accepted | Native median s [min, max] | Iterations | NLP − SOC W | First-repeat KCL A | nnz(KKT L) |
|:--|--:|--:|--:|--:|--:|--:|
| fast | 3/3 | 0.6047 [0.6046, 0.6054] | 73 | 355.879001 | 44.681 | 242544 |
| balanced | 3/3 | 0.6013 [0.5988, 0.6070] | 68 | 353.689778 | 30.535 | 253514 |
| physical_sparse | 3/3 | 0.4868 [0.4830, 0.4895] | 56 | 355.845921 | 372.493 | 247858 |
| kim2 | 3/3 | 0.6070 [0.6048, 0.6152] | 72 | 355.525007 | 25.616 | 244171 |
| kim4 | 3/3 | 0.6291 [0.6236, 0.6345] | 73 | 354.730590 | 39.101 | 247722 |
| balanced_cholmod | 3/3 | 0.7013 [0.6950, 0.7020] | 68 | 355.774290 | 31.567 | 253514 |

Physical basis: 20 dependent components; relative map difference 5.65e-15; relative electrical residual 2.54e-16; no fallback.

## Interpretation

The structural physical basis is the main improvement. Automatic selection now uses it only for small independent-state dimensions; selecting it explicitly on larger cases can change SOC strength and severely worsen voltage-tree recovery (notably ENWL 96). The sparse fast/balanced presets remain alternatives, not uniformly faster choices.

Kim4 fails acceptance on 45 buses. CHOLMOD is slower than QDLDL on this panel and is not promoted. Budget-dependent primal objectives are not consistently monotone in these numerically sensitive models; small conic residuals should not be treated as rigorous accuracy certificates or used to assert that a smaller cut set is stronger.

## Reproduction

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test/integration examples/benchmark_soc_profiles.jl examples/results/soc_profiles_2026-09-11.json 3
python3 examples/summarize_soc_profiles.py
```

[Raw measurements](soc_profiles_2026-09-11.json). The automatic-policy change was made after this sweep; its `physical_sparse` variant explicitly selects the same small-state algorithm. Wider-panel runs exercise the new automatic policy.
