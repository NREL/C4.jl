struct ThermalParams <: ThermalTechnology

    name::String

    cost_capital::Float64 # annualized $/MW
    cost_generation::Float64 # $/MWh

    unit_size::Float64 # MW/unit

    sites::Vector{ThermalSiteParams}

end

num_units(tech::ThermalParams) =
    sum(site.units_existing for site in tech.sites; init=0)

availableunits(tech::ThermalParams, t::Int) =
    sum(availableunits(site, t) for site in tech.sites; init=0)

nameplatecapacity(tech::ThermalParams) =
    num_units(tech) * tech.unit_size

availablecapacity(tech::ThermalParams, t::Int) =
    availableunits(tech, t) * tech.unit_size

cost_generation(params::ThermalParams) = params.cost_generation

const TechnologyParams = Union{
    ThermalParams,
    VariableExistingParams, VariableCandidateParams,
    StorageExistingParams, StorageCandidateParams
}

name(tech::TechnologyParams) = tech.name
