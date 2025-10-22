struct RegionReliabilityDispatch{R,I} <: RegionDispatch{R}

    storagetechs::Vector{StorageDispatch}

    available_capacity::Vector{JuMP_ExpressionRef}

    import_interfaces::Vector{InterfaceDispatch{I}}
    export_interfaces::Vector{InterfaceDispatch{I}}

    region::R

    function RegionReliabilityDispatch(
        m::JuMP.Model,
        region::R,
        interfaces::Vector{InterfaceDispatch{I}},
        period::TimePeriod
    ) where {I, R<:Region{I}}

        n_timesteps = length(period)
        ts = period.timesteps

        storagedispatch = [StorageDispatch(m, region, stor, period)
                           for stor in storagetechs(region)]

        available_capacity = @expression(m, [t in 1:n_timesteps],
                sum(availablecapacity(gen, ts[t]) for gen in variabletechs(region))
                + sum(availablecapacity(gen, ts[t]) for gen in thermaltechs(region))
                + sum(stor.dispatch[t] for stor in storagedispatch))

        import_interfaces = [interfaces[i] for i in importinginterfaces(region)]
        export_interfaces = [interfaces[i] for i in exportinginterfaces(region)]

        new{R,I}(storagedispatch, available_capacity,
                 import_interfaces, export_interfaces, region)

    end

end

struct ReliabilityDispatch{S<:System, R<:Region, I<:Interface} <: SystemDispatch{S}

    period::TimePeriod

    regions::Vector{RegionReliabilityDispatch}
    interfaces::Vector{InterfaceDispatch}

    netimports::Matrix{JuMP_ExpressionRef}
    available_capacity::Matrix{JuMP_ExpressionRef}

    system::S

    function ReliabilityDispatch(
        m::JuMP.Model, system::S, period::TimePeriod, voll::Float64=NaN
    ) where { R<:Region, I<:Interface, S<:System{R,I} }

        isnan(voll) ||
            @warn("A non-NaN VoLL was provided, but will be ignored by ReliabilityDispatch")

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

        available_capacity = @expression(m, [r in 1:n_regions, t in 1:n_timesteps],
            regions[r].available_capacity[t] + netimports[r,t])

        new{S,R,I}(period, regions, interfaces, netimports,
                   available_capacity, system)

    end

end

const ReliabilityDispatchSequence = DispatchSequence{<:ReliabilityDispatch}

cost(dispatch::ReliabilityDispatch) = 0
