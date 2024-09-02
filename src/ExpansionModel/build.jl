abstract type SiteExpansion end

struct ThermalSiteExpansion <: SiteExpansion

    params::ThermalSiteParams
    units_new::JuMP.VariableRef

    function ThermalSiteExpansion(
        m::JuMP.Model, siteparams::ThermalSiteParams,
        techparams::ThermalParams, regionparams::RegionParams
    )

        fullname = join([regionparams.name, techparams.name, siteparams.name], ",")
        units_new = @variable(m, integer=true, lower_bound=0, upper_bound=siteparams.units_new_max)
        JuMP.set_name(units_new, "thermal_new_units[$fullname]")
        new(siteparams, units_new)

    end

end

sitebuildtype(::Type{ThermalParams}) = ThermalSiteExpansion

function ThermalSiteParams(build::ThermalSiteExpansion)
    site = build.params
    new_units = round(Int, value(build.units_new))
    return ThermalSiteParams(
        site.name,
        site.units_existing + new_units,
        site.units_new_max - new_units,
        site.λ, site.μ)
end

function warmstart_builds!(build::ThermalSiteExpansion, prev_build::ThermalSiteExpansion)
    JuMP.set_start_value(build.units_new, value(prev_build.units_new))
    return
end

struct VariableSiteExpansion <: SiteExpansion

    params::VariableSiteParams
    capacity_new::JuMP.VariableRef

    function VariableSiteExpansion(
        m::JuMP.Model, siteparams::VariableSiteParams,
        techparams::VariableParams, regionparams::RegionParams
    )

        fullname = join([regionparams.name, techparams.name, siteparams.name], ",")
        capacity_new = @variable(m, lower_bound=0, upper_bound=siteparams.capacity_new_max)
        JuMP.set_name(capacity_new, "variable_new_capacity[$fullname]")
        new(siteparams, capacity_new)

    end

end

sitebuildtype(::Type{VariableParams}) = VariableSiteExpansion

function VariableSiteParams(build::VariableSiteExpansion)
    site = build.params
    new_capacity = value(build.capacity_new)
    return VariableSiteParams(
        site.name,
        site.capacity_existing + new_capacity,
        site.capacity_new_max - new_capacity,
        site.availability)
end

function warmstart_builds!(build::VariableSiteExpansion, prev_build::VariableSiteExpansion)
    JuMP.set_start_value(build.capacity_new, value(prev_build.capacity_new))
    return
end

struct StorageSiteExpansion <: SiteExpansion

    params::StorageSiteParams
    power_new::JuMP.VariableRef
    energy_new::JuMP.VariableRef

    function StorageSiteExpansion(
        m::JuMP.Model, siteparams::StorageSiteParams,
        techparams::StorageParams, regionparams::RegionParams
    )

        fullname = join([regionparams.name, techparams.name, siteparams.name], ",")

        power_new = @variable(m, lower_bound=0, upper_bound=siteparams.power_new_max)
        JuMP.set_name(power_new, "storage_new_power[$fullname]")

        energy_new = @variable(m, lower_bound=0, upper_bound=siteparams.energy_new_max)
        JuMP.set_name(energy_new, "storage_new_energy[$fullname]")

        new(siteparams, power_new, energy_new)

    end

end

sitebuildtype(::Type{StorageParams}) = StorageSiteExpansion

maxpower(build::StorageSiteExpansion) =
    build.params.power_existing + build.power_new

maxenergy(build::StorageSiteExpansion) =
    build.params.energy_existing + build.energy_new

function StorageSiteParams(build::StorageSiteExpansion)
    site = build.params
    new_power = value(build.power_new)
    new_energy = value(build.energy_new)
    return StorageSiteParams(
        site.name,
        site.power_existing + new_power,
        site.power_new_max - new_power,
        site.energy_existing + new_energy,
        site.energy_new_max - new_energy)
end

function warmstart_builds!(build::StorageSiteExpansion, prev_build::StorageSiteExpansion)
    JuMP.set_start_value(build.power_new, value(prev_build.power_new))
    JuMP.set_start_value(build.energy_new, value(prev_build.energy_new))
    return
end

struct TechnologyExpansion{T<:TechnologyParams,B<:SiteExpansion}

    params::T
    sites::Vector{B}

    function TechnologyExpansion(
        m::JuMP.Model, techparams::T, regionparams::RegionParams
    ) where T <: TechnologyParams

        B = sitebuildtype(T)

        sites = [B(m, siteparams, techparams, regionparams)
                 for siteparams in techparams.sites]

        new{T,B}(techparams, sites)

    end

end

function warmstart_builds!(build::T, prev_build::T) where {T <: TechnologyExpansion}
    warmstart_builds!.(build.sites, prev_build.sites)
    return
end

const ThermalExpansion = TechnologyExpansion{ThermalParams,ThermalSiteExpansion}
const VariableExpansion = TechnologyExpansion{VariableParams,VariableSiteExpansion}
const GeneratorExpansion = Union{ThermalExpansion,VariableExpansion}
const StorageExpansion = TechnologyExpansion{StorageParams,StorageSiteExpansion}

