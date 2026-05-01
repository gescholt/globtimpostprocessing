# Tests for TreeDisplay utility functions
# Run with: julia --project=pkg/globtimpostprocessing test/test_tree_display.jl
#
# These test pure formatting utilities — no SubdivisionTree required.

using Test
using GlobtimPostProcessing

@testset "Tracker Utilities" begin
    @testset "progress_bar" begin
        @test progress_bar(0, 50) == "░░░░░░░░░░"
        @test progress_bar(25, 50) == "█████░░░░░"
        @test progress_bar(50, 50) == "██████████"
        @test progress_bar(100, 50) == "██████████"  # clamp >1
        @test progress_bar(1, 10) == "█░░░░░░░░░"
        @test progress_bar(5, 10) == "█████░░░░░"
    end

    @testset "format_error" begin
        @test format_error([Inf, Inf, Inf]) == "?"
        @test format_error([0.1, 0.2, Inf]) == "0.3"
        @test format_error([0.123456]) == "0.123"  # 3 sigfigs
        @test format_error(Float64[]) == "?"  # empty
        @test format_error([1.0, 2.0, 3.0]) == "6.0"
    end

    @testset "format_time" begin
        @test format_time(0.0) == "0.0s"
        @test format_time(5.5) == "5.5s"
        @test format_time(59.9) == "59.9s"
        @test format_time(60.0) == "1.0m"
        @test format_time(90.0) == "1.5m"
        @test format_time(120.0) == "2.0m"
    end
end
