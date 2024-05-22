module IterationModel

using C4.Data
using C4.AdequacyModel
using C4.ExpansionModel

import JuMP: value

export aspp

include("eue_estimator_compression.jl")

function aspp(
    sys::System, economic_chronology::ExpansionModel.TimeProxyAssignment,
    max_neues::Vector{Float64}, optimizer; nsamples::Int=1000)

    max_eues = [max_neue / 1_000_000 * sum(region.demand)
                for (max_neue, region) in zip(max_neues, sys.regions)]

    display(sys)
    @time ram = AdequacyProblem(sys)
    @time adequacy = assess(ram, samples=nsamples)
    println(adequacy.region_neue)
    eue_estimator = nullestimator(sys, s -> economic_chronology)

    cem = nothing
    n_iters = 0

    while any(neue > max_neue for (neue, max_neue) in zip(adequacy.region_neue, max_neues))

        n_iters += 1

        @time cem = ExpansionProblem(sys, economic_chronology, eue_estimator, max_eues, optimizer)
        @time solve!(cem)
        @time sys = System(cem)
        display(sys)

        @time ram = AdequacyProblem(sys)
        @time adequacy = assess(ram, samples=nsamples)
        println(adequacy.region_neue, "\n")
        eue_estimator = update_estimator(sys, cem, adequacy, eue_estimator)

    end

    return cem, adequacy, n_iters

end

function update_estimator(
    sys::System, cem::ExpansionProblem, adequacy::AdequacyResult,
    old_estimator::ExpansionModel.EUEEstimator
)

    times = add_stressperiod(old_estimator.times, adequacy)

    new_estimators = estimators(cem, adequacy, times)

    return ExpansionModel.EUEEstimator(times, new_estimators)

end

function add_stressperiod(old_times::TimeProxyAssignment, adequacy::AdequacyResult)

    # TODO identify new stress period and create a new TPA with it included
    return old_times

end

function estimators(
    cem::ExpansionProblem, adequacy::AdequacyResult, tpa::TimeProxyAssignment)

    dispatches = cem.reliabilitydispatch.dispatches

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

    sort!(steps)

    lolps = Float64[]
    surpluses = Int[]

    step = length(steps)
    surplus = last(steps)
    n_greater = 0

    push!(surpluses, surplus)
    push!(lolps, n_greater / n_samples) # Always 0

    while surplus > 0 && step > 1

        step -= 1
        n_greater += 1
        new_surplus = steps[step]
        new_surplus == surplus && continue

        surplus = new_surplus

        push!(surpluses, surplus)
        push!(lolps, n_greater / n_samples)

    end

    push!(surpluses, 0)
    push!(lolps, (n_greater + 1) / n_samples)

    n_segments = length(lolps)
    eue_int = similar(lolps)
    eue_prev = 0
    surpl_prev = 0

    for (i, (surpl, lolp)) in enumerate(zip(surpluses, lolps))
        eue_int[i] = surpl_prev * lolp + eue_prev
        eue_prev += (surpl_prev - surpl)  * lolp
        surpl_prev = surpl
    end

    @assert iszero(first(lolps))
    @assert iszero(first(eue_int))

    return eue_int[2:end], lolps[2:end]

end

end
