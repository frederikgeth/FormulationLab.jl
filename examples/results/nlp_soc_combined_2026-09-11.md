# ENWL and DistributionTestCases: Ipopt NLP versus fixed SOC

One warmed run per case/profile; one BLAS thread; 90-second solver limits. Build time is separate from solve time. Times are wall seconds and include profile-specific work in the corresponding stage. No iterative cuts are used.

ENWL selection: 12 evenly spaced ranks by bus count among 128 reduced feeders (ties sorted by filename). DistributionTestCases selection: modified IEEE 13/34/123, CIGRE, and LV snapshots t500/t1000. Source-bus generators are removed. Other dispatch remains available; taps are fixed and control laws are omitted. Both engines minimize source active-power import. Input preparation uses BMOPFTools parsing/migration, and DSS conversion uses its PowerIO-backed importer. Input files are unchanged.

BMOPFTools uses transformer `s_rating` as an operating limit; FormulationLab treats it as a base quantity. Consequently transformer-case gaps are not clean measurements of relaxation strength alone. Voltage-dependent load laws are retained, not converted to constant power.

Gaps below use Ipopt source import minus the SOC numerical primal objective, in watts. They are not certified optimality gaps: Ipopt provides a local candidate, SOC dual bounds are numerical, and mismatched constraints or validation findings can invalidate an interpretation as relaxation error. Negative imports denote export. Failed or nearly optimal SOC runs are not accepted as bounds.

| Case | Buses | NLP status | NLP build / solve s | SOC profile | SOC status | SOC build / solve s | NLP − SOC W |
|---|---:|---|---:|---|---|---:|---:|
| network_23_Feeder_3.json | 5 | LOCALLY_SOLVED | 0.002944 / 0.002056 | linear | OPTIMAL | 0.05013 / 0.006151 | -2.648e-06 |
| network_23_Feeder_3.json | 5 | LOCALLY_SOLVED | 0.002944 / 0.002056 | kim | OPTIMAL | 0.0356 / 0.03678 | -1.441e-06 |
| network_9_Feeder_4.json | 24 | LOCALLY_SOLVED | 0.01217 / 0.01285 | linear | OPTIMAL | 0.5548 / 17.93 | 0.1042 |
| network_9_Feeder_4.json | 24 | LOCALLY_SOLVED | 0.01217 / 0.01285 | kim | OPTIMAL | 1.103 / 49.59 | 0.05942 |
| network_5_Feeder_6.json | 36 | LOCALLY_SOLVED | 0.008998 / 0.01265 | linear | OPTIMAL | 0.5172 / 17.24 | 20.09 |
| network_5_Feeder_6.json | 36 | LOCALLY_SOLVED | 0.008998 / 0.01265 | kim | ALMOST_OPTIMAL | 0.7863 / 21.27 | — |
| network_18_Feeder_6.json | 45 | LOCALLY_SOLVED | 0.01386 / 0.01691 | linear | OPTIMAL | 1.145 / 45.88 | 20.7 |
| network_18_Feeder_6.json | 45 | LOCALLY_SOLVED | 0.01386 / 0.01691 | kim | OPTIMAL | 1.299 / 69.52 | 8.956 |
| network_22_Feeder_4.json | 54 | LOCALLY_SOLVED | 0.01265 / 0.02011 | linear | ALMOST_OPTIMAL | 3.73 / 0.4299 | — |
| network_22_Feeder_4.json | 54 | LOCALLY_SOLVED | 0.01265 / 0.02011 | kim | ALMOST_OPTIMAL | 3.376 / 0.5432 | — |
| network_13_Feeder_1.json | 77 | LOCALLY_SOLVED | 0.01865 / 0.03119 | linear | ALMOST_OPTIMAL | 7.736 / 0.5634 | — |
| network_13_Feeder_1.json | 77 | LOCALLY_SOLVED | 0.01865 / 0.03119 | kim | ALMOST_OPTIMAL | 7.84 / 0.6708 | — |
| network_18_Feeder_9.json | 96 | LOCALLY_SOLVED | 0.02219 / 0.03659 | linear | ALMOST_OPTIMAL | 15.2 / 1.399 | — |
| network_18_Feeder_9.json | 96 | LOCALLY_SOLVED | 0.02219 / 0.03659 | kim | ALMOST_OPTIMAL | 15.3 / 1.543 | — |
| network_19_Feeder_4.json | 110 | LOCALLY_SOLVED | 0.02468 / 0.03466 | linear | ALMOST_OPTIMAL | 26.11 / 0.9236 | — |
| network_19_Feeder_4.json | 110 | LOCALLY_SOLVED | 0.02468 / 0.03466 | kim | ALMOST_OPTIMAL | 26.9 / 0.9839 | — |
| network_3_Feeder_2.json | 140 | LOCALLY_SOLVED | 0.03222 / 0.06442 | linear | ALMOST_OPTIMAL | 54.15 / 1.008 | — |
| network_3_Feeder_2.json | 140 | LOCALLY_SOLVED | 0.03222 / 0.06442 | kim | ALMOST_OPTIMAL | 54.08 / 1.086 | — |
| network_13_Feeder_4.json | 178 | LOCALLY_SOLVED | 0.04124 / 0.1632 | linear | BUDGET | — / — | — |
| network_2_Feeder_4.json | 241 | LOCALLY_SOLVED | 0.06647 / 0.1321 | linear | BUDGET | — / — | — |
| Network_8_Feeder_2.json | 538 | LOCALLY_SOLVED | 0.2431 / 0.3873 | linear | BUDGET | — / — | — |
| ieee13/ieee13_pmd.dss | 16 | input/build error | — / — | linear | ERROR | — / — | — |
| ieee34/ieee34_pmd.dss | 56 | LOCALLY_INFEASIBLE | 1.98 / 1.741 | linear | SLOW_PROGRESS | 2.988 / 0.5083 | — |
| ieee123/ieee123_pmd.dss | 130 | input/build error | — / — | linear | ERROR | — / — | — |
| cigre/CIGRE_test_case.dss | 4 | LOCALLY_INFEASIBLE | 0.8706 / 0.004144 | linear | OPTIMAL | 0.7095 / 0.003052 | — |
| lvtestcase/snapshots/lvtestcase_pmd_t500.dss | 907 | LOCALLY_SOLVED | 1.101 / 0.06609 | linear | BUDGET | — / — | — |
| lvtestcase/snapshots/lvtestcase_pmd_t1000.dss | 907 | LOCALLY_SOLVED | 1.128 / 0.06854 | linear | BUDGET | — / — | — |