nameplatecapacity(build::ThermalExpansion) = sum(
        (site.params.units_existing + site.units_new) * build.params.unit_size
        for site in build.sites; init=0)

availablecapacity(build::ThermalExpansion, t::Int) = sum(
        (site.params.units_existing + site.units_new) * build.params.unit_size
        * availability(site.params, t)
        for site in build.sites; init=0)

cost(build::ThermalExpansion) =
    sum(site.units_new for site in build.sites; init=0) *
    build.params.unit_size * build.params.cost_capital

function ThermalParams(build::ThermalExpansion)
    thermaltech = build.params
    return ThermalParams(
        thermaltech.name,
        thermaltech.cost_capital, thermaltech.cost_generation,
        thermaltech.unit_size,
        ThermalSiteParams.(build.sites))
end

nameplatecapacity(build::VariableExpansion) = sum(
        (site.params.capacity_existing + site.capacity_new)
        for site in build.sites; init=0)

availablecapacity(build::VariableExpansion, t::Int) = sum(
        (site.params.capacity_existing + site.capacity_new)
        * availability(site.params, t)
        for site in build.sites; init=0)

cost(build::VariableExpansion) =
    sum(site.capacity_new for site in build.sites; init=0) * build.params.cost_capital

function VariableParams(build::VariableExpansion)
    variabletech = build.params
    return VariableParams(
        variabletech.name,
        variabletech.cost_capital, variabletech.cost_generation,
        VariableSiteParams.(build.sites))
end

maxpower(build::StorageExpansion) = sum(
    site.params.power_existing + site.power_new for site in build.sites; init=0)

maxenergy(build::StorageExpansion) = sum(
    site.params.energy_existing + site.energy_new for site in build.sites; init=0)

cost(build::StorageExpansion) =
    sum(site.power_new for site in build.sites; init=0) * build.params.cost_capital_power +
    sum(site.energy_new for site in build.sites; init=0) * build.params.cost_capital_energy

function StorageParams(build::StorageExpansion)
    storage = build.params
    return StorageParams(
        storage.name,
        storage.cost_capital_power, storage.cost_capital_energy,
        StorageSiteParams.(build.sites))
end

struct RegionExpansion

    params::RegionParams

    thermaltechs::Vector{ThermalExpansion}
    variabletechs::Vector{VariableExpansion}
    storagetechs::Vector{StorageExpansion}

    function RegionExpansion(m::JuMP.Model, regionparams::RegionParams)

        thermaltechs = [TechnologyExpansion(m, techparams, regionparams)
                        for techparams in regionparams.thermaltechs]

        variabletechs = [TechnologyExpansion(m, techparams, regionparams)
                        for techparams in regionparams.variabletechs]

        storagetechs = [TechnologyExpansion(m, techparams, regionparams)
                        for techparams in regionparams.storagetechs]

        new(regionparams, thermaltechs, variabletechs, storagetechs)

    end

end

cost(build::RegionExpansion) =
    sum(cost(thermaltech) for thermaltech in build.thermaltechs; init=0) +
    sum(cost(variabletech) for variabletech in build.variabletechs; init=0) +
    sum(cost(storagetech) for storagetech in build.storagetechs; init=0)

function RegionParams(build::RegionExpansion)
    region = build.params
    return RegionParams(
        region.name, region.demand,
        ThermalParams.(build.thermaltechs),
        VariableParams.(build.variabletechs),
        StorageParams.(build.storagetechs),
        region.export_interfaces, region.import_interfaces)
end

function warmstart_builds!(build::RegionExpansion, prev_build::RegionExpansion)
    warmstart_builds!.(build.thermaltechs, prev_build.thermaltechs)
    warmstart_builds!.(build.variabletechs, prev_build.variabletechs)
    warmstart_builds!.(build.storagetechs, prev_build.storagetechs)
    return
end

struct InterfaceExpansion

    params::InterfaceParams
    capacity_new::JuMP.VariableRef

    function InterfaceExpansion(m::JuMP.Model, params::InterfaceParams)

        capacity_new = @variable(m, lower_bound=0,
                                    upper_bound=params.capacity_new_max)
        JuMP.set_name(capacity_new, "iface_capacity_new[$(params.name)]")

        return new(params, capacity_new)

    end

end

cost(build::InterfaceExpansion) = build.capacity_new * build.params.cost_capital

function InterfaceParams(build::InterfaceExpansion)
    iface = build.params
    new_capacity = value(build.capacity_new)
    return InterfaceParams(
        iface.name, iface.region_from, iface.region_to, iface.cost_capital,
        iface.capacity_existing + new_capacity,
        iface.capacity_new_max - new_capacity)
end

function warmstart_builds!(build::InterfaceExpansion, prev_build::InterfaceExpansion)
    JuMP.set_start_value(build.capacity_new, value(prev_build.capacity_new))
    return
end

struct SystemExpansion
     regions::Vector{RegionExpansion}
     interfaces::Vector{InterfaceExpansion}
end

cost(builds::SystemExpansion) =
    sum(cost(region) for region in builds.regions; init=0) +
    sum(cost(interface) for interface in builds.interfaces; init=0)
