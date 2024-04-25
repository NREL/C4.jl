struct GeneratorDispatch

    dispatch::Vector{JuMP.VariableRef}
    dispatch_max::Vector{JuMP_LessThanConstraintRef}

    function GeneratorDispatch(
        m::JuMP.Model, regionbuild::RegionBuild, genbuild::GeneratorBuild, period::TimePeriod
    )

        T = length(period)

        dispatch = @variable(m, [1:T], lower_bound = 0)
        fullname = join([regionbuild.params.name, genbuild.params.name, period.name], ",")
        varnames!(dispatch, "gen_dispatch[$(fullname)]", 1:T)

        dispatch_max = @constraint(m, [t in 1:T],
            dispatch[t] <= availablecapacity(genbuild, t))

        new(dispatch, dispatch_max)

    end

end

struct StorageDispatch

    dispatch::Vector{JuMP.VariableRef}

    dispatch_min::Vector{JuMP_LessThanConstraintRef}
    dispatch_max::Vector{JuMP_LessThanConstraintRef}

    e_net::JuMP_ExpressionRef # MWh

    e_high::JuMP.VariableRef # MWh
    e_high_def::Vector{JuMP_LessThanConstraintRef}

    e_low::JuMP.VariableRef # MWh
    e_low_def::Vector{JuMP_LessThanConstraintRef}

    function StorageDispatch(
        m::JuMP.Model, regionbuild::RegionBuild, storbuild::StorageBuild, period::TimePeriod
    )

        T = length(period)

        dispatch = @variable(m, [1:T])
        fullname = join([regionbuild.params.name, storbuild.params.name, period.name], ",")
        varnames!(dispatch, "stor_dispatch[$(fullname)]", 1:T)

        capacity = maxpower(storbuild)

        dispatch_min = @constraint(m, [t in 1:T], -capacity <= dispatch[t])
        dispatch_max = @constraint(m, [t in 1:T], dispatch[t] <= capacity)

        e_net = @expression(m, sum(dispatch))

        e_high = @variable(m, base_name="stor_ΔE_high[$(fullname)]")
        e_high_def = @constraint(m, [t in 1:T], sum(dispatch[1:t]) <= e_high)

        e_low = @variable(m, base_name="stor_ΔE_low[$(fullname)]")
        e_low_def = @constraint(m, [t in 1:T], e_low <= sum(dispatch[1:t]))

        return new(dispatch, dispatch_min, dispatch_max,
                   e_net, e_high, e_high_def, e_low, e_low_def)

    end

end

struct InterfaceDispatch

    flow::Vector{JuMP.VariableRef}

    flow_min::Vector{JuMP_GreaterThanConstraintRef}
    flow_max::Vector{JuMP_LessThanConstraintRef}

    function InterfaceDispatch(
        m::JuMP.Model, iface::InterfaceBuild, period::TimePeriod
    )

        T = length(period)

        flow = @variable(m, [1:T])
        varnames!(flow, "iface_flow[$(iface.params.name),$(period.name)]", 1:T)

        flow_min = @constraint(m, [t in 1:T],
            flow[t] >= -iface.params.capacity_existing - iface.capacity_new)

        flow_max = @constraint(m, [t in 1:T],
            flow[t] <= iface.params.capacity_existing + iface.capacity_new)

        new(flow, flow_min, flow_max)

    end

end

struct RegionEconomicDispatch

    thermaltechs::Vector{GeneratorDispatch}
    variabletechs::Vector{GeneratorDispatch}
    storagetechs::Vector{StorageDispatch}

    netload::Vector{JuMP_ExpressionRef}

    import_interfaces::Vector{InterfaceDispatch}
    export_interfaces::Vector{InterfaceDispatch}

    function RegionEconomicDispatch(
        m::JuMP.Model,
        regionbuild::RegionBuild,
        interfaces::Vector{InterfaceDispatch},
        period::TimePeriod
    )

        T = length(period)

        thermaldispatch = [GeneratorDispatch(m, regionbuild, techbuild, period)
                           for techbuild in regionbuild.thermaltechs]

        variabledispatch = [GeneratorDispatch(m, regionbuild, techbuild, period)
                            for techbuild in regionbuild.variabletechs]

        storagedispatch = [StorageDispatch(m, regionbuild, techbuild, period)
                           for techbuild in regionbuild.storagetechs]

        netload = @expression(m, [t in 1:T], regionbuild.params.demand[t]
                - sum(tech.dispatch[t] for tech in thermaldispatch)
                - sum(tech.dispatch[t] for tech in variabledispatch)
                - sum(tech.dispatch[t] for tech in storagedispatch))

        import_interfaces = [interfaces[i] for i in regionbuild.params.import_interfaces]
        export_interfaces = [interfaces[i] for i in regionbuild.params.export_interfaces]

        new(thermaldispatch, variabledispatch, storagedispatch,
            netload, import_interfaces, export_interfaces)

    end

end

abstract type Dispatch end

struct EconomicDispatch <: Dispatch

    regions::Vector{RegionEconomicDispatch}
    interfaces::Vector{InterfaceDispatch}

    netimports::Matrix{JuMP_ExpressionRef}
    powerbalance::Matrix{JuMP_EqualToConstraintRef}

    function EconomicDispatch(m::JuMP.Model, builds::Builds, period::TimePeriod)

        T = length(period)
        R = length(builds.regions)

        interfaces = [InterfaceDispatch(m, iface, period)
                   for iface in builds.interfaces]

        regions = [RegionEconomicDispatch(m, region, interfaces, period)
                   for region in builds.regions]

        netimports = @expression(m, [r in 1:R, t in 1:T],
           sum(iface.flow[t] for iface in regions[r].import_interfaces) -
           sum(iface.flow[t] for iface in regions[r].export_interfaces)
        )

        powerbalance = @constraint(m, [r in 1:R, t in 1:T],
            regions[r].netload[t] == netimports[r,t])

        new(regions, interfaces, netimports, powerbalance)

    end

end

struct ReliabilityDispatch <: Dispatch

    # TODO

    function ReliabilityDispatch(m::JuMP.Model, builds::Builds, period::TimePeriod)
        new()
    end

end

struct DispatchRecurrence{D <: Dispatch}

    dispatch::D
    repetitions::Int

    next_recurrence::Union{DispatchRecurrence{D}, Nothing}

end

mutable struct DispatchSequence{D <: Dispatch}

    time::TimeProxyAssignment

    dispatches::Vector{D}

    first_recurrence::Union{DispatchRecurrence{D}, Nothing}

    function DispatchSequence{D}(m::JuMP.Model, builds::Builds, time::TimeProxyAssignment) where D

        dispatches = [D(m, builds, period) for period in time.periods]

        new(time, dispatches, nothing)

    end

end

