using DBInterface
using DuckDB

using C4.Data
using C4.CapacityCreditExpansionModel

import C4.powerunits_MW

include("generate_nddata.jl")

sys = SystemParams("Data/toysystem-coppersheet")
display(sys)

cc_surface = cc_data(150.0, 3, 4, 3) # random 3D array of wind/solar/storage CCs

# Here we just hardcode things because the numbers are all made up anyways.
# A more robust solution would be to iterate through
# sys.region[1].variabletechs, extract each technology's name, and match
# it with CC data stored somewhere else.

cc_nd = CapacityCreditSurfaceParams(
    [0.9, 0.9], # Gas CT and Gas CC static capacity credits
    [150., 100], # wind and solar step sizes
    [10.], # 4h battery step size
    cc_surface
)

cc_static = ccs_static(cc_nd)

@test cc_static.thermaltechs == [0.9, 0.9]

@test cc_static.variabletechs[1].stepsize == 150
@test cc_static.variabletechs[1].points == cc_surface[1:2,1,1]

@test cc_static.variabletechs[2].stepsize == 100
@test cc_static.variabletechs[2].points == cc_surface[1,1:2,1]

@test cc_static.storagetechs[1].stepsize == 10
@test cc_static.storagetechs[1].points == cc_surface[1,1,1:2]

cc_1d = ccs_1d(cc_nd)

@test cc_1d.thermaltechs == [0.9, 0.9]

@test cc_1d.variabletechs[1].stepsize == 150
@test cc_1d.variabletechs[1].points == cc_surface[:,1,1]

@test cc_1d.variabletechs[2].stepsize == 100
@test cc_1d.variabletechs[2].points == cc_surface[1,:,1]

@test cc_1d.storagetechs[1].stepsize == 10
@test cc_1d.storagetechs[1].points == cc_surface[1,1,:]

peak_load = maximum(sys.regions[1].demand) * powerunits_MW # in MW

# 1D Curves

cc_cem = CapacityCreditExpansionProblem(sys, fullchrono, cc_1d, peak_load, optimizer)
write_to_file(cc_cem.model, "model_cc_1d.lp")

cc_start = now()
solve!(cc_cem)
cc_end = now()

con = DBInterface.connect(DuckDB.DB, timestamp * "_cc_1d.db")
store(con, cc_cem, cc_start => cc_end)

println("1D CC System Cost: ", value(cost(cc_cem)))
println("1D CC System LCOE: ", value(lcoe(cc_cem)))

sys_built = SystemParams(cc_cem)
display(sys_built)

cc_cem = CapacityCreditExpansionProblem(sys, fullchrono, cc_1d, 0., optimizer)
solve!(cc_cem)
println("System Cost w/o PRM: ", value(cost(cc_cem)))

for prm in 0:0.1:0.5

    # Note that for testing purposes, this *ignores* any EFC contributions
    # of existing generators, which you wouldn't want to do in reality

    build_efc = peak_load * (1 + prm)

    local cc_cem = CapacityCreditExpansionProblem(sys, fullchrono, cc_1d, build_efc, optimizer)
    solve!(cc_cem)

    println("System Cost @ PRM = $(prm): ", value(cost(cc_cem)))

end

#ND Surface

cc_cem = CapacityCreditExpansionProblem(sys, fullchrono, cc_nd, peak_load, optimizer)
write_to_file(cc_cem.model, "model_cc_nd.lp")

cc_start = now()
solve!(cc_cem)
cc_end = now()
println(termination_status(cc_cem.model))

con = DBInterface.connect(DuckDB.DB, timestamp * "_cc_nd.db")
store(con, cc_cem, cc_start => cc_end)

println("ND CC System Cost: ", value(cost(cc_cem)))
println("ND CC System LCOE: ", value(lcoe(cc_cem)))

sys_built = SystemParams(cc_cem)
display(sys_built)

cc_cem = CapacityCreditExpansionProblem(sys, fullchrono, cc_nd, 0., optimizer)
solve!(cc_cem)
println("System Cost w/o PRM: ", value(cost(cc_cem)))

for prm in 0:0.1:0.5

    # Note that for testing purposes, this *ignores* any EFC contributions
    # of existing generators, which you wouldn't want to do in reality

    build_efc = peak_load * (1 + prm)

    local cc_cem = CapacityCreditExpansionProblem(sys, fullchrono, cc_nd, build_efc, optimizer)
    solve!(cc_cem)

    println("System Cost @ PRM = $(prm): ", value(cost(cc_cem)))

end
