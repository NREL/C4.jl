module ExpansionModel

import JuMP
import JuMP: @variable, @constraint, @expression, @objective, value

import  ..JuMP_GreaterThanConstraintRef, ..JuMP_LessThanConstraintRef,
        ..JuMP_ExpressionRef,
        ..Site, ..VariableSite,
        ..ThermalTechnology, ..VariableTechnology, ..StorageTechnology,
        ..Interface, ..Region, ..System, ..varnames!,
        ..nameplatecapacity, ..availablecapacity, ..availability, ..maxpower, ..maxenergy,
        ..roundtrip_efficiency, ..operating_cost,
        ..name, ..variabletechs, ..storagetechs, ..thermaltechs,
        ..sites, ..cost, ..co2,
        ..cost_generation, ..cost_startup, ..co2_generation, ..co2_startup,
        ..max_unit_ramp, ..num_units, ..unit_size, ..min_gen,
        ..co2_startup, ..co2_generation,
        ..min_uptime, ..min_downtime,
        ..region_from, ..region_to,
        ..demand, ..importinginterfaces, ..exportinginterfaces, ..solve!

import ..Data: ThermalExistingParams, ThermalCandidateParams,
               VariableExistingParams, VariableExistingSiteParams,
               VariableCandidateParams, VariableCandidateSiteParams,
               StorageExistingParams, StorageCandidateParams

using ..Data
using ..AdequacyModel
using ..DispatchModel

include("thermal.jl")
include("variable.jl")
include("storage.jl")

include("build.jl")

include("riskestimates.jl")

export ExpansionProblem, ExpansionAdequacyContext, warmstart_builds!, solve!,
       capex, opex, carbon_offset_cost, cost, lcoe, emissions_intensity, nullestimator

const ExpansionEconomicDispatch =
    DispatchSequence{EconomicDispatch{SystemExpansion,RegionExpansion,InterfaceExpansion}}

const ExpansionReliabilityDispatch =
    DispatchSequence{ReliabilityDispatch{SystemExpansion,RegionExpansion,InterfaceExpansion}}

mutable struct ExpansionProblem

    model::JuMP.Model

    system::SystemParams

    builds::SystemExpansion

    economicdispatch::ExpansionEconomicDispatch

    reliabilitydispatch::ExpansionReliabilityDispatch
    reliabilityconstraints::ReliabilityConstraints

    carbon_offset_price::Float64
    carbon_offsets::Union{JuMP.VariableRef,Nothing} # in annual Megatonnes CO2
    co2_constraint::Union{JuMP_LessThanConstraintRef,Nothing}

    function ExpansionProblem(
        system::SystemParams,
        riskparams::RiskEstimateParams,
        eue_max::Vector{Float64}, # in powerunits_MWh
        co2_max::Real, # in annual Megatonnes CO2
        carbon_offset_price::Real, # $/tonne CO2
        optimizer)

        n_timesteps = length(system.timesteps)
        n_regions = length(system.regions)

        timestepcount(riskparams.times) == n_timesteps ||
            error("Time period assignment is incompatible with system timesteps")

        length(eue_max) == n_regions ||
            error("Mismatch between EUE constraint count and system regions")

        m = JuMP.direct_model(optimizer)

        builds = SystemExpansion(
            [RegionExpansion(m, r) for r in system.regions],
            [InterfaceExpansion(m, i) for i in system.interfaces])

        economicdispatch = DispatchSequence(
            EconomicDispatch, m, builds, riskparams.times)

        reliabilitydispatch = DispatchSequence(
            ReliabilityDispatch, m, builds, riskparams.times)

        reliabilityconstraints = ReliabilityConstraints(
            m, builds, reliabilitydispatch.dispatches, riskparams, eue_max)

        if isnan(co2_max)
            carbon_offsets = co2_constraint = nothing
            carbon_offset_cost = 0
        else
            carbon_offsets = @variable(m, lower_bound=0)
            co2_constraint = @constraint(m,
                co2(economicdispatch) - carbon_offsets <= co2_max)
            # convert $/tonne to $/Megatonne
            carbon_offset_cost = (carbon_offset_price * 1e6) * carbon_offsets
        end

        annualization_factor = 8766 / n_timesteps

        @objective(m, Min,
            cost(builds) + annualization_factor *
                (cost(economicdispatch) + carbon_offset_cost)
        )

        return new(m, system, builds, economicdispatch,
                   reliabilitydispatch, reliabilityconstraints,
                   carbon_offset_price, carbon_offsets, co2_constraint)

    end

end

function solve!(prob::ExpansionProblem)

    flush(stdout)

    JuMP.optimize!(prob.model)

    JuMP.termination_status(prob.model) == JuMP.OPTIMAL ||
        @error "Problem did not solve to optimality"

end

# Capex is annualized, so scale opex to approximate an annual cost
opex(prob::ExpansionProblem) =
    8766 / length(prob.system.timesteps) * cost(prob.economicdispatch)

capex(prob::ExpansionProblem) = cost(prob.builds)

# Capex is annualized, so scale carbon offset cost to approximate an annual cost
function carbon_offset_cost(prob::ExpansionProblem)

    if isnothing(prob.carbon_offsets)
        0
    else
        annualization_factor = 8766 / length(prob.system.timesteps)
        annualization_factor * (prob.carbon_offset_price * 1e6) * prob.carbon_offsets
    end

end

cost(prob::ExpansionProblem) = capex(prob) + opex(prob) + carbon_offset_cost(prob)

"""
CO2 emissions in annualized Megatonnes
"""
co2(prob::ExpansionProblem) =
    8766 / length(prob.system.timesteps) * co2(prob.economicdispatch)

function lcoe(prob::ExpansionProblem)

    # Scale demand to an approximate annual value to compare to annualized costs
    demand_scaler = 8766 / length(prob.system.timesteps)

    # Note: total demand here is the full-chronology demand,
    #       not necessarily what economic dispatch sees
    demand = total_demand(prob.system) * powerunits_MW * demand_scaler

    return cost(prob) / demand

end

"""
System emissions intensity in kg/MWh (g/kWh)
"""
emissions_intensity(prob::ExpansionProblem) =
    co2(prob.economicdispatch) / (total_demand(prob.system) * powerunits_MW) * 1e9

SystemParams(prob::ExpansionProblem) = SystemParams(
    prob.system.name, prob.system.timesteps,
    RegionParams.(prob.builds.regions),
    InterfaceParams.(prob.builds.interfaces),
    prob.system.fuels
)

function warmstart_builds!(prob::ExpansionProblem, prev_prob::ExpansionProblem)
    warmstart_builds!.(prob.builds.regions, prev_prob.builds.regions)
    warmstart_builds!.(prob.builds.interfaces, prev_prob.builds.interfaces)
    return
end


include("ExpansionAdequacyContext.jl")
include("export.jl")

end
