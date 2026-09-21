# Formulation and input API

```@autodocs
Modules = [FormulationLab]
Pages = ["api.jl", "bmopf.jl", "sdp.jl", "branch_flow_sdp.jl", "soc.jl",
         "contracts.jl", "relaxation.jl"]
```

```@docs
kron_reduce_bmopf
```

## Network preparation and reconstruction

```@docs
ReductionOptions
ReductionPlan
PreparedNetwork
prepare_network
reduction_report
reconstruction_plan
restore_prepared_network
ReconstructedSolution
reconstruct_solution
```
