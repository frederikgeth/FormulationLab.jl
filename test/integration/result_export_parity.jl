# Optional live compatibility test. BMOPFTools is not a runtime dependency.
using Test, FormulationLab, JuMP, Ipopt, JSON3
import BMOPFTools
include("../../examples/ivr_compiler_cases.jl")
function leaf_compare(a,b;path=String[])
    if a isa AbstractDict && b isa AbstractDict
        @test Set(keys(a))==Set(keys(b))
        for k in intersect(Set(keys(a)),Set(keys(b)))
            leaf_compare(a[k],b[k];path=[path;string(k)])
        end
    elseif a isa Number && b isa Number
        @test isapprox(a,b;atol=2e-5,rtol=1e-6) || isnan(a)&&isnan(b)
    end
end
@testset "Live BMOPFTools export compatibility" begin
    for m in (2,3,4)
        net=ivr_compiler_case(conductors=m,segments=3)
        delete!(net["load"],"d1");delete!(net["load"],"d2")
        # Shared scalar spelling: this BMOPFTools revision rejects [vn_max].
        for d in values(net["bus"]);haskey(d,"vn_max") && (d["vn_max"]=only(d["vn_max"]));end
        ref=BMOPFTools.solve_opf(net;optimizer=Ipopt.Optimizer,per_unit=true,s_base=1e4,
            solver_options=("print_level"=>0,"tol"=>1e-10,"constr_viol_tol"=>1e-10))
        @test ref["feasible"]
        r=FormulationLab.solve_opf(net,IVRNLP(specialization=:conductor_regions,linear_elimination=:passive_chains);
            optimizer=Ipopt.Optimizer,solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10))
        @test r.solve.optimal
        d=result_dict(net,r)
        for family in ("bus","line","load","voltage_source","losses")
            @test Set(keys(d[family]))==Set(keys(ref[family]))
            leaf_compare(d[family],ref[family];path=[family])
        end
        io=IOBuffer();FormulationLab.write_result(d,io);seekstart(io)
        @test isequal(BMOPFTools.read_result(io),d)
        io=IOBuffer();BMOPFTools.write_result(d,io);seekstart(io)
        @test isequal(FormulationLab.read_result(io),d)
    end
end
