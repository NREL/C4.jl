
struct AdequacyProblem

    sys::SystemParams
    prassys::SystemModel
    samples::Int

    # neue::Float64
    # neue_stderr::Float64
    # region_neue::Vector{Float64}
    # period_eue::Vector{Float64}
    # surplus_mean::Matrix{Float64}
    # shortfall_samples::Array{Float64,3}

    # eue::Float64
    # eue_std::Float64
    # lole::Float64
    # lole_std::Float64

    # region_eues::Vector{Float64}
    # region_eue_stds::Vector{Float64}
    # region_loles::Vector{Float64}
    # region_lole_stds::Vector{Float64}

    function AdequacyProblem(sys::SystemParams; samples::Int)

        n_periods = length(sys.timesteps)
        meta = (N=n_periods, L=1, T=Hour, P=MW, E=MWh)

        regions = load_regions(sys, meta)
        n_regions = length(regions)

        generators, region_gen_idxs = load_generators(sys, meta)
        storages, region_stor_idxs = load_storages(sys, meta)
        generatorstorages, region_genstor_idxs = load_generatorstorages(sys, meta)

        interfaces, lines, interface_line_idxs = load_transmission(sys, meta)

        prassys = SystemModel(
            regions, interfaces, generators, region_gen_idxs,
            storages, region_stor_idxs, generatorstorages, region_genstor_idxs,
            lines, interface_line_idxs, sys.timesteps)

        return new(sys, prassys, samples)

    end

end

function load_regions(sys::SystemParams, meta)

    names = [r.name for r in sys.regions]
    load = zeros(Int, length(sys.regions), meta.N)

    for (r, region) in enumerate(sys.regions)
        load[r, :] = round.(Int, region.demand .* powerunits_MW)
    end

    return Regions{meta.N, meta.P}(names, load)

end

function load_generators(sys::SystemParams, meta)

    n_regions = length(sys.regions)
    n_gens, has_variable = count_gens(sys)

    region_gen_idxs = Vector{UnitRange{Int}}(undef, n_regions)

    names = Vector{String}(undef, n_gens)
    categories = Vector{String}(undef, n_gens)
    capacity = zeros(Int, n_gens, meta.N)
    lambda = Matrix{Float64}(undef, n_gens, meta.N)
    mu = Matrix{Float64}(undef, n_gens, meta.N)

    g_last = 0

    for (r, region) in enumerate(sys.regions)

        g_first = g_last + 1

        for tech in region.thermaltechs
            for site in tech.sites
                sitename = join([region.name, tech.name, site.name], "_")
                for i in 1:site.units_existing
                    g_last += 1
                    names[g_last] = sitename * "_$i"
                    categories[g_last] = tech.name
                    capacity[g_last, :] .= round.(Int, tech.unit_size .* powerunits_MW)
                    lambda[g_last, :] .= site.λ
                    mu[g_last, :] .= site.μ
                end
            end
        end

        if has_variable[r]

            g_last += 1
            names[g_last] = region.name * " VRE"
            categories[g_last] = "VRE"
            lambda[g_last, :] .= 0.
            mu[g_last, :] .= 1.

            for tech in region.variabletechs
                for site in tech.sites
                    capacity[g_last, :] .+=
                        round.(Int, site.capacity_existing .* powerunits_MW .* site.availability)
                end
            end

        end

        region_gen_idxs[r] = g_first:g_last

    end

    generators = Generators{meta.N, meta.L, meta.T, meta.P}(
        names, categories, capacity, lambda, mu)

    return generators, region_gen_idxs

end

"""
Counts the number of PRAS generators in the system.
Each unit of a thermal tech counts as a new generator, while
VRE across all techs and sites within a region is pooled.
"""
function count_gens(sys::SystemParams)

    n_gens = 0
    has_variable = zeros(Bool, length(sys.regions))

    for (r, region) in enumerate(sys.regions)

        for tech in region.thermaltechs
            for site in tech.sites
                n_gens += site.units_existing
            end
        end

        for tech in region.variabletechs
            has_variable[r] && break
            for site in tech.sites
                if site.capacity_existing > 0
                    has_variable[r] = true
                    break
                end
            end
        end

        n_gens += has_variable[r]

    end

    return n_gens, has_variable

