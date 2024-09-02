module ExpansionModel

import JuMP
import JuMP: @variable, @constraint, @expression, @objective, value

import MathOptInterface
const MOI = MathOptInterface

import IterTools: zip_longest

using ..Data

include("jump_utils.jl")
include("build.jl")
include("time.jl")
include("representative_periods.jl")
include("eue_estimator.jl")

include("dispatch.jl")
include("dispatch_recurrences.jl")
include("dispatch_economic.jl")
include("dispatch_reliability.jl")

export nullestimator, ExpansionProblem, warmstart_builds!, solve!,
       capex, opex, cost, lcoe,
       TimeProxyAssignment, singleperiod, seasonalperiods, monthlyperiods,
       weeklyperiods, dailyperiods, fullchronologyperiods

mutable struct ExpansionProblem

    model::JuMP.Model

    system::SystemParams

    builds::SystemExpansion

    economicdispatch::EconomicDispatchSequence
    reliabilitydispatch::ReliabilityDispatchSequence

    function ExpansionProblem(
        system::SystemParams,
        economic_periods::TimeProxyAssignment,
        eue_estimator::EUEEstimator,
        eue_max::Vector{Float64},
        optimizer)

        n_timesteps = length(system.timesteps)
        n_regions = length(system.regions)

        timestepcount(economic_periods) == n_timesteps ||
            error("Economic period assignment is incompatible with system timesteps")

        timestepcount(eue_estimator.times) == n_timesteps ||
            error("Reliability period assignment is incompatible with system timesteps")

        length(eue_max) == n_regions ||
            error("Mismatch between EUE constraint count and system regions")

        m = JuMP.Model(optimizer)

        builds = SystemExpansion(
            [RegionExpansion(m, r) for r in system.regions],
            [InterfaceExpansion(m, i) for i in system.interfaces])

        economicdispatch = EconomicDispatchSequence(m, builds, economic_periods)

        reliabilitydispatch = ReliabilityDispatchSequence(
            m, builds, eue_estimator, eue_max)

        opex_scalar = 8766 / n_timesteps
        @objective(m, Min, cost(builds) + opex_scalar * cost(economicdispatch))

        return new(m, system, builds, economicdispatch, reliabilitydispatch)

    end

end

solve!(prob::ExpansionProblem) = JuMP.optimize!(prob.model)

# Capex is annualized, so scale opex to approximate an annual cost
opex(prob::ExpansionProblem) =
    8766 / length(prob.system.timesteps) * cost(prob.economicdispatch)

capex(prob::ExpansionProblem) = cost(prob.builds)
cost(prob::ExpansionProblem) = capex(prob) + opex(prob)

function lcoe(prob::ExpansionProblem)

    # TODO: Need to apply the relevant weightings for this to be accurate!
    total_demand = sum(sum(region.demand) for region in prob.system.regions)

    # Scale demand to an approximate annual value to compare to annualized costs
    demand_scaler = 8766 / length(prob.system.timesteps)

    return cost(prob) /  (demand_scaler * total_demand)
end

SystemParams(prob::ExpansionProblem) = SystemParams(
    prob.system.name, prob.system.timesteps,
    RegionParams.(prob.builds.regions), InterfaceParams.(prob.builds.interfaces)
)

function warmstart_builds!(prob::ExpansionProblem, prev_prob::ExpansionProblem)
    warmstart_builds!.(prob.builds.regions, prev_prob.builds.regions)
    warmstart_builds!.(prob.builds.interfaces, prev_prob.builds.interfaces)
    return
end

end
