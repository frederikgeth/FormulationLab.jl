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

## Small ENWL NLP/SDP comparison

`benchmark_nlp_sdp_enwl.jl` compares a BMOPFTools/Ipopt AC solution with the
dense reference `IVRSDP` and `BranchFlowSDP`, using Mosek for both relaxations.
It selects the five smallest reduced ENWL feeders (5–11 buses), uses a common
10 kVA power base and one solver thread, warms every execution path before
timing, and checkpoints JSON after each stage. The fixed 10 kVA base is also the
formulations' normal default; substantially smaller bases caused avoidable
BranchFlowSDP conditioning failures in Mosek during experiment development.

```sh
julia --project=test/integration examples/benchmark_nlp_sdp_enwl.jl \
  ../BMOPFDraftData/benchmarks/ENWLbenchmark/reduced \
  examples/results/enwl_nlp_sdp_mosek.json
```

The original ENWL snapshots have four-conductor buses but prescribe only the
three phase voltages at the source; their neutral is tied to ground through a
finite, very large shunt. A branch-flow root block needs every root voltage.
The experiment therefore applies `kron_reduce_bmopf` once and passes the same
derived three-wire dictionary to Ipopt, IVRSDP, and BranchFlowSDP. For these
snapshots the reduction is deliberately classified as
`grounded_neutral_projection`: it replaces the finite grounding impedance by an
ideal ground and is a documented model change, not an exact equivalence claim.

Interpret the resulting quantities carefully:

- Ipopt provides a locally feasible AC upper bound for this minimization
  problem, not proof of the global optimum.
- An SDP objective should lie below the Ipopt objective when the implemented
  constraint sets agree. The reported solver bound is numerical evidence, not
  a residual-corrected certificate.
- Agreement between IVRSDP and BranchFlowSDP is especially informative because
  the two formulations lift different variables. A disagreement can indicate
  different relaxations, inconsistent component coverage, or numerical error.
- Non-optimal Mosek runs remain explicit and contribute no objective or bound.
  Do not loosen feasibility tolerances merely to turn `SLOW_PROGRESS` into an
  accepted result; first check whether the objective is stable under scaling.
- BMOPFTools' `solution_check` independently checks its implemented quantities
  and explicitly records unassessed dimensions. `checks_passed` is therefore
  useful validation evidence, but not an independent replay of every equation.

### Per-unit scaling study

The BMOPF files and published results use SI units, while all three optimization
models use per-unit coordinates internally. `benchmark_enwl_sdp_scaling.jl`
checks that this coordinate choice does not silently change the SI objective:

```sh
julia --project=test/integration examples/benchmark_enwl_sdp_scaling.jl \
  ../BMOPFDraftData/benchmarks/ENWLbenchmark/reduced \
  examples/results/enwl_sdp_scaling_mosek.json
```

The broad sweep varies ``S_base`` from 1 to 100 kVA for both SDP formulations.
On the 10-bus numerical witness, a second grid varies objective normalization,
IVR state scaling (`global` versus `voltage_region`), and Mosek interior-point
scaling (`free` versus `none`). The voltage base remains the largest source
voltage magnitude. Failed iterates are retained only as diagnostics and never
included in reported objective intervals.
