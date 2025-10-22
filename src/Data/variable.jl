struct VariableExistingSiteParams <: VariableSite

    name::String

    capacity::Float64 # MW
    availability::Vector{Float64}

end

nameplatecapacity(site::VariableExistingSiteParams) = site.capacity
availability(site::VariableExistingSiteParams, t::Int) = site.availability[t]

struct VariableExistingParams <: VariableTechnology

    name::String
    category::String

    cost_generation::Float64 # $/MWh

    sites::Vector{VariableExistingSiteParams}

end

sites(tech::VariableExistingParams) = tech.sites
cost_generation(tech::VariableExistingParams) = tech.cost_generation
name(tech::VariableExistingParams) = tech.name

struct VariableCandidateSiteParams

    name::String

    capacity_max::Float64 # MW
    availability::Vector{Float64}

end

name(site::VariableCandidateSiteParams) = site.name

struct VariableCandidateParams

    name::String
    category::String

    cost_capital::Float64 # annualized $/MW
    cost_generation::Float64 # $/MWh

    sites::Vector{VariableCandidateSiteParams}

end
