# Optional live reference: scalar winding-total caps, in per-unit solve mode.
using Test,FormulationLab,JuMP,Ipopt,JSON3,SHA
import BMOPFTools
include("../ivr_nwinding_limit_fixtures.jl")
const SETTINGS=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.)
rows=Any[]
@testset "Live BMOPFTools scalar multiwinding bound and SI export parity" begin
    for phases in (1,3),reverse in (false,true),sb in (1e3,1e5),bounded in (false,true)
        net,demand=_nwinding_limit_case(;phases,reverse,rating=bounded ? 100phases : nothing)
        original=deepcopy(net)
        ref=BMOPFTools.solve_opf(net;optimizer=Ipopt.Optimizer,per_unit=true,s_base=sb,
            solver_options=Tuple(string(k)=>v for (k,v) in pairs(SETTINGS)))
        @test ref["feasible"]
        for lifting in (:off,:powers,:bounded_observations)
            b=build_opf(net,IVRNLP(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools,
                lifting,lifted_power_base=500.,observation_sharing=:signed,
                specialization=:conductor_regions,linear_elimination=:passive_blocks,
                device_elimination=:transformer_currents,transformer_scaling=:nominal,row_scaling=:composed);optimizer=Ipopt.Optimizer)
            r=solve_ivr_nlp_opf(b;solver_options=SETTINGS)
            @test r.solve.optimal && physical_residuals(net,r).passed
            expected=bounded ? sum(max.(0.,demand.-100.)) : 0.
            # Native linear generator prices multiply kW, not W.
            @test r.objective≈expected/1000 atol=1e-8
            @test sum(abs,real.(r.powers[(:generator,"g")]))≈expected atol=1e-5
            @test r.objective≈ref["objective"] atol=1e-5
            d=result_dict(b,r)
            for winding in ("w1","w2","w3"),channel in keys(d["transformer"]["tx"][winding])
                ours=d["transformer"]["tx"][winding][channel];theirs=ref["transformer"]["tx"][winding][channel]
                @test Set(keys(ours))==Set(keys(theirs))
                for k in keys(ours)
                    # Current phase is undefined at zero magnitude.
                    k=="ca" && max(ours["cm"],theirs["cm"])<1e-6 && continue
                    @test isapprox(ours[k],theirs[k];atol=2e-5,rtol=1e-6)
                end
            end
            io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(BMOPFTools.read_result(io),d)
            @test net==original
            push!(rows,(;phases,reverse,s_base=sb,bounded,lifting,objective=r.objective,reference_objective=ref["objective"],passed=true))
        end
    end
end
if !isempty(ARGS)
    root=dirname(dirname(pathof(BMOPFTools)))
    files=("src/io/nwinding.jl","ext/BMOPFOpfExt/nwinding.jl","ext/BMOPFOpfExt/per_unit.jl")
    report=(;reference_path=root,reference_revision=readchomp(`git -C $root rev-parse HEAD`),
        reference_dirty=!isempty(readchomp(`git -C $root status --porcelain`)),
        reference_source_sha256=Dict(p=>bytes2hex(sha256(read(joinpath(root,p)))) for p in files),
        cases=rows,note="Per-unit single/three-phase unbalanced, forward/reverse, absent/active scalar winding-total caps; lossless all-wye unequal-turn three-winding circuit. Vectors and excitation-location parity are outside the live claim.")
    open(io->JSON3.write(io,report),ARGS[1],"w")
end
