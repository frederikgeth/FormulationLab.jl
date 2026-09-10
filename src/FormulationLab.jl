module FormulationLab
using JuMP
using LinearAlgebra
using SparseArrays
import JSON3
import PowerIO
import SHA

include("contracts.jl")
include("io/bmopf.jl")
include("io/kron_reduction.jl")
include("scaling.jl")

"""Default optimizer supplied by the optional Clarabel extension."""
default_optimizer() = default_optimizer(Val(:clarabel))
function default_optimizer(::Val)
    throw(ArgumentError("Load Clarabel (`using Clarabel`) or pass an optimizer explicitly."))
end

include("formulations/lindist3flow/types.jl")
include("formulations/lindist3flow/coefficients.jl")
include("formulations/lindist3flow/lowering.jl")
include("formulations/lindist3flow/controls.jl")
include("formulations/lindist3flow/applicability.jl")
include("formulations/lindist3flow/model.jl")

export L3FOptions, L3FFinding, L3FApplicabilityReport, L3FInapplicableError,
       L3FReferenceState, CrossVoltageCoefficients, AffineScalarCoefficients,
       ConnectionPowerMap, LineDropCoefficients,
       L3FBuild, L3FResult, is_l3f_applicable,
       cross_voltage_coefficients, evaluate_cross_voltage,
       winding_voltage_coefficients, evaluate_affine, connection_power_map,
       line_drop_coefficients, regulator_gain_matrix,
       check_l3f_applicability, build_l3f_opf, solve_l3f_opf,
       l3f_reference_from_powerflow,
       validate_l3f_solution, l3f_model_class

include("formulations/sdp.jl")
include("formulations/sdp_transformers.jl")
include("api.jl")
export AbstractFormulation, LinDist3Flow, IVRSDP, formulation_kind, build_opf, solve_opf
export SDPOptions, SDPBuild, SDPResult, SDPInapplicableError, build_sdp_opf, solve_sdp_opf
export BMOPFInput, read_bmopf, SolveStatus, solve_status, solve_diagnostics
export kron_reduce_bmopf, reduce_bmopf_neutrals, kron_reduce_neutrals
end
