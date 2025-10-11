struct VariableDispatch{V<:VariableTechnology}

    dispatch::Vector{JuMP.VariableRef}
    dispatch_max::Vector{JuMP_LessThanConstraintRef}

    tech::V

    function VariableDispatch(
        m::JuMP.Model, region::Region,
        tech::V, period::TimePeriod
    ) where V <: VariableTechnology

        T = length(period)
        ts = period.timesteps

        dispatch = @variable(m, [1:T], lower_bound = 0)
        fullname = join([name(region), name(tech), period.name], ",")
        varnames!(dispatch, "tech_dispatch[$(fullname)]", 1:T)

        dispatch_max = @constraint(m, [t in 1:T],
            dispatch[t] <= availablecapacity(tech, ts[t]))

        return new{V}(dispatch, dispatch_max, tech)

    end

end

cost(dispatch::VariableDispatch) =
    sum(dispatch.dispatch) * cost_generation(dispatch.tech)

# TODO: Where is this used?
name(dispatch::VariableDispatch) = name(dispatch.tech)
