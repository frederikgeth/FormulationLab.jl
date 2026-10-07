"""Small nonlinear calibration model; not an OPF or a timing benchmark.

`minimum=nothing` leaves Ipopt's minimum-refinement option unset. Other solver
settings and starts are identical across controls. Requires JuMP and Ipopt.
"""
function refinement_policy_model(minimum::Union{Nothing,Int}=nothing)
    minimum === nothing || 0 <= minimum <= 10 ||
        throw(ArgumentError("minimum must be between zero and ten"))
    m = Model(Ipopt.Optimizer)
    @variable(m, 0.1 <= x <= 4, start=1.2)
    @variable(m, y <= 5, start=1.8)
    @variable(m, z == 0.5)
    @constraint(m, balance, x + y + z == 3.5)
    @constraint(m, circle, x^2 + y^2 <= 8)
    @constraint(m, nonlinear, exp(0.1x) + y >= 1)
    @objective(m, Min, 1000*(x-1)^2 + 2000*(y-2)^2 + 7x*y + z^2)
    for (key, value) in ("print_level"=>10, "tol"=>1e-10,
                         "acceptable_iter"=>0, "bound_relax_factor"=>0.0,
                         "max_iter"=>100, "mumps_pivot_order"=>7,
                         "max_refinement_steps"=>10,
                         "nlp_scaling_method"=>"gradient-based")
        set_optimizer_attribute(m, key, value)
    end
    minimum === nothing || set_optimizer_attribute(m, "min_refinement_steps", minimum)
    return m
end
