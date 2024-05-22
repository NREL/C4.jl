function estimator_compression(ints::Vector{Float64}, slopes::Vector{Float64}, max_error::Float64)
    return reduced_ints, reduced_slopes
end


function removal_candidates(ints::Vector{Float64}, slopes::Vector{Float64})

    n_segments = length(ints)

    length(slopes) == n_segments || error("Number of slopes and intercepts must match")

    # We need at least two segments to consider removing any
    n_segments < 2 && return Pair{Int,Float64}[]

    max_error = similar(ints)

    max_error_x = ints[2] / slopes[2]
    max_error[1] = ints[1] - slopes[1] * max_error_x

    for i in 2:(n_segments-1)

        int_prev, int, int_next = ints[(i-1):(i+1)]
        slope_prev, slope, slope_next = slopes[(i-1):(i+1)]

        max_error_x = (int_prev - int_next) / (slope_prev - slope_next)
        removed_y = int_prev - slope_prev * max_error_x
        true_y = int - slope * max_error_x
        max_error[i] = true_y - removed_y

    end

    max_error[n_segments] = ints[n_segments] - ints[n_segments-1]

    candidates = Pair{Float64,Int}[]
    already_removed = BitSet()

    # Potential performance improvement: for a tranche of equal-maxerror segments,
    # remove the largest non-sequential subset instead of stopping at the first
    # adjacent segment found. Logic might be overly complicated though.
    # Current approach becomes one-at-a-time removal/recalculation in worst case,
    # which still works (but is slower than necessary)

    for i in sortperm(max_error)

        prev_removed = i-1 in already_removed
        next_removed = i+1 in already_removed

        (prev_removed || next_removed) && break

        push!(candidates, max_error[i]=>i)
        push!(already_removed, i)

    end

    return candidates

end
