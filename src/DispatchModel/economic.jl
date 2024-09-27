struct RegionEconomicDispatch{R,TG,VG,ST,SS,I} <: RegionDispatch{R}

    thermaltechs::Vector{GeneratorDispatch{TG}}
    variabletechs::Vector{GeneratorDispatch{VG}}
    storagetechs::Vector{StorageDispatch{ST,SS}}

    netload::Vector{JuMP_ExpressionRef}

    import_interfaces::Vector{InterfaceDispatch{I}}
    export_interfaces::Vector{InterfaceDispatch{I}}

    region::R

    function RegionEconomicDispatch(
        m::JuMP.Model,
        region::R,
        interfaces::Vector{InterfaceDispatch{I}},
        period::TimePeriod
    ) where {TG, VG, ST, SS, I, R<:Region{TG,VG,ST,SS,I} }

        T = length(period)
        ts = period.timesteps

        thermaldispatch = [GeneratorDispatch(m, region, tech, period)
                           for tech in region.thermaltechs]

        variabledispatch = [GeneratorDispatch(m, region, tech, period)
                            for tech in region.variabletechs]

        storagedispatch = [StorageDispatch(m, region, tech, period)
                           for tech in region.storagetechs]

        netload = @expression(m, [t in 1:T],
                demand(region, ts[t])
                - sum(gen.dispatch[t] for gen in thermaldispatch)
                - sum(gen.dispatch[t] for gen in variabledispatch)
                - sum(stor.dispatch[t] for stor in storagedispatch))

        import_interfaces = [interfaces[i] for i in importinginterfaces(region)]
        export_interfaces = [interfaces[i] for i in exportinginterfaces(region)]

        new{R,TG,VG,ST,SS,I}(
            thermaldispatch, variabledispatch, storagedispatch,
            netload, import_interfaces, export_interfaces, region)

    end

end

cost(dispatch::RegionEconomicDispatch) =
    sum(cost(thermaltech) for thermaltech in dispatch.thermaltechs; init=0) +
    sum(cost(variabletech) for variabletech in dispatch.variabletechs; init=0)

struct EconomicDispatch{S<:System, R<:Region, I<:Interface} <: SystemDispatch{S}

    period::TimePeriod

    regions::Vector{RegionEconomicDispatch{R}}
    interfaces::Vector{InterfaceDispatch{I}}

    netimports::Matrix{JuMP_ExpressionRef}
    powerbalance::Matrix{JuMP_EqualToConstraintRef}

    system::S

    function EconomicDispatch(
        m::JuMP.Model, system::S, period::TimePeriod
    ) where { R<:Region, I<:Interface, S<:System{R,I} }

        n_timesteps = length(period)
        n_regions = length(system.regions)

        interfaces = [InterfaceDispatch(m, iface, period)
                   for iface in system.interfaces]

        regions = [RegionEconomicDispatch(m, region, interfaces, period)
                   for region in system.regions]

        netimports = @expression(m, [r in 1:n_regions, t in 1:n_timesteps],
           sum(iface.flow[t] for iface in regions[r].import_interfaces) -
           sum(iface.flow[t] for iface in regions[r].export_interfaces)
        )

        powerbalance = @constraint(m, [r in 1:n_regions, t in 1:n_timesteps],
            regions[r].netload[t] == netimports[r,t])

        new{S,R,I}(period, regions, interfaces, netimports,
                   powerbalance, system)

    end

end

const EconomicDispatchSequence = DispatchSequence{<:EconomicDispatch}

cost(dispatch::EconomicDispatch) =
    sum(cost(region) for region in dispatch.regions; init=0)
