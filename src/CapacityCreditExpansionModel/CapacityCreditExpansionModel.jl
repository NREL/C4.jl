module CapacityCreditExpansionModel

import JuMP
import JuMP: @variable, @constraint, @expression, @objective, value

import ..Site, ..ThermalSite, ..VariableSite, ..StorageSite,
       ..ThermalTechnology, ..VariableTechnology, ..StorageTechnology,
       ..Interface, ..Region, ..System, ..varnames!,
       ..JuMP_LessThanConstraintRef, ..JuMP_GreaterThanConstraintRef,
       ..availablecapacity, ..maxpower, ..maxenergy,
       ..roundtrip_efficiency, ..operating_cost,
       ..name, ..cost, ..cost_generation, ..region_from, ..region_to,
       ..demand, ..importinginterfaces, ..exportinginterfaces, ..solve!

using ..Data
using ..DispatchModel

import ..ExpansionModel

# Note that all capacity credits are defined at the tech level
# (not the site level). In this implementation, capacity credit methods
# assume the problem involves a single region

abstract type CapacityCreditParams end
abstract type CapacityCreditFormulation end

new_nameplate(build::ExpansionModel.ThermalExpansion) = sum(
    site.units_new * build.params.unit_size for site in build.sites; init=0)

new_nameplate(build::ExpansionModel.VariableExpansion) = sum(
    site.capacity_new for site in build.sites; init=0)

new_nameplate(build::ExpansionModel.StorageExpansion) = sum(
    site.power_new for site in build.sites; init=0)

include("1d_curves.jl")

export CapacityCreditExpansionProblem,
       CapacityCreditCurveParams, CapacityCreditCurvesParams

mutable struct CapacityCreditExpansionProblem{T <: CapacityCreditFormulation} <: ExpansionModel.AbstractExpansionProblem

    model::JuMP.Model

    system::SystemParams

    builds::ExpansionModel.SystemExpansion

    economicdispatch::ExpansionModel.ExpansionEconomicDispatch

    reliabilityconstraints::T

    function CapacityCreditExpansionProblem(
        system::SystemParams,
        chronology::TimeProxyAssignment,
        capacitycredits::CapacityCreditParams,
        build_efc::Float64, # powerunits_MW
        optimizer)

        n_timesteps = length(system.timesteps)
        n_regions = length(system.regions)

        n_regions == 1 ||
            error("Capacity credit formulations require a single region")

        m = JuMP.direct_model(optimizer)

        builds = ExpansionModel.SystemExpansion(
            [ExpansionModel.RegionExpansion(m, r) for r in system.regions],
            [ExpansionModel.InterfaceExpansion(m, i) for i in system.interfaces])

        economicdispatch = DispatchSequence(
            EconomicDispatch, m, builds, chronology)

        reliabilityconstraints = capacity_credits(
            m, first(builds.regions), capacitycredits, build_efc)

        T = typeof(reliabilityconstraints)

        opex_scalar = 8766 / n_timesteps

        @objective(m, Min, cost(builds) + opex_scalar * cost(economicdispatch))

        return new{T}(m, system, builds, economicdispatch,
                   reliabilityconstraints)

    end

end

end
