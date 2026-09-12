# IEEE 8500 / 9500 loading audit — 12 September 2026

PowerIO 0.11.0, Julia 1.12.6, FormulationLab base revision `1748ef0`. No power-flow or optimization solve was run. This is a conversion/applicability audit, not a performance benchmark. Balanced and unbalanced original masters, both converted 9500 archives, and one derived linecode-based 9500 snapshot were inspected.

| Input | BMOPF export | Buses | Loads | Generic n-winding banks | LinDist3Flow |
|:--|:--|--:|--:|--:|:--|
| [8500_bal](ieee_loading_8500_bal_2026-09-12.json) | completed | 4876 | 1177 | 1177 | rejected in all three modes |
| [8500_unbal](ieee_loading_8500_unbal_2026-09-12.json) | completed | 4876 | 2354 | 1177 | rejected in all three modes |
| [9500_bal](ieee_loading_9500_bal_2026-09-12.json) | unresolved line geometry | — | — | — | not reached |
| [9500_unbal](ieee_loading_9500_unbal_2026-09-12.json) | unresolved line geometry | — | — | — | not reached |
| [9500_bal_converted](ieee_loading_9500_bal_converted_2026-09-12.json) | unresolved line geometry | — | — | — | not reached |
| [9500_unbal_converted](ieee_loading_9500_unbal_converted_2026-09-12.json) | unresolved line geometry | — | — | — | not reached |
| [9500_unbal_linecodes](ieee_loading_9500_unbal_linecodes_2026-09-12.json) | completed | 5302 | 2550 | 1275 | rejected in all three modes |

All seven files parsed into a PowerIO module. Four could not be emitted as BMOPF. The three completed exports were tested with `:lower`, `:approximate` and `:permissive`; none passed applicability. A zero process exit code means the audit recorded its outcome, not that the circuit is supported.

## Findings

1. **8500 service-transformer encoding:** the original deck explicitly describes 1,177 center-tapped three-winding service transformers. PowerIO exports them as `n_winding`, not the `center_tap` subtype consumed by LinDist3Flow. The first rejection is the unconsumed `x_sc` field. This is a supported-schema-versus-formulation mismatch, not malformed feeder data. Do not delete `x_sc` to bypass the guard; convert pairwise leakage to the appropriate coupled equivalent and preserve winding polarity, ratios, grounding, losses and ratings.
2. **9500 geometry:** the original and converted decks each report 2,626 unresolved geometry lines. Switching a private copy to the upstream `LineCodes.dss` and `LinesSwitchesLineCodes.dss` removes this blocker. Both master redirects were changed; no line parameters were synthesized. This is a distinct input variant whose electrical equivalence to the geometry deck still needs an OpenDSS comparison.
3. **Dropped reactor:** all three completed exports lose `Reactor.HVMV_Sub_HSB`. The source deck puts substation source impedance in this series device. Treat this as a missing electrical branch, not harmless metadata. PowerIO needs a series-reactor-to-branch representation.
4. **9500 DERs:** the linecode variant exports 178 IBRs and 12 generators, but drops `Battery1` and `Battery2`. A declared static battery dispatch must be exported explicitly before claiming the same snapshot. Zero generation cost defaults are separately reported and do not mean the generators were dropped.
5. **Impedance convention:** this audit applies a diagnostic adapter only to PowerIO-generated Yd/Dy aliases: `r_series`/`x_series` are mapped to the wye-side canonical fields. This is not the primary-referred convention used in the separate Springfield sensitivity study. A permanent provenance-aware boundary contract is still needed.
6. **Controls and later checks:** regulators retain written taps; control laws are not executed. Capacitor/controller state must be frozen consistently for an oracle comparison. The early transformer rejection prevents assessing downstream topology, other device applicability and solver behavior; those are not presumed to pass.

## Recommended work order

1. Repair PowerIO series-reactor export and formalize wye-side impedance normalization.
2. Add a narrowly recognized `n_winding` to center-tap adapter with independent OpenDSS tests, including secondary polarity and unequal load cases. Keep unsupported generic winding configurations rejected.
3. Re-audit 8500, then run a matching static OpenDSS reference and LinDist3Flow comparison. Distinguish engineering-limit violations from conversion or numerical failures.
4. Use the supplied 9500 linecode variant initially; verify it against the geometry-based OpenDSS circuit. Export fixed battery states and audit IBR/generator dispatch before solving.
5. Only after faithful snapshots pass these checks, benchmark SOC/SDP scale and consider additional meshed operating configurations.

## Reproduction and provenance

Pinned upstream repositories and every downloaded file hash are in [the source manifest](ieee_loading_sources_2026-09-12.json). The derived linecode master changes only the two documented include choices. Original downloads are unchanged. Converted archive files are extracted to temporary directories.

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 python3 examples/run_large_ieee_audit.py /path/to/ieee-test-feeders-2026-09-12
python3 examples/summarize_large_ieee_audit.py
```

The orchestrator applies a 240-second process budget per case. The first six recorded runs completed without timeout;  the seventh was run separately and completed normally. Each raw record preserves the last stage, timings and diagnostics.
