# IVR benchmark report

Sources: strict.jsonl. Times are optimizer-call wall time; build excluded.

## Noise floor

`powers_dup` builds the identical model as `powers`. The spread of their median ratio is the smallest arm difference worth interpreting.

| Solver | Instances | Median abs. deviation | 90th pct abs. deviation | Max abs. deviation |
|---|---:|---:|---:|---:|
| ipopt_strict | 3 | 1.1% | 1.9% | 2.1% |

## Arms relative to the `powers` control

Geometric-mean ratio of median solve time over instances both arms solve (below 1 = faster). Success counts every instance.

### ipopt_strict

| Arm | Solved | Geo-mean time ratio | Faster >5% | Slower >5% | Median iterations | Geo-mean iteration ratio |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 3/8 | 0.715 | 3 | 0 | 30 | 0.762 |
| `powers` | 3/8 | 1.000 | 0 | 0 | 45 | 1.000 |
| `powers_dup` | 3/8 | 1.003 | 0 | 0 | 45 | 1.000 |
| `powers_zero` | 3/8 | 1.228 | 2 | 1 | 60 | 1.268 |
| `reduced` | 3/8 | 1.284 | 2 | 1 | 60 | 1.288 |
| `reduced_broad` | 3/8 | 1.640 | 1 | 2 | 88 | 1.666 |
| `reduced_scaled` | 3/8 | 0.371 | 3 | 0 | 26 | 0.631 |
| `reduced_txelim` | 3/8 | 0.856 | 2 | 1 | 38 | 0.929 |

## Performance profiles

Fraction of instances an arm solves within τ × the best arm's median time (Dolan–Moré). Unsolved instances never count. Instances no arm solves are excluded.

### ipopt_strict (3 instances)

| Arm | τ=1.0 | τ=1.1 | τ=1.25 | τ=1.5 | τ=2.0 | τ=4.0 |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 0.00 | 0.00 | 0.00 | 0.00 | 0.67 | 1.00 |
| `powers` | 0.00 | 0.00 | 0.00 | 0.00 | 0.33 | 0.67 |
| `powers_dup` | 0.00 | 0.00 | 0.00 | 0.00 | 0.33 | 0.67 |
| `powers_zero` | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.67 |
| `reduced` | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.67 |
| `reduced_broad` | 0.00 | 0.00 | 0.00 | 0.00 | 0.33 | 0.33 |
| `reduced_scaled` | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| `reduced_txelim` | 0.00 | 0.00 | 0.00 | 0.00 | 0.33 | 1.00 |

## Where Ipopt spends time

From the diagnostic solve of each (instance, arm). Shares of Ipopt's own total (internal + function evaluations).

| Statistic | Median | 10th pct | 90th pct |
|---|---:|---:|---:|
| Function-evaluation share | 0.035 | 0.026 | 0.044 |
| Primal-dual system solve share | 0.918 | 0.866 | 0.940 |
| Factorizations per iteration | 1.607 | 1.170 | 2.230 |

### Cost model

Least squares on log median solve time over 24 (instance, arm) cells.

| Predictors | R² | Coefficients (intercept, …) |
|---|---:|---|
| iterations only | 0.774 | -5.261, 1.408 |
| factor size only | 0.212 | -14.415, 1.044 |
| iterations + factor size | 0.952 | -18.384, 1.378, 0.956 |
| factorizations + factor size | 0.981 | -17.787, 0.863, 1.023 |
| iterations + factor size + derivative nnz | 0.979 | -19.767, 1.528, 0.767, 0.280 |

## Objective consistency

Largest relative objective spread among solved arms per instance (local optima or loose termination).

| Solver | Instances | Median spread | Max spread | Instances with spread > 1e-4 |
|---|---:|---:|---:|---:|
| ipopt_strict | 3 | 1.8e-11 | 1.2e-09 | 0 |

## Median solve time per instance (ms)

### ipopt_strict

| Case | Buses | Load | `full` | `powers` | `powers_dup` | `powers_zero` | `reduced` | `reduced_broad` | `reduced_scaled` | `reduced_txelim` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 11_MVFeeder1365.bmopf.json | 198 | 1 | 469.5 | 495.7 | 506.0 | 1320.8 | 1299.5 | 2310.5 | 292.3 | 626.6 |
| 24_MVFeeder0277.bmopf.json | 350 | 1 | 920.4 | 1466.0 | 1464.7 | 1151.3 | 1348.8 | 926.2 | 565.4 | 1096.6 |
| 27_MVFeeder2091.bmopf.json | 141 | 1 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 53_MVFeeder1979.bmopf.json | 313 | 1 | 1181.2 | 1918.0 | 1897.0 | 1697.9 | 1685.3 | 2872.7 | 430.1 | 1272.7 |
| 11_MVFeeder1365.bmopf.json | 198 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 24_MVFeeder0277.bmopf.json | 350 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 27_MVFeeder2091.bmopf.json | 141 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 53_MVFeeder1979.bmopf.json | 313 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |

