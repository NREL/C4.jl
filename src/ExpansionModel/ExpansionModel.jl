module ExpansionModel

import JuMP
import JuMP: @variable, @constraint, @expression, @objective, value

import  ..JuMP_GreaterThanConstraintRef, ..JuMP_LessThanConstraintRef,
        ..JuMP_ExpressionRef,
        ..Site, ..ThermalSite, ..VariableSite, ..StorageSite,
        ..ThermalTechnology, ..VariableTechnology, ..StorageTechnology,
        ..Interface, ..Region, ..System, ..varnames!,
        ..availablecapacity, ..maxpower, ..maxenergy,
        ..roundtrip_efficiency, ..operating_cost,
        ..name, ..cost, ..cost_generation, ..region_from, ..region_to,
        ..demand, ..importinginterfaces, ..exportinginterfaces, ..solve!

using ..Data
using ..AdequacyModel
using ..DispatchModel

import ..AdequacyModel: AdequacyContext,
                        ThermalRegionUnitCount, ThermalSiteUnitCount

include("build.jl")
include("riskestimates.jl")

export ExpansionProblem, warmstart_builds!, solve!,
       capex, opex, cost, lcoe, nullestimator

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

    function ExpansionProblem(
        system::SystemParams,
        riskparams::RiskEstimateParams,
        eue_max::Vector{Float64}, # in powerunits_MWh
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

        opex_scalar = 8766 / n_timesteps

        @objective(m, Min, cost(builds) + opex_scalar * cost(economicdispatch))

        return new(m, system, builds, economicdispatch,
                   reliabilitydispatch, reliabilityconstraints)

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
cost(prob::ExpansionProblem) = capex(prob) + opex(prob)

function lcoe(prob::ExpansionProblem)

    # Scale demand to an approximate annual value to compare to annualized costs
    demand_scaler = 8766 / length(prob.system.timesteps)

    # Note: total demand here is the full-chronology demand,
    #       not necessarily what economic dispatch sees
    demand = total_demand(prob.system) * powerunits_MW * demand_scaler

    return cost(prob) / demand

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

function AdequacyContext(
    cem::ExpansionProblem, adequacy::AdequacyResult
)

    R, T = size(adequacy.load)

    variable_availability = zeros(Float64, R, T)
    for (r, region) in enumerate(cem.builds.regions)
        for tech in region.variabletechs
            for site in tech.sites
                capacity = site.params.capacity_existing + value(site.capacity_new)
                variable_availability[r,:] .+= capacity .* site.params.availability
            end
        end
    end

    thermal_units = [ThermalRegionUnitCount(region) for region in cem.builds.regions]

    return AdequacyContext(
        variable_availability, thermal_units, adequacy)

end


include("export.jl")

end
