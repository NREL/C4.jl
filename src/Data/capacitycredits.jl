abstract type CapacityCreditParams end

const geq0 = >=(0)
const leq0 = <=(0)

struct CapacityCreditSurfaceParams{N} <: CapacityCreditParams

    thermaltechs::Vector{Float64}

    variable_stepsize::Vector{Float64} # powerunits_MW nameplate
    storage_stepsize::Vector{Float64} # powerunits_MW nameplate

    points::Array{Float64,N} # powerunits_MW EFC 

    function CapacityCreditSurfaceParams(
        thermaltechs::Vector{Float64},
        variable_stepsize::Vector{Float64},
        storage_stepsize::Vector{Float64},
        points::Array{Float64,N};
        check_concavity::Bool=true
    ) where N

        n_variabletechs = length(variable_stepsize)
        n_storagetechs = length(storage_stepsize)
        n_techs = n_variabletechs + n_storagetechs

        n_techs == N ||
            error("Dimension mismatch between variable and storage " *
                  "technologies ($(n_techs)) and capacity credit array ($(N))")

        all(>(0), variable_stepsize) && all(>(0), storage_stepsize) ||
            error("Variable and storage CC curve step sizes must be positive")

        if check_concavity
            test_valid_ccs(points)
        end

        return new{N}(thermaltechs, variable_stepsize, storage_stepsize, points)

    end

end

function CapacityCreditSurfaceParams(
    sys::SystemParams, datapath::String;
    check_concavity::Bool=true
)

    thermal_efcs = load_lookup(joinpath(datapath, "thermal.csv"))
    thermaltechs = [thermal_efcs[tech.name]
                    for tech in sys.regions[1].thermaltechs]

    variable_stepsizes = load_lookup(joinpath(datapath, "variable.csv"))
    variable_stepsize = [variable_stepsizes[tech.name]
                         for tech in sys.regions[1].variabletechs]

    storage_stepsizes = load_lookup(joinpath(datapath, "storage.csv"))
    storage_stepsize = [storage_stepsizes[tech.name]
                         for tech in sys.regions[1].storagetechs]

    technames = vcat(
        [tech.name for tech in sys.regions[1].variabletechs],
        [tech.name for tech in sys.regions[1].storagetechs])

    data = readdlm(joinpath(datapath, "surface.csv"), ',')

    tech_idxs = indexin(technames, data[1, 1:end-1])
    all(!isnothing, tech_idxs) ||
        error("EFC surface data does not contain all variable and storage technologies")

    idxs = data[2:end, tech_idxs]

    techsteps = vec(maximum(idxs, dims=1)) .+ 1
    points = fill(NaN, techsteps...)

    efcs = Dict(Tuple.(eachrow(idxs)) .=> data[2:end, end])
    display(efcs)

    for I in CartesianIndices(points)
        points[I] = efcs[Tuple(I) .- 1]
    end

    return CapacityCreditSurfaceParams(
                thermaltechs, variable_stepsize, storage_stepsize, points,
                check_concavity=check_concavity)

end

function load_lookup(path::String)
    data = readdlm(path, ',')
    return Dict(data[i,1] => Float64(data[i,2]) for i in 2:size(data,1))
end

struct CapacityCreditCurveParams

    stepsize::Float64 # MW nameplate
    points::Vector{Float64} # MW EFC

    function CapacityCreditCurveParams(stepsize::Float64, points::Vector{Float64}; check_concavity::Bool=true)

        stepsize > 0 || error("Step size must be positive")

        iszero(first(points)) ||
            error("First point in the EFC curve should be zero")

        all(>=(0), points) || error("Curve values should be non-negative")

        if check_concavity

            d1 = diff(points)
            all(geq0, d1) || error("Curve values should be non-decreasing")
            all(leq0, diff(d1)) || error("Curve slopes should be non-increasing")

        end

        return new(stepsize, points)

    end

end

struct CapacityCreditCurvesParams <: CapacityCreditParams
    thermaltechs::Vector{Float64}
    variabletechs::Vector{CapacityCreditCurveParams}
    storagetechs::Vector{CapacityCreditCurveParams}
end

function ccs_static(
    nd_surface::CapacityCreditSurfaceParams;
    check_concavity::Bool=true)

    n_variabletechs = length(nd_surface.variable_stepsize)
    n_storagetechs = length(nd_surface.storage_stepsize)
    n_techs = n_variabletechs + n_storagetechs

    variabletechs = Vector{CapacityCreditCurveParams}(undef, n_variabletechs)

    for (dim, stepsize) in enumerate(nd_surface.variable_stepsize)

        idx = Tuple(x == dim ? (1:min(2, size(nd_surface.points, dim))) : 1
                    for x in 1:n_techs)

        variabletechs[dim] = CapacityCreditCurveParams(
            stepsize, nd_surface.points[idx...],
            check_concavity=check_concavity)

    end

    storagetechs = Vector{CapacityCreditCurveParams}(undef, n_storagetechs)

    for (i, stepsize) in enumerate(nd_surface.storage_stepsize)

        dim = n_variabletechs + i

        idx = Tuple(x == dim ? (1:min(2, size(nd_surface.points, dim))) : 1
                    for x in 1:n_techs)

        storagetechs[i] = CapacityCreditCurveParams(
            stepsize, nd_surface.points[idx...],
            check_concavity=check_concavity)

    end

    return CapacityCreditCurvesParams(
        nd_surface.thermaltechs, variabletechs, storagetechs)

end

function ccs_1d(
    nd_surface::CapacityCreditSurfaceParams;
    check_concavity::Bool=true)

    n_variabletechs = length(nd_surface.variable_stepsize)
    n_storagetechs = length(nd_surface.storage_stepsize)
    n_techs = n_variabletechs + n_storagetechs

    variabletechs = Vector{CapacityCreditCurveParams}(undef, n_variabletechs)

    for (dim, stepsize) in enumerate(nd_surface.variable_stepsize)

        idx = Tuple(x == dim ? (:) : 1 for x in 1:n_techs)

        variabletechs[dim] = CapacityCreditCurveParams(
            stepsize, nd_surface.points[idx...],
            check_concavity=check_concavity)

    end

    storagetechs = Vector{CapacityCreditCurveParams}(undef, n_storagetechs)

    for (i, stepsize) in enumerate(nd_surface.storage_stepsize)

        dim = n_variabletechs + i

        idx = Tuple(x == dim ? (:) : 1 for x in 1:n_techs)

        storagetechs[i] = CapacityCreditCurveParams(
            stepsize, nd_surface.points[idx...],
            check_concavity=check_concavity)

    end

    return CapacityCreditCurvesParams(
        nd_surface.thermaltechs, variabletechs, storagetechs)

end

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
