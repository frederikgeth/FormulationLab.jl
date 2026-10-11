# IVR benchmark report

Sources: validation.jsonl. Times are optimizer-call wall time; build excluded.

## Noise floor

`powers_dup` builds the identical model as `powers`. The spread of their median ratio is the smallest arm difference worth interpreting.

| Solver | Instances | Median abs. deviation | 90th pct abs. deviation | Max abs. deviation |
|---|---:|---:|---:|---:|
| ipopt | 18 | 0.6% | 1.4% | 4.0% |
| ipopt_pivtol | 19 | 0.6% | 2.6% | 7.2% |
| madnlp | 19 | 9.8% | 36.5% | 76.0% |

## Arms relative to the `powers` control

Geometric-mean ratio of median solve time over instances both arms solve (below 1 = faster). Success counts every instance.

### ipopt

| Arm | Solved | Geo-mean time ratio | Faster >5% | Slower >5% | Median iterations | Geo-mean iteration ratio |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 19/20 | 0.888 | 9 | 6 | 24 | 0.933 |
| `powers` | 18/20 | 1.000 | 0 | 0 | 29 | 1.000 |
| `powers_dup` | 18/20 | 0.999 | 0 | 0 | 29 | 1.000 |
| `profile_fast` | 19/20 | 0.404 | 18 | 0 | 19 | 0.683 |
| `profile_scaled` | 19/20 | 0.464 | 18 | 0 | 19 | 0.680 |

### ipopt_pivtol

| Arm | Solved | Geo-mean time ratio | Faster >5% | Slower >5% | Median iterations | Geo-mean iteration ratio |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 19/20 | 0.992 | 1 | 0 | 21 | 1.000 |
| `powers` | 19/20 | 1.000 | 0 | 0 | 21 | 1.000 |
| `powers_dup` | 19/20 | 0.998 | 1 | 0 | 21 | 1.000 |
| `profile_fast` | 19/20 | 0.724 | 19 | 0 | 19 | 0.932 |
| `profile_scaled` | 19/20 | 0.860 | 19 | 0 | 19 | 0.932 |

### madnlp

| Arm | Solved | Geo-mean time ratio | Faster >5% | Slower >5% | Median iterations | Geo-mean iteration ratio |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 19/20 | 0.999 | 5 | 8 | 21 | 1.000 |
| `powers` | 19/20 | 1.000 | 0 | 0 | 21 | 1.000 |
| `powers_dup` | 19/20 | 1.015 | 4 | 9 | 21 | 1.000 |
| `profile_fast` | 19/20 | 0.933 | 12 | 3 | 20 | 0.929 |
| `profile_scaled` | 19/20 | 0.977 | 7 | 5 | 20 | 0.929 |

## Performance profiles

Fraction of instances an arm solves within τ × the best arm's median time (Dolan–Moré). Unsolved instances never count. Instances no arm solves are excluded.

### ipopt (19 instances)

| Arm | τ=1.0 | τ=1.1 | τ=1.25 | τ=1.5 | τ=2.0 | τ=4.0 |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 0.00 | 0.00 | 0.00 | 0.16 | 0.47 | 0.79 |
| `powers` | 0.00 | 0.00 | 0.00 | 0.05 | 0.42 | 0.84 |
| `powers_dup` | 0.00 | 0.00 | 0.00 | 0.05 | 0.42 | 0.84 |
| `profile_fast` | 0.95 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| `profile_scaled` | 0.05 | 0.26 | 0.84 | 1.00 | 1.00 | 1.00 |

### ipopt_pivtol (19 instances)

| Arm | τ=1.0 | τ=1.1 | τ=1.25 | τ=1.5 | τ=2.0 | τ=4.0 |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 0.00 | 0.00 | 0.00 | 0.95 | 1.00 | 1.00 |
| `powers` | 0.00 | 0.00 | 0.00 | 0.95 | 1.00 | 1.00 |
| `powers_dup` | 0.00 | 0.00 | 0.00 | 0.95 | 1.00 | 1.00 |
| `profile_fast` | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| `profile_scaled` | 0.00 | 0.00 | 1.00 | 1.00 | 1.00 | 1.00 |

