#!/usr/bin/env julia

"""
Quick script to find and visualize the best critical point
This bypasses the interactive menu and goes straight to results
"""

using Pkg
Pkg.activate(@__DIR__)

using JSON3
using DataFrames
using Printf

# Force fresh load by clearing any cached modules
if isdefined(Main, :TrajectoryComparison)
    @eval Main TrajectoryComparison = nothing
end

include(joinpath(@__DIR__, "src", "TrajectoryComparison.jl"))
using .TrajectoryComparison

function find_best_critical_point(exp_path::String)
    println("═" ^ 80)
    println("Finding Best Critical Point")
    println("═" ^ 80)
    println("Experiment: $exp_path\n")

    # Load config
    config_file = joinpath(exp_path, "experiment_config.json")
    config = JSON3.read(read(config_file, String))

    println("True parameters: ", config["p_true"])
    println()

    # Find all degree files
    csv_files = filter(f -> occursin(r"critical_points_deg_\d+\.csv", f), readdir(exp_path))
    degrees = Int[]
    for csv_file in csv_files
        m = match(r"deg_(\d+)\.csv", csv_file)
        m !== nothing && push!(degrees, parse(Int, m[1]))
    end
    sort!(degrees)

    println("Available degrees: ", degrees)
    println()

    # Search through all degrees for the best point
    best_point = nothing
    best_distance = Inf
    best_degree = 0

    for degree in degrees
        println("Checking degree $degree...")
        cp_df = TrajectoryComparison.load_critical_points_for_degree(exp_path, degree)

        if nrow(cp_df) == 0
            println("  No critical points")
            continue
        end

        # Evaluate all points for this degree
        evaluated = TrajectoryComparison.evaluate_all_critical_points(config, cp_df; recovery_threshold=0.05)

        # Find best in this degree
        valid_idx = findall(!isnan, evaluated.param_distance)
        if !isempty(valid_idx)
            min_idx = argmin(evaluated.param_distance[valid_idx])
            local_best_idx = valid_idx[min_idx]
            local_best_dist = evaluated.param_distance[local_best_idx]

            println("  Best distance: $local_best_dist")

            if local_best_dist < best_distance
                best_distance = local_best_dist
                best_point = evaluated[local_best_idx, :]
                best_degree = degree
            end
        end
    end

    println()
    println("═" ^ 80)
    println("BEST CRITICAL POINT FOUND")
    println("═" ^ 80)
    println("Degree: $best_degree")
    println("Parameter distance: $best_distance")
    println("Trajectory distance: ", best_point.trajectory_distance)
    println()
    println("Critical point coordinates:")
    for col in names(best_point)
        if startswith(string(col), "x")
            @printf("  %s = %12.6f\n", col, best_point[col])
        end
    end
    println("  z  = ", best_point.z)
    println()

    return (point=best_point, degree=best_degree, config=config)
end

# Main execution
if length(ARGS) > 0
    exp_path = ARGS[1]
else
    exp_path = "/Users/ghscholt/GlobalOptim/globtimcore/experiments/lotka_volterra_4d_study/configs_20251006_160051/hpc_results/lotka_volterra_4d_exp4_range1.6_20251006_230001"
end

result = find_best_critical_point(exp_path)

println("Next step: Generate trajectories using these parameters")
println("Parameters for ODE: [", join([result.point[Symbol("x$i")] for i in 1:4], ", "), "]")
