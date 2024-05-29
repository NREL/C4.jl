module IterationModel

using C4.Data
using C4.AdequacyModel
using C4.ExpansionModel

import Dates: Date
import JuMP: value

export iterate_ra_cem

include("eue_estimator_compression.jl")

function iterate_ra_cem(
    sys::System, economic_chronology::ExpansionModel.TimeProxyAssignment,
    max_neues::Vector{Float64}, optimizer;
    nsamples::Int=1000, neue_tols::Vector{Float64}=Float64[],
    aspp::Bool=true, endog_risk::Bool=true, min_iters::Int=0)

    neue_factors = [sum(region.demand) * 1e-6 for region in sys.regions]
    max_eues = max_neues .* neue_factors

    if length(neue_tols) > 0

        all(neue_tols .< max_neues) ||
            error("NEUE compression error tolerances must be less than the provided NEUE thresholds")
        eue_tols = neue_tols .* neue_factors

        # We assume the worst and require that NEUE estimate + max_error <= threshold
        max_eues .-= eue_tols

    else
        eue_tols = zeros(length(sys.regions))
    end

    display(sys)
    ram = AdequacyProblem(sys)
    adequacy = assess(ram, samples=nsamples)
    println(adequacy.region_neue)

    # TODO: Figure out good way to jump straight to valid estimator
    #       (save a round of iteration) - will clean up the while loop too
    eue_estimator = nullestimator(sys, economic_chronology)

    cem = nothing
    n_iters = 0

    is_adequate = all(adequacy.region_neue .<= max_neues)

    while (n_iters < min_iters) || !is_adequate

        n_iters += 1

        cem = ExpansionProblem(sys, economic_chronology, eue_estimator, max_eues, optimizer)
        solve!(cem)
        sys = System(cem)
        #display(sys)

        ram = AdequacyProblem(sys)
        adequacy = assess(ram, samples=nsamples)
        println(adequacy.region_neue, "\n")

        is_adequate = all(adequacy.region_neue .<= max_neues)

        eue_estimator = update_estimator(sys, cem, adequacy, eue_estimator, eue_tols,
                                         aspp=aspp, endog_risk=endog_risk)

        aspp || endog_risk || break

    end

    return cem, adequacy, n_iters

end

function update_estimator(
    sys::System, cem::ExpansionProblem, adequacy::AdequacyResult,
    old_estimator::ExpansionModel.EUEEstimator, eue_tols::Vector{Float64};
    aspp::Bool, endog_risk::Bool
)

    new_times = if aspp
        add_stressperiod(sys, old_estimator.times, adequacy)
    else
        old_estimator.times
    end

    new_estimator = if endog_risk
        ExpansionModel.EUEEstimator(new_times, estimators(cem, adequacy, new_times))
    else
        nullestimator(sys, new_times)
    end

    length(eue_tols) > 0 && compress_estimator!(new_estimator, eue_tols)

    return new_estimator

end

function add_stressperiod(
    sys::System, times::TimeProxyAssignment, adequacy::AdequacyResult
)

    days = reshape(adequacy.period_eue, times.daylength, :)
    days = vec(sum(days, dims=1))
    og_new_day = argmax(days)

    new_day = og_new_day
    new_day_first_hour = (new_day - 1) * 24 + 1

    while already_included(new_day_first_hour, times.periods)
        new_day = new_day > 1 ? new_day - 1 : length(days)
        new_day_first_hour = (new_day - 1) * times.daylength + 1
        if new_day == og_new_day
            @warn("No unmodeled stress periods left to add")
            return times
        end
    end

    ts = new_day_first_hour:(new_day_first_hour+times.daylength-1)
    name = string(Date(sys.timesteps[new_day_first_hour])) # TODO
    new_period = TimePeriod(ts, name)
    println("Adding period: $name")

    new_periods = [times.periods; new_period]
    new_days = copy(times.days)
    new_days[new_day] = length(times.periods)

    return TimeProxyAssignment(new_periods, new_days)

end

already_included(hour::Int, periods::Vector{TimePeriod}) =
    any(p -> in(hour, p.timesteps), periods)

function estimators(
    cem::ExpansionProblem, adequacy::AdequacyResult, tpa::TimeProxyAssignment)

    dispatches = cem.reliabilitydispatch.dispatches

    # TODO: cem..dispatches are out-of-date relative to
    #       (potentially newly-augmented) tpa. We need to use the old
    #       assignment for the period to find the right surplus_means, then
    #       use that (with the 1:1 adequacy data) to create a
    #       new 1:1 PeriodEUEEstimator for the new period
    return [period_estimator(adequacy.shortfall_samples,
                             value.(dispatch.surplus_mean), tpa, p)
            for (p, dispatch) in enumerate(dispatches)]

end

function period_estimator(
    surplus_steps::Array{Int,3}, surplus_mean::Matrix{Float64},
    tpa::TimeProxyAssignment, period_idx::Int)

    R, T = size(surplus_mean)
    n_samples = size(surplus_steps, 3)

    T == tpa.daylength || error("Day length mismatch")

    period_days = [i for (i, day_assignment) in enumerate(tpa.days)
                     if day_assignment==period_idx]

    eue_ints = Matrix{Vector{Float64}}(undef, R, T)
    eue_slopes = Matrix{Vector{Float64}}(undef, R, T)

    for r in 1:R, t_period in 1:T

        steps = Int[]
        surplus_rt = round(Int, surplus_mean[r, t_period])

        for day in period_days
            t = (day-1) * T + t_period
            append!(steps, surplus_steps[r, t, :] .+ surplus_rt)
        end

        eue_ints[r, t_period], eue_slopes[r, t_period] =
            estimator_params(steps, n_samples)

    end

    return ExpansionModel.PeriodEUEEstimator(eue_ints, eue_slopes)

end

function estimator_params(steps::Vector{Int}, n_samples::Int)

    n_steps = length(steps)

    intercepts = Float64[]
    slopes = Float64[]

    cum_count = 0
    cum_eue = 0.
    prev_surplus = Inf
    prev_slope = 0

    for (surplus, count) in unique_steps(steps)

        cum_count += count
        slope = cum_count / n_samples

        if !isinf(prev_surplus)
            cum_eue += prev_slope * (prev_surplus - surplus)
        end

        push!(slopes, slope)
        push!(intercepts, cum_eue + slope * surplus)

        prev_surplus = surplus
        prev_slope = slope

    end

    return intercepts, slopes

end

function unique_steps(steps::Vector{Int})

    d = Dict{Int,Int}()
    result = Pair{Int,Int}[]

    for s in steps
        s <= 0 && continue
        if s in keys(d)
            d[s] += 1
        else
            d[s] = 1
        end
    end

    for s in sort(collect(keys(d)), rev=true)
        push!(result, s => d[s])
    end

    return result

end

end
