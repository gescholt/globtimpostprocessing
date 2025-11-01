#!/usr/bin/env julia

using Pkg
Pkg.activate(".")

using GlobtimPostProcessing
using DataFrames
using Printf

# Load campaign results
campaign_path = "/Users/ghscholt/GlobalOptim/globtimcore/experiments/lotka_volterra_4d_study/configs_20251006_160051/hpc_results"
println("📂 Loading campaign results...")
results = load_campaign_results(campaign_path)

# Compute aggregate statistics
println("\n📊 Computing aggregate statistics...")
agg_stats = aggregate_campaign_statistics(results)

# Print campaign summary table
println("\n" * "="^100)
println("📋 CAMPAIGN SUMMARY TABLE")
println("="^100)

summary = agg_stats["campaign_summary"]
println("\nOverall Statistics:")
println("  Total experiments: $(summary["num_experiments"])")
println("  Successful: $(summary["successful_experiments"]) ($(round(summary["success_rate"]*100, digits=1))%)")
println("  Total computation time: $(round(summary["total_computation_hours"], digits=2)) hours")
println("  Total critical points: $(summary["total_critical_points"])")
println("  Degrees covered: $(summary["degrees_covered"])")

# Create per-experiment table
println("\n" * "-"^100)
println("📊 PER-EXPERIMENT RESULTS")
println("-"^100)

# Table header
@printf("%-40s | %15s | %15s | %12s | %12s\n",
    "Experiment", "Sample Range", "Critical Pts", "L2 Error", "Param Error")
println("-"^100)

# Sort experiments by range for readability
exp_range_pairs = []
for exp in results.experiments
    range_val = get(exp.metadata, "sample_range", 0.0)
    push!(exp_range_pairs, (exp, range_val))
end
sort!(exp_range_pairs, by=x->x[2])

# Print each experiment
for (exp, range_val) in exp_range_pairs
    exp_id = exp.experiment_id
    exp_stats = get(agg_stats["experiments"], exp_id, Dict())

    # Get critical points
    cp_count = something(get(exp.metadata, "total_critical_points", nothing), 0)

    # Get L2 error (mean across degrees)
    l2_err_str = "N/A"
    if haskey(exp_stats, "approximation_quality") && get(exp_stats["approximation_quality"], "available", false)
        l2_err = exp_stats["approximation_quality"]["mean_error"]
        l2_err_str = @sprintf("%.3e", l2_err)
    end

    # Get parameter recovery error
    param_err_str = "N/A"
    if haskey(exp_stats, "parameter_recovery") && get(exp_stats["parameter_recovery"], "available", false)
        param_err = exp_stats["parameter_recovery"]["mean_error"]
        param_err_str = @sprintf("%.3e", param_err)
    end

    # Extract short experiment name
    short_name = replace(exp_id, "lotka_volterra_4d_" => "")

    @printf("%-40s | %15s | %12d | %12s | %12s\n",
        short_name, "±$(range_val)", cp_count, l2_err_str, param_err_str)
end

println("-"^100)

# Print degrees breakdown if available
println("\n" * "-"^100)
println("📈 PER-DEGREE BREAKDOWN")
println("-"^100)

for (exp, range_val) in exp_range_pairs
    exp_id = exp.experiment_id
    short_name = replace(exp_id, "lotka_volterra_4d_" => "")

    println("\n$(short_name) (Range ±$(range_val)):")

    results_summary = get(exp.metadata, "results_summary", Dict())
    if !isempty(results_summary)
        @printf("  %-8s | %12s | %15s | %15s\n",
            "Degree", "Crit Pts", "L2 Error", "Condition #")
        println("  " * "-"^60)

        # Sort by degree
        degrees = sort([parse(Int, replace(k, "degree_" => "")) for k in keys(results_summary)])

        for deg in degrees
            deg_key = "degree_$deg"
            deg_data = results_summary[deg_key]

            cp = get(deg_data, "critical_points_refined", 0)
            l2 = get(deg_data, "l2_error", NaN)
            cond = get(deg_data, "condition_number", NaN)

            l2_str = isnan(l2) ? "N/A" : @sprintf("%.3e", l2)
            cond_str = isnan(cond) ? "N/A" : @sprintf("%.3e", cond)

            @printf("  %-8d | %12d | %15s | %15s\n", deg, cp, l2_str, cond_str)
        end
    else
        println("  No per-degree data available")
    end
end

println("\n" * "="^100)
println("✅ Table generation complete!")
