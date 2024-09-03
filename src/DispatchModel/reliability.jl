struct RegionReliabilityDispatch{R,ST,SS,I} <: RegionDispatch{R}

    storagetechs::Vector{StorageDispatch{ST,SS}}

    surplus_mean::Vector{JuMP_ExpressionRef}

    import_interfaces::Vector{InterfaceDispatch{I}}
    export_interfaces::Vector{InterfaceDispatch{I}}

    region::R

    function RegionReliabilityDispatch(
        m::JuMP.Model,
        region::R,
        interfaces::Vector{InterfaceDispatch{I}},
        period::TimePeriod
    ) where {TG, VG, ST, SS, I, R<:Region{TG,VG,ST,SS,I}}

        n_timesteps = length(period)
        ts = period.timesteps

        storagedispatch = [StorageDispatch(m, region, stor, period)
                           for stor in region.storagetechs]

        surplus_mean = @expression(m, [t in 1:n_timesteps],
            sum(availablecapacity(gen, ts[t]) for gen in region.variabletechs)
            + sum(availablecapacity(gen, ts[t]) for gen in region.thermaltechs)
            + sum(stor.dispatch[t] for stor in storagedispatch)
            - region.params.demand[ts[t]] # TODO: Abstract demand(region, t)
        )

        # TODO: Abstract interfaces in/out
        import_interfaces = [interfaces[i] for i in region.params.import_interfaces]
        export_interfaces = [interfaces[i] for i in region.params.export_interfaces]

        new{R,ST,SS,I}(storagedispatch, surplus_mean,
                       import_interfaces, export_interfaces, region)

    end

end

struct ReliabilityDispatch{S<:System, R<:Region, I<:Interface} <: SystemDispatch{S}

    period::TimePeriod

    regions::Vector{RegionReliabilityDispatch}
    interfaces::Vector{InterfaceDispatch}

    netimports::Matrix{JuMP_ExpressionRef}
    surplus_mean::Matrix{JuMP_ExpressionRef}
    surplus_floor::Matrix{JuMP_LessThanConstraintRef}

    system::S

    function ReliabilityDispatch(
        m::JuMP.Model, system::S, period::TimePeriod
    ) where { R<:Region, I<:Interface, S<:System{R,I} }

        n_timesteps = length(period)
        n_regions = length(system.regions)

        interfaces = [InterfaceDispatch(m, iface, period)
                   for iface in system.interfaces]

        regions = [RegionReliabilityDispatch(m, region, interfaces, period)
                   for region in system.regions]

        netimports = @expression(m, [r in 1:n_regions, t in 1:n_timesteps],
           sum(iface.flow[t] for iface in regions[r].import_interfaces) -
           sum(iface.flow[t] for iface in regions[r].export_interfaces)
        )

        surplus_mean = @expression(m, [r in 1:n_regions, t in 1:n_timesteps],
            regions[r].surplus_mean[t] + netimports[r,t]
        )

        surplus_floor = @constraint(m, [r in 1:n_regions, t in 1:n_timesteps],
            0 <= surplus_mean[r,t]
        )

        new{S,R,I}(period, regions, interfaces, netimports,
            surplus_mean, surplus_floor, system)

    end

end

struct ReliabilityEstimate

    period::TimePeriod

    eue::Matrix{JuMP.VariableRef}
    eue_segments::JuMP.Containers.SparseAxisArray{JuMP_GreaterThanConstraintRef,3,Tuple{Int64,Int64,Int64}}

    function ReliabilityEstimate(
        m::JuMP.Model, system::System, dispatch::ReliabilityDispatch,
        eue_estimator::PeriodEUEEstimator)

        T = length(dispatch.period)
        R = length(system.regions)
        period_name = dispatch.period.name

        eue = @variable(m, [1:R, 1:T], lower_bound = 0)
        varnames!(eue, "eue[$(period_name)]", name.(system.regions), 1:T)

        eue_segments = @constraint(m, [r in 1:R, t in 1:T, s in 1:n_segments(eue_estimator, r, t)],
            eue[r,t] >= intercept(eue_estimator, r, t, s)
                        - dispatch.surplus_mean[r,t] * slope(eue_estimator, r, t, s)
        )

        new(dispatch.period, eue, eue_segments)

    end

end

struct ReliabilityConstraints

    estimates::Vector{ReliabilityEstimate}

    region_eue::Vector{JuMP_ExpressionRef}
    region_eue_max::Vector{JuMP_LessThanConstraintRef}

    function ReliabilityConstraints(
        m::JuMP.Model, system::System, dispatches::Vector{<:ReliabilityDispatch},
        eue_estimator::EUEEstimator, eue_max::Vector{Float64})

        n_regions = length(system.regions)

        eue_estimates = [
            ReliabilityEstimate(m, system, dispatch, estimator)
            for (dispatch, estimator)
            in zip(dispatches, eue_estimator.estimators)]

        region_eue = @expression(m, [r in 1:n_regions],
            sum(sum(estimate.eue[r, :]) for estimate in eue_estimates))

        region_eue_max = @constraint(m, [r in 1:n_regions],
            region_eue[r] <= eue_max[r])

        new(eue_estimates, region_eue, region_eue_max)

    end

end
