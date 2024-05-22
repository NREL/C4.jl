using C4.IterationModel: estimator_params, removal_candidates

@testset "EUE estimator" begin

    @testset "EUE estimator builder" begin

        surplus_points = [5, 10, 15, 20, 25]
        eue_ints, eue_slopes = estimator_params(surplus_points, 5)
        @test eue_slopes == [0.2, 0.4, 0.6, 0.8, 1.0]
        @test eue_ints == [5, 9, 12, 14, 15]

        surplus_points = [13, 13, 13, 13, 15]
        eue_ints, eue_slopes = estimator_params(surplus_points, 5)
        @test eue_slopes == [0.2, 1.0]
        @test eue_ints == [3, 13.4]

        surplus_points = [5, 10, 15, 20, 25, 13, 13, 13, 13, 15]
        eue_ints, eue_slopes = estimator_params(surplus_points, 5)
        @test eue_slopes == [0.2, 0.4, 0.8, 1.6, 1.8, 2.0]
        @test eue_ints == [5, 9, 15, 25.4, 27.4, 28.4]

    end

    @testset "EUE estimator compression" begin

        # This is a bad test case since equally-spaced / equal-slope-changed
        # segments all have the same max error (0.5), with degenerate sort
        # results (except for the last segment, when the "next" segment is
        # the x axis i.e. infinite slope)
        eue_slopes = [0.2, 0.4, 0.6, 0.8, 1.0]
        eue_ints = [5., 9, 12, 14, 15]
        candidates = removal_candidates(eue_ints, eue_slopes)
        @test all(isapprox(0.5), first.(candidates))

        eue_slopes = [0.2, 1.0]
        eue_ints = [3, 13.4]
        candidates = removal_candidates(eue_ints, eue_slopes)
        @test length(candidates) == 1
        @test first(first(candidates)) ≈ 0.32
        @test last(first(candidates)) == 1

    end

end
