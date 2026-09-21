# Scalable ENWL SDP ladder

Inputs and reported objectives use SI units; both SDP formulations use per-unit coordinates internally. IVRSDP uses its automatic chordal profile, while BranchFlowSDP uses component-local moments. Accepted rows must terminate `OPTIMAL` and pass a `1e-7` scaled residual gate. This is a numerical reporting gate, not a certified lower-bound test; a negative NLP−candidate entry exposes reversed numerical ordering.

| Case | Buses | Formulation | Base (VA) | Status | Accepted | Candidate objective (W) | NLP−candidate (W) | Residual | Build (s) | Solve (s) | Variables | Decomposition | Cliques / order |
|---|---:|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|---:|
| `network_18_Feeder_9.json` | 96 | ivr | 10000 | OPTIMAL | true | -1369.051 | -0.005438626 | 1.993657e-9 | 7.120457 | 1.689757 | 8830 | chordal | 151 / 3–9 |
| `network_18_Feeder_9.json` | 96 | branch_flow | 10000 | OPTIMAL | true | -1369.056 | -0.000689176 | 3.87591e-9 | 2.613627 | 1.070871 | 10548 | local | — |
| `network_18_Feeder_9.json` | 96 | ivr | 3000 | OPTIMAL | true | -1369.056 | -3.997126e-6 | 3.019669e-9 | 2.012431 | 0.692702 | 8830 | chordal | 151 / 3–9 |
| `network_18_Feeder_9.json` | 96 | branch_flow | 3000 | OPTIMAL | true | -1369.056 | -0.0002011677 | 4.296152e-8 | 0.4765766 | 0.7223765 | 10548 | local | — |
| `network_18_Feeder_9.json` | 96 | ivr | 30000 | OPTIMAL | true | -1369.051 | -0.005854433 | 3.497056e-9 | 1.990446 | 0.6080282 | 8830 | chordal | 151 / 3–9 |
| `network_18_Feeder_9.json` | 96 | branch_flow | 30000 | OPTIMAL | true | -1369.029 | -0.02754016 | 1.72453e-9 | 0.4821272 | 0.4639351 | 10548 | local | — |
| `Network_14_Feeder_1.json` | 134 | ivr | 10000 | OPTIMAL | true | -10522.71 | -0.02283828 | 3.815416e-9 | 4.353352 | 1.461803 | 15641 | chordal | 223 / 3–10 |
| `Network_14_Feeder_1.json` | 134 | branch_flow | 10000 | OPTIMAL | true | -10522.73 | -0.002899059 | 4.835477e-9 | 0.8060484 | 1.427137 | 14826 | local | — |
| `Network_14_Feeder_1.json` | 134 | ivr | 3000 | OPTIMAL | true | -10522.73 | -0.001438268 | 1.166276e-9 | 4.369155 | 1.649167 | 15641 | chordal | 223 / 3–10 |
| `Network_14_Feeder_1.json` | 134 | branch_flow | 3000 | OPTIMAL | false | -10522.72 | -0.01974917 | 1.012299e-6 | 0.8008822 | 1.543098 | 14826 | local | — |
| `Network_14_Feeder_1.json` | 134 | ivr | 30000 | OPTIMAL | true | -10522.71 | -0.02386675 | 4.646982e-9 | 4.367606 | 1.533472 | 15641 | chordal | 223 / 3–10 |
| `Network_14_Feeder_1.json` | 134 | branch_flow | 30000 | OPTIMAL | true | -10522.73 | -0.004686703 | 3.944636e-9 | 0.8078761 | 1.092621 | 14826 | local | — |
| `network_13_Feeder_4.json` | 178 | ivr | 10000 | SLOW_PROGRESS | false | — | — | 2.2647e-6 | 12.35138 | 9.645691 | 46599 | chordal | 404 / 0–16 |
| `network_13_Feeder_4.json` | 178 | branch_flow | 10000 | OPTIMAL | false | -24832.71 | -0.03438336 | 1.30612e-6 | 1.413308 | 1.414355 | 23226 | local | — |
| `network_13_Feeder_4.json` | 178 | ivr | 3000 | OPTIMAL | false | -24832.74 | -0.004241481 | 1.006877e-6 | 12.47232 | 10.13336 | 46599 | chordal | 404 / 0–16 |
| `network_13_Feeder_4.json` | 178 | branch_flow | 3000 | OPTIMAL | false | -24832.92 | 0.1796945 | 9.45357e-6 | 1.419881 | 1.684118 | 23226 | local | — |
| `network_13_Feeder_4.json` | 178 | ivr | 30000 | SLOW_PROGRESS | false | — | — | 4.685524e-7 | 12.58784 | 9.767295 | 46599 | chordal | 404 / 0–16 |
| `network_13_Feeder_4.json` | 178 | branch_flow | 30000 | OPTIMAL | false | -24832.7 | -0.04799535 | 4.53968e-7 | 1.437452 | 1.310974 | 23226 | local | — |

Every reached case is evaluated at 3, 10, and 30 kVA. A later case is attempted only when both formulations pass the 10 kVA primary gate on the preceding case. A skipped case is an experiment-budget decision, not an applicability finding. Models above 250000 variables are built and diagnosed but not sent to the solver.
