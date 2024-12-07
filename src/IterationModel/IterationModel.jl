module IterationModel

using C4.Data
using C4.AdequacyModel
using C4.DispatchModel
using C4.ExpansionModel

import ..store, ..powerunits_MW

import Dates: Date, now
import DBInterface
import DelimitedFiles: writedlm
import DuckDB
import JuMP: value

export iterate_ra_cem

include("eue_estimator_compression.jl")

function iterate_ra_cem(
    sys::SystemParams, base_chronology::TimeProxyAssignment,
    max_neues::Vector{Float64}, optimizer;
    nsamples::Int=1000, neue_tols::Vector{Float64}=Float64[],
    timeout::Float64=Inf,
    aspp::Bool=true, endog_risk::Bool=true, outfile::String="",
    check_dispatch::Bool=false)

    persist = length(outfile) > 0
    max_neue = maximum(max_neues)
    timeout += time()

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

    ram_start = now()
    ram = AdequacyProblem(sys, samples=nsamples)
    solve!(ram)
    ram_end = now()

    println(ram.region_neue)

    curves_start = now()
    eue_estimator = bootstrap_estimator(
        sys, base_chronology, ram, eue_tols,
        aspp=aspp, endog_risk=endog_risk)
    curves_end = now()

    if persist
        store_start = now()
        con = DBInterface.connect(DuckDB.DB, outfile)
        store(con, sys)
        store_iteration(con, 0)
        store_iteration_step(con, 0, "adequacy", ram_start => ram_end)
        store(con, 0, ram)
        store_iteration_step(con, 0, "riskcurves", curves_start => curves_end)
        store_end = now()
        store_iteration_step(con, 0, "persistence", store_start => store_end)
    end

    cem = nothing
    sys_built = nothing
    prev_cem = nothing
    n_iters = 0

    while (time() < timeout)

        n_iters += 1
        cem_start = now()

        cem = ExpansionProblem(sys, eue_estimator, max_eues, optimizer)
        isnothing(prev_cem) || warmstart_builds!(cem, prev_cem)

        println("Recurrences:")
        for recc in cem.reliabilitydispatch.recurrences
            println(recc.repetitions, " x ", recc.dispatch.period.name)
        end

        solve!(cem)
        cem_end = now()

        ram_start = now()
        sys_built = SystemParams(cem)
        ram = AdequacyProblem(sys_built, samples=nsamples)
        solve!(ram)
        ram_end = now()

        println(ram.neue, "\t", ram.region_neue, "\n")

        is_adequate = all(ram.region_neue .<= max_neues)

        curves_start = now()
        eue_estimator = update_estimator(cem, ram, eue_estimator, eue_tols,
                                         aspp=aspp, endog_risk=endog_risk)
        curves_end = now()

        if persist
            store_start = now()
            store_iteration(con, n_iters)
            store_iteration_step(con, n_iters, "expansion", cem_start => cem_end)
            store_iteration_step(con, n_iters, "adequacy", ram_start => ram_end)
            store_iteration_step(con, n_iters, "riskcurves", curves_start => curves_end)
            store(con, n_iters, cem.builds)
            store(con, n_iters, cem.economicdispatch)
            store(con, n_iters, ram)
            store_end = now()
            store_iteration_step(con, n_iters, "persistence", store_start => store_end)
        end

        prev_cem = cem

        is_adequate && break
        aspp || endog_risk || break

    end

    pcm = nothing

    if (aspp || endog_risk) && check_dispatch

        pcm_start = now()
        n_iters += 1
        fullchrono = fullchronologyperiods(sys_built, daylength=base_chronology.daylength)
        pcm = DispatchProblem(sys_built, EconomicDispatch, fullchrono, optimizer)
        solve!(pcm)
        pcm_end = now()

        if persist
            store_iteration(con, n_iters)
            store_iteration_step(con, n_iters, "dispatch", pcm_start => pcm_end)
            store(con, n_iters, pcm.dispatch)
        end

    end

    return cem, ram, pcm

end

function bootstrap_estimator(
    sys::SystemParams, time::TimeProxyAssignment, adequacy::AdequacyProblem,
    eue_tols::Vector{Float64}; aspp::Bool, endog_risk::Bool
)

    if aspp
        time = add_stressperiod(sys, time, adequacy)
    end

    if endog_risk
        estimator = EUEEstimator(time, estimators(adequacy, time))
        length(eue_tols) > 0 && compress_estimator!(estimator, eue_tols)
    else
        estimator = nullestimator(sys, time)
    end

    return estimator

