# SDP sparsity experiment

The IVR rows use the prepared radial feeder. The BranchFlow rows use the same feeder with one named line duplicated as a parallel circuit, which forces the otherwise conditional global voltage closure. Inputs and outputs are SI; model coordinates are per unit on a 10 kVA base. Mosek uses one thread. Times are medians of 3 fresh build/solve repetitions.

| Profile | Status | Objective (W) | Objective span (W) | Residual | Build median (s) | Solve median (s) | Variables | Constraints | Fill edges | Cliques | Max order |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ivr_minimum_degree | SLOW_PROGRESS | — | — | 1.3538e-6 | 0.2526025 | 0.817712 | 6353 | 2962 | 549.0 | 52.0 | 14.0 |
| ivr_minimum_fill | SLOW_PROGRESS | — | — | 2.996585e-6 | 0.412635 | 0.9378122 | 6041 | 2816 | 549.0 | 52.0 | 14.0 |
| bfm_dense | OPTIMAL | -4037.593 | 0.0 | 1.593734e-8 | 0.08250921 | 0.3738742 | 13506 | 1702 | — | 1.0 | 72.0 |
| bfm_auto | OPTIMAL | -4037.593 | 0.0 | 1.009445e-8 | 0.08184525 | 0.2497372 | 5988 | 1842 | 0.0 | 15.0 | 30.0 |
| bfm_minimum_degree | OPTIMAL | -4037.59 | 0.0 | 2.818525e-8 | 0.07707017 | 0.1878871 | 4926 | 1902 | 0.0 | 21.0 | 12.0 |
| bfm_minimum_fill | OPTIMAL | -4037.59 | 0.0 | 2.818525e-8 | 0.09156604 | 0.1878336 | 4926 | 1902 | 0.0 | 21.0 | 12.0 |

This is a small repeated structural and numerical experiment, not a solver-independent timing claim. Repetitions run in a fixed profile order; compare objectives only within one formulation/network pair and inspect the residual and termination status.
