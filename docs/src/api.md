# Formulation and input API

```@autodocs
Modules = [FormulationLab]
Pages = ["api.jl", "bmopf.jl", "sdp.jl", "branch_flow_sdp.jl", "soc.jl",
         "linivr.jl", "contracts.jl", "relaxation.jl"]
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

## Exact IVR construction, updates and assessment

The [tutorial](tutorial_exact_ivr.md) demonstrates these routines. The
[scope and result contract](ivr_nlp.md) defines channel ordering, SI units and
fallback behavior. Internal coordinate maps are implementation details.
Independent SI checks are documented under [`physical_residuals`](@ref).

```@docs
IVRNLPOptions
IVRNLPBuild
IVRNLPResult
IVRNLPInapplicableError
build_ivr_nlp_opf
solve_ivr_nlp_opf
update_ivr_loads!
update_ivr_generators!
ivr_nlp_point_report
```


## Common result dictionary and JSON

See the [physical result contract](results.md) for field semantics and recovery limits.

```@docs
result_dict
write_result
read_result
```
