function SystemParams(datadir::String)

    name = basename(datadir)

    regions, timesteps = load_regions(datadir)
    interfaces = load_interfaces(datadir, regions)

    system = SystemParams(name, timesteps, regions, interfaces)

    load_thermaltechs!(system, datadir)
    load_thermalsites!(system, datadir)

    load_variabletechs!(system, datadir)
    load_variablesites!(system, datadir)

    load_storagetechs!(system, datadir)
    load_storagesites!(system, datadir)

    return system

end

function load_regions(datadir::String)

    regionpath = joinpath(datadir, "regions.csv")
    data = readdlm(regionpath, ',')

    timestamps_raw = DateTime.(data[2:end, 1], dateformat"y-m-dTH:M:S.s")
    timestamps = first(timestamps_raw):Hour(1):last(timestamps_raw)

    timestamps == timestamps_raw ||
        error("Input timesteps should be hourly")

    regions = RegionParams[]
    regionnames = Set{String}()

    for c in 2:size(data, 2)

        regionname = String(data[1, c])
        demand = Float64.(data[2:end, c]) / powerunits_MW

        regionname in regionnames &&
            error("Region name $regionname is duplicated in $regionpath")

        region = RegionParams(
            regionname, demand,
            ThermalParams[],
            VariableParams[],
            StorageParams[],
            Int[], Int[] # Region indices
        )

        push!(regionnames, regionname)
        push!(regions, region)

    end

    return regions, timestamps

end

function load_interfaces(datadir::String, regions::Vector{RegionParams})

    data = readdlm(joinpath(datadir, "transmission.csv"), ',')
    interfaces = InterfaceParams[]

    for i in 2:size(data, 1)

        iface_idx = i-1

        name = string(data[i,1])
        region_from = string(data[i,2])
        region_to = string(data[i,3])
        cost_capital = Float64(data[i,4]) * powerunits_MW
        capacity_existing = Float64(data[i,5]) / powerunits_MW
        capacity_new_max = Float64(data[i,6]) / powerunits_MW

        from_idx, region_from = getbyname(regions, region_from)
        to_idx, region_to = getbyname(regions, region_to)

        interface = InterfaceParams(
            name, from_idx, to_idx, cost_capital,
            capacity_existing, capacity_new_max)

        push!(region_from.export_interfaces, iface_idx)
        push!(region_to.import_interfaces, iface_idx)
        push!(interfaces, interface)

    end

    return interfaces

end

function load_thermaltechs!(system::SystemParams, datadir::String)

    regions = regionset(system)
    techspath = joinpath(datadir, "thermal/regiontechs.csv")
    validator = AddValidator{String}("region", regions, "tech", techspath)
    techs = readdlm(techspath, ',')

    for r in 2:size(techs, 1)

        regionname = string(techs[r, 1])
        techname = string(techs[r, 2])

        validate!(validator, regionname, techname)

        cost_capital = Float64(techs[r, 3]) * powerunits_MW
        cost_generation = Float64(techs[r, 4]) * powerunits_MW
        size = techs[r, 5] / powerunits_MW

        tech = ThermalParams(
            techname, cost_capital, cost_generation, size, ThermalSiteParams[])

        _, region = getbyname(system.regions, regionname)
        push!(region.thermaltechs, tech)

    end

end

function load_thermalsites!(system::SystemParams, datadir::String)

    n_timesteps = length(system.timesteps)

    regiontechs = regiontechset(system, ThermalParams)
    sitespath = joinpath(datadir, "thermal/sites.csv")
    validator = AddValidator{String}(
        "region-technology pair", regiontechs, "site", sitespath)

    sites = readdlm(sitespath, ',')

    for r in 2:size(sites, 1)

        regionname = string(sites[r, 1])
        techname = string(sites[r, 2])
        sitename = string(sites[r, 3])

        validate!(validator, (regionname, techname), sitename)

        units_existing = Int(sites[r, 4])
        units_new_max = Int(sites[r, 5])

        site = ThermalSiteParams(
            sitename, units_existing, units_new_max,
            zeros(n_timesteps), ones(n_timesteps))

        tech = get_tech(system, ThermalParams, regionname, techname)
        push!(tech.sites, site)

    end

    mttfpath = joinpath(datadir, "thermal/mttf.csv")
    load_sites_timeseries!(system, ThermalParams, mttfpath, :λ, x -> 1/x)

    mttrpath = joinpath(datadir, "thermal/mttr.csv")
    load_sites_timeseries!(system, ThermalParams, mttrpath, :μ, x -> 1/x)

end

