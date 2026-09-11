# Wider ENWL profile screen

One serial screening run per completed profile. Same per-unit preparation and study tolerances as the implementation sweep. The nine cases up to 140 buses use the new automatic default, fast and balanced profiles. The three larger cases attempt fast and balanced separately with 120-second external process budgets, including warm-up, parsing and building. Native solve times exclude these stages. External timeouts are not solver failures.

| Case | Profile | Outcome | Build s | Native solve s | NLP − SOC W |
|:--|:--|:--|--:|--:|--:|
| network_23_Feeder_3.json | clarabel | OPTIMAL | 0.0131 | 0.0020 | -0.0000 |
| network_23_Feeder_3.json | fast | OPTIMAL | 0.0123 | 0.0015 | 2.8020 |
| network_23_Feeder_3.json | balanced | OPTIMAL | 0.0198 | 0.0038 | 0.0695 |
| network_9_Feeder_4.json | clarabel | OPTIMAL | 0.1039 | 0.0408 | 0.1035 |
| network_9_Feeder_4.json | fast | OPTIMAL | 0.1669 | 0.8404 | 25.4619 |
| network_9_Feeder_4.json | balanced | OPTIMAL | 0.2169 | 1.3137 | 3.0923 |
| network_5_Feeder_6.json | clarabel | OPTIMAL | 0.2212 | 0.4131 | 20.2660 |
| network_5_Feeder_6.json | fast | OPTIMAL | 0.2174 | 0.6995 | 97.2491 |
| network_5_Feeder_6.json | balanced | OPTIMAL | 0.2485 | 0.9840 | 8.4649 |
| network_18_Feeder_6.json | clarabel | OPTIMAL | 0.3060 | 0.4985 | 20.7139 |
| network_18_Feeder_6.json | fast | OPTIMAL | 0.3660 | 2.0868 | 57.4335 |
| network_18_Feeder_6.json | balanced | OPTIMAL | 0.4126 | 2.8653 | 16.4805 |
| network_22_Feeder_4.json | clarabel | ALMOST_OPTIMAL | 3.7600 | 0.4016 | — |
| network_22_Feeder_4.json | fast | ALMOST_OPTIMAL | 3.2846 | 0.4095 | — |
| network_22_Feeder_4.json | balanced | ALMOST_OPTIMAL | 3.3583 | 0.4241 | — |
| network_13_Feeder_1.json | clarabel | ALMOST_OPTIMAL | 7.8554 | 0.5332 | — |
| network_13_Feeder_1.json | fast | ALMOST_OPTIMAL | 7.6144 | 0.5177 | — |
| network_13_Feeder_1.json | balanced | ALMOST_OPTIMAL | 7.6385 | 0.5524 | — |
| network_18_Feeder_9.json | clarabel | OPTIMAL | 15.3129 | 1.3477 | 33.6070 |
| network_18_Feeder_9.json | fast | OPTIMAL | 16.7923 | 1.4956 | 33.6070 |
| network_18_Feeder_9.json | balanced | OPTIMAL | 16.7446 | 1.5486 | 33.6270 |
| network_19_Feeder_4.json | clarabel | OPTIMAL | 29.9033 | 0.8888 | 0.7506 |
| network_19_Feeder_4.json | fast | OPTIMAL | 26.7326 | 0.8250 | 0.7506 |
| network_19_Feeder_4.json | balanced | OPTIMAL | 25.9976 | 0.7722 | 0.5921 |
| network_3_Feeder_2.json | clarabel | OPTIMAL | 53.1046 | 0.8797 | 24.5777 |
| network_3_Feeder_2.json | fast | OPTIMAL | 53.0811 | 0.8781 | 24.5777 |
| network_3_Feeder_2.json | balanced | OPTIMAL | 53.2732 | 0.9095 | 23.8057 |
| network_13_Feeder_4.json | fast | PROCESS_BUDGET (build_fast) | — | — | — |
| network_13_Feeder_4.json | balanced | PROCESS_BUDGET (build_balanced) | — | — | — |
| network_2_Feeder_4.json | fast | PROCESS_BUDGET (build_fast) | — | — | — |
| network_2_Feeder_4.json | balanced | PROCESS_BUDGET (build_balanced) | — | — | — |
| Network_8_Feeder_2.json | fast | PROCESS_BUDGET (build_fast) | — | — | — |
| Network_8_Feeder_2.json | balanced | PROCESS_BUDGET (build_balanced) | — | — | — |

21/27 completed solves were accepted; 6 external process-budget outcomes. The limited screen is not a guarantee of performance or coverage on all BMOPF inputs.

## Reproduction

```sh
python3 examples/run_soc_profile_panel.py
python3 examples/summarize_soc_profile_panel.py
```

[Job index, manifests and raw-file locations](soc_profiles_panel_2026-09-11.json).
