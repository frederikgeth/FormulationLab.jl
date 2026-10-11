# Strict Ipopt solves (tol ~1e-10, no bound relaxation, no acceptable exit) sit
# close to the limits of double precision. Whether one ends at LOCALLY_SOLVED
# or ALMOST_LOCALLY_SOLVED can depend on the CI runner's CPU, through BLAS and
# MUMPS pivoting. The tests using this helper verify formulation equivalence,
# not solver robustness, so retry with alternative MUMPS pivot thresholds before
# failing. Every physical, membership and objective check still applies to the
# returned result. Starting values are unchanged between attempts.
const STRICT_PIVOT_LADDER = ((;), (mumps_pivtol=1e-3,), (mumps_pivtol=1e-2,), (mumps_pivtol=1e-6,))

function strict_solve(build, settings)
    result = nothing
    for extra in STRICT_PIVOT_LADDER
        result = solve_ivr_nlp_opf(build; solver_options=merge(settings, extra))
        result.solve.optimal && return result
    end
    result
end
