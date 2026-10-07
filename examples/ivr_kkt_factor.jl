"""Fresh-factorization diagnostics for canonical symmetric KKT exports.

Uses the MUMPS library loaded by Ipopt, through a header-matched C bridge.
All metrics are diagnostic; no optimizer or eligible timing is performed.
"""
module IVRKKTOfflineFactor
using Ipopt, LinearAlgebra, Libdl, JSON3, SHA
const M = Ipopt.Ipopt_jll.MUMPS_seq_jll

function bridge(directory)
    mkpath(directory)
    source=joinpath(@__DIR__,"ivr_mumps_bridge.c")
    library=joinpath(directory,"ivr_mumps_bridge."*Libdl.dlext)
    include_dir=joinpath(M.artifact_dir,"include")
    run(`cc -std=c11 -O2 -Wall -Wextra -Werror -shared -fPIC -I$include_dir $source -o $library`)
    h=Libdl.dlopen(library)
    version=unsafe_string(ccall(Libdl.dlsym(h,:lab_mumps_version),Cstring,()))
    version=="5.9.1" || error("calibrated MUMPS 5.9.1 headers required")
    pkgversion(M)==v"500.900.100+0" || error("calibrated MUMPS 5.9.1 library required")
    BLAS.set_num_threads(1)
    ob=Libdl.dlopen(Ipopt.OpenBLAS32_jll.libopenblas_path)
    ccall(Libdl.dlsym(ob,:openblas_set_num_threads),Cvoid,(Cint,),1)
    (;library,handle=h,entry=Libdl.dlsym(Libdl.dlopen(M.libdmumps),:dmumps_c),
      factor=Libdl.dlsym(h,:lab_mumps_factor),solve=Libdl.dlsym(h,:lab_mumps_solve),
      free=Libdl.dlsym(h,:lab_mumps_free),version)
end

function input(data)
    n=Int(data["dimension"]);0<n<=typemax(Cint) || error("invalid dimension")
    i=Cint.(data["rows"]);j=Cint.(data["columns"]);a=Float64.(data["values"])
    b=Float64.(data["rhs"]);t=Float64.(data["coordinate_map"])
    length(i)==length(j)==length(a) && length(a)<=typemax(Cint) || error("invalid triplets")
    length(b)==length(t)==n || error("invalid vector dimensions")
    all(k->1<=j[k]<=i[k]<=n,eachindex(a)) || error("lower triangle required")
    length(Set(zip(i,j)))==length(a) || error("duplicate canonical entries")
    all(isfinite,a) && all(isfinite,b) && all(x->isfinite(x)&&x>0,t) || error("nonfinite input")
    (;n,i,j,a,b,t)
end

function action(n,i,j,a,x)
    y=zeros(eltype(x),n)
    for k in eachindex(a)
        y[i[k]]+=a[k]*x[j[k]]
        i[k]!=j[k] && (y[j[k]]+=a[k]*x[i[k]])
    end
    y
end

"""Use 256-bit accumulation on the actual Float64 matrix/RHS and direction."""
function metrics(n,i,j,a,q,b;reference=nothing)
    all(isfinite,q) || error("nonfinite solution")
    setprecision(BigFloat,256) do
        aa=BigFloat.(a);qq=BigFloat.(q);bb=BigFloat.(b)
        r=bb-action(n,i,j,aa,qq)
        den=abs.(bb)+action(n,i,j,abs.(aa),abs.(qq))
        eta=maximum((den[k]==0 ? (r[k]==0 ? BigFloat(0) : BigFloat(Inf)) : abs(r[k])/den[k]) for k in 1:n)
        isfinite(eta) || error("nonfinite backward error")
        gap=reference===nothing ? nothing : maximum(abs.(qq-BigFloat.(reference))./max.(1,abs.(qq),abs.(BigFloat.(reference))))
        (;residual=Float64.(r),residual_max=Float64(maximum(abs,r)),
          backward_error=Float64(eta),reference_gap=gap===nothing ? nothing : Float64(gap))
    end
end

