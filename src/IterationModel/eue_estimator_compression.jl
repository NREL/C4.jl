# TODO: None of this code is optimized, revisit if needed

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
    ints::Vector{Vector{Float64}}, slopes::Vector{Vector{Float64}},
    errorlimit::Float64=Inf)

    n_curves = length(ints)

    length(slopes) == n_curves ||
        error("Number of curves must match between slopes and intercepts")

    result = Tuple{Float64,Int,Int}[]

    for i in 1:n_curves
        _, _, removal_order, maxerrors = compress_estimator(ints[i], slopes[i])
        append!(result, tuple.(maxerrors, i, removal_order))
    end

    sort!(result)

    # TODO: Map back to individual curves that respect the joint error limit

    return result

end

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

function total_error_curve(steps::Vector{Tuple{Float64,Int,Int}}, n_curves::Int)

    max_err = zeros(n_curves)
    total_err = similar(steps, Float64)

    for (i, (err, curve_idx, segment_idx)) in enumerate(steps)
        max_err[curve_idx] = err
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
