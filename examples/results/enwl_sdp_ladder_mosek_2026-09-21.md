# ENWL SDP benchmark ladder

Inputs and reported objectives use SI units; SDP models use per-unit coordinates internally. Every accepted SDP result terminated `OPTIMAL` and has maximum scaled JuMP residual at most `1e-7`. Ipopt is a locally feasible AC reference, not a global certificate.

## Primary comparison (10 kVA, all strengthening)

| Case | Buses | Ipopt (W) | IVRSDP (W) | BranchFlowSDP (W) | NLP−IVR (W) | NLP−BFM (W) | IVR residual | BFM residual |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `network_9_Feeder_4.json` | 24 | -4036.823 | -4036.822 | -4036.823 | -0.0009824671 | -0.0005398207 | 3.329541e-9 | 3.349418e-8 |
| `network_18_Feeder_6.json` | 45 | -2969.251 | -2969.249 | -2969.25 | -0.001399441 | -0.0006510565 | 3.029043e-10 | 1.556768e-9 |
| `network_18_Feeder_9.json` | 96 | -1369.056 | — | -1368.982 | — | -0.07469623 | 1.559576e-7 | 4.80661e-9 |

## Strengthening ablation at 10 kVA

| Case | Formulation | Configuration | Status | Accepted | Objective (W) | Residual | Build (s) | Solve (s) | Variables | Constraints | LNC | RLT |
|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `network_9_Feeder_4.json` | ivr | all | OPTIMAL | true | -4036.822 | 3.329541e-9 | 0.2787531 | 2.002738 | 1596 | 944 | 68 | 0 |
| `network_9_Feeder_4.json` | ivr | baseline | OPTIMAL | true | -4036.823 | 2.99305e-11 | 0.1324492 | 0.300655 | 1596 | 332 | 0 | 0 |
| `network_9_Feeder_4.json` | ivr | line_lnc | OPTIMAL | true | -4036.822 | 3.329541e-9 | 0.2624191 | 2.02183 | 1596 | 944 | 68 | 0 |
| `network_9_Feeder_4.json` | ivr | port_rlt | OPTIMAL | true | -4036.823 | 2.99305e-11 | 0.1288965 | 0.2993107 | 1596 | 332 | 0 | 0 |
| `network_9_Feeder_4.json` | branch_flow | all | OPTIMAL | true | -4036.823 | 3.349418e-8 | 0.1137058 | 0.6137823 | 13428 | 2292 | 69 | 0 |
| `network_9_Feeder_4.json` | branch_flow | baseline | OPTIMAL | true | -4036.814 | 6.678816e-10 | 0.07793604 | 0.1090569 | 2988 | 1244 | 0 | 0 |
| `network_9_Feeder_4.json` | branch_flow | line_lnc | OPTIMAL | true | -4036.818 | 8.204045e-10 | 0.09302742 | 0.5557808 | 13428 | 2223 | 69 | 0 |
| `network_9_Feeder_4.json` | branch_flow | port_rlt | OPTIMAL | true | -4036.814 | 6.678816e-10 | 0.07630167 | 0.09287921 | 2988 | 1244 | 0 | 0 |
| `network_9_Feeder_4.json` | branch_flow | implied_current | OPTIMAL | true | -4036.82 | 1.779634e-9 | 0.07668271 | 0.1022645 | 2988 | 1313 | 0 | 0 |
| `network_18_Feeder_6.json` | ivr | all | OPTIMAL | true | -2969.249 | 3.029043e-10 | 0.5365806 | 6.478942 | 1711 | 1765 | 131 | 0 |
| `network_18_Feeder_6.json` | ivr | baseline | OPTIMAL | true | -2969.251 | 3.388867e-11 | 0.2801522 | 0.9404242 | 1711 | 586 | 0 | 0 |
| `network_18_Feeder_6.json` | ivr | line_lnc | OPTIMAL | true | -2969.249 | 3.029043e-10 | 0.5394257 | 6.522873 | 1711 | 1765 | 131 | 0 |
| `network_18_Feeder_6.json` | ivr | port_rlt | OPTIMAL | true | -2969.251 | 3.388867e-11 | 0.2691435 | 0.9290305 | 1711 | 586 | 0 | 0 |
| `network_18_Feeder_6.json` | branch_flow | all | OPTIMAL | true | -2969.25 | 1.556768e-9 | 0.2038089 | 2.324645 | 41436 | 4149 | 132 | 0 |
| `network_18_Feeder_6.json` | branch_flow | baseline | OPTIMAL | true | -2969.235 | 1.984043e-9 | 0.171341 | 0.1911005 | 4851 | 2156 | 0 | 0 |
| `network_18_Feeder_6.json` | branch_flow | line_lnc | OPTIMAL | true | -2969.228 | 5.584268e-9 | 0.2063268 | 1.909848 | 41436 | 4017 | 132 | 0 |
| `network_18_Feeder_6.json` | branch_flow | port_rlt | OPTIMAL | true | -2969.235 | 1.984043e-9 | 0.164143 | 0.1957162 | 4851 | 2156 | 0 | 0 |
| `network_18_Feeder_6.json` | branch_flow | implied_current | OPTIMAL | true | -2969.239 | 4.256489e-9 | 0.1558692 | 0.2140521 | 4851 | 2288 | 0 | 0 |
| `network_18_Feeder_9.json` | ivr | all | TIME_LIMIT | false | — | 1.559576e-7 | 6.623041 | 180.9123 | 8256 | 3824 | 284 | 0 |
| `network_18_Feeder_9.json` | branch_flow | all | OPTIMAL | true | -1368.982 | 4.80661e-9 | 0.6106371 | 11.35955 | 176724 | 8952 | 285 | 0 |
| `network_18_Feeder_9.json` | branch_flow | baseline | OPTIMAL | true | -1369.012 | 7.564282e-9 | 0.418303 | 0.3953724 | 10548 | 4664 | 0 | 0 |
| `network_18_Feeder_9.json` | branch_flow | line_lnc | OPTIMAL | true | -1369.053 | 7.539879e-9 | 0.6338367 | 10.82462 | 176724 | 8667 | 285 | 0 |
| `network_18_Feeder_9.json` | branch_flow | port_rlt | OPTIMAL | true | -1369.012 | 7.564282e-9 | 0.4336608 | 0.3915612 | 10548 | 4664 | 0 | 0 |
| `network_18_Feeder_9.json` | branch_flow | implied_current | OPTIMAL | true | -1369.012 | 1.40627e-8 | 0.4329313 | 0.4354481 | 10548 | 4949 | 0 | 0 |

