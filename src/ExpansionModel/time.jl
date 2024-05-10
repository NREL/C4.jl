# TODO: Revisit naming. Here we implicitly state that "days" and "TimePeriods"
#       are synonymous
# "period" sometimes implies a single timestep, sometimes a contiguous set of timesteps
struct TimeProxyAssignment

    daylength::Int
    periods::Vector{TimePeriod} # set of all TimePeriods
    days::Vector{Int} # mapping from days into TimePeriods set

    function TimeProxyAssignment(periods::Vector{TimePeriod}, days::Vector{Int})

        period_length = length(first(periods))
        n_periods = length(periods)

        all(period -> length(period) == period_length, periods) ||
                error("Expected all periods to have the same length")

        all(p -> 1 <= p <= n_periods, days) ||
                error("Invalid period index in day mapping")

        new(period_length, periods, days)

    end

end

periodcount(tpa::TimeProxyAssignment) = length(tpa.periods)

function timestepcount(tpa::TimeProxyAssignment)
    tpa.daylength * length(tpa.days)
end

function fullchronology(sys::System; daylength::Int=24)
    n_days = daycount(sys, daylength)
    periods = [TimePeriod(((d-1)*daylength+1):(d*daylength), "Day $d") for d in 1:n_days]
    return TimeProxyAssignment(periods, collect(1:n_days))
end

function add_period!(tpa::TimeProxyAssignment, tp::TimePeriod, ds::Vector{Int})
    push!(tpa.periods, tp)
    days[ds] .= tp
    return
end

function daycount(sys::System, daylength::Int)
    n_periods = length(sys.timesteps)
    n_days, remainder = divrem(n_periods, daylength)
    iszero(remainder) ||
        error("System timesteps ($(n_periods)) should be a multiple of daylength ($(daylength))")
    return n_days
end
