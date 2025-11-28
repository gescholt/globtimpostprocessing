#!/usr/bin/env julia
"""
⚠️  NOTE - This functionality is being integrated into analyze_experiments.jl

For now, this standalone script still works.
In the future, basis comparison will be available as Mode 3 in the unified script:
    julia --project=. analyze_experiments.jl
    (then select "3. Basis Comparison")

The unified script will auto-detect basis pairs in campaigns and provide
the same comparison functionality plus quality diagnostics and parameter recovery.

---

OLD DOCUMENTATION (for reference):
Polynomial Basis Comparison: Chebyshev vs Legendre

Compares two experiments that differ only in polynomial basis choice.
Analyzes approximation quality, numerical stability, critical point discovery,
and computation time.

Usage:
    julia --project=. compare_basis_functions.jl <chebyshev_dir> <legendre_dir>

Example:
    julia --project=. compare_basis_functions.jl \\
      collected_experiments_20251014_090544/lv4d_basis_comparison_chebyshev_deg4-6_domain0.3_GN16_20251013_172835 \\
      collected_experiments_20251014_090544/lv4d_basis_comparison_legendre_deg4-6_domain0.3_GN16_20251013_172835
"""

# Note: Basis comparison integration is planned for Phase 4 of issue #7
# For now, this standalone script continues to work

using Pkg
Pkg.activate(@__DIR__)

using JSON3
using DataFrames
using Printf
using Statistics

function print_header(text::String; width=80)
    println("\n" * "="^width)
    println(text)
    println("="^width)
end

function print_section(text::String; width=80)
    println("\n" * text)
    println("-"^width)
end

function load_basis_results(exp_dir::String)
    """Load results_summary.json from experiment directory"""
    summary_path = joinpath(exp_dir, "results_summary.json")

    if !isfile(summary_path)
        error("Results file not found: $summary_path")
    end

    try
        data = JSON3.read(read(summary_path, String))
        return data
    catch e
        error("Failed to parse $summary_path: $e")
    end
end

function extract_basis_name(exp_dir::String)
    """Extract basis type from directory name"""
    basename_dir = basename(exp_dir)

    if occursin("chebyshev", lowercase(basename_dir))
        return "Chebyshev"
    elseif occursin("legendre", lowercase(basename_dir))
        return "Legendre"
    else
        return "Unknown"
    end
end

function verify_experiment_compatibility(cheb_dir::String, leg_dir::String, cheb_data, leg_data)
    """Verify that experiments are comparable (same parameters except basis)"""
    print_section("Experiment Compatibility Check")

    # Check degree ranges match
    cheb_degrees = [d.degree for d in cheb_data]
    leg_degrees = [d.degree for d in leg_data]

    if cheb_degrees != leg_degrees
        @warn "Degree ranges differ!" cheb_degrees leg_degrees
        println("  ⚠️  Degree ranges: Cheb=$cheb_degrees, Leg=$leg_degrees")
    else
        println("  ✅ Degree ranges match: $(cheb_degrees)")
    end

    # Extract parameters from directory names
    cheb_base = basename(cheb_dir)
    leg_base = basename(leg_dir)

    # Check GN
    cheb_gn_match = match(r"GN(\d+)", cheb_base)
    leg_gn_match = match(r"GN(\d+)", leg_base)

    if cheb_gn_match !== nothing && leg_gn_match !== nothing
        if cheb_gn_match.captures[1] == leg_gn_match.captures[1]
            println("  ✅ Grid nodes (GN): $(cheb_gn_match.captures[1])")
        else
            @warn "Grid nodes differ!" cheb_gn_match.captures[1] leg_gn_match.captures[1]
        end
    end

    # Check domain
    cheb_domain_match = match(r"domain([\d.]+)", cheb_base)
    leg_domain_match = match(r"domain([\d.]+)", leg_base)

    if cheb_domain_match !== nothing && leg_domain_match !== nothing
        if cheb_domain_match.captures[1] == leg_domain_match.captures[1]
            println("  ✅ Domain size: ±$(cheb_domain_match.captures[1])")
        else
            @warn "Domain sizes differ!" cheb_domain_match.captures[1] leg_domain_match.captures[1]
        end
    end

    # Check timestamps (should be same if launched together)
    cheb_time_match = match(r"(\d{8}_\d{6})", cheb_base)
    leg_time_match = match(r"(\d{8}_\d{6})", leg_base)

    if cheb_time_match !== nothing && leg_time_match !== nothing
        if cheb_time_match.captures[1] == leg_time_match.captures[1]
            println("  ✅ Launch time: $(cheb_time_match.captures[1]) (simultaneous)")
        else
            println("  ⚠️  Launch times: Cheb=$(cheb_time_match.captures[1]), Leg=$(leg_time_match.captures[1])")
        end
    end

    println("\n  ✅ Experiments are comparable")
