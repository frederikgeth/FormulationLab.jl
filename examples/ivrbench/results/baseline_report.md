# IVR benchmark report

Sources: baseline.jsonl. Times are optimizer-call wall time; build excluded.

## Noise floor

`powers_dup` builds the identical model as `powers`. The spread of their median ratio is the smallest arm difference worth interpreting.

| Solver | Instances | Median abs. deviation | 90th pct abs. deviation | Max abs. deviation |
|---|---:|---:|---:|---:|

## Arms relative to the `powers` control

Geometric-mean ratio of median solve time over instances both arms solve (below 1 = faster). Success counts every instance.

### ipopt

| Arm | Solved | Geo-mean time ratio | Faster >5% | Slower >5% | Median iterations | Geo-mean iteration ratio |
|---|---:|---:|---:|---:|---:|---:|
| `bmopftools` | 6/12 | 0.864 | 2 | 3 | 36 | 1.213 |
| `full` | 6/12 | 1.222 | 2 | 2 | 40 | 1.183 |
| `powers` | 5/12 | 1.000 | 0 | 0 | 31 | 1.000 |
| `reduced_scaled` | 6/12 | 0.428 | 5 | 0 | 20 | 0.707 |

## Performance profiles

Fraction of instances an arm solves within τ × the best arm's median time (Dolan–Moré). Unsolved instances never count. Instances no arm solves are excluded.

### ipopt (6 instances)

| Arm | τ=1.0 | τ=1.1 | τ=1.25 | τ=1.5 | τ=2.0 | τ=4.0 |
|---|---:|---:|---:|---:|---:|---:|
| `bmopftools` | 0.00 | 0.00 | 0.00 | 0.17 | 0.50 | 1.00 |
| `full` | 0.00 | 0.00 | 0.00 | 0.00 | 0.17 | 0.67 |
| `powers` | 0.00 | 0.00 | 0.00 | 0.00 | 0.33 | 0.83 |
| `reduced_scaled` | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |

## Objective consistency

Largest relative objective spread among solved arms per instance (local optima or loose termination).

| Solver | Instances | Median spread | Max spread | Instances with spread > 1e-4 |
|---|---:|---:|---:|---:|
| ipopt | 6 | 1.2e-04 | 2.3e-04 | 3 |

## Median solve time per instance (ms)

### ipopt

| Case | Buses | Load | `bmopftools` | `full` | `powers` | `reduced_scaled` |
|---|---:|---:|---:|---:|---:|---:|
| 53_MVFeeder0641.bmopf.json | 1583 | 1 | 7490.5 | 15542.4 | 6510.9 | 2193.4 |
| 76_MVFeeder0812.bmopf.json | 995 | 1 | 3514.6 | 11666.2 | fail 3/3 | 1564.1 |
| 84_MVFeeder0460.bmopf.json | 248 | 1 | 583.2 | 969.6 | 767.1 | 337.1 |
| 84_MVFeeder2024.bmopf.json | 110 | 1 | 191.0 | 156.7 | 167.9 | 103.4 |
| 84_MVFeeder2628.bmopf.json | 498 | 1 | 1122.0 | 2540.1 | 2713.3 | 829.2 |
| 84_MVFeeder2809.bmopf.json | 701 | 1 | 1962.1 | 1735.0 | 1679.2 | 865.8 |
| 53_MVFeeder0641.bmopf.json | 1583 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 76_MVFeeder0812.bmopf.json | 995 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 84_MVFeeder0460.bmopf.json | 248 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 84_MVFeeder2024.bmopf.json | 110 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 84_MVFeeder2628.bmopf.json | 498 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |
| 84_MVFeeder2809.bmopf.json | 701 | 1.5 | fail 3/3 | fail 3/3 | fail 3/3 | fail 3/3 |

