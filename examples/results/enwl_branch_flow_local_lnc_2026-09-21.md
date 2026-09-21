# BranchFlowSDP local-strengthening regression

The input and objective use SI units. BranchFlowSDP uses per-unit coordinates internally. An SDP row is accepted only after an `OPTIMAL` termination and a maximum scaled JuMP residual no larger than `1e-7`. Ipopt is a locally feasible AC reference, not a global certificate.

## 10 kVA ablation

| Configuration | Accepted | Objective (W) | NLP−SDP (W) | Residual | Variables | Constraints | Solve (s) | LNC applied/skipped |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | true | -1369.012 | -0.04416165 | 7.564282e-9 | 10548 | 4664 | 1.564012 | 0/0 |
| line_lnc | true | -1369.052 | -0.004350032 | 1.924996e-8 | 10548 | 7229 | 0.5410517 | 285/285 |
| all | true | -1369.038 | -0.01884264 | 2.19462e-8 | 10548 | 7514 | 0.5712529 | 285/285 |
| tcr | true | -1368.951 | -0.1056106 | 6.345026e-9 | 21099 | 7422 | 0.9131438 | 0/0 |
| tcr_all | true | -1368.989 | -0.06765946 | 1.114135e-8 | 21099 | 10272 | 1.113384 | 285/285 |

## Power-base sensitivity with all strengthening

| Configuration | Base (VA) | Accepted | Objective (W) | NLP−SDP (W) | Within ordering tolerance | Residual | Solve (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| all | 3000 | true | -1369.049 | -0.007316122 | true | 1.609141e-8 | 0.707341 |
| all | 10000 | true | -1369.038 | -0.01884264 | false | 2.19462e-8 | 0.5712529 |
| all | 30000 | true | -1369.029 | -0.02754016 | false | 1.72453e-9 | 0.4520144 |
| tcr_all | 3000 | true | -1369.025 | -0.03158361 | false | 2.860121e-8 | 1.475114 |
| tcr_all | 10000 | true | -1368.989 | -0.06765946 | false | 1.114135e-8 | 1.113384 |
| tcr_all | 30000 | true | -1369.026 | -0.03049971 | false | 5.294075e-9 | 0.8885988 |

Accepted-objective spans: all = 0.02022404 W; tcr_all = 0.03715975 W. The ordering tolerance is 0.01369056 W.