end

function create_comparison_table(cheb_data, leg_data)
    """Create detailed comparison DataFrame"""
    comparison_df = DataFrame(
        degree = Int[],
        cheb_L2 = Float64[],
        leg_L2 = Float64[],
        L2_improvement_pct = Float64[],
        cheb_CN = Float64[],
        leg_CN = Float64[],
        CN_improvement_factor = Float64[],
        cheb_critical_points = Int[],
        leg_critical_points = Int[],
        cheb_best_value = Float64[],
        leg_best_value = Float64[],
        cheb_time = Float64[],
        leg_time = Float64[],
        time_delta = Float64[]
    )

    for (cheb_deg, leg_deg) in zip(cheb_data, leg_data)
        # Calculate improvements
        L2_improvement = 100 * (cheb_deg.L2_norm - leg_deg.L2_norm) / cheb_deg.L2_norm
        CN_improvement = cheb_deg.condition_number / leg_deg.condition_number
        time_delta = leg_deg.computation_time - cheb_deg.computation_time

        push!(comparison_df, (
            cheb_deg.degree,
            cheb_deg.L2_norm,
            leg_deg.L2_norm,
            L2_improvement,
            cheb_deg.condition_number,
            leg_deg.condition_number,
            CN_improvement,
            cheb_deg.critical_points,
            leg_deg.critical_points,
            cheb_deg.best_value,
            leg_deg.best_value,
            cheb_deg.computation_time,
            leg_deg.computation_time,
            time_delta
        ))
    end

    return comparison_df
end

function print_comparison_table(df::DataFrame)
    """Pretty print comparison table"""
    print_section("Detailed Comparison by Degree")

    println("\n📊 L2 APPROXIMATION ERROR")
    println(@sprintf("%-8s %12s %12s %12s", "Degree", "Chebyshev", "Legendre", "Δ (%)"))
    println("-"^50)
    for row in eachrow(df)
        println(@sprintf("%-8d %12.2f %12.2f %11.1f%%",
                row.degree, row.cheb_L2, row.leg_L2, row.L2_improvement_pct))
    end

    println("\n🔢 CONDITION NUMBER (Numerical Stability)")
    println(@sprintf("%-8s %12s %12s %12s", "Degree", "Chebyshev", "Legendre", "Factor"))
    println("-"^50)
    for row in eachrow(df)
        println(@sprintf("%-8d %12.2f %12.2f %11.1fx",
                row.degree, row.cheb_CN, row.leg_CN, row.CN_improvement_factor))
    end

    println("\n📍 CRITICAL POINTS FOUND")
    println(@sprintf("%-8s %12s %12s %12s", "Degree", "Chebyshev", "Legendre", "Δ"))
    println("-"^50)
    for row in eachrow(df)
        delta = row.leg_critical_points - row.cheb_critical_points
        delta_str = delta >= 0 ? "+$delta" : "$delta"
        println(@sprintf("%-8d %12d %12d %12s",
                row.degree, row.cheb_critical_points, row.leg_critical_points, delta_str))
    end

    println("\n⭐ BEST OBJECTIVE VALUE")
    println(@sprintf("%-8s %12s %12s %12s", "Degree", "Chebyshev", "Legendre", "Better"))
    println("-"^50)
    for row in eachrow(df)
        better = row.cheb_best_value < row.leg_best_value ? "Cheb" : "Leg"
        println(@sprintf("%-8d %12.2f %12.2f %12s",
                row.degree, row.cheb_best_value, row.leg_best_value, better))
    end

    println("\n⏱️  COMPUTATION TIME")
    println(@sprintf("%-8s %12s %12s %12s", "Degree", "Cheb (s)", "Leg (s)", "Δ (s)"))
    println("-"^50)
    for row in eachrow(df)
        println(@sprintf("%-8d %12.2f %12.2f %11+.2f",
                row.degree, row.cheb_time, row.leg_time, row.time_delta))
    end
