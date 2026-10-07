# Balanced SI witness with an IBR connected directly to a prescribed source.
# Internal voltages include filter impedance; no compiler expressions construct it.
function _ibr_voltage_witness(m;filtered=true)
    net,_,_,_=_ibr_state(m)
    delete!(net,"line");delete!(net,"load");delete!(net["bus"],"b1")
    d=net["ibr"]["g"];d["bus"]="b0";tm=d["terminal_map"];n=m==2 ? 1 : 3
    v=m==2 ? ComplexF64[230,0] : [230cis.([0.,-2pi/3,2pi/3]);m==4 ? [0im] : ComplexF64[]]
    D=m==2 ? [1. -1.] : m==3 ? [1. -1. 0.;0. 1. -1.;-1. 0. 1.] : [Matrix{Float64}(I,3,3) -ones(3)]
    u=D*v;ci=.01u;it=transpose(D)*ci
    shunt=filtered ? .001 : 0.;z=filtered ? .2+.08im : 0im
    jf=ci+im*shunt.*u;e=u+z.*jf;port=m==3 ? it : ci
    s=(m==3 ? v : u).*conj.(port)
    d["p_min"]=real.(s);d["p_max"]=real.(s)
    d["q_min"]=fill(-5000.,n);d["q_max"]=fill(5000.,n)
    d["r_filter"]=fill(real(z),n);d["x_filter"]=fill(imag(z),n);d["b_filter_shunt"]=shunt
    d["grid_forming"]=true;d["v_ref_internal"]=abs(e[1]);d["cost"]=zeros(n)
    source=-it;m==3 || (source[end]=0im)
    point=ACPoint(voltage=Dict(("b0",t)=>x for (t,x) in zip(tm,v)),
        currents=Dict((:voltage_source,"source")=>source,(:ibr,"g")=>port,(:ibr_internal,"g")=>jf))
    net,point,e
end
