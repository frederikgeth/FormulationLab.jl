# ENWL per-unit scaling study

BMOPF inputs and published results are in SI units. Each optimization model is internally per-unit with `V_base` equal to the largest source-voltage magnitude, `I_base = S_base/V_base`, and `Z_base = V_base²/S_base`. Changing `S_base` is an algebraically equivalent coordinate change; a stable solve should preserve the SI objective.

All runs use Mosek, one thread, real PSD embeddings, and the same normalized Kron-reduced ENWL dictionaries. A run contributes to an objective span only when it terminates `OPTIMAL` and its maximum scaled JuMP residual is at most `1e-7`.

## Power-base sweep

| Case | Formulation | Solver optimal | Accepted | Objective interval (W) | Span (W) | Worst accepted residual |
|---|---|---:|---:|---:|---:|---:|
| network_23_Feeder_3.json | ivr | 5/5 | 5/5 | -1711.491 to -1711.49 | 0.0001046648 | 8.753735e-9 |
| network_23_Feeder_3.json | branch_flow | 4/5 | 3/5 | -1711.491 to -1711.49 | 9.815696e-5 | 2.623234e-8 |
| network_13_Feeder_3.json | ivr | 5/5 | 5/5 | -1716.606 to -1716.606 | 5.457951e-5 | 7.173329e-10 |
| network_13_Feeder_3.json | branch_flow | 4/5 | 3/5 | -1716.606 to -1716.604 | 0.001890722 | 4.212085e-8 |
| network_11_Feeder_2.json | ivr | 5/5 | 5/5 | 1219.576 to 1219.576 | 2.8572e-5 | 1.131484e-9 |
| network_11_Feeder_2.json | branch_flow | 4/5 | 3/5 | 1219.579 to 1219.601 | 0.02207587 | 8.274709e-9 |
| network_10_Feeder_2.json | ivr | 5/5 | 5/5 | -1089.605 to -1089.605 | 0.0001214217 | 3.389015e-10 |
| network_10_Feeder_2.json | branch_flow | 1/5 | 0/5 | — | — | — |
| network_5_Feeder_1.json | ivr | 5/5 | 5/5 | 1544.831 to 1544.832 | 0.0004165475 | 1.606959e-10 |
| network_5_Feeder_1.json | branch_flow | 5/5 | 4/5 | 1544.831 to 1544.837 | 0.005726451 | 7.207965e-8 |

A large span or changing termination status is numerical scaling sensitivity, not a physical change in the feeder or a valid relaxation-strength comparison.

## Ten-bus scaling controls

The witness grid separately varies objective normalization, IVR state scaling, and Mosek's internal interior-point scaling over 3, 10, and 30 kVA bases.

| Formulation | Objective scaling | State scaling | Mosek scaling | Solver optimal | Accepted | Objective span (W) | Worst accepted residual |
|---|---|---|---|---:|---:|---:|---:|
| branch_flow | false | not_applicable | free | 0/3 | 0/3 | — | — |
| branch_flow | false | not_applicable | none | 0/3 | 0/3 | — | — |
| branch_flow | true | not_applicable | free | 1/3 | 0/3 | — | — |
| branch_flow | true | not_applicable | none | 1/3 | 0/3 | — | — |
| ivr | false | global | free | 3/3 | 3/3 | 4.650742e-6 | 2.732789e-10 |
| ivr | false | global | none | 3/3 | 3/3 | 1.300207e-5 | 5.012402e-9 |
| ivr | false | voltage_region | free | 3/3 | 3/3 | 4.650742e-6 | 2.732789e-10 |
| ivr | false | voltage_region | none | 3/3 | 3/3 | 1.300207e-5 | 5.012402e-9 |
| ivr | true | global | free | 3/3 | 3/3 | 0.0001156476 | 1.51956e-10 |
| ivr | true | global | none | 3/3 | 3/3 | 0.0002762731 | 3.148533e-9 |
| ivr | true | voltage_region | free | 3/3 | 3/3 | 0.0001156476 | 1.51956e-10 |
| ivr | true | voltage_region | none | 3/3 | 3/3 | 0.0002762731 | 3.148533e-9 |

Failed iterates and their raw objectives remain in the JSON only as diagnostics; they are not bounds and are excluded from every interval above.

## Findings

- IVR is numerically accepted in 25/25 power-base runs. BranchFlow is solver-optimal in 18/25 but passes the residual gate in only 13/25.
- Without objective normalization, BranchFlow is solver-optimal in 0/6 ten-bus witness runs.
- At 3 kVA with objective normalization enabled, toggling only Mosek's interior-point scaling changes two solver-optimal BranchFlow raw objectives by 16.08649 W. Both fail the residual gate, demonstrating why an `OPTIMAL` label alone is not sufficient evidence of a stable bound.
- IVR `global` and `voltage_region` scaling differ by at most 0.0 W here. Each feeder is a single voltage region, so both modes select unit state scales.

The practical conclusion is that the current IVR formulation is stable across the tested per-unit coordinates, while BranchFlow needs additional row/state scaling before its Mosek objective should be used quantitatively on the ten-bus witness.
