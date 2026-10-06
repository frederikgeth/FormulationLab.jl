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
function profiles(net,workload;column_treatments=(:uniform_1k,:nominal_max),
                  row_modes=(:off,:definitions,:laws,:both),kwargs...)
    workload in (:quadratic_cost,:exchange_tracking) || throw(ArgumentError("unsupported row-scaling workload"))
    !isempty(column_treatments) && allunique(column_treatments) &&
        all(x->x in (:uniform_1k,:uniform_10k,:voltage_class,:nominal_max),column_treatments) ||
        throw(ArgumentError("column treatments must be nonempty, unique, supported load-unit treatments"))
    !isempty(row_modes) && allunique(row_modes) &&
        all(x->x in (:off,:definitions,:laws,:both),row_modes) ||
        throw(ArgumentError("row modes must be nonempty, unique, supported row scopes"))
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
    end for column in column_treatments for mode in row_modes]
end
function benchmark(path,output;checkpoint=:sweep,column_treatments=(:uniform_1k,:nominal_max),
                   row_modes=(:off,:definitions,:laws,:both),kwargs...)
    builder=(net,workload;kw...)->profiles(net,workload;column_treatments,row_modes,kw...)
    T.M.F.benchmark_profiles(path,output,builder,@__FILE__;checkpoint,kwargs...)
end
end
