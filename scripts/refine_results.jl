#!/usr/bin/env julia
"""
PE-05: Local Refinement from Polynomial Critical Points

Refines polynomial critical points using NelderMead local optimization
to find actual local minima of f, then compares recovery before/after.

Question: Do polynomial critical points (which are saddles of f) lead to
actual minima that are closer to p_true?

Usage:
    julia --project=../../.. experiments/lv4d_2025/refine_results.jl \\
        --experiment-dir /path/to/lv4d_results

Or use defaults (most recent experiment matching pattern):
    julia --project=../../.. experiments/lv4d_2025/refine_results.jl --seed 1 --domain 0.08
"""

const SCRIPT_DIR = @__DIR__
const PROJECT_ROOT = abspath(joinpath(SCRIPT_DIR, "..", ".."))
const POSTPROC_ROOT = abspath(joinpath(PROJECT_ROOT, "..", "globtimpostprocessing"))

# Stack environments: globtimpostprocessing on top of globtim
using Pkg
pushfirst!(LOAD_PATH, POSTPROC_ROOT)
pushfirst!(LOAD_PATH, PROJECT_ROOT)
Pkg.activate(POSTPROC_ROOT)

using GlobtimPostProcessing
using Globtim
using JSON
using CSV
using DataFrames
using LinearAlgebra
using Statistics
using ArgParse

function parse_args_refine()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--experiment-dir"
            help = "Path to experiment results directory"
            arg_type = String
            default = nothing
        "--seed"
            help = "Seed to match (if experiment-dir not specified)"
            arg_type = Int
            default = 1
        "--domain"
            help = "Domain to match (if experiment-dir not specified)"
            arg_type = Float64
            default = 0.08
        "--max-time"
            help = "Maximum time per point in seconds"
            arg_type = Float64
            default = 60.0
    end
    return parse_args(s)
end

function find_experiment_dir(results_root, seed, domain)
    dirs = filter(isdir, readdir(results_root, join=true))
    matching = filter(d -> occursin("domain$(domain)", basename(d)) &&
                          occursin("seed$(seed)", basename(d)), dirs)

    if isempty(matching)
        error("No experiments found matching seed=$seed, domain=$domain in $results_root")
    end

    # Return most recent
    return sort(matching, by=mtime, rev=true)[1]
end

