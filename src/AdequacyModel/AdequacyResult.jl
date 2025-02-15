struct ThermalSiteAdequacyImpact
    eue::Matrix{Float64} # RxT
end

function ThermalSiteAdequacyImpact(
    site::ThermalSiteParams, prob::AdequacyProblem, r::Int, unitsize::Int
)

    eue = if iszero(site.units_new_max)

        # Don't bother getting gradients for sites where no expansion is possible
        R = length(prob.sys.regions)
        T = length(prob.sys.timesteps)
        fill(NaN, R, T)

    else

        simspec = SequentialMonteCarlo(samples=prob.samples, seed=1)
        augmented_sys = add_unit(prob.prassys, r, unitsize, site.λ, site.μ)
        sf, = assess(augmented_sys, simspec, Shortfall())
        sf.shortfall_mean ./ powerunits_MW

    end

    return ThermalSiteAdequacyImpact(eue)

end

struct ThermalTechAdequacyImpact
    sites::Vector{ThermalSiteAdequacyImpact} # per site
end

function ThermalTechAdequacyImpact(tech::ThermalParams, prob::AdequacyProblem, r::Int)
    unitsize = round(Int, tech.unit_size)
    return ThermalTechAdequacyImpact([
        ThermalSiteAdequacyImpact(site, prob, r, unitsize)
        for site in tech.sites])
end

struct ThermalRegionAdequacyImpact
    techs::Vector{ThermalTechAdequacyImpact} # per tech
end

ThermalRegionAdequacyImpact(region::RegionParams, prob::AdequacyProblem, r::Int) =
    ThermalRegionAdequacyImpact([
        ThermalTechAdequacyImpact(tech, prob, r) for tech in region.thermaltechs])

struct AdequacyResult

    # TODO: Since PRAS v0.7.1 this is redundant with shortfalls.regions.load, can be eliminated
    load::Matrix{Float64} # RxT demand

    # Positive is a net power injection into the region, negative is a net withdrawal
    storage_offset::Matrix{Float64} # RxT
    transmission_offset::Matrix{Float64} # RxT

    shortfalls::PRAS.PRASCore.Results.ShortfallResult

    thermalimpacts::Vector{ThermalRegionAdequacyImpact} # per region

end

function show_neues(result::AdequacyResult; regions::Bool=true)

    println("System\t", NEUE(result.shortfalls))

    for region in result.shortfalls.regions.names
        println(region, "\t", NEUE(result.shortfalls, region))
    end

end

region_neues(result::AdequacyResult) =
    [val(NEUE(result.shortfalls, region))
     for region in result.shortfalls.regions.names]

function solve(prob::AdequacyProblem)

    simspec = SequentialMonteCarlo(samples=prob.samples, seed=1)

    sf, fl, se = assess(prob.prassys, simspec, Shortfall(), Flow(), StorageEnergy())

    R = length(prob.prassys.regions)
    T = length(prob.prassys.timestamps)
    n_stors = length(prob.prassys.storages)

    net_stor_discharge = -diff([zeros(n_stors) se.energy_mean], dims=2) ./ powerunits_MW
    region_net_stor_discharge = aggregate(net_stor_discharge, prob.prassys.region_stor_idxs)

    region_net_import = zeros(Float64, R, T)
    for (i, (from, to)) in enumerate(zip(
            prob.prassys.interfaces.regions_from, prob.prassys.interfaces.regions_to))
        region_net_import[from, :] .-= fl.flow_mean[i, :] ./ powerunits_MW
        region_net_import[to, :] .+= fl.flow_mean[i, :] ./ powerunits_MW
    end

    thermalimpacts = [ThermalRegionAdequacyImpact(region, prob, r)
                 for (r, region) in enumerate(prob.sys.regions)]

    return AdequacyResult(
        prob.prassys.regions.load ./ powerunits_MW,
        region_net_stor_discharge, region_net_import,
        sf, thermalimpacts)

end

function add_unit(
    sys::PRAS.SystemModel{N,L,T,P},
    r::Int, unitsize::Int,
    λ::Vector{Float64}, μ::Vector{Float64}
) where {N, L, T, P}

    R = length(sys.regions)
    G = length(sys.generators)

    region_gen_idxs = copy(sys.region_gen_idxs)

    first_r_gen, last_r_gen = extrema(sys.region_gen_idxs[r])
    region_gen_idxs[r] = first_r_gen:(last_r_gen + 1)

    for i in (r+1):R
        region_gen_idxs[i] = sys.region_gen_idxs[i] .+ 1
    end

    generators = vcat(
        sys.generators[1:last_r_gen],
        PRAS.Generators{N,L,T,P}(
            ["_gradient_testunit"], ["_gradient_testunits"],
            fill(unitsize, 1, N), permutedims(λ), permutedims(μ)),
        sys.generators[(last_r_gen+1):G])

    return PRAS.SystemModel(sys.regions, sys.interfaces,
                            generators, region_gen_idxs,
                            sys.storages, sys.region_stor_idxs,
                            sys.generatorstorages, sys.region_genstor_idxs,
                            sys.lines, sys.interface_line_idxs,
                            sys.timestamps)

end

function aggregate(unit_vals::Matrix{Float64}, idxs::Vector{UnitRange{Int}})

    agg_vals = Matrix{Float64}(undef, length(idxs), size(unit_vals, 2))

    for (i, idx) in enumerate(idxs)
        agg_vals[i, :] = sum(unit_vals[idx, :], dims=1)
    end

    return agg_vals

end
