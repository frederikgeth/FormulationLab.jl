# Optional BMOPFTools / Ipopt reference

`julia --project=test/integration test/integration/ivr_nameplate_reference.jl /tmp/nameplate-reference.json`
checks active/absent single-phase nameplate caps, dispatch and transformer result
fields against the local BMOPFTools checkout in per unit. It also checks that
both implementations reject a supplied zero rating. The exact-IVR run explicitly
uses `transformer_nameplate=:bmopftools`; the default native policy is retained.

The experimental native exact IVR comparison uses the same optional environment:

```sh
julia --project=test/integration test/integration/ivr_nlp_reference.jl /tmp/ivr-reference.json
```

It checks two-wire, three-wire delta, and four-wire wye/delta circuits against
BMOPFTools, including independent SI residual checks. This small panel contains
no controllable dispatch and makes no speedup claim.

BMOPFTools, Ipopt, and MosekTools are isolated here; none is a runtime or
default-test requirement. This environment uses the sibling BMOPFTools checkout
directly, without depending on PowerOptLab. Mosek experiments require a local
Mosek installation and license.

```sh
julia --project=test/integration -e 'using Pkg; Pkg.develop([PackageSpec(path="."), PackageSpec(path="../BMOPFTools.jl")]); Pkg.instantiate()'
julia --project=test/integration test/integration/relaxation_reference.jl /tmp/transformer-audit.json
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

See `docs/src/ac_validation.md` for the dated transformer audit and
`docs/src/ivr_reference_domains.md` for the scope of the later reference evidence. The older
`replay.jl` callback tests remain available, but the transformer audit is standalone
and does not require running the default suite first.

## Multiwinding correctness panels

All panels use declared per-unit bases. Run from the repository root, using a
separate output directory for each panel:

```sh
julia --project=test/integration --startup-file=no test/integration/ivr_nwinding_limits_reference.jl /tmp/nwinding-limits.json
julia --project=test/integration --startup-file=no test/integration/ivr_nwinding_connections_reference.jl /tmp/nwinding-connections/report.json
julia --project=test/integration --startup-file=no test/integration/ivr_nwinding_equalities_reference.jl /tmp/nwinding-equalities/report.json
julia --project=test/integration --startup-file=no test/integration/ivr_nwinding_equalities_reference.jl /tmp/nwinding-excitation/report.json --excitation
julia --project=test/integration --startup-file=no test/integration/ivr_nwinding_nonstar_reference.jl /tmp/nwinding-nonstar/report.json
```

The limits panel asserts single/three-phase all-wye scalar-cap agreement. The
connections panel retains mixed wye/delta outcomes under two stopping policies.
The equality and excitation panels retain both the original reference fixed-Q
inequalities and an exact equality intervention on a private model. The non-star
panel adds four windings, pair leakage, excitation and bound perturbations.
The reference checkout is not modified by the intervention.

For the latter four commands, inspect individual `accepted`, status, physical,
membership and comparison fields: successful process exit is not an all-cases-pass
claim. Failed endpoints remain in their reports. Reader round trips are distinct
from physical and optimization agreement. These correctness panels provide no
isolated runtime ranking; preserve their reference revisions and source hashes
when interpreting or reproducing them.
