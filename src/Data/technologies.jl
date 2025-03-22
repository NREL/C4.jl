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

struct VariableParams <: VariableTechnology

    name::String

    cost_capital::Float64 # annualized $/MW
    cost_generation::Float64 # $/MWh

    sites::Vector{VariableSiteParams}

end

nameplatecapacity(params::VariableParams) =
    sum(site.capacity_existing for site in params.sites; init=0)

availablecapacity(tech::VariableParams, t::Int) =
    sum(availablecapacity(site, t) for site in tech.sites; init=0)

cost_generation(params::VariableParams) = params.cost_generation

const GeneratorParams = Union{ThermalParams,VariableParams}

struct StorageParams <: StorageTechnology{StorageSiteParams}

    name::String

    cost_capital_power::Float64 # annualized $/MW
    cost_operation::Float64 # $/MWh

    roundtrip_efficiency::Float64
    duration::Float64 # hours

    sites::Vector{StorageSiteParams}

end

powerrating(tech::StorageParams) =
    sum(site.power_existing for site in tech.sites; init=0)

energyrating(tech::StorageParams) =
    powerrating(tech) * tech.duration

roundtrip_efficiency(tech::StorageParams) = tech.roundtrip_efficiency

operating_cost(tech::StorageParams) = tech.cost_operation

const TechnologyParams = Union{GeneratorParams,StorageParams}
name(tech::TechnologyParams) = tech.name
