function DispatchModel.GeneratorDispatch(
    m::JuMP.Model, regionbuild::RegionExpansion,
    genbuild::G, period::TimePeriod
) where G <: GeneratorExpansion

    T = length(period)
    ts = period.timesteps

    dispatch = @variable(m, [1:T], lower_bound = 0)
    fullname = join([regionbuild.params.name, genbuild.params.name, period.name], ",")
    varnames!(dispatch, "gen_dispatch[$(fullname)]", 1:T)

    dispatch_max = @constraint(m, [t in 1:T],
        dispatch[t] <= availablecapacity(genbuild, ts[t]))

    return DispatchModel.GeneratorDispatch{G}(
        dispatch, dispatch_max, genbuild)

end

function DispatchModel.StorageSiteDispatch(
    m::JuMP.Model, regionbuild::RegionExpansion, storbuild::StorageExpansion,
    sitebuild::StorageSiteExpansion, period::TimePeriod
)

    T = length(period)

    dispatch = @variable(m, [1:T])
    fullname = join([
        regionbuild.params.name, storbuild.params.name,
        sitebuild.params.name, period.name], ",")
    varnames!(dispatch, "stor_dispatch[$(fullname)]", 1:T)

    capacity = maxpower(sitebuild)

    dispatch_min = @constraint(m, [t in 1:T], -capacity <= dispatch[t])
    dispatch_max = @constraint(m, [t in 1:T], dispatch[t] <= capacity)

    e_net = @expression(m, sum(dispatch))

    e_high = @variable(m, base_name="stor_ΔE_high[$(fullname)]")
    e_high_def = @constraint(m, [t in 1:T], sum(dispatch[1:t]) <= e_high)

    e_low = @variable(m, base_name="stor_ΔE_low[$(fullname)]")
    e_low_def = @constraint(m, [t in 1:T], e_low <= sum(dispatch[1:t]))

    return DispatchModel.StorageSiteDispatch{StorageSiteExpansion}(
        dispatch, dispatch_min, dispatch_max,
        e_net, e_high, e_high_def, e_low, e_low_def, sitebuild)

end

function DispatchModel.StorageDispatch(
    m::JuMP.Model, regionbuild::RegionExpansion, storbuild::StorageExpansion, period::TimePeriod
)

    T = length(period)

    sites = [DispatchModel.StorageSiteDispatch(
                m, regionbuild, storbuild, sitebuild, period)
             for sitebuild in storbuild.sites]

    dispatch = @expression(m, [t in 1:T],
       sum(site.dispatch[t] for site in sites)
    )

    return DispatchModel.StorageDispatch{StorageExpansion, StorageSiteExpansion}(
        sites, dispatch, storbuild)

end

function DispatchModel.InterfaceDispatch(
    m::JuMP.Model, iface::InterfaceExpansion, period::TimePeriod
)

    T = length(period)

    flow = @variable(m, [1:T])
    varnames!(flow, "iface_flow[$(iface.params.name),$(period.name)]", 1:T)

    flow_min = @constraint(m, [t in 1:T],
        flow[t] >= -iface.params.capacity_existing - iface.capacity_new)

    flow_max = @constraint(m, [t in 1:T],
        flow[t] <= iface.params.capacity_existing + iface.capacity_new)

    return DispatchModel.InterfaceDispatch{InterfaceExpansion}(
        flow, flow_min, flow_max, iface)

end
