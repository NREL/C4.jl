struct ThermalSiteRiskEstimateParams
    units::Int
    dEUE::Float64
end

function eue_adjustment(
    build::ThermalSiteExpansion,
    riskparams::ThermalSiteRiskEstimateParams)

    # Don't add terms where expansion isn't possible
    iszero(build.params.units_new_max) && return 0

    units = build.params.units_existing + build.units_new
    return -riskparams.dEUE * (units - riskparams.units)

end

struct ThermalTechRiskEstimateParams
    sites::Vector{ThermalSiteRiskEstimateParams}
end

function eue_adjustment(
    builds::ThermalExpansion,
    riskparams::ThermalTechRiskEstimateParams)

    return sum(eue_adjustment(sitebuild, siteriskparams)
               for (sitebuild, siteriskparams)
               in zip(builds.sites, riskparams.sites))

end

struct RiskEstimatePlaneParams

    base_eue::Float64

    # (conditionally) Deterministic Capacity:
    # (Available Variable Gen + Storage Discharge - Storage Charge
    #  + Imports - Exports - Demand)
    nonthermal_available::Float64

    # EUE change associated with adding (conditionally) deterministic capacity
    nonthermal_dEUE::Float64

    thermaltechs::Vector{ThermalTechRiskEstimateParams} # per tech

end

function eue_estimate(
    nonthermal_available::JuMP_ExpressionRef,
    thermaltechs::Vector{ThermalExpansion},
    riskparams::RiskEstimatePlaneParams)

    thermal_adjustment = sum(eue_adjustment(techbuilds, techriskparams)
        for (techbuilds, techriskparams)
        in zip(thermaltechs, riskparams.thermaltechs); init=0)

    nonthermal_adjustment = -riskparams.nonthermal_dEUE *
        (nonthermal_available - riskparams.nonthermal_available)

    return riskparams.base_eue + thermal_adjustment + nonthermal_adjustment

end

const RiskEstimatePeriodParams = Array{RiskEstimatePlaneParams,3} # RxTxJ

struct RiskEstimateParams

    times::TimeProxyAssignment
    periods::Vector{RiskEstimatePeriodParams}

    function RiskEstimateParams(
        times::TimeProxyAssignment, estimators::Vector{RiskEstimatePeriodParams}
    )

        length(times.periods) == length(estimators) ||
            error("Mismatched count of dispatch periods and EUE estimators")

        new(times, estimators)

    end

end

# TODO: Could implement iterator interface here for slightly nicer usage
allperiods(riskparams::RiskEstimateParams) =
    [(period, riskparams.periods[i])
     for (i, period) in enumerate(riskparams.times.periods)]

function nullestimator(times::TimeProxyAssignment, n_regions::Int)

    n_periods = length(times.periods)
    n_timesteps = times.daylength

    nullperiod = Array{RiskEstimatePlaneParams,3}(undef, n_regions, n_timesteps, 0)

    return RiskEstimateParams(times, fill(nullperiod, n_periods))

end

struct ReliabilityEstimate

    period::TimePeriod

    eue::Matrix{JuMP.VariableRef}
    eue_planes::Array{JuMP_GreaterThanConstraintRef,3}

    function ReliabilityEstimate(
        m::JuMP.Model, system::System,
        dispatch::ReliabilityDispatch,
        riskparams::RiskEstimatePeriodParams)

        R, T, J = size(riskparams)
        period_name = dispatch.period.name

        eue = @variable(m, [1:R, 1:T], lower_bound = 0)
        varnames!(eue, "eue[$(period_name)]", name.(system.regions), 1:T)

        eue_planes = @constraint(m, [r in 1:R, t in 1:T, j in 1:J],
            eue[r,t] >= eue_estimate(
                dispatch.nonthermal_available[r,t],
                system.regions[r].thermaltechs,
                riskparams[r,t,j])
        )

        new(dispatch.period, eue, eue_planes)

    end

end

struct ReliabilityConstraints

    estimates::Vector{ReliabilityEstimate}

    region_eue::Vector{JuMP_ExpressionRef}
    region_eue_max::Vector{JuMP_LessThanConstraintRef}

    function ReliabilityConstraints(
        m::JuMP.Model, system::System, dispatches::Vector{<:ReliabilityDispatch},
        riskparams::RiskEstimateParams, eue_max::Vector{Float64})

        n_regions = length(system.regions)

        eue_estimates = [
            ReliabilityEstimate(m, system, dispatch, periodriskparams)
            for (dispatch, periodriskparams)
            in zip(dispatches, riskparams.periods)]

        region_eue = @expression(m, [r in 1:n_regions],
            sum(sum(estimate.eue[r, :]) for estimate in eue_estimates))

        region_eue_max = @constraint(m, [r in 1:n_regions],
            region_eue[r] <= eue_max[r])

        new(eue_estimates, region_eue, region_eue_max)

    end

end
