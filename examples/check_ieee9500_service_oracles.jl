# Independent isolated AC service cases using the IEEE 9500 source parameters.
# Both use a favorable 1.05 pu stiff source; this is not a full-feeder replay.
# Usage: julia --project=test examples/check_ieee9500_service_oracles.jl OUTPUT.json
using OpenDSSDirect, JSON3
D=OpenDSSDirect
out=Dict{String,Any}()
for (label,cmds) in [
 ("ct5",["New Circuit.ct phases=1 bus1=hv.2.0 basekv=7.2 pu=1.05 r1=0 x1=1e-7",
 "New XfmrCode.CT5 phases=1 windings=3 kvs=[7.2 .12 .12] kvas=[5 5 5] %imag=.5 %Rs=[.6 1.2 1.2] %noloadloss=.2 xhl=2.04 xht=2.04 xlt=1.36",
 "New Transformer.T226192762B XfmrCode=CT5 buses=[hv.2.0 lv.1.0 lv.0.2]",
 "New Line.service bus1=lv.1.2 bus2=load.1.2 linecode=4/0Triplex length=50 units=ft",
 "New Load.a phases=1 bus1=load.1.0 kv=.12 kw=3.84505480527878 pf=.97 model=1 vminpu=.88",
 "New Load.b phases=1 bus1=load.2.0 kv=.12 kw=1.91154945194721 pf=.97 model=1 vminpu=.88"]),
 ("triplex",["New Circuit.triplex phases=1 bus1=lv.1.0 basekv=.12 pu=1.05 r1=0 x1=1e-7",
 "New Vsource.leg2 phases=1 bus1=lv.2.0 basekv=.12 pu=1.05 angle=180 r1=0 x1=1e-7",
 "New Line.Tpx338899C0 bus1=lv.1.2 bus2=load.1.2 linecode=4/0Triplex length=50 units=ft",
 "New Load.a phases=1 bus1=load.1.0 kv=.12 kw=34.04621676206589 pf=.97 model=1 vminpu=.88",
 "New Load.b phases=1 bus1=load.2.0 kv=.12 kw=32.05378323793411 pf=.97 model=1 vminpu=.88"])]
 D.dss("clear");D.dss(first(cmds))
 D.dss("New Linecode.4/0Triplex nphases=2 units=kft rmatrix=[.40995115 .11809509 | .11809509 .40995115] xmatrix=[.16681819 .12759250 | .12759250 .16681819] cmatrix=[3 -2.4 | -2.4 3] normamps=156 emergamps=195")
 for cmd in cmds[2:end];D.dss(cmd);end
 D.dss("set controlmode=off maxiterations=200 tolerance=1e-10")
 D.dss("solve")
 rows=Dict{String,Any}()
 for name in D.Circuit.AllElementNames()
  startswith(lowercase(name),"line.") || startswith(lowercase(name),"transformer.") || continue
  D.Circuit.SetActiveElement(name)
  p=D.CktElement.Powers()
  rows[name]=Dict("current_A"=>abs.(D.CktElement.Currents()),"p_kW"=>real.(p),"q_kvar"=>imag.(p),"emergamps"=>D.CktElement.EmergAmps(),"nconds"=>D.CktElement.NumConductors())
 end
 out[label]=Dict("converged"=>D.Solution.Converged(),"elements"=>rows,"voltages_V"=>Dict(n=>abs(v) for (n,v) in zip(D.Circuit.AllNodeNames(),D.Circuit.AllBusVolts())))
end
open(io->JSON3.write(io,out),ARGS[1],"w")
println("service oracle convergence: ",Dict(k=>v["converged"] for (k,v) in out))
