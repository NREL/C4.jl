using Test
using Dates

using C4.Data
using C4.AdequacyModel
using C4.DispatchModel
using C4.ExpansionModel
using C4.IterationModel

import C4.store

using DuckDB

import HiGHS
import JuMP: optimizer_with_attributes, value, termination_status

include("DispatchModel/sequencing.jl")
include("IterationModel/eue_estimator.jl")

optimizer = optimizer_with_attributes(
    HiGHS.Optimizer,
    "log_to_console" => false,
)

sys = SystemParams("Data/toysystem")
display(sys)

timestamp = Dates.format(now(), "yyyymmddHHMMSS")
con = DBInterface.connect(DuckDB.DB, timestamp * ".params.db")
store(con, sys)

fullchrono = fullchronologyperiods(sys, daylength=2)
repeatedchrono = singleperiod(sys, daylength=2)

eue_estimator = nullestimator(sys, fullchrono)
max_eues = zeros(3)

ram = AdequacyProblem(sys)
adequacy = assess(ram, samples=1000)
println("NEUE: ", adequacy.region_neue)

cem = ExpansionProblem(sys, repeatedchrono, eue_estimator, max_eues, optimizer)
cem = ExpansionProblem(sys, fullchrono, eue_estimator, max_eues, optimizer)

solve!(cem)
println("System Cost: ", value(cost(cem)))
println("System LCOE: ", value(lcoe(cem)))

sys_built = SystemParams(cem)
display(sys_built)

ram = AdequacyProblem(sys_built)
adequacy = assess(ram, samples=1000)
println("NEUE: ", adequacy.region_neue)

pcm = DispatchProblem(sys_built, ReliabilityDispatch, fullchrono, optimizer)
solve!(pcm)
println(termination_status(pcm.model))
println("Operating Cost (Reliability): ", value(cost(pcm)))

pcm = DispatchProblem(sys_built, EconomicDispatch, fullchrono, optimizer)
solve!(pcm)
println(termination_status(pcm.model))
println("Operating Cost (Economic): ", value(cost(pcm)))

max_neues = ones(3)
cem, adequacy = iterate_ra_cem(
    sys, repeatedchrono, max_neues, optimizer, max_iters=5)
println("System Cost: ", value(cost(cem)))
println("System LCOE: ", value(lcoe(cem)))
println("NEUE: ", adequacy.region_neue)

neue_tols = fill(0.1, 3)
cem, adequacy = iterate_ra_cem(
    sys, repeatedchrono, max_neues, optimizer, neue_tols=neue_tols, max_iters=5)
println("System Cost: ", value(cost(cem)))
println("System LCOE: ", value(lcoe(cem)))
println("NEUE: ", adequacy.region_neue)

sys_built = SystemParams(cem)
display(sys_built)

pcm = DispatchProblem(sys_built, ReliabilityDispatch, fullchrono, optimizer)
solve!(pcm)
println(termination_status(pcm.model))
println("Operating Cost (Reliability): ", value(cost(pcm)))

pcm = DispatchProblem(sys_built, EconomicDispatch, fullchrono, optimizer)
solve!(pcm)
println(termination_status(pcm.model))
println("Operating Cost (Economic): ", value(cost(pcm)))
