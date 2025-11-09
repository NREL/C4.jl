# TODO: Differentiate reliability vs economic dispatch in variable names
struct ThermalDispatch{G<:ThermalTechnology}

    dispatch::Vector{JuMP.VariableRef}
    units_committed::Vector{JuMP.VariableRef}
    units_startup::Vector{JuMP.VariableRef}
    units_shutdown::Vector{JuMP.VariableRef}

    units_committed_max::Vector{JuMP_LessThanConstraintRef}
    commitment_state::Vector{JuMP_EqualToConstraintRef}
    min_up_time::Vector{JuMP_LessThanConstraintRef}
    min_down_time::Vector{JuMP_LessThanConstraintRef}
    dispatch_max::Vector{JuMP_LessThanConstraintRef}
    dispatch_min::Vector{JuMP_LessThanConstraintRef}
    ramp_up_max::Vector{JuMP_LessThanConstraintRef}
    ramp_down_max::Vector{JuMP_LessThanConstraintRef}

    tech::G

    function ThermalDispatch(
        m::JuMP.Model, region::Region,
        tech::G, period::TimePeriod
    ) where G <: ThermalTechnology

        T = length(period)
        ts = period.timesteps

        fullname = join([name(region), name(tech), period.name], ",")

        dispatch = @variable(m, [1:T], lower_bound = 0)
        varnames!(dispatch, "tech_dispatch[$(fullname)]", 1:T)

        units_committed = @variable(m, [1:T], integer=true, lower_bound = 0)
        varnames!(units_committed, "tech_units_committed[$(fullname)]", 1:T)

        units_startup = @variable(m, [1:T], binary=true, lower_bound = 0)
        varnames!(units_startup, "tech_units_startup[$(fullname)]", 1:T)

        units_shutdown = @variable(m, [1:T], binary=true, lower_bound = 0)
        varnames!(units_shutdown, "tech_units_shutdown[$(fullname)]", 1:T)

        units_committed_max = @constraint(m, [t in 1:T],
            units_committed[t] <= num_units(tech))

        commitment_state = @constraint(m, [t in 1:T],
            units_committed[t] == units_committed[prev_t(t, T)] + units_startup[t] - units_shutdown[t])

        min_up_time = @constraint(m, [t in 1:T],
            sum(units_startup[tt] for tt in last_n(t, min_uptime(tech), T)) <= units_committed[t])

        min_down_time = @constraint(m, [t in 1:T],
            sum(units_shutdown[tt] for tt in last_n(t, min_downtime(tech), T)) <= num_units(tech) - units_committed[t])

        dispatch_max = @constraint(m, [t in 1:T],
            dispatch[t] <= unit_size(tech) * units_committed[t])

        dispatch_min = @constraint(m, [t in 1:T],
            min_gen(tech) * units_committed[t] <= dispatch[t])

        ramp_up_max = @constraint(m, [t in 1:T],
            dispatch[t] - dispatch[prev_t(t, T)] <= max_unit_ramp(tech) * (units_committed[t] - units_startup[t]) - min_gen(tech) * units_shutdown[t] + max(min_gen(tech), max_unit_ramp(tech)) * units_startup[t]
            )

        ramp_down_max = @constraint(m, [t in 1:T],
            dispatch[prev_t(t, T)] - dispatch[t] <= max_unit_ramp(tech) * (units_committed[t] - units_startup[t]) - min_gen(tech) * units_startup[t] + max(min_gen(tech), max_unit_ramp(tech)) * units_shutdown[t]
            )

        return new{G}(dispatch, units_committed, units_startup, units_shutdown, units_committed_max, commitment_state, dispatch_max, min_up_time, min_down_time, dispatch_min, ramp_up_max, ramp_down_max, tech)

    end

end

cost(dispatch::ThermalDispatch) =
    cost_startup(dispatch.tech) * sum(dispatch.units_startup) +
    cost_generation(dispatch.tech) * sum(dispatch.dispatch)

co2(dispatch::ThermalDispatch) =
    co2_startup(dispatch.tech) * sum(dispatch.units_startup) +
    co2_generation(dispatch.tech) * sum(dispatch.dispatch)

name(dispatch::ThermalDispatch) = name(dispatch.tech)

prev_t(t::Int, T::Int) = t == 1 ? T : t - 1

function last_n(t::Int, n::Int, T::Int)
    inds = Vector{Int}(undef, n)
    for i in n:-1:1
        inds[i] = t
        t = prev_t(t, T)
    end
    return inds
end


struct StorageDispatch{S<:StorageTechnology}

    charge::Vector{JuMP.VariableRef}
    discharge::Vector{JuMP.VariableRef}
    dispatch::Vector{JuMP_ExpressionRef}

    charge_max::Vector{JuMP_LessThanConstraintRef}
    discharge_max::Vector{JuMP_LessThanConstraintRef}

    e_net::JuMP.VariableRef # MWh
    e_net_def::JuMP_EqualToConstraintRef

    e_high::JuMP.VariableRef # MWh
    e_high_def::Vector{JuMP_LessThanConstraintRef}

    e_low::JuMP.VariableRef # MWh
    e_low_def::Vector{JuMP_LessThanConstraintRef}

    stor::S

    function StorageDispatch(
        m::JuMP.Model, region::Region, stor::S,
        period::TimePeriod) where S <: StorageTechnology

        T = length(period)

        charge = @variable(m, [1:T], lower_bound = 0)
        fullname = join([name(region), name(stor), period.name], ",")
        varnames!(charge, "stor_charge[$(fullname)]", 1:T)

        discharge = @variable(m, [1:T], lower_bound = 0)
        fullname = join([name(region), name(stor), period.name], ",")
        varnames!(discharge, "stor_discharge[$(fullname)]", 1:T)

        capacity = maxpower(stor)
        eff = sqrt(roundtrip_efficiency(stor))

        charge_max = @constraint(m, [t in 1:T], charge[t] <= capacity)
        discharge_max = @constraint(m, [t in 1:T], discharge[t] <= capacity)

        e_net = @variable(m)
        e_net_def = @constraint(m, e_net == eff * sum(charge) - 1/eff * sum(discharge))

        e_high = @variable(m, base_name="stor_ΔE_high[$(fullname)]")
        e_high_def = @constraint(m, [t in 1:T],
            eff * sum(charge[1:t]) - 1/eff * sum(discharge[1:t]) <= e_high)

        e_low = @variable(m, base_name="stor_ΔE_low[$(fullname)]")
        e_low_def = @constraint(m, [t in 1:T],
            e_low <= eff * sum(charge[1:t]) - 1/eff * sum(discharge[1:t]))
        dispatch = @expression(m, [t in 1:T], discharge[t] - charge[t])

        return new{S}(
            charge, discharge, dispatch, charge_max, discharge_max,
            e_net, e_net_def, e_high, e_high_def, e_low, e_low_def,
            stor)

    end

end

name(dispatch::StorageDispatch) =
    name(dispatch.stor)

usage(dispatch::StorageDispatch) =
    sum(dispatch.charge) + sum(dispatch.discharge)

cost(dispatch::StorageDispatch) =
    usage(dispatch) * operating_cost(dispatch.stor)

struct InterfaceDispatch{I<:Interface}

    flow::Vector{JuMP.VariableRef}

    flow_min::Vector{JuMP_GreaterThanConstraintRef}
    flow_max::Vector{JuMP_LessThanConstraintRef}

    iface::I

    function InterfaceDispatch(
        m::JuMP.Model, iface::I, period::TimePeriod) where I <: Interface

        T = length(period)

        flow = @variable(m, [1:T])
        varnames!(flow, "iface_flow[$(name(iface)),$(period.name)]", 1:T)

        capacity = availablecapacity(iface)
        flow_min = @constraint(m, [t in 1:T], flow[t] >= -capacity)
        flow_max = @constraint(m, [t in 1:T], flow[t] <= capacity)

        return new{I}(flow, flow_min, flow_max, iface)

    end

end

region_from(iface::InterfaceDispatch) = region_from(iface.iface)
region_to(iface::InterfaceDispatch) = region_to(iface.iface)

"""
RegionDispatch is an abstract type for holding optimization problem components
for dispatching a Region. RegionDispatch instance constructors should take the
following arguments:
```
RegionDispatch(::JuMP.Model, ::Region, ::Vector{InterfaceDispatch}, ::TimePeriod)
```
"""
abstract type RegionDispatch{R<:Region} end

name(dispatch::RegionDispatch) = name(dispatch.region)
demand(dispatch::RegionDispatch, t::Int) = demand(dispatch.region, t)

"""
SystemDispatch contains optimization problem components for
dispatching a System. SystemDispatch constructors should take the
following arguments:
```
SystemDispatch(::JuMP.Model, ::System, ::TimePeriod)
```
"""
abstract type SystemDispatch{S<:System} end
