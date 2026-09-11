# NLP / fixed-SOC experiments

Use the optional environment documented in `test/integration/README.md`.
BMOPFTools and Ipopt are not package runtime dependencies. Run from the repository
root with the dataset paths in `examples/results/nlp_soc_panel_manifest.json`
adjusted to your checkout locations.

```sh
julia --project=test/integration examples/benchmark_nlp_soc.jl examples/results/nlp_soc_panel_manifest.json examples/results/nlp_soc_panel_2026-09-11.json
```

This broad runner checkpoints each completed stage and applies **solver**
time limits. It now routes SOC cases above 140 buses to the bounded runner
instead of attempting unbounded construction. The recorded run was interrupted during the 178-bus SOC build once
construction costs became substantial. The completed observations were retained;
the larger cases were retried using a separate process budget:

```sh
python3 examples/run_bounded_panel.py
python3 examples/merge_nlp_soc_panel.py
python3 examples/summarize_nlp_soc.py examples/results/nlp_soc_combined_2026-09-11.json examples/results/nlp_soc_combined_2026-09-11.md
```

The bounded runner allows 240 seconds per process, including Julia startup,
warm-up, parsing and selected model stages. It saves completed NLP results before
starting SOC, and records the active stage when interrupted. A process-budget
failure is not a solver infeasibility result. Fresh processes warm up on the same
small feeder; first uses of additional component types may still compile code.
All solve comparisons are sequential with one BLAS thread. These are single-run
measurements, not statistical timing estimates.

Controlled follow-ups:

```sh
julia --project=test/integration examples/benchmark_soc_tolerances.jl examples/results/nlp_soc_panel_2026-09-11.json examples/results/soc_tolerance_probe_2026-09-11.json
julia --project=test/integration examples/benchmark_import_diagnostics.jl
```

The tolerance probe changes only Clarabel stopping tolerances. It records the
Euclidean rotated-cone violation, raw primal candidate, accepted objective and
numerical bound separately. The import diagnostics are **derived-input runs**:
restoring IEEE 13 line 671692's explicitly stated sequence impedance, or removing
transformer `s_rating` fields to investigate the NLP's extra nameplate caps.
They are not replacements for the original-input results.

Both engines receive the same cleaned, BMOPFTools-normalized physical input;
source generators are removed, taps fixed and control profiles omitted. Source
import is the objective, with zero cost on retained non-source generators. The
original datasets are never edited. Raw/source and normalized-input evidence,
removed items, parser diagnostics, per-unit bases, statuses and checker findings
are retained where available. The solver models nevertheless differ in their
interpretation of transformer nameplate fields; this is explicitly a comparison
caveat, not silently corrected in the baseline.
