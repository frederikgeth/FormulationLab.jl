# IVR benchmark report

Sources: ablation.jsonl. Times are optimizer-call wall time; build excluded.

## Noise floor

`powers_dup` builds the identical model as `powers`. The spread of their median ratio is the smallest arm difference worth interpreting.

| Solver | Instances | Median abs. deviation | 90th pct abs. deviation | Max abs. deviation |
|---|---:|---:|---:|---:|
| ipopt | 4 | 1.1% | 2.5% | 2.7% |
| ipopt_pivtol | 5 | 0.7% | 2.3% | 2.7% |

## Arms relative to the `powers` control

Geometric-mean ratio of median solve time over instances both arms solve (below 1 = faster). Success counts every instance.

### ipopt

| Arm | Solved | Geo-mean time ratio | Faster >5% | Slower >5% | Median iterations | Geo-mean iteration ratio |
|---|---:|---:|---:|---:|---:|---:|
| `full_scaled` | 5/5 | 0.525 | 4 | 0 | 20 | 0.710 |
| `powers` | 4/5 | 1.000 | 0 | 0 | 28 | 1.000 |
| `powers_dup` | 4/5 | 1.011 | 0 | 0 | 28 | 1.000 |
| `powers_scaled` | 5/5 | 0.504 | 4 | 0 | 20 | 0.710 |
| `reduced` | 5/5 | 1.114 | 2 | 2 | 35 | 1.166 |
| `reduced_gscale` | 5/5 | 1.111 | 2 | 2 | 35 | 1.166 |
| `reduced_rscale` | 5/5 | 0.950 | 2 | 2 | 33 | 1.081 |
| `reduced_scaled` | 5/5 | 0.455 | 4 | 0 | 20 | 0.733 |
| `reduced_tr` | 5/5 | 0.460 | 4 | 0 | 20 | 0.733 |
| `reduced_tscale` | 5/5 | 0.426 | 4 | 0 | 20 | 0.676 |

### ipopt_pivtol

| Arm | Solved | Geo-mean time ratio | Faster >5% | Slower >5% | Median iterations | Geo-mean iteration ratio |
|---|---:|---:|---:|---:|---:|---:|
| `full_scaled` | 5/5 | 0.948 | 2 | 0 | 20 | 0.981 |
| `powers` | 5/5 | 1.000 | 0 | 0 | 21 | 1.000 |
| `powers_dup` | 5/5 | 0.997 | 0 | 0 | 21 | 1.000 |
| `powers_scaled` | 5/5 | 0.953 | 2 | 0 | 20 | 0.981 |
| `reduced` | 5/5 | 0.842 | 5 | 0 | 21 | 1.000 |
| `reduced_gscale` | 5/5 | 0.816 | 5 | 0 | 21 | 1.000 |
| `reduced_rscale` | 5/5 | 0.818 | 5 | 0 | 21 | 1.000 |
| `reduced_scaled` | 5/5 | 0.784 | 5 | 0 | 20 | 0.981 |
| `reduced_tr` | 5/5 | 0.785 | 5 | 0 | 20 | 0.981 |
| `reduced_tscale` | 5/5 | 0.734 | 5 | 0 | 20 | 0.933 |

## Performance profiles

Fraction of instances an arm solves within τ × the best arm's median time (Dolan–Moré). Unsolved instances never count. Instances no arm solves are excluded.

### ipopt (5 instances)

| Arm | τ=1.0 | τ=1.1 | τ=1.25 | τ=1.5 | τ=2.0 | τ=4.0 |
|---|---:|---:|---:|---:|---:|---:|
| `full_scaled` | 0.00 | 0.00 | 0.20 | 0.80 | 1.00 | 1.00 |
| `powers` | 0.00 | 0.00 | 0.00 | 0.00 | 0.40 | 0.60 |
| `powers_dup` | 0.00 | 0.00 | 0.00 | 0.00 | 0.20 | 0.60 |
| `powers_scaled` | 0.20 | 0.20 | 0.20 | 0.60 | 1.00 | 1.00 |
| `reduced` | 0.00 | 0.00 | 0.00 | 0.00 | 0.20 | 0.80 |
| `reduced_gscale` | 0.00 | 0.00 | 0.00 | 0.00 | 0.20 | 0.80 |
| `reduced_rscale` | 0.00 | 0.00 | 0.00 | 0.00 | 0.20 | 0.80 |
| `reduced_scaled` | 0.60 | 0.80 | 0.80 | 0.80 | 1.00 | 1.00 |
| `reduced_tr` | 0.00 | 0.80 | 0.80 | 0.80 | 1.00 | 1.00 |
| `reduced_tscale` | 0.20 | 0.60 | 0.80 | 1.00 | 1.00 | 1.00 |

### ipopt_pivtol (5 instances)

