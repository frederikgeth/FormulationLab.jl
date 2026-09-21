# SDP sparsity experiment

The IVR rows use the prepared radial feeder. The BranchFlow rows use the same feeder with one named line duplicated as a parallel circuit, which forces the otherwise conditional global voltage closure. Inputs and outputs are SI; model coordinates are per unit on a 10 kVA base. Mosek uses one thread. Times are medians of 3 fresh build/solve repetitions.

| Profile | Status | Objective (W) | Objective span (W) | Residual | Build median (s) | Solve median (s) | Variables | Constraints | Fill edges | Cliques | Max order |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ivr_minimum_degree | OPTIMAL | -1089.605 | 0.0 | 2.943952e-10 | 0.03199633 | 0.02775967 | 803 | 432 | 57.0 | 15.0 | 7.0 |
| ivr_minimum_fill | OPTIMAL | -1089.605 | 0.0 | 2.82665e-8 | 0.03936546 | 0.02885088 | 803 | 432 | 57.0 | 15.0 | 7.0 |
| bfm_dense | SLOW_PROGRESS | — | — | 6.484864e-6 | 0.03529029 | 0.1906001 | 2958 | 668 | — | 1.0 | 30.0 |
| bfm_auto | SLOW_PROGRESS | — | — | 6.484864e-6 | 0.03483583 | 0.1895929 | 2958 | 668 | — | 1.0 | 30.0 |
| bfm_minimum_degree | SLOW_PROGRESS | — | — | 1.022023e-5 | 0.03288521 | 0.1649428 | 1926 | 708 | 0.0 | 5.0 | 12.0 |
| bfm_minimum_fill | SLOW_PROGRESS | — | — | 1.022023e-5 | 0.03299462 | 0.1577358 | 1926 | 708 | 0.0 | 5.0 | 12.0 |

This is a small repeated structural and numerical experiment, not a solver-independent timing claim. Repetitions run in a fixed profile order; compare objectives only within one formulation/network pair and inspect the residual and termination status.
