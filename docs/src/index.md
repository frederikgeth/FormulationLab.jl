# FormulationLab.jl

FormulationLab builds terminal-explicit unbalanced power-flow approximations and
convex relaxations from BMOPF data. It is a laboratory for comparing electrical
formulations, bound semantics, conic representations and recovery methods under
one input and result contract.

If you are new to the package, begin with:

1. [Choosing a formulation](formulations.md), which separates approximations,
   relaxations, solver representations and recovered candidates;
2. [Notation and conventions](notation.md), which defines the shared
   ``U/I/S/W/L`` matrix notation, connection maps, signs and units; and
3. [Component coverage](coverage.md), which states what each formulation
   actually accepts.

The [literature map](literature.md) relates the implementations to published
BIM, BFM, IVR, chordal, SOC and strengthening results without importing their
assumptions or exactness claims wholesale.

## First solve

```julia
using FormulationLab, Clarabel
input = read_bmopf("network.json")
result = solve_opf(input, IVRSDP(objective=:source_import);
                   solver_options=(verbose=false,))
```

`read_bmopf` uses PowerIO. JuMP supplies the optimization model; the optimizer is
selected independently of the electrical formulation. BMOPF input and public
results are in SI units. Conic formulations use internal per-unit coordinates,
and expose the selected bases in their diagnostics.

## Formulation families

- [LinDist3Flow](lindist3flow.md) is a fixed-reference, lossless approximation.
- [IVRSDP](sdp.md) is a dense or chordal current--voltage semidefinite
  relaxation with explicit component currents and winding equations.
- [IVRSOC](soc.md) keeps the IVR electrical maps but replaces PSD cones with
  SOC outer approximations and optional fixed projections.
- [BranchFlowSDP](branch_flow_sdp.md) retains classic bus-voltage,
  line-power and line-current moments, full matrix KCL, local connection and
  transformer blocks, and conditional voltage closure for meshes and multiple
  sources.

These models can agree at a rank-one AC point while behaving differently after
relaxation. A solver-reported optimum, small rank ratio or reconstructed voltage
is not by itself an AC-feasibility certificate. Use the [verification](verification.md)
and [AC containment](ac_validation.md) guidance when interpreting results.

## Package boundaries

PowerIO is the only power-system runtime dependency. Clarabel is an optional
extension; MosekTools is an optional test dependency and can also be supplied by
a caller. ExaModels is deferred until a nonconvex formulation is implemented.

For implementation structure, see [architecture](architecture.md). For
numerical profiles and measured behavior, see [SDP numerics](sdp_numerics.md),
[SOC profiles](soc_profiles.md), and the [formulation decision
record](formulation_choices.md).