## Power-base sensitivity with all strengthening

| Case | Formulation | Base (VA) | Status | Accepted | Objective (W) | Residual |
|---|---|---:|---|---:|---:|---:|
| `network_9_Feeder_4.json` | ivr | 3000 | OPTIMAL | true | -4036.823 | 4.291918e-9 |
| `network_9_Feeder_4.json` | ivr | 10000 | OPTIMAL | true | -4036.822 | 3.329541e-9 |
| `network_9_Feeder_4.json` | ivr | 30000 | OPTIMAL | true | -4036.824 | 3.170626e-8 |
| `network_9_Feeder_4.json` | branch_flow | 3000 | OPTIMAL | true | -4036.823 | 7.689739e-8 |
| `network_9_Feeder_4.json` | branch_flow | 10000 | OPTIMAL | true | -4036.823 | 3.349418e-8 |
| `network_9_Feeder_4.json` | branch_flow | 30000 | OPTIMAL | true | -4036.807 | 1.980744e-9 |
| `network_18_Feeder_6.json` | ivr | 3000 | OPTIMAL | true | -2969.25 | 2.791385e-10 |
| `network_18_Feeder_6.json` | ivr | 10000 | OPTIMAL | true | -2969.249 | 3.029043e-10 |
| `network_18_Feeder_6.json` | ivr | 30000 | OPTIMAL | true | -2969.251 | 8.268224e-10 |
| `network_18_Feeder_6.json` | branch_flow | 3000 | OPTIMAL | true | -2969.25 | 1.297919e-8 |
| `network_18_Feeder_6.json` | branch_flow | 10000 | OPTIMAL | true | -2969.25 | 1.556768e-9 |
| `network_18_Feeder_6.json` | branch_flow | 30000 | OPTIMAL | true | -2968.995 | 1.465164e-8 |
| `network_18_Feeder_9.json` | ivr | 3000 | TIME_LIMIT | false | — | 0.000503252 |
| `network_18_Feeder_9.json` | ivr | 10000 | TIME_LIMIT | false | — | 1.559576e-7 |
| `network_18_Feeder_9.json` | ivr | 30000 | TIME_LIMIT | false | — | 5.422545e-9 |
| `network_18_Feeder_9.json` | branch_flow | 3000 | OPTIMAL | false | — | 1.595145e-7 |
| `network_18_Feeder_9.json` | branch_flow | 10000 | OPTIMAL | true | -1368.982 | 4.80661e-9 |
| `network_18_Feeder_9.json` | branch_flow | 30000 | OPTIMAL | true | -1368.747 | 1.10091e-8 |

The 96-bus stage runs only if both formulations pass the 45-bus gate with all strengthening at 10 kVA. A skipped stage is an experiment-budget decision, not an applicability result.

## Interpretation

- `network_9_Feeder_4.json` / ivr: 3/3 bases accepted; accepted-objective span 0.001371069 W.
- `network_9_Feeder_4.json` / branch_flow: 3/3 bases accepted; accepted-objective span 0.01560051 W.
- `network_18_Feeder_6.json` / ivr: 3/3 bases accepted; accepted-objective span 0.001192947 W.
- `network_18_Feeder_6.json` / branch_flow: 3/3 bases accepted; accepted-objective span 0.2554939 W.
- `network_18_Feeder_9.json` / ivr: 0/3 bases accepted; accepted-objective span — W.
- `network_18_Feeder_9.json` / branch_flow: 2/3 bases accepted; accepted-objective span 0.2346846 W.
- The ENWL generator boxes do not provide the finite P/Q domains needed by the port-RLT construction, so every port-RLT ablation applies zero cuts and matches its baseline model exactly.
- Automatic line LNCs activate a global voltage closure in BranchFlowSDP. At 96 buses this changes 10,548 variables in the baseline to 176,724 with LNCs; the solve time rises from about 0.4 s to about 11 s.
- Solver acceptance is not a certified bound. In particular, the 96-bus 10 kVA BranchFlowSDP objective is 0.0747 W above the feasible Ipopt objective, outside the comparison tolerance, and its accepted objectives span about 0.235 W across bases. The result is numerically useful but not quantitatively trustworthy.
- The dense 96-bus IVRSDP reaches the 180 s limit at every base. The 30 kVA iterate passes the residual threshold but is still rejected because Mosek did not declare optimality. Sparse/chordal IVR is the appropriate next scalability comparison.
