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
build_opf(input, f::IVRSDP; optimizer=default_optimizer(), kwargs...) =
    build_sdp_opf(input, optimizer; options=f.options, kwargs...)

"""Solve a formulation. A relaxation result is not an AC-feasibility certificate."""
solve_opf(input, f::LinDist3Flow; optimizer=default_optimizer(), kwargs...) =
    solve_l3f_opf(input, optimizer; options=f.options, kwargs...)
solve_opf(input, f::IVRSDP; optimizer=default_optimizer(), kwargs...) =
    solve_sdp_opf(input, optimizer; options=f.options, kwargs...)
