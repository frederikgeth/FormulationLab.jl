# PowerIO compatibility and IEEE feeder roadmap

FormulationLab consumes BMOPF through PowerIO. The IEEE experiments expose
conversion gaps as well as formulation restrictions; successful parsing is not
proof that all electrical components survived conversion. The changes below
refer to the tested local PowerIO commit `f6fb8081` on
`codex/ieee-service-imports`, based on `fa4d9da5`, in the Rust repository
`eigenergy/powerio`. They are not changes to the PowerIO.jl wrapper.

## What is already fixed locally

| Area | Tested local behavior | Remaining boundary |
|:--|:--|:--|
| `XfmrCode` | An initial named template supplies winding data before later explicit overrides. IEEE service banks export as center taps. | Missing, late, repeated, positional or unsupported templates are diagnosed and retained untyped. |
| Series reactor | Scalar R+jX between distinct phase-only buses becomes a diagonal series branch; expressions are evaluated. | Matrix, sequence, parallel-loss and other reactor specification profiles are outside this lowering. |
| Identifier case | DSS bus and linecode references resolve to the declared export identifiers. | Continue exercising mixed-case references in regression cases for other object classes. |
| Switch state | Default whole-terminal Open/Close commands on typed ideal switches are applied. | Partial-conductor and ordinary-line switching are not implemented by this profile. |

The original repository is `/Users/uqfgeth/Documents/GitHub/powerio`; the isolated
worktree is `/tmp/powerio-ieee-imports`. The installed PowerIO.jl 0.11.0 artifact
was not replaced. A FormulationLab checkout alone therefore cannot reproduce
the corrected IEEE import. Build the PowerIO branch and explicitly select its
C API library through `POWERIO_CAPI`. The FormulationLab package dependency
remains PowerIO; no dependency on the Rust worktree is added to `Project.toml`.

The immediate integration task is to review and merge these Rust fixes, then
make them available through the PowerIO binary distribution used by PowerIO.jl.
This document does not claim that the local commit has been published upstream.

## Missing PowerIO capabilities, in priority order

1. **Complete line geometry and cable conversion.** The original and converted
   IEEE 9500 decks each encountered 2,626 unresolved geometry lines. The supplied
   linecode variant is a useful workaround, but equivalence to the geometry deck
   has not been established. Support the actual WireData/CNData/TSData and
   geometry/spacing combinations used by these decks, preserving conductor
   order, units, frequency, earth-return assumptions and shunts. Compare the
   resulting series/shunt matrices against OpenDSS before claiming equivalence.
2. **Faithful static operating-state export.** Support terminal/conductor-level
   switching and opening ordinary lines, with source-order behavior. Preserve
   fixed capacitor states, written taps and DER dispatch. Static control
   *results* can be imported from an explicitly frozen external snapshot; this
   does not require implementing volt-var, volt-watt or regulator control laws
   in FormulationLab.
3. **Explicit storage snapshot support.** Original 9500 imports drop two storage
   objects. The current example replaces them with named 2.5 kW idle loads after
   checking their initially full state in OpenDSS. Generalize this into an
   explicit snapshot contract: AC P/Q, sign convention, losses, capability
   limits, operating state and provenance. Never infer a feasible charging
   state from a written charge command alone. Energy dynamics are outside the
   present static scope.
4. **Broader transformer-template semantics.** Implement late/repeated XfmrCode
   assignment and its interaction with winding edits, defaults, abbreviations,
   positional properties and inheritance using the engine's assignment order.
   Keep asymmetric multiwinding banks generic when a center-tap subtype would
   lose unequal taps, impedances, ratings or winding polarity.
5. **Broader reactor models.** Add the reactor specification profiles that occur
   in target datasets, with tests for their series and shunt admittance. A
   scalar series equivalent is not generally sufficient for coupled or parallel
   reactor models.
6. **Canonical electrical conventions and diagnostics.** Emit unambiguous
   reference-side leakage fields, or explicit provenance for aliases. The
   current FormulationLab `:wye_terminal` option is a caller-selected contract
   for the verified Yd/Dy DSS export, not a universal BMOPF assumption. Preserve
   whether ratings were written, defaulted or inferred; make omitted electrical
   devices and unsupported state operations readily distinguishable from
   retained presentation metadata.

Each extension needs a small synthetic regression and an independent OpenDSS
comparison of the relevant quantities. Large feeder counts alone cannot detect
an incorrect voltage base, omitted branch or wrong winding polarity.

## Findings that are not established PowerIO bugs

**IEEE 9500 rating infeasibility:** the corrected linecode scenario, with explicit
idle batteries, passes radial applicability and builds 41,169 variables. Clarabel
reports `INFEASIBLE` in 1.118 s. A separate diagnostic removing 4,080
branch/source/transformer rating fields solves in 0.556 s. This implicates the
rating constraints but does not identify a bad parser bound: genuine overload,
limit semantics, default ratings or the L3F approximation may be responsible.
The next step is to isolate conflicting limits and compare their values and
physical winding interpretation against the source and OpenDSS. Defaults remain
unchanged; the unrated run is not a solution of the rated problem.

**IEEE 8500 topology:** both load variants fail the radial conductor-cycle check.
The meshed mode additionally rejects phase-separated parallel regulator banks
under its current bus-bridge rule and reports unreachable terminals associated
with switch definitions. Trace those terminals against OpenDSS first. Extending
FormulationLab requires a conductor-aware reference and cycle treatment for
parallel regulator banks; weakening the existing bridge/reachability checks is
not a compatibility fix.

**AC accuracy:** there is no frozen full-feeder AC replay for these corrected
large cases yet. The reported times are single feasibility runs with zero
objective, not repeated benchmarks or relaxation-gap measurements.

## Evidence and reproduction

The repository contains:

- `examples/results/ieee_loading_audit_2026-09-12.md`: the original-artifact audit,
  including geometry failures; its initial transformer diagnosis is superseded.
- `examples/results/ieee_import_fixes_2026-09-12.md` and adjacent JSON: corrected
  imports, counts, exact model outcomes, timings, known limitations and commands.
- `examples/results/ieee_loading_sources_2026-09-12.json`: upstream revisions,
  licenses and source-file hashes.
- `examples/export_large_ieee.jl`, `examples/check_large_ieee_snapshot.jl` and
  `examples/prepare_ieee9500_static.py`: export, applicability/solve and explicit
  static-scenario preparation. Original datasets are not rewritten.

FormulationLab validation at the implementation commit: 5,694 passing tests and
successful Documenter build. PowerIO validation: distribution and C API tests,
including 40 DSS reader regressions, and Rust formatting. These checks cover the
implemented profiles; they do not certify complete OpenDSS compatibility.
