module IVRHybridTests
using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/benchmark_ivr_hybrid.jl")
const H=IVRHybridStudy
point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
# mumps_pivtol=1e-3 avoids platform-dependent pivot retries that ended these
# strict solves at ALMOST_LOCALLY_SOLVED on x86-64 Linux (see ivr_findings.md).
solve(b)=solve_ivr_nlp_opf(b;solver_options=merge(H.P.STRICT,(mumps_pivtol=1e-3,)))
# Independent graph traversal, without consulting the compiler's component map.
function groups(net,selected)
    todo=Set(selected);result=Vector{String}[]
    while !isempty(todo)
        stack=[first(sort!(collect(todo)))];members=String[]
        while !isempty(stack)
            b=pop!(stack);b in todo || continue
            delete!(todo,b);push!(members,b)
            for d in values(net["line"])
                d["bus_from"]==b && d["bus_to"] in todo && push!(stack,d["bus_to"])
                d["bus_to"]==b && d["bus_from"] in todo && push!(stack,d["bus_from"])
            end
        end
        push!(result,sort!(members))
    end
    sort!(result;by=first)
end

@testset "Hybrid component cap and exact linear certificate" begin
    for m in (2,3,4),charged in (false,true),alternate in (false,true)
        net=H.case(conductors=m,segments=8;charged,alternate);original=deepcopy(net)
        full=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        rf=solve(full);@test rf.solve.optimal && physical_residuals(net,rf).passed
        for specialization in (:off,:conductor_regions),cap in (1,2,4,100)
            opts=(;objective=:source_import,specialization,linear_elimination=:passive_hybrid,passive_component_limit=cap,
                lifting=:bounded_observations,observation_sharing=:exact)
            b=build_opf(net,IVRNLP(;opts...);optimizer=Ipopt.Optimizer)
            rep=b.numerical_diagnostics[:linear_elimination_report];gs=groups(net,rep.series_buses)
            @test rep.eliminated_components==gs
            @test rep.max_component_buses==maximum(length,gs;init=0)<=cap
            @test Set(keys(rep.component_limit_rejections))==Set(k for (k,v) in rep.retained_series_buses if v=="eliminated_component_limit")
            @test all(>(cap),values(rep.component_limit_rejections))
            @test Set(vcat(gs...))==Set(rep.series_buses)
            @test length(unique(values(rep.selected_series_lines)))==length(rep.series_buses)
            y=ComplexF64[sin(k)+im*cos(2k) for k in eachindex(b.coordinates.projection)]
            ev(row,x)=FormulationLab._linivr_eval(row,x)
            z=[ev(row,y) for row in b.coordinates.reconstruction]
            @test [ev(row,z) for row in b.coordinates.projection]≈y atol=1e-10
            for bus in rep.series_buses,t in net["bus"][bus]["terminal_names"]
                @test abs(ev(b.electrical.kcl[(bus,t)],z))<1e-10
            end
            for line in b.electrical.lnc_lines
                line.id in values(rep.selected_series_lines) || continue
                @test all(k->abs(ev(b.electrical.equations[k],z))<1e-10,line.equation_indices)
            end
            supplied=ivr_nlp_point_report(b,point(rf))
            @test supplied.passed && length(supplied.variable_values)==num_variables(b.model)
            r=solve(b);@test r.solve.optimal && physical_residuals(net,r).passed
            @test ivr_nlp_point_report(full,point(r)).passed && ivr_nlp_point_report(b,point(r)).passed
            @test r.objective≈rf.objective atol=1e-4 rtol=1e-8
            out=result_dict(b,r);io=IOBuffer();write_result(out,io);seekstart(io);@test isequal(read_result(io),out)
            @test Set(keys(r.voltage_candidate))==Set(keys(rf.voltage_candidate)) && Set(keys(r.powers))==Set(keys(rf.powers))
            if cap==100
                unlimited=build_opf(net,IVRNLP(; (k=>v for (k,v) in pairs(opts) if k!=:linear_elimination)...,linear_elimination=:passive_blocks))
                @test b.coordinates.projection==unlimited.coordinates.projection && b.coordinates.reconstruction==unlimited.coordinates.reconstruction
            end
        end
        @test net==original
    end
end

