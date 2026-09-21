# Small ENWL: Ipopt NLP versus Mosek SDP

All three models receive the same normalized, Kron-reduced network. Ipopt supplies a locally feasible AC point; it does not certify the global optimum. The SDP objectives are numerical relaxation values, not rigorous residual-corrected bounds.

The source ENWL files model the explicit neutral grounding with a finite, very large shunt. The shared reduction instead fixes that neutral at ideal ground, so every case is reported as `grounded_neutral_projection`, not as an exact reduction of the source file.

| Case | Buses | Ipopt AC (W) | IVRSDP (W) | BranchFlowSDP (W) | NLP−IVR (W) | NLP−BFM (W) | IVR−BFM (W) |
|---|---:|---:|---:|---:|---:|---:|---:|
| network_23_Feeder_3.json | 5 | -1711.491 | -1711.491 | -1711.49 | -1.399513e-6 | -0.0001181246 | -0.0001167251 |
| network_13_Feeder_3.json | 6 | -1716.606 | -1716.606 | -1716.606 | -4.860408e-6 | -0.0001695491 | -0.0001646887 |
| network_11_Feeder_2.json | 8 | 1219.576 | 1219.576 | 1219.579 | -2.618183e-5 | -0.002558275 | -0.002532093 |
| network_10_Feeder_2.json | 10 | -1089.605 | -1089.605 | — | -0.0001175232 | — | — |
| network_5_Feeder_1.json | 11 | 1544.831 | 1544.831 | 1544.837 | 2.323113e-6 | -0.005774618 | -0.005776941 |

`NLP−SDP ≥ 0` is the expected relaxation ordering when the implemented constraint sets agree. `IVR−BFM` directly measures agreement between the two lifted formulations.

Sub-centiwatt ordering reversals are treated as numerical agreement. The JSON uses a per-case tolerance of `max(0.01 W, 1e-5 × |NLP objective|)` and never publishes an objective from a solve that did not terminate `OPTIMAL`.

## Solver outcomes

| Case | Ipopt / BMOPFTools | IVR status | IVR rank ratio | IVR residual | BFM status | BFM rank ratio | BFM residual |
|---|---|---|---:|---:|---|---:|---:|
| network_23_Feeder_3.json | LOCALLY_SOLVED / checks_passed | OPTIMAL | 0.0440118 | 6.890339e-12 | OPTIMAL | 4.726568e-6 | 2.623234e-8 |
| network_13_Feeder_3.json | LOCALLY_SOLVED / checks_passed | OPTIMAL | 0.04604056 | 3.013743e-11 | OPTIMAL | 2.102365e-6 | 4.212085e-8 |
| network_11_Feeder_2.json | LOCALLY_SOLVED / checks_passed | OPTIMAL | 0.06538456 | 3.369482e-11 | OPTIMAL | 0.0001270014 | 4.718797e-9 |
| network_10_Feeder_2.json | LOCALLY_SOLVED / checks_passed | OPTIMAL | 0.9991801 | 3.875256e-11 | SLOW_PROGRESS | — | 5.641941e-6 |
| network_5_Feeder_1.json | LOCALLY_SOLVED / checks_passed | OPTIMAL | 0.4231063 | 2.037148e-12 | OPTIMAL | 0.0001048757 | 1.270756e-9 |

The rank ratios are formulation-specific diagnostics: IVR uses its global lifted state, whereas BranchFlow reports the worst topology moment block. Compare trends, not the two numbers as if they measured the same matrix.

## AC validation

- `network_23_Feeder_3.json`: Ipopt `LOCALLY_SOLVED`; BMOPFTools `checks_passed`; maximum JuMP model residual 6.526897000000001e-17.
- `network_13_Feeder_3.json`: Ipopt `LOCALLY_SOLVED`; BMOPFTools `checks_passed`; maximum JuMP model residual 9.831003000000001e-17.
- `network_11_Feeder_2.json`: Ipopt `LOCALLY_SOLVED`; BMOPFTools `checks_passed`; maximum JuMP model residual 9.047667000000001e-17.
- `network_10_Feeder_2.json`: Ipopt `LOCALLY_SOLVED`; BMOPFTools `checks_passed`; maximum JuMP model residual 9.551821000000001e-17.
- `network_5_Feeder_1.json`: Ipopt `LOCALLY_SOLVED`; BMOPFTools `checks_passed`; maximum JuMP model residual 2.235712e-14.

BMOPFTools' checker lists unassessed dimensions in the JSON record. A `checks_passed` result therefore means that all implemented independent checks passed; it is not a complete second implementation of every OPF equation.
