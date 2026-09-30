# LinIVR coverage expansion — 30 September 2026

Transformer cases vary tap (0.94/1.06), current scale (1/10/30), and flow direction. References are independently constructed from winding EMFs and currents and must pass the SI physical checker. No loaded reference enters the LinIVR builder. Limits receive a recorded factor-two current margin for this accuracy panel. The multiwinding case has coupled non-star leakage, non-unity taps, delta excitation and four windings.

| Transformer | Accepted / cases | Maximum conductor phasor error V | Maximum device power mismatch VA |
|:--|--:|--:|--:|
| single_phase | 12 / 12 | 0.05412 | 92.87139 |
| center_tap | 12 / 12 | 0.14057 | 184.21933 |
| wye_delta | 12 / 12 | 0.35838 | 394.97911 |
| delta_wye | 12 / 12 | 0.09621 | 167.45763 |
| single_phase_autotransformer | 12 / 12 | 0.17822 | 254.97153 |
| open_delta_regulator | 12 / 12 | 0.14119 | 343.26398 |
| n_winding | 1 / 1 | 0.00035 | 0.53793 |

All listed successful references pass independent physical validation; the approximate candidates still have nonzero device-power residuals. Construction/solution success is coverage evidence, not a claim of AC exactness or an optimality certificate. Timings are single warmed observations with possible additional compilation.

| Device case | LinIVR | BMOPFTools OPF | Fixed-dispatch PF |
|:--|:--|:--|:--|
| ibr_SINGLE_PHASE | OPTIMAL | LOCALLY_SOLVED | LOCALLY_SOLVED |
| feeder_ibr_SINGLE_PHASE | OPTIMAL | LOCALLY_SOLVED | LOCALLY_SOLVED |
| ibr_FOUR_LEG | OPTIMAL | LOCALLY_SOLVED | LOCALLY_SOLVED |
| feeder_ibr_FOUR_LEG | OPTIMAL | LOCALLY_SOLVED | LOCALLY_SOLVED |
| ibr_THREE_LEG | OPTIMAL | LOCALLY_SOLVED | LOCALLY_SOLVED |
| feeder_ibr_THREE_LEG | OPTIMAL | LOCALLY_SOLVED | LOCALLY_SOLVED |
| delta_generator | OPTIMAL | LOCALLY_SOLVED | LOCALLY_SOLVED |

Delta generators and three-leg inverters use coil P/Q and coil current limits, matching this BMOPFTools revision. Unequal coil powers distinguish this from the existing SDP conductor-power convention. Each inverter is tested at fixed PCC voltage and at the end of an unbalanced two-segment four-wire feeder. These comparisons verify PCC behavior only: this BMOPFTools implementation does not stamp the filter circuit used by FormulationLab. Filter losses and internal powers are checked separately in the SI regression suite. Internal-power budgets are affine, and actual internal powers can exceed them by omitted second-order filter losses.


Raw observations: [linivr_coverage_2026-09-30.json](linivr_coverage_2026-09-30.json). Run `examples/benchmark_linivr_coverage.jl` using the optional integration environment. Static controls, grid-forming internal-voltage regulation, general voltage-dependent loads, DC networks and time series remain unsupported.
