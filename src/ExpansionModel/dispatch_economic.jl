struct RegionEconomicDispatch <: RegionDispatch

    thermaltechs::Vector{GeneratorTechDispatch}
    variabletechs::Vector{GeneratorTechDispatch}
    storagetechs::Vector{StorageTechDispatch}

    netload::Vector{JuMP_ExpressionRef}

    import_interfaces::Vector{InterfaceDispatch}
    export_interfaces::Vector{InterfaceDispatch}

    build::RegionBuild

    function RegionEconomicDispatch(
        m::JuMP.Model,
        regionbuild::RegionBuild,
        interfaces::Vector{InterfaceDispatch},
        period::TimePeriod
    )

        T = length(period)
        ts = period.timesteps

        thermaldispatch = [GeneratorTechDispatch(m, regionbuild, techbuild, period)
                           for techbuild in regionbuild.thermaltechs]

        variabledispatch = [GeneratorTechDispatch(m, regionbuild, techbuild, period)
                            for techbuild in regionbuild.variabletechs]

        storagedispatch = [StorageTechDispatch(m, regionbuild, techbuild, period)
                           for techbuild in regionbuild.storagetechs]

        netload = @expression(m, [t in 1:T],
                regionbuild.params.demand[ts[t]]
                - sum(gen.dispatch[t] for gen in thermaldispatch)
                - sum(gen.dispatch[t] for gen in variabledispatch)
                - sum(stor.dispatch[t] for stor in storagedispatch))

        import_interfaces = [interfaces[i] for i in regionbuild.params.import_interfaces]
        export_interfaces = [interfaces[i] for i in regionbuild.params.export_interfaces]

        new(thermaldispatch, variabledispatch, storagedispatch,
            netload, import_interfaces, export_interfaces, regionbuild)

    end

end

cost(dispatch::RegionEconomicDispatch) =
    sum(cost(thermaltech) for thermaltech in dispatch.thermaltechs; init=0) +
    sum(cost(variabletech) for variabletech in dispatch.variabletechs; init=0)

struct EconomicDispatch <: Dispatch

    regions::Vector{RegionEconomicDispatch}
    interfaces::Vector{InterfaceDispatch}

    netimports::Matrix{JuMP_ExpressionRef}
    powerbalance::Matrix{JuMP_EqualToConstraintRef}

    build::Builds

    function EconomicDispatch(m::JuMP.Model, build::Builds, period::TimePeriod)

        T = length(period)
        R = length(build.regions)

        interfaces = [InterfaceDispatch(m, iface, period)
                   for iface in build.interfaces]

        regions = [RegionEconomicDispatch(m, region, interfaces, period)
                   for region in build.regions]

        netimports = @expression(m, [r in 1:R, t in 1:T],
           sum(iface.flow[t] for iface in regions[r].import_interfaces) -
           sum(iface.flow[t] for iface in regions[r].export_interfaces)
        )

        powerbalance = @constraint(m, [r in 1:R, t in 1:T],
            regions[r].netload[t] == netimports[r,t])

        new(regions, interfaces, netimports, powerbalance, build)

    end

end

cost(dispatch::EconomicDispatch) =
    sum(cost(region) for region in dispatch.regions; init=0)

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

cost(sequence::EconomicDispatchSequence) =
    sum(cost(recurrence) for recurrence in sequence.recurrences; init=0)
