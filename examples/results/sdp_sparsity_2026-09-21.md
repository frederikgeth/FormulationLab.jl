# SDP sparsity experiment

The IVR rows use the prepared radial feeder. The BranchFlow rows use the same feeder with one named line duplicated as a parallel circuit, which forces the otherwise conditional global voltage closure. Inputs and outputs are SI; model coordinates are per unit on a 10 kVA base. Mosek uses one thread.

| Profile | Status | Objective (W) | Residual | Build (s) | Solve (s) | Variables | Constraints | Fill edges | Cliques | Max order |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ivr_minimum_degree | OPTIMAL | -1369.049 | 1.730955e-9 | 10.98952 | 1.728329 | 9530 | 5051 | 901.0 | 154.0 | 9.0 |
| ivr_minimum_fill | OPTIMAL | -1369.05 | 1.778915e-9 | 7.326668 | 0.519998 | 9007 | 4790 | 780.0 | 150.0 | 9.0 |
| bfm_dense | OPTIMAL | -1371.05 | 2.099209e-9 | 2.489044 | 5.097019 | 176802 | 6418 | — | 1.0 | 288.0 |
| bfm_minimum_degree | OPTIMAL | -1371.048 | 7.0314e-9 | 0.4852574 | 0.9867661 | 19608 | 6838 | 0.0 | 43.0 | 12.0 |
| bfm_minimum_fill | OPTIMAL | -1371.048 | 7.0314e-9 | 0.5707595 | 0.9206348 | 19608 | 6838 | 0.0 | 43.0 | 12.0 |

This is a single-run structural and numerical experiment, not a solver-independent timing claim. Compare objectives only within one formulation/network pair and inspect the residual and termination status.
