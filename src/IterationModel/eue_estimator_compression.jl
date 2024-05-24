# TODO: None of this code is optimized, revisit if needed

function compress_estimator!(estimator::ExpansionModel.EUEEstimator, eue_tols::Vector{Float64})

    n_regions = size(first(estimator.estimators).slopes, 1)
    length(eue_tols) == n_regions ||
        error("Number of EUE tolerances passed does not match number of regions")

    for (r, tol) in enumerate(eue_tols)
        compress_estimator!(estimator, r, tol)
    end

end

function compress_estimator!(estimator::ExpansionModel.EUEEstimator, r::Int, eue_tol::Float64)

    n_periods = length(estimator.estimators)
    t_per_period = estimator.times.daylength

    slopes = Matrix{Vector{Float64}}(undef, t_per_period, n_periods)
    intercepts = Matrix{Vector{Float64}}(undef, t_per_period, n_periods)

    for (p, period_estimator) in enumerate(estimator.estimators)
        slopes[:, p] = period_estimator.slopes[r,:]
        intercepts[:, p] = period_estimator.intercepts[r,:]
    end

    n_curves = length(slopes)
    n_segments = sum(length.(slopes))


    # Note: No need to compute the entire curves here, could stop once tol is reached

    combined_curve = compress_estimators(intercepts, slopes)
    eue_errors = total_error_curve(combined_curve, n_curves)

    keepers = [BitSet(eachindex(slopes[t,p])) for t in 1:t_per_period, p in 1:n_periods]

    for (err, s, t, p) in combined_curve
        err > eue_tol && break
        delete!(keepers[t,p], s)
    end

    for p in 1:n_periods, t in 1:t_per_period

        curve_keepers = collect(keepers[t,p])

        all_slopes = estimator.estimators[p].slopes[r,t]
        estimator.estimators[p].slopes[r,t] = all_slopes[curve_keepers]

        all_ints = estimator.estimators[p].intercepts[r,t]
        estimator.estimators[p].intercepts[r,t] = all_ints[curve_keepers]

    end

end

function compress_estimator(
    ints::Vector{Float64}, slopes::Vector{Float64}, errorlimit::Float64=Inf)

    n_segments = length(ints)
    included = BitSet(1:n_segments)

    candidates = Pair{Float64,Int}[]
    maxerrors = Float64[]
    removal_order = Int[]

    # TODO: There's a lot of repeated work here, we should cache max_errs &
    # invalidate when neighbors are removed

    while length(included) > 1

        for segment_idx in included
            max_err = new_maxerror(ints, slopes, included, segment_idx)
            push!(candidates, max_err => segment_idx)
        end

        max_err, idx = minimum(candidates)
        empty!(candidates)

        max_err > errorlimit && break

        delete!(included, idx)
        push!(removal_order, idx)
        push!(maxerrors, max_err)

    end

    keep = collect(included)
    sort!(keep)

    return ints[keep], slopes[keep], removal_order, maxerrors

end

function compress_estimators(
    ints::Matrix{Vector{Float64}}, slopes::Matrix{Vector{Float64}},
    errorlimit::Float64=Inf)

    daylength, n_periods = size(ints)

    size(slopes) == size(ints) ||
        error("Number of curves must match between slopes and intercepts")

    result = Tuple{Float64,Int,Int,Int}[]

    for p in 1:n_periods, t in 1:daylength
        _, _, segment_idxs, maxerrors = compress_estimator(ints[t,p], slopes[t,p])
        append!(result, tuple.(maxerrors, segment_idxs, t, p))
    end

    sort!(result)

    return result

end

compress_estimators(
    ints::Vector{Vector{Float64}}, slopes::Vector{Vector{Float64}},
    errorlimit::Float64=Inf) =
    compress_estimators(reshape(ints, :, 1), reshape(slopes, :, 1), errorlimit)

"""
Calculate error between "true" value and compressed curve at
intersection of nearest non-removed segments on each side of candidate
"""
function new_maxerror(
    ints::Vector{Float64}, slopes::Vector{Float64},
    included::BitSet, candidate_segment::Int)

    n_segments = length(ints)

    length(slopes) == n_segments ||
        error("Number of slopes and intercepts must match")

    1 <= candidate_segment <= n_segments ||
        error("Invalid removal candidate index")

    (n_segments > 1 && length(included) > 1) ||
        error("At least two segments are required to consider removals")

    candidate_segment in included ||
        error("The removal candidate must not already be removed")

    next_segment = next_idx(included, candidate_segment, n_segments)
    prev_segment = prev_idx(included, candidate_segment)

    if isnothing(prev_segment)

        max_error_x = ints[next_segment] / slopes[next_segment]

        return ints[candidate_segment] - slopes[candidate_segment] * max_error_x

    elseif isnothing(next_segment)

        return ints[candidate_segment] - ints[prev_segment]

    else

        int_prev, int, int_next =
            ints[[prev_segment, candidate_segment, next_segment]]

        slope_prev, slope, slope_next =
            slopes[[prev_segment, candidate_segment, next_segment]]

        max_error_x = (int_prev - int_next) / (slope_prev - slope_next)
        removed_y = int_prev - slope_prev * max_error_x
        true_y = int - slope * max_error_x

        return true_y - removed_y

    end

end

function total_error_curve(steps::Vector{Tuple{Float64,Int,Int,Int}}, n_curves::Int)

    n_timesteps = 0
    n_periods = 0

    for (_, _, curve_timestep_idx, curve_period_idx) in steps
        n_periods = max(n_periods, curve_period_idx)
        n_timesteps = max(n_timesteps, curve_timestep_idx)
    end

    max_err = zeros(n_timesteps, n_periods)
    total_err = similar(steps, Float64)

    for (i, (err, _, t, p)) in enumerate(steps)
        max_err[t, p] = err
        total_err[i] = sum(max_err)
    end

    return total_err

end

function prev_idx(included::BitSet, i0::Int)
    i = i0 - 1
    while i ∉ included
        i -= 1
        i < 1 && return nothing
    end
    return i
end

function next_idx(included::BitSet, i0::Int, imax::Int)
    i = i0 + 1
    while i ∉ included
        i += 1
        i > imax && return nothing
    end
    return i
end
