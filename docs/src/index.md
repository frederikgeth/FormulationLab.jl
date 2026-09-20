# FormulationLab.jl

FormulationLab builds unbalanced power-flow approximations and relaxations from
BMOPF JSON through PowerIO. JuMP supplies the initial optimization backend;
optimizers are selected independently of the formulation.

```julia
using FormulationLab, Clarabel
input = read_bmopf("network.json")
result = solve_opf(input, IVRSDP(objective=:source_import);
                   solver_options=(verbose=false,))
```

[LinDist3Flow](lindist3flow.md) is a fixed-reference lossless approximation.
[IVRSDP](sdp.md) is a dense or chordal current–voltage semidefinite relaxation with explicit
winding connections, fixed-tap transformers, and regulators. [IVRSOC](soc.md) replaces its moment cones with SOC outer
relaxations with constant-power secants and optional fixed complex projections.
[BranchFlowSDP](branch_flow_sdp.md) is an experimental radial branch-flow
semidefinite relaxation with bus and edge moments and a deliberately narrower
series-line component contract. These results are not
AC feasibility certificates. Read the [coverage contract](coverage.md) before
selecting a formulation.

PowerIO is the only power-system runtime dependency. Clarabel is an optional
extension; MosekTools is an optional test dependency and can also be supplied by
a caller. ExaModels is deferred until a nonconvex formulation is implemented.