@testset "Every eliminated interior voltage family and both line endpoints survive" begin
    for m in (2,3,4),charged in (false,true),cap in (1,2)
        net=H.case(conductors=m,segments=4;charged)
        opts=(;linear_elimination=:passive_hybrid,passive_component_limit=cap,
            specialization=:conductor_regions,lifting=:bounded_observations,observation_sharing=:exact)
        base=build_opf(net,IVRNLP(;opts...);optimizer=Ipopt.Optimizer);r=solve(base);p=point(r)
        @test r.solve.optimal && physical_residuals(net,r).passed
        for bus in base.numerical_diagnostics[:linear_elimination_report].series_buses
            phases=m==2 ? ["a"] : ["a","b","c"];v=[p.voltage[(bus,t)] for t in phases]
            vn=m==3 ? 0im : p.voltage[(bus,"n")];u=v.-vn;a=cis(2pi/3)
            bounds=Dict("v_min"=>abs.(v),"v_max"=>abs.(v))
            m!=3 && merge!(bounds,Dict("vpn_min"=>abs.(u),"vpn_max"=>abs.(u),"vn_max"=>[abs(vn)]))
            if m>=3
                merge!(bounds,Dict("vpp_min"=>abs.([v[1]-v[2],v[2]-v[3],v[3]-v[1]]),
                    "vpp_max"=>abs.([v[1]-v[2],v[2]-v[3],v[3]-v[1]]),
                    "vpos_min"=>[abs(sum([1,a,a^2].*u)/3)],"vpos_max"=>[abs(sum([1,a,a^2].*u)/3)],
                    "vneg_max"=>[abs(sum([1,a^2,a].*u)/3)],"vzero_max"=>[abs(sum(u)/3)]))
            end
            for (field,x) in bounds,k in eachindex(x)
                x[k]>1e-5 || continue
                tight=deepcopy(net);lower=endswith(field,"min")
                tight["bus"][bus][field]=lower ? .5x : 2x
                tight["bus"][bus][field][k]=lower ? 1.5x[k] : .5x[k]
                b=build_opf(tight,IVRNLP(;opts...));q=ivr_nlp_point_report(b,p)
                @test !q.passed && q.max_reconstruction_residual_pu<1e-7
                audit=physical_residuals(tight,p;delta_dispatch=:coil)
                @test any(x->x.label=="bus/$bus/$field" && x.residual>getproperty(audit.tolerances,x.unit),audit.records)
            end
        end
        for id in keys(net["line"]),side in (:line_from,:line_to),field in ("i_max","s_max")
            x=abs.(field=="i_max" ? p.currents[(side,id)] : r.powers[(side,id)][1:(m==2 ? 1 : 3)])
            for k in eachindex(x)
                x[k]>1e-5 || continue
                tight=deepcopy(net);tight["line"][id][field]=fill(1e9,length(x));tight["line"][id][field][k]=.5x[k]
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(;opts...)),p).passed
                audit=physical_residuals(tight,p;delta_dispatch=:coil)
                label="line/$id/$(side==:line_from ? "from" : "to")/$field"
                @test any(x->x.label==label && x.residual>getproperty(audit.tolerances,x.unit),audit.records)
            end
        end
    end
end

@testset "Hybrid boundaries, deterministic selection and transactional refusal" begin
    for shape in (:chain,:mesh,:junction),cap in (1,2,4)
        net=H.case(segments=12,charged=true)
        if shape!=:chain
            net["line"]["extra"]=merge(deepcopy(net["line"]["l1"]),Dict("bus_from"=>shape==:mesh ? "b12" : "b6","bus_to"=>"b0"))
        end
        opts=(;linear_elimination=:passive_hybrid,passive_component_limit=cap)
        b=build_opf(net,IVRNLP(;opts...));rep=b.numerical_diagnostics[:linear_elimination_report]
        @test rep.eliminated_components==groups(net,rep.series_buses)
        @test maximum(length,rep.eliminated_components;init=0)<=cap
        @test "b0" ∉ rep.series_buses && "b12" ∉ rep.series_buses
        shape==:junction && @test "b6" ∉ rep.series_buses
        permuted=deepcopy(net)
        for family in ("bus","line","load")
            permuted[family]=Dict(k=>permuted[family][k] for k in reverse(sort!(collect(keys(permuted[family])))))
        end
        other=build_opf(permuted,IVRNLP(;opts...));r2=other.numerical_diagnostics[:linear_elimination_report]
        @test rep.series_buses==r2.series_buses && rep.selected_series_lines==r2.selected_series_lines
        full=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=solve(full)
        @test r.solve.optimal && ivr_nlp_point_report(b,point(r)).passed && ivr_nlp_point_report(other,point(r)).passed
    end
    # A rejected dense block must not reserve component membership for later buses.
    net=H.case(segments=4,charged=true);code=net["linecode"]["wire"]
    for key in collect(keys(code));key=="i_max" || delete!(code,key);end
    for j in 1:2
        code["R_series_$(j)_$(j)"]=0.;code["X_series_$(j)_$(j)"]=1.
        code["B_from_$(j)_$(j)"]=.5;code["B_to_$(j)_$(j)"]=.5
    end
    for l in values(net["line"]);l["length"]=1.;end
    b=build_opf(net,IVRNLP(linear_elimination=:passive_hybrid,passive_component_limit=1))
    rep=b.numerical_diagnostics[:linear_elimination_report]
    @test isempty(rep.series_buses) && isempty(rep.eliminated_components) && isempty(rep.component_limit_rejections)
    @test all(==("ill_conditioned_local_block"),values(rep.retained_series_buses))
    full=build_opf(net,IVRNLP());@test b.coordinates.reconstruction==full.coordinates.reconstruction
    # Operating-support rejection also rolls back all component bookkeeping.
    net=H.case(segments=4,charged=true)
    b=build_opf(net,IVRNLP(linear_elimination=:passive_hybrid,passive_component_limit=1,series_selection=:bound_support))
    rep=b.numerical_diagnostics[:linear_elimination_report]
    @test !isempty(rep.bound_support_rejections)
    @test rep.eliminated_components==groups(net,rep.series_buses) && rep.max_component_buses<=1
    @test isempty(intersect(Set(keys(rep.bound_support_rejections)),Set(rep.series_buses)))
    for key in ("vpn_min","vpn_max","vn_max"),d in values(net["bus"]);delete!(d,key);end
    for d in values(net["line"]);delete!(d,"s_max");end
    delete!(net["linecode"]["wire"],"i_max")
    b=build_opf(net,IVRNLP(linear_elimination=:passive_hybrid,passive_component_limit=1,series_selection=:bound_support))
    @test !isempty(b.numerical_diagnostics[:linear_elimination_report].series_buses)
    for cap in (0,-1)
        @test_throws ArgumentError build_opf(net,IVRNLP(linear_elimination=:passive_hybrid,passive_component_limit=cap))
    end
    @test build_opf(net,IVRNLP(linear_elimination=:passive_blocks,passive_component_limit=1)).coordinates.reconstruction==
        build_opf(net,IVRNLP(linear_elimination=:passive_blocks)).coordinates.reconstruction
