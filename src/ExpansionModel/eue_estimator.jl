struct PeriodEUEEstimator

    intercepts::Matrix{Vector{Float64}}
    slopes::Matrix{Vector{Float64}}

    function PeriodEUEEstimator(
        intercepts::Matrix{Vector{Float64}}, slopes::Matrix{Vector{Float64}}
    )

        size(intercepts) == size(slopes) ||
            error("Mismatched count of EUE estimators")

        all(length.(intercepts) .== length.(slopes)) ||
            error("Mismatched count of EUE estimator segments")

        new(intercepts, slopes)

    end

end

n_segments(estimators::PeriodEUEEstimator, r::Int, t::Int) =
    length(estimators.intercepts[r,t])

intercept(estimators::PeriodEUEEstimator, r::Int, t::Int, s::Int) =
    estimators.intercepts[r,t][s]

slope(estimators::PeriodEUEEstimator, r::Int, t::Int, s::Int) =
    estimators.slopes[r,t][s]

struct EUEEstimator # TODO: Naming

    times::TimeProxyAssignment
    estimators::Vector{PeriodEUEEstimator}

    function EUEEstimator(
        times::TimeProxyAssignment, estimators::Vector{PeriodEUEEstimator}
    )

        length(times.periods) == length(estimators) ||
            error("Mismatched count of dispatch periods and EUE estimators")

        new(times, estimators)

    end

end

# TODO: Could implement iterator interface here for slightly nicer usage
allperiods(ee::EUEEstimator) =
    [(period, ee.estimators[i]) for (i, period) in enumerate(ee.times.periods)]

function nullestimator(system::SystemParams, times::TimeProxyAssignment)

    zero_matrix = fill([0.], length(system.regions), times.daylength)

    estimators = [PeriodEUEEstimator(zero_matrix, zero_matrix)
                  for period in times.periods]

    return EUEEstimator(times, estimators)

end
