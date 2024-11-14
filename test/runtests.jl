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

fullchrono = fullchronologyperiods(sys, daylength=2)
repeatedchrono = singleperiod(sys, daylength=2)

eue_estimator = nullestimator(sys, fullchrono)
max_eues = zeros(3)

ram_start = now()
ram = AdequacyProblem(sys, samples=1000)
solve!(ram)
ram_end = now()
println("NEUE: ", ram.region_neue)

cem = ExpansionProblem(sys, repeatedchrono, eue_estimator, max_eues, optimizer)

cem_start = now()
cem = ExpansionProblem(sys, fullchrono, eue_estimator, max_eues, optimizer)
solve!(cem)
cem_end = now()

println("System Cost: ", value(cost(cem)))
println("System LCOE: ", value(lcoe(cem)))

sys_built = SystemParams(cem)
display(sys_built)

ram = AdequacyProblem(sys_built, samples=1000)
solve!(ram)
println("NEUE: ", ram.region_neue)

pcm = DispatchProblem(sys_built, ReliabilityDispatch, fullchrono, optimizer)
solve!(pcm)
println(termination_status(pcm.model))
println("Operating Cost (Reliability): ", value(cost(pcm)))

pcm_start = now()
pcm = DispatchProblem(sys_built, EconomicDispatch, fullchrono, optimizer)
solve!(pcm)
pcm_end = now()
println(termination_status(pcm.model))
println("Operating Cost (Economic): ", value(cost(pcm)))

max_neues = ones(3)
neue_tols = fill(0.1, 3)
cem, ram, pcm = iterate_ra_cem(
    sys, fullchrono, max_neues, optimizer,
    neue_tols=neue_tols, outfile=timestamp * ".db", check_dispatch=true)
println("System Cost: ", value(cost(cem)))
println("System LCOE: ", value(lcoe(cem)))
println("NEUE: ", ram.region_neue)

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
