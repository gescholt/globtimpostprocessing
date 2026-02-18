#!/usr/bin/env julia
#=
ENVIRONMENT NOTE: This is a standalone entry-point script, NOT part of the
GlobtimPostProcessing package test suite. It requires `Globtim` and `ArgParse`
to be available in the active environment. Run it from a shared monorepo
environment that has all packages developed, e.g.:
    julia --project=@monorepo scripts/refine_subdivision_results.jl ...
Do NOT run this from the globtimpostprocessing package environment — those
dependencies are intentionally not declared in its Project.toml.
=#
"""
PE-05b: Multi-Start Refinement from Subdivision Results

Tests whether local optimization from each orthant's best polynomial critical point
can recover p_true better than the global polynomial minimum selection.

Key question: Does orthant 13's best point (where p_true is) converge to p_true
even though orthant 16 has the lowest polynomial minimum?

Usage:
    julia experiments/lv4d_2025/refine_subdivision_results.jl \\
        --experiment-dir globtim_results/lotka_volterra_4d/lv4d_subdivision_GN8_deg8-8_domain0.15_seed1_20260108_170451
"""

const SCRIPT_DIR = @__DIR__
const POSTPROC_ROOT = dirname(SCRIPT_DIR)  # scripts/ -> globtimpostprocessing/

using Pkg
Pkg.activate(POSTPROC_ROOT)
Pkg.instantiate()

pushfirst!(LOAD_PATH, POSTPROC_ROOT)

using GlobtimPostProcessing
using JSON
using CSV
using DataFrames
using LinearAlgebra
using Statistics
using ArgParse
using Printf

function parse_args_refine()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--experiment-dir"
            help = "Path to subdivision experiment results directory"
            arg_type = String
            required = true
        "--max-time"
            help = "Maximum time per point in seconds"
            arg_type = Float64
            default = 60.0
        "--degree"
            help = "Polynomial degree to analyze"
            arg_type = Int
            default = 8
    end
    return parse_args(s)
end

function find_best_point_per_orthant(df::DataFrame)
    """Find the critical point with lowest z value in each orthant."""
    result = combine(groupby(df, :orthant)) do sdf
        idx = argmin(sdf.z)
        sdf[idx, [:x1, :x2, :x3, :x4, :z]]
    end
    return sort(result, :orthant)
end

