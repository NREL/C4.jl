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