## Validation and failures

- **network_23_Feeder_3.json**: NLP maximum model residual: 2.22e-16; independent BMOPFTools finding counts: {'W.SOL.GEN_ACTIVE': 1}
- **network_9_Feeder_4.json**: NLP maximum model residual: 1.341e-14; independent BMOPFTools finding counts: {'W.SOL.GEN_ACTIVE': 6}
- **network_5_Feeder_6.json**: NLP maximum model residual: 2.22e-16; independent BMOPFTools finding counts: {'W.SOL.GEN_ACTIVE': 5}
- **network_18_Feeder_6.json**: NLP maximum model residual: 2.215e-14; independent BMOPFTools finding counts: {'W.SOL.GEN_ACTIVE': 6}
- **network_22_Feeder_4.json**: NLP maximum model residual: 2.109e-15; independent BMOPFTools finding counts: {'W.SOL.GEN_ACTIVE': 7}
- **network_13_Feeder_1.json**: NLP maximum model residual: 7.751e-14; independent BMOPFTools finding counts: {'W.SOL.GEN_ACTIVE': 12}
- **network_18_Feeder_9.json**: NLP maximum model residual: 6.006e-14; independent BMOPFTools finding counts: {'W.SOL.GEN_ACTIVE': 13}
- **network_19_Feeder_4.json**: NLP maximum model residual: 8.341e-15; independent BMOPFTools finding counts: {'W.SOL.GEN_ACTIVE': 14}
- **network_3_Feeder_2.json**: NLP maximum model residual: 9.617e-14; independent BMOPFTools finding counts: {'W.SOL.GEN_ACTIVE': 17}
- **network_13_Feeder_4.json**: soc_error: External 240 s process budget reached in stage soc_build (includes startup/warm-up); no completed SOC result.; NLP maximum model residual: 1.468e-12; independent BMOPFTools finding counts: {'W.SOL.VOLT_ACTIVE': 145, 'W.SOL.THERMAL_ACTIVE': 4, 'W.SOL.GEN_ACTIVE': 43}
- **network_2_Feeder_4.json**: soc_error: External 240 s process budget reached in stage soc_build (includes startup/warm-up); no completed SOC result.; NLP maximum model residual: 5.569e-12; independent BMOPFTools finding counts: {'W.SOL.GEN_ACTIVE': 29}
- **Network_8_Feeder_2.json**: soc_error: External 240 s process budget reached in stage soc_build (includes startup/warm-up); no completed SOC result.; NLP maximum model residual: 1.849e-12; independent BMOPFTools finding counts: {'W.SOL.GEN_ACTIVE': 76}
- **ieee13/ieee13_pmd.dss**: nlp_error: ArgumentError: Line '671692': no impedance source (missing/unknown linecode or series matrices). Declare exact zero impedance explicitly for an ideal line.; soc_error: E.SDP.UNSUPPORTED: line/671692 references an unknown linecode
- **ieee34/ieee34_pmd.dss**: NLP maximum model residual: 0.01259; independent BMOPFTools finding counts: {'W.SOL.INCOMPLETE_RESULT': 1, 'W.SOL.THERMAL_ACTIVE': 3, 'W.SOL.LOAD_MODEL_RESIDUAL': 15, 'W.SOL.INIT_LARGE_ERROR': 1}
- **ieee123/ieee123_pmd.dss**: nlp_error: ArgumentError: Line 'sw2': no impedance source (missing/unknown linecode or series matrices). Declare exact zero impedance explicitly for an ideal line.; soc_error: E.SDP.UNSUPPORTED: line/sw2 references an unknown linecode
- **cigre/CIGRE_test_case.dss**: NLP maximum model residual: 0.3021; independent BMOPFTools finding counts: {'W.SOL.THERMAL_ACTIVE': 3, 'W.SOL.LOAD_RESIDUAL': 1, 'W.SOL.POWER_BALANCE': 2, 'W.SOL.NEG_LOSS': 1}
- **lvtestcase/snapshots/lvtestcase_pmd_t500.dss**: soc_error: External 240 s process budget reached in stage soc_linear (includes startup/warm-up); no completed SOC result.; NLP maximum model residual: 5.14e-14; independent BMOPFTools finding counts: {}
- **lvtestcase/snapshots/lvtestcase_pmd_t1000.dss**: soc_error: External 240 s process budget reached in stage soc_linear (includes startup/warm-up); no completed SOC result.; NLP maximum model residual: 6.596e-12; independent BMOPFTools finding counts: {}

