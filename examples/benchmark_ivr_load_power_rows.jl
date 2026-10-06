"""Independent load row/column factorial on the objective-specific finalists.

Cost uses reduced_powers; tracking uses reduced_reuse. Cross 1 kVA and nominal
maximum load column units with off/definitions/laws/both row scaling. Active rows
always use nominal maximum channel apparent-power units with a 1 VA floor,
independently of columns. Physical data and all non-load numerical options stay
fixed. Existing full-model and other formulation runners remain available.
"""
module IVRLoadPowerRowStudy
using FormulationLab
include("benchmark_ivr_load_power_units.jl")
const U=IVRLoadPowerUnitStudy
const T=U.T
const P=U.P
function profiles(net,workload;kwargs...)
    workload in (:quadratic_cost,:exchange_tracking) || throw(ArgumentError("unsupported row-scaling workload"))
    finalist=workload==:quadratic_cost ? "reduced_powers" : "reduced_reuse"
    base=only(p for p in T.profiles(net,workload;load_power_lifting=true,kwargs...) if p.name==finalist)
    nominal=U.assignments(net,:nominal_max)
    [let columns=U.assignments(net,column),rows=mode==:off ? Dict{String,Float64}() : copy(nominal)
        merge(base,(;name=String(column)*"__"*String(mode),formulation_name=finalist,
            options=IVRNLPOptions(;(k=>(k==:load_power_bases ? copy(columns) :
                k==:load_power_row_bases ? copy(rows) : k==:load_power_row_scaling ? mode :
                deepcopy(getfield(base.options,k))) for k in fieldnames(IVRNLPOptions))...),
            factors=merge(base.factors,(;column_treatment=column,row_mode=mode,
                load_power_bases=copy(columns),load_power_row_bases=copy(rows)))))
    end for column in (:uniform_1k,:nominal_max) for mode in (:off,:definitions,:laws,:both)]
end
benchmark(path,output;checkpoint=:sweep,kwargs...)=T.M.F.benchmark_profiles(path,output,profiles,@__FILE__;checkpoint,kwargs...)
end