end

@testset "Hybrid power workloads, updates and benchmark controls" begin
    net=H.case(conductors=3,segments=4,charged=true)
    for workload in (:quadratic_cost,:exchange_tracking)
        ps=H.profiles(net,workload;exchange_target_W=1500.)
        @test length(ps)==7 && allunique(p.name for p in ps)
        @test all(p.options.lifting==:powers && p.options.lifted_power_base==1e3 && p.options.s_base==1e4 for p in ps)
        anchor=nothing;reference=build_opf(net,IVRNLP(objective=:power,power_terms=first(ps).options.power_terms))
        for p in ps
            row,x=H.P.trial(net,p,reference,anchor;initial_point=H.E.S.U.G.H.S.L.start_point(net))
            @test row["accepted"]
            anchor===nothing && (anchor=x)
        end
    end
    b=build_opf(net,IVRNLP(objective=:source_import,linear_elimination=:passive_hybrid,passive_component_limit=2,
        lifted_power_base=1e3,lifting=:powers,power_sharing=:generators);optimizer=Ipopt.Optimizer)
    vars=all_variables(b.model)
    update_ivr_loads!(b,Dict("d4"=>(p=[1500.,500.,100.],q=[200.,100.,20.])))
    update_ivr_generators!(b,Dict("der"=>(p_min=[100.,100.,100.],p_max=[100.,100.,100.],q_min=zeros(3),q_max=zeros(3))))
    r=solve(b)
    @test r.solve.optimal && physical_residuals(b.network,r).passed
    @test all_variables(b.model)==vars && ivr_nlp_point_report(build_opf(b.network,IVRNLP()),point(r)).passed
    mktempdir() do dir
        path=joinpath(dir,"input.json");open(io->JSON3.write(io,net),path,"w")
        @test_throws ArgumentError H.benchmark(path,path)
        r=H.benchmark(path,joinpath(dir,"report.json"))
        @test r["position_balanced"] && r["network_unchanged"] && r["source_unchanged"]
        @test r["ranking"]["objective_comparable"] && length(r["ranking"]["eligible"])==7
    end
end

@testset "Hybrid apparent-power witnesses isolate both endpoint expressions" begin
    for m in (2,3),cap in (1,2)
        endpoints=Set{String}()
        for direction in (-1,1)
            net=H.case(conductors=m,segments=4)
            delete!(net,"generator")
            for d in values(net["load"]);d["p_nom"] .*= direction;d["q_nom"] .*= direction;end
            b=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=solve(b);p=point(r)
            @test r.solve.optimal && physical_residuals(net,r).passed
            for id in keys(net["line"])
                f=abs(r.powers[(:line_from,id)][1]);t=abs(r.powers[(:line_to,id)][1])
                @test abs(f-t)>1e-4
                endpoint=f>t ? "from" : "to";push!(endpoints,endpoint)
                tight=deepcopy(net);tight["line"][id]["s_max"][1]=(f+t)/2
                reduced=build_opf(tight,IVRNLP(linear_elimination=:passive_hybrid,passive_component_limit=cap,
                    specialization=:conductor_regions,lifting=:powers))
                q=ivr_nlp_point_report(reduced,p)
                @test !q.passed && q.max_reconstruction_residual_pu<1e-7
                audit=physical_residuals(tight,p;delta_dispatch=:coil)
                @test [x.label for x in audit.records if x.residual>getproperty(audit.tolerances,x.unit)]==["line/$id/$endpoint/s_max"]
            end
        end
        @test endpoints==Set(["from","to"])
    end
end
end
