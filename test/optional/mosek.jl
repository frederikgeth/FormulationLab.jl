# Setup: julia --project=test/optional -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
# Requires the ordinary test environment to be instantiated, and a local Mosek license.
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using MosekTools
const SDP_TEST_OPTIMIZER = MosekTools.Optimizer
const SDP_TEST_SOLVER_OPTIONS = (MSK_IPAR_LOG=0, MSK_DPAR_INTPNT_CO_TOL_REL_GAP=1e-9)
include("../sdp_tests.jl")
