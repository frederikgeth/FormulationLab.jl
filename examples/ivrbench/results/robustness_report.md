# IVR benchmark report

Sources: robustness.jsonl. Times are optimizer-call wall time; build excluded.

## Noise floor

`powers_dup` builds the identical model as `powers`. The spread of their median ratio is the smallest arm difference worth interpreting.

| Solver | Instances | Median abs. deviation | 90th pct abs. deviation | Max abs. deviation |
|---|---:|---:|---:|---:|
| ipopt | 19 | 0.4% | 1.6% | 2.2% |
| madnlp | 20 | 10.9% | 46.8% | 110.0% |

## Arms relative to the `powers` control

Geometric-mean ratio of median solve time over instances both arms solve (below 1 = faster). Success counts every instance.

### ipopt

| Arm | Solved | Geo-mean time ratio | Faster >5% | Slower >5% | Median iterations | Geo-mean iteration ratio |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 20/34 | 0.875 | 11 | 5 | 26 | 0.922 |
| `powers` | 19/34 | 1.000 | 0 | 0 | 31 | 1.000 |
| `powers_dup` | 19/34 | 0.997 | 0 | 0 | 31 | 1.000 |
| `powers_zero` | 19/34 | 1.200 | 7 | 11 | 36 | 1.274 |
| `reduced` | 20/34 | 1.187 | 7 | 11 | 37 | 1.244 |
| `reduced_broad` | 15/34 | 1.735 | 3 | 12 | 40 | 1.667 |
| `reduced_scaled` | 20/34 | 0.404 | 19 | 0 | 20 | 0.685 |
| `reduced_txelim` | 20/34 | 1.249 | 7 | 11 | 38 | 1.293 |

### madnlp

| Arm | Solved | Geo-mean time ratio | Faster >5% | Slower >5% | Median iterations | Geo-mean iteration ratio |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 20/34 | 1.005 | 10 | 8 | 22 | 1.000 |
| `powers` | 20/34 | 1.000 | 0 | 0 | 22 | 1.000 |
| `powers_dup` | 20/34 | 0.997 | 8 | 5 | 22 | 1.000 |
| `powers_zero` | 20/34 | 0.883 | 12 | 4 | 22 | 1.000 |
| `reduced` | 20/34 | 0.953 | 11 | 7 | 22 | 1.000 |
| `reduced_broad` | 20/34 | 1.624 | 0 | 19 | 25 | 1.221 |
| `reduced_scaled` | 20/34 | 0.799 | 17 | 0 | 20 | 0.952 |
| `reduced_txelim` | 20/34 | 1.010 | 8 | 8 | 22 | 1.000 |

## Performance profiles

Fraction of instances an arm solves within τ × the best arm's median time (Dolan–Moré). Unsolved instances never count. Instances no arm solves are excluded.

### ipopt (20 instances)

| Arm | τ=1.0 | τ=1.1 | τ=1.25 | τ=1.5 | τ=2.0 | τ=4.0 |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 0.00 | 0.00 | 0.05 | 0.15 | 0.50 | 0.80 |
| `powers` | 0.00 | 0.00 | 0.00 | 0.10 | 0.40 | 0.80 |
| `powers_dup` | 0.00 | 0.00 | 0.00 | 0.10 | 0.40 | 0.80 |
| `powers_zero` | 0.00 | 0.00 | 0.00 | 0.10 | 0.15 | 0.70 |
| `reduced` | 0.00 | 0.00 | 0.00 | 0.05 | 0.20 | 0.75 |
| `reduced_broad` | 0.00 | 0.00 | 0.00 | 0.00 | 0.10 | 0.45 |
| `reduced_scaled` | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| `reduced_txelim` | 0.00 | 0.00 | 0.00 | 0.10 | 0.20 | 0.65 |

### madnlp (20 instances)

