using C4.IterationModel: estimator_params

@testset "EUE estimator builder" begin

    surplus_points = [5, 10, 15, 20, 25]
    eue_ints, eue_slopes = estimator_params(surplus_points, 5)
    @test eue_slopes == [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
    @test eue_ints == [0., 5, 9, 12, 14, 15]

    surplus_points = [13, 13, 13, 13, 15]
    eue_ints, eue_slopes = estimator_params(surplus_points, 5)
    @test eue_slopes == [0.0, 0.2, 1.0]
    @test eue_ints == [0, 3, 13.4]

    surplus_points = [5, 10, 15, 20, 25, 13, 13, 13, 13, 15]
    eue_ints, eue_slopes = estimator_params(surplus_points, 5)
    @test eue_slopes == [0, 0.2, 0.4, 0.8, 1.6, 1.8, 2.0]
    @test eue_ints == [0, 5, 9, 15, 25.4, 27.4, 28.4]

end
