module FormulationLabClarabelExt
using FormulationLab, Clarabel, JuMP

# Dense reference models do not need chordal decomposition. This also avoids
# Clarabel 0.11.1's PSD completion path, which indexes OrderedSet and fails
# with OrderedCollections 2. Explicit optimizer factories remain user-owned.
FormulationLab.default_optimizer(::Val{:clarabel}) = JuMP.optimizer_with_attributes(
    Clarabel.Optimizer, "chordal_decomposition_enable" => false)
end
