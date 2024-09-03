struct ThermalSiteParams <: ThermalSite

    name::String

    units_existing::Int
    units_new_max::Int

    λ::Vector{Float64}
    μ::Vector{Float64}

end

availability(site::ThermalSiteParams, t::Int) =
    site.μ[t] / (site.λ[t] + site.μ[t])

struct VariableSiteParams <: VariableSite

    name::String

    capacity_existing::Float64
    capacity_new_max::Float64

    availability::Vector{Float64}

end

availability(site::VariableSiteParams, t::Int) = site.availability[t]

struct StorageSiteParams <: StorageSite

    name::String

    power_existing::Float64
    power_new_max::Float64

    energy_existing::Float64
    energy_new_max::Float64

end
