# ENWL SDP tolerance sensitivity

The Ipopt point satisfies every automatically derived line LNC. The table tests whether tighter requested Mosek conic tolerances make the reported dual objective a reliable lower bound.

Only `2` of `12` runs passed the complete usability gate. Requested tolerances did not produce monotone achieved dual feasibility or termination status; they must be treated as solver requests rather than certificates.

| Formulation | LNC | Requested tolerance | Status | Usable | NLP−bound (W) | Model residual | Mosek PFEAS | Mosek DFEAS | Solve (s) |
|---|---|---:|---|---:|---:|---:|---:|---:|---:|
| ivr | baseline | 1.0e-8 | OPTIMAL | false | -1.29097 | 4.684955e-8 | 6.677437e-8 | 1.484494e-8 | 31.30802 |
| ivr | baseline | 1.0e-10 | OPTIMAL | true | 0.0001899111 | 2.078778e-11 | 8.517809e-11 | 9.331857e-8 | 31.25636 |
| ivr | baseline | 1.0e-12 | SLOW_PROGRESS | false | 0.0001899111 | 2.078778e-11 | 8.517809e-11 | 9.331857e-8 | 5.601679 |
| ivr | line_lnc | 1.0e-8 | OPTIMAL | false | -2.352154 | 4.237144e-8 | 3.284713e-8 | 8.660897e-9 | 33.88654 |
| ivr | line_lnc | 1.0e-10 | SLOW_PROGRESS | false | -0.1793407 | 3.210847e-9 | 2.5187e-9 | 2.073214e-8 | 8.059646 |
| ivr | line_lnc | 1.0e-12 | SLOW_PROGRESS | false | -0.1793407 | 3.210847e-9 | 2.5187e-9 | 2.073214e-8 | 8.035065 |
| branch_flow | baseline | 1.0e-8 | OPTIMAL | false | -0.4779811 | 6.781851e-9 | 1.470938e-8 | 2.747757e-7 | 3.312864 |
| branch_flow | baseline | 1.0e-10 | SLOW_PROGRESS | false | -0.3703122 | 5.245777e-9 | 9.940478e-9 | 1.983416e-6 | 4.275365 |
| branch_flow | baseline | 1.0e-12 | SLOW_PROGRESS | false | -0.3703122 | 5.245777e-9 | 9.940478e-9 | 1.983416e-6 | 4.230976 |
| branch_flow | line_lnc | 1.0e-8 | OPTIMAL | false | -0.7403519 | 1.632743e-9 | 1.557059e-6 | 1.983762e-7 | 4.207487 |
| branch_flow | line_lnc | 1.0e-10 | OPTIMAL | true | -0.02943012 | 5.11946e-9 | 6.243863e-8 | 5.196834e-6 | 4.413814 |
| branch_flow | line_lnc | 1.0e-12 | SLOW_PROGRESS | false | -5.82505e-5 | 6.807457e-9 | 4.000587e-9 | 0.003021694 | 5.954534 |
