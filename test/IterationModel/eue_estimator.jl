using C4.IterationModel:
    estimator_params, new_maxerror,
    compress_estimator, compress_estimators, total_error_curve

@testset "EUE estimator" begin

    @testset "EUE estimator builder" begin

        surplus_points = [5]
        eue_ints, eue_slopes = estimator_params(surplus_points, 1)
        @test eue_slopes ≈ [1.0]
        @test eue_ints ≈ [5]

        surplus_points = [5, 5, 5]
        eue_ints, eue_slopes = estimator_params(surplus_points, 3)
        @test eue_slopes ≈ [1.0]
        @test eue_ints ≈ [5]

        surplus_points = [0, 0, 0]
        eue_ints, eue_slopes = estimator_params(surplus_points, 3)
        @test eue_slopes == []
        @test eue_ints == []

        surplus_points = [-5, -5, -5]
        eue_ints, eue_slopes = estimator_params(surplus_points, 3)
        @test eue_slopes == []
        @test eue_ints == []

        surplus_points = zeros(Int, 1000)
        surplus_points[1:234] .= -189
        surplus_points[235:489] .= -169
        surplus_points[490:747] .= 166
        surplus_points[748:1000] .= 168
        eue_ints, eue_slopes = estimator_params(surplus_points, 1000)
        @test eue_slopes ≈ [0.253, 0.511]
        @test eue_ints ≈ [42.504, 85.332]

        surplus_points = [-5, 0, 5, 5]
        eue_ints, eue_slopes = estimator_params(surplus_points, 4)
        @test eue_slopes ≈ [0.5]
        @test eue_ints ≈ [2.5]

        surplus_points = [-5, 0, 5, 10]
        eue_ints, eue_slopes = estimator_params(surplus_points, 4)
        @test eue_slopes ≈ [0.25, 0.5]
        @test eue_ints ≈ [2.5, 3.75]

        surplus_points = [5, 10, 15, 20, 25]
        eue_ints, eue_slopes = estimator_params(surplus_points, 5)
        @test eue_slopes ≈ [0.2, 0.4, 0.6, 0.8, 1.0]
        @test eue_ints ≈ [5, 9, 12, 14, 15]

        surplus_points = [13, 13, 13, 13, 15]
        eue_ints, eue_slopes = estimator_params(surplus_points, 5)
        @test eue_slopes ≈ [0.2, 1.0]
        @test eue_ints ≈ [3, 13.4]

        surplus_points = [5, 10, 15, 20, 25, 13, 13, 13, 13, 15]
        eue_ints, eue_slopes = estimator_params(surplus_points, 5)
        @test eue_slopes ≈ [0.2, 0.4, 0.8, 1.6, 1.8, 2.0]
        @test eue_ints ≈ [5, 9, 15, 25.4, 27.4, 28.4]

    end

    @testset "EUE estimator compression" begin

        eue_slopes1 = [0.2, 0.4, 0.6, 0.8, 1.0]
        eue_ints1 = [5., 9, 12, 14, 15]

        _, _, order, curve = compress_estimator(eue_ints1, eue_slopes1)
        println(order)
        println(curve)

        segments = BitSet(1:5)
        @test new_maxerror(eue_ints1, eue_slopes1, segments, 1) ≈ 0.5
        @test new_maxerror(eue_ints1, eue_slopes1, segments, 2) ≈ 0.5
        @test new_maxerror(eue_ints1, eue_slopes1, segments, 3) ≈ 0.5
        @test new_maxerror(eue_ints1, eue_slopes1, segments, 4) ≈ 0.5
        @test new_maxerror(eue_ints1, eue_slopes1, segments, 5) ≈ 1.0

        eue_slopes2 = [0.2, 1.0]
        eue_ints2 = [3, 13.4]

        _, _, order, curve = compress_estimator(eue_ints2, eue_slopes2)
        println(order)
        println(curve)

        segments = BitSet(1:2)
        @test new_maxerror(eue_ints2, eue_slopes2, segments, 1) ≈ 0.32
        @test new_maxerror(eue_ints2, eue_slopes2, segments, 2) ≈ 10.4

        combined_curve = compress_estimators(
            [eue_ints1, eue_ints2], [eue_slopes1, eue_slopes2])

        @test length(combined_curve) == 5

        @test combined_curve[1][1] ≈ 0.32
        @test combined_curve[1][2] == 1
        @test combined_curve[1][3] == 2
        @test combined_curve[1][4] == 1

        @test combined_curve[2][1] ≈ 0.5
        @test combined_curve[2][3] == 1
        @test combined_curve[2][4] == 1

        @test combined_curve[3][1] ≈ 0.5
        @test combined_curve[3][3] == 1
        @test combined_curve[2][4] == 1

        total_error_curve(combined_curve, 2) ≈ [0.32, 0.82, 0.82, 1.32, 3.32]

    end

end
