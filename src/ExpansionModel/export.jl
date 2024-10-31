import DBInterface
import DuckDB
import Dates: DateTime

import ..store

function store(
    con::DBInterface.Connection, cem::ExpansionProblem,
    timings::Pair{DateTime,DateTime}; iter::Int=0)

    store(con, cem.system)
    store_iteration(con, iter)
    store_iteration_step(con, iter, "expansion", timings)
    store(con, iter, cem.builds)
    store(con, iter, cem.economicdispatch)

end

struct ExpansionAppender

    sitebuilds::DuckDB.Appender
    interfacebuilds::DuckDB.Appender

    ExpansionAppender(con::DuckDB.DB) = new(
        DuckDB.Appender(con, "sitebuilds"),
        DuckDB.Appender(con, "interfacebuilds")
    )

end

function DuckDB.close(appender::ExpansionAppender)
    DuckDB.close(appender.sitebuilds)
    DuckDB.close(appender.interfacebuilds)
    return
end

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

    appender = ExpansionAppender(con)

    foreach(region -> store(appender, iter, region), sys.regions)
    foreach(iface -> store(appender, iter, iface, sys.regions), sys.interfaces)

    DuckDB.close(appender)

    # TODO: Transmission expansion costs
    DBInterface.execute(con, "CREATE VIEW IF NOT EXISTS summary_capex AS
        SELECT iteration, site, tech, region, power * cost_capital_power as cost_power, energy * cost_capital_energy as cost_energy
        FROM sitebuilds JOIN techs USING (tech, region)
    ")

end

function store(appender::ExpansionAppender, iter::Int, region::RegionExpansion)

    foreach(tech -> store(appender, iter, tech, region), region.thermaltechs)
    foreach(tech -> store(appender, iter, tech, region), region.variabletechs)
    foreach(tech -> store(appender, iter, tech, region), region.storagetechs)

end

function store(appender::ExpansionAppender, iter::Int,
               tech::TechnologyExpansion, region::RegionExpansion)

    foreach(site -> store(appender, iter, site, tech, region), tech.sites)

end

function store(appender::ExpansionAppender, iter::Int, site::ThermalSiteExpansion,
               tech::ThermalExpansion, region::RegionExpansion)

    total_units = value(site.units_new) + site.params.units_existing 
    total_capacity = total_units * tech.params.unit_size

    DuckDB.append(appender.sitebuilds, iter)
    DuckDB.append(appender.sitebuilds, name(site))
    DuckDB.append(appender.sitebuilds, name(tech))
    DuckDB.append(appender.sitebuilds, name(region))
    DuckDB.append(appender.sitebuilds, total_capacity)
    DuckDB.append(appender.sitebuilds, nothing)
    DuckDB.end_row(appender.sitebuilds)

end

function store(appender::ExpansionAppender, iter::Int, site::VariableSiteExpansion,
               tech::VariableExpansion, region::RegionExpansion)

    total_capacity = value(site.capacity_new) + site.params.capacity_existing

    DuckDB.append(appender.sitebuilds, iter)
    DuckDB.append(appender.sitebuilds, name(site))
    DuckDB.append(appender.sitebuilds, name(tech))
    DuckDB.append(appender.sitebuilds, name(region))
    DuckDB.append(appender.sitebuilds, total_capacity)
    DuckDB.append(appender.sitebuilds, nothing)
    DuckDB.end_row(appender.sitebuilds)

end

function store(appender::ExpansionAppender, iter::Int, site::StorageSiteExpansion,
               tech::StorageExpansion, region::RegionExpansion)

    total_power = value(maxpower(site))
    total_energy = value(maxenergy(site))

    DuckDB.append(appender.sitebuilds, iter)
    DuckDB.append(appender.sitebuilds, name(site))
    DuckDB.append(appender.sitebuilds, name(tech))
    DuckDB.append(appender.sitebuilds, name(region))
    DuckDB.append(appender.sitebuilds, total_power)
    DuckDB.append(appender.sitebuilds, total_energy)
    DuckDB.end_row(appender.sitebuilds)

end

function store(appender::ExpansionAppender, iter::Int,
               iface::InterfaceExpansion, regions::Vector{RegionExpansion})

    region_from = name(regions[iface.params.region_from])
    region_to = name(regions[iface.params.region_to])

    total_capacity = value(availablecapacity(iface))

    DuckDB.append(appender.interfacebuilds, iter)
    DuckDB.append(appender.interfacebuilds, region_from)
    DuckDB.append(appender.interfacebuilds, region_to)
    DuckDB.append(appender.interfacebuilds, total_capacity)
    DuckDB.end_row(appender.interfacebuilds)

end
