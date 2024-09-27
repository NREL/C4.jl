using DBInterface

import ..store
import ..Data: store_adequacy_iteration

function store(
    con::DBInterface.Connection, result::AdequacyProblem,
    timings::Pair{DateTime,DateTime}; iter::Int=0)

    store(con, result.sys)
    store_adequacy_iteration(con, iter, timings)

    DBInterface.execute(con, "CREATE TABLE IF NOT EXISTS adequacies (
        iteration INTEGER PRIMARY KEY REFERENCES iterations(id),
        demand DOUBLE,
        eue DOUBLE,
        eue_std DOUBLE,
        lole DOUBLE,
        lole_std DOUBLE
    )")

    DBInterface.execute(con, "CREATE TABLE IF NOT EXISTS region_adequacies (
        iteration INTEGER REFERENCES iterations(id),
        region TEXT REFERENCES regions(region),
        demand DOUBLE,
        eue DOUBLE,
        eue_std DOUBLE,
        lole DOUBLE,
        lole_std DOUBLE,
        PRIMARY KEY (iteration, region)
    )")

    region_names = result.prassys.regions.names
    region_demands = vec(sum(result.prassys.regions.load, dims=2))

    DBInterface.execute(con, "INSERT into adequacies (
            iteration, demand, eue, eue_std, lole, lole_std
        ) VALUES (?, ?, ?, ?, ?, ?)",
        (iter, sum(region_demands), result.eue, result.eue_std, result.lole, result.lole_std)
    )

    for r in 1:length(region_names)

        DBInterface.execute(con, "INSERT into region_adequacies (
                iteration, region, demand, eue, eue_std, lole, lole_std
            ) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (iter, region_names[r], region_demands[r],
             result.region_eues[r], result.region_eue_stds[r],
             result.region_loles[r], result.region_lole_stds[r])
        )

    end

end
