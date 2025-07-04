using DBInterface
using DuckDB

using C4.Data
using C4.CapacityCreditExpansionModel

import C4.powerunits_MW

include("generate_nddata.jl")

sys = SystemParams("Data/toysystem-coppersheet")
display(sys)

cc_nd = CapacityCreditSurfaceParams(sys, "Data/toysystem/capacitycredits")

@testset "ND Surface Loading" begin

    @test cc_nd.thermaltechs == [0.95, 0.9]
    @test cc_nd.variable_stepsize == [150., 100.]
    @test cc_nd.storage_stepsize == [10.]

    @test cc_nd.points[1,1,1] ≈ 0
    @test cc_nd.points[1,2,1] ≈ 55.371477332138895
    @test cc_nd.points[2,3,1] ≈ 100

end

cc_static = ccs_static(cc_nd)

@testset "Static CC Conversion" begin

    @test cc_static.thermaltechs == cc_nd.thermaltechs

    @test cc_static.variabletechs[1].stepsize == cc_nd.variable_stepsize[1]
    @test cc_static.variabletechs[1].points == cc_nd.points[1:2,1,1]

    @test cc_static.variabletechs[2].stepsize == cc_nd.variable_stepsize[2]
    @test cc_static.variabletechs[2].points == cc_nd.points[1,1:2,1]

    @test cc_static.storagetechs[1].stepsize == cc_nd.storage_stepsize[1]
    @test cc_static.storagetechs[1].points == cc_nd.points[1,1,1:1]

end

cc_1d = ccs_1d(cc_nd)

@testset "1D CC Conversion" begin

    @test cc_1d.thermaltechs == cc_nd.thermaltechs

    @test cc_1d.variabletechs[1].stepsize == cc_nd.variable_stepsize[1]
    @test cc_1d.variabletechs[1].points == cc_nd.points[:,1,1]

    @test cc_1d.variabletechs[2].stepsize == cc_nd.variable_stepsize[2]
    @test cc_1d.variabletechs[2].points == cc_nd.points[1,:,1]

    @test cc_1d.storagetechs[1].stepsize == cc_nd.storage_stepsize[1]
    @test cc_1d.storagetechs[1].points == cc_nd.points[1,1,:]

end

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

cem, ram, pcm = solve_capacitycredits(
    sys, fullchrono, cc_nd, peak_load * 1.15, optimizer,
    check_dispatch=true, outfile=timestamp * "_cc_nd_full.db")

sys_built = SystemParams(cem)
display(sys_built)
println("System Capex: ", value(capex(cem)))
println("System Opex: ", value(cost(pcm)))
