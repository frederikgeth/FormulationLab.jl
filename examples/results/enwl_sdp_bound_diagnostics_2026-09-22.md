# ENWL strengthening and bound diagnostics

All objectives are reported in watts. Mosek feasibility and optimality metrics remain in the internally scaled conic model. A usable bound passes termination, primal residual, dual status, primal/dual ordering, and feasible-AC ordering checks. Ipopt supplies a checked local feasible point, not a global optimum.

Across all runs, the largest disagreement between JuMP's objective bound and Mosek's dual objective was `0.0 W`. The independently solved Ipopt voltages satisfied `5739` distinct formulation/case line-LNC instances; `0` violated a normalized cut or domain inequality. Thus the observed bound reversals are numerical certificate failures, not a wrapper bound-source mismatch or evidence that the derived LNCs exclude the reference AC points.

| Buses | Formulation | Configuration | Status | Usable | Solver bound (W) | NLP−bound (W) | Model residual | Mosek PFEAS | Mosek DFEAS | Relative gap | Build (s) | Solve (s) | Variables | LNC | RLT | Current bounds |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 178 | ivr | baseline | SLOW_PROGRESS | false | -24832.41 | -0.3331942 | 5.788925e-8 | 1.032971e-7 | 2.11243e-8 | 7.337356e-9 | 2.021972 | 7.015928 | 46728 | 0 | 0 | 0 |
| 178 | ivr | line_lnc | SLOW_PROGRESS | false | -24832.71 | -0.0356998 | 5.671208e-9 | 1.494122e-8 | 9.77436e-10 | 3.256372e-10 | 2.092253 | 6.22193 | 46599 | 530 | 0 | 0 |
| 178 | ivr | port_rlt | SLOW_PROGRESS | false | -24832.41 | -0.3331942 | 5.788925e-8 | 1.032971e-7 | 2.11243e-8 | 7.337356e-9 | 1.51331 | 6.971374 | 46728 | 0 | 0 | 0 |
| 178 | ivr | implied_current | SLOW_PROGRESS | false | -24832.12 | -0.6213048 | 2.470855e-7 | 5.409899e-7 | 6.39471e-8 | 1.860022e-8 | 1.535029 | 7.805668 | 46728 | 0 | 0 | 173 |
| 178 | ivr | all | SLOW_PROGRESS | false | -24832.21 | -0.5381119 | 9.031758e-8 | 1.359163e-7 | 1.791336e-8 | 4.072587e-9 | 1.506524 | 8.910823 | 46599 | 530 | 0 | 173 |
| 178 | branch_flow | baseline | SLOW_PROGRESS | false | -24832.73 | -0.0102054 | 1.413991e-8 | 2.286091e-8 | 1.152816e-5 | 1.534287e-10 | 1.26784 | 1.377433 | 23226 | 0 | 0 | 0 |
| 178 | branch_flow | line_lnc | OPTIMAL | false | -24832.68 | -0.060365 | 7.517687e-8 | 2.795066e-7 | 1.130616e-6 | 1.514266e-11 | 2.034006 | 1.249226 | 23226 | 531 | 0 | 0 |
| 178 | branch_flow | port_rlt | SLOW_PROGRESS | false | -24832.73 | -0.0102054 | 1.413991e-8 | 2.286091e-8 | 1.152816e-5 | 1.534287e-10 | 1.463844 | 1.384249 | 23226 | 0 | 0 | 0 |
| 178 | branch_flow | implied_current | SLOW_PROGRESS | false | -24832.73 | -0.0102054 | 1.413991e-8 | 2.286091e-8 | 1.152816e-5 | 1.534287e-10 | 1.475563 | 1.383386 | 23226 | 0 | 0 | 0 |
| 178 | branch_flow | all | OPTIMAL | false | -24832.68 | -0.060365 | 7.517687e-8 | 2.795066e-7 | 1.130616e-6 | 1.514266e-11 | 1.849973 | 1.244661 | 23226 | 531 | 0 | 0 |
| 244 | ivr | baseline | SLOW_PROGRESS | false | -10552.85 | 131.6614 | 2.472357e-8 | 5.135976e-8 | 8.768849e-9 | 2.217175e-9 | 1.974939 | 1.859513 | 27192 | 0 | 0 | 0 |
| 244 | ivr | line_lnc | SLOW_PROGRESS | false | -10552.91 | 131.7219 | 4.237735e-8 | 4.824136e-8 | 1.14335e-8 | 8.480091e-12 | 1.788587 | 3.472192 | 25911 | 728 | 0 | 0 |
| 244 | ivr | port_rlt | SLOW_PROGRESS | false | -10552.85 | 131.6614 | 2.472357e-8 | 5.135976e-8 | 8.768849e-9 | 2.217175e-9 | 1.765504 | 1.818568 | 27192 | 0 | 0 | 0 |
| 244 | ivr | implied_current | SLOW_PROGRESS | false | -10440.76 | 19.57829 | 3.025944e-8 | 4.891679e-8 | 5.403429e-9 | 2.132681e-9 | 1.745254 | 2.975498 | 27192 | 0 | 0 | 124 |
| 244 | ivr | all | SLOW_PROGRESS | false | -10440.83 | 19.64206 | 2.164246e-8 | 3.701003e-8 | 6.799374e-9 | 1.124222e-12 | 1.744858 | 2.477922 | 25911 | 728 | 0 | 124 |
| 244 | branch_flow | baseline | SLOW_PROGRESS | false | -10599.4 | 178.2109 | 3.202515e-7 | 3.66546e-7 | 3.47377e-8 | 1.486291e-8 | 1.852162 | 2.250558 | 26736 | 0 | 0 | 0 |
| 244 | branch_flow | line_lnc | SLOW_PROGRESS | false | -10601.1 | 179.9119 | 3.606938e-7 | 3.427314e-7 | 6.204246e-7 | 4.949182e-11 | 3.060595 | 2.634684 | 26736 | 729 | 0 | 0 |
| 244 | branch_flow | port_rlt | SLOW_PROGRESS | false | -10599.4 | 178.2109 | 3.202515e-7 | 3.66546e-7 | 3.47377e-8 | 1.486291e-8 | 2.168308 | 2.232521 | 26736 | 0 | 0 | 0 |
| 244 | branch_flow | implied_current | SLOW_PROGRESS | false | -10599.4 | 178.2109 | 3.202515e-7 | 3.66546e-7 | 3.47377e-8 | 1.486291e-8 | 1.963653 | 2.236078 | 26736 | 0 | 0 | 0 |
| 244 | branch_flow | all | SLOW_PROGRESS | false | -10601.1 | 179.9119 | 3.606938e-7 | 3.427314e-7 | 6.204246e-7 | 4.949182e-11 | 3.052704 | 2.688594 | 26736 | 729 | 0 | 0 |
| 538 | ivr | baseline | OPTIMAL | true | -44545.19 | 0.0001899111 | 2.078778e-11 | 8.517809e-11 | 9.331857e-8 | 2.50033e-14 | 8.160614 | 34.77342 | 80757 | 0 | 0 | 0 |
| 538 | ivr | line_lnc | OPTIMAL | false | -44544.99 | -0.2020103 | 3.616478e-9 | 2.816873e-9 | 5.303636e-9 | 8.992125e-11 | 7.98042 | 35.34927 | 74314 | 1610 | 0 | 0 |
| 538 | ivr | port_rlt | OPTIMAL | true | -44545.19 | 0.0001899111 | 2.078778e-11 | 8.517809e-11 | 9.331857e-8 | 2.50033e-14 | 8.158015 | 34.55882 | 80757 | 0 | 0 | 0 |
| 538 | ivr | implied_current | SLOW_PROGRESS | false | -44539.89 | -5.296068 | 1.972457e-7 | 3.711406e-7 | 6.072871e-8 | 1.679167e-8 | 8.155457 | 7.764924 | 80757 | 0 | 0 | 304 |
| 538 | ivr | all | SLOW_PROGRESS | false | -44535.99 | -9.19781 | 2.917909e-7 | 2.866376e-7 | 3.491652e-8 | 3.932177e-9 | 8.06955 | 8.475484 | 74314 | 1610 | 0 | 304 |
| 538 | branch_flow | baseline | SLOW_PROGRESS | false | -44544.82 | -0.3703122 | 5.245777e-9 | 9.940478e-9 | 1.983416e-6 | 1.056773e-9 | 6.994872 | 4.264361 | 60384 | 0 | 0 | 0 |
| 538 | branch_flow | line_lnc | OPTIMAL | false | -44544.45 | -0.7403519 | 1.632743e-9 | 1.557059e-6 | 1.983762e-7 | 1.101272e-9 | 9.781179 | 4.28353 | 60384 | 1611 | 0 | 0 |
| 538 | branch_flow | port_rlt | SLOW_PROGRESS | false | -44544.82 | -0.3703122 | 5.245777e-9 | 9.940478e-9 | 1.983416e-6 | 1.056773e-9 | 6.125414 | 4.272352 | 60384 | 0 | 0 | 0 |
| 538 | branch_flow | implied_current | SLOW_PROGRESS | false | -44544.82 | -0.3703122 | 5.245777e-9 | 9.940478e-9 | 1.983416e-6 | 1.056773e-9 | 6.111025 | 4.263397 | 60384 | 0 | 0 | 0 |
| 538 | branch_flow | all | OPTIMAL | false | -44544.45 | -0.7403519 | 1.632743e-9 | 1.557059e-6 | 1.983762e-7 | 1.101272e-9 | 9.752879 | 4.303455 | 60384 | 1611 | 0 | 0 |
