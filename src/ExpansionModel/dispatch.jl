# TODO: Differentiate reliability vs economic dispatch in variable names

struct GeneratorTechDispatch{G<:GeneratorTechnology}

    dispatch::Vector{JuMP.VariableRef}
    dispatch_max::Vector{JuMP_LessThanConstraintRef}

    build::TechnologyBuild{G}

    function GeneratorTechDispatch(
        m::JuMP.Model,
        regionbuild::RegionBuild, genbuild::TechnologyBuild{G}, period::TimePeriod
    ) where G <: GeneratorTechnology

        T = length(period)

        dispatch = @variable(m, [1:T], lower_bound = 0)
        fullname = join([regionbuild.params.name, genbuild.params.name, period.name], ",")
        varnames!(dispatch, "gen_dispatch[$(fullname)]", 1:T)

        dispatch_max = @constraint(m, [t in 1:T],
            dispatch[t] <= availablecapacity(genbuild, t))

        new{G}(dispatch, dispatch_max, genbuild)

    end

end

cost(dispatch::GeneratorTechDispatch) =
    sum(dispatch.dispatch) * dispatch.build.params.cost_generation

struct StorageSiteDispatch

    dispatch::Vector{JuMP.VariableRef}

    dispatch_min::Vector{JuMP_LessThanConstraintRef}
    dispatch_max::Vector{JuMP_LessThanConstraintRef}

    e_net::JuMP_ExpressionRef # MWh

    e_high::JuMP.VariableRef # MWh
    e_high_def::Vector{JuMP_LessThanConstraintRef}

    e_low::JuMP.VariableRef # MWh
    e_low_def::Vector{JuMP_LessThanConstraintRef}

    build::StorageSiteBuild

    function StorageSiteDispatch(
        m::JuMP.Model, regionbuild::RegionBuild, storbuild::StorageBuild,
        sitebuild::StorageSiteBuild, period::TimePeriod
    )

        T = length(period)

        dispatch = @variable(m, [1:T])
        fullname = join([
            regionbuild.params.name, storbuild.params.name,
            sitebuild.params.name, period.name], ",")
        varnames!(dispatch, "stor_dispatch[$(fullname)]", 1:T)

        capacity = maxpower(sitebuild)

        dispatch_min = @constraint(m, [t in 1:T], -capacity <= dispatch[t])
        dispatch_max = @constraint(m, [t in 1:T], dispatch[t] <= capacity)

        e_net = @expression(m, sum(dispatch))

        e_high = @variable(m, base_name="stor_ΔE_high[$(fullname)]")
        e_high_def = @constraint(m, [t in 1:T], sum(dispatch[1:t]) <= e_high)

        e_low = @variable(m, base_name="stor_ΔE_low[$(fullname)]")
        e_low_def = @constraint(m, [t in 1:T], e_low <= sum(dispatch[1:t]))

        return new(dispatch, dispatch_min, dispatch_max,
                   e_net, e_high, e_high_def, e_low, e_low_def, sitebuild)

    end

end

struct StorageTechDispatch

    sites::Vector{StorageSiteDispatch}
    dispatch::Vector{JuMP_ExpressionRef}

    build::StorageBuild

    function StorageTechDispatch(
        m::JuMP.Model, regionbuild::RegionBuild, storbuild::StorageBuild, period::TimePeriod
    )

        T = length(period)

        sites = [StorageSiteDispatch(m, regionbuild, storbuild, sitebuild, period)
                 for sitebuild in storbuild.sites]

        dispatch = @expression(m, [t in 1:T],
           sum(site.dispatch[t] for site in sites)
        )

        new(sites, dispatch, storbuild)

    end

end

struct InterfaceDispatch

    flow::Vector{JuMP.VariableRef}

    flow_min::Vector{JuMP_GreaterThanConstraintRef}
    flow_max::Vector{JuMP_LessThanConstraintRef}

    build::InterfaceBuild

    function InterfaceDispatch(
        m::JuMP.Model, iface::InterfaceBuild, period::TimePeriod
    )

        T = length(period)

        flow = @variable(m, [1:T])
        varnames!(flow, "iface_flow[$(iface.params.name),$(period.name)]", 1:T)

        flow_min = @constraint(m, [t in 1:T],
            flow[t] >= -iface.params.capacity_existing - iface.capacity_new)

        flow_max = @constraint(m, [t in 1:T],
            flow[t] <= iface.params.capacity_existing + iface.capacity_new)

        new(flow, flow_min, flow_max, iface)

    end

end

abstract type RegionDispatch end
abstract type Dispatch end
