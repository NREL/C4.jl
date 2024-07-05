using Test

using C4.Data
using C4.AdequacyModel
using C4.ExpansionModel
using C4.IterationModel

import HiGHS
import JuMP: optimizer_with_attributes, value

include("ExpansionModel/sequencing.jl")
include("IterationModel/eue_estimator.jl")

optimizer = optimizer_with_attributes(
    HiGHS.Optimizer,
    "log_to_console" => false,
)


sys = System("Data/toysystem")
display(sys)

fullchrono = fullchronologyperiods(sys, daylength=2)
repeatedchrono = singleperiod(sys, daylength=2)

eue_estimator = nullestimator(sys, fullchrono)
max_eues = zeros(3)

@time ram = AdequacyProblem(sys)
@time adequacy = assess(ram, samples=1000)
println("NEUE: ", adequacy.region_neue)

@time cem = ExpansionProblem(sys, repeatedchrono, eue_estimator, max_eues, optimizer)
@time cem = ExpansionProblem(sys, fullchrono, eue_estimator, max_eues, optimizer)

@time solve!(cem)
println("System Cost: ", value(cost(cem)))
println("System LCOE: ", value(lcoe(cem)))

sys_built = System(cem)
display(sys_built)

@time ram = AdequacyProblem(sys_built)
@time adequacy = assess(ram, samples=1000)
println("NEUE: ", adequacy.region_neue)

max_neues = ones(3)
@time cem, adequacy = iterate_ra_cem(
    sys, repeatedchrono, max_neues, optimizer, max_iters=5)
println("System Cost: ", value(cost(cem)))
println("System LCOE: ", value(lcoe(cem)))
println("NEUE: ", adequacy.region_neue)

neue_tols = fill(0.1, 3)
@time cem, adequacy = iterate_ra_cem(
    sys, repeatedchrono, max_neues, optimizer, neue_tols=neue_tols, max_iters=5)
println("System Cost: ", value(cost(cem)))
println("System LCOE: ", value(lcoe(cem)))
println("NEUE: ", adequacy.region_neue)
