# SDP sparsity experiment

The IVR rows use the prepared radial feeder. The BranchFlow rows use the same feeder with one named line duplicated as a parallel circuit, which forces the otherwise conditional global voltage closure. Inputs and outputs are SI; model coordinates are per unit on a 10 kVA base. Mosek uses one thread. Times are medians of 3 fresh build/solve repetitions.

| Profile | Status | Objective (W) | Objective span (W) | Residual | Build median (s) | Solve median (s) | Variables | Constraints | Fill edges | Cliques | Max order |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ivr_minimum_degree | OPTIMAL | -2969.249 | 0.0 | 1.975637e-9 | 0.8316113 | 0.1430486 | 3440 | 1923 | 333.0 | 68.0 | 7.0 |
| ivr_minimum_fill | OPTIMAL | -2969.249 | 0.0 | 2.312921e-9 | 1.049882 | 0.1468152 | 3522 | 1962 | 324.0 | 69.0 | 7.0 |
| bfm_dense | OPTIMAL | -2977.126 | 0.0 | 5.275414e-9 | 0.1721319 | 1.184844 | 41514 | 2992 | — | 1.0 | 135.0 |
| bfm_auto | OPTIMAL | -2977.127 | 0.0 | 1.053836e-8 | 0.1631315 | 0.5083195 | 11817 | 3062 | 0.0 | 8.0 | 27.0 |
| bfm_minimum_degree | OPTIMAL | -2977.126 | 0.0 | 1.440883e-9 | 0.1603113 | 0.4304201 | 9132 | 3172 | 0.0 | 19.0 | 12.0 |
| bfm_minimum_fill | OPTIMAL | -2977.126 | 0.0 | 1.440883e-9 | 0.1933392 | 0.4387745 | 9132 | 3172 | 0.0 | 19.0 | 12.0 |

This is a small repeated structural and numerical experiment, not a solver-independent timing claim. Repetitions run in a fixed profile order; compare objectives only within one formulation/network pair and inspect the residual and termination status.
