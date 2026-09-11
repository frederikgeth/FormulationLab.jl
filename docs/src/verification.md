# Verification — 2026-09-11

| Check | Result |
|---|---|
| Default suite, Julia 1.10.11 | 1,508 passed, no skips |
| Default suite, Julia 1.12.6 | 1,508 passed, no skips |
| Optional MosekTools analytical SDP suite | 220 passed |
| New fixed-transformer OpenDSS comparisons (included above) | 42 passed |
| Documenter build and cross-reference checks | Passed |
| Separate BMOPFTools replay integration | 46 passed |
| Historical PowerOptLab adapter check (adapter subsequently removed) | 7 passed |
| Core package loading without a solver | Passed |
| Runtime/default-test dependency audit | No BMOPFTools, PowerOptLab, or Mosek dependency |
| PowerOptLab tracked diff whitespace check | Passed |

The default suite runs the migrated coefficient, component, applicability,
SI/per-unit, IEEE feeder, and OpenDSS oracle checks, plus new PowerIO-boundary,
callback, schema-spelling, independent-island, generic API, and SDP checks. The transformer extension adds 98 analytical and
contract checks plus 42 independent OpenDSS checks at unity and non-unity taps.
Mosek is isolated in `test/optional/Project.toml` and uses the same SDP tests.

The 46 replay checks were executed separately using the sibling PowerOptLab
Julia environment. The entire PowerOptLab test suite was not rerun; its
then-proposed forwarding API and nonlinear replay were checked by seven
integration checks. The adapter was subsequently removed from the PowerOptLab
PR; PowerOptLab has no FormulationLab dependency.

OpenDSSDirect 0.9.9 emits constructor-method/precompilation warnings on Julia
1.12.6 and falls back to loading without its cache. Its oracle tests nevertheless
run and pass. The Julia 1.10.11 suite also passes.

Clarabel 0.11.1 with OrderedCollections 2 reproduced an indexed-OrderedSet failure
in chordal PSD completion. The default optional Clarabel factory disables chordal
decomposition for this dense reference. Explicitly supplied optimizer factories
retain their own settings. No claim about a performance-optimal profile is made.

The static AC extension adds analytical grounding, switch/capacitor, inverter,
voltage-limit and load-envelope checks, plus 36 three-winding OpenDSS comparisons.
A non-star four-winding case checks coupled leakage independently.

A combined three-phase fixed inverter setpoint and delta-capacitor fixture exposed
Clarabel numerical sensitivity. Fixed P/Q boxes now compile as single equalities,
and source-fixed internal magnitude equations are not duplicated. The combined
regression checks optimal status and its analytical power result at the default
Clarabel settings, as well as with optional Mosek. Near-optimal statuses remain
unpublished as optimal results. These local encoding fixes are not a general
performance or reliability guarantee for the dense representation.

These tests establish the migrated L3F contracts and the declared static AC SDP
models and envelopes. They do not establish complete BMOPF coverage, scalable SDP performance,
rigorous numerical lower-bound certificates, or AC feasibility of a recovered
SDP voltage candidate.