end

function load_storages(sys::SystemParams, meta)

    n_regions = length(sys.regions)
    n_stors = count_stors(sys)

    region_stor_idxs = Vector{UnitRange{Int}}(undef, n_regions)

    names = Vector{String}(undef, n_stors)
    categories = Vector{String}(undef, n_stors)
    power_capacity = Matrix{Int}(undef, n_stors, meta.N)
    energy_capacity = Matrix{Int}(undef, n_stors, meta.N)
    oneway_efficiency = Matrix{Float64}(undef, n_stors, meta.N)

    allones = ones(n_stors, meta.N)
    allzeros = zeros(n_stors, meta.N)

    s_last = 0

    for (r, region) in enumerate(sys.regions)

        s_first = s_last + 1

        for tech in region.storagetechs
            efficiency = sqrt(tech.roundtrip_efficiency)
            for site in tech.sites
                sitename = join([region.name, tech.name, site.name], "_")
                if site.power_existing > 0 && site.energy_existing > 0
                    s_last += 1
                    names[s_last] = sitename
                    categories[s_last] = tech.name
                    power_capacity[s_last, :] .= round(Int, site.power_existing .* powerunits_MW)
                    energy_capacity[s_last, :] .= round(Int, site.energy_existing .* powerunits_MW)
                    oneway_efficiency[s_last, :] .= efficiency
                end
            end
        end

        region_stor_idxs[r] = s_first:s_last

    end

    storages = Storages{meta.N, meta.L, meta.T, meta.P, meta.E}(
        names, categories,
        power_capacity, power_capacity, energy_capacity,
        oneway_efficiency, oneway_efficiency, allones, allzeros, allones)

    return storages, region_stor_idxs

end

function count_stors(sys::SystemParams)
    n_stors = 0
    for region in sys.regions
        for tech in region.storagetechs
            for site in tech.sites
                if site.power_existing > 0 && site.energy_existing > 0
                    n_stors += 1
                end
            end
        end
    end
    return n_stors
end

function load_generatorstorages(sys::SystemParams, meta)

    intvals = zeros(Int, 0, meta.N)
    fltvals = zeros(Float64, 0, meta.N)

    generatorstorages =
        GeneratorStorages{meta.N, meta.L, meta.T, meta.P, meta.E}(
        String[], String[],
        intvals, intvals, intvals, fltvals, fltvals, fltvals,
        intvals, intvals, intvals, fltvals, fltvals)

    region_genstor_idxs = fill(1:0, length(sys.regions))

    return generatorstorages, region_genstor_idxs

end

function load_transmission(sys::SystemParams, meta)

    n_ifaces = length(sys.interfaces)

    names = Vector{String}(undef, n_ifaces)
    from = Vector{Int}(undef, n_ifaces)
    to = Vector{Int}(undef, n_ifaces)
    capacity = Matrix{Int}(undef, n_ifaces, meta.N)

    lambda = zeros(Float64, n_ifaces, meta.N)
    mu = ones(Float64, n_ifaces, meta.N)

    interface_line_idxs = Vector{UnitRange{Int}}(undef, n_ifaces)

    for (i, iface) in enumerate(sys.interfaces)

        region_from = sys.regions[iface.region_from]
        region_to = sys.regions[iface.region_to]
        names[i] = region_from.name * " -> " * region_to.name
        capacity[i, :] .= round(Int, iface.capacity_existing .* powerunits_MW)

        # Sort indices since PRAS requires from_idx < to_idx
        # Note: this would generally be dangerous, but no problem here since line limits are always symmetrical
        from[i], to[i] = minmax(iface.region_from, iface.region_to)

        interface_line_idxs[i] = i:i

    end

    interfaces = Interfaces{meta.N, meta.P}(
        from, to, capacity, capacity)

    lines = Lines{meta.N, meta.L, meta.T, meta.P}(
        names, names, capacity, capacity, lambda, mu)

    return interfaces, lines, interface_line_idxs

end
