using DBInterface
import ..store

function store(con::DBInterface.Connection, sys::SystemParams)

    DBInterface.execute(con, "CREATE TABLE regions (
        region TEXT PRIMARY KEY
    )")

    DBInterface.execute(con, "CREATE TABLE techtypes (
        techtype TEXT PRIMARY KEY
    )")

    DBInterface.execute(con, "INSERT INTO techtypes VALUES
        ('thermal'),
        ('variable'),
        ('storage')")

    DBInterface.execute(con, "CREATE TABLE techs (
        tech TEXT,
        region TEXT REFERENCES regions(region),
        techtype TEXT REFERENCES techtypes(techtype),
        cost_generation DOUBLE,
        cost_capital_power DOUBLE,
        cost_capital_energy DOUBLE,
        PRIMARY KEY (tech, region)
    )")

    DBInterface.execute(con, "CREATE TABLE sites (
        site TEXT,
        tech TEXT,
        region TEXT,
        FOREIGN KEY (tech, region) REFERENCES techs (tech, region),
        PRIMARY KEY (site, tech, region)
    )")

    foreach(region -> store(con, region), sys.regions)

    DBInterface.execute(con, "CREATE TABLE interfaces (
        region_from TEXT REFERENCES regions(region),
        region_to TEXT REFERENCES regions(region),
        cost_capital DOUBLE,
        PRIMARY KEY (region_from, region_to),
    )")

    foreach(iface -> store(con, iface, sys.regions), sys.interfaces)

    DBInterface.execute(con, "CREATE TABLE iterations (
        id INTEGER PRIMARY KEY,
        optimization_start TIMESTAMP,
        optimization_end TIMESTAMP,
        adequacy_start TIMESTAMP,
        adequacy_end TIMESTAMP
    )")

end

function store(con::DBInterface.Connection, region::RegionParams)

    DBInterface.execute(
        con,
        "INSERT into regions (region) VALUES (?)",
        (region.name,)
    )

    foreach(tech -> store(con, tech, region), region.thermaltechs)
    foreach(tech -> store(con, tech, region), region.variabletechs)
    foreach(tech -> store(con, tech, region), region.storagetechs)

end

techtype(::ThermalParams) = "thermal"
techtype(::VariableParams) = "variable"

function store(con::DBInterface.Connection, gen::GeneratorParams, region::RegionParams)

    DBInterface.execute(
        con,
        "INSERT into techs (
            tech, region, techtype, cost_generation, cost_capital_power
        ) VALUES (?, ?, ?, ?, ?)",
        (gen.name, region.name, techtype(gen), gen.cost_generation, gen.cost_capital)
    )

    foreach(site -> store(con, site, gen, region), gen.sites)

end

function store(con::DBInterface.Connection, stor::StorageParams, region::RegionParams)

    DBInterface.execute(
        con,
        "INSERT into techs (
            tech, region, techtype,
            cost_capital_power, cost_capital_energy
        ) VALUES (?, ?, 'storage', ?, ?)",
        (stor.name, region.name, stor.cost_capital_power, stor.cost_capital_energy)
    )

    foreach(site -> store(con, site, stor, region), stor.sites)

end

function store(con::DBInterface.Connection, site::SiteParams,
               tech::TechnologyParams, region::RegionParams)

    DBInterface.execute(
        con,
        "INSERT into sites (
            site, tech, region
        ) VALUES (?, ?, ?)",
        (site.name, tech.name, region.name)
    )

end

function store(con::DBInterface.Connection, iface::InterfaceParams, regions::Vector{RegionParams})

    region_from = regions[iface.region_from].name
    region_to = regions[iface.region_to].name

    DBInterface.execute(
        con,
        "INSERT into interfaces (
            region_from, region_to, cost_capital
        ) VALUES (?, ?, ?)",
        (region_from, region_to, iface.cost_capital)
    )

end
