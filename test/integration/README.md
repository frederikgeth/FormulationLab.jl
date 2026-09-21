# Optional BMOPFTools / Ipopt reference

BMOPFTools, Ipopt, and MosekTools are isolated here; none is a runtime or
default-test requirement. This environment uses the sibling BMOPFTools checkout
directly, without depending on PowerOptLab. Mosek experiments require a local
Mosek installation and license.

```sh
julia --project=test/integration -e 'using Pkg; Pkg.develop([PackageSpec(path="."), PackageSpec(path="../BMOPFTools.jl")]); Pkg.instantiate()'
julia --project=test/integration test/integration/relaxation_reference.jl /tmp/transformer-audit.json
julia --project=test/integration test/integration/mosek_bound_diagnostics.jl
```

The reproducible small-ENWL comparison uses BMOPFTools/Ipopt as a local AC
reference and Mosek for both SDP formulations:

```sh
julia --project=test/integration examples/benchmark_nlp_sdp_enwl.jl \
  ../BMOPFDraftData/benchmarks/ENWLbenchmark/reduced /tmp/enwl-nlp-sdp.json
```

See `examples/README_nlp_soc_experiments.md` for the input transformation and
the limits on interpreting local NLP points and numerical SDP bounds.

Add `--smoke` for one single-phase case. The full audit runs 25 NLP cases,
independently checks their SI residuals, and checks valid states against dense
SDP, chordal SDP, SOC-linear and SOC-Kim. It then solves those relaxations with
Clarabel and checks their objectives against the feasible NLP value within a
numerical tolerance. This is not a certified dual-bound calculation.

JSON output records the reference package path/revision, versions, input hashes,
observed versus reconstructed channels, physical residuals and containment
residuals. Inferred internal currents are not independent measurements. Failed
reference solves and incompatible states remain explicit report entries; they
are never silently accepted or used for objective comparisons. The known-good
single-phase and regulator cases are assertions, so regressions fail the run.

See `docs/src/ac_validation.md` for current transformer disagreements. The older
`replay.jl` callback tests remain available, but the transformer audit is standalone
and does not require running the default suite first.
