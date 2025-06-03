module IterationModel

using C4.Data
using C4.AdequacyModel
using C4.DispatchModel
using C4.ExpansionModel

import ..store, ..powerunits_MW
import C4.ExpansionModel: RiskEstimateParams, RiskEstimatePeriodParams,
                          RiskEstimatePlaneParams, ThermalTechRiskEstimateParams,
                          ThermalSiteRiskEstimateParams
import C4.AdequacyModel: ThermalRegionUnitCount, ThermalRegionAdequacyImpact,
                         ThermalTechUnitCount, ThermalTechAdequacyImpact,
                         ThermalSiteUnitCount, ThermalSiteAdequacyImpact

import Base: +
import Dates: Date, now
import DBInterface
import DelimitedFiles: writedlm
import DuckDB
import JuMP: value
import PRAS: EUE, NEUE, val

export iterate_ra_cem

function iterate_ra_cem(
    sys::SystemParams, base_chronology::TimeProxyAssignment,
    max_neues::Vector{Float64}, optimizer;
    nsamples::Int=1000, skip_existing_stress_periods::Bool=false,
    timeout::Float64=Inf, first_feasible::Bool=true,
    aspp::Bool=true, endog_risk::Bool=true, outfile::String="",
    check_dispatch::Bool=false)

    persist = length(outfile) > 0
    max_neue = maximum(max_neues)
    timeout += time()

    neue_factors = [sum(region.demand) * 1e-6 for region in sys.regions]
    max_eues = max_neues .* neue_factors

    n_regions = length(sys.regions)

    adequacy_results = AdequacyContext[]

    ram_start = now()
    ram = AdequacyProblem(sys, samples=nsamples)
    ram_result = solve(ram)
    push!(adequacy_results, AdequacyContext(sys, ram_result))
    ram_end = now()

    show_neues(ram_result)

    aug_start = now()

    chronology = if aspp
        add_stressperiod(sys, base_chronology, ram_result,
                         skip_existing=skip_existing_stress_periods)
    else
        base_chronology
    end

    eue_estimator = if endog_risk
        RiskEstimateParams(chronology, adequacy_results)
    else
        nullestimator(chronology, n_regions)
    end

    aug_end = now()

    if persist
        store_start = now()
        con = DBInterface.connect(DuckDB.DB, outfile)
        store(con, sys)
        store_iteration(con, 0)
        store_iteration_step(con, 0, "adequacy", ram_start => ram_end)
        store(con, 0, ram_result)
        store_iteration_step(con, 0, "augmentation", aug_start => aug_end)
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
        ram_result = solve(ram)
        push!(adequacy_results, AdequacyContext(cem, ram_result))
        ram_end = now()

        show_neues(ram_result)

        is_adequate = all(region_neues(ram_result) .<= max_neues)

        aug_start = now()

        aspp && (chronology = add_stressperiod(sys, chronology, ram_result,
                                               skip_existing=skip_existing_stress_periods))

        eue_estimator = if endog_risk
            RiskEstimateParams(chronology, adequacy_results)
        else
            nullestimator(chronology, n_regions)
        end

        aug_end = now()

        if persist
            store_start = now()
            store_iteration(con, n_iters)
            store_iteration_step(con, n_iters, "expansion", cem_start => cem_end)
            store_iteration_step(con, n_iters, "adequacy", ram_start => ram_end)
            store_iteration_step(con, n_iters, "augmentation", aug_start => aug_end)
            store(con, n_iters, cem.builds)
            store(con, n_iters, cem.economicdispatch)
            store(con, n_iters, ram_result)
            DBInterface.execute(con, "CHECKPOINT")
            store_end = now()
            store_iteration_step(con, n_iters, "persistence", store_start => store_end)
            DBInterface.execute(con, "CHECKPOINT")
        end

        prev_cem = cem

        first_feasible && is_adequate && break

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

function add_stressperiod(
    sys::SystemParams, times::TimeProxyAssignment, adequacy::AdequacyResult;
    skip_existing::Bool=false
)

    eues = sum(adequacy.shortfalls.shortfall_mean, dims=1)
    days = reshape(eues, times.daylength, :)
    days = vec(sum(days, dims=1))
    og_new_day = argmax(days)

    new_day = og_new_day
    new_day_first_hour = (new_day - 1) * times.daylength + 1

    while already_included(new_day_first_hour, times.periods)

        skip_existing && return times

        new_day = new_day > 1 ? new_day - 1 : length(days)
        new_day_first_hour = (new_day - 1) * times.daylength + 1

        if new_day == og_new_day
            @warn("No unmodeled stress periods left to add")
            return times
        end

    end

    ts = new_day_first_hour:(new_day_first_hour+times.daylength-1)
    name = string(Date(sys.timesteps[new_day_first_hour]))
    new_period = TimePeriod(ts, name)
    println("Adding period: $name")

    new_periods = [times.periods; new_period]

    new_days = copy(times.days)
    new_days[new_day] = length(new_periods)

    return TimeProxyAssignment(new_periods, new_days)

