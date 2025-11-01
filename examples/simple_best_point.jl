#!/usr/bin/env julia

"""
Simple script to find the best critical point by parameter distance only.
Skips trajectory evaluation to avoid world age issues.
"""

using Pkg
Pkg.activate(@__DIR__)

using CSV
using DataFrames
using JSON3
using Printf
using Statistics
using LinearAlgebra

function find_best_by_param_distance(exp_path::String)
    println("=" ^ 80)
    println("Finding Best Critical Point (by parameter distance)")
    println("=" ^ 80)
    println("Path: $exp_path\n")

    # Load config
    config_file = joinpath(exp_path, "experiment_config.json")
    config = JSON3.read(read(config_file, String))
    p_true = collect(config["p_true"])

    println("True parameters: ", p_true)
    println()

    # Find all degrees
    csv_files = filter(f -> occursin(r"critical_points_deg_\d+\.csv", f), readdir(exp_path))
    degrees = Int[]
    for csv_file in csv_files
        m = match(r"deg_(\d+)\.csv", csv_file)
        m !== nothing && push!(degrees, parse(Int, m[1]))
    end
    sort!(degrees)

    println("Available degrees: ", degrees)
    println()

    # Search for best point
    best_point = nothing
    best_dist = Inf
    best_degree = 0

    for degree in degrees
        csv_path = joinpath(exp_path, "critical_points_deg_$(degree).csv")
        cp_df = CSV.read(csv_path, DataFrame)

        if nrow(cp_df) == 0
            continue
        end

        # Extract parameter columns (x1, x2, x3, x4)
        param_cols = [Symbol("x$i") for i in 1:length(p_true)]

        for row in eachrow(cp_df)
            # Get parameters from critical point
            p_found = [row[col] for col in param_cols]

            # Compute L2 distance
            dist = norm(p_found - p_true)

            if dist < best_dist
                best_dist = dist
                best_point = row
                best_degree = degree
            end
        end

        println("Degree $degree: best distance = ", best_dist)
    end

    println()
    println("=" ^ 80)
    println("BEST CRITICAL POINT FOUND")
    println("=" ^ 80)
    println("Degree: $best_degree")
    println("Parameter distance: $best_dist")
    println("Objective value: ", best_point.z)
    println()
    println("Critical point parameters:")
    for i in 1:length(p_true)
        col = Symbol("x$i")
        @printf("  x%d = %12.6f  (true: %12.6f, error: %12.6e)\n",
                i, best_point[col], p_true[i], best_point[col] - p_true[i])
    end
    println()

    return (point=best_point, degree=best_degree, config=config, p_true=p_true)
end

# Main
if length(ARGS) > 0
    exp_path = ARGS[1]
else
    exp_path = "/Users/ghscholt/GlobalOptim/globtimcore/experiments/lotka_volterra_4d_study/configs_20251006_160051/hpc_results/lotka_volterra_4d_exp4_range1.6_20251006_230001"
end

result = find_best_by_param_distance(exp_path)

println("Next steps:")
println("1. Use these parameters to generate trajectories in globtimcore")
println("2. Parameters: [", join([result.point[Symbol("x$i")] for i in 1:length(result.p_true)], ", "), "]")
println("3. Configuration: $(result.config["model_func"]), IC=$(result.config["ic"]), t=$(result.config["time_interval"])")
