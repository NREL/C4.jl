import DBInterface
import DuckDB

import ..store

function store(
    con::DBInterface.Connection, result::AdequacyProblem,
    timings::Pair{DateTime,DateTime}; iter::Int=0)

    store(con, result.sys)
    store_iteration(con, iter)
    store_iteration_step(con, iter, "adequacy", timings)
    store(con, iter, result)

end

struct AdequacyAppender

    adequacies::DuckDB.Appender
    region_adequacies::DuckDB.Appender

    AdequacyAppender(con::DuckDB.DB) = new(
        DuckDB.Appender(con, "adequacies"),
        DuckDB.Appender(con, "region_adequacies"),
    )

end

function DuckDB.close(appender::AdequacyAppender)
    DuckDB.close(appender.adequacies)
    DuckDB.close(appender.region_adequacies)
    return
end

function store(con::DBInterface.Connection, iter::Int, result::AdequacyProblem)

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

    appender = AdequacyAppender(con)

    region_names = result.prassys.regions.names
    region_demands = vec(sum(result.prassys.regions.load, dims=2))

    DuckDB.append(appender.adequacies, iter)
    DuckDB.append(appender.adequacies, sum(region_demands))
    DuckDB.append(appender.adequacies, result.eue)
    DuckDB.append(appender.adequacies, result.eue_std)
    DuckDB.append(appender.adequacies, result.lole)
    DuckDB.append(appender.adequacies, result.lole_std)
    DuckDB.end_row(appender.adequacies)

    for r in 1:length(region_names)

        DuckDB.append(appender.region_adequacies, iter)
        DuckDB.append(appender.region_adequacies, region_names[r])
        DuckDB.append(appender.region_adequacies, region_demands[r])
        DuckDB.append(appender.region_adequacies, result.region_eues[r])
        DuckDB.append(appender.region_adequacies, result.region_eue_stds[r])
        DuckDB.append(appender.region_adequacies, result.region_loles[r])
        DuckDB.append(appender.region_adequacies, result.region_lole_stds[r])
        DuckDB.end_row(appender.region_adequacies)

    end

    DuckDB.close(appender)

    return

end
