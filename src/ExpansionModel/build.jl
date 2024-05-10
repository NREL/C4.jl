abstract type ResourceSiteBuild end

struct ThermalSiteBuild <: ResourceSiteBuild

    params::ThermalSite
    units_new::JuMP.VariableRef

    function ThermalSiteBuild(
        m::JuMP.Model, siteparams::ThermalSite,
        techparams::ThermalTechnology, regionparams::Region
    )

        fullname = join([regionparams.name, techparams.name, siteparams.name], ",")
        units_new = @variable(m, integer=true, lower_bound=0, upper_bound=siteparams.units_new_max)
        JuMP.set_name(units_new, "thermal_new_units[$fullname]")
        new(siteparams, units_new)

    end

end

sitebuildtype(::Type{ThermalTechnology}) = ThermalSiteBuild

function ThermalSite(build::ThermalSiteBuild)
    site = build.params
    new_units = value(build.units_new)
    return ThermalSite(
        site.name,
        site.units_existing + new_units,
        site.units_new_max - new_units,
        site.λ, site.μ)
end

struct VariableSiteBuild <: ResourceSiteBuild

    params::VariableSite
    capacity_new::JuMP.VariableRef

    function VariableSiteBuild(
        m::JuMP.Model, siteparams::VariableSite,
        techparams::VariableTechnology, regionparams::Region
    )

        fullname = join([regionparams.name, techparams.name, siteparams.name], ",")
        capacity_new = @variable(m, lower_bound=0, upper_bound=siteparams.capacity_new_max)
        JuMP.set_name(capacity_new, "variable_new_capacity[$fullname]")
        new(siteparams, capacity_new)

    end

end

sitebuildtype(::Type{VariableTechnology}) = VariableSiteBuild

function VariableSite(build::VariableSiteBuild)
    site = build.params
    new_capacity = value(build.capacity_new)
    return VariableSite(
        site.name,
        site.capacity_existing + new_capacity,
        site.capacity_new_max - new_capacity,
        site.availability)
end

struct StorageSiteBuild <: ResourceSiteBuild

    params::StorageSite
    power_new::JuMP.VariableRef
    energy_new::JuMP.VariableRef

    function StorageSiteBuild(
        m::JuMP.Model, siteparams::StorageSite,
        techparams::StorageTechnology, regionparams::Region
    )

        fullname = join([regionparams.name, techparams.name, siteparams.name], ",")

        power_new = @variable(m, lower_bound=0, upper_bound=siteparams.power_new_max)
        JuMP.set_name(power_new, "storage_new_power[$fullname]")

        energy_new = @variable(m, lower_bound=0, upper_bound=siteparams.energy_new_max)
        JuMP.set_name(energy_new, "storage_new_energy[$fullname]")

        new(siteparams, power_new, energy_new)

    end

end

sitebuildtype(::Type{StorageTechnology}) = StorageSiteBuild

maxpower(build::StorageSiteBuild) =
    build.params.power_existing + build.power_new

maxenergy(build::StorageSiteBuild) =
    build.params.energy_existing + build.energy_new

function StorageSite(build::StorageSiteBuild)
    site = build.params
    new_power = value(build.power_new)
    new_energy = value(build.energy_new)
    return StorageSite(
        site.name,
        site.power_existing + new_power,
        site.power_new_max - new_power,
        site.energy_existing + new_energy,
        site.energy_new_max - new_energy)
end

struct TechnologyBuild{T<:ResourceTechnology,B<:ResourceSiteBuild}

    params::T
    sites::Vector{B}

    function TechnologyBuild(
        m::JuMP.Model, techparams::T, regionparams::Region
    ) where T <: ResourceTechnology

        B = sitebuildtype(T)

        sites = [B(m, siteparams, techparams, regionparams)
                 for siteparams in techparams.sites]

        new{T,B}(techparams, sites)

    end

end

const ThermalBuild = TechnologyBuild{ThermalTechnology}
const VariableBuild = TechnologyBuild{VariableTechnology}
const GeneratorBuild = TechnologyBuild{<:GeneratorTechnology}
const StorageBuild = TechnologyBuild{StorageTechnology}

