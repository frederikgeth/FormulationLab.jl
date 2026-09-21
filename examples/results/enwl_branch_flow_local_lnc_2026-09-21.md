# BranchFlowSDP line-local LNC regression

The input and objective use SI units. BranchFlowSDP uses per-unit coordinates internally. An SDP row is accepted only after an `OPTIMAL` termination and a maximum scaled JuMP residual no larger than `1e-7`. Ipopt is a locally feasible AC reference, not a global certificate.

## 10 kVA ablation

| Configuration | Accepted | Objective (W) | NLP−SDP (W) | Residual | Variables | Constraints | Solve (s) | LNC applied/skipped |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | true | -1369.012 | -0.04416165 | 7.564282e-9 | 10548 | 4664 | 1.682495 | 0/0 |
| line_lnc | true | -1369.052 | -0.004350032 | 1.924996e-8 | 10548 | 7229 | 0.5640242 | 285/285 |
| all | true | -1369.038 | -0.01884264 | 2.19462e-8 | 10548 | 7514 | 0.6424616 | 285/285 |

## Power-base sensitivity with all strengthening

| Base (VA) | Accepted | Objective (W) | NLP−SDP (W) | Within ordering tolerance | Residual | Solve (s) |
|---:|---:|---:|---:|---:|---:|---:|
| 3000 | true | -1369.049 | -0.007316122 | true | 1.609141e-8 | 0.7294593 |
| 10000 | true | -1369.038 | -0.01884264 | false | 2.19462e-8 | 0.6424616 |
| 30000 | true | -1369.029 | -0.02754016 | false | 1.72453e-9 | 0.5077446 |

Accepted-objective span: 0.02022404 W. The ordering tolerance is 0.01369056 W.
