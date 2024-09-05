module DispatchModel

import JuMP
import JuMP: @variable, @constraint, @expression, @objective, value

import IterTools: zip_longest

import ..GeneratorTechnology, ..StorageTechnology, ..StorageSite,
       ..Interface, ..Region, ..System,
       ..JuMP_ExpressionRef, ..JuMP_LessThanConstraintRef,
       ..JuMP_GreaterThanConstraintRef, ..JuMP_EqualToConstraintRef, ..varnames!,
       ..availablecapacity, ..maxpower, ..maxenergy,
       ..name, ..cost, ..cost_generation, ..demand,
       ..importinginterfaces, ..exportinginterfaces, ..solve!

using ..Data

include("dispatch.jl")
include("sequencing.jl")
include("economic.jl")
include("eue_estimator.jl")
include("reliability.jl")

export DispatchProblem, DispatchSequence, EconomicDispatch,
       ReliabilityDispatch, ReliabilityConstraints,
       EUEEstimator, PeriodEUEEstimator, nullestimator

struct DispatchProblem{D<:DispatchSequence}

    model::JuMP.Model

    system::SystemParams

    dispatch::D

    function DispatchProblem(
        system::SystemParams, D::Type{<:SystemDispatch},
        periods::TimeProxyAssignment, optimizer
    )

        n_timesteps = length(system.timesteps)

        timestepcount(periods) == n_timesteps ||
            error("Period assignment is incompatible with system timesteps")

        m = JuMP.Model(optimizer) 

        dispatch = DispatchSequence(D, m, system, periods)

        opex_scalar = 8766 / n_timesteps
        @objective(m, Min, opex_scalar * cost(dispatch))

        return new{typeof(dispatch)}(m, system, dispatch)

    end

end

solve!(prob::DispatchProblem) = JuMP.optimize!(prob.model)

cost(prob::DispatchProblem) =
    8766 / length(prob.system.timesteps) * cost(prob.dispatch)

end