function run_refinement(args)
    # Find experiment directory
    if args["experiment-dir"] !== nothing
        experiment_dir = args["experiment-dir"]
    else
        results_root = joinpath(PROJECT_ROOT, "globtim_results", "lotka_volterra_4d")
        experiment_dir = find_experiment_dir(results_root, args["seed"], args["domain"])
    end

    println()
    println("="^70)
    println("PE-05: LOCAL REFINEMENT FROM POLYNOMIAL CRITICAL POINTS")
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
    IC = Float64.(exp_config["ic"])
    TIME_INTERVAL = Float64.(exp_config["time_interval"])
    NUM_POINTS = exp_config["num_points"]

    println("p_true = $(round.(p_true, digits=4))")
    println("p_center = $(round.(p_center, digits=4))")
    println()

    # Load raw critical points using globtimpostprocessing API
    println("Loading raw critical points...")
    raw_data = load_raw_critical_points(experiment_dir)
    println("Found $(raw_data.n_points) polynomial critical points (degree $(raw_data.degree))")
    println()

    # Recreate error function
    println("Recreating error function...")
    model, _params, _states, outputs = define_daisy_ex3_model_4D()

    error_func = make_error_distance(
        model, outputs, IC, p_true, TIME_INTERVAL, NUM_POINTS, L2_norm
    )

    # Recovery BEFORE refinement
    println()
    println("--- BEFORE REFINEMENT ---")
    raw_values = [error_func(pt) for pt in raw_data.points]
    recovery_before = [norm(pt .- p_true) for pt in raw_data.points]

    best_raw_idx = argmin(raw_values)
    best_raw_value = raw_values[best_raw_idx]
    best_recovery_before = recovery_before[best_raw_idx]

    println("Best polynomial critical point: #$best_raw_idx")
    println("  f(p) = $(round(best_raw_value, digits=2))")
    println("  ||p - p_true|| = $(round(best_recovery_before, digits=4)) ($(round(best_recovery_before*100, digits=1))%)")

    # Configure refinement for ODE objectives
    println()
    println("--- RUNNING LOCAL REFINEMENT (NelderMead, max $(args["max-time"])s/point) ---")

    config = ode_refinement_config(max_time_per_point=args["max-time"])

    # Use batch refinement
    results = refine_critical_points_batch(
        error_func,
        raw_data.points;
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
    recovery_after = [norm(pt .- p_true) for pt in refined_points]

    # Print per-point results
    println()
    for (i, r) in enumerate(results)
        status = r.converged ? "✓" : (r.timed_out ? "⏱" : "✗")
        println("Point $i: f=$(round(raw_values[i], digits=1)) → $(round(r.value_refined, sigdigits=4)) " *
                "($status, $(round(r.time_elapsed, digits=1))s, $(r.f_calls) f-calls)")
    end

    # Recovery AFTER refinement
    println()
    println("--- AFTER REFINEMENT ---")
    best_refined_idx = argmin(refined_values)
    best_refined_value = refined_values[best_refined_idx]
    best_recovery_after = recovery_after[best_refined_idx]

    println("Best refined point: #$best_refined_idx")
    println("  f(p) = $(round(best_refined_value, sigdigits=4))")
    println("  ||p - p_true|| = $(round(best_recovery_after, digits=4)) ($(round(best_recovery_after*100, digits=1))%)")

    # Parameter recovery comparison table
    println()
    println("--- PARAMETER RECOVERY ---")
    println("| Point | Before (saddle) | After (minimum) | Change |")
    println("|-------|-----------------|-----------------|--------|")
    for i in 1:length(raw_data.points)
        before_pct = round(recovery_before[i] * 100, digits=1)
        after_pct = round(recovery_after[i] * 100, digits=1)
        change_pct = round((recovery_before[i] - recovery_after[i]) * 100, digits=1)
        sign = change_pct >= 0 ? "-" : "+"
        println("| $i     | $(before_pct)%          | $(after_pct)%            | $(sign)$(abs(change_pct))% |")
    end

    # Summary comparison
    println()
    println("="^70)
    println("SUMMARY")
    println("="^70)
    println()

    println("| Metric | Before | After | Change |")
    println("|--------|--------|-------|--------|")
    println("| Best f(p) | $(round(best_raw_value, digits=2)) | $(round(best_refined_value, sigdigits=4)) | $(round(best_raw_value - best_refined_value, sigdigits=3)) |")
    println("| Best recovery | $(round(best_recovery_before*100, digits=1))% | $(round(best_recovery_after*100, digits=1))% | $(round((best_recovery_before - best_recovery_after)*100, digits=1))% |")
    println("| Converged | N/A | $(sum(converged))/$(length(converged)) | - |")
    println()

    # Did refinement help?
    if best_recovery_after < best_recovery_before
        improvement_pct = (best_recovery_before - best_recovery_after) / best_recovery_before * 100
        println("✓ Refinement IMPROVED recovery by $(round(improvement_pct, digits=1))%")
    elseif best_recovery_after > best_recovery_before
        degradation_pct = (best_recovery_after - best_recovery_before) / best_recovery_before * 100
        println("✗ Refinement DEGRADED recovery by $(round(degradation_pct, digits=1))%")
    else
        println("→ Refinement had NO EFFECT on recovery")
    end

    target_met = best_recovery_after < 0.05
    println("Target (<5%): $(target_met ? "✓ PASS" : "✗ FAIL")")
    println()

    # Save results
    output_path = joinpath(experiment_dir, "refinement_comparison.csv")
    results_df = DataFrame(
        point_idx = 1:length(raw_data.points),
        raw_value = raw_values,
        refined_value = refined_values,
        converged = converged,
        recovery_before = recovery_before,
        recovery_after = recovery_after,
        f_calls = [r.f_calls for r in results],
        time_elapsed = [r.time_elapsed for r in results]
    )

    # Add raw and refined coordinates
    n_dims = length(raw_data.points[1])
    for j in 1:n_dims
        results_df[!, Symbol("raw_x$j")] = [pt[j] for pt in raw_data.points]
        results_df[!, Symbol("refined_x$j")] = [pt[j] for pt in refined_points]
    end

    CSV.write(output_path, results_df)
    println("Results saved: $output_path")
end

if abspath(PROGRAM_FILE) == @__FILE__
    args = parse_args_refine()
    run_refinement(args)
end
