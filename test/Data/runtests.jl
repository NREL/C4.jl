using C4.Data
using C4.AdequacyModel

sys = System("Data/toysystem")
display(sys)

# for region in sys.regions
#     for tech in region.variabletechs
#         for site in tech.sites
#             println(join([region.name, tech.name, site.name, site.availability], " "))
#         end
#     end
# end

@time ram = AdequacyProblem(sys)

# println(ram.sys.regions.names)

# display([ram.sys.interfaces.regions_from ram.sys.interfaces.regions_to])

# display([ram.sys.generators.names ram.sys.generators.capacity])
# display([ram.sys.storages.names, ram.sys.storages.charge_capacity])

@time sf = assess(ram, samples=100)
display(sf)
