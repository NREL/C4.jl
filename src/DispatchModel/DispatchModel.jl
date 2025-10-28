module DispatchModel

import JuMP
import JuMP: @variable, @constraint, @expression, @objective, value

import IterTools: zip_longest

import ..ThermalTechnology, ..VariableTechnology, ..StorageTechnology,
       ..Interface, ..Region, ..System,
       ..JuMP_ExpressionRef, ..JuMP_LessThanConstraintRef,
       ..JuMP_GreaterThanConstraintRef, ..JuMP_EqualToConstraintRef, ..varnames!,
       ..availablecapacity, ..maxpower, ..maxenergy,
       ..roundtrip_efficiency, ..operating_cost, ..max_unit_ramp, ..num_units, ..unit_size, ..min_gen,
       ..name, ..cost, ..cost_generation, ..demand, ..region_from, ..region_to,
       ..variabletechs, ..storagetechs, ..thermaltechs,
       ..importinginterfaces, ..exportinginterfaces, ..solve!, ..powerunits_MW

using ..Data

include("dispatch.jl")
include("variable.jl")

include("sequencing.jl")

include("economic.jl")
include("reliability.jl")

export DispatchProblem, EconomicDispatchProblem, ReliabilityDispatchProblem,
       DispatchSequence, EconomicDispatchSequence, ReliabilityDispatchSequence,
       EconomicDispatch, ReliabilityDispatch

struct DispatchProblem{D<:DispatchSequence}

    model::JuMP.Model

    system::SystemParams

    dispatch::D

    function DispatchProblem(
        system::SystemParams, D::Type{<:SystemDispatch},
        periods::TimeProxyAssignment, optimizer, voll::Float64=NaN
    )

        n_timesteps = length(system.timesteps)

        timestepcount(periods) == n_timesteps ||
            error("Period assignment is incompatible with system timesteps")

        m = JuMP.direct_model(optimizer)

        dispatch = DispatchSequence(D, m, system, periods, voll)

        opex_scalar = 8766 / n_timesteps
        @objective(m, Min, opex_scalar * cost(dispatch))

        return new{typeof(dispatch)}(m, system, dispatch)

    end

end

const EconomicDispatchProblem = DispatchProblem{<:EconomicDispatchSequence}
const ReliabilityDispatchProblem = DispatchProblem{<:ReliabilityDispatchSequence}

function solve!(prob::DispatchProblem)

    flush(stdout)

    JuMP.optimize!(prob.model)

    JuMP.termination_status(prob.model) == JuMP.OPTIMAL ||
        @error "Problem did not solve to optimality"

end

cost(prob::DispatchProblem) =
    8766 / length(prob.system.timesteps) * cost(prob.dispatch)

include("export.jl")

end
