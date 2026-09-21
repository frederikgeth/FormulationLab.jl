# SDP sparsity experiment

The IVR rows use the prepared radial feeder. The BranchFlow rows use the same feeder with one named line duplicated as a parallel circuit, which forces the otherwise conditional global voltage closure. Inputs and outputs are SI; model coordinates are per unit on a 10 kVA base. Mosek uses one thread. Times are medians of 3 fresh build/solve repetitions.

| Profile | Status | Objective (W) | Objective span (W) | Residual | Build median (s) | Solve median (s) | Variables | Constraints | Fill edges | Cliques | Max order |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ivr_minimum_degree | OPTIMAL | -1369.049 | 0.0 | 1.730955e-9 | 5.792178 | 0.6340521 | 9530 | 5051 | 901.0 | 154.0 | 9.0 |
| ivr_minimum_fill | OPTIMAL | -1369.05 | 0.0 | 1.778915e-9 | 7.537284 | 0.517524 | 9007 | 4790 | 780.0 | 150.0 | 9.0 |
| bfm_dense | OPTIMAL | -1371.05 | 0.0 | 2.099209e-9 | 0.4959222 | 4.700418 | 176802 | 6418 | — | 1.0 | 288.0 |
| bfm_auto | OPTIMAL | -1371.049 | 0.0 | 8.495142e-9 | 0.4706263 | 1.112198 | 26076 | 6558 | 0.0 | 15.0 | 27.0 |
| bfm_minimum_degree | OPTIMAL | -1371.048 | 0.0 | 7.0314e-9 | 0.469253 | 0.9197848 | 19608 | 6838 | 0.0 | 43.0 | 12.0 |
| bfm_minimum_fill | OPTIMAL | -1371.048 | 0.0 | 7.0314e-9 | 0.5709327 | 0.9024309 | 19608 | 6838 | 0.0 | 43.0 | 12.0 |

This is a small repeated structural and numerical experiment, not a solver-independent timing claim. Repetitions run in a fixed profile order; compare objectives only within one formulation/network pair and inspect the residual and termination status.
