# BranchFlowSDP TCR voltage-skeleton audit

BMOPFTools/Ipopt supplies a locally feasible AC point on the same normalized, Kron-reduced input. The exact lift uses `[1;v][1;v]ᴴ` for every local TCR block; it tests validity of the new voltage constraints, not every pre-existing BranchFlow equation.

- Ipopt objective: -1369.056 W
- Ipopt maximum model residual: 2.620126e-14
- Exact local blocks: 95
- Minimum exact-lift eigenvalue: -2.213581e-15
- Maximum source-anchor mismatch: 0.0 V

| Fixed quantities | Status | Accepted | Objective (W) | NLP−SDP (W) | Residual |
|---|---|---:|---:|---:|---:|
| none | OPTIMAL | true | -1368.951 | -0.1056106 | 6.345026e-9 |
| first-order voltage | OPTIMAL | true | -1369.056 | -0.0005114154 | 8.037429e-9 |
| first and second voltage moments | OPTIMAL | true | -1369.056 | -8.415679e-6 | 3.687831e-9 |

A PSD exact lift establishes that the TCR voltage block itself does not exclude the Ipopt voltage point. A failure after fixing all voltage moments instead points to a mismatch elsewhere in the BranchFlow and BMOPFTools component models; a feasible solve with unstable ordering points toward conic conditioning or solver accuracy. For a minimization, the free model cannot have a higher true optimum than the same model with the first-order voltages fixed; a reported reversal is therefore a direct numerical monotonicity failure.
