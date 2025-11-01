#!/usr/bin/env julia

using Pkg
Pkg.activate(".")

using CSV
using DataFrames
using JSON3
using Printf
using Statistics
using LinearAlgebra

# Helper to load experiment config
function load_config(exp_path)
    config_file = joinpath(exp_path, "experiment_config.json")
    if isfile(config_file)
        return JSON3.read(read(config_file, String))
    end
    return nothing
end

# Helper to load all critical points CSVs for an experiment
function load_all_critical_points(exp_path)
    csv_files = filter(f -> startswith(basename(f), "critical_points_deg_"), readdir(exp_path, join=true))

    results = Dict{Int, DataFrame}()
    for csv_file in csv_files
        # Extract degree from filename
        m = match(r"deg_(\d+)\.csv", basename(csv_file))
        if m !== nothing
            degree = parse(Int, m[1])
            df = CSV.read(csv_file, DataFrame)
            results[degree] = df
        end
    end

    return results
end

# Compute L2 distance to true parameter
function param_distance(cp_row, p_true)
    p_found = [cp_row.x1, cp_row.x2, cp_row.x3, cp_row.x4]
    return norm(p_found .- p_true)
end

# Main analysis
campaign_path = "/Users/ghscholt/GlobalOptim/globtimcore/experiments/lotka_volterra_4d_study/configs_20251006_160051/hpc_results"

exp_dirs = filter(isdir, readdir(campaign_path, join=true))
sort!(exp_dirs)

println("="^120)
println("📊 DETAILED CAMPAIGN ANALYSIS: Lotka-Volterra 4D Parameter Recovery")
println("="^120)

# Collect all experiment data
exp_data = []

for exp_path in exp_dirs
    exp_name = basename(exp_path)

    # Load config to get true parameters
    config = load_config(exp_path)
    if config === nothing
        @warn "No config found for $exp_name"
        continue
    end

    p_true = haskey(config, :p_true) ? collect(config.p_true) : collect(config.p_center)
    sample_range = haskey(config, :domain_range) ? config.domain_range : config.sample_range

    # Load all critical points
    cp_by_degree = load_all_critical_points(exp_path)

    if isempty(cp_by_degree)
        @warn "No critical points found for $exp_name"
        continue
    end

    push!(exp_data, (
        name = exp_name,
        sample_range = sample_range,
        p_true = p_true,
        cp_by_degree = cp_by_degree
    ))
end

# Sort by sample range
sort!(exp_data, by = x -> x.sample_range)

# Print summary table
println("\n📋 SUMMARY BY EXPERIMENT")
println("-"^120)
@printf("%-50s | %12s | %12s | %20s | %20s\n",
    "Experiment", "Range", "# Degrees", "Total Crit Pts", "Best Distance")
println("-"^120)

for exp in exp_data
    total_cp = sum(nrow(df) for df in values(exp.cp_by_degree))
    degrees = sort(collect(keys(exp.cp_by_degree)))

    # Find best parameter recovery across all degrees
    best_dist = Inf
    for (deg, df) in exp.cp_by_degree
        if nrow(df) > 0
            distances = [param_distance(row, exp.p_true) for row in eachrow(df)]
            best_dist = min(best_dist, minimum(distances))
        end
    end

    short_name = replace(exp.name, "lotka_volterra_4d_" => "")

    @printf("%-50s | %12s | %12d | %20d | %20.6f\n",
        short_name, "±$(exp.sample_range)", length(degrees), total_cp,
        best_dist == Inf ? NaN : best_dist)
end

println("-"^120)

# Print detailed per-degree breakdown
println("\n📈 DETAILED PER-DEGREE ANALYSIS")
println("="^120)

for exp in exp_data
    println("\n$(exp.name)")
    println("  Sample range: ±$(exp.sample_range)")
    println("  True parameters: [$(join([@sprintf("%.6f", p) for p in exp.p_true], ", "))]")
    println()

    @printf("  %-8s | %12s | %20s | %20s | %20s\n",
        "Degree", "# Crit Pts", "Min Distance", "Mean Distance", "Best Objective")
    println("  " * "-"^100)

    degrees = sort(collect(keys(exp.cp_by_degree)))

    for deg in degrees
        df = exp.cp_by_degree[deg]
        n_cp = nrow(df)

        if n_cp > 0
            # Compute distances to true parameter
            distances = [param_distance(row, exp.p_true) for row in eachrow(df)]
            min_dist = minimum(distances)
            mean_dist = mean(distances)
            best_obj = minimum(df.z)

            @printf("  %-8d | %12d | %20.6f | %20.6f | %20.3e\n",
                deg, n_cp, min_dist, mean_dist, best_obj)
        else
            @printf("  %-8d | %12d | %20s | %20s | %20s\n",
                deg, n_cp, "N/A", "N/A", "N/A")
        end
    end
end

# Convergence analysis: how does best distance improve with degree?
println("\n📉 CONVERGENCE ANALYSIS: Best Parameter Distance vs Degree")
println("="^120)
println()

# Create convergence table
@printf("%-8s", "Degree")
for (i, exp) in enumerate(exp_data)
    # Try to extract exp number from name, otherwise use index
    m = match(r"_exp(\d+)_", exp.name)
    if m !== nothing
        short_name = "Exp$(m[1])"
    else
        # Use range and index for experiments with same range
        short_name = "±$(exp.sample_range) #$i"
    end
    @printf(" | %15s", short_name)
end
println()
println("-"^(8 + length(exp_data) * 18))

# Get all unique degrees
all_degrees = Set{Int}()
for exp in exp_data
    union!(all_degrees, keys(exp.cp_by_degree))
end
degrees = sort(collect(all_degrees))

for deg in degrees
    @printf("%-8d", deg)

    for exp in exp_data
        if haskey(exp.cp_by_degree, deg)
            df = exp.cp_by_degree[deg]
            if nrow(df) > 0
                distances = [param_distance(row, exp.p_true) for row in eachrow(df)]
                min_dist = minimum(distances)
                @printf(" | %15.6f", min_dist)
            else
                @printf(" | %15s", "N/A")
            end
        else
            @printf(" | %15s", "-")
        end
    end
    println()
end

println("\n" * "="^120)
println("✅ Analysis complete!")
