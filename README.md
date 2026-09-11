# FormulationLab.jl

Unbalanced power-flow formulations with explicit mathematical scope and solver-oriented representations. PowerIO is the only power-system runtime dependency; JuMP is the initial modeling backend.

Implemented:

- **LinDist3Flow**: migrated from PowerOptLab, including affine/SOC limits, component lowering, applicability diagnostics, per-unit scaling, and IEEE/OpenDSS regression tests. This is a fixed-reference, lossless **approximation**, not an AC lower bound.
- **IVRSDP**: a dense or chordal semidefinite **relaxation** of current–voltage equations. It retains explicit neutrals and delta connections, eliminates linear electrical equations, and lifts voltage/current products. It supports the static AC electrical component families, including general multiwinding transformers and inverter capability models. Nonlinear loads use additional convex envelopes; control laws are not evaluated.

- **IVRSOC**: shares the SDP electrical model, replacing PSD cones with complex pairwise SOC minors, physical voltage–current projections, and optional eigenvector cuts. Load power cones are retained. See [the formulation and benchmarks](docs/src/soc.md).

```julia
using FormulationLab, Clarabel

input = read_bmopf("network.json")  # PowerIO parsing, retained diagnostics, SI data
result = solve_opf(input, LinDist3Flow(unsupported=:lower);
                   solver_options=(verbose=false,))

# On a case within the SDP subset:
sdp = solve_opf(input, IVRSDP(objective=:source_import);
               solver_options=(verbose=false,))

# SOC outer approximation, optionally tightened toward the SDP:
soc = solve_opf(input, IVRSOC(objective=:source_import);
                separation=PSDSeparationOptions(), solver_options=(verbose=false,))

# Build without attaching a solver, for inspection or customization:
build = build_opf(input, IVRSDP(); optimizer=nothing)
```

Programmatic BMOPF dictionaries are also accepted. They are copied, not modified, and do not imply schema validation. A PowerIO read preserves diagnostics; it does not certify that a formulation supports the document. Unsupported SDP fields are rejected explicitly.

Solvers are optional. Loading Clarabel enables formulation-specific defaults; explicit factories such as `optimizer=Clarabel.Optimizer` keep their own defaults. The SDP and SOC numerical profiles and measured tradeoffs are documented in [SDP numerics](docs/src/sdp_numerics.md) and [SOC outer approximation](docs/src/soc.md).

MosekTools can be passed as `optimizer=MosekTools.Optimizer` when installed by the caller. It is an **optional test dependency only** in this repository.

Results use SI units. SDP `relaxed_powers` are lifted power quantities; `voltage_candidate` uses source-column recovery by default and is not certified AC feasible. SOC results expose moment blocks without assuming PSD completion or recovering a voltage candidate. A solver-reported objective bound is numerical evidence, not a rigorous certificate. No AC optimality gap is claimed without a separately verified feasible upper bound.

## Tests

```sh
julia --project=test -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=test test/runtests.jl

# Optional, requires a local Mosek license:
julia --project=test/optional -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=test/optional test/optional/mosek.jl
```

The default test environment includes Clarabel, Ipopt (for migrated affine-model comparisons), and OpenDSSDirect. It has no BMOPFTools or Mosek dependency. Nonlinear BMOPFTools replay comparisons are retained separately in [test/integration](test/integration/README.md).

- [Architecture and next steps](docs/src/architecture.md)
- [BMOPF coverage](docs/src/coverage.md)
- [SDP equations, scope, and numerical interpretation](docs/src/sdp.md)
- [LinDist3Flow usage](docs/src/lindist3flow.md) and [component equations](docs/src/lindist3flow_components.md)
- [Migration provenance](docs/src/migration.md) and [verification results](docs/src/verification.md)

ExaModels is deferred until a nonconvex model is implemented. Full BMOPF coverage, chordal SDP, SOC relaxations/cuts, and benchmarked solver profiles are subsequent milestones.

## Documentation

Build the Documenter site locally:

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Open `docs/build/index.html`. Documentation CI builds the site on every pull
request and publishes a downloadable HTML artifact. Publication to GitHub Pages
can be enabled separately; no deployment credentials are needed for the build.

Optional lifted nonlinear cuts can strengthen the SDP on physical voltage maps:
use `IVRSDP(lnc=:lines)` for conservatively derived line bounds, or supply
`voltage_lncs` with explicit domain provenance. See the
[LNC formulation and usage](docs/src/lnc.md).