### madnlp (19 instances)

| Arm | τ=1.0 | τ=1.1 | τ=1.25 | τ=1.5 | τ=2.0 | τ=4.0 |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 0.21 | 0.37 | 0.84 | 0.95 | 1.00 | 1.00 |
| `powers` | 0.11 | 0.42 | 0.84 | 0.89 | 1.00 | 1.00 |
| `powers_dup` | 0.05 | 0.32 | 0.84 | 0.95 | 0.95 | 1.00 |
| `profile_fast` | 0.37 | 0.84 | 0.95 | 0.95 | 0.95 | 1.00 |
| `profile_scaled` | 0.26 | 0.58 | 0.84 | 0.95 | 0.95 | 1.00 |

## MadNLP relative to Ipopt (same models, both MUMPS)

| Arm | Instances | Geo-mean time ratio MadNLP/Ipopt | Geo-mean iteration ratio |
|---|---:|---:|---:|
| `full` | 19 | 0.288 | 0.757 |
| `powers` | 18 | 0.277 | 0.748 |
| `powers_dup` | 18 | 0.280 | 0.748 |
| `profile_fast` | 19 | 0.634 | 1.015 |
| `profile_scaled` | 19 | 0.579 | 1.020 |

## Where Ipopt spends time

From the diagnostic solve of each (instance, arm). Shares of Ipopt's own total (internal + function evaluations).

| Statistic | Median | 10th pct | 90th pct |
|---|---:|---:|---:|
| Function-evaluation share | 0.049 | 0.035 | 0.059 |
| Primal-dual system solve share | 0.821 | 0.793 | 0.905 |
| Factorizations per iteration | 1.053 | 1.047 | 1.558 |

### Cost model

Least squares on log median solve time over 188 (instance, arm) cells.

| Predictors | R² | Coefficients (intercept, …) |
|---|---:|---|
| iterations only | 0.722 | -7.644, 2.153 |
| factor size only | 0.622 | -19.768, 1.365 |
| iterations + factor size | 0.970 | -18.883, 1.623, 0.935 |
| factorizations + factor size | 0.988 | -17.739, 0.979, 0.987 |
| iterations + factor size + derivative nnz | 0.971 | -18.728, 1.634, 0.729, 0.214 |

## Objective consistency

Largest relative objective spread among solved arms per instance (local optima or loose termination).

| Solver | Instances | Median spread | Max spread | Instances with spread > 1e-4 |
|---|---:|---:|---:|---:|
| ipopt | 19 | 2.6e-08 | 6.8e-05 | 0 |
| ipopt_pivtol | 19 | 2.4e-13 | 5.7e-12 | 0 |
| madnlp | 19 | 6.1e-15 | 3.5e-05 | 0 |

## Median solve time per instance (ms)

### ipopt