Raw JSON retains exact statuses, numerical solver bounds, parser provenance, all findings, input hashes, per-unit bases, model sizes, strengthening counts and compilation/solve timings. The SOC `max_scaled_violation` field uses MOI’s distance upper bound; it is not the geometric rotated-cone distance used by the newer containment audit.


## Stopping-tolerance experiment

Same default SOC constraints; `tol_feas=1e-7`, `tol_gap_abs=1e-6`, `tol_gap_rel=1e-7`. No incumbent-dependent strengthening. Geometric residuals replace MOI’s rotated-cone distance upper bound with the Euclidean SOC distance.

| Case | Status | Build / solve s | Geometric violation | NLP − SOC W |
|---|---|---:|---:|---:|
| network_22_Feeder_4.json | ALMOST_OPTIMAL | 3.865 / 0.457 | 1.131e-07 | — |
| network_13_Feeder_1.json | ALMOST_OPTIMAL | 7.924 / 0.583 | 2.07e-08 | — |
| network_18_Feeder_9.json | OPTIMAL | 15.27 / 1.384 | 5.998e-08 | 33.61 |
| network_19_Feeder_4.json | OPTIMAL | 26.46 / 0.9373 | 1.176e-07 | 0.7506 |
| network_3_Feeder_2.json | OPTIMAL | 55.45 / 1.067 | 6.051e-08 | 24.58 |

## Controlled import and nameplate diagnostics

These are explicitly modified inputs. They must not replace or be counted as successes for the original-input panel. Removing `s_rating` disables BMOPFTools nameplate caps; it is not a certified general transformation of every transformer representation.

**ieee13_impedance_repair**: Restore line 671692's explicitly stated OpenDSS sequence impedance as diag(1e-4 ohm). Separate derived-input experiment.
NLP: LOCALLY_INFEASIBLE; source import — W.
SOC: SLOW_PROGRESS; source import — W.

**cigre_no_nameplate_caps**: Separate diagnostic removing s_rating fields to disable BMOPFTools nameplate caps; not a solve of the unchanged input.
NLP: LOCALLY_SOLVED; source import 1.837e+06 W.
SOC: OPTIMAL; source import 1.836e+06 W.

**ieee34_no_nameplate_caps**: Separate diagnostic removing s_rating fields to disable BMOPFTools nameplate caps; not a solve of the unchanged input.
NLP: LOCALLY_SOLVED; source import 2.043e+06 W.
SOC: SLOW_PROGRESS; source import — W.

## Implications

- Ipopt is the stronger speed/reliability baseline on the sampled ENWL feeders and the two LV snapshots. These local feasible solutions do not establish global optimality.
- Prioritize SOC construction profiling and numerical reliability before adding more strengthening. Fixed Kim cuts improve some converged bounds but are not uniformly reliable or economical on this panel.
- Relaxing stopping tolerances rescues some cases, but residuals and numerical dual bounds still require inspection. It does not cure construction scaling.
- Imported IEEE/CIGRE outcomes must be interpreted with parser diagnostics and the transformer rating contract. They are not evidence that the unchanged original DSS circuit is infeasible.
