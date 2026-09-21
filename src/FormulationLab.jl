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

# Defer SDP solver selection until the actual cone layout is known. An explicit
# optimizer factory remains entirely owned by the caller.
struct _SDPDefaultOptimizer end
default_sdp_optimizer() = _SDPDefaultOptimizer()
default_sdp_optimizer(decomposition::Symbol) = default_sdp_optimizer(Val(:clarabel),Val(decomposition))
function default_sdp_optimizer(::Val,::Val)
    throw(ArgumentError("Load Clarabel (`using Clarabel`) or pass an optimizer explicitly."))
end

include("formulations/lindist3flow/types.jl")
include("formulations/lindist3flow/coefficients.jl")
include("formulations/lindist3flow/lowering.jl")
include("formulations/lindist3flow/controls.jl")
include("formulations/lindist3flow/input_mesh.jl")
include("formulations/lindist3flow/applicability.jl")
include("formulations/lindist3flow/model.jl")
include("formulations/lindist3flow/operating_modes.jl")

export L3FOptions, L3FFinding, L3FApplicabilityReport, L3FInapplicableError,
       L3FReferenceState, CrossVoltageCoefficients, AffineScalarCoefficients,
       ConnectionPowerMap, LineDropCoefficients,
       L3FBuild, L3FResult, is_l3f_applicable,
       cross_voltage_coefficients, evaluate_cross_voltage,
       winding_voltage_coefficients, evaluate_affine, connection_power_map,
       line_drop_coefficients, regulator_gain_matrix,
       check_l3f_applicability, build_l3f_opf, solve_l3f_opf,
       l3f_reference_from_powerflow,
       validate_l3f_solution, l3f_model_class, l3f_limit_report

include("cuts/lnc.jl")
include("formulations/sdp.jl")
include("formulations/sdp_transformers.jl")
include("formulations/sdp_static.jl")
include("formulations/sdp_numerics.jl")
include("formulations/physical_bounds.jl")
include("formulations/sdp_sparse.jl")
include("formulations/sdp_nwinding.jl")
include("formulations/branch_flow_sdp.jl")
include("cuts/lnc_lines.jl")
include("formulations/soc.jl")
include("cuts/soc_fixed.jl")
include("api.jl")
include("validation/containment.jl")
include("validation/physical.jl")
include("io/bmopf_simplify.jl")
include("io/network_reduction.jl")
include("io/reconstruction.jl")
export ReductionOptions, ReductionPlan, PreparedNetwork, prepare_network, reduction_report
export ReconstructedSolution, reconstruct_solution, reconstruction_plan, restore_prepared_network
export ACPoint, containment_report, physical_residuals, complete_ac_point
export PhysicalBoundReport, bound_report
export IVRSOC, SOCOptions, SOCBuild, SOCResult, build_soc_opf, solve_soc_opf
export BranchFlowSDPOptions, BranchFlowSDPBuild, BranchFlowSDPResult,
       BranchFlowSDPInapplicableError, BranchFlowSDPApplicabilityReport,
       check_branch_flow_sdp_applicability, is_branch_flow_sdp_applicable,
       build_branch_flow_sdp, solve_branch_flow_sdp
export LNCBounds, VoltagePhasor, VoltageLNC, LNCDiagnostic, add_lnc!, add_voltage_lnc!, phasor_products
export AbstractFormulation, LinDist3Flow, IVRSDP, BranchFlowSDP,
       formulation_kind, build_opf, solve_opf
export SDPOptions, SDPBuild, SDPResult, SDPInapplicableError, build_sdp_opf, solve_sdp_opf
export BMOPFInput, read_bmopf, SolveStatus, solve_status, solve_diagnostics
export kron_reduce_bmopf, reduce_bmopf_neutrals, kron_reduce_neutrals
end
