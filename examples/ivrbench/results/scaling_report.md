# IVR benchmark report

Sources: scaling.jsonl. Times are optimizer-call wall time; build excluded.

## Noise floor

`powers_dup` builds the identical model as `powers`. The spread of their median ratio is the smallest arm difference worth interpreting.

| Solver | Instances | Median abs. deviation | 90th pct abs. deviation | Max abs. deviation |
|---|---:|---:|---:|---:|
| ipopt | 5 | 1.4% | 2.4% | 2.7% |
| madnlp | 6 | 7.0% | 37.4% | 47.5% |

## Arms relative to the `powers` control

Geometric-mean ratio of median solve time over instances both arms solve (below 1 = faster). Success counts every instance.

### ipopt

| Arm | Solved | Geo-mean time ratio | Faster >5% | Slower >5% | Median iterations | Geo-mean iteration ratio |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 6/6 | 1.231 | 2 | 3 | 40 | 1.183 |
| `powers` | 5/6 | 1.000 | 0 | 0 | 31 | 1.000 |
| `powers_dup` | 5/6 | 1.000 | 0 | 0 | 31 | 1.000 |
| `powers_zero` | 5/6 | 1.010 | 2 | 2 | 35 | 1.122 |
| `reduced` | 5/6 | 1.104 | 2 | 2 | 35 | 1.166 |
| `reduced_broad` | 3/6 | 1.814 | 0 | 3 | 52 | 1.708 |
| `reduced_scaled` | 6/6 | 0.423 | 5 | 0 | 20 | 0.707 |
| `reduced_txelim` | 5/6 | 1.205 | 2 | 2 | 37 | 1.230 |

### madnlp

| Arm | Solved | Geo-mean time ratio | Faster >5% | Slower >5% | Median iterations | Geo-mean iteration ratio |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 6/6 | 0.992 | 1 | 0 | 22 | 1.000 |
| `powers` | 6/6 | 1.000 | 0 | 0 | 22 | 1.000 |
| `powers_dup` | 6/6 | 1.033 | 1 | 2 | 22 | 1.000 |
| `powers_zero` | 6/6 | 1.054 | 2 | 1 | 22 | 1.000 |
| `reduced` | 6/6 | 0.884 | 5 | 0 | 22 | 1.000 |
| `reduced_broad` | 6/6 | 1.553 | 0 | 6 | 26 | 1.183 |
| `reduced_scaled` | 6/6 | 0.908 | 6 | 0 | 20 | 0.967 |
| `reduced_txelim` | 6/6 | 0.923 | 4 | 0 | 22 | 1.000 |

## Performance profiles

Fraction of instances an arm solves within τ × the best arm's median time (Dolan–Moré). Unsolved instances never count. Instances no arm solves are excluded.

### ipopt (6 instances)

| Arm | τ=1.0 | τ=1.1 | τ=1.25 | τ=1.5 | τ=2.0 | τ=4.0 |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 0.00 | 0.00 | 0.00 | 0.17 | 0.17 | 0.67 |
| `powers` | 0.00 | 0.00 | 0.00 | 0.00 | 0.33 | 0.83 |
| `powers_dup` | 0.00 | 0.00 | 0.00 | 0.00 | 0.33 | 0.83 |
| `powers_zero` | 0.00 | 0.00 | 0.00 | 0.17 | 0.33 | 0.67 |
| `reduced` | 0.00 | 0.00 | 0.00 | 0.00 | 0.17 | 0.67 |
| `reduced_broad` | 0.00 | 0.00 | 0.00 | 0.00 | 0.17 | 0.17 |
| `reduced_scaled` | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| `reduced_txelim` | 0.00 | 0.00 | 0.00 | 0.00 | 0.17 | 0.50 |

### madnlp (6 instances)

| Arm | τ=1.0 | τ=1.1 | τ=1.25 | τ=1.5 | τ=2.0 | τ=4.0 |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 0.17 | 0.17 | 0.67 | 0.83 | 1.00 | 1.00 |
| `powers` | 0.00 | 0.17 | 0.67 | 0.83 | 1.00 | 1.00 |
| `powers_dup` | 0.00 | 0.17 | 0.50 | 0.83 | 1.00 | 1.00 |
| `powers_zero` | 0.17 | 0.50 | 0.67 | 0.83 | 0.83 | 1.00 |
| `reduced` | 0.17 | 0.83 | 0.83 | 1.00 | 1.00 | 1.00 |
| `reduced_broad` | 0.00 | 0.00 | 0.17 | 0.50 | 0.50 | 1.00 |
| `reduced_scaled` | 0.50 | 0.67 | 0.67 | 1.00 | 1.00 | 1.00 |
| `reduced_txelim` | 0.00 | 0.67 | 0.67 | 1.00 | 1.00 | 1.00 |

## MadNLP relative to Ipopt (same models, both MUMPS)