| Arm | τ=1.0 | τ=1.1 | τ=1.25 | τ=1.5 | τ=2.0 | τ=4.0 |
|---|---:|---:|---:|---:|---:|---:|
| `full` | 0.05 | 0.20 | 0.40 | 0.85 | 1.00 | 1.00 |
| `powers` | 0.00 | 0.20 | 0.55 | 0.75 | 1.00 | 1.00 |
| `powers_dup` | 0.00 | 0.20 | 0.75 | 0.85 | 0.90 | 1.00 |
| `powers_zero` | 0.15 | 0.55 | 0.85 | 0.90 | 1.00 | 1.00 |
| `reduced` | 0.00 | 0.40 | 0.75 | 0.80 | 1.00 | 1.00 |
| `reduced_broad` | 0.00 | 0.00 | 0.00 | 0.10 | 0.50 | 1.00 |
| `reduced_scaled` | 0.65 | 0.95 | 1.00 | 1.00 | 1.00 | 1.00 |
| `reduced_txelim` | 0.15 | 0.35 | 0.70 | 0.75 | 0.90 | 1.00 |

## MadNLP relative to Ipopt (same models, both MUMPS)

| Arm | Instances | Geo-mean time ratio MadNLP/Ipopt | Geo-mean iteration ratio |
|---|---:|---:|---:|
| `full` | 20 | 0.306 | 0.754 |
| `powers` | 19 | 0.281 | 0.733 |
| `powers_dup` | 19 | 0.288 | 0.733 |
| `powers_zero` | 19 | 0.214 | 0.580 |
| `reduced` | 20 | 0.223 | 0.577 |
| `reduced_broad` | 15 | 0.287 | 0.559 |
| `reduced_scaled` | 20 | 0.564 | 1.014 |
| `reduced_txelim` | 20 | 0.225 | 0.556 |

## Where Ipopt spends time

From the diagnostic solve of each (instance, arm). Shares of Ipopt's own total (internal + function evaluations).

| Statistic | Median | 10th pct | 90th pct |
|---|---:|---:|---:|
| Function-evaluation share | 0.033 | 0.022 | 0.046 |
| Primal-dual system solve share | 0.905 | 0.833 | 0.942 |
| Factorizations per iteration | 1.559 | 1.053 | 2.299 |

### Cost model

Least squares on log median solve time over 151 (instance, arm) cells.

| Predictors | R² | Coefficients (intercept, …) |
|---|---:|---|
| iterations only | 0.809 | -6.056, 1.628 |
| factor size only | 0.442 | -20.489, 1.465 |
| iterations + factor size | 0.973 | -18.075, 1.387, 0.937 |
| factorizations + factor size | 0.986 | -17.452, 0.872, 0.995 |
| iterations + factor size + derivative nnz | 0.977 | -17.886, 1.416, 0.792, 0.140 |

## Objective consistency

Largest relative objective spread among solved arms per instance (local optima or loose termination).

| Solver | Instances | Median spread | Max spread | Instances with spread > 1e-4 |
|---|---:|---:|---:|---:|
| ipopt | 20 | 5.1e-05 | 9.9e-03 | 7 |
| madnlp | 20 | 6.7e-11 | 1.9e-03 | 3 |

## Median solve time per instance (ms)

### ipopt

