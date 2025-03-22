struct ThermalSiteParams <: ThermalSite

    name::String

    units_existing::Int
    units_new_max::Int

    rating::Vector{Float64}

    λ::Vector{Float64}
    μ::Vector{Float64}

end

availability(site::ThermalSiteParams, t::Int) =
    site.rating[t] * site.μ[t] / (site.λ[t] + site.μ[t])

availableunits(site::ThermalSiteParams, t::Int) =
    availability(site, t) * site.units_existing

struct VariableSiteParams <: VariableSite

    name::String

    capacity_existing::Float64
    capacity_new_max::Float64

    availability::Vector{Float64}

end

availability(site::VariableSiteParams, t::Int) = site.availability[t]

availablecapacity(site::VariableSiteParams, t::Int) =
    site.availability[t] * site.capacity_existing

const GeneratorSiteParams = Union{ThermalSiteParams,VariableSiteParams}

struct StorageSiteParams <: StorageSite

    name::String

    power_existing::Float64
    power_new_max::Float64

    # The asymmetry with other resource types isn't great,
    # nor is the abstract typing (needed because StorageParams
    # isn't defined yet and has a circular dependency with this type),
    # but it's good enough for this ephemeral branch
    tech::StorageTechnology{StorageSiteParams}

end

maxpower(site::StorageSiteParams) = site.power_existing
maxenergy(site::StorageSiteParams) = maxpower(site) * site.tech.duration

const SiteParams = Union{GeneratorSiteParams,StorageSiteParams}
name(site::SiteParams) = site.name
