struct CapacityCreditSurfaceParams{N} <: CapacityCreditParams

    thermaltechs::Vector{Float64}

    variable_stepsize::Vector{Float64} # powerunits_MW nameplate
    storage_stepsize::Vector{Float64} # powerunits_MW nameplate

    points::Array{Float64,N} # powerunits_MW EFC 

    function CapacityCreditSurfaceParams(
        thermaltechs::Vector{Float64},
        variable_stepsize::Vector{Float64},
        storage_stepsize::Vector{Float64},
        points::Array{Float64,N}
    ) where N

        n_variabletechs = length(variable_stepsize)
        n_storagetechs = length(storage_stepsize)
        n_techs = n_variabletechs + n_storagetechs

        n_techs == N ||
            error("Dimension mismatch between variable and storage " *
                  "technologies ($(n_techs)) and capacity credit array ($(N))")

        all(>(0), variable_stepsize) && all(>(0), storage_stepsize) ||
            error("Variable and storage CC curve step sizes must be positive")

        test_valid_ccs(points)

        return new{N}(thermaltechs, variable_stepsize, storage_stepsize, points)

    end

end

# TODO: Automatically create static and 1D curve parametrizations from
#       ND surface data

function capacity_credits(
    m::JuMP.Model,
    efc::JuMP.VariableRef,
    variabletechs::Vector{ExpansionModel.VariableExpansion},
    storagetechs::Vector{ExpansionModel.StorageExpansion},
    capacitycredits::CapacityCreditSurfaceParams{N}) where N

    length(capacitycredits.variable_stepsize) == length(variabletechs) ||
        error("Mismatched number of variable techs between expansion " *
              "and capacity credit parameters")

    length(capacitycredits.storage_stepsize) == length(storagetechs) ||
        error("Mismatched number of storage techs between expansion " *
              "and capacity credit parameters")

    techs = vcat(variabletechs, storagetechs)
    steps = vcat(capacitycredits.variable_stepsize, capacitycredits.storage_stepsize)

    dims = size(capacitycredits.points)
    constraints = Array{JuMP_LessThanConstraintRef,N}(undef, dims)
    gradient = Vector{Float64}(undef, N)
    reference_capacity = Vector{Float64}(undef, N)

    for I in CartesianIndices(capacitycredits.points)

        point_efc = capacitycredits.points[I] / powerunits_MW
        idx = Tuple(I)

        # Calculate gradient @ I. Would be nice to just provide a gradient
        # dataset so that it could be calculated independently, potentially
        # using a better method (e.g. marginals via MRI?).
        # For now we just approximate the gradients from EFC differences
        for (dim, i) in enumerate(idx)

            basestep = steps[dim] / powerunits_MW
            step = 0

            delta = Tuple(x==dim ? 1 : 0 for x in 1:N)

            prev_efc = if i > 1
                step += basestep
                capacitycredits.points[(idx .- delta)...] / powerunits_MW
            else
                point_efc
            end

            next_efc = if i < dims[dim]
                step += basestep
                capacitycredits.points[(idx .+ delta)...] / powerunits_MW
            else
                point_efc
            end

            gradient[dim] = (next_efc - prev_efc) / step
            reference_capacity[dim] = basestep * (i-1)

        end

        constraints[I] = @constraint(m,
            efc <= point_efc + sum(
                (new_nameplate(techs[i]) - reference_capacity[i]) * gradient[i]
                for i in 1:N))

    end

    return constraints

end

struct CapacityCreditSurface{N} <: CapacityCreditFormulation

    thermal_efc::JuMP_ExpressionRef # EFC MW

    variable_storage_efc::JuMP.VariableRef # EFC MW
    efc_constraints::Array{JuMP_LessThanConstraintRef,N}

    prm::JuMP_GreaterThanConstraintRef

end

function capacity_credits(
    m::JuMP.Model, region::ExpansionModel.RegionExpansion,
    capacitycredits::CapacityCreditSurfaceParams{N}, build_efc::Float64
) where N

    # TODO: Should CapacityCreditSurfaceParams store the no-build
    #       system EFC and offset build_efc?

    n_thermaltechs = length(capacitycredits.thermaltechs)

    n_thermaltechs == length(region.thermaltechs) ||
        error("Mismatched number of thermal techs between expansion " *
              "and capacity credit parameters")

    thermal_efc = sum(cc * new_nameplate(tech) for (tech, cc)
        in zip(region.thermaltechs, capacitycredits.thermaltechs))

    # variable_storage_efc = @variable(m, variable_storage_efc)
    variable_storage_efc = @variable(m, variable_storage_efc, lower_bound=0)

    efc_surface = capacity_credits(
        m, variable_storage_efc,
        region.variabletechs, region.storagetechs,
        capacitycredits)

    prm = @constraint(m, reserve_margin_requirement,
        thermal_efc + variable_storage_efc >= build_efc / powerunits_MW)

    return CapacityCreditSurface{N}(
        thermal_efc, variable_storage_efc, efc_surface, prm)

end

const geq0 = >=(0)
const leq0 = <=(0)

"""
Check that the surface provided is non-negative, non-decreasing, and concave
"""
function test_valid_ccs(x::Array{Float64,N}) where N

    all(geq0, x) || error("Capacity credits must be non-negative")

    for i in 1:N

        dx = diff(x, dims=i)
        all(geq0, dx) || error(
            "Capacity credits must be non-decreasing, " *
            "but the provided values decrease in dimension $i")

        for j in 1:N
            all(leq0, diff(dx, dims=j)) || error(
                "The capacity credit surface must be concave " *
                "(have non-increasing returns), " *
                "but the second derivative with respect to dimensions " *
                "$i and $j is positive")
        end

    end

end
