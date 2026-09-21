module FormulationLabClarabelExt
using FormulationLab, Clarabel, JuMP

# Dense reference models do not need chordal decomposition. This also avoids
# Clarabel 0.11.1's PSD completion path, which indexes OrderedSet and fails
# with OrderedCollections 2. Explicit optimizer factories remain user-owned.
FormulationLab.default_optimizer(::Val{:clarabel}) = JuMP.optimizer_with_attributes(
    Clarabel.Optimizer, "chordal_decomposition_enable" => false)
FormulationLab.default_sdp_optimizer(::Val{:clarabel},::Val{:dense}) = FormulationLab.default_optimizer()
FormulationLab.default_sdp_optimizer(::Val{:clarabel},::Val{:branch_flow}) =
    JuMP.optimizer_with_attributes(
        Clarabel.Optimizer, "chordal_decomposition_enable"=>false,
        "static_regularization_constant"=>1e-7,
        "iterative_refinement_max_iter"=>30)
FormulationLab.default_sdp_optimizer(::Val{:clarabel},::Val{:chordal}) = JuMP.optimizer_with_attributes(
    Clarabel.Optimizer, "chordal_decomposition_enable"=>false,
    "static_regularization_constant"=>1e-5, "iterative_refinement_max_iter"=>30)
FormulationLab.default_optimizer(::Val{:clarabel_soc}) = JuMP.optimizer_with_attributes(
    Clarabel.Optimizer, "chordal_decomposition_enable"=>false,
    "static_regularization_constant"=>1e-7, "iterative_refinement_max_iter"=>30,
    "tol_gap_abs"=>1e-7)
end