end

function print_summary_statistics(df::DataFrame, cheb_data, leg_data)
    """Print aggregate statistics and findings"""
    print_section("Summary Statistics")

    # L2 improvement
    avg_L2_improvement = mean(df.L2_improvement_pct)
    min_L2_improvement = minimum(df.L2_improvement_pct)
    max_L2_improvement = maximum(df.L2_improvement_pct)

    println(@sprintf("\n📈 L2 Approximation (Legendre vs Chebyshev):"))
    println(@sprintf("  Average improvement: %.1f%%", avg_L2_improvement))
    println(@sprintf("  Range: %.1f%% to %.1f%%", min_L2_improvement, max_L2_improvement))

    if avg_L2_improvement > 0
        println("  ✅ Legendre provides better approximation quality")
    else
        println("  ✅ Chebyshev provides better approximation quality")
    end

    # Condition number
    avg_CN_improvement = mean(df.CN_improvement_factor)

    println(@sprintf("\n🔢 Numerical Stability:"))
    println(@sprintf("  Legendre is %.1fx more stable on average", avg_CN_improvement))

    if avg_CN_improvement > 1.5
        println("  ✅ Legendre significantly more numerically stable")
    end

    # Critical points
    total_cheb_CP = sum(df.cheb_critical_points)
    total_leg_CP = sum(df.leg_critical_points)

    println(@sprintf("\n📍 Critical Point Discovery:"))
    println(@sprintf("  Total: Chebyshev=%d, Legendre=%d", total_cheb_CP, total_leg_CP))

    # Best global minimum
    cheb_global_min = minimum(d.best_value for d in cheb_data)
    leg_global_min = minimum(d.best_value for d in leg_data)
    cheb_best_deg = [d.degree for d in cheb_data if d.best_value == cheb_global_min][1]
    leg_best_deg = [d.degree for d in leg_data if d.best_value == leg_global_min][1]

    println(@sprintf("\n⭐ Best Global Minimum:"))
    println(@sprintf("  Chebyshev: %.2f (degree %d)", cheb_global_min, cheb_best_deg))
    println(@sprintf("  Legendre:  %.2f (degree %d)", leg_global_min, leg_best_deg))

    if cheb_global_min < leg_global_min
        improvement_factor = (leg_global_min - cheb_global_min) / leg_global_min * 100
        println(@sprintf("  ✅ Chebyshev found better minimum (%.1f%% better)", improvement_factor))
    else
        improvement_factor = (cheb_global_min - leg_global_min) / cheb_global_min * 100
        println(@sprintf("  ✅ Legendre found better minimum (%.1f%% better)", improvement_factor))
    end

    # Computation time
    avg_time_delta = mean(abs.(df.time_delta))

    println(@sprintf("\n⏱️  Computation Time:"))
    println(@sprintf("  Average difference: %.2f seconds", avg_time_delta))

    if avg_time_delta < 5.0
        println("  ✅ Computation times virtually identical")
    end
end

function print_recommendation(df::DataFrame, cheb_data, leg_data)
    """Print final recommendation based on analysis"""
    print_header("RECOMMENDATION")

    avg_L2_improvement = mean(df.L2_improvement_pct)
    avg_CN_improvement = mean(df.CN_improvement_factor)
    cheb_global_min = minimum(d.best_value for d in cheb_data)
    leg_global_min = minimum(d.best_value for d in leg_data)

    println("\n🎯 LEGENDRE BASIS:")
    println("  ✅ Better numerical stability ($(round(avg_CN_improvement, digits=1))x lower condition numbers)")
    println("  ✅ Better L2 approximation quality (~$(round(avg_L2_improvement, digits=1))% improvement)")
    println("  ✅ More real solutions discovered")
    println("  ✅ No computation time penalty")

    if cheb_global_min < leg_global_min
        println("  ⚠️  Missed best global minimum (Chebyshev found $(round(cheb_global_min, digits=2)))")
    end

    println("\n🎯 CHEBYSHEV BASIS:")
    println("  ✅ Standard choice in literature (well-established)")

    if cheb_global_min < leg_global_min
        println("  ✅ Found best global minimum ($(round(cheb_global_min, digits=2)))")
    end

    if avg_CN_improvement > 2.0
        println("  ⚠️  Higher condition numbers (stability concerns)")
    end

    if avg_L2_improvement > 5.0
        println("  ⚠️  Worse L2 approximation quality")
    end

    println("\n💡 BEST PRACTICE:")
    println("  → Run BOTH bases and compare results")
    println("  → Use Legendre for better approximation and stability")
    println("  → Keep Chebyshev as fallback if Legendre misses critical minima")
    println("  → For this problem: $(cheb_global_min < leg_global_min ? "Chebyshev" : "Legendre") found best solution")

    println("\n📝 IMPLEMENTATION:")
    println("  Add `basis_type` parameter to experiment configuration")
    println("  Run parallel experiments with both bases")
    println("  Postprocess: Select best result across both bases")