end

already_included(hour::Int, periods::Vector{TimePeriod}) =
    any(p -> in(hour, p.timesteps), periods)

function RiskEstimateParams(
    time::TimeProxyAssignment, results::Vector{AdequacyContext})

    period_params = [
        RiskEstimatePeriodParams(results, time, p)
        for p in eachindex(time.periods)
    ]

    return RiskEstimateParams(time, period_params)

end

function RiskEstimatePeriodParams(
    adequacycontexts::Vector{AdequacyContext},
    time::TimeProxyAssignment,
    p::Int
)

    R = length(first(adequacycontexts).thermal_units)
    T = time.daylength
    J = length(adequacycontexts)

    representative_ts = time.periods[p].timesteps
    represented_ts = represented_timeslices(time, p)

    thermalparams = Matrix{Vector{ThermalTechRiskEstimateParams}}(undef, R, T)
    planes = Array{RiskEstimatePlaneParams,3}(undef, R, T, J)

    for (j, adequacycontext) in enumerate(adequacycontexts)

        shortfalls = adequacycontext.adequacy.shortfalls

        nonthermal_availablecapacity =
            adequacycontext.variable_availability[:, representative_ts] +
            adequacycontext.adequacy.storage_offset[:, representative_ts] +
            adequacycontext.adequacy.transmission_offset[:, representative_ts]

        base_eue = zeros(R,T)
        nonthermal_dEUE = zeros(R,T)

        for ts in represented_ts
            base_eue .+= shortfalls.shortfall_mean[:, ts] ./ powerunits_MW
            nonthermal_dEUE .+= shortfalls.eventperiod_regionperiod_mean[:, ts]
        end

        for r in 1:R

            aggregate_impacts = ThermalRegionAdequacyImpact(
                adequacycontext.adequacy.thermalimpacts[r], time, p)

            for t in 1:T
                thermalparams[r,t] = riskparams(
                    adequacycontext.thermal_units[r],
                    aggregate_impacts, base_eue, r, t)
            end

        end

        planes[:,:,j] .= RiskEstimatePlaneParams.(
            base_eue, nonthermal_availablecapacity,
            nonthermal_dEUE, thermalparams)

    end

    return planes

end

riskparams(
    unitcounts::AdequacyModel.ThermalRegionUnitCount,
    adequacyimpact::ThermalRegionAdequacyImpact,
    base_eue::Matrix{Float64}, r::Int, t::Int
) = riskparams.(unitcounts.techs, adequacyimpact.techs, Ref(base_eue), r, t)

riskparams(
    unitcounts::AdequacyModel.ThermalTechUnitCount,
    adequacyimpact::ThermalTechAdequacyImpact,
    base_eue::Matrix{Float64}, r::Int, t::Int
) = ThermalTechRiskEstimateParams(
    riskparams.(unitcounts.sites, adequacyimpact.sites, Ref(base_eue), r, t))

riskparams(
    unitcount::AdequacyModel.ThermalSiteUnitCount,
    adequacyimpact::ThermalSiteAdequacyImpact,
    base_eue::Matrix{Float64}, r::Int, t::Int
) = ThermalSiteRiskEstimateParams(unitcount.units, base_eue[r,t] - adequacyimpact.eue[r,t])

"""
Collapse a full chronology ThermalRegionAdequacyImpact down into an aggregated
ThermalRegionAdequacyImpact, for a specific period p from the provided
TimeProxyAssignment
"""
ThermalRegionAdequacyImpact(
    region::ThermalRegionAdequacyImpact, time::TimeProxyAssignment, p::Int
) = sum(extract_timeslice(region, ts) for ts in represented_timeslices(time, p))

extract_timeslice(region::ThermalRegionAdequacyImpact, ts::UnitRange{Int}) =
    ThermalRegionAdequacyImpact(extract_timeslice.(region.techs, Ref(ts)))

extract_timeslice(tech::ThermalTechAdequacyImpact, ts::UnitRange{Int}) =
    ThermalTechAdequacyImpact(extract_timeslice.(tech.sites, Ref(ts)))

extract_timeslice(site::ThermalSiteAdequacyImpact, ts::UnitRange{Int}) =
    ThermalSiteAdequacyImpact(site.eue[:, ts])

+(s1::ThermalRegionAdequacyImpact, s2::ThermalRegionAdequacyImpact) =
    ThermalRegionAdequacyImpact(s1.techs + s2.techs)

+(s1::ThermalTechAdequacyImpact, s2::ThermalTechAdequacyImpact) =
    ThermalTechAdequacyImpact(s1.sites + s2.sites)

+(s1::ThermalSiteAdequacyImpact, s2::ThermalSiteAdequacyImpact) =
    ThermalSiteAdequacyImpact(s1.eue + s2.eue)

function represented_timeslices(time::TimeProxyAssignment, p::Int)
    T = time.daylength
    return [((d-1)*T+1):(d*T) for d in findall(isequal(p), time.days)]
end

end
