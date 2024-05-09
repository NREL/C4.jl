using Test

using C4.Data
using C4.AdequacyModel
using C4.ExpansionModel

import HiGHS

include("ExpansionModel/sequencing.jl")

sys = System("Data/toysystem")
display(sys)

fullchrono = fullchronology(sys, daylength=2)
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
@time sf = assess(ram, samples=100)

# println(ram.sys.regions.names)

# display([ram.sys.interfaces.regions_from ram.sys.interfaces.regions_to])

# display([ram.sys.generators.names ram.sys.generators.capacity])
# display([ram.sys.storages.names, ram.sys.storages.charge_capacity])

@time cem = ExpansionProblem(sys, fullchrono, eue_estimator, max_eues, HiGHS.Optimizer)
println(cem.model)