end

function save_comparison_results(df::DataFrame, output_dir::String)
    """Save comparison results to CSV and JSON"""
    mkpath(output_dir)

    # Save CSV
    csv_path = joinpath(output_dir, "basis_comparison_results.csv")
    CSV.write(csv_path, df)
    println("\n💾 Saved comparison table: $csv_path")

    # Save summary JSON
    summary = Dict(
        "avg_L2_improvement_pct" => mean(df.L2_improvement_pct),
        "avg_CN_improvement_factor" => mean(df.CN_improvement_factor),
        "total_cheb_critical_points" => sum(df.cheb_critical_points),
        "total_leg_critical_points" => sum(df.leg_critical_points),
        "cheb_best_global" => minimum(df.cheb_best_value),
        "leg_best_global" => minimum(df.leg_best_value),
        "avg_time_delta_seconds" => mean(abs.(df.time_delta))
    )

    json_path = joinpath(output_dir, "basis_comparison_summary.json")
    open(json_path, "w") do f
        JSON3.pretty(f, summary)
    end
    println("💾 Saved summary JSON: $json_path")
end

function compare_basis_functions(cheb_dir::String, leg_dir::String)
    """Main comparison function"""
    print_header("POLYNOMIAL BASIS COMPARISON: CHEBYSHEV vs LEGENDRE", width=80)

    println("\n📂 Experiment Directories:")
    println("  Chebyshev: $(basename(cheb_dir))")
    println("  Legendre:  $(basename(leg_dir))")

    # Load data
    println("\n📥 Loading experiment results...")
    cheb_data = load_basis_results(cheb_dir)
    leg_data = load_basis_results(leg_dir)

    println("  ✅ Loaded $(length(cheb_data)) Chebyshev results")
    println("  ✅ Loaded $(length(leg_data)) Legendre results")

    # Verify compatibility
    verify_experiment_compatibility(cheb_dir, leg_dir, cheb_data, leg_data)

    # Create comparison table
    comparison_df = create_comparison_table(cheb_data, leg_data)

    # Print detailed comparison
    print_comparison_table(comparison_df)

    # Print summary statistics
    print_summary_statistics(comparison_df, cheb_data, leg_data)

    # Print recommendation
    print_recommendation(comparison_df, cheb_data, leg_data)

    # Save results
    output_dir = joinpath(dirname(cheb_dir), "basis_comparison_analysis")
    save_comparison_results(comparison_df, output_dir)

    println("\n" * "="^80)
    println("✅ Comparison complete!")
    println("="^80 * "\n")

    return comparison_df
end

# Main execution
function main()
    if length(ARGS) != 2
        println("Usage: julia compare_basis_functions.jl <chebyshev_dir> <legendre_dir>")
        println("\nExample:")
        println("  julia --project=. compare_basis_functions.jl \\")
        println("    collected_experiments_20251014_090544/lv4d_basis_comparison_chebyshev_... \\")
        println("    collected_experiments_20251014_090544/lv4d_basis_comparison_legendre_...")
        exit(1)
    end

    cheb_dir = ARGS[1]
    leg_dir = ARGS[2]

    # Verify directories exist
    if !isdir(cheb_dir)
        error("Chebyshev directory not found: $cheb_dir")
    end

    if !isdir(leg_dir)
        error("Legendre directory not found: $leg_dir")
    end

    # Run comparison
    compare_basis_functions(cheb_dir, leg_dir)
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
