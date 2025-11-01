#!/usr/bin/env julia

# Test if evaluate_all_critical_points accepts recovery_threshold keyword

using Pkg
Pkg.activate(@__DIR__)

println("Loading TrajectoryComparison module...")
include(joinpath(@__DIR__, "src", "TrajectoryComparison.jl"))
using .TrajectoryComparison

println("\nChecking methods for evaluate_all_critical_points:")
println(methods(TrajectoryComparison.evaluate_all_critical_points))

println("\nTrying to call with recovery_threshold keyword...")
using DataFrames

config = Dict("p_true" => [0.2, 0.3, 0.5, 0.6])
empty_df = DataFrame()

try
    result = TrajectoryComparison.evaluate_all_critical_points(config, empty_df; recovery_threshold=0.05)
    println("✓ SUCCESS: Function accepts recovery_threshold keyword")
    println("Result columns: ", names(result))
catch e
    println("✗ FAILED: ", e)
    rethrow(e)
end
