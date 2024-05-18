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

fullchrono = fullchronology(sys, daylength=2)

repeatchrono = deepcopy(fullchrono)
repeatchrono.days[2] = 1

eue_estimator = nullestimator(sys, s -> fullchronology(s, daylength=2))
max_eues = zeros(3)

# for region in sys.regions
#     for tech in region.variabletechs
#         for site in tech.sites
#             println(join([region.name, tech.name, site.name, site.availability], " "))
#         end
#     end
# end

@time ram = AdequacyProblem(sys)
@time adequacy = assess(ram, samples=1000)
println("NEUE: ", adequacy.region_neue)

# println(ram.sys.regions.names)

# display([ram.sys.interfaces.regions_from ram.sys.interfaces.regions_to])

# display([ram.sys.generators.names ram.sys.generators.capacity])
# display([ram.sys.storages.names, ram.sys.storages.charge_capacity])

@time cem = ExpansionProblem(sys, fullchrono, eue_estimator, max_eues, HiGHS.Optimizer)

#@time cem = ExpansionProblem(sys, repeatchrono, eue_estimator, max_eues, HiGHS.Optimizer)
# println(cem.model)

@time solve!(cem)
println("System Cost: ", cost(cem))
println("System LCOE: ", lcoe(cem))

sys_built = System(cem)
display(sys_built)

@time ram = AdequacyProblem(sys_built)
@time adequacy = assess(ram, samples=1000)
println("NEUE: ", adequacy.region_neue)

aspp(sys, fullchrono, ones(3), HiGHS.Optimizer)
