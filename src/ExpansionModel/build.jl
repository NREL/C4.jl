struct ThermalSiteExpansion <: ThermalSite

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

function ThermalSiteParams(build::ThermalSiteExpansion)
    site = build.params
    new_units = round(Int, value(build.units_new))
    return ThermalSiteParams(
        site.name,
        site.units_existing + new_units,
        site.units_new_max - new_units,
        site.rating, site.λ, site.μ)
end

function warmstart_builds!(build::ThermalSiteExpansion, prev_build::ThermalSiteExpansion)
    JuMP.set_start_value(build.units_new, value(prev_build.units_new))
    return
end

const SiteExpansion = Union{ThermalSiteExpansion,VariableSiteExpansion}
name(site::SiteExpansion) = name(site.params)

struct ThermalExpansion <: ThermalTechnology

    params::ThermalParams
    sites::Vector{ThermalSiteExpansion}

    function ThermalExpansion(
        m::JuMP.Model, techparams::ThermalParams, regionparams::RegionParams
    )

        sites = [ThermalSiteExpansion(m, siteparams, techparams, regionparams)
                 for siteparams in techparams.sites]

        new(techparams, sites)

    end

end

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

cost_generation(tech::ThermalExpansion) = cost_generation(tech.params)

function ThermalParams(build::ThermalExpansion)
    thermaltech = build.params
    return ThermalParams(
        thermaltech.name,
        thermaltech.cost_capital, thermaltech.cost_generation,
        thermaltech.unit_size,
        ThermalSiteParams.(build.sites))
end

const TechnologyExpansion = Union{
    ThermalExpansion,VariableExpansion,StorageExpansion
}
name(tech::TechnologyExpansion) = name(tech.params)

function warmstart_builds!(
    build::T, prev_build::T
) where {T <: TechnologyExpansion}
    warmstart_builds!.(build.sites, prev_build.sites)
    return
end

struct InterfaceExpansion <: Interface

    params::InterfaceParams
    capacity_new::JuMP.VariableRef

    function InterfaceExpansion(m::JuMP.Model, params::InterfaceParams)

        capacity_new = @variable(m, lower_bound=0,
                                    upper_bound=params.capacity_new_max)
        JuMP.set_name(capacity_new, "iface_capacity_new[$(params.name)]")

        return new(params, capacity_new)

    end

end

name(iface::InterfaceExpansion) = name(iface.params)
availablecapacity(iface::InterfaceExpansion) = availablecapacity(iface.params) + iface.capacity_new
cost(build::InterfaceExpansion) = build.capacity_new * build.params.cost_capital

region_from(iface::InterfaceExpansion) = region_from(iface.params)
region_to(iface::InterfaceExpansion) = region_to(iface.params)

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

struct RegionExpansion <: Region{ThermalExpansion, InterfaceExpansion}

    params::RegionParams

    thermaltechs::Vector{ThermalExpansion}
    variabletechs::Vector{VariableExpansion}
    storagetechs::Vector{StorageExpansion}

    function RegionExpansion(m::JuMP.Model, regionparams::RegionParams)

        thermaltechs = [ThermalExpansion(m, techparams, regionparams)
                        for techparams in regionparams.thermaltechs]

        variabletechs = [VariableExpansion(m, techparams, regionparams)
                        for techparams in regionparams.variabletechs_candidate]

        storagetechs = [StorageExpansion(m, techparams, regionparams)
                        for techparams in regionparams.storagetechs_candidate]

        new(regionparams, thermaltechs, variabletechs, storagetechs)

    end

end

name(region::RegionExpansion) = region.params.name
demand(region::RegionExpansion, t::Int) = demand(region.params, t)

importinginterfaces(region::RegionExpansion) = importinginterfaces(region.params)
exportinginterfaces(region::RegionExpansion) = exportinginterfaces(region.params)

cost(build::RegionExpansion) =
    sum(cost(thermaltech) for thermaltech in build.thermaltechs; init=0) +
    sum(cost(variabletech) for variabletech in build.variabletechs; init=0) +
    sum(cost(storagetech) for storagetech in build.storagetechs; init=0)

variabletechs(region::RegionExpansion) =
    [region.variabletechs; region.params.variabletechs_existing]

storagetechs(region::RegionExpansion) =
    [region.storagetechs; region.params.storagetechs_existing]

function RegionParams(build::RegionExpansion)

    region = build.params

    variable_existing = vcat(
            region.variabletechs_existing,
            [VariableExistingParams(tech)
             for tech in build.variabletechs
             if value(nameplatecapacity(tech)) > 0])

    storage_existing = vcat(
            region.storagetechs_existing,
            [StorageExistingParams(tech)
             for tech in build.storagetechs
             if value(maxpower(tech)) > 0])

    return RegionParams(
        region.name, region.demand,
        ThermalParams.(build.thermaltechs),
        variable_existing,
        VariableCandidateParams.(build.variabletechs),
        storage_existing,
        StorageCandidateParams.(build.storagetechs),
        region.export_interfaces, region.import_interfaces)
end

function warmstart_builds!(build::RegionExpansion, prev_build::RegionExpansion)
    warmstart_builds!.(build.thermaltechs, prev_build.thermaltechs)
    warmstart_builds!.(build.variabletechs, prev_build.variabletechs)
    warmstart_builds!.(build.storagetechs, prev_build.storagetechs)
    return
end

struct SystemExpansion <: System{RegionExpansion, InterfaceExpansion}
     regions::Vector{RegionExpansion}
     interfaces::Vector{InterfaceExpansion}
end

cost(builds::SystemExpansion) =
    sum(cost(region) for region in builds.regions; init=0) +
    sum(cost(interface) for interface in builds.interfaces; init=0)
