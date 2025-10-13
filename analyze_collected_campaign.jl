#!/usr/bin/env julia
"""
Quick Campaign Analysis for Phase 0 Collections

Analyzes campaigns collected via collect_batch.sh (Phase 0 format).
Works with flat directory structure without requiring hpc_results subdirectory.

Usage:
    julia --project=. analyze_collected_campaign.jl <campaign_path>

Example:
    julia --project=. analyze_collected_campaign.jl collected_experiments_20251013_083530/campaign_lotka_volterra_4d_extended_degrees
"""

using Pkg
Pkg.activate(@__DIR__)

using GlobtimPostProcessing
using DataFrames
using Printf
using JSON3
using Statistics
using CSV

function print_header(text::String)
    println("\n" * "="^80)
    println(text)
    println("="^80)
end

function load_experiment_summary(exp_dir::String)
    summary_path = joinpath(exp_dir, "results_summary.json")

    if !isfile(summary_path)
        return nothing
    end

    try
        data = JSON3.read(read(summary_path, String))
        return data
    catch e
        @warn "Failed to parse $summary_path: $e"
        return nothing
    end
end

function count_critical_points(exp_dir::String)
    csv_files = filter(f -> startswith(f, "critical_points_deg_") && endswith(f, ".csv"), readdir(exp_dir))

    total_points = 0
    by_degree = Dict{Int, Int}()

    for csv_file in csv_files
        # Extract degree from filename
        m = match(r"critical_points_deg_(\d+)\.csv", csv_file)
        if m === nothing
            continue
        end

        degree = parse(Int, m.captures[1])

        # Count lines in file (subtract 1 for header)
        csv_path = joinpath(exp_dir, csv_file)
        try
            df = CSV.read(csv_path, DataFrame)
            count = nrow(df)
            by_degree[degree] = count
            total_points += count
        catch e
            @warn "Failed to read $csv_file: $e"
        end
    end

    return total_points, by_degree
end

