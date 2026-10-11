# FormulationLab.jl

[![Documentation](https://img.shields.io/badge/docs-latest-blue.svg)](https://frederikgeth.github.io/FormulationLab.jl/)

Unbalanced power-flow formulations with explicit mathematical scope and solver-oriented representations. PowerIO is the only power-system runtime dependency; JuMP is the initial modeling backend.

Implemented:

- **IVRNLP (experimental)**: exact static current–voltage equations, physical
  magnitude limits, reusable load demands, and generator boxes/prices. Requires an
  explicit nonlinear optimizer and supports lines, sources, shunts, fixed switches,
  capacitors, fixed transformers/regulators, static IBRs, constant-power/impedance
  loads and voltage-dependent current/ZIP/exponential laws on certified positive
  coil-voltage domains. Optional certified radial
  whole-section or pendant-region conductor specialization retains physical
  limits and boundary equations; local
  solves carry no global optimality guarantee. See [exact IVR](docs/src/ivr_nlp.md), its [equations](docs/src/ivr_theory.md)
  and the [build–verify–reuse tutorial](docs/src/tutorial_exact_ivr.md).
  Optional exact P/Q/observation lifting and charged π-section block elimination
  preserve original physical limits and result observations. For performance,
  use `IVRNLP(profile=:scaled, ...)` with `solver_options=ivr_ipopt_options()`;
  see the [performance findings](docs/src/ivr_findings.md) and the
  [benchmark method](docs/src/ivr_benchmarking.md).
- **LinIVR (experimental)**: no-load current–voltage approximation retaining
  explicit neutrals and power decision variables, without Kron reduction or a
  loaded starting point. Includes SOC physical limits, optional quadratic
  line/shunt/transformer/filter loss minimization, and device-power mismatch diagnostics. See the
  [formulation and experiment](docs/src/linivr.md).
- **LinDist3Flow**: migrated from PowerOptLab, including affine/SOC limits, component lowering, applicability diagnostics, per-unit scaling, and IEEE/OpenDSS regression tests. This is a fixed-reference, lossless **approximation**, not an AC lower bound.
- **IVRSDP**: a dense or chordal semidefinite **relaxation** of current–voltage equations. It retains explicit neutrals and delta connections, eliminates linear electrical equations, and lifts voltage/current products. It supports the static AC electrical component families, including general multiwinding transformers and inverter capability models. Nonlinear loads use additional convex envelopes; control laws are not evaluated.

- **IVRSOC**: shares the SDP electrical model, replacing PSD cones with complex pairwise SOC minors, physical voltage–current projections, constant-power secants, and optional fixed complex three-map projections. Load power cones are retained. See [the formulation and benchmarks](docs/src/soc.md).

- **BranchFlowSDP**: an experimental multiphase branch-flow SDP with bus voltage
  moments, line ``W/S/L`` blocks including endpoint shunts, full matrix KCL,
  local connection and transformer moments, and a voltage-closure Gram for
  meshes, multiple sources and cross-bus cuts. It supports fixed switches,
  capacitors, delta generators, general multiwinding transformers, power-cone
  load envelopes, physical voltage maps and optional LNCs. Static IBRs remain
  outside this formulation.

```julia
using FormulationLab, Clarabel

input = read_bmopf("network.json")  # PowerIO parsing, retained diagnostics, SI data
result = solve_opf(input, LinDist3Flow(unsupported=:lower);
                   solver_options=(verbose=false,))

# On a case within the SDP subset:
sdp = solve_opf(input, IVRSDP(objective=:source_import);
               solver_options=(verbose=false,))

# Fixed SOC relaxation, built once and solved once:
soc = solve_opf(input, IVRSOC(objective=:source_import);
                solver_options=(verbose=false,))

# Branch-flow SDP; optional line LNCs use conservative declared bounds:
bfm = solve_opf(input, BranchFlowSDP(objective=:source_import, lnc=:lines);
                solver_options=(verbose=false,))

# Named fixed profiles (explicit keyword options override presets):
fast = IVRSOC(profile=:fast)
balanced = IVRSOC(profile=:balanced)

# Shared BMOPFTools-compatible reduction and original-network reconstruction:
prepared = prepare_network(input; reduction=:bmopf)
reduced = solve_opf(prepared, IVRSOC(); solver_options=(verbose=false,))
full = reconstruct_solution(prepared, reduced)

# Build without attaching a solver, for inspection or customization:
build = build_opf(input, IVRSDP(); optimizer=nothing)
```

Programmatic BMOPF dictionaries are also accepted. They are copied, not modified, and do not imply schema validation. A PowerIO read preserves diagnostics; it does not certify that a formulation supports the document. Unsupported SDP fields are rejected explicitly.

All six formulations support `result_dict(network, result)`, `write_result` and
`read_result` for a shared BMOPFTools-style physical result layout in SI units.
Exact-IVR reductions restore the original observations; approximate and relaxed
phasors are labelled, and unavailable values remain explicit. See the
[result contract and JSON conventions](docs/src/results.md).

Solvers are optional. Loading Clarabel enables formulation-specific defaults; explicit factories such as `optimizer=Clarabel.Optimizer` keep their own defaults. The SDP and SOC numerical profiles and measured tradeoffs are documented in [SDP numerics](docs/src/sdp_numerics.md) and [Fixed SOC relaxation](docs/src/soc.md).

MosekTools can be passed as `optimizer=MosekTools.Optimizer` when installed by the caller. It is an **optional test dependency only** in this repository.

Results use SI units. SDP `relaxed_powers` are lifted power quantities; `voltage_candidate` uses source-column recovery by default and is not certified AC feasible. SOC results expose moment blocks and an estimated voltage state recovered through a voltage-correlation tree, without assuming PSD completion. A solver-reported objective bound is numerical evidence, not a rigorous certificate. No AC optimality gap is claimed without a separately verified feasible upper bound.

## Tests

```sh
julia --project=test -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=test test/runtests.jl

# Optional, requires a local Mosek license:
julia --project=test/optional -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=test/optional test/optional/mosek.jl
```

The default test environment includes Clarabel, Ipopt (for exact IVR and nonlinear reference comparisons), and OpenDSSDirect. It has no BMOPFTools or Mosek dependency. Nonlinear BMOPFTools replay comparisons are retained separately in [test/integration](test/integration/README.md).

- [Motivating exact-IVR examples](docs/src/ivr_examples.md) and the
  [executable tutorial](docs/src/tutorial_exact_ivr.md)
- [Select an exact-IVR profile](docs/src/ivr_selection.md) and inspect the
  [validation evidence map](docs/src/ivr_validation.md)
- [Choose a formulation](docs/src/formulations.md) and review the shared
  [notation and conventions](docs/src/notation.md)
- [Literature and formulation lineage](docs/src/literature.md)
- [SOC profiles and structural sparsity](docs/src/soc_profiles.md)
- [Formulation decisions and experimental lessons](docs/src/formulation_choices.md)
- [Architecture and next steps](docs/src/architecture.md)
- [BMOPF coverage](docs/src/coverage.md)
- [SDP equations, scope, and numerical interpretation](docs/src/sdp.md)
- [Branch-flow SDP](docs/src/branch_flow_sdp.md)
- [LinDist3Flow usage](docs/src/lindist3flow.md) and [component equations](docs/src/lindist3flow_components.md)
- [Migration provenance](docs/src/migration.md) and [verification results](docs/src/verification.md)

ExaModels is deferred while the experimental exact IVR baseline is evaluated.
Fixed SOC solve performance and validated state recovery remain active work;
DC and time-series semantics remain separately scoped.

## Documentation

The latest documentation is published at
[frederikgeth.github.io/FormulationLab.jl](https://frederikgeth.github.io/FormulationLab.jl/).

Build the Documenter site locally:

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Open `docs/build/index.html`. Documentation CI builds the site on every pull
request and publishes a downloadable HTML artifact. Successful builds on `main`
are deployed to GitHub Pages using GitHub's short-lived OIDC credentials.

Optional lifted nonlinear cuts can strengthen either SDP on physical voltage maps:
use `IVRSDP(lnc=:lines)` or `BranchFlowSDP(lnc=:lines)` for conservatively
derived line bounds, or supply
`voltage_lncs` with explicit domain provenance. See the
[LNC formulation and usage](docs/src/lnc.md).

See [network reduction and state reconstruction](docs/src/reduction.md) for policies, approximation warnings, portable plans, and the [numerical study](examples/results/reduction_study_2026-09-11.md).

LinDist3Flow also offers explicit impedance-alias normalization and a fixed
meshed-line approximation; see [the input and mesh contract](docs/src/lindist3flow_mesh.md).
