# Migration provenance

LinDist3Flow source, tests, component equations, and the required Kron helper
were copied from `frederikgeth/PowerOptLab.jl`, local commit
`f919dbdab37a70b6fcf329ab966d9ef8d5ad10ac` (2026-09-11 migration).
Original copyright and license are retained in LICENSE.md. Dataset provenance
embedded in the IEEE test constructors is retained; LICENSE-DATA.md is retained.

The six original formulation files and ten L3F test/fixture files have moved.
The PowerOptLab removal PR deletes the L3F API without a forwarding adapter or
FormulationLab dependency. Its shared Kron utility
remains there because other PowerOptLab workflows use it; FormulationLab contains
the migrated helper it needs, with independent parsing/serialization boundaries.

Changes from the migrated implementation:

- PowerIO ingestion through a source-preserving adapter, with diagnostics/digest.
- Standalone per-unit preparation, including multiple independent islands and
  linecode specialization across voltage levels. No external model initialization.
- Optional Clarabel extension; no runtime Ipopt, BMOPFTools, or PowerOptLab.
- Explicit `powerflow` callback for nonlinear replay and reference construction.
- `model_kind="approximation"` and `provides_ac_lower_bound=false` on L3F results.
- Proposal tap-name normalization and explicit refusal of additional DC/time-series tables.

The original nonlinear replay testsets were moved to `test/integration/replay.jl`.
They remain executable with BMOPFTools supplied by a separate environment. Main
suite callback tests use a labeled test double solely to test API plumbing.

The first SDP and generic formulation API are new code. Their support is narrower
than L3F's and is explicitly listed in coverage.md; neither is advertised as full
BMOPF support.
