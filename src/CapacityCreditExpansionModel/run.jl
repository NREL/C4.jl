import Dates: now
import DBInterface
import DuckDB

import ..store

using C4.Data
using C4.AdequacyModel
using C4.DispatchModel
using C4.CapacityCreditExpansionModel

function solve_capacitycredits(
    sys::SystemParams, chronology::TimeProxyAssignment,
    capacitycredits::CapacityCreditParams, build_efc::Float64, optimizer;
    nsamples::Int=1000, outfile::String="", check_dispatch::Bool=false)

    persist = length(outfile) > 0

    n_regions = length(sys.regions)

    ram_start = now()
    ram = AdequacyProblem(sys, samples=nsamples)
    ram_result = solve(ram) # TODO: Skip the thermal sensitivities
    ram_end = now()

    show_neues(ram_result)

    if persist
        store_start = now()
        con = DBInterface.connect(DuckDB.DB, outfile)
        store(con, sys)
        store_iteration(con, 0)
        store_iteration_step(con, 0, "adequacy", ram_start => ram_end)
        store(con, 0, ram_result)
        store_end = now()
        store_iteration_step(con, 0, "persistence", store_start => store_end)
    end

    cem_start = now()

    cem = CapacityCreditExpansionProblem(sys, chronology, capacitycredits, build_efc, optimizer)

    println("Recurrences:")
    for recc in cem.economicdispatch.recurrences
        println(recc.repetitions, " x ", recc.dispatch.period.name)
    end

    solve!(cem)
    cem_end = now()

    ram_start = now()
    sys_built = SystemParams(cem)
    ram = AdequacyProblem(sys_built, samples=nsamples)
    ram_result = solve(ram)
    ram_end = now()

    show_neues(ram_result)

    if persist
        store_start = now()
        store_iteration(con, 1)
        store_iteration_step(con, 1, "expansion", cem_start => cem_end)
        store_iteration_step(con, 1, "adequacy", ram_start => ram_end)
        store(con, 1, cem.builds)
        store(con, 1, cem.economicdispatch)
        store(con, 1, ram_result)
        DBInterface.execute(con, "CHECKPOINT")
        store_end = now()
        store_iteration_step(con, 1, "persistence", store_start => store_end)
        DBInterface.execute(con, "CHECKPOINT")
    end

    pcm = nothing

    if check_dispatch

        pcm_start = now()
        fullchrono = fullchronologyperiods(sys_built, daylength=chronology.daylength)
        pcm = DispatchProblem(sys_built, EconomicDispatch, fullchrono, optimizer)
        solve!(pcm)
        pcm_end = now()

        if persist
            store_start = now()
            store_iteration(con, 2)
            store_iteration_step(con, 2, "dispatch", pcm_start => pcm_end)
            store(con, 2, pcm.dispatch)
            DBInterface.execute(con, "CHECKPOINT")
            store_end = now()
            store_iteration_step(con, 2, "persistence", store_start => store_end)
            DBInterface.execute(con, "CHECKPOINT")
        end

    end

    return cem, ram_result, pcm

end
