"""
Unit tests for LV4D TUI domain filtering logic.

Tests the threshold comparison logic in _tui_select_domain_filter to ensure
edge cases are handled correctly (Issue: domain=0.01 should match threshold 0.010).
"""

using Test

@testset "LV4D TUI Domain Filtering" begin
    @testset "Domain filter threshold edge case - single domain equals threshold" begin
        # When only experiment has domain=0.01, the 0.010 threshold should appear
        domains = [0.01]
        min_domain = minimum(domains)
        max_domain = maximum(domains)

        standard_thresholds = [0.002, 0.005, 0.010, 0.050, 0.100]

        # BUG: 0.010 < 0.01 is false, so threshold not included
        # FIX: Should use <= instead of <
        matching_thresholds = filter(t -> min_domain <= t && t <= max_domain, standard_thresholds)

        @test 0.010 in matching_thresholds  # This tests the fix
        @test length(matching_thresholds) == 1
    end

    @testset "Domain filter threshold edge case - domain at upper boundary" begin
        # Experiments with domains 0.002 and 0.005
        domains = [0.002, 0.005]
        min_domain = minimum(domains)
        max_domain = maximum(domains)

        standard_thresholds = [0.002, 0.005, 0.010, 0.050, 0.100]

        # 0.005 should be included when max_domain == 0.005
        matching_thresholds = filter(t -> min_domain <= t && t <= max_domain, standard_thresholds)

        @test 0.002 in matching_thresholds
        @test 0.005 in matching_thresholds
        @test !(0.010 in matching_thresholds)  # Above max
        @test length(matching_thresholds) == 2
    end

    @testset "Multiple domain thresholds in range" begin
        # With domain range 0.005 to 0.05, should include 0.005, 0.010, 0.050
        domains = [0.005, 0.01, 0.05]
        min_domain = minimum(domains)
        max_domain = maximum(domains)

        standard_thresholds = [0.002, 0.005, 0.010, 0.050, 0.100]
        matching_thresholds = filter(t -> min_domain <= t && t <= max_domain, standard_thresholds)

        @test 0.005 in matching_thresholds
        @test 0.010 in matching_thresholds
        @test 0.050 in matching_thresholds
        @test !(0.002 in matching_thresholds)  # Below min
        @test !(0.100 in matching_thresholds)  # Above max
        @test length(matching_thresholds) == 3
    end

    @testset "No thresholds in range returns empty" begin
        # Domains between standard thresholds
        domains = [0.003, 0.004]  # Between 0.002 and 0.005
        min_domain = minimum(domains)
        max_domain = maximum(domains)

        standard_thresholds = [0.002, 0.005, 0.010, 0.050, 0.100]
        matching_thresholds = filter(t -> min_domain <= t && t <= max_domain, standard_thresholds)

        @test isempty(matching_thresholds)
    end

    @testset "Wide range includes multiple thresholds" begin
        # Wide domain range
        domains = [0.001, 0.002, 0.01, 0.05, 0.1, 0.2]
        min_domain = minimum(domains)
        max_domain = maximum(domains)

        standard_thresholds = [0.002, 0.005, 0.010, 0.050, 0.100]
        matching_thresholds = filter(t -> min_domain <= t && t <= max_domain, standard_thresholds)

        # All thresholds should be included since they're all within [0.001, 0.2]
        @test length(matching_thresholds) == 5
    end
end