| Arm | Instances | Geo-mean time ratio MadNLP/Ipopt | Geo-mean iteration ratio |
|---|---:|---:|---:|
| `full` | 6 | 0.190 | 0.529 |
| `powers` | 5 | 0.275 | 0.717 |
| `powers_dup` | 5 | 0.286 | 0.717 |
| `powers_zero` | 5 | 0.214 | 0.561 |
| `reduced` | 5 | 0.172 | 0.486 |
| `reduced_broad` | 3 | 0.357 | 0.629 |
| `reduced_scaled` | 6 | 0.610 | 0.993 |
| `reduced_txelim` | 5 | 0.196 | 0.529 |

## Where Ipopt spends time

From the diagnostic solve of each (instance, arm). Shares of Ipopt's own total (internal + function evaluations).

| Statistic | Median | 10th pct | 90th pct |
|---|---:|---:|---:|
| Function-evaluation share | 0.031 | 0.022 | 0.042 |
| Primal-dual system solve share | 0.919 | 0.846 | 0.946 |
| Factorizations per iteration | 1.857 | 1.100 | 2.405 |

### Cost model

Least squares on log median solve time over 39 (instance, arm) cells.

| Predictors | R² | Coefficients (intercept, …) |
|---|---:|---|
| iterations only | 0.525 | -7.295, 2.156 |
| factor size only | 0.801 | -18.486, 1.318 |
| iterations + factor size | 0.991 | -19.927, 1.388, 1.075 |
| factorizations + factor size | 0.997 | -18.291, 0.870, 1.056 |
| iterations + factor size + derivative nnz | 0.992 | -19.723, 1.405, 0.930, 0.141 |

## Objective consistency

Largest relative objective spread among solved arms per instance (local optima or loose termination).

| Solver | Instances | Median spread | Max spread | Instances with spread > 1e-4 |
|---|---:|---:|---:|---:|
| ipopt | 6 | 1.2e-04 | 1.8e-04 | 3 |
| madnlp | 6 | 8.6e-06 | 1.4e-04 | 1 |

## Median solve time per instance (ms)

### ipopt

| Case | Buses | Load | `full` | `powers` | `powers_dup` | `powers_zero` | `reduced` | `reduced_broad` | `reduced_scaled` | `reduced_txelim` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 53_MVFeeder0641.bmopf.json | 1583 | 1 | 14888.9 | 6401.3 | 6287.5 | fail 5/5 | fail 5/5 | fail 5/5 | 2067.9 | fail 5/5 |
| 76_MVFeeder0812.bmopf.json | 995 | 1 | 11848.8 | fail 5/5 | fail 5/5 | 8825.2 | 16507.0 | fail 5/5 | 1352.1 | 7700.3 |
| 84_MVFeeder0460.bmopf.json | 248 | 1 | 944.2 | 758.4 | 764.6 | 485.2 | 537.8 | 1360.8 | 333.2 | 641.4 |
| 84_MVFeeder2024.bmopf.json | 110 | 1 | 149.3 | 163.5 | 161.2 | 386.9 | 323.5 | 198.2 | 100.2 | 267.3 |
| 84_MVFeeder2628.bmopf.json | 498 | 1 | 2503.6 | 2689.9 | 2763.7 | 1641.1 | 1672.8 | fail 5/5 | 826.2 | 1707.9 |
| 84_MVFeeder2809.bmopf.json | 701 | 1 | 1931.1 | 1682.8 | 1678.8 | 1896.2 | 2864.6 | 4616.2 | 848.1 | 4043.1 |

### madnlp

| Case | Buses | Load | `full` | `powers` | `powers_dup` | `powers_zero` | `reduced` | `reduced_broad` | `reduced_scaled` | `reduced_txelim` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 53_MVFeeder0641.bmopf.json | 1583 | 1 | 1512.8 | 1468.4 | 1513.5 | 3564.6 | 1381.1 | 1640.4 | 1360.0 | 1416.7 |
| 76_MVFeeder0812.bmopf.json | 995 | 1 | 1084.0 | 1071.4 | 1069.8 | 1024.9 | 755.4 | 1127.9 | 985.5 | 1020.9 |
| 84_MVFeeder0460.bmopf.json | 248 | 1 | 165.8 | 182.9 | 181.5 | 175.6 | 180.0 | 244.5 | 166.5 | 169.7 |
| 84_MVFeeder2024.bmopf.json | 110 | 1 | 63.5 | 63.3 | 70.2 | 64.7 | 55.7 | 171.5 | 54.6 | 57.1 |
| 84_MVFeeder2628.bmopf.json | 498 | 1 | 405.6 | 397.6 | 586.5 | 372.0 | 371.2 | 806.8 | 357.7 | 365.9 |
| 84_MVFeeder2809.bmopf.json | 701 | 1 | 817.0 | 829.3 | 602.9 | 532.5 | 738.5 | 1347.1 | 772.3 | 723.9 |

