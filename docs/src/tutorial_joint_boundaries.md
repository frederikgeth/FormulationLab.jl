# Tutorial: distinguish independent current and voltage restrictions

This self-contained example uses the manufactured two-wire π line. It compares
the joint-limit case with two controls that each relax one physical bound. The
same reduced formulation and power objective are used throughout. See the
[study](ivr_joint_boundaries.md) for the full panel and numerical qualifications.

```@example jointbounds
using FormulationLab, JuMP, Ipopt
include(joinpath(@__DIR__,"..","..","examples","benchmark_ivr_joint_boundaries.jl"))
study = IVRJointBoundaryStudy
function solve_case(treatment)
    net, manifest = study.scenario(conductors=2,direction=1,treatment=treatment)
    profile = only(p for p in study.profiles(net,manifest;
        nlp_scaling_method="gradient-based") if p.name=="reduced_reuse")
    build = build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
    start = study.L.M.E.S.U.G.H.S.L.start_point(net)
    for (variable,value) in ivr_nlp_point_report(build,start).variable_values
        set_start_value(variable,value)
    end
    result = solve_ivr_nlp_opf(build;
        solver_options=merge(study.P.STRICT,profile.solver_options))
    @assert result.solve.optimal && physical_residuals(net,result).passed
    point = ACPoint(voltage=result.voltage_candidate,currents=result.current_candidate)
    (;net,manifest,build,result,point)
end
cases = Dict(t=>solve_case(t) for t in (:joint,:wide_voltage,:loose_current))
[(treatment=t,objective=cases[t].result.objective)
    for t in (:joint,:wide_voltage,:loose_current)]
```

Inspect boundary proximity in the joint case, retaining signed slacks. Then
audit the relaxed solutions against the original joint network. A failed audit
alone is insufficient: verify which bound family caused the rejection.

```@example jointbounds
joint = cases[:joint]
currents = study.L.current_activity(joint.net,joint.point)
voltages = study.voltage_activity(joint.net,joint.point,joint.manifest)
@assert all(x.side==:to ? abs(x.slack_A)<=1e-5 : x.slack_A>1 for x in currents.records)
@assert all(abs(x.slack_V)<=1e-5 for x in voltages.records)
checks = []
for treatment in (:wide_voltage,:loose_current)
    control = cases[treatment]
    report = physical_residuals(joint.net,control.result)
    failed = [x.label for x in report.records
        if x.residual>getproperty(report.tolerances,x.unit)]
    @assert !report.passed && isempty(report.unassessed)
    @assert treatment==:wide_voltage ? failed==["bus/b1/vpn_min"] :
        !isempty(failed) && all(x in ("line/l1/from/i_max","line/l1/to/i_max") for x in failed)
    @assert !ivr_nlp_point_report(joint.build,control.point).passed
    @assert ivr_nlp_point_report(control.build,joint.point).passed
    @assert control.result.objective<joint.result.objective
    push!(checks,(;treatment,failed_bounds=failed))
end
checks
```

Both restrictions matter: relaxing either admits a better feasible point that
the original model rejects only for that family. The experiment does not prove
a global optimum. Three-wire cases also demonstrate why proximity and strictly
nonnegative activity must be reported separately at floating-point boundaries.
