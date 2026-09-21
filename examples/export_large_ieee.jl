# Export with the selected POWERIO_CAPI library; source DSS files are untouched.
using FormulationLab, PowerIO, JSON3
p=read_bmopf(PowerIO.parse(ARGS[1];format="dss"))
open(io->JSON3.write(io,p.network),ARGS[2],"w")
println(Dict(k=>length(v) for (k,v) in p.network["transformer"]))

open(io->JSON3.write(io,Dict("source"=>abspath(ARGS[1]),"powerio_julia_version"=>string(pkgversion(PowerIO)),
    "capi"=>get(ENV,"POWERIO_CAPI","installed artifact"),
    "diagnostics"=>[Dict("code"=>d.code,"message"=>d.message,"severity"=>string(d.severity)) for d in p.diagnostics])),ARGS[2]*".provenance.json","w")