function load_variabletechs!(system::SystemParams, datadir::String)

    regions = regionset(system)
    techspath = joinpath(datadir, "variable/regiontechs.csv")
    validator = AddValidator{String}("region", regions, "tech", techspath)

    techs = readdlm(techspath, ',')

    for r in 2:size(techs, 1)

        regionname = string(techs[r, 1])
        techname = string(techs[r, 2])

        validate!(validator, regionname, techname)

        cost_capital = Float64(techs[r, 3]) * powerunits_MW
        cost_generation = Float64(techs[r, 4]) * powerunits_MW

        tech = VariableParams(
            techname, cost_capital, cost_generation, VariableSiteParams[])

        _, region = getbyname(system.regions, regionname)
        push!(region.variabletechs, tech)

    end

end

function load_variablesites!(system::SystemParams, datadir::String)

    n_timesteps = length(system.timesteps)

    regiontechs = regiontechset(system, VariableParams)
    sitespath = joinpath(datadir, "variable/sites.csv")
    validator = AddValidator{String}(
        "region-technology pair", regiontechs, "site", sitespath)

    sites = readdlm(sitespath, ',')

    for r in 2:size(sites, 1)

        regionname = string(sites[r, 1])
        techname = string(sites[r, 2])
        sitename = string(sites[r, 3])

        validate!(validator, (regionname, techname), sitename)

        capacity_existing = Float64(sites[r, 4]) / powerunits_MW
        capacity_new_max = Float64(sites[r, 5]) / powerunits_MW

        site = VariableSiteParams(
            sitename, capacity_existing, capacity_new_max,
            zeros(n_timesteps))

        tech = get_tech(system, VariableParams, regionname, techname)
        push!(tech.sites, site)

    end

    availabilitiespath = joinpath(datadir, "variable/availability.csv")
    load_sites_timeseries!(system, VariableParams, availabilitiespath, :availability)

end

function load_storagetechs!(system::SystemParams, datadir::String)

    regions = regionset(system)
    techspath = joinpath(datadir, "storage/regiontechs.csv")
    validator = AddValidator{String}("region", regions, "tech", techspath)

    techs = readdlm(techspath, ',')

    for r in 2:size(techs, 1)

        regionname = string(techs[r, 1])
        techname = string(techs[r, 2])

        validate!(validator, regionname, techname)

        cost_capital_power = Float64(techs[r, 3]) * powerunits_MW
        cost_capital_energy = Float64(techs[r, 4]) * powerunits_MW
        cost_operation = Float64(techs[r, 5]) * powerunits_MW
        roundtrip_efficiency = Float64(techs[r, 6])

        tech = StorageParams(
            techname, cost_capital_power, cost_capital_energy, cost_operation,
            roundtrip_efficiency, StorageSiteParams[])

        _, region = getbyname(system.regions, regionname)
        push!(region.storagetechs, tech)

    end

end

function load_storagesites!(system::SystemParams, datadir::String)

    regiontechs = regiontechset(system, StorageParams)
    sitespath = joinpath(datadir, "storage/sites.csv")
    validator = AddValidator{String}(
        "region-technology pair", regiontechs, "site", sitespath)

    sites = readdlm(sitespath, ',')

    for r in 2:size(sites, 1)

        regionname = string(sites[r, 1])
        techname = string(sites[r, 2])
        sitename = string(sites[r, 3])

        validate!(validator, (regionname, techname), sitename)

        power_existing = Float64(sites[r, 4]) / powerunits_MW
        power_new_max = Float64(sites[r, 5]) / powerunits_MW

        energy_existing = Float64(sites[r, 6]) / powerunits_MW
        energy_new_max = Float64(sites[r, 7]) / powerunits_MW

        site = StorageSiteParams(
            sitename, power_existing, power_new_max,
            energy_existing, energy_new_max)

        tech = get_tech(system, StorageParams, regionname, techname)
        push!(tech.sites, site)

    end

end

function load_sites_timeseries!(
    system::SystemParams, techtype::Type{<:Technology},
    datapath::String, field::Symbol, transformer::Function=identity
)

    validator = UpdateValidator(
        "region-technology-site triple ",
        datapath,
        regiontechsiteset(system, techtype)
    )

    data = readdlm(datapath, ',')

    timesteps = DateTime.(data[4:end, 1], dateformat"y-m-dTH:M:S.s")
    timesteps == system.timesteps ||
        error("Timestamps in $datapath are not consistent with demand data")

    for c in 2:size(data, 2)

        regionname = string(data[1, c])
        techname = string(data[2, c])
        sitename = string(data[3, c])

        validate!(validator, (regionname, techname, sitename))

        site = get_site(
            system, techtype, regionname, techname, sitename)

        getfield(site, field) .= transformer.(Float64.(data[4:end, c]))

    end

end