function run_multistart_refinement(args)
    experiment_dir = args["experiment-dir"]
    if !isabspath(experiment_dir)
        experiment_dir = abspath(experiment_dir)
    end

    degree = args["degree"]
    max_time = args["max-time"]

    println()
    println("="^70)
    println("PE-05b: MULTI-START REFINEMENT FROM SUBDIVISION")
    println("="^70)
    println("Experiment: $(basename(experiment_dir))")
    println()

    # Load experiment config
    config_path = joinpath(experiment_dir, "experiment_config.json")
    if !isfile(config_path)
        error("experiment_config.json not found in $experiment_dir")
    end
    exp_config = JSON.parsefile(config_path)

    # Extract parameters from config
    p_true = Float64.(exp_config["p_true"])
    p_center = Float64.(exp_config["p_center"])

    println("p_true = $(round.(p_true, digits=4))")
    println("p_center = $(round.(p_center, digits=4))")
    println()

    # Load critical points
    csv_path = joinpath(experiment_dir, "critical_points_merged_deg_$(degree).csv")
    if !isfile(csv_path)
        error("Critical points file not found: $csv_path")
    end
    df = CSV.read(csv_path, DataFrame)
    println("Loaded $(nrow(df)) critical points from degree $degree")
    println()

    # Find best point per orthant
    starts = find_best_point_per_orthant(df)
    n_orthants = nrow(starts)
    println("Found best point per orthant ($n_orthants orthants)")

    # Print starting points table
    println()
    println("-"^70)
    println(@sprintf("%-8s %-12s %-50s", "Orthant", "Start f(p)", "Coordinates"))
    println("-"^70)
    for row in eachrow(starts)
        coords = @sprintf("[%.4f, %.4f, %.4f, %.4f]", row.x1, row.x2, row.x3, row.x4)
        println(@sprintf("%-8d %-12.2f %-50s", row.orthant, row.z, coords))
    end
    println("-"^70)
    println()

    # Recreate error function
    println("Recreating error function...")

    # Check if IC and time_interval are in config (they should be for subdivision experiments)
    if !haskey(exp_config, "ic") || !haskey(exp_config, "time_interval")
        # Use defaults from Lotka-Volterra 4D (4 state variables: prey1, pred1, prey2, pred2)
        IC = [10.0, 10.0, 10.0, 10.0]
        TIME_INTERVAL = (0.0, 20.0)
        NUM_POINTS = 100
        @debug "Using default IC=$IC, TIME_INTERVAL=$TIME_INTERVAL, NUM_POINTS=$NUM_POINTS"
    else
        IC = Float64.(exp_config["ic"])
        TIME_INTERVAL = Tuple(Float64.(exp_config["time_interval"]))
        NUM_POINTS = exp_config["num_points"]
    end

    model, _params, _states, outputs = define_daisy_ex3_model_4D()

    error_func = make_error_distance(
        model, outputs, IC, p_true, TIME_INTERVAL, NUM_POINTS, L2_norm
    )

    # Extract starting points as vectors
    start_points = [[row.x1, row.x2, row.x3, row.x4] for row in eachrow(starts)]
    start_values = [row.z for row in eachrow(starts)]
    orthant_ids = [row.orthant for row in eachrow(starts)]

    # Compute recovery BEFORE refinement
    recovery_before = [norm(pt .- p_true) for pt in start_points]

    # Configure refinement
    println()
    println("--- RUNNING LOCAL REFINEMENT (NelderMead, max $(max_time)s/point) ---")

    config = ode_refinement_config(max_time_per_point=max_time)

    # Run batch refinement
    results = refine_critical_points_batch(
        error_func,
        start_points;
        method=config.method,
        max_time=config.max_time_per_point,
        max_iterations=config.max_iterations,
        f_abstol=config.f_abstol,
        x_abstol=config.x_abstol,
        show_progress=true
    )

    # Extract refined data
    refined_points = [r.refined for r in results]
    refined_values = [r.value_refined for r in results]
    converged = [r.converged for r in results]
    timed_out = [r.timed_out for r in results]
    f_calls = [r.f_calls for r in results]
    time_elapsed = [r.time_elapsed for r in results]
    recovery_after = [norm(pt .- p_true) for pt in refined_points]

    # Results table
    println()
    println("-"^70)
    println(@sprintf("%-8s %-12s %-14s %-10s %-10s %-8s",
        "Orthant", "Start f(p)", "Refined f(p)", "Recovery", "Time", "Status"))
    println("-"^70)

    for i in 1:n_orthants
        status = converged[i] ? "OK" : (timed_out[i] ? "TIMEOUT" : "FAIL")
        recovery_pct = @sprintf("%.1f%%", recovery_after[i] * 100)
        println(@sprintf("%-8d %-12.2f %-14.4f %-10s %-10.1fs %-8s",
            orthant_ids[i], start_values[i], refined_values[i],
            recovery_pct, time_elapsed[i], status))
    end
    println("-"^70)

    # Find best recovery
    best_idx = argmin(recovery_after)
    best_orthant = orthant_ids[best_idx]
    best_recovery = recovery_after[best_idx]
    best_refined_value = refined_values[best_idx]

    # Find which orthant contains p_true (for reference)
    # Using same logic as plot_orthant_analysis.jl
    function point_to_orthant(point, center)
        signs = sign.(point .- center)
        bits = [(s > 0 ? 1 : 0) for s in signs]
        return sum(bits[i] * 2^(i-1) for i in eachindex(bits)) + 1
    end
    true_orthant = point_to_orthant(p_true, p_center)

    # Global polynomial minimum (what subdivision algorithm selected)
    global_poly_min_idx = argmin(start_values)
    global_poly_min_orthant = orthant_ids[global_poly_min_idx]
    global_poly_min_recovery = recovery_after[global_poly_min_idx]

    # Summary
    println()
    println("="^70)
    println("SUMMARY")
    println("="^70)
    println()

    println("p_true is in Orthant $true_orthant")
    println()

    println("GLOBAL POLYNOMIAL MIN (Algorithm's selection):")
    println("  Orthant: $global_poly_min_orthant")
    println("  Start f(p): $(round(start_values[global_poly_min_idx], digits=2))")
    println("  Refined f(p): $(round(refined_values[global_poly_min_idx], sigdigits=4))")
    println("  Recovery: $(round(global_poly_min_recovery * 100, digits=1))%")
    println()

    println("BEST RECOVERY (Multi-start winner):")
    println("  Orthant: $best_orthant")
    println("  Start f(p): $(round(start_values[best_idx], digits=2))")
    println("  Refined f(p): $(round(best_refined_value, sigdigits=4))")
    println("  Recovery: $(round(best_recovery * 100, digits=1))%")
    println()

    # Compare approaches
    if best_orthant == global_poly_min_orthant
        println("MATCH: Multi-start agrees with global polynomial min selection")
    else
        improvement = (global_poly_min_recovery - best_recovery) / global_poly_min_recovery * 100
        println("MISMATCH: Multi-start found better recovery in different orthant!")
        println("  Improvement: $(round(improvement, digits=1))% better than global-min selection")
    end
    println()

    target_met = best_recovery < 0.05
    println("Target (<5%): $(target_met ? "PASS" : "FAIL")")
    println()

    # Save results
    output_path = joinpath(experiment_dir, "multistart_refinement_deg_$(degree).csv")
    results_df = DataFrame(
        orthant = orthant_ids,
        start_value = start_values,
        refined_value = refined_values,
        recovery_before = recovery_before,
        recovery_after = recovery_after,
        converged = converged,
        timed_out = timed_out,
        f_calls = f_calls,
        time_elapsed = time_elapsed
    )

    # Add coordinates
    for j in 1:4
        results_df[!, Symbol("start_x$j")] = [pt[j] for pt in start_points]
        results_df[!, Symbol("refined_x$j")] = [pt[j] for pt in refined_points]
    end

    CSV.write(output_path, results_df)
    println("Results saved: $output_path")

    # Save summary JSON
    summary = Dict(
        "experiment" => basename(experiment_dir),
        "degree" => degree,
        "n_orthants" => n_orthants,
        "true_orthant" => true_orthant,
        "global_poly_min_orthant" => global_poly_min_orthant,
        "global_poly_min_recovery" => global_poly_min_recovery,
        "best_recovery_orthant" => best_orthant,
        "best_recovery" => best_recovery,
        "target_met" => target_met,
        "total_f_calls" => sum(f_calls),
        "total_time" => sum(time_elapsed)
    )
    summary_path = joinpath(experiment_dir, "multistart_summary_deg_$(degree).json")
    open(summary_path, "w") do io
        JSON.print(io, summary, 2)
    end
    println("Summary saved: $summary_path")
end

if abspath(PROGRAM_FILE) == @__FILE__
    args = parse_args_refine()
    run_multistart_refinement(args)
end
