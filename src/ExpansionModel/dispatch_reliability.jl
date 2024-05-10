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

    build::Builds

    function ReliabilityDispatch(
        m::JuMP.Model, build::Builds, period::TimePeriod,
        eue_estimator::PeriodEUEEstimator)

        T = length(period)
        R = length(build.regions)
        regionnames = [region.params.name for region in build.regions]

        interfaces = [InterfaceDispatch(m, iface, period)
                   for iface in build.interfaces]

        regions = [RegionReliabilityDispatch(m, region, interfaces, period)
                   for region in build.regions]

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
            eue, eue_segments, build)

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
