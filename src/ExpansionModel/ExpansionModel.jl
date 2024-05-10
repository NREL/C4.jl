module ExpansionModel

import JuMP
import JuMP: @variable, @constraint, @expression, @objective, optimize!

import MathOptInterface
const MOI = MathOptInterface

import IterTools: zip_longest

using ..Data

include("jump_utils.jl")
include("build.jl")
include("time.jl")
include("eue_estimator.jl")

include("dispatch.jl")
include("dispatch_recurrences.jl")
include("dispatch_economic.jl")
include("dispatch_reliability.jl")

export fullchronology, nullestimator, ExpansionProblem, solve!

mutable struct ExpansionProblem

    model::JuMP.Model

    system::System

    builds::Builds

    economicdispatch::EconomicDispatchSequence
    reliabilitydispatch::ReliabilityDispatchSequence

    function ExpansionProblem(
        system::System,
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

        builds = Builds(
            [RegionBuild(m, r) for r in system.regions],
            [InterfaceBuild(m, i) for i in system.interfaces])

        economicdispatch = EconomicDispatchSequence(m, builds, economic_periods)

        reliabilitydispatch = ReliabilityDispatchSequence(
            m, builds, eue_estimator, eue_max)

        @objective(m, Min, cost(builds) + cost(economicdispatch))

        return new(m, system, builds, economicdispatch, reliabilitydispatch)

    end

end

solve!(prob::ExpansionProblem) = optimize!(prob.model)

end