| Case | Buses | Load | `full` | `powers` | `powers_dup` | `profile_fast` | `profile_scaled` |
|---|---:|---:|---:|---:|---:|---:|---:|
| 11_MVFeeder1363.bmopf.json | 358 | 0.5 | 1911.5 | 1188.6 | 1196.1 | 475.0 | 640.4 |
| 11_MVFeeder1365.bmopf.json | 198 | 0.5 | 324.4 | 338.2 | 334.2 | 202.9 | 277.6 |
| 24_MVFeeder0277.bmopf.json | 350 | 0.5 | 633.5 | 1068.5 | 1076.7 | 438.1 | 489.7 |
| 27_MVFeeder1284.bmopf.json | 323 | 0.5 | 973.3 | 704.8 | 701.8 | 416.1 | 460.3 |
| 27_MVFeeder2091.bmopf.json | 141 | 0.5 | 190.5 | 198.2 | 197.8 | 120.3 | 142.9 |
| 28_MVFeeder1378.bmopf.json | 179 | 0.5 | 358.5 | 486.4 | 484.1 | 179.0 | 214.7 |
| 52_MVFeeder0192.bmopf.json | 331 | 0.5 | 1704.2 | 2179.1 | 2167.4 | 357.7 | 368.6 |
| 53_MVFeeder1979.bmopf.json | 313 | 0.5 | 1131.6 | 1072.2 | 1074.3 | 328.9 | 380.0 |
| 75_MVFeeder0423.bmopf.json | 221 | 0.5 | 348.9 | 372.0 | 373.6 | 214.7 | 248.9 |
| 76_MVFeeder3139.bmopf.json | 149 | 0.5 | 201.1 | 462.0 | 462.2 | 137.8 | 177.8 |
| 11_MVFeeder1363.bmopf.json | 358 | 1 | 3683.4 | fail 3/3 | fail 3/3 | 447.6 | 499.2 |
| 11_MVFeeder1365.bmopf.json | 198 | 1 | 327.7 | 306.5 | 306.6 | 216.0 | 257.4 |
| 24_MVFeeder0277.bmopf.json | 350 | 1 | 979.6 | 841.5 | 850.6 | 460.8 | 473.7 |
| 27_MVFeeder1284.bmopf.json | 323 | 1 | 819.7 | 737.6 | 707.8 | 398.0 | 436.1 |
| 27_MVFeeder2091.bmopf.json | 141 | 1 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 28_MVFeeder1378.bmopf.json | 179 | 1 | 370.6 | 564.0 | 560.4 | 191.4 | 210.2 |
| 52_MVFeeder0192.bmopf.json | 331 | 1 | 2534.8 | 2510.9 | 2501.0 | 346.7 | 384.7 |
| 53_MVFeeder1979.bmopf.json | 313 | 1 | 873.2 | 1133.8 | 1143.1 | 372.5 | 411.3 |
| 75_MVFeeder0423.bmopf.json | 221 | 1 | 450.8 | 683.9 | 688.8 | 278.4 | 259.6 |
| 76_MVFeeder3139.bmopf.json | 149 | 1 | 224.6 | 270.0 | 275.0 | 153.4 | 190.9 |

### ipopt_pivtol

| Case | Buses | Load | `full` | `powers` | `powers_dup` | `profile_fast` | `profile_scaled` |
|---|---:|---:|---:|---:|---:|---:|---:|
| 11_MVFeeder1363.bmopf.json | 358 | 0.5 | 527.2 | 524.1 | 530.7 | 409.9 | 492.3 |
| 11_MVFeeder1365.bmopf.json | 198 | 0.5 | 248.7 | 248.4 | 250.9 | 185.4 | 221.2 |
| 24_MVFeeder0277.bmopf.json | 350 | 0.5 | 458.1 | 453.3 | 455.0 | 341.5 | 399.7 |
| 27_MVFeeder1284.bmopf.json | 323 | 0.5 | 506.8 | 506.2 | 508.3 | 360.2 | 429.0 |
| 27_MVFeeder2091.bmopf.json | 141 | 0.5 | 160.8 | 161.6 | 161.4 | 113.9 | 135.5 |
| 28_MVFeeder1378.bmopf.json | 179 | 0.5 | 234.9 | 233.8 | 235.2 | 169.4 | 204.4 |
| 52_MVFeeder0192.bmopf.json | 331 | 0.5 | 474.4 | 482.4 | 494.0 | 310.9 | 368.2 |
| 53_MVFeeder1979.bmopf.json | 313 | 0.5 | 433.1 | 444.8 | 443.2 | 318.3 | 375.1 |
| 75_MVFeeder0423.bmopf.json | 221 | 0.5 | 264.0 | 262.4 | 265.6 | 199.3 | 239.6 |
| 76_MVFeeder3139.bmopf.json | 149 | 0.5 | 178.2 | 182.0 | 182.4 | 132.5 | 162.9 |
| 11_MVFeeder1363.bmopf.json | 358 | 1 | 511.8 | 505.7 | 505.1 | 389.4 | 466.8 |
| 11_MVFeeder1365.bmopf.json | 198 | 1 | 260.1 | 258.4 | 259.2 | 195.7 | 229.9 |
| 24_MVFeeder0277.bmopf.json | 350 | 1 | 497.9 | 496.2 | 496.9 | 356.1 | 415.5 |
| 27_MVFeeder1284.bmopf.json | 323 | 1 | 519.6 | 523.3 | 517.9 | 360.0 | 420.3 |
| 27_MVFeeder2091.bmopf.json | 141 | 1 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 28_MVFeeder1378.bmopf.json | 179 | 1 | 247.3 | 245.5 | 249.9 | 179.8 | 211.6 |
| 52_MVFeeder0192.bmopf.json | 331 | 1 | 456.1 | 454.8 | 448.2 | 329.2 | 383.0 |
| 53_MVFeeder1979.bmopf.json | 313 | 1 | 438.2 | 496.7 | 461.0 | 340.9 | 406.7 |
| 75_MVFeeder0423.bmopf.json | 221 | 1 | 293.6 | 287.2 | 286.0 | 214.7 | 244.7 |
| 76_MVFeeder3139.bmopf.json | 149 | 1 | 208.7 | 213.9 | 206.8 | 146.0 | 182.1 |

