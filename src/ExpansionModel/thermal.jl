struct ThermalExpansion <: ThermalTechnology

    params::ThermalCandidateParams
    units_new::JuMP.VariableRef

    function ThermalExpansion(
        m::JuMP.Model, techparams::ThermalCandidateParams, regionparams::RegionParams
    )

        fullname = join([regionparams.name, techparams.name], ",")
        units_new = @variable(m, integer=true, lower_bound=0, upper_bound=techparams.max_units)
        JuMP.set_name(units_new, "thermal_new_units[$fullname]")

        new(techparams, units_new)

    end

end

nameplatecapacity(tech::ThermalExpansion) =
        tech.units_new * tech.params.unit_size

availablecapacity(tech::ThermalExpansion, t::Int) =
        tech.units_new * tech.params.unit_size * availability(tech.params, t)

cost(build::ThermalExpansion) =
    build.units_new * build.params.unit_size * build.params.cost_capital

cost_generation(tech::ThermalExpansion) = tech.params.cost_generation

max_ramp(tech::ThermalExpansion) = tech.params.max_ramp * tech.units_new

function ThermalExistingParams(tech::ThermalExpansion)

    new_units = round(Int, value(tech.units_new))
    params = tech.params

    new_site = ThermalExistingSiteParams(
        "",
        new_units,
        params.rating,
        params.λ,
        params.μ)

    return ThermalExistingParams(
        params.name,
        params.category,
        params.cost_generation,
        params.cost_startup,
        params.unit_size,
        params.min_gen,
        params.max_ramp,
        params.min_uptime,
        params.min_downtime,
        [new_site])

end

function ThermalCandidateParams(tech::ThermalExpansion)

    new_units = round(Int, value(tech.units_new))
    params = tech.params

    return ThermalCandidateParams(
        params.name,
        params.category,
        params.cost_generation,
        params.cost_startup,
        params.cost_capital,
        params.max_units - new_units,
        params.unit_size,
        params.min_gen,
        params.max_ramp,
        params.min_uptime,
        params.min_downtime,
        params.rating,
        params.λ,
        params.μ)

end

function warmstart_builds!(build::ThermalExpansion, prev_build::ThermalExpansion)
    JuMP.set_start_value(build.units_new, value(prev_build.units_new))
    return
end