| Case | Buses | Load | `full` | `powers` | `powers_dup` | `powers_zero` | `reduced` | `reduced_broad` | `reduced_scaled` | `reduced_txelim` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 11_MVFeeder1363.bmopf.json | 358 | 0.5 | 1843.9 | 1150.7 | 1147.5 | 1900.7 | 1890.6 | fail 3/3 | 421.7 | 2042.4 |
| 11_MVFeeder1365.bmopf.json | 198 | 0.5 | 320.4 | 329.8 | 324.9 | 647.8 | 656.2 | 1955.9 | 193.8 | 761.2 |
| 24_MVFeeder0277.bmopf.json | 350 | 0.5 | 607.1 | 1020.1 | 1023.5 | 1187.7 | 752.6 | 1217.0 | 364.9 | 870.2 |
| 27_MVFeeder1284.bmopf.json | 323 | 0.5 | 953.0 | 679.3 | 681.9 | 1632.0 | 1619.6 | fail 3/3 | 367.7 | 1921.9 |
| 27_MVFeeder2091.bmopf.json | 141 | 0.5 | 185.9 | 197.2 | 193.2 | 400.3 | 402.1 | 245.4 | 115.5 | 269.6 |
| 28_MVFeeder1378.bmopf.json | 179 | 0.5 | 368.6 | 488.3 | 490.0 | 448.6 | 516.2 | 552.4 | 193.6 | 494.2 |
| 52_MVFeeder0192.bmopf.json | 331 | 0.5 | 1647.9 | 2062.5 | 2055.8 | fail 3/3 | 4427.8 | fail 3/3 | 372.3 | 4584.8 |
| 53_MVFeeder1979.bmopf.json | 313 | 0.5 | 1134.8 | 1065.9 | 1063.2 | 767.4 | 792.6 | 1705.9 | 322.5 | 606.9 |
| 75_MVFeeder0423.bmopf.json | 221 | 0.5 | 346.0 | 375.5 | 372.3 | 334.2 | 331.9 | 817.9 | 210.5 | 297.1 |
| 76_MVFeeder3139.bmopf.json | 149 | 0.5 | 198.1 | 465.0 | 469.8 | 1038.2 | 537.0 | 294.3 | 156.8 | 683.7 |
| 11_MVFeeder1363.bmopf.json | 358 | 1 | 3529.4 | fail 3/3 | fail 3/3 | 2159.2 | 2155.5 | fail 3/3 | 430.8 | 2293.9 |
| 11_MVFeeder1365.bmopf.json | 198 | 1 | 316.4 | 302.6 | 299.1 | 808.2 | 809.9 | 2186.6 | 211.9 | 699.8 |
| 24_MVFeeder0277.bmopf.json | 350 | 1 | 929.5 | 816.3 | 798.7 | 906.4 | 1465.2 | 690.1 | 441.3 | 1270.0 |
| 27_MVFeeder1284.bmopf.json | 323 | 1 | 788.6 | 690.9 | 691.8 | 1029.0 | 1032.7 | 5308.4 | 410.8 | 873.3 |
| 27_MVFeeder2091.bmopf.json | 141 | 1 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 28_MVFeeder1378.bmopf.json | 179 | 1 | 375.4 | 573.3 | 569.1 | 480.1 | 358.1 | 1398.5 | 205.8 | 335.3 |
| 52_MVFeeder0192.bmopf.json | 331 | 1 | 2431.1 | 2400.5 | 2392.6 | 3683.9 | 2387.6 | fail 3/3 | 579.4 | 3416.6 |
| 53_MVFeeder1979.bmopf.json | 313 | 1 | 859.5 | 1115.7 | 1115.6 | 853.7 | 860.2 | 1643.6 | 360.1 | 925.6 |
| 75_MVFeeder0423.bmopf.json | 221 | 1 | 439.4 | 664.5 | 662.5 | 293.8 | 365.6 | 726.8 | 216.5 | 308.8 |
| 76_MVFeeder3139.bmopf.json | 149 | 1 | 228.5 | 274.5 | 277.9 | 488.5 | 528.8 | 403.3 | 186.0 | 756.4 |
| 11_MVFeeder1365.bmopf.json | 198 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 27_MVFeeder1284.bmopf.json | 323 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 27_MVFeeder2091.bmopf.json | 141 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 28_MVFeeder1378.bmopf.json | 179 | 1.5 | 571.4 | 843.0 | 849.7 | 271.4 | 297.1 | 549.3 | 199.6 | 708.2 |
| 53_MVFeeder1979.bmopf.json | 313 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 75_MVFeeder0423.bmopf.json | 221 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 76_MVFeeder3139.bmopf.json | 149 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 11_MVFeeder1365.bmopf.json | 198 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 27_MVFeeder1284.bmopf.json | 323 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 27_MVFeeder2091.bmopf.json | 141 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 28_MVFeeder1378.bmopf.json | 179 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 53_MVFeeder1979.bmopf.json | 313 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 75_MVFeeder0423.bmopf.json | 221 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 76_MVFeeder3139.bmopf.json | 149 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |

### madnlp