end

function update_estimator(
    cem::ExpansionProblem, adequacy::AdequacyProblem,
    old_estimator::EUEEstimator, eue_tols::Vector{Float64};
    aspp::Bool, endog_risk::Bool
)

    new_times = if aspp
        add_stressperiod(cem.system, old_estimator.times, adequacy)
    else
        old_estimator.times
    end

    new_estimator = if endog_risk
        EUEEstimator(new_times, estimators(cem, adequacy, new_times))
    else
        nullestimator(cem.system, new_times)
    end

    length(eue_tols) > 0 && compress_estimator!(new_estimator, eue_tols)

    return new_estimator

end

function add_stressperiod(
    sys::SystemParams, times::TimeProxyAssignment, adequacy::AdequacyProblem
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
    new_days[new_day] = length(new_periods)

    return TimeProxyAssignment(new_periods, new_days)

end

already_included(hour::Int, periods::Vector{TimePeriod}) =
    any(p -> in(hour, p.timesteps), periods)

function estimators(adequacy::AdequacyProblem, tpa::TimeProxyAssignment)

    return [
        period_estimator(adequacy.shortfall_samples, adequacy.surplus_mean, tpa, p)
        for p in eachindex(tpa.periods)
    ]

end

function estimators(
    cem::ExpansionProblem, adequacy::AdequacyProblem, tpa::TimeProxyAssignment)

    dispatch_periods = [d.period for d in cem.reliabilitydispatch.dispatches]

    result = similar(tpa.periods, PeriodEUEEstimator)

    min_slope = Inf
    max_slope = -Inf

    for (p, period) in enumerate(tpa.periods)

        dispatch_idx = findfirst(isequal(period), dispatch_periods)

        surplus_mean = if isnothing(dispatch_idx)
            adequacy.surplus_mean
        else
            dispatch = cem.reliabilitydispatch.dispatches[dispatch_idx]
            value.(dispatch.surplus_mean)
        end

        result[p] =
            period_estimator(adequacy.shortfall_samples, surplus_mean, tpa, p)

        for v in result[p].slopes
            low, hi = extrema(v)
            low < min_slope && (min_slope = low)
            hi > max_slope && (max_slope = hi)
        end

    end

    @show (min_slope, max_slope)

    return result

end

function period_estimator(
    surplus_steps::Array{Float64,3}, surplus_mean::Matrix{Float64},
    tpa::TimeProxyAssignment, period_idx::Int)

    R, T_fullchrono, n_samples = size(surplus_steps)
    T_period = tpa.daylength

    size(surplus_mean, 1) == R || error("Region count mismatch")

    const_means = size(surplus_mean, 2) == T_period

    const_means || size(surplus_mean, 2) == T_fullchrono ||
        error("Day length mismatch")

    period_days = [i for (i, day_assignment) in enumerate(tpa.days)
                     if day_assignment==period_idx]

    eue_ints = Matrix{Vector{Float64}}(undef, R, T_period)
    eue_slopes = Matrix{Vector{Float64}}(undef, R, T_period)

    for r in 1:R, t_period in 1:T_period

        steps = Float64[]

        for day in period_days

            t = (day-1) * T_period + t_period
            t_idx = const_means ? t_period : t

            append!(steps, surplus_steps[r, t, :] .+ surplus_mean[r, t_idx])

        end

        eue_ints[r, t_period], eue_slopes[r, t_period] =
            estimator_params(steps, n_samples)

    end

    return PeriodEUEEstimator(eue_ints, eue_slopes)

end

function estimator_params(steps::Vector{Float64}, n_samples::Int)

    n_steps = length(steps)

    intercepts = Float64[]
    slopes = Float64[]

    cum_count = 0
    cum_eue = 0.
    prev_surplus = Inf
    prev_slope = 0

    for (surplus, count) in unique_steps(round.(Int, steps .* powerunits_MW))

        cum_count += count
        slope = cum_count / n_samples

        if !isinf(prev_surplus)
            cum_eue += prev_slope * (prev_surplus - surplus)
        end

        push!(slopes, slope)
        push!(intercepts, (cum_eue + slope * surplus) / powerunits_MW)

        prev_surplus = surplus
        prev_slope = slope

    end

    # These aren't mathematically necessary, but JuMP complains when iterating
    # over an empty set of constraints
    if iszero(length(slopes))
        push!(slopes, 0)
        push!(intercepts, 0)
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
