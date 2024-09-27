using DBInterface
using Dates

import ..store

function store(con::DBInterface.Connection, iter::Int, seq::EconomicDispatchSequence)

    DBInterface.execute(con, "CREATE TABLE IF NOT EXISTS periods (
        iteration INTEGER REFERENCES iterations(id),
        period TEXT,
        reps INTEGER,
        t_start INTEGER,
        t_end INTEGER,
        PRIMARY KEY (iteration, period)
    )")

    DBInterface.execute(con, "CREATE TABLE IF NOT EXISTS demands (
        iteration INTEGER,
        period TEXT,
        timestep INTEGER,
        region TEXT REFERENCES regions(region),
        load DOUBLE,
        FOREIGN KEY (iteration, period) REFERENCES periods (iteration, period),
        PRIMARY KEY (iteration, period, timestep, region)
    )")

    DBInterface.execute(con, "CREATE TABLE IF NOT EXISTS dispatches (
        iteration INTEGER,
        period TEXT,
        timestep INTEGER,
        tech TEXT,
        region TEXT,
        dispatch DOUBLE,
        FOREIGN KEY (iteration, period) REFERENCES periods (iteration, period),
        FOREIGN KEY (tech, region) REFERENCES techs (tech, region),
        PRIMARY KEY (iteration, period, timestep, tech, region)
    )")

    DBInterface.execute(con, "CREATE TABLE IF NOT EXISTS flows (
        iteration INTEGER,
        period TEXT,
        timestep INTEGER,
        region_from TEXT,
        region_to TEXT,
        flow DOUBLE,
        FOREIGN KEY (iteration, period) REFERENCES periods (iteration, period),
        FOREIGN KEY (region_from, region_to) REFERENCES interfaces (region_from, region_to),
        PRIMARY KEY (iteration, period, timestep, region_from, region_to)
    )")

    store(con, iter, seq.time)
    foreach(dispatch -> store(con, iter, dispatch), seq.dispatches)

end

function store(con::DBInterface.Connection, iter::Int, time::TimeProxyAssignment)
    reps = zeros(Int, length(time.periods))
    foreach(p_idx -> reps[p_idx] += 1, time.days)
    foreach((p, n) -> store(con, iter, p, n), time.periods, reps)
end

function store(con::DBInterface.Connection, iter::Int, period::TimePeriod, reps::Int)
    DBInterface.execute(con, "INSERT into periods (
            iteration, period, reps, t_start, t_end
        ) VALUES (?, ?, ?, ?, ?)",
        (iter, period.name, reps, first(period.timesteps), last(period.timesteps))
    )
end

function store(con::DBInterface.Connection, iter::Int, dispatch::EconomicDispatch)

    foreach(region -> store(con, iter, dispatch.period, region), dispatch.regions)

    foreach(interface ->
                store(con, iter, dispatch.period, interface, dispatch.regions),
            dispatch.interfaces)

end

function store(
    con::DBInterface.Connection, iter::Int, period::TimePeriod,
    region::RegionEconomicDispatch)

    regionparams = region.region

    for (i, t) in enumerate(period.timesteps)

        DBInterface.execute(con, "INSERT into demands (
                iteration, period, timestep, region, load
            ) VALUES (?, ?, ?, ?, ?)",
            (iter, period.name, i, regionparams.name, regionparams.demand[t])
        )

        for gen in region.thermaltechs

            dispatch = value(gen.dispatch[i])

            DBInterface.execute(con, "INSERT into dispatches (
                    iteration, period, timestep, tech, region, dispatch
                ) VALUES (?, ?, ?, ?, ?, ?)",
                (iter, period.name, i, gen.gen.name, regionparams.name, dispatch)
            )

        end

        for gen in region.variabletechs

            dispatch = value(gen.dispatch[i])

            DBInterface.execute(con, "INSERT into dispatches (
                    iteration, period, timestep, tech, region, dispatch
                ) VALUES (?, ?, ?, ?, ?, ?)",
                (iter, period.name, i, gen.gen.name, regionparams.name, dispatch)
            )

        end


        for stor in region.storagetechs

            dispatch = value(stor.dispatch[i])

            DBInterface.execute(con, "INSERT into dispatches (
                    iteration, period, timestep, tech, region, dispatch
                ) VALUES (?, ?, ?, ?, ?, ?)",
                (iter, period.name, i, stor.stor.name, regionparams.name, dispatch)
            )

        end

    end

end

function store(
    con::DBInterface.Connection, iter::Int, period::TimePeriod,
    interface::InterfaceDispatch, regions::Vector{<:RegionEconomicDispatch})

    region_from = regions[interface.iface.region_from].region.name
    region_to = regions[interface.iface.region_to].region.name

    for (i, t) in enumerate(period.timesteps)

        flow = value(interface.flow[i])

        DBInterface.execute(con, "INSERT into flows (
                iteration, period, timestep, region_from, region_to, flow
            ) VALUES (?, ?, ?, ?, ?, ?)",
            (iter, period.name, i, region_from, region_to, flow)
        )

    end

end
