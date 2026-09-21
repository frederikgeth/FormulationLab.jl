# SDP sparsity experiment

The IVR rows use the prepared radial feeder. The BranchFlow rows use the same feeder with one named line duplicated as a parallel circuit, which forces the otherwise conditional global voltage closure. Inputs and outputs are SI; model coordinates are per unit on a 10 kVA base. Mosek uses one thread. Times are medians of 3 fresh build/solve repetitions.

| Profile | Status | Objective (W) | Objective span (W) | Residual | Build median (s) | Solve median (s) | Variables | Constraints | Fill edges | Cliques | Max order |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ivr_minimum_degree | OPTIMAL | 1544.832 | 0.0 | 7.869907e-10 | 0.0318175 | 0.01248942 | 424 | 291 | 66.0 | 15.0 | 5.0 |
| ivr_minimum_fill | OPTIMAL | 1544.831 | 0.0 | 1.187376e-9 | 0.04532812 | 0.01253662 | 424 | 292 | 66.0 | 15.0 | 5.0 |
| bfm_dense | OPTIMAL | 1544.811 | 0.0 | 1.516766e-9 | 0.0358785 | 0.103313 | 3354 | 711 | — | 1.0 | 33.0 |
| bfm_auto | OPTIMAL | 1544.811 | 0.0 | 8.915246e-11 | 0.03463879 | 0.08082512 | 2619 | 721 | 0.0 | 2.0 | 24.0 |
| bfm_minimum_degree | OPTIMAL | 1544.811 | 0.0 | 4.462937e-10 | 0.0345565 | 0.06616121 | 2085 | 741 | 0.0 | 4.0 | 12.0 |
| bfm_minimum_fill | OPTIMAL | 1544.811 | 0.0 | 4.462937e-10 | 0.03635608 | 0.06947058 | 2085 | 741 | 0.0 | 4.0 | 12.0 |

This is a small repeated structural and numerical experiment, not a solver-independent timing claim. Repetitions run in a fixed profile order; compare objectives only within one formulation/network pair and inspect the residual and termination status.
