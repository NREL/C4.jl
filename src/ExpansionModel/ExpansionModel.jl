module ExpansionModel

import JuMP
import JuMP: @variable, @constraint, @expression

import MathOptInterface
const MOI = MathOptInterface

using ..Data

include("jump_utils.jl")
include("build.jl")
include("time.jl")
include("dispatch.jl")

export fullchronology, ExpansionProblem

mutable struct ExpansionProblem

    model::JuMP.Model

    system::System

    builds::Builds

    economicdispatch::DispatchSequence{EconomicDispatch}
    reliabilitydispatch::DispatchSequence{ReliabilityDispatch}

    function ExpansionProblem(
        system::System,
        economic_periods::TimeProxyAssignment,
        reliability_periods::TimeProxyAssignment,
        optimizer)

        n_timesteps = length(system.timesteps)

        timestepcount(economic_periods) == n_timesteps ||
            error("Economic period assignment is incompatible with system timesteps")

        timestepcount(reliability_periods) == n_timesteps ||
            error("Reliability period assignment is incompatible with system timesteps")

        m = JuMP.Model(optimizer)

        builds = Builds(
            [RegionBuild(m, r) for r in system.regions],
            [InterfaceBuild(m, i) for i in system.interfaces])

        economicdispatch = DispatchSequence{EconomicDispatch}(
            m, builds, economic_periods)

        reliabilitydispatch = DispatchSequence{ReliabilityDispatch}(
            m, builds, reliability_periods)

        return new(m, system, builds, economicdispatch, reliabilitydispatch)

    end

end

end
