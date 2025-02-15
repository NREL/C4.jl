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
import JuMP: optimizer_with_attributes, value, termination_status, write_to_file

include("DispatchModel/sequencing.jl")

optimizer = optimizer_with_attributes(
    HiGHS.Optimizer,
    "log_to_console" => false,
)

sys = SystemParams("Data/toysystem")
n_regions = length(sys.regions)
display(sys)

timestamp = Dates.format(now(), "yyyymmddHHMMSS")

fullchrono = fullchronologyperiods(sys, daylength=2)
repeatedchrono = singleperiod(sys, daylength=2)

max_eues = zeros(3)

ram = AdequacyProblem(sys, samples=1000)
ram_results = solve(ram)
println("Base reliability:")
show_neues(ram_results)

# Formulate and solve a one-off CEM without risk curves

cem = ExpansionProblem(sys, nullestimator(repeatedchrono, n_regions), max_eues, optimizer)
write_to_file(cem.model, "model.lp")

cem = ExpansionProblem(sys, nullestimator(fullchrono, n_regions), max_eues, optimizer)
solve!(cem)

println("System Cost: ", value(cost(cem)))
println("System LCOE: ", value(lcoe(cem)))

sys_built = SystemParams(cem)
display(sys_built)

ram = AdequacyProblem(sys_built, samples=1000)
ram_results = solve(ram)
println("One-shot CEM reliability without risk curves:")
show_neues(ram_results)

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

# Formulate and solve a one-off CEM with risk curves

ram = AdequacyProblem(sys, samples=1000)
ram_results = solve(ram)
curve_data = [AdequacyContext(sys, ram_results)]
curve_params = ExpansionModel.RiskEstimateParams(repeatedchrono, curve_data)
cem = ExpansionProblem(sys, curve_params, max_eues, optimizer)
write_to_file(cem.model, "model_riskcurves.lp")
solve!(cem)

println("System Cost: ", value(cost(cem)))
println("System LCOE: ", value(lcoe(cem)))

sys_built = SystemParams(cem)
display(sys_built)

ram = AdequacyProblem(sys_built, samples=1000)
ram_results = solve(ram)
println("One-shot CEM reliability with risk curves:")
show_neues(ram_results) # TODO: Why isn't this system more reliable than the first?

# Formulate and solve an iterative RA-CEM feedback loop

max_neues = ones(3)
cem, ram, pcm = iterate_ra_cem(
    sys, fullchrono, max_neues, optimizer,
    outfile=timestamp * ".db", check_dispatch=true)
println("System Cost: ", value(cost(cem)))
println("System LCOE: ", value(lcoe(cem)))

sys_built = SystemParams(cem)
display(sys_built)

ram = AdequacyProblem(sys_built, samples=1000)
ram_results = solve(ram)
println("Iterative CEM reliability:")
show_neues(ram_results)


pcm = DispatchProblem(sys_built, ReliabilityDispatch, fullchrono, optimizer)
solve!(pcm)
println(termination_status(pcm.model))
println("Operating Cost (Reliability): ", value(cost(pcm)))

pcm = DispatchProblem(sys_built, EconomicDispatch, fullchrono, optimizer)
solve!(pcm)
println(termination_status(pcm.model))
println("Operating Cost (Economic): ", value(cost(pcm)))
