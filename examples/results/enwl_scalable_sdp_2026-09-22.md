# Scalable ENWL SDP ladder

Inputs and reported objectives use SI units; both SDP formulations use per-unit coordinates internally. IVRSDP uses its automatic chordal profile, while BranchFlowSDP uses component-local moments. A usable bound requires optimal termination, a feasible dual status, a finite lower bound, original-model residual at most `1e-7`, consistent primal/dual ordering, and lower-bound ordering against the feasible Ipopt objective. Ipopt remains a local feasible reference, not a global certificate. AC feasibility of the recovered rank-one candidate is reported separately.

| Case | Buses | Formulation | Base (VA) | Reps | Status | Usable bound | Solver bound report (W) | NLP−bound (W) | Residual | AC recovery | Build (s) | Solve (s) | Variables | Decomposition | Cliques / order |
|---|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|
| `network_18_Feeder_9.json` | 96 | ivr | 17594.105263157893 | 3 | OPTIMAL | false | -1369.044 | -0.01257254 | 1.616867e-8 | false | 0.4272172 | 0.6189975 | 8830 | chordal | 151 / 3–9 |
| `network_18_Feeder_9.json` | 96 | branch_flow | 17594.105263157893 | 3 | OPTIMAL | false | -1369.04 | -0.01648455 | 1.303693e-9 | true | 0.5704454 | 0.4444898 | 10548 | local | — |
| `network_18_Feeder_9.json` | 96 | ivr | 5864.701754385964 | 1 | OPTIMAL | true | -1369.052 | -0.004315982 | 1.496667e-9 | false | 0.4337012 | 0.6871355 | 8830 | chordal | 151 / 3–9 |
| `network_18_Feeder_9.json` | 96 | branch_flow | 5864.701754385964 | 1 | OPTIMAL | true | -1369.054 | -0.002627979 | 1.299166e-8 | true | 0.5464071 | 0.5233209 | 10548 | local | — |
| `network_18_Feeder_9.json` | 96 | ivr | 52782.31578947368 | 1 | OPTIMAL | true | -1369.054 | -0.002245656 | 3.697081e-10 | false | 0.4093501 | 0.7060121 | 8830 | chordal | 151 / 3–9 |
| `network_18_Feeder_9.json` | 96 | branch_flow | 52782.31578947368 | 1 | OPTIMAL | true | -1369.054 | -0.002557725 | 1.196823e-9 | true | 0.5424341 | 0.4378248 | 10548 | local | — |
| `Network_14_Feeder_1.json` | 134 | ivr | 24000 | 3 | OPTIMAL | false | -10522.71 | -0.02321969 | 8.746572e-9 | false | 0.683188 | 1.55533 | 15641 | chordal | 223 / 3–10 |
| `Network_14_Feeder_1.json` | 134 | branch_flow | 24000 | 3 | OPTIMAL | true | -10522.73 | -0.003660713 | 7.955927e-9 | true | 0.9756002 | 0.8951924 | 14826 | local | — |
| `Network_14_Feeder_1.json` | 134 | ivr | 8000 | 1 | OPTIMAL | true | -10522.73 | -0.00117816 | 1.474782e-8 | false | 0.7556514 | 1.558727 | 15641 | chordal | 223 / 3–10 |
| `Network_14_Feeder_1.json` | 134 | branch_flow | 8000 | 1 | OPTIMAL | true | -10522.73 | -0.0009091145 | 1.157856e-8 | true | 0.9006355 | 1.171454 | 14826 | local | — |
| `Network_14_Feeder_1.json` | 134 | ivr | 72000 | 1 | OPTIMAL | false | -10522.72 | -0.01632576 | 1.550798e-9 | false | 0.7369433 | 1.636362 | 15641 | chordal | 223 / 3–10 |
| `Network_14_Feeder_1.json` | 134 | branch_flow | 72000 | 1 | OPTIMAL | true | -10522.73 | -0.00496076 | 6.543085e-9 | true | 0.8991832 | 0.7428277 | 14826 | local | — |
| `network_13_Feeder_4.json` | 178 | ivr | 58666.666666666664 | 3 | SLOW_PROGRESS | false | -24832.21 | -0.5381119 | 9.031758e-8 | false | 1.412691 | 8.511215 | 46599 | chordal | 404 / 0–16 |
| `network_13_Feeder_4.json` | 178 | branch_flow | 58666.666666666664 | 3 | OPTIMAL | false | -24832.68 | -0.060365 | 7.517687e-8 | false | 1.76864 | 1.188209 | 23226 | local | — |
| `network_13_Feeder_4.json` | 178 | ivr | 19555.555555555555 | 1 | SLOW_PROGRESS | false | -24832.58 | -0.1671581 | 1.179032e-6 | false | 1.591114 | 8.52002 | 46599 | chordal | 404 / 0–16 |
| `network_13_Feeder_4.json` | 178 | branch_flow | 19555.555555555555 | 1 | OPTIMAL | false | -24832.71 | -0.03620821 | 2.041348e-7 | false | 1.552469 | 1.230408 | 23226 | local | — |
| `network_13_Feeder_4.json` | 178 | ivr | 176000 | 1 | SLOW_PROGRESS | false | -24831.05 | -1.693269 | 1.888372e-7 | false | 1.611293 | 9.782366 | 46599 | chordal | 404 / 0–16 |
| `network_13_Feeder_4.json` | 178 | branch_flow | 176000 | 1 | OPTIMAL | false | -24832.57 | -0.179177 | 1.403793e-8 | false | 1.551987 | 1.065394 | 23226 | local | — |
| `network_9_Feeder_5.json` | 244 | ivr | 41333.333333333336 | 3 | SLOW_PROGRESS | false | -10440.83 | 19.64206 | 2.164246e-8 | false | 1.703302 | 2.324644 | 25911 | chordal | 395 / 3–10 |
| `network_9_Feeder_5.json` | 244 | branch_flow | 41333.333333333336 | 3 | SLOW_PROGRESS | false | -10601.1 | 179.9119 | 3.606938e-7 | false | 2.638419 | 2.535988 | 26736 | local | — |
| `network_9_Feeder_5.json` | 244 | ivr | 13777.777777777777 | 1 | SLOW_PROGRESS | false | -10440.83 | 19.6455 | 1.727768e-7 | false | 1.658665 | 2.3321 | 25911 | chordal | 395 / 3–10 |
| `network_9_Feeder_5.json` | 244 | branch_flow | 13777.777777777777 | 1 | OPTIMAL | false | -10601.22 | 180.0323 | 7.584817e-7 | false | 2.502537 | 2.145399 | 26736 | local | — |
| `network_9_Feeder_5.json` | 244 | ivr | 124000 | 1 | SLOW_PROGRESS | false | -10439.07 | 17.88428 | 7.362451e-8 | false | 1.814958 | 4.312209 | 25911 | chordal | 395 / 3–10 |
| `network_9_Feeder_5.json` | 244 | branch_flow | 124000 | 1 | SLOW_PROGRESS | false | -10601.01 | 179.8253 | 5.114424e-7 | false | 2.47948 | 2.021242 | 26736 | local | — |
| `network_15_Feeder_3.json` | 302 | ivr | 57333.333333333336 | 3 | SLOW_PROGRESS | false | -25834.72 | -0.6385287 | 3.732337e-8 | false | 2.427129 | 7.35176 | 37933 | chordal | 506 / 3–18 |
| `network_15_Feeder_3.json` | 302 | branch_flow | 57333.333333333336 | 3 | OPTIMAL | true | -25835.36 | -0.004055757 | 3.88209e-9 | true | 3.874344 | 1.796521 | 33834 | local | — |
| `network_15_Feeder_3.json` | 302 | ivr | 19111.11111111111 | 1 | SLOW_PROGRESS | false | -25835.29 | -0.06518532 | 1.072285e-8 | false | 2.300318 | 5.494533 | 37933 | chordal | 506 / 3–18 |
| `network_15_Feeder_3.json` | 302 | branch_flow | 19111.11111111111 | 1 | OPTIMAL | true | -25835.35 | -0.006287962 | 5.136669e-9 | true | 3.959984 | 2.018509 | 33834 | local | — |
| `network_15_Feeder_3.json` | 302 | ivr | 172000 | 1 | SLOW_PROGRESS | false | -25831.63 | -3.729888 | 8.548168e-8 | false | 2.484784 | 5.490201 | 37933 | chordal | 506 / 3–18 |
| `network_15_Feeder_3.json` | 302 | branch_flow | 172000 | 1 | OPTIMAL | true | -25835.35 | -0.008060911 | 1.330967e-9 | true | 3.941331 | 1.765006 | 33834 | local | — |
| `network_17_Feeder_1.json` | 376 | ivr | 62666.666666666664 | 3 | OPTIMAL | false | -22364.95 | -0.024805 | 8.622744e-10 | true | 3.313102 | 10.89592 | 31331 | chordal | 587 / 3–9 |
| `network_17_Feeder_1.json` | 376 | branch_flow | 62666.666666666664 | 3 | OPTIMAL | true | -22364.95 | -0.02234005 | 2.661793e-9 | true | 5.462621 | 2.072354 | 41100 | local | — |
| `network_17_Feeder_1.json` | 376 | ivr | 20888.888888888887 | 1 | OPTIMAL | true | -22364.97 | 7.191791e-5 | 4.957621e-10 | true | 3.476445 | 11.07649 | 31331 | chordal | 587 / 3–9 |
| `network_17_Feeder_1.json` | 376 | branch_flow | 20888.888888888887 | 1 | OPTIMAL | false | -22364.85 | -0.1229939 | 1.626819e-9 | true | 5.593576 | 2.793928 | 41100 | local | — |
| `network_17_Feeder_1.json` | 376 | ivr | 188000 | 1 | SLOW_PROGRESS | false | -22360.85 | -4.118005 | 6.844193e-8 | false | 3.125768 | 4.372984 | 31331 | chordal | 587 / 3–9 |
| `network_17_Feeder_1.json` | 376 | branch_flow | 188000 | 1 | OPTIMAL | false | -22364.91 | -0.05761636 | 2.006303e-9 | true | 5.579436 | 2.176376 | 41100 | local | — |
| `Network_8_Feeder_2.json` | 538 | ivr | 101333.33333333333 | 3 | SLOW_PROGRESS | false | -44535.99 | -9.19781 | 2.917909e-7 | false | 7.217235 | 8.119459 | 74314 | chordal | 922 / 0–18 |
| `Network_8_Feeder_2.json` | 538 | branch_flow | 101333.33333333333 | 3 | OPTIMAL | false | -44544.45 | -0.7403519 | 1.632743e-9 | true | 9.207455 | 4.055293 | 60384 | local | — |
| `Network_8_Feeder_2.json` | 538 | ivr | 33777.777777777774 | 1 | SLOW_PROGRESS | false | -44543.62 | -1.564008 | 2.787033e-7 | false | 6.888721 | 11.46592 | 74314 | chordal | 922 / 0–18 |
| `Network_8_Feeder_2.json` | 538 | branch_flow | 33777.777777777774 | 1 | OPTIMAL | false | -44544.62 | -0.5720375 | 1.753074e-8 | true | 9.857881 | 4.229934 | 60384 | local | — |
| `Network_8_Feeder_2.json` | 538 | ivr | 304000 | 1 | SLOW_PROGRESS | false | -44532.23 | -12.96289 | 2.417845e-7 | false | 6.876347 | 7.634428 | 74314 | chordal | 922 / 0–18 |
| `Network_8_Feeder_2.json` | 538 | branch_flow | 304000 | 1 | OPTIMAL | true | -44545.16 | -0.02889659 | 8.176746e-9 | true | 9.958109 | 3.764146 | 60384 | local | — |

Each case uses a data-derived per-phase power base and factors 0.3333333333333333, 1, 3. The primary-base rows are medians of 3 fresh builds and solves; sensitivity rows run once. A failure does not suppress later cases. Models above 250000 variables are built and diagnosed but not sent to the solver. This is an experiment-budget decision, not an applicability finding.
