# Verification — 2026-09-11

| Check | Result |
|---|---|
| Default suite, Julia 1.10.11 | 1,254 passed, no skips |
| Default suite, Julia 1.12.6 | 1,254 passed, no skips |
| Optional MosekTools SDP suite | 44 passed |
| Separate BMOPFTools replay integration | 46 passed |
| PowerOptLab migration adapter | 7 passed |
| Core package loading without a solver | Passed |
| Runtime/default-test dependency audit | No BMOPFTools, PowerOptLab, or Mosek dependency |
| PowerOptLab tracked diff whitespace check | Passed |

The default suite runs the migrated coefficient, component, applicability,
SI/per-unit, IEEE feeder, and OpenDSS oracle checks, plus new PowerIO-boundary,
callback, schema-spelling, independent-island, generic API, and SDP checks.
Mosek is isolated in `test/optional/Project.toml` and uses the same SDP tests.

The 46 replay checks were executed separately using the sibling PowerOptLab
Julia environment. The entire PowerOptLab test suite was not rerun; its
forwarding API, normalized status/diagnostics, and nonlinear replay were checked
by the seven new integration checks. These checks used a local development dependency; the PowerOptLab migration
pins the published FormulationLab commit for reproducible installation.

OpenDSSDirect 0.9.9 emits constructor-method/precompilation warnings on Julia
1.12.6 and falls back to loading without its cache. Its oracle tests nevertheless
run and pass. The Julia 1.10.11 suite also passes.

Clarabel 0.11.1 with OrderedCollections 2 reproduced an indexed-OrderedSet failure
in chordal PSD completion. The default optional Clarabel factory disables chordal
decomposition for this dense reference. Explicitly supplied optimizer factories
retain their own settings. No claim about a performance-optimal profile is made.

These tests establish the migrated L3F contracts and the declared initial SDP
subset. They do not establish complete BMOPF coverage, scalable SDP performance,
rigorous numerical lower-bound certificates, or AC feasibility of a recovered
SDP voltage candidate.
