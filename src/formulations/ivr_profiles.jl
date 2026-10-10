"""Named exact-IVR option sets.

Profiles collapse the individual compiler options into a few supported choices.
Explicit keywords passed alongside a profile override its settings. Every
profile solves the same physical problem; the reductions it enables are exact
and refuse or fall back when their certificates do not hold.

- `:reference`: the unreduced, unlifted model with global per-unit bases. Use it
  for correctness comparisons.
- `:fast`: power lifting, conductor-region specialization, bounded passive-block
  elimination, certified zero-load elimination and per-voltage-zone
  (transformer-nominal) coordinates. On the 2026-10 MV/LV benchmark this was the
  fastest and most reliable Ipopt configuration. Most of the gain comes from the
  per-zone coordinates. See `docs/src/ivr_findings.md`.
- `:scaled`: power lifting and per-zone coordinates without structural
  reductions. This is a conservative choice when a reduction certificate is
  undesirable, for example before changing an eliminated zero load to nonzero
  demand.
"""
const IVR_PROFILES = Dict{Symbol,NamedTuple}(
    :reference => (;),
    :fast => (lifting=:powers, specialization=:conductor_regions,
              linear_elimination=:passive_blocks, zero_load_elimination=true,
              transformer_scaling=:nominal),
    :scaled => (lifting=:powers, transformer_scaling=:nominal),
)

"""
    ivr_ipopt_options(; kwargs...)

Recommended Ipopt settings for exact IVR. These are the Ipopt defaults except
`mumps_pivtol=1e-3`: a larger initial MUMPS pivot tolerance avoids the repeated
pivot-tolerance increases and refactorizations that otherwise dominate solve
time on poorly scaled KKT systems. Keywords add or override options; pass the
result as `solver_options`.
"""
ivr_ipopt_options(;kwargs...)=(; print_level=0, mumps_pivtol=1e-3, kwargs...)

function _ivr_profile_options(profile::Symbol;kwargs...)
    haskey(IVR_PROFILES,profile) ||
        throw(ArgumentError("unknown IVRNLP profile :$profile; choose one of $(sort!(collect(keys(IVR_PROFILES))))"))
    IVRNLPOptions(; IVR_PROFILES[profile]..., kwargs...)
end
