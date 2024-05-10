function System(datadir::String)

    name = basename(datadir)

    regions, timesteps = load_regions(datadir)
    interfaces = load_interfaces(datadir, regions)

    system = System(name, timesteps, regions, interfaces)

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

    regions = Region[]
    regionnames = Set{String}()

    for c in 2:size(data, 2)

        regionname = String(data[1, c])
        demand = Float64.(data[2:end, c])

        regionname in regionnames &&
            error("Region name $regionname is duplicated in $regionpath")

        region = Region(
            regionname, demand,
            ThermalTechnology[],
            VariableTechnology[],
            StorageTechnology[],
            Interface[], Interface[]
        )

        push!(regionnames, regionname)
        push!(regions, region)

    end

    return regions, timestamps

end

function load_interfaces(datadir::String, regions::Vector{Region})

    data = readdlm(joinpath(datadir, "transmission.csv"), ',')
    interfaces = Interface[]

    for i in 2:size(data, 1)

        iface_idx = i-1

        name = string(data[i,1])
        region_from = string(data[i,2])
        region_to = string(data[i,3])
        cost_capital = Float64(data[i,4])
        capacity_existing = Float64(data[i,5])
        capacity_new_max = Float64(data[i,6])

        from_idx, region_from = getbyname(regions, region_from)
        to_idx, region_to = getbyname(regions, region_to)

        interface = Interface(
            name, from_idx, to_idx, cost_capital,
            capacity_existing, capacity_new_max)

        push!(region_from.export_interfaces, iface_idx)
        push!(region_to.import_interfaces, iface_idx)
        push!(interfaces, interface)

    end

    return interfaces

end

function load_thermaltechs!(system::System, datadir::String)

    regions = regionset(system)
    techspath = joinpath(datadir, "thermal/regiontechs.csv")
    validator = AddValidator{String}("region", regions, "tech", techspath)
    techs = readdlm(techspath, ',')

    for r in 2:size(techs, 1)

        regionname = string(techs[r, 1])
        techname = string(techs[r, 2])

        validate!(validator, regionname, techname)

        cost_capital = Float64(techs[r, 3])
        cost_generation = Float64(techs[r, 4])
        size = Int(techs[r, 5])

        tech = ThermalTechnology(
            techname, cost_capital, cost_generation, size, ThermalSite[])

        _, region = getbyname(system.regions, regionname)
        push!(region.thermaltechs, tech)

    end

end

function load_thermalsites!(system::System, datadir::String)

    n_timesteps = length(system.timesteps)

    regiontechs = regiontechset(system, ThermalTechnology)
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

        site = ThermalSite(
            sitename, units_existing, units_new_max,
            zeros(n_timesteps), ones(n_timesteps))

        tech = get_tech(system, ThermalTechnology, regionname, techname)
        push!(tech.sites, site)

    end

    mttfpath = joinpath(datadir, "thermal/mttf.csv")
    load_sites_timeseries!(system, ThermalTechnology, mttfpath, :λ, x -> 1/x)

    mttrpath = joinpath(datadir, "thermal/mttr.csv")
    load_sites_timeseries!(system, ThermalTechnology, mttrpath, :μ, x -> 1/x)

end

function load_variabletechs!(system::System, datadir::String)

    regions = regionset(system)
    techspath = joinpath(datadir, "variable/regiontechs.csv")
    validator = AddValidator{String}("region", regions, "tech", techspath)

    techs = readdlm(techspath, ',')

    for r in 2:size(techs, 1)

        regionname = string(techs[r, 1])
        techname = string(techs[r, 2])

        validate!(validator, regionname, techname)

        cost_capital = Float64(techs[r, 3])
        cost_generation = Float64(techs[r, 4])

        tech = VariableTechnology(
            techname, cost_capital, cost_generation, VariableSite[])

        _, region = getbyname(system.regions, regionname)
        push!(region.variabletechs, tech)

    end

end

function load_variablesites!(system::System, datadir::String)

    n_timesteps = length(system.timesteps)

    regiontechs = regiontechset(system, VariableTechnology)
    sitespath = joinpath(datadir, "variable/sites.csv")
    validator = AddValidator{String}(
        "region-technology pair", regiontechs, "site", sitespath)

    sites = readdlm(sitespath, ',')

    for r in 2:size(sites, 1)

        regionname = string(sites[r, 1])
        techname = string(sites[r, 2])
        sitename = string(sites[r, 3])

        validate!(validator, (regionname, techname), sitename)

        capacity_existing = Float64(sites[r, 4])
        capacity_new_max = Float64(sites[r, 5])

        site = VariableSite(
            sitename, capacity_existing, capacity_new_max,
            zeros(n_timesteps))

        tech = get_tech(system, VariableTechnology, regionname, techname)
        push!(tech.sites, site)

    end

    availabilitiespath = joinpath(datadir, "variable/availability.csv")
    load_sites_timeseries!(system, VariableTechnology, availabilitiespath, :availability)

end

function load_storagetechs!(system::System, datadir::String)

    regions = regionset(system)
    techspath = joinpath(datadir, "storage/regiontechs.csv")
    validator = AddValidator{String}("region", regions, "tech", techspath)

    techs = readdlm(techspath, ',')

    for r in 2:size(techs, 1)

        regionname = string(techs[r, 1])
        techname = string(techs[r, 2])

        validate!(validator, regionname, techname)

        cost_capital_power = Float64(techs[r, 3])
        cost_capital_energy = Float64(techs[r, 4])

        tech = StorageTechnology(
            techname, cost_capital_power, cost_capital_energy, VariableSite[])

        _, region = getbyname(system.regions, regionname)
        push!(region.storagetechs, tech)

    end

end

function load_storagesites!(system::System, datadir::String)

    regiontechs = regiontechset(system, StorageTechnology)
    sitespath = joinpath(datadir, "storage/sites.csv")
    validator = AddValidator{String}(
        "region-technology pair", regiontechs, "site", sitespath)

    sites = readdlm(sitespath, ',')

    for r in 2:size(sites, 1)

        regionname = string(sites[r, 1])
        techname = string(sites[r, 2])
        sitename = string(sites[r, 3])

        validate!(validator, (regionname, techname), sitename)

        power_existing = Float64(sites[r, 4])
        power_new_max = Float64(sites[r, 5])

        energy_existing = Float64(sites[r, 6])
        energy_new_max = Float64(sites[r, 7])

        site = StorageSite(
            sitename, power_existing, power_new_max,
            energy_existing, energy_new_max)

        tech = get_tech(system, StorageTechnology, regionname, techname)
        push!(tech.sites, site)

    end

end

function load_sites_timeseries!(
    system::System, techtype::Type{<:ResourceTechnology}, datapath::String,
    field::Symbol, transformer::Function=identity
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
