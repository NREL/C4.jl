abstract type RegionDispatch end
abstract type Dispatch end

struct GeneratorTechDispatch

    dispatch::Vector{JuMP.VariableRef}
    dispatch_max::Vector{JuMP_LessThanConstraintRef}

    function GeneratorTechDispatch(
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

struct StorageSiteDispatch

    dispatch::Vector{JuMP.VariableRef}

    dispatch_min::Vector{JuMP_LessThanConstraintRef}
    dispatch_max::Vector{JuMP_LessThanConstraintRef}

    e_net::JuMP_ExpressionRef # MWh

    e_high::JuMP.VariableRef # MWh
    e_high_def::Vector{JuMP_LessThanConstraintRef}

    e_low::JuMP.VariableRef # MWh
    e_low_def::Vector{JuMP_LessThanConstraintRef}

    function StorageSiteDispatch(
        m::JuMP.Model, regionbuild::RegionBuild, storbuild::StorageBuild,
        sitebuild::StorageSiteBuild, period::TimePeriod
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

        return new(dispatch, dispatch_min, dispatch_max,
                   e_net, e_high, e_high_def, e_low, e_low_def)

    end

end

struct StorageTechDispatch

    sites::Vector{StorageSiteDispatch}
    dispatch::Vector{JuMP_ExpressionRef}

    function StorageTechDispatch(
        m::JuMP.Model, regionbuild::RegionBuild, storbuild::StorageBuild, period::TimePeriod
    )

        T = length(period)

        sites = [StorageSiteDispatch(m, regionbuild, storbuild, sitebuild, period)
                 for sitebuild in storbuild.sites]

        dispatch = @expression(m, [t in 1:T],
           sum(site.dispatch[t] for site in sites)
        )

        new(sites, dispatch)

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

struct RegionEconomicDispatch <: RegionDispatch

    thermaltechs::Vector{GeneratorTechDispatch}
    variabletechs::Vector{GeneratorTechDispatch}
    storagetechs::Vector{StorageTechDispatch}

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

        thermaldispatch = [GeneratorTechDispatch(m, regionbuild, techbuild, period)
                           for techbuild in regionbuild.thermaltechs]

        variabledispatch = [GeneratorTechDispatch(m, regionbuild, techbuild, period)
                            for techbuild in regionbuild.variabletechs]

        storagedispatch = [StorageTechDispatch(m, regionbuild, techbuild, period)
                           for techbuild in regionbuild.storagetechs]

        netload = @expression(m, [t in 1:T], regionbuild.params.demand[t]
                - sum(gen.dispatch[t] for gen in thermaldispatch)
                - sum(gen.dispatch[t] for gen in variabledispatch)
                - sum(stor.dispatch[t] for stor in storagedispatch))

        import_interfaces = [interfaces[i] for i in regionbuild.params.import_interfaces]
        export_interfaces = [interfaces[i] for i in regionbuild.params.export_interfaces]

        new(thermaldispatch, variabledispatch, storagedispatch,
            netload, import_interfaces, export_interfaces)

    end

end

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

struct RegionReliabilityDispatch <: RegionDispatch

    storagetechs::Vector{StorageTechDispatch}

    surplus_mean::Vector{JuMP_ExpressionRef}

    import_interfaces::Vector{InterfaceDispatch}
    export_interfaces::Vector{InterfaceDispatch}

    function RegionReliabilityDispatch(
        m::JuMP.Model,
        regionbuild::RegionBuild,
        interfaces::Vector{InterfaceDispatch},
        period::TimePeriod
    )

        T = length(period)

        storagedispatch = [StorageTechDispatch(m, regionbuild, techbuild, period)
                           for techbuild in regionbuild.storagetechs]

        surplus_mean = @expression(m, [t in 1:T],
            sum(availablecapacity(gen, t) for gen in regionbuild.variabletechs)
            + sum(availablecapacity(gen, t) for gen in regionbuild.thermaltechs)
            + sum(stor.dispatch[t] for stor in storagedispatch)
            - regionbuild.params.demand[t]
        )

        import_interfaces = [interfaces[i] for i in regionbuild.params.import_interfaces]
        export_interfaces = [interfaces[i] for i in regionbuild.params.export_interfaces]

        new(storagedispatch, surplus_mean, import_interfaces, export_interfaces)

    end

end

struct ReliabilityDispatch <: Dispatch

    regions::Vector{RegionReliabilityDispatch}
    interfaces::Vector{InterfaceDispatch}

    netimports::Matrix{JuMP_ExpressionRef}

    surplus_mean::Matrix{JuMP_ExpressionRef}
    surplus_floor::Matrix{JuMP_LessThanConstraintRef}

    eue::Matrix{JuMP.VariableRef}
    eue_segments::JuMP.Containers.SparseAxisArray{JuMP_GreaterThanConstraintRef,3,Tuple{Int64,Int64,Int64}}

    function ReliabilityDispatch(
        m::JuMP.Model, builds::Builds, period::TimePeriod,
        eue_estimator::PeriodEUEEstimator)

        T = length(period)
        R = length(builds.regions)
        regionnames = [region.params.name for region in builds.regions]

        interfaces = [InterfaceDispatch(m, iface, period)
                   for iface in builds.interfaces]

        regions = [RegionReliabilityDispatch(m, region, interfaces, period)
                   for region in builds.regions]

        netimports = @expression(m, [r in 1:R, t in 1:T],
           sum(iface.flow[t] for iface in regions[r].import_interfaces) -
           sum(iface.flow[t] for iface in regions[r].export_interfaces)
        )

        surplus_mean = @expression(m, [r in 1:R, t in 1:T],
            regions[r].surplus_mean[t] + netimports[r,t]
        )

        surplus_floor = @constraint(m, [r in 1:R, t in 1:T],
            0 <= surplus_mean[r,t]
        )

        eue = @variable(m, [1:R, 1:T], lower_bound = 0)
        varnames!(eue, "eue[$(period.name)]", regionnames, 1:T)

        eue_segments = @constraint(m, [r in 1:R, t in 1:T, s in 1:n_segments(eue_estimator, r, t)],
            eue[r,t] >= intercept(eue_estimator, r, t, s)
                        - surplus_mean[r,t] * slope(eue_estimator, r, t, s)
        )

        new(regions, interfaces, netimports,
            surplus_mean, surplus_floor,
            eue, eue_segments)

    end

end

struct StorageSiteDispatchRecurrence

    emin_first::JuMP_LessThanConstraintRef
    emax_first::JuMP_LessThanConstraintRef
    emin_last::JuMP_LessThanConstraintRef
    emax_last::JuMP_LessThanConstraintRef

    soc_last::JuMP_ExpressionRef

    function StorageSiteDispatchRecurrence(
        m::JuMP.Model,
        prev_recurrence::Union{StorageSiteDispatchRecurrence,Nothing},
        build::StorageSiteBuild, dispatch::StorageSiteDispatch, repetitions::Int)

        energy = maxenergy(build)

        soc0_first = isnothing(prev_recurrence) ? 0 : prev_recurrence.soc_last
        soc0_last = soc0_first + (repetitions - 1) * dispatch.e_net

        emin_first = @constraint(m, 0 <= soc0_first + dispatch.e_low)
        emax_first = @constraint(m, soc0_first + dispatch.e_high <= energy)
        emin_last = @constraint(m, 0 <= soc0_last + dispatch.e_low)
        emax_last = @constraint(m, soc0_last + dispatch.e_high <= energy)

        soc_last = soc0_first + repetitions * dispatch.e_net

        new(emin_first, emax_first, emin_last, emax_last, soc_last)

    end

end

struct StorageTechDispatchRecurrence

    sites::Vector{StorageSiteDispatchRecurrence}

    function StorageTechDispatchRecurrence(
        m::JuMP.Model,
        prev_recurrence::Union{StorageTechDispatchRecurrence,Nothing},
        build::TechnologyBuild{StorageTechnology,StorageSiteBuild},
        dispatch::StorageTechDispatch, repetitions::Int
    )

        prev_recurrence_sites = isnothing(prev_recurrence) ?
            StorageSiteDispatchRecurrence[] : prev_recurrence.sites

        sites = [
            StorageSiteDispatchRecurrence(
                m, prev_siterecurrence, sitebuild, sitedispatch, repetitions)
            for (prev_siterecurrence, sitebuild, sitedispatch)
            in zip_longest(prev_recurrence_sites, build.sites, dispatch.sites)
        ]

        new(sites)

    end

end

struct RegionDispatchRecurrence

    storagetechs::Vector{StorageTechDispatchRecurrence}

    function RegionDispatchRecurrence(
        m::JuMP.Model,
        prev_recurrence::Union{RegionDispatchRecurrence,Nothing},
        build::RegionBuild, dispatch::D, repetitions::Int
    ) where D <: RegionDispatch

        prev_recurrence_storagetechs = isnothing(prev_recurrence) ?
            StorageTechDispatchRecurrence[] : prev_recurrence.storagetechs

        storagetechs = [
            StorageTechDispatchRecurrence(
                m, prev_techrecurrence, techbuild, techdispatch, repetitions)
            for (prev_techrecurrence, techbuild, techdispatch)
            in zip_longest(prev_recurrence_storagetechs, build.storagetechs, dispatch.storagetechs)
        ]

        new(storagetechs)

    end

end

struct DispatchRecurrence{D <: Dispatch}

    dispatch::D
    repetitions::Int

    regions::Vector{RegionDispatchRecurrence}

    function DispatchRecurrence(
        m::JuMP.Model, prev_recurrence::Union{DispatchRecurrence{D},Nothing},
        build::Builds, dispatch::D, repetitions::Int
    ) where D <: Dispatch

        prev_recurrence_regions = isnothing(prev_recurrence) ?
            RegionDispatchRecurrence[] : prev_recurrence.regions

        regions = [
            RegionDispatchRecurrence(
                m, prev_regionrecurrence, regionbuild, regiondispatch, repetitions)
            for (prev_regionrecurrence, regionbuild, regiondispatch)
            in zip_longest(prev_recurrence_regions, build.regions, dispatch.regions)]

        new{D}(dispatch, repetitions, regions)

    end

end

struct EconomicDispatchSequence

    time::TimeProxyAssignment

    dispatches::Vector{EconomicDispatch}
    recurrences::Vector{DispatchRecurrence{EconomicDispatch}}

    function EconomicDispatchSequence(m::JuMP.Model, builds::Builds, time::TimeProxyAssignment)

        dispatches = [EconomicDispatch(m, builds, period) for period in time.periods]

        recurrences = sequence_recurrences(m, builds, dispatches, time)

        new(time, dispatches, recurrences)

    end

end

struct ReliabilityDispatchSequence

    time::TimeProxyAssignment

    dispatches::Vector{ReliabilityDispatch}
    recurrences::Vector{DispatchRecurrence{ReliabilityDispatch}}

    region_eue::Vector{JuMP_ExpressionRef}
    region_eue_max::Vector{JuMP_LessThanConstraintRef}

    function ReliabilityDispatchSequence(
        m::JuMP.Model, builds::Builds,
        eue_estimator::EUEEstimator, eue_max::Vector{Float64})

        dispatches = [ReliabilityDispatch(m, builds, period, period_estimator)
                      for (period, period_estimator) in allperiods(eue_estimator)]

        recurrences = sequence_recurrences(m, builds, dispatches, eue_estimator.times)

        R = length(builds.regions)

        region_eue = @expression(m, [r in 1:R],
            sum(sum(dispatch.eue[r, :]) for dispatch in dispatches))

        region_eue_max = @constraint(m, [r in 1:R],
            region_eue[r] <= eue_max[r])

        new(eue_estimator.times, dispatches, recurrences, region_eue, region_eue_max)

    end

end

function sequence_recurrences(
    m::JuMP.Model, builds::Builds, dispatches::Vector{D}, time::TimeProxyAssignment
) where D <: Dispatch

    sequence = deduplicate(time.days)
    recurrences = Vector{DispatchRecurrence}(undef, length(sequence))

    prev_recurrence = nothing

    for (i, (p, repetitions)) in enumerate(sequence)

        recurrence = DispatchRecurrence(m, prev_recurrence, builds, dispatches[p], repetitions)

        recurrences[i]  = recurrence
        prev_recurrence = recurrence

    end

    return recurrences

end

function deduplicate(xs::Vector{Int})

    result = Pair{Int,Int}[]

    iszero(length(xs)) && return result

    x_prev = first(xs)
    repetitions = 1

    for x in xs[2:end]

        if x == x_prev
            repetitions += 1
            continue
        end

        push!(result, x_prev=>repetitions)

        x_prev = x
        repetitions = 1

    end

    push!(result, x_prev=>repetitions)

    return result

end
