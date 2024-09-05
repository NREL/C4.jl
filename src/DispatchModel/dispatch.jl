# TODO: Differentiate reliability vs economic dispatch in variable names

"""
GeneratorDispatch contains optimization problem components for
dispatching a GeneratorTechnology. GeneratorDispatch constructors should take
the following arguments:
```
GeneratorDispatch(::JuMP.Model, ::Region, ::GeneratorTechnology, ::TimePeriod)
```
"""
struct GeneratorDispatch{G<:GeneratorTechnology}

    dispatch::Vector{JuMP.VariableRef}
    dispatch_max::Vector{JuMP_LessThanConstraintRef}

    gen::G

end

cost(dispatch::GeneratorDispatch) =
    sum(dispatch.dispatch) * cost_generation(dispatch.gen)

# TODO: Abstract these and eliminate ExpansionProblem/dispatch.jl

function GeneratorDispatch(
    m::JuMP.Model, region::RegionParams,
    gen::G, period::TimePeriod
) where G <: GeneratorParams

    T = length(period)
    ts = period.timesteps

    dispatch = @variable(m, [1:T], lower_bound = 0)
    fullname = join([region.name, gen.name, period.name], ",")
    varnames!(dispatch, "gen_dispatch[$(fullname)]", 1:T)

    dispatch_max = @constraint(m, [t in 1:T],
        dispatch[t] <= availablecapacity(gen, ts[t]))

    return DispatchModel.GeneratorDispatch{G}(
        dispatch, dispatch_max, gen)

end

struct StorageSiteDispatch{S<:StorageSite}

    dispatch::Vector{JuMP.VariableRef}

    dispatch_min::Vector{JuMP_LessThanConstraintRef}
    dispatch_max::Vector{JuMP_LessThanConstraintRef}

    e_net::JuMP_ExpressionRef # MWh

    e_high::JuMP.VariableRef # MWh
    e_high_def::Vector{JuMP_LessThanConstraintRef}

    e_low::JuMP.VariableRef # MWh
    e_low_def::Vector{JuMP_LessThanConstraintRef}

    site::S

end

function StorageSiteDispatch(
    m::JuMP.Model, region::RegionParams, stor::StorageParams,
    site::StorageSiteParams, period::TimePeriod)

    T = length(period)

    dispatch = @variable(m, [1:T])
    fullname = join([
        region.name, stor.name, site.name, period.name], ",")
    varnames!(dispatch, "stor_dispatch[$(fullname)]", 1:T)

    capacity = maxpower(site)

    dispatch_min = @constraint(m, [t in 1:T], -capacity <= dispatch[t])
    dispatch_max = @constraint(m, [t in 1:T], dispatch[t] <= capacity)

    e_net = @expression(m, sum(dispatch))

    e_high = @variable(m, base_name="stor_ΔE_high[$(fullname)]")
    e_high_def = @constraint(m, [t in 1:T], sum(dispatch[1:t]) <= e_high)

    e_low = @variable(m, base_name="stor_ΔE_low[$(fullname)]")
    e_low_def = @constraint(m, [t in 1:T], e_low <= sum(dispatch[1:t]))

    return StorageSiteDispatch{StorageSiteParams}(
        dispatch, dispatch_min, dispatch_max,
        e_net, e_high, e_high_def, e_low, e_low_def, site)

end

"""
StorageDispatch contains optimization problem components for
dispatching a StorageTechnology. StorageDispatch constructors should take
the following arguments:
```
StorageDispatch(::JuMP.Model, ::Region, ::StorageTechnology, ::TimePeriod)
```
"""
struct StorageDispatch{ST<:StorageTechnology, SS<:StorageSite}

    sites::Vector{StorageSiteDispatch{SS}}

    dispatch::Vector{JuMP_ExpressionRef}

    stor::ST

end

function StorageDispatch(
    m::JuMP.Model, region::RegionParams,
    stor::StorageParams, period::TimePeriod)

    T = length(period)

    sites = [StorageSiteDispatch(
                m, region, stor, site, period)
             for site in stor.sites]

    dispatch = @expression(m, [t in 1:T],
       sum(site.dispatch[t] for site in sites)
    )

    return DispatchModel.StorageDispatch{StorageParams, StorageSiteParams}(
        sites, dispatch, stor)

end

"""
InterfaceDispatch contains optimization problem components for
dispatching an Interface. InterfaceDispatch constructors should take
the following arguments:
```
InterfaceDispatch(::JuMP.Model, ::Interface, ::TimePeriod)
```
"""
struct InterfaceDispatch{I<:Interface}

    flow::Vector{JuMP.VariableRef}

    flow_min::Vector{JuMP_GreaterThanConstraintRef}
    flow_max::Vector{JuMP_LessThanConstraintRef}

    iface::I

end

function InterfaceDispatch(
    m::JuMP.Model, iface::InterfaceParams, period::TimePeriod)

    T = length(period)

    flow = @variable(m, [1:T])
    varnames!(flow, "iface_flow[$(iface.name),$(period.name)]", 1:T)

    flow_min = @constraint(m, [t in 1:T],
        flow[t] >= -iface.capacity_existing)

    flow_max = @constraint(m, [t in 1:T],
        flow[t] <= iface.capacity_existing)

    return DispatchModel.InterfaceDispatch{InterfaceParams}(
        flow, flow_min, flow_max, iface)

end

"""
RegionDispatch is an abstract type for holding optimization problem components
for dispatching a Region. RegionDispatch instance constructors should take the
following arguments:
```
RegionDispatch(::JuMP.Model, ::Region, ::Vector{InterfaceDispatch}, ::TimePeriod)
```
"""
abstract type RegionDispatch{R<:Region} end

# Do we even need this one?
"""
SystemDispatch contains optimization problem components for
dispatching a System. SystemDispatch constructors should take the
following arguments:
```
SystemDispatch(::JuMP.Model, ::System, ::TimePeriod)
```
"""
abstract type SystemDispatch{S<:System} end