| Case | Buses | Load | `full` | `powers` | `powers_dup` | `powers_zero` | `reduced` | `reduced_broad` | `reduced_scaled` | `reduced_txelim` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 11_MVFeeder1363.bmopf.json | 358 | 0.5 | 415.2 | 294.0 | 415.5 | 277.7 | 281.3 | 415.6 | 254.8 | 404.5 |
| 11_MVFeeder1365.bmopf.json | 198 | 0.5 | 130.7 | 113.2 | 113.3 | 121.4 | 122.8 | 183.7 | 97.6 | 107.8 |
| 24_MVFeeder0277.bmopf.json | 350 | 0.5 | 247.4 | 285.0 | 246.6 | 378.6 | 240.7 | 527.2 | 219.1 | 235.3 |
| 27_MVFeeder1284.bmopf.json | 323 | 0.5 | 409.3 | 273.5 | 271.0 | 266.7 | 433.0 | 657.9 | 242.3 | 263.1 |
| 27_MVFeeder2091.bmopf.json | 141 | 0.5 | 79.3 | 78.5 | 82.3 | 75.1 | 72.5 | 171.3 | 68.6 | 85.3 |
| 28_MVFeeder1378.bmopf.json | 179 | 0.5 | 145.5 | 113.9 | 115.5 | 103.9 | 127.1 | 199.8 | 105.8 | 150.0 |
| 52_MVFeeder0192.bmopf.json | 331 | 0.5 | 376.5 | 214.2 | 230.2 | 219.3 | 369.7 | 645.7 | 198.5 | 380.2 |
| 53_MVFeeder1979.bmopf.json | 313 | 0.5 | 236.1 | 377.4 | 246.6 | 195.5 | 224.2 | 523.3 | 207.4 | 191.5 |
| 75_MVFeeder0423.bmopf.json | 221 | 0.5 | 154.1 | 119.7 | 120.9 | 127.3 | 136.6 | 216.4 | 114.6 | 138.3 |
| 76_MVFeeder3139.bmopf.json | 149 | 0.5 | 109.1 | 119.9 | 92.2 | 85.7 | 83.8 | 174.3 | 78.3 | 95.8 |
| 11_MVFeeder1363.bmopf.json | 358 | 1 | 245.4 | 397.2 | 259.3 | 380.7 | 250.8 | 395.3 | 258.3 | 246.8 |
| 11_MVFeeder1365.bmopf.json | 198 | 1 | 131.6 | 151.6 | 297.3 | 126.3 | 128.9 | 170.6 | 119.7 | 275.6 |
| 24_MVFeeder0277.bmopf.json | 350 | 1 | 247.9 | 389.4 | 264.6 | 239.0 | 265.9 | 526.1 | 246.8 | 235.1 |
| 27_MVFeeder1284.bmopf.json | 323 | 1 | 268.6 | 293.3 | 284.6 | 267.6 | 398.1 | 616.4 | 250.4 | 400.8 |
| 27_MVFeeder2091.bmopf.json | 141 | 1 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 28_MVFeeder1378.bmopf.json | 179 | 1 | 153.0 | 137.5 | 120.0 | 144.7 | 117.1 | 198.2 | 137.0 | 112.7 |
| 52_MVFeeder0192.bmopf.json | 331 | 1 | 254.5 | 269.1 | 242.2 | 228.7 | 367.2 | 427.3 | 203.5 | 251.3 |
| 53_MVFeeder1979.bmopf.json | 313 | 1 | 272.0 | 259.4 | 283.6 | 240.0 | 228.5 | 296.1 | 215.0 | 246.9 |
| 75_MVFeeder0423.bmopf.json | 221 | 1 | 153.4 | 134.6 | 133.9 | 127.0 | 130.9 | 237.0 | 134.1 | 131.0 |
| 76_MVFeeder3139.bmopf.json | 149 | 1 | 122.5 | 141.3 | 296.8 | 100.3 | 113.6 | 255.5 | 91.9 | 110.7 |
| 11_MVFeeder1365.bmopf.json | 198 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 27_MVFeeder1284.bmopf.json | 323 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 27_MVFeeder2091.bmopf.json | 141 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 28_MVFeeder1378.bmopf.json | 179 | 1.5 | 145.2 | 158.3 | 139.6 | 115.1 | 130.8 | 227.5 | 119.1 | 304.2 |
| 53_MVFeeder1979.bmopf.json | 313 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 75_MVFeeder0423.bmopf.json | 221 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 76_MVFeeder3139.bmopf.json | 149 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 11_MVFeeder1365.bmopf.json | 198 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 27_MVFeeder1284.bmopf.json | 323 | 2 | fail 3/3 | fail 3/3 | fail 2/2 | fail 2/2 | fail 2/2 | fail 2/2 | fail 3/3 | fail 2/2 |
| 27_MVFeeder2091.bmopf.json | 141 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 28_MVFeeder1378.bmopf.json | 179 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 53_MVFeeder1979.bmopf.json | 313 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 75_MVFeeder0423.bmopf.json | 221 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 76_MVFeeder3139.bmopf.json | 149 | 2 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |

