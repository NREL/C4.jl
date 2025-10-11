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

struct StorageSiteParams <: StorageSite

    name::String

    power_existing::Float64
    power_new_max::Float64

    energy_existing::Float64
    energy_new_max::Float64

end

maxpower(site::StorageSiteParams) = site.power_existing
maxenergy(site::StorageSiteParams) = site.energy_existing

const SiteParams = Union{
    ThermalSiteParams,VariableExistingSiteParams,VariableCandidateSiteParams,
    StorageSiteParams
}

name(site::SiteParams) = site.name