availablecapacity(build::ThermalBuild, t::Int) = sum(
        (site.params.units_existing + site.units_new) * build.params.unit_size
        * availability(site.params, t)
        for site in build.sites; init=0)

cost(build::ThermalBuild) =
    sum(site.units_new for site in build.sites; init=0) *
    build.params.unit_size * build.params.cost_capital

function ThermalTechnology(build::ThermalBuild)
    thermaltech = build.params
    return ThermalTechnology(
        thermaltech.name,
        thermaltech.cost_capital, thermaltech.cost_generation,
        thermaltech.unit_size,
        ThermalSite.(build.sites))
end

availablecapacity(build::VariableBuild, t::Int) = sum(
        (site.params.capacity_existing + site.capacity_new)
        * availability(site.params, t)
        for site in build.sites; init=0)

cost(build::VariableBuild) =
    sum(site.capacity_new for site in build.sites; init=0) * build.params.cost_capital

function VariableTechnology(build::VariableBuild)
    variabletech = build.params
    return VariableTechnology(
        variabletech.name,
        variabletech.cost_capital, variabletech.cost_generation,
        VariableSite.(build.sites))
end

maxpower(build::StorageBuild) = sum(
    site.params.power_existing + site.power_new for site in build.sites; init=0)

maxenergy(build::StorageBuild) = sum(
    site.params.energy_existing + site.energy_new for site in build.sites; init=0)

cost(build::StorageBuild) =
    sum(site.power_new for site in build.sites; init=0) * build.params.cost_capital_power +
    sum(site.energy_new for site in build.sites; init=0) * build.params.cost_capital_energy

function StorageTechnology(build::StorageBuild)
    storage = build.params
    return StorageTechnology(
        storage.name,
        storage.cost_capital_power, storage.cost_capital_energy,
        StorageSite.(build.sites))
end

struct RegionBuild

    params::Region

    thermaltechs::Vector{TechnologyBuild{ThermalTechnology}}
    variabletechs::Vector{TechnologyBuild{VariableTechnology}}
    storagetechs::Vector{TechnologyBuild{StorageTechnology}}

    function RegionBuild(m::JuMP.Model, regionparams::Region)

        thermaltechs = [TechnologyBuild(m, techparams, regionparams)
                        for techparams in regionparams.thermaltechs]

        variabletechs = [TechnologyBuild(m, techparams, regionparams)
                        for techparams in regionparams.variabletechs]

        storagetechs = [TechnologyBuild(m, techparams, regionparams)
                        for techparams in regionparams.storagetechs]

        new(regionparams, thermaltechs, variabletechs, storagetechs)

    end

end

cost(build::RegionBuild) =
    sum(cost(thermaltech) for thermaltech in build.thermaltechs; init=0) +
    sum(cost(variabletech) for variabletech in build.variabletechs; init=0) +
    sum(cost(storagetech) for storagetech in build.storagetechs; init=0)

function Region(build::RegionBuild)
    region = build.params
    return Region(
        region.name, region.demand,
        ThermalTechnology.(build.thermaltechs),
        VariableTechnology.(build.variabletechs),
        StorageTechnology.(build.storagetechs),
        region.export_interfaces, region.import_interfaces)
end

struct InterfaceBuild

    params::Interface
    capacity_new::JuMP.VariableRef

    function InterfaceBuild(m::JuMP.Model, params::Interface)

        capacity_new = @variable(m, lower_bound=0,
                                    upper_bound=params.capacity_new_max)
        JuMP.set_name(capacity_new, "iface_capacity_new[$(params.name)]")

        return new(params, capacity_new)

    end

end

cost(build::InterfaceBuild) = build.capacity_new * build.params.cost_capital

function Interface(build::InterfaceBuild)
    iface = build.params
    new_capacity = value(build.capacity_new)
    return Interface(
        iface.name, iface.region_from, iface.region_to, iface.cost_capital,
        iface.capacity_existing + new_capacity,
        iface.capacity_new_max - new_capacity)
end

struct Builds
     regions::Vector{RegionBuild}
     interfaces::Vector{InterfaceBuild}
end

cost(builds::Builds) =
    sum(cost(region) for region in builds.regions; init=0) +
    sum(cost(interface) for interface in builds.interfaces; init=0)
