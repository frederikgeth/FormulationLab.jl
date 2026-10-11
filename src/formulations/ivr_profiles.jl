"""Named exact-IVR option sets.

Profiles collapse the individual compiler options into a few supported choices.
Explicit keywords passed alongside a profile override its settings. Every
profile solves the same physical problem; the reductions it enables are exact
and refuse or fall back when their certificates do not hold.

- `:reference`: the unreduced, unlifted model with the default per-zone
  coordinates. Use it for correctness comparisons. Pass
  `transformer_scaling=:off` for a single global per-unit base.
- `:scaled`: power lifting and per-voltage-zone (transformer-nominal)
  coordinates. This is the recommended default profile. In the 2026-10 benchmark the
  per-zone coordinates carried almost all of the Ipopt speedup, and this profile
  was within 1.5x of the best arm on every instance tested.
- `:fast`: `:scaled` plus conductor-region specialization, bounded
  passive-block elimination and certified zero-load elimination. It was about
  13% faster than `:scaled` on French MV/LV feeders but 2.1x slower on a 22k-bus
  network under default Ipopt, so benchmark it on your workload before
  preferring it. See `docs/src/ivr_findings.md`.
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
