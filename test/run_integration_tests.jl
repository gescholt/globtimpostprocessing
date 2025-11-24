#!/usr/bin/env julia
"""
Run Integration Tests with Real Fixtures

This script runs only the integration tests using real globtimcore data.
Use this for quick validation of the complete workflow.

Usage:
    julia --project=. test/run_integration_tests.jl

Or from test directory:
    julia --project=.. run_integration_tests.jl
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Test

println("="^70)
println("Running Integration Tests with Real Fixtures")
println("="^70)
println()

@testset "Integration: Real Fixtures End-to-End" begin
    include("test_integration_real_fixtures.jl")
end

println()
println("="^70)
println("Integration tests completed!")
println("="^70)