function analyze_campaign(campaign_path::String)
    if !isdir(campaign_path)
        error("Campaign directory not found: $campaign_path")
    end

    campaign_name = basename(campaign_path)
    print_header("Analyzing Campaign: $campaign_name")

    # Discover experiments
    exp_dirs = filter(readdir(campaign_path)) do name
        path = joinpath(campaign_path, name)
        return isdir(path) && isfile(joinpath(path, "results_summary.json"))
    end

    if isempty(exp_dirs)
        println("\n❌ No experiments found with results_summary.json")
        println("\nDirectory structure:")
        for item in readdir(campaign_path)
            println("  - $item")
        end
        return
    end

    println("\n📊 Found $(length(exp_dirs)) experiments")

    # Analyze each experiment
    results = []

    for exp_name in sort(exp_dirs)
        exp_path = joinpath(campaign_path, exp_name)

        println("\n" * "-"^80)
        println("Experiment: $exp_name")
        println("-"^80)

        # Load summary
        summary = load_experiment_summary(exp_path)

        if summary === nothing
            println("  ⚠️  Failed to load results_summary.json")
            continue
        end

        # Count critical points
        total_cp, cp_by_degree = count_critical_points(exp_path)

        # Handle both array format (degree results) and dict format (full summary)
        # If summary is an array, it's the degree-by-degree results
        if summary isa AbstractVector
            # Array format: each element is a degree result
            total_time = sum(get(deg_result, :computation_time, 0.0) for deg_result in summary)
            min_degree = minimum(get(deg_result, :degree, 0) for deg_result in summary)
            max_degree = maximum(get(deg_result, :degree, 0) for deg_result in summary)

            # Extract L2 norms and objective values by degree
            l2_by_degree = Dict{Int, Float64}()
            best_value_by_degree = Dict{Int, Float64}()
            for deg_result in summary
                degree = get(deg_result, :degree, 0)
                l2_by_degree[degree] = get(deg_result, :L2_norm, NaN)
                best_value_by_degree[degree] = get(deg_result, :best_value, NaN)
            end

            # Get final (highest) degree L2 norm
            final_l2 = get(l2_by_degree, max_degree, missing)
            final_best_value = get(best_value_by_degree, max_degree, missing)

            result = Dict(
                "experiment" => exp_name,
                "total_critical_points" => total_cp,
                "cp_by_degree" => cp_by_degree,
                "l2_by_degree" => l2_by_degree,
                "best_value_by_degree" => best_value_by_degree,
                "final_l2_norm" => final_l2,
                "final_best_value" => final_best_value,
                "domain_size" => missing,
                "polynomial_degree" => "$min_degree-$max_degree",
                "grid_nodes" => missing,
                "total_time_seconds" => total_time,
                "summary" => summary
            )
        else
            # Dict format: traditional summary with config and timing
            config = get(summary, :experiment_config, Dict())
            timing = get(summary, :timing_info, Dict())

            result = Dict(
                "experiment" => exp_name,
                "total_critical_points" => total_cp,
                "cp_by_degree" => cp_by_degree,
                "l2_by_degree" => Dict{Int, Float64}(),
                "best_value_by_degree" => Dict{Int, Float64}(),
                "final_l2_norm" => missing,
                "final_best_value" => missing,
                "domain_size" => get(config, :domain_size, missing),
                "polynomial_degree" => get(config, :polynomial_degree, missing),
                "grid_nodes" => get(config, :grid_nodes, missing),
                "total_time_seconds" => get(timing, :total_time_seconds, missing),
                "summary" => summary
            )
        end

        push!(results, result)

        # Print key info
        println("  Critical Points: $total_cp")

        # Print L2 norms and critical points by degree
        l2_by_deg = result["l2_by_degree"]
        best_val_by_deg = result["best_value_by_degree"]

        if !isempty(cp_by_degree) && !isempty(l2_by_deg)
            println("  By degree (CP | L2 norm | best value):")
            for degree in sort(collect(keys(cp_by_degree)))
                cp_count = cp_by_degree[degree]
                l2_val = get(l2_by_deg, degree, NaN)
                best_val = get(best_val_by_deg, degree, NaN)

                l2_str = isnan(l2_val) ? "N/A" : @sprintf("%.1f", l2_val)
                best_str = isnan(best_val) ? "N/A" : @sprintf("%.1f", best_val)

                println("    deg $degree: $cp_count | $l2_str | $best_str")
            end
        elseif !isempty(cp_by_degree)
            println("  By degree:")
            for degree in sort(collect(keys(cp_by_degree)))
                println("    deg $degree: $(cp_by_degree[degree])")
            end
        end

        if !ismissing(result["domain_size"])
            println("  Domain size: $(result["domain_size"])")
        end

        if !ismissing(result["polynomial_degree"])
            println("  Polynomial degree: $(result["polynomial_degree"])")
        end

        if !ismissing(result["final_l2_norm"]) && !isnan(result["final_l2_norm"])
            println("  Final L2 norm (deg $(split(result["polynomial_degree"], "-")[end])): $(round(result["final_l2_norm"], digits=1))")
        end

        if !ismissing(result["final_best_value"]) && !isnan(result["final_best_value"])
            println("  Best objective value: $(round(result["final_best_value"], digits=1))")
        end

        if !ismissing(result["total_time_seconds"])
            println("  Total time: $(round(result["total_time_seconds"], digits=1))s")
        end
    end

    # Generate summary table
    print_header("Campaign Summary")

    df_data = DataFrame(
        experiment = [r["experiment"] for r in results],
        critical_points = [r["total_critical_points"] for r in results],
        final_L2_norm = [r["final_l2_norm"] for r in results],
        best_objective = [r["final_best_value"] for r in results],
        domain_size = [r["domain_size"] for r in results],
        poly_degree = [r["polynomial_degree"] for r in results],
        time_sec = [r["total_time_seconds"] for r in results]
    )

    println(df_data)

    # Statistics
    println("\n📈 Statistics:")
    println("  Total experiments: $(length(results))")
    println("  Total critical points: $(sum(r["total_critical_points"] for r in results))")
    println("  Mean critical points: $(round(mean(r["total_critical_points"] for r in results), digits=1))")
    println("  Std critical points: $(round(std(r["total_critical_points"] for r in results), digits=1))")

    if !all(ismissing(r["total_time_seconds"]) for r in results)
        times = filter(!ismissing, [r["total_time_seconds"] for r in results])
        println("  Total computation time: $(round(sum(times), digits=1))s")
        println("  Mean time per experiment: $(round(mean(times), digits=1))s")
    end

    print_header("Analysis Complete")

    return results
end

# Main execution
function main()
    if length(ARGS) < 1
        println("Usage: julia --project=. analyze_collected_campaign.jl <campaign_path>")
        println("\nExample:")
        println("  julia --project=. analyze_collected_campaign.jl collected_experiments_20251013_083530/campaign_lotka_volterra_4d_extended_degrees")
        exit(1)
    end

    campaign_path = ARGS[1]
    results = analyze_campaign(campaign_path)

    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
