# Test Capture Analysis module
# Validates that computed polynomial critical points capture known critical points
# No dependency on Globtim - tests capture analysis in isolation

using Test
using GlobtimPostProcessing
using LinearAlgebra

# Test fixtures (test_functions.jl) are included once in runtests.jl

@testset "Capture Analysis" begin

    @testset "Exports" begin
        @test isdefined(GlobtimPostProcessing, :KnownCriticalPoints)
        @test isdefined(GlobtimPostProcessing, :CaptureResult)
        @test isdefined(GlobtimPostProcessing, :compute_capture_analysis)
        @test isdefined(GlobtimPostProcessing, :missed_critical_points)
        @test isdefined(GlobtimPostProcessing, :print_capture_summary)
        @test isdefined(GlobtimPostProcessing, :print_degree_capture_convergence)
    end

    @testset "KnownCriticalPoints Construction" begin
        @testset "Basic construction with bounds" begin
            points = [[0.0, 0.0], [1.0, 1.0]]
            values = [0.0, 2.0]
            types = [:min, :saddle]
            b = [(-1.0, 1.0), (-1.0, 1.0)]

            known = KnownCriticalPoints(points, values, types, b)

            @test length(known.points) == 2
            @test length(known.values) == 2
            @test length(known.types) == 2
            # domain_diameter = norm([2.0, 2.0]) = 2*sqrt(2)
            @test known.domain_diameter ≈ 2 * sqrt(2)
        end

        @testset "Domain diameter computation" begin
            # 1D domain [-1, 1]: diameter = 2.0
            known_1d = KnownCriticalPoints(
                [[0.0]], [0.0], [:min],
                [(-1.0, 1.0)]
            )
            @test known_1d.domain_diameter ≈ 2.0

            # 3D domain [0, 1]^3: diameter = sqrt(3)
            known_3d = KnownCriticalPoints(
                [[0.5, 0.5, 0.5]], [1.0], [:min],
                [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)]
            )
            @test known_3d.domain_diameter ≈ sqrt(3)

            # Asymmetric domain [-1.2, 1.2]^4: diameter = norm([2.4, 2.4, 2.4, 2.4]) = 2.4*sqrt(4) = 4.8
            known_4d = KnownCriticalPoints(
                [[0.0, 0.0, 0.0, 0.0]], [0.0], [:min],
                [(-1.2, 1.2), (-1.2, 1.2), (-1.2, 1.2), (-1.2, 1.2)]
            )
            @test known_4d.domain_diameter ≈ 4.8
        end

        @testset "Error on empty points" begin
            @test_throws ErrorException KnownCriticalPoints(
                Vector{Float64}[], Float64[], Symbol[],
                [(-1.0, 1.0)]
            )
        end

        @testset "Error on mismatched lengths" begin
            # values too short
            @test_throws ErrorException KnownCriticalPoints(
                [[0.0], [1.0]], [0.0], [:min, :max],
                [(-1.0, 1.0)]
            )
            # types too short
            @test_throws ErrorException KnownCriticalPoints(
                [[0.0], [1.0]], [0.0, 1.0], [:min],
                [(-1.0, 1.0)]
            )
        end

        @testset "Error on invalid type" begin
            @test_throws ErrorException KnownCriticalPoints(
                [[0.0]], [0.0], [:minimum],  # :minimum is not valid, must be :min
                [(-1.0, 1.0)]
            )
        end

        @testset "Error on mismatched bounds" begin
            # 2D point with 1D bounds
            @test_throws ErrorException KnownCriticalPoints(
                [[0.0, 0.0]], [0.0], [:min],
                [(-1.0, 1.0)]  # 1D bounds, 2D point
            )
        end

        @testset "Error on point dimension mismatch with bounds" begin
            # 3D point with 2D bounds
            @test_throws ErrorException KnownCriticalPoints(
                [[0.0, 0.0, 0.0]], [0.0], [:min],
                [(-1.0, 1.0), (-1.0, 1.0)]
            )
        end
    end

    @testset "Basic Capture - All Found" begin
        # 3 known CPs in 2D, computed points exactly on them
        known = KnownCriticalPoints(
            [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]],
            [0.0, 1.0, 1.0],
            [:min, :saddle, :max],
            [(-2.0, 2.0), (-2.0, 2.0)]
        )
        # Computed points are exactly at known CPs
        computed = [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]]

        result = compute_capture_analysis(known, computed)

        # All distances should be ≈ 0
        @test all(d -> d ≈ 0.0, result.distances)
        # Capture rate should be 1.0 at all tolerances
        @test all(r -> r ≈ 1.0, result.capture_rates)
        # No missed CPs
        missed = missed_critical_points(result, known)
        @test isempty(missed)
        # Metadata
        @test result.n_known == 3
        @test result.n_computed == 3
    end

    @testset "Basic Capture - None Found" begin
        # 3 known CPs, computed points very far away
        known = KnownCriticalPoints(
            [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]],
            [0.0, 1.0, 1.0],
            [:min, :saddle, :max],
            [(-2.0, 2.0), (-2.0, 2.0)]
        )
        # Computed points are far away (outside any reasonable tolerance)
        computed = [[100.0, 100.0], [-100.0, -100.0]]

        result = compute_capture_analysis(known, computed)

        # All capture rates should be 0.0 (default tolerances are fractions of domain diameter ≈ 5.66)
        @test all(r -> r ≈ 0.0, result.capture_rates)
        # All CPs missed
        missed = missed_critical_points(result, known)
        @test length(missed) == 3
    end

    @testset "Basic Capture - Empty Computed Points" begin
        known = KnownCriticalPoints(
            [[0.0, 0.0], [1.0, 0.0]],
            [0.0, 1.0],
            [:min, :saddle],
            [(-2.0, 2.0), (-2.0, 2.0)]
        )
        computed = Vector{Float64}[]

        result = compute_capture_analysis(known, computed)

        @test result.n_computed == 0
        @test all(isinf, result.distances)
        @test all(r -> r ≈ 0.0, result.capture_rates)
        @test all(idx -> idx == 0, result.nearest_indices)
    end

    @testset "Partial Capture" begin
        # 4 known CPs, computed points near 2 of them
        known = KnownCriticalPoints(
            [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0], [1.0, 1.0]],
            [0.0, 1.0, 1.0, 2.0],
            [:min, :saddle, :saddle, :max],
            [(-2.0, 2.0), (-2.0, 2.0)]
        )
        # domain_diameter = norm([4, 4]) = 4*sqrt(2) ≈ 5.657
        # Computed points: very close to [0,0] and [1,1], far from [1,0] and [0,1]
        computed = [[0.001, -0.001], [1.001, 1.001], [50.0, 50.0]]

        result = compute_capture_analysis(known, computed;
            tolerance_fractions = [0.001, 0.01, 0.05, 0.1]
        )

        # At the smallest tolerance (0.001 * 5.657 ≈ 0.00566), the close points have
        # distance ≈ 0.0014 which IS within this tolerance
        # At tolerance 0.01 * 5.657 ≈ 0.0566, both close points should be captured
        # Known CPs at [1,0] and [0,1] should NOT be captured at any reasonable tolerance

        # Check that exactly 2 are captured at tolerance_fractions=0.01
        tol_01_idx = findfirst(tf -> tf ≈ 0.01, result.tolerance_fractions)
        @test sum(result.captured_at[tol_01_idx]) == 2
        @test result.capture_rates[tol_01_idx] ≈ 0.5

        # Missed CPs should include indices 2 and 3 (the saddle points at [1,0] and [0,1])
        missed = missed_critical_points(result, known; tolerance_index = tol_01_idx)
        @test length(missed) == 2
        missed_indices = [m.index for m in missed]
        @test 2 in missed_indices  # [1.0, 0.0]
        @test 3 in missed_indices  # [0.0, 1.0]
    end

    @testset "Multiple Tolerances" begin
        # Set up known CPs at specific distances from computed points
        # Known CPs: at [0,0], [1,0], [2,0]
        # Computed CP: [0.05, 0] (distance 0.05 from [0,0], 0.95 from [1,0], 1.95 from [2,0])
        known = KnownCriticalPoints(
            [[0.0, 0.0], [1.0, 0.0], [2.0, 0.0]],
            [0.0, 1.0, 4.0],
            [:min, :saddle, :max],
            [(-5.0, 5.0), (-5.0, 5.0)]
        )
        # domain_diameter = norm([10, 10]) = 10*sqrt(2) ≈ 14.14
        computed = [[0.05, 0.0]]

        # domain_diameter = norm([10, 10]) = 10*sqrt(2) ≈ 14.142
        # dist([0,0] → [0.05,0]) = 0.05
        # dist([1,0] → [0.05,0]) = 0.95
        # dist([2,0] → [0.05,0]) = 1.95
        #
        # Tolerance fractions chosen so:
        # 0.004 * 14.142 = 0.0566 → captures [0,0] (dist=0.05 < 0.0566)
        # 0.06  * 14.142 = 0.849  → still only [0,0] (dist=0.95 > 0.849)
        # 0.07  * 14.142 = 0.990  → captures [0,0] and [1,0] (dist=0.95 < 0.990)
        # 0.15  * 14.142 = 2.121  → captures all 3 (dist=1.95 < 2.121)
        result = compute_capture_analysis(known, computed;
            tolerance_fractions = [0.004, 0.06, 0.07, 0.15]
        )

        # Verify tolerance_fractions are sorted (they already are)
        @test issorted(result.tolerance_fractions)
        # Verify tolerance_values are computed correctly
        @test result.tolerance_values ≈ result.tolerance_fractions .* result.domain_diameter

        # Capture rates should be monotonically non-decreasing
        for i in 2:length(result.capture_rates)
            @test result.capture_rates[i] >= result.capture_rates[i-1]
        end

        # Specific capture counts
        @test sum(result.captured_at[1]) == 1  # only [0,0] (0.05 < 0.0566)
        @test sum(result.captured_at[2]) == 1  # still only [0,0] (0.95 > 0.849)
        @test sum(result.captured_at[3]) == 2  # [0,0] and [1,0] (0.95 < 0.990)
        @test sum(result.captured_at[4]) == 3  # all (1.95 < 2.121)

        @test result.capture_rates[1] ≈ 1/3
        @test result.capture_rates[4] ≈ 1.0
    end

    @testset "Per-Type Capture Tracking" begin
        # 2 minima, 2 saddles, 1 maximum
        known = KnownCriticalPoints(
            [[0.0, 0.0], [1.0, 0.0],   # minima
             [0.5, 0.5], [0.5, -0.5],  # saddles
             [2.0, 2.0]],               # maximum
            [0.0, 0.1, 1.0, 1.0, 5.0],
            [:min, :min, :saddle, :saddle, :max],
            [(-5.0, 5.0), (-5.0, 5.0)]
        )
        # domain_diameter = 10*sqrt(2) ≈ 14.14

        # Computed points: near both minima and one saddle, far from other saddle and max
        computed = [
            [0.01, 0.01],    # near [0,0] (min)
            [0.99, 0.01],    # near [1,0] (min)
            [0.51, 0.49],    # near [0.5, 0.5] (saddle)
        ]
        # Distances: ~0.014, ~0.014, ~0.014 for captured ones
        # Distance to [0.5, -0.5]: nearest is [0.51, 0.49] → dist ≈ 0.99
        # Distance to [2.0, 2.0]: nearest is [0.51, 0.49] → dist ≈ 2.12

        result = compute_capture_analysis(known, computed;
            tolerance_fractions = [0.002, 0.01, 0.1]
        )
        # tol_abs: [0.028, 0.1414, 1.414]

        # At tol 0.002 (abs ≈ 0.028): captures the 3 close points (2 min + 1 saddle)
        @test result.type_capture_rates[:min][1] ≈ 1.0  # 2/2
        @test result.type_capture_rates[:saddle][1] ≈ 0.5  # 1/2
        @test result.type_capture_rates[:max][1] ≈ 0.0  # 0/1

        # At tol 0.1 (abs ≈ 1.414): captures saddle at [0.5, -0.5] too (dist ≈ 0.99)
        @test result.type_capture_rates[:saddle][3] ≈ 1.0  # 2/2

        # Type counts
        @test result.type_counts[:min] == 2
        @test result.type_counts[:saddle] == 2
        @test result.type_counts[:max] == 1
    end

    @testset "Set-Based Matching" begin
        # Multiple computed points near the SAME known CP
        # Only 1 known CP should be counted as captured (not 2)
        known = KnownCriticalPoints(
            [[0.0, 0.0], [10.0, 10.0]],
            [0.0, 100.0],
            [:min, :max],
            [(-20.0, 20.0), (-20.0, 20.0)]
        )
        # domain_diameter = norm([40, 40]) = 40*sqrt(2) ≈ 56.57

        # 3 computed points all near [0,0], none near [10,10]
        computed = [
            [0.01, 0.01],
            [-0.01, 0.01],
            [0.02, -0.02],
        ]

        result = compute_capture_analysis(known, computed;
            tolerance_fractions = [0.001, 0.01, 0.1]
        )

        # At tol 0.001 (abs ≈ 0.057): all 3 computed points are near [0,0]
        # but only 1 known CP is captured → rate = 0.5
        @test result.capture_rates[1] ≈ 0.5
        @test sum(result.captured_at[1]) == 1

        # [10,10] should be missed at all reasonable tolerances
        # Distance from [10,10] to nearest computed ≈ 14.1
        @test result.distances[2] > 14.0
    end

    @testset "Missed Critical Points Details" begin
        known = KnownCriticalPoints(
            [[0.0, 0.0], [5.0, 5.0], [10.0, 10.0]],
            [0.0, 25.0, 100.0],
            [:min, :saddle, :max],
            [(-15.0, 15.0), (-15.0, 15.0)]
        )
        computed = [[0.01, -0.01]]  # only near [0,0]

        result = compute_capture_analysis(known, computed;
            tolerance_fractions = [0.01, 0.05]
        )

        # At largest tolerance (0.05): only [0,0] captured
        missed = missed_critical_points(result, known)
        @test length(missed) == 2

        # Check named tuple fields
        m1 = missed[1]
        @test haskey(pairs(m1) |> Dict, :index)
        @test haskey(pairs(m1) |> Dict, :point)
        @test haskey(pairs(m1) |> Dict, :value)
        @test haskey(pairs(m1) |> Dict, :type)
        @test haskey(pairs(m1) |> Dict, :nearest_distance)

        # Verify the missed CPs are [5,5] and [10,10]
        missed_indices = [m.index for m in missed]
        @test 2 in missed_indices
        @test 3 in missed_indices

        # Check specific missed CP data
        m_saddle = first(filter(m -> m.type == :saddle, missed))
        @test m_saddle.point ≈ [5.0, 5.0]
        @test m_saddle.value ≈ 25.0
        @test m_saddle.nearest_distance > 0.0

        # Check tolerance_index parameter
        missed_strict = missed_critical_points(result, known; tolerance_index = 1)
        @test length(missed_strict) >= length(missed)  # stricter tolerance → more missed

        # Error on invalid tolerance_index
        @test_throws ErrorException missed_critical_points(result, known; tolerance_index = 0)
        @test_throws ErrorException missed_critical_points(result, known; tolerance_index = 100)
    end

    @testset "Adaptive Tolerance - Domain Size Effect" begin
        # Same point configuration, different domain sizes
        # Points: known at [0,0], computed at [0.5, 0]
        # Distance = 0.5 always
        points = [[0.0, 0.0]]
        values = [0.0]
        types = [:min]
        computed = [[0.5, 0.0]]

        # Small domain: [-1, 1]^2, diameter = 2*sqrt(2) ≈ 2.83
        # tol at 0.2 = 0.566 → captures (0.5 < 0.566)
        known_small = KnownCriticalPoints(points, values, types, [(-1.0, 1.0), (-1.0, 1.0)])
        result_small = compute_capture_analysis(known_small, computed;
            tolerance_fractions = [0.1, 0.2]
        )

        # Large domain: [-10, 10]^2, diameter = 20*sqrt(2) ≈ 28.28
        # tol at 0.2 = 5.66 → captures (0.5 < 5.66)
        # tol at 0.01 = 0.283 → does NOT capture (0.5 > 0.283)
        known_large = KnownCriticalPoints(points, values, types, [(-10.0, 10.0), (-10.0, 10.0)])
        result_large = compute_capture_analysis(known_large, computed;
            tolerance_fractions = [0.01, 0.2]
        )

        # Verify tolerance_values scale with domain
        @test result_large.tolerance_values[2] > result_small.tolerance_values[2]

        # Small domain at 0.1: tol = 0.283 → 0.5 > 0.283, NOT captured
        @test result_small.capture_rates[1] ≈ 0.0
        # Small domain at 0.2: tol = 0.566 → 0.5 < 0.566, captured
        @test result_small.capture_rates[2] ≈ 1.0

        # Large domain at 0.01: tol = 0.283 → 0.5 > 0.283, NOT captured
        @test result_large.capture_rates[1] ≈ 0.0
        # Large domain at 0.2: tol = 5.66 → 0.5 < 5.66, captured
        @test result_large.capture_rates[2] ≈ 1.0
    end

    @testset "Tolerance Fractions Sorted" begin
        known = KnownCriticalPoints(
            [[0.0, 0.0]], [0.0], [:min],
            [(-1.0, 1.0), (-1.0, 1.0)]
        )
        computed = [[0.1, 0.0]]

        # Pass unsorted tolerance fractions
        result = compute_capture_analysis(known, computed;
            tolerance_fractions = [0.1, 0.01, 0.05, 0.001]
        )

        # Should be sorted ascending in result
        @test issorted(result.tolerance_fractions)
        @test result.tolerance_fractions == [0.001, 0.01, 0.05, 0.1]
    end

    @testset "Nearest Indices" begin
        known = KnownCriticalPoints(
            [[0.0, 0.0], [3.0, 0.0]],
            [0.0, 9.0],
            [:min, :max],
            [(-5.0, 5.0), (-5.0, 5.0)]
        )
        computed = [
            [10.0, 10.0],  # idx 1: far from both
            [0.1, 0.0],    # idx 2: near [0,0]
            [2.9, 0.0],    # idx 3: near [3,0]
        ]

        result = compute_capture_analysis(known, computed)

        # Known CP [0,0] should be nearest to computed idx 2
        @test result.nearest_indices[1] == 2
        @test result.distances[1] ≈ 0.1

        # Known CP [3,0] should be nearest to computed idx 3
        @test result.nearest_indices[2] == 3
        @test result.distances[2] ≈ 0.1
    end

    @testset "Print Functions" begin
        known = KnownCriticalPoints(
            [[0.0, 0.0], [1.0, 0.0], [0.5, 0.5]],
            [0.0, 1.0, 0.5],
            [:min, :max, :saddle],
            [(-2.0, 2.0), (-2.0, 2.0)]
        )
        computed = [[0.01, 0.01], [0.99, 0.01]]

        result = compute_capture_analysis(known, computed)

        @testset "print_capture_summary" begin
            pipe = Pipe()
            Base.link_pipe!(pipe; reader_supports_async=true, writer_supports_async=true)
            print_capture_summary(result, known; io = pipe.in)
            close(pipe.in)
            output = read(pipe.out, String)

            @test contains(output, "Capture Analysis")
            @test contains(output, "Tol (frac)")
            @test contains(output, "Rate")
            @test contains(output, "Per-Type")
            # Should have a missed CPs section (saddle at [0.5, 0.5] is likely missed)
            @test contains(output, "Missed") || contains(output, "captured")
        end

        @testset "print_degree_capture_convergence" begin
            # Create two fake degree results
            result2 = compute_capture_analysis(known, [computed; [[0.49, 0.51]]])

            degree_results = [(4, result), (6, result2)]

            pipe = Pipe()
            Base.link_pipe!(pipe; reader_supports_async=true, writer_supports_async=true)
            print_degree_capture_convergence(degree_results; io = pipe.in)
            close(pipe.in)
            output = read(pipe.out, String)

            @test contains(output, "Capture Rate vs Polynomial Degree")
            @test contains(output, "Degree")
            @test contains(output, "# Computed")
        end

        @testset "print_degree_capture_convergence error on empty" begin
            @test_throws ErrorException print_degree_capture_convergence(
                Tuple{Int, CaptureResult}[]
            )
        end

        @testset "print_degree_capture_convergence error on inconsistent tolerances" begin
            known2 = KnownCriticalPoints(
                [[0.0, 0.0]], [0.0], [:min],
                [(-2.0, 2.0), (-2.0, 2.0)]
            )
            r_a = compute_capture_analysis(known2, [[0.01, 0.01]];
                tolerance_fractions = [0.01, 0.05])
            r_b = compute_capture_analysis(known2, [[0.01, 0.01]];
                tolerance_fractions = [0.02, 0.1])  # different fractions
            @test_throws ErrorException print_degree_capture_convergence(
                [(4, r_a), (6, r_b)]
            )
        end
    end

    @testset "All Captured - No Missed Table" begin
        # When all CPs are captured, print should say so
        known = KnownCriticalPoints(
            [[0.0, 0.0]], [0.0], [:min],
            [(-1.0, 1.0), (-1.0, 1.0)]
        )
        computed = [[0.0, 0.0]]
        result = compute_capture_analysis(known, computed)

        pipe = Pipe()
        Base.link_pipe!(pipe; reader_supports_async=true, writer_supports_async=true)
        print_capture_summary(result, known; io = pipe.in)
        close(pipe.in)
        output = read(pipe.out, String)

        @test contains(output, "All 1 known critical points captured")
    end

    @testset "Deuflhard 2D Smoke Test" begin
        # Use deuflhard_2d from test fixtures
        # Known minimum near (0, 0) with value ≈ 4.0 ((exp(0) - 3)^2 + 0 = 4)
        f_origin = deuflhard_2d([0.0, 0.0])
        @test f_origin ≈ 4.0  # (1 - 3)^2 + 0^2 = 4

        known = KnownCriticalPoints(
            [[0.0, 0.0]],
            [f_origin],
            [:min],
            [(-1.2, 1.2), (-1.2, 1.2)]
        )
        # domain_diameter = norm([2.4, 2.4]) = 2.4*sqrt(2) ≈ 3.394

        # Computed point near origin (as if polynomial found it)
        computed_near = [[0.02, -0.01]]
        result_near = compute_capture_analysis(known, computed_near;
            tolerance_fractions = [0.01, 0.05, 0.1]
        )

        # Distance ≈ 0.022, tol at 0.01 = 0.034 → captured
        @test result_near.capture_rates[1] ≈ 1.0

        # Computed point far from origin
        computed_far = [[1.0, 1.0]]
        result_far = compute_capture_analysis(known, computed_far;
            tolerance_fractions = [0.01, 0.05, 0.1]
        )

        # Distance ≈ 1.414, even tol at 0.1 = 0.339 → NOT captured
        @test result_far.capture_rates[3] ≈ 0.0
    end

    @testset "build_known_cps_from_2d_product" begin
        @testset "Export" begin
            @test isdefined(GlobtimPostProcessing, :build_known_cps_from_2d_product)
        end

        @testset "Deuflhard 2D → 4D" begin
            # Use deuflhard_2d from test fixtures
            # We know it has critical points; use a small subset for testing
            # Origin is a saddle in 2D (eigs [-8, 8])
            # [0.741, 0.741] approx is a minimum (both eigs positive)
            pts_2d = [
                [0.0, 0.0],                                    # saddle
                [-0.741151903683758, 0.741151903683749],        # min
                [-0.126217280731682, -0.126217280731676],       # max
            ]
            b4d = [(-1.2, 1.2), (-1.2, 1.2), (-1.2, 1.2), (-1.2, 1.2)]

            known_4d = build_known_cps_from_2d_product(deuflhard_2d, pts_2d, b4d)

            # Should produce 3^2 = 9 4D critical points
            @test length(known_4d.points) == 9
            @test length(known_4d.values) == 9
            @test length(known_4d.types) == 9

            # Domain diameter: norm([2.4, 2.4, 2.4, 2.4]) = 4.8
            @test known_4d.domain_diameter ≈ 4.8

            # Type distribution: 1 min * 1 min = 1 min, 1 max * 1 max = 1 max
            n_min = count(t -> t == :min, known_4d.types)
            n_max = count(t -> t == :max, known_4d.types)
            n_saddle = count(t -> t == :saddle, known_4d.types)
            @test n_min == 1   # min+min
            @test n_max == 1   # max+max
            @test n_saddle == 7  # everything else

            # Check that values are sums of 2D values
            f_origin = deuflhard_2d([0.0, 0.0])
            f_min2d = deuflhard_2d([-0.741151903683758, 0.741151903683749])
            f_max2d = deuflhard_2d([-0.126217280731682, -0.126217280731676])

            # Find the min+min point (both components are the 2D minimum)
            min_idx = findfirst(t -> t == :min, known_4d.types)
            @test known_4d.values[min_idx] ≈ 2 * f_min2d

            # Find the max+max point
            max_idx = findfirst(t -> t == :max, known_4d.types)
            @test known_4d.values[max_idx] ≈ 2 * f_max2d

            # All 4D points should be 4-dimensional
            @test all(p -> length(p) == 4, known_4d.points)
        end

        @testset "Full Deuflhard CSV" begin
            # Load actual CSV if available
            csv_path = joinpath(@__DIR__, "..", "..", "globtim", "data",
                "matlab_critical_points", "valid_points_deuflhard.csv")
            if isfile(csv_path)
                using CSV, DataFrames
                df = CSV.read(csv_path, DataFrame)
                pts_2d = [[df[i, :x], df[i, :y]] for i in 1:nrow(df)]

                b4d = [(-1.2, 1.2), (-1.2, 1.2), (-1.2, 1.2), (-1.2, 1.2)]

                known_4d = build_known_cps_from_2d_product(deuflhard_2d, pts_2d, b4d)

                @test length(known_4d.points) == 225  # 15^2
                @test known_4d.domain_diameter ≈ 4.8

                n_min = count(t -> t == :min, known_4d.types)
                n_max = count(t -> t == :max, known_4d.types)
                n_saddle = count(t -> t == :saddle, known_4d.types)

                @test n_min == 36    # 6^2
                @test n_max == 4     # 2^2
                @test n_saddle == 185  # 225 - 36 - 4

                # All values should be non-negative (sum of squared terms)
                @test all(v -> v >= 0.0, known_4d.values)

                # Minimum value should be ≈ 0.0 (min+min with f≈0)
                @test minimum(known_4d.values) < 1e-10
            else
                @warn "Deuflhard CSV not found at $csv_path, skipping full CSV test"
            end
        end

        @testset "Error handling" begin
            @test_throws ErrorException build_known_cps_from_2d_product(
                deuflhard_2d, Vector{Float64}[], [(-1.0, 1.0), (-1.0, 1.0), (-1.0, 1.0), (-1.0, 1.0)]
            )
            # Wrong dimension bounds
            @test_throws ErrorException build_known_cps_from_2d_product(
                deuflhard_2d, [[0.0, 0.0]], [(-1.0, 1.0), (-1.0, 1.0)]  # 2D bounds, not 4D
            )
        end
    end

    @testset "Single Type - No Per-Type Table" begin
        # When there's only one type, per-type table should still work
        known = KnownCriticalPoints(
            [[0.0, 0.0], [1.0, 0.0]],
            [0.0, 1.0],
            [:min, :min],
            [(-2.0, 2.0), (-2.0, 2.0)]
        )
        computed = [[0.0, 0.0], [1.0, 0.0]]
        result = compute_capture_analysis(known, computed)

        @test length(result.type_capture_rates) == 1
        @test haskey(result.type_capture_rates, :min)
        @test all(r -> r ≈ 1.0, result.type_capture_rates[:min])

        # Print should work without error (per-type table skipped for single type)
        pipe = Pipe()
        Base.link_pipe!(pipe; reader_supports_async=true, writer_supports_async=true)
        print_capture_summary(result, known; io = pipe.in)
        close(pipe.in)
        output = read(pipe.out, String)
        @test contains(output, "Capture Analysis")
        # Should NOT contain "Per-Type" since there's only 1 type
        @test !contains(output, "Per-Type")
    end

    # ─── Newton-Based Critical Point Refinement ──────────────────────────────

    @testset "Newton Refinement Exports" begin
        @test isdefined(GlobtimPostProcessing, :CriticalPointRefinementResult)
        @test isdefined(GlobtimPostProcessing, :refine_to_critical_point)
        @test isdefined(GlobtimPostProcessing, :refine_to_critical_points)
        @test isdefined(GlobtimPostProcessing, :build_known_cps_from_refinement)
    end

    @testset "refine_to_critical_point" begin
        # Simple quadratic: f(x) = x₁² + x₂² → minimum at origin
        f_quad(x) = x[1]^2 + x[2]^2

        @testset "Finds minimum of quadratic (ForwardDiff)" begin
            result = refine_to_critical_point(f_quad, [0.5, 0.3]; gradient_method=:forwarddiff)
            @test result.converged
            @test result.gradient_norm < 1e-8
            @test result.cp_type == :min
            @test norm(result.point) < 1e-6
            @test all(λ -> λ > 0, result.eigenvalues)
        end

        @testset "Finds minimum of quadratic (FiniteDiff)" begin
            result = refine_to_critical_point(f_quad, [0.5, 0.3]; gradient_method=:finitediff)
            @test result.converged
            @test result.gradient_norm < 1e-6
            @test result.cp_type == :min
            @test norm(result.point) < 1e-4
        end

        @testset "Finds saddle point" begin
            # f(x) = x₁² - x₂² → saddle at origin
            f_saddle(x) = x[1]^2 - x[2]^2
            result = refine_to_critical_point(f_saddle, [0.1, 0.05]; gradient_method=:forwarddiff)
            @test result.converged
            @test result.cp_type == :saddle
            @test norm(result.point) < 1e-6
        end

        @testset "Finds maximum" begin
            # f(x) = -(x₁² + x₂²) → maximum at origin
            f_max(x) = -(x[1]^2 + x[2]^2)
            result = refine_to_critical_point(f_max, [0.3, -0.2]; gradient_method=:forwarddiff)
            @test result.converged
            @test result.cp_type == :max
            @test norm(result.point) < 1e-6
        end

        @testset "Respects box constraints" begin
            result = refine_to_critical_point(f_quad, [2.0, 2.0];
                gradient_method=:forwarddiff,
                bounds=[(0.5, 3.0), (0.5, 3.0)],
            )
            # The true minimum is at origin but box is [0.5, 3.0]²
            # Newton should converge but be clamped at lower bound
            @test all(result.point .>= 0.5 - 1e-10)
        end

        @testset "Batch version" begin
            pts = [[0.5, 0.3], [-0.2, 0.4], [0.1, -0.1]]
            results = refine_to_critical_points(f_quad, pts; gradient_method=:forwarddiff)
            @test length(results) == 3
            @test all(r -> r isa CriticalPointRefinementResult, results)
            @test all(r -> r.converged, results)
        end

        @testset "Deuflhard 2D — finds various CP types" begin
            # Start near a known saddle point of Deuflhard: approximately (0.507, -0.918)
            result = refine_to_critical_point(deuflhard_2d, [0.51, -0.92];
                gradient_method=:forwarddiff, tol=1e-10)
            @test result.converged
            @test result.gradient_norm < 1e-8
            @test result.cp_type in [:min, :max, :saddle]  # should find the nearby CP
        end

        @testset "Hessian skip on rejected CPs (accept_tol)" begin
            # Rosenbrock: f(x,y) = (1-x)^2 + 100(y-x^2)^2 — Newton doesn't converge in 2 iters from far away
            f_rosen(x) = (1 - x[1])^2 + 100 * (x[2] - x[1]^2)^2

            # With max_iterations=2 and strict tol, should NOT converge from [5,5]
            # accept_tol=1e-20 means the CP also won't be "accepted" → Hessian skipped
            result = refine_to_critical_point(f_rosen, [5.0, 5.0];
                gradient_method=:forwarddiff, tol=1e-12, accept_tol=1e-20,
                max_iterations=2)
            @test !result.converged
            @test result.gradient_norm >= 1e-20  # not within accept_tol
            @test result.cp_type == :unknown
            @test isempty(result.eigenvalues)
        end

        @testset "Hessian computed for accepted (non-converged) CPs" begin
            # Rosenbrock from a point that makes some progress but doesn't fully converge
            f_rosen(x) = (1 - x[1])^2 + 100 * (x[2] - x[1]^2)^2

            # From close-ish start with few iters, won't reach tol=1e-20 but gradient
            # should be moderate. Use generous accept_tol so it's "accepted".
            result = refine_to_critical_point(f_rosen, [0.9, 0.81];
                gradient_method=:forwarddiff, tol=1e-20, accept_tol=1e3,
                max_iterations=3)
            @test !result.converged  # tol is impossibly tight
            @test result.gradient_norm < 1e3  # within accept_tol
            @test result.cp_type in [:min, :max, :saddle, :degenerate]  # Hessian was computed
            @test !isempty(result.eigenvalues)
        end

        @testset "accept_tol=Inf (default) always computes Hessian" begin
            # Rosenbrock from far away — won't converge in 2 iters
            f_rosen(x) = (1 - x[1])^2 + 100 * (x[2] - x[1]^2)^2

            # Default accept_tol=Inf means Hessian is always computed even on rejected CPs
            result = refine_to_critical_point(f_rosen, [5.0, 5.0];
                gradient_method=:forwarddiff, tol=1e-12, max_iterations=2)
            @test !result.converged
            @test result.cp_type in [:min, :max, :saddle, :degenerate]  # NOT :unknown
            @test !isempty(result.eigenvalues)
        end
    end

    @testset "build_known_cps_from_refinement" begin
        # Use quadratic with known minimum at origin + saddle function
        # f(x) = x₁² + x₂² has one CP at origin (min)
        f_quad(x) = x[1]^2 + x[2]^2

        @testset "Basic: quadratic, multiple starts converge to same CP" begin
            raw_points = [[0.5, 0.3], [-0.2, 0.4], [0.1, -0.1], [-0.3, -0.2]]
            b2d = [(-1.0, 1.0), (-1.0, 1.0)]

            known = build_known_cps_from_refinement(f_quad, raw_points, b2d;
                gradient_method=:forwarddiff, dedup_fraction=0.01)

            # All 4 starts should converge to the same minimum at origin → 1 unique CP
            @test length(known.points) == 1
            @test known.types[1] == :min
            @test norm(known.points[1]) < 1e-4
            lb, ub = GlobtimPostProcessing.lower_bounds(b2d), GlobtimPostProcessing.upper_bounds(b2d)
            @test known.domain_diameter ≈ norm(ub .- lb)
        end

        @testset "Dedup separates distinct CPs" begin
            # f(x) = (x₁² - 1)² + x₂² → minima at (±1, 0), saddle at (0, 0)
            f_two_min(x) = (x[1]^2 - 1)^2 + x[2]^2

            raw_points = [
                [0.8, 0.1],   # should converge to (1, 0) min
                [-0.9, 0.1],  # should converge to (-1, 0) min
                [0.05, 0.05], # should converge to (0, 0) saddle
            ]
            b2d = [(-2.0, 2.0), (-2.0, 2.0)]

            known = build_known_cps_from_refinement(f_two_min, raw_points, b2d;
                gradient_method=:forwarddiff, dedup_fraction=0.01)

            # Should find 3 distinct CPs: two minima and one saddle
            @test length(known.points) == 3
            n_min = count(t -> t == :min, known.types)
            n_saddle = count(t -> t == :saddle, known.types)
            @test n_min == 2
            @test n_saddle == 1
        end

        @testset "Error on empty raw_points" begin
            @test_throws ErrorException build_known_cps_from_refinement(
                f_quad, Vector{Float64}[], [(-1.0, 1.0), (-1.0, 1.0)];
                gradient_method=:forwarddiff)
        end

        @testset "Error on dimension mismatch" begin
            @test_throws ErrorException build_known_cps_from_refinement(
                f_quad, [[0.5, 0.3]], [(-1.0, 1.0)];  # 1D bounds, 2D points
                gradient_method=:forwarddiff)
        end
    end

    # ─── Degree Convergence Summary and Verdict ──────────────────────────────

    @testset "DegreeConvergenceInfo + print_degree_convergence_summary" begin
        @testset "Exports" begin
            @test isdefined(GlobtimPostProcessing, :DegreeConvergenceInfo)
            @test isdefined(GlobtimPostProcessing, :print_degree_convergence_summary)
        end

        @testset "Prints without error" begin
            types = [:min, :saddle]
            known = KnownCriticalPoints([[0.0, 0.0], [1.0, 1.0]], [0.0, 2.0], types,
                [(-1.0, 1.0), (-1.0, 1.0)])
            dd = known.domain_diameter
            tol_fracs = [0.01, 0.05, 0.1]

            cr4 = compute_capture_analysis(known, [[0.3, 0.3], [1.2, 1.2]]; tolerance_fractions=tol_fracs)
            cr6 = compute_capture_analysis(known, [[0.01, 0.01], [1.0, 1.0]]; tolerance_fractions=tol_fracs)

            degree_capture = [(4, cr4), (6, cr6)]
            info = [
                DegreeConvergenceInfo(4, 0.5, 0.1, 10, 1e-2, 0.1),
                DegreeConvergenceInfo(6, 0.01, 0.003, 25, 1e-5, 0.001),
            ]

            pipe = Pipe()
            Base.link_pipe!(pipe; reader_supports_async=true, writer_supports_async=true)
            print_degree_convergence_summary(degree_capture, info; io=pipe.in)
            close(pipe.in)
            output = read(pipe.out, String)
            @test contains(output, "Degree Convergence Summary")
            @test contains(output, "Cap @5%")
        end
    end

    @testset "CaptureVerdict + compute_capture_verdict + print_capture_verdict" begin
        @testset "Exports" begin
            @test isdefined(GlobtimPostProcessing, :CaptureVerdict)
            @test isdefined(GlobtimPostProcessing, :compute_capture_verdict)
            @test isdefined(GlobtimPostProcessing, :print_capture_verdict)
        end

        @testset "Computes correct verdict" begin
            types = [:min, :min, :saddle]
            known = KnownCriticalPoints(
                [[0.0, 0.0], [1.0, 0.0], [0.5, 0.5]],
                [0.0, 1.0, 0.5], types,
                [(-2.0, 2.0), (-2.0, 2.0)])
            dd = known.domain_diameter
            tol_fracs = [0.01, 0.05, 0.1]

            # At degree 4: capture 1/3 at 5%
            cr4 = compute_capture_analysis(known, [[0.01, 0.01]]; tolerance_fractions=tol_fracs)
            # At degree 8: capture 3/3 at 5%
            cr8 = compute_capture_analysis(known, [[0.0, 0.0], [1.0, 0.0], [0.5, 0.5]];
                tolerance_fractions=tol_fracs)

            verdict = compute_capture_verdict([(4, cr4), (8, cr8)])
            @test verdict.best_degree == 8
            @test verdict.capture_rate ≈ 1.0
            @test verdict.n_captured == 3
            @test verdict.n_known == 3
            @test verdict.label == "EXCELLENT"
            @test length(verdict.type_breakdown) == 2  # :min and :saddle
            @test length(verdict.degree_trend) == 2    # deg 4 and 8
        end

        @testset "Prints without error" begin
            types = [:min, :saddle]
            known = KnownCriticalPoints(
                [[0.0, 0.0], [1.0, 1.0]],
                [0.0, 2.0], types,
                [(-2.0, 2.0), (-2.0, 2.0)])
            tol_fracs = [0.01, 0.05, 0.1]
            cr = compute_capture_analysis(known, [[0.0, 0.0], [1.0, 1.0]];
                tolerance_fractions=tol_fracs)

            verdict = compute_capture_verdict([(6, cr)])

            pipe = Pipe()
            Base.link_pipe!(pipe; reader_supports_async=true, writer_supports_async=true)
            print_capture_verdict(verdict; io=pipe.in)
            close(pipe.in)
            output = read(pipe.out, String)
            @test contains(output, "CAPTURE RESULT")
            @test contains(output, "EXCELLENT")
        end

        @testset "Error on missing tolerance fraction" begin
            types = [:min]
            known = KnownCriticalPoints([[0.0, 0.0]], [0.0], types, [(-1.0, 1.0), (-1.0, 1.0)])
            cr = compute_capture_analysis(known, [[0.0, 0.0]]; tolerance_fractions=[0.01, 0.1])

            # Default reference is 0.05, which is not in [0.01, 0.1]
            @test_throws ErrorException compute_capture_verdict([(4, cr)])
        end
    end

end
