struct TimePeriod
    timesteps::UnitRange{Int}
    name::String
end

struct TimeProxyAssignment
    daylength::Int
    timeperiods::Vector{TimePeriod} # set of all TimePeriods
    days::Vector{TimePeriod} # mapping from days to TimePeriods
end

function timestepcount(tpa::TimeProxyAssignment)
    tpa.daylength * length(tpa.days)
end

function fullchronology(sys::System; daylength::Int=24)
    n_days = daycount(sys, daylength)
    timeperiods = [TimePeriod(((d-1)*daylength+1):(d*daylength), "Day $d") for d in 1:n_days]
    return TimeProxyAssignment(daylength, timeperiods, timeperiods)
end

function add_period!(tpa::TimeProxyAssignment, tp::TimePeriod, ds::Vector{Int})
    push!(tpa.timeperiods, tp)
    days[ds] = tp
    return
end

function daycount(sys::System, daylength::Int)
    n_periods = length(sys.timesteps)
    n_days, remainder = divrem(n_periods, daylength)
    iszero(remainder) ||
        error("System timesteps ($(n_periods)) should be a multiple of daylength ($(daylength))")
    return n_days
end