| Arm | τ=1.0 | τ=1.1 | τ=1.25 | τ=1.5 | τ=2.0 | τ=4.0 |
|---|---:|---:|---:|---:|---:|---:|
| `full_scaled` | 0.00 | 0.00 | 0.20 | 1.00 | 1.00 | 1.00 |
| `powers` | 0.00 | 0.00 | 0.00 | 1.00 | 1.00 | 1.00 |
| `powers_dup` | 0.00 | 0.00 | 0.00 | 1.00 | 1.00 | 1.00 |
| `powers_scaled` | 0.00 | 0.00 | 0.20 | 1.00 | 1.00 | 1.00 |
| `reduced` | 0.00 | 0.40 | 0.80 | 1.00 | 1.00 | 1.00 |
| `reduced_gscale` | 0.00 | 0.60 | 1.00 | 1.00 | 1.00 | 1.00 |
| `reduced_rscale` | 0.00 | 0.20 | 1.00 | 1.00 | 1.00 | 1.00 |
| `reduced_scaled` | 0.00 | 0.60 | 1.00 | 1.00 | 1.00 | 1.00 |
| `reduced_tr` | 0.00 | 0.60 | 1.00 | 1.00 | 1.00 | 1.00 |
| `reduced_tscale` | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |

## Where Ipopt spends time

From the diagnostic solve of each (instance, arm). Shares of Ipopt's own total (internal + function evaluations).

| Statistic | Median | 10th pct | 90th pct |
|---|---:|---:|---:|
| Function-evaluation share | 0.049 | 0.032 | 0.064 |
| Primal-dual system solve share | 0.823 | 0.795 | 0.912 |
| Factorizations per iteration | 1.050 | 1.048 | 1.949 |

### Cost model

Least squares on log median solve time over 97 (instance, arm) cells.

| Predictors | R² | Coefficients (intercept, …) |
|---|---:|---|
| iterations only | 0.435 | -6.900, 2.033 |
| factor size only | 0.728 | -16.468, 1.131 |
| iterations + factor size | 0.982 | -19.624, 1.584, 0.999 |
| factorizations + factor size | 0.994 | -18.163, 0.953, 1.025 |
| iterations + factor size + derivative nnz | 0.984 | -19.168, 1.566, 0.541, 0.476 |

## Objective consistency

Largest relative objective spread among solved arms per instance (local optima or loose termination).

| Solver | Instances | Median spread | Max spread | Instances with spread > 1e-4 |
|---|---:|---:|---:|---:|
| ipopt | 5 | 9.5e-05 | 1.8e-04 | 2 |
| ipopt_pivtol | 5 | 1.3e-13 | 9.4e-13 | 0 |

## Median solve time per instance (ms)

### ipopt

| Case | Buses | Load | `full_scaled` | `powers` | `powers_dup` | `powers_scaled` | `reduced` | `reduced_gscale` | `reduced_rscale` | `reduced_scaled` | `reduced_tr` | `reduced_tscale` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 76_MVFeeder0812.bmopf.json | 995 | 1 | 1829.9 | fail 3/3 | fail 3/3 | 2100.5 | 16383.8 | 16257.2 | 13070.2 | 1355.1 | 1360.2 | 1726.7 |
| 84_MVFeeder0460.bmopf.json | 248 | 1 | 347.5 | 776.2 | 797.5 | 313.3 | 548.2 | 554.8 | 531.7 | 341.3 | 344.3 | 365.9 |
| 84_MVFeeder2024.bmopf.json | 110 | 1 | 134.8 | 167.5 | 167.2 | 133.6 | 335.7 | 336.6 | 220.0 | 104.5 | 106.0 | 105.0 |
| 84_MVFeeder2628.bmopf.json | 498 | 1 | 895.3 | 2701.1 | 2699.6 | 849.0 | 1694.9 | 1658.8 | 1312.8 | 826.9 | 841.3 | 544.4 |
| 84_MVFeeder2809.bmopf.json | 701 | 1 | 1059.6 | 1660.2 | 1693.8 | 1057.6 | 2882.7 | 2863.9 | 3092.6 | 844.0 | 848.1 | 919.0 |

### ipopt_pivtol

| Case | Buses | Load | `full_scaled` | `powers` | `powers_dup` | `powers_scaled` | `reduced` | `reduced_gscale` | `reduced_rscale` | `reduced_scaled` | `reduced_tr` | `reduced_tscale` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 76_MVFeeder0812.bmopf.json | 995 | 1 | 1341.0 | 1533.0 | 1522.9 | 1353.2 | 1411.6 | 1205.8 | 1243.2 | 1130.9 | 1141.1 | 1120.9 |
| 84_MVFeeder0460.bmopf.json | 248 | 1 | 324.1 | 350.9 | 341.5 | 329.6 | 293.9 | 295.9 | 292.4 | 276.9 | 275.2 | 250.2 |
| 84_MVFeeder2024.bmopf.json | 110 | 1 | 135.6 | 139.3 | 139.4 | 136.7 | 109.4 | 108.9 | 109.9 | 106.1 | 108.1 | 99.5 |
| 84_MVFeeder2628.bmopf.json | 498 | 1 | 695.7 | 705.7 | 718.1 | 690.9 | 604.6 | 603.3 | 590.5 | 580.7 | 578.2 | 512.1 |
| 84_MVFeeder2809.bmopf.json | 701 | 1 | 942.3 | 954.2 | 956.9 | 944.2 | 778.9 | 779.6 | 785.3 | 774.6 | 767.8 | 753.7 |

