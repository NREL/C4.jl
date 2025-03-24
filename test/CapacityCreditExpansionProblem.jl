using DBInterface
using DuckDB

using C4.CapacityCreditExpansionModel

import C4.powerunits_MW

include("generate_nddata.jl")

sys = SystemParams("Data/toysystem-coppersheet")
display(sys)

peak_load = maximum(sys.regions[1].demand) * powerunits_MW # in MW
cc_surface = cc_data(150.0, 3, 4, 3) # random 3D array of wind/solar/storage CCs

# Here we just hardcode things because the numbers are all made up anyways.
# A more robust solution would be to iterate through
# sys.region[1].variabletechs, extract each technology's name, and match
# it with CC data stored somewhere else.

cc_1d = CapacityCreditCurvesParams(
    [0.9, 0.9], # Gas CT and Gas CC static capacity credits
    [
        # Wind (Variable Tech #1)
        CapacityCreditCurveParams(150., cc_surface[:,1,1]), 
        # Solar PV (Variable Tech #2)
        CapacityCreditCurveParams(100., cc_surface[1,:,1])
    ], [
        # 4h Lithium Ion (Storage Tech #1)
        CapacityCreditCurveParams(10., cc_surface[1,1,:])
    ])

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

cc_nd = CapacityCreditSurfaceParams(
    [0.9, 0.9], # Gas CT and Gas CC static capacity credits
    [150., 100], # wind and solar step sizes
    [10.], # 4h battery step size
    cc_surface
)

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
