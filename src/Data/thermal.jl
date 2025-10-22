struct ThermalExistingSiteParams

    name::String

    units::Int
    unit_size::Float64 # MW/unit

    rating::Vector{Float64}

    λ::Vector{Float64}
    μ::Vector{Float64}

end

nameplatecapacity(site::ThermalExistingSiteParams) =
    site.units * site.unit_size

availability(site::ThermalExistingSiteParams, t::Int) =
    site.rating[t] * site.μ[t] / (site.λ[t] + site.μ[t])

availablecapacity(site::ThermalExistingSiteParams, t::Int) =
    nameplatecapacity(site) * availability(site, t)

struct ThermalExistingParams <: ThermalTechnology

    name::String
    category::String

    cost_generation::Float64 # $/MWh

    sites::Vector{ThermalExistingSiteParams}

end

nameplatecapacity(tech::ThermalExistingParams) =
    sum(nameplatecapacity(site) for site in tech.sites; init=0)

availablecapacity(tech::ThermalExistingParams, t::Int) =
    sum(availablecapacity(site, t) for site in tech.sites; init=0)

cost_generation(tech::ThermalExistingParams) = tech.cost_generation

struct ThermalCandidateParams

    name::String
    category::String

    cost_generation::Float64 # $/MWh
    cost_capital::Float64 # annualized $/MW

    max_units::Int
    unit_size::Float64 # MW/unit

    rating::Vector{Float64}

    λ::Vector{Float64}
    μ::Vector{Float64}

end

availability(params::ThermalCandidateParams, t::Int) =
    params.rating[t] * params.μ[t] / (params.λ[t] + params.μ[t])
