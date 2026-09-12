# IEEE service-feeder import fixes — 12 September 2026

The IEEE 8500 and 9500 service transformers now import with their intended
winding data. The 9500 linecode/static scenario builds, but its rated model is
infeasible. It solves when branch and transformer ratings are removed as a
separate diagnostic. The 8500 cases still fail topology applicability checks.
No AC feasibility or relaxation-gap claim follows from these runs.

## Changes and provenance

PowerIO branch `codex/ieee-service-imports`, commit `f6fb8081`, based on
`fa4d9da5`, is in the isolated worktree `/tmp/powerio-ieee-imports`.
The installed PowerIO.jl 0.11.0 binary has **not** been replaced. Experiments use
`POWERIO_CAPI=/tmp/powerio-ieee-imports/target/debug/libpowerio_capi.dylib`.

- Resolve initial named `XfmrCode` before subsequent transformer overrides.
  Previously, 1,177 / 1,275 service banks acquired default three-phase,
  roughly 7.2 kV / 7.2 kV / 7.2 kV, 1 MVA winding data. They now use their
  intended single-phase 7.2 kV / 120 V / 120 V data and individual code ratings.
  PowerIO's existing center-tap emitter then recognizes them; no speculative
  generic `n_winding` conversion was added to FormulationLab.
- Retain the scalar series reactor as a length-one diagonal impedance branch.
- Resolve DSS case-insensitive bus and linecode references to declared IDs.
- Apply default whole-terminal Open/Close commands to ideal switches. In the
  9500 master this preserves nine normally open switches. Partial-conductor
  commands and ordinary-line operations remain diagnosed as unsupported.
- FormulationLab accepts explicitly selected `:wye_terminal` impedance aliases,
  preserves winding-2 exciting branches, and aggregates identical parallel
  ideal-switch contacts and their ratings before neutral reduction.

Initial XfmrCode support is deliberately bounded: missing, late, repeated,
empty, positional, abbreviated or otherwise unsupported templates are retained
untyped with diagnostics. This is not general OpenDSS template execution.

Sources are the previously downloaded feeders under
`/Users/uqfgeth/Downloads/ieee-test-feeders-2026-09-12`; checksums, licenses and
upstream revisions are in the earlier download manifest. Original files are
unchanged. The 9500 run selects the upstream linecode alternative because the
geometry importer remains incomplete.

## Numerical checks

Julia 1.12.6, one Julia and BLAS thread, Clarabel, per-unit power base 1 MVA,
`unsupported=:approximate`, fixed written transformer taps. Controls are not
simulated. Timings below are solver-reported times from one run, not repeated
performance benchmarks. The objective is zero: this is a feasibility check.

| Scenario | Outcome | Clarabel solve time |
|---|---|---:|
| IEEE 8500 balanced, radial | Rejected: one conductor-cycle finding | — |
| IEEE 8500 unbalanced, radial | Rejected: same conductor-cycle finding | — |
| IEEE 8500 balanced, meshed | Rejected: regulator bridge restriction and unreachable terminals | — |
| IEEE 9500 unbalanced, linecodes, static idle batteries, ratings retained | Builds 41,169 variables; `INFEASIBLE` | 1.118 s |
| Same 9500 scenario, branch/source/transformer ratings removed | `OPTIMAL` for this altered feasibility problem | 0.556 s |

The last row removes 4,080 rating fields from lines, linecodes, switches,
voltage sources and transformers; IBR capability limits remain. This isolates
an incompatibility involving the retained ratings, but does not identify which
rating or prove that any particular bound is wrong. The default retains every
rating. No feasible physical state is reported from the infeasibility
certificate. Detailed counts and errors are in the adjacent JSON report.

The corrected 9500 snapshot has 5,302 buses, 3,913 lines (including the reactor),
110 switches (nine open), 1,275 center taps, 33 single-phase transformers,
18 single-phase regulators, one delta/wye bank, 178 IBRs and 12 generators.
There are 2,552 loads, including two explicit static battery equivalents.

An independent OpenDSSDirect probe of the battery definition confirms the
initially full storage becomes **Idling** after a snapshot solve: `kW=-2.5`,
`kvar=0`, and three terminal powers of approximately 0.833333 kW each. The staged
scenario uses two constant-power 2.5 kW idle loads. This is an explicit static
approximation; it does not represent energy dynamics or the requested charging
state of a battery with available energy capacity. No battery is silently lost.

## Reproduction

Build the local PowerIO branch with `cargo build -p powerio-capi --offline`, then
set `POWERIO_CAPI` as above. Use the repository test environment for Julia.

```sh
python3 examples/prepare_ieee9500_static.py ORIGINAL_9500_BASE NEW_STATIC_DIRECTORY
julia --project=test examples/export_large_ieee.jl NEW_STATIC_DIRECTORY/Master-unbal-initial-config.dss /tmp/9500.json
julia --project=test examples/check_large_ieee_snapshot.jl /tmp/9500.json /tmp/9500-results.json
```

For 8500, export `Master.dss` or `Master-unbal.dss` directly. An optional third
argument `meshed_linear` to the checker selects the existing meshed mode.
Export also writes parser provenance and diagnostics beside the snapshot.

## Validation and next work

- FormulationLab: 5,694 tests pass, including SI/per-unit exciting-branch
  equivalence, wye-side alias placement and duplicate-switch aggregation.
- Documenter builds successfully.
- PowerIO: full distribution and C API suites pass; 40 DSS reader regressions
  pass, including transformer template winding values, reactor RPN impedance,
  reference case resolution and switch state. Rust formatting passes.

Next, isolate conflicting 9500 ratings without changing the defaults, and
compare dispatch/voltages against a consistently frozen OpenDSS snapshot.
For 8500, trace the cycle and the implicit switch conductors against OpenDSS;
then extend meshed support for phase-separated parallel regulator banks only
with a conductor-aware reference and cycle contract. Do not remove branches or
weaken connectivity checks merely to obtain a solve.
