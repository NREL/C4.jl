module ExpansionModel

import JuMP
import JuMP: @variable, @constraint, @expression

using ..Data

include("build.jl")
include("time.jl")
include("dispatch.jl")

export fullchronology, ExpansionProblem

mutable struct ExpansionProblem

    model::JuMP.Model

    system::System

    regions::Vector{RegionBuild}
    interfaces::Vector{InterfaceBuild}

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

        regions = [RegionBuild(m, r) for r in system.regions]
        interfaces = [InterfaceBuild(m, i) for i in system.interfaces]

        economicdispatch = DispatchSequence{EconomicDispatch}(system, economic_periods)
        reliabilitydispatch = DispatchSequence{ReliabilityDispatch}(system, reliability_periods)

        return new(m, system, regions, interfaces, economicdispatch, reliabilitydispatch)

    end

end

end