function factor_solve(bridge,z,a,rhs_list;permutation=nothing,references=fill(nothing,length(rhs_list)))
    n=z.n;i=z.i;j=z.j;values=copy(a)
    all(isfinite,values) || error("nonfinite factor matrix")
    perm=permutation===nothing ? Cint[] : Cint.(permutation)
    isempty(perm) || sort(perm)==collect(1:n) || error("invalid permutation")
    info=zeros(Cint,80);out=zeros(Cint,n);result=Any[]
    GC.@preserve i j values perm begin
        ptr=ccall(bridge.factor,Ptr{Cvoid},(Ptr{Cvoid},Cint,Cint,Ptr{Cint},Ptr{Cint},Ptr{Cdouble},Ptr{Cint},Cint,Ptr{Cint},Ptr{Cint}),
            bridge.entry,n,length(values),i,j,values,isempty(perm) ? C_NULL : pointer(perm),!isempty(perm),info,out)
        try
            ptr==C_NULL && error("MUMPS allocation failed")
            info[1]<0 && return (;passed=false,info=Int.(info),permutation=Int.(out),rhs=result)
            sort(out)==collect(1:n) || error("invalid output permutation")
            # MUMPS may reorganize a supplied order for locality (guide 5.6.2).
            # The paired experiment checks equality of the two effective orders.
            for (b,reference) in zip(rhs_list,references)
                length(b)==n && all(isfinite,b) || error("invalid RHS")
                q=copy(b)
                status=ccall(bridge.solve,Cint,(Ptr{Cvoid},Ptr{Cdouble}),ptr,q)
                status>=0 || error("MUMPS solve failed: $status")
                stages=Any[]
                for stage in 0:2
                    report=metrics(n,i,j,a,q,b;reference)
                    push!(stages,(;stage,report.residual_max,report.backward_error,report.reference_gap))
                    if stage<2
                        correction=report.residual
                        status=ccall(bridge.solve,Cint,(Ptr{Cvoid},Ptr{Cdouble}),ptr,correction)
                        status>=0 || error("MUMPS refinement solve failed: $status")
                        q+=correction
                    end
                end
                push!(result,(;stages,solution=q))
            end
            (;passed=true,info=Int.(info),permutation=Int.(out),
              given_order_reorganized=!isempty(perm) && out!=perm,rhs=result)
        finally
            ccall(bridge.free,Cvoid,(Ptr{Cvoid},),ptr)
        end
    end
end

function experiment(bridge,data)
    z=input(data);n=z.n
    native=get(data,"native_solution",nothing)
    qstar=sin.(Float64.(1:n))
    manufactured=setprecision(BigFloat,256) do
        Float64.(action(n,z.i,z.j,BigFloat.(z.a),BigFloat.(qstar)))
    end
    target=z.a .* z.t[z.i] .* z.t[z.j]
    original=factor_solve(bridge,z,z.a,[z.b,manufactured];references=[native,qstar])
    original.passed || return (;passed=false,original)
    transformed=factor_solve(bridge,z,target,[z.b.*z.t,manufactured.*z.t];references=[native===nothing ? nothing : native./z.t,qstar./z.t])
    fixed_original=factor_solve(bridge,z,z.a,[z.b,manufactured];permutation=original.permutation,references=[native,qstar])
    fixed_transformed=factor_solve(bridge,z,target,[z.b.*z.t,manufactured.*z.t];permutation=original.permutation,references=[native===nothing ? nothing : native./z.t,qstar./z.t])
    if fixed_original.passed && fixed_transformed.passed
        fixed_original.permutation==fixed_transformed.permutation || error("paired effective orders differ")
        fixed_original.info[33]==fixed_transformed.info[33]==0 || error("controlled scaling not disabled")
    end
    pairs=Any[]
    for (name,left,right) in [("automatic",original,transformed),("fixed_unscaled",fixed_original,fixed_transformed)]
        differences=Any[]
        if left.passed && right.passed
            for r in 1:2
                a=left.rhs[r].solution;b=right.rhs[r].solution.*z.t
                push!(differences,(;rhs=r,mapped_direction_gap=maximum(abs.(a.-b)./max.(1.,abs.(a),abs.(b))),
                    original=metrics(n,z.i,z.j,z.a,a,r==1 ? z.b : manufactured;reference=r==1 ? native : qstar),
                    mapped=metrics(n,z.i,z.j,z.a,b,r==1 ? z.b : manufactured;reference=r==1 ? native : qstar)))
            end
        end
        push!(pairs,(;name,original=left,transformed=right,differences))
    end
    passed=all(p.original.passed && p.transformed.passed for p in pairs)
    quality=passed && all(last(r.stages).backward_error<=1e-10 for p in pairs for f in (p.original,p.transformed) for r in f.rhs)
    (;passed,quality_passed=quality,timing_eligible=false,pairs)
end
end