### madnlp

| Case | Buses | Load | `full` | `powers` | `powers_dup` | `profile_fast` | `profile_scaled` |
|---|---:|---:|---:|---:|---:|---:|---:|
| 11_MVFeeder1363.bmopf.json | 358 | 0.5 | 294.2 | 281.3 | 315.8 | 295.1 | 295.1 |
| 11_MVFeeder1365.bmopf.json | 198 | 0.5 | 121.5 | 119.9 | 135.8 | 108.7 | 130.2 |
| 24_MVFeeder0277.bmopf.json | 350 | 0.5 | 271.6 | 454.4 | 277.9 | 231.6 | 288.5 |
| 27_MVFeeder1284.bmopf.json | 323 | 0.5 | 275.0 | 243.7 | 270.6 | 263.5 | 271.9 |
| 27_MVFeeder2091.bmopf.json | 141 | 0.5 | 97.9 | 79.5 | 82.4 | 70.0 | 95.1 |
| 28_MVFeeder1378.bmopf.json | 179 | 0.5 | 112.7 | 125.1 | 112.8 | 118.6 | 117.5 |
| 52_MVFeeder0192.bmopf.json | 331 | 0.5 | 417.2 | 262.3 | 461.5 | 239.4 | 222.0 |
| 53_MVFeeder1979.bmopf.json | 313 | 0.5 | 251.0 | 230.7 | 235.9 | 201.4 | 233.0 |
| 75_MVFeeder0423.bmopf.json | 221 | 0.5 | 126.6 | 143.6 | 142.8 | 120.6 | 134.7 |
| 76_MVFeeder3139.bmopf.json | 149 | 0.5 | 91.4 | 92.4 | 90.7 | 96.5 | 91.1 |
| 11_MVFeeder1363.bmopf.json | 358 | 1 | 256.2 | 269.0 | 288.9 | 286.0 | 265.3 |
| 11_MVFeeder1365.bmopf.json | 198 | 1 | 137.5 | 120.0 | 121.7 | 294.0 | 118.0 |
| 24_MVFeeder0277.bmopf.json | 350 | 1 | 266.3 | 257.1 | 287.0 | 231.9 | 229.9 |
| 27_MVFeeder1284.bmopf.json | 323 | 1 | 305.7 | 268.8 | 286.0 | 267.8 | 260.7 |
| 27_MVFeeder2091.bmopf.json | 141 | 1 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 28_MVFeeder1378.bmopf.json | 179 | 1 | 134.9 | 121.1 | 136.4 | 113.3 | 113.7 |
| 52_MVFeeder0192.bmopf.json | 331 | 1 | 257.6 | 434.8 | 278.7 | 244.4 | 221.5 |
| 53_MVFeeder1979.bmopf.json | 313 | 1 | 313.3 | 287.2 | 295.1 | 220.1 | 284.5 |
| 75_MVFeeder0423.bmopf.json | 221 | 1 | 132.9 | 150.2 | 134.2 | 134.8 | 313.5 |
| 76_MVFeeder3139.bmopf.json | 149 | 1 | 105.9 | 106.8 | 116.0 | 111.0 | 115.7 |

