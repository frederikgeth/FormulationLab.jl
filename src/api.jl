"""An electrical formulation, independent of the optimizer used to solve it."""
abstract type AbstractFormulation end

"""Fixed-reference, lossless radial approximation with affine/SOC limits."""
struct LinDist3Flow <: AbstractFormulation
    options::L3FOptions
end
LinDist3Flow(;kwargs...) = LinDist3Flow(L3FOptions(;kwargs...))

"""Dense current–voltage semidefinite relaxation for its declared component subset."""
struct IVRSDP <: AbstractFormulation
    options::SDPOptions
end
IVRSDP(;kwargs...) = IVRSDP(SDPOptions(;kwargs...))

formulation_kind(::LinDist3Flow) = :approximation
formulation_kind(::IVRSDP) = :relaxation

"""Build an inspectable formulation with a separately supplied optimizer factory."""
build_opf(input, f::LinDist3Flow; optimizer=default_optimizer(), kwargs...) =
    build_l3f_opf(input, optimizer; options=f.options, kwargs...)
build_opf(input, f::IVRSDP; optimizer=default_sdp_optimizer(), kwargs...) =
    build_sdp_opf(input, optimizer; options=f.options, kwargs...)

"""Solve a formulation. A relaxation result is not an AC-feasibility certificate."""
solve_opf(input, f::LinDist3Flow; optimizer=default_optimizer(), kwargs...) =
    solve_l3f_opf(input, optimizer; options=f.options, kwargs...)
solve_opf(input, f::IVRSDP; optimizer=default_sdp_optimizer(), kwargs...) =
    solve_sdp_opf(input, optimizer; options=f.options, kwargs...)

"""
    IVRSOC(; profile=:clarabel, kwargs...)

Fixed SOC/power-cone relaxation. `profile=:fast` selects sparse coordinates and
linear strengthening; `:balanced` adds up to eight fixed Kim triplets. Both use
`clique_size=32`. Explicit keyword options override these presets. The existing
`:clarabel` (default) and `:reference` electrical profiles remain available.
Presets do not change solver tolerances, reduction, or the electrical contract.
"""
struct IVRSOC <: AbstractFormulation
    options::SOCOptions
end
function IVRSOC(;profile=:clarabel,physical_projections=true,voltage_recovery=:voltage_tree,
    strengthening=nothing,max_triplets=nothing,directions=(1.0+0im,1.0im),kwargs...)
    profile in (:clarabel,:reference,:fast,:balanced) || throw(ArgumentError("unknown SOC profile: $profile"))
    preset=profile in (:fast,:balanced)
    defaults=preset ? (profile=:clarabel,basis=:sparse,clique_size=32,state_scaling=:global) : (profile=profile,state_scaling=:global)
    electrical=SDPOptions(;merge(defaults,(;kwargs...))...)
    strength=strengthening===nothing ? (profile==:balanced ? :kim : :linear) : strengthening
    budget=max_triplets===nothing ? (profile==:balanced ? 8 : 16) : max_triplets
    IVRSOC(SOCOptions(;profile,electrical,physical_projections,voltage_recovery,
        strengthening=strength,max_triplets=budget,directions))
end
formulation_kind(::IVRSOC)=:relaxation
build_opf(input,f::IVRSOC;optimizer=default_soc_optimizer(),kwargs...)=build_soc_opf(input,optimizer;options=f.options,kwargs...)
solve_opf(input,f::IVRSOC;optimizer=default_soc_optimizer(),kwargs...)=solve_soc_opf(input,optimizer;options=f.options,kwargs...)
