struct CapacityCreditCurveParams

    stepsize::Float64 # powerunits_MW nameplate
    points::Vector{Float64} # powerunits_MW EFC

    function CapacityCreditCurveParams(stepsize::Float64, points::Vector{Float64})
        stepsize > 0 || error("Step size must be positive")

        iszero(first(points)) ||
            error("First point in the EFC curve should be zero")

        d1 = diff(points)
        all(>=(0), d1) || error("Curve values should be non-decreasing")
        all(<=(0), diff(d1)) || error("Curve slopes should be non-increasing")

        return new(stepsize, points)

    end

end

function capacity_credits(
    m::JuMP.Model,
    efc::JuMP.VariableRef,
    build::Union{ExpansionModel.VariableExpansion,
                 ExpansionModel.StorageExpansion},
    cc::CapacityCreditCurveParams
)

    n_segments = length(cc.points)

    cc_nameplate(s::Int) = (s-1) * cc.stepsize

    cc_slope(s::Int) = if s == 1 
        (cc.points[s+1] - cc.points[s]) / cc.stepsize
    elseif s == n_segments
        (cc.points[s] - cc.points[s-1]) / cc.stepsize
    else
        (cc.points[s+1] - cc.points[s-1]) / (2*cc.stepsize)
    end

    efc_constraints = @constraint(m, [s in 1:n_segments],
        efc <= cc.points[s] +
                (new_nameplate(build) - cc_nameplate(s)) * cc_slope(s)
    )

    return efc_constraints

end

struct CapacityCreditCurvesParams <: CapacityCreditParams
    thermaltechs::Vector{Float64}
    variabletechs::Vector{CapacityCreditCurveParams}
    storagetechs::Vector{CapacityCreditCurveParams}
end


struct CapacityCreditCurves <: CapacityCreditFormulation

    variable_efcs::Vector{JuMP.VariableRef} # EFC MW
    variable_curves::Vector{Vector{JuMP_LessThanConstraintRef}}

    storage_efcs::Vector{JuMP.VariableRef} # EFC MW
    storage_curves::Vector{Vector{JuMP_LessThanConstraintRef}}

    prm::JuMP_GreaterThanConstraintRef

end

function capacity_credits(
    m::JuMP.Model, region::ExpansionModel.RegionExpansion,
    capacitycredits::CapacityCreditCurvesParams, build_efc::Float64)

    n_thermaltechs = length(capacitycredits.thermaltechs)

    n_thermaltechs == length(region.thermaltechs) ||
        error("Mismatched number of thermal techs between expansion " *
              "and capacity credit parameters")

    thermal_efc = sum(cc * new_nameplate(tech) for (tech, cc)
        in zip(region.thermaltechs, capacitycredits.thermaltechs))

    n_variabletechs = length(capacitycredits.variabletechs)

    n_variabletechs == length(region.variabletechs) ||
        error("Mismatched number of variable techs between expansion " *
              "and capacity credit parameters")

    variable_efcs = @variable(m, [t in 1:n_variabletechs])

    variable_curves = [capacity_credits(m, efc, tech, curveparams)
        for (efc, tech, curveparams)
        in zip(variable_efcs, region.variabletechs, capacitycredits.variabletechs)
    ]

    n_storagetechs = length(capacitycredits.storagetechs)

    n_storagetechs == length(region.storagetechs) ||
        error("Mismatched number of storage techs between expansion " *
              "and capacity credit parameters")

    storage_efcs = @variable(m, [t in 1:n_storagetechs])

    storage_curves = [capacity_credits(m, efc, tech, curveparams)
        for (efc, tech, curveparams)
        in zip(storage_efcs, region.storagetechs, capacitycredits.storagetechs)
    ]

    prm = @constraint(m,
        thermal_efc + sum(variable_efcs) + sum(storage_efcs) >= build_efc)

    return CapacityCreditCurves(
        variable_efcs, variable_curves,
        storage_efcs, storage_curves, prm)

end
