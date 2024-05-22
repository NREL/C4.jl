function estimator_compression(ints::Vector{Float64}, slopes::Vector{Float64}, max_error::Float64)
    return reduced_ints, reduced_slopes
end

function removal_candidates(ints::Vector{Float64}, slopes::Vector{Float64})

    n_segments = length(ints)

    length(slopes) == n_segments || error("Number of slopes and intercepts must match")

    # We need at least two segments to consider removing any
    n_segments > 1 || return Pair{Int,Float64}[]

    included = BitSet(1:n_segments)
    maxerrors = new_maxerror.(Ref(ints), Ref(slopes), Ref(included), 1:n_segments)

    candidates = Pair{Float64,Int}[]
    already_removed = BitSet()

    # Potential performance improvement: for a tranche of equal-maxerror segments,
    # remove the largest non-sequential subset instead of stopping at the first
    # adjacent segment found. Logic might be overly complicated though.
    # Current approach becomes one-at-a-time removal/recalculation in worst case,
    # which still works (but is slower than necessary)

    for i in sortperm(maxerrors)

        prev_removed = i-1 in already_removed
        next_removed = i+1 in already_removed

        (prev_removed || next_removed) && break

        push!(candidates, maxerrors[i]=>i)
        push!(already_removed, i)

    end

    return candidates

end


function new_maxerror(
    ints::Vector{Float64}, slopes::Vector{Float64},
    included::BitSet, candidate_segment::Int)

    # Calculate error between "true" value and compressed curve at
    # intersection of nearest non-removed segments on each side of candidate

    n_segments = length(ints)

    length(slopes) == n_segments ||
        error("Number of slopes and intercepts must match")

    1 <= candidate_segment <= n_segments ||
        error("Invalid removal candidate index")

    (n_segments > 1 && length(included) > 1) ||
        error("At least two segments are required to consider removals")

    candidate_segment in included ||
        error("The removal candidate must not already be removed")

    if candidate_segment == 1

        next_segment = next_idx(included, candidate_segment, n_segments)
        max_error_x = ints[next_segment] / slopes[next_segment]

        return ints[candidate_segment] - slopes[candidate_segment] * max_error_x

    elseif candidate_segment == n_segments

        prev_segment = prev_idx(included, candidate_segment)

        return ints[candidate_segment] - ints[prev_segment]

    else

        next_segment = next_idx(included, candidate_segment, n_segments)
        prev_segment = prev_idx(included, candidate_segment)

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

function prev_idx(included::BitSet, i0::Int)
    i = i0 - 1
    while i ∉ included
        i -= 1
        i < 1 && error("No indices lower that $(i0)")
    end
    return i
end

function next_idx(included::BitSet, i0::Int, imax::Int)
    i = i0 + 1
    while i ∉ included
        i += 1
        i > imax && error("No indices higher than $(i0)")
    end
    return i
end
