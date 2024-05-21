using Test

using C4.Data
using C4.AdequacyModel
using C4.ExpansionModel
using C4.IterationModel

import HiGHS

include("ExpansionModel/sequencing.jl")
include("IterationModel/eue_estimator.jl")

sys = System("Data/toysystem")
display(sys)

fullchrono = fullchronologyperiods(sys, daylength=2)
repeatedchrono = singleperiod(sys, daylength=2)

eue_estimator = nullestimator(sys, s -> fullchronologyperiods(s, daylength=2))
max_eues = zeros(3)

@time ram = AdequacyProblem(sys)
@time adequacy = assess(ram, samples=1000)
println("NEUE: ", adequacy.region_neue)

@time cem = ExpansionProblem(sys, repeatedchrono, eue_estimator, max_eues, HiGHS.Optimizer)

@time cem = ExpansionProblem(sys, fullchrono, eue_estimator, max_eues, HiGHS.Optimizer)

@time solve!(cem)
println("System Cost: ", cost(cem))
println("System LCOE: ", lcoe(cem))

sys_built = System(cem)
display(sys_built)

@time ram = AdequacyProblem(sys_built)
@time adequacy = assess(ram, samples=1000)
println("NEUE: ", adequacy.region_neue)

aspp(sys, fullchrono, ones(3), HiGHS.Optimizer)
