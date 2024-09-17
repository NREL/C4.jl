using DBInterface
using Dates

import ..store

function store(con::DBInterface.Connection, iter::Int, sys::SystemExpansion)

    DBInterface.execute(con, "CREATE TABLE IF NOT EXISTS sitebuilds (
        iteration INTEGER REFERENCES iterations(id),
        site TEXT,
        tech TEXT,
        region TEXT,
        power DOUBLE,
        energy DOUBLE,
        FOREIGN KEY (site, tech, region) REFERENCES sites (site, tech, region),
        PRIMARY KEY (iteration, site, tech, region)
    )")

    DBInterface.execute(con, "CREATE TABLE IF NOT EXISTS interfacebuilds (
        iteration INTEGER REFERENCES iterations(id),
        region_from TEXT,
        region_to TEXT,
        capacity DOUBLE,
        FOREIGN KEY (region_from, region_to) REFERENCES interfaces (region_from, region_to),
        PRIMARY KEY (iteration, region_from, region_to)
    )")

    foreach(region -> store(con, iter, region), sys.regions)
    foreach(iface -> store(con, iter, iface, sys.regions), sys.interfaces)

end

function store(con::DBInterface.Connection, iter::Int, region::RegionExpansion)

    foreach(tech -> store(con, iter, tech, region), region.thermaltechs)
    foreach(tech -> store(con, iter, tech, region), region.variabletechs)
    foreach(tech -> store(con, iter, tech, region), region.storagetechs)

end

function store(con::DBInterface.Connection, iter::Int,
               tech::TechnologyExpansion, region::RegionExpansion)

    foreach(site -> store(con, iter, site, tech, region), tech.sites)

end

function store(con::DBInterface.Connection, iter::Int, site::ThermalSiteExpansion,
               tech::ThermalExpansion, region::RegionExpansion)

    total_units = value(site.units_new) + site.params.units_existing 
    total_capacity = total_units * tech.params.unit_size

    DBInterface.execute(
        con,
        "INSERT into sitebuilds (
            iteration, site, tech, region, power
        ) VALUES (?, ?, ?, ?, ?)",
        (iter, site.params.name, tech.params.name, region.params.name, total_capacity)
    )

end

function store(con::DBInterface.Connection, iter::Int, site::VariableSiteExpansion,
               tech::VariableExpansion, region::RegionExpansion)

    total_capacity = value(site.capacity_new) + site.params.capacity_existing

    DBInterface.execute(
        con,
        "INSERT into sitebuilds (
            iteration, site, tech, region, power
        ) VALUES (?, ?, ?, ?, ?)",
        (iter, site.params.name, tech.params.name, region.params.name, total_capacity)
    )

end

function store(con::DBInterface.Connection, iter::Int, site::StorageSiteExpansion,
               tech::StorageExpansion, region::RegionExpansion)

    total_power = value(site.power_new) + site.params.power_existing
    total_energy = value(site.energy_new) + site.params.energy_existing

    DBInterface.execute(
        con,
        "INSERT into sitebuilds (
            iteration, site, tech, region, power, energy
        ) VALUES (?, ?, ?, ?, ?, ?)",
        (iter, site.params.name, tech.params.name, region.params.name, total_power, total_energy)
    )

end

function store(con::DBInterface.Connection, iter::Int,
               iface::InterfaceExpansion, regions::Vector{RegionExpansion})

    region_from = regions[iface.params.region_from].params.name
    region_to = regions[iface.params.region_to].params.name

    total_capacity = value(iface.capacity_new) + iface.params.capacity_existing

    DBInterface.execute(
        con,
        "INSERT into interfacebuilds (
            iteration, region_from, region_to, capacity
        ) VALUES (?, ?, ?, ?)",
        (iter, region_from, region_to, total_capacity)
    )

end

function store_expansion_iteration(
    con::DBInterface.Connection, iter::Int, times::Pair{DateTime,DateTime})

    DBInterface.execute(
        con,
        "INSERT into iterations (
            id, optimization_start, optimization_end
        ) VALUES (?, ?, ?)",
        (iter, first(times), last(times))
    )

end
