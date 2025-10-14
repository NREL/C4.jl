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

const SiteParams = Union{
    ThermalSiteParams,VariableExistingSiteParams,VariableCandidateSiteParams,
    StorageExistingSiteParams
}

name(site::SiteParams) = site.name
