#!/usr/bin/env julia
"""
LV4D Results Processing Pipeline Demo

Demonstrates the full workflow for analyzing LV4D experiment results.
Run from GlobalOptim directory:

    julia --project=globtimpostprocessing globtimpostprocessing/scripts/lv4d_pipeline_demo.jl [experiment_path]
"""

using GlobtimPostProcessing
using GlobtimPostProcessing.LV4DAnalysis
using DataFrames
using PrettyTables
using Printf
using LinearAlgebra

# Default experiment path
const DEFAULT_EXP = "globtim/globtim_results/lotka_volterra_4d/lv4d_GN16_deg4-12_dom1.0e-3_seed42_20260123_121429"

function main(exp_path::String = DEFAULT_EXP)
    println("=" ^ 70)
    println("LV4D RESULTS PROCESSING PIPELINE")
    println("=" ^ 70)
    println()

    # =========================================================================
    # Step 1: Load Experiment (LV4DAnalysis)
    # =========================================================================
    println("STEP 1: Loading Experiment")
    println("-" ^ 40)

    data = load_lv4d_experiment(exp_path)

    @printf("Directory: %s\n", basename(data.dir))
    @printf("True params: [%s]\n", join([@sprintf("%.4f", p) for p in data.p_true], ", "))
    @printf("Domain center: [%s]\n", join([@sprintf("%.4f", p) for p in data.p_center], ", "))
    @printf("Domain size: %.2e\n", data.domain_size)
    @printf("Dimension: %d\n", data.dim)
    @printf("Degrees analyzed: %s\n", join(sort(unique(data.degree_results.degree)), ", "))
    println()

    # =========================================================================
    # Step 2: Quality Analysis (LV4DAnalysis)
    # =========================================================================
    println("STEP 2: Quality Analysis")
    println("-" ^ 40)
    analyze_quality(data)
    println()

    # =========================================================================
    # Step 3: Degree-by-Degree Results
    # =========================================================================
    println("STEP 3: Degree-by-Degree Summary")
    println("-" ^ 40)

    # Build summary table from degree_results
    df = data.degree_results
    display_df = select(df,
        :degree,
        :L2_norm,
        :critical_points,
        :recovery_error,
        :hessian_minima,
        :hessian_saddle,
        :computation_time
    )

    # Format for display
    headers = ["Degree", "L2 Norm", "CPs", "Recovery Err", "Minima", "Saddles", "Time (s)"]
    ft = (v, _, j) -> begin
        if v isa AbstractFloat && !isnan(v)
            if j == 2  # L2 norm
                @sprintf("%.2f", v)
            elseif j == 4  # recovery error
                @sprintf("%.2e", v)
            elseif j == 7  # time
                @sprintf("%.1f", v)
            else
                string(v)
            end
        else
            string(v)
        end
    end

    pretty_table(display_df;
        header = headers,
        formatters = (ft,),
        alignment = [:r, :r, :r, :r, :r, :r, :r],
        tf = tf_unicode_rounded
    )
    println()

    # =========================================================================
    # Step 4: Parameter Recovery Table (ParameterRecovery module)
    # =========================================================================
    println("STEP 4: Parameter Recovery Analysis")
    println("-" ^ 40)

    degrees = sort(unique(df.degree))
    p_true = Float64.(data.p_true)

    recovery_table = generate_parameter_recovery_table(exp_path, p_true, degrees, 0.01)

    # Display with formatting
    headers = ["Degree", "CPs", "Min Distance", "Mean Distance", "Recoveries (<0.01)"]
    ft_recovery = (v, _, _) -> begin
        if v isa AbstractFloat && !isnan(v)
            @sprintf("%.2e", v)
        else
            string(v)
        end
    end

    pretty_table(recovery_table;
        header = headers,
        formatters = (ft_recovery,),
        alignment = [:r, :r, :r, :r, :r],
        tf = tf_unicode_rounded
    )
    println()

    # =========================================================================
    # Step 5: Critical Point Classification (CriticalPointClassification module)
    # =========================================================================
    println("STEP 5: Critical Point Classification")
    println("-" ^ 40)

    if data.critical_points !== nothing && nrow(data.critical_points) > 0
        cps = copy(data.critical_points)

        # Check if Hessian eigenvalues are available
        eig_cols = [Symbol("hessian_eig$i") for i in 1:data.dim]
        if all(c -> hasproperty(cps, c), eig_cols)
            classify_all_critical_points!(cps)
            summary = get_classification_summary(cps)

            for (type, count) in summary
                @printf("  %s: %d\n", type, count)
            end
        else
            # Use pre-computed classification from results_summary
            total_minima = sum(skipmissing(df.hessian_minima))
            total_saddle = sum(skipmissing(df.hessian_saddle))
            total_degen = sum(skipmissing(df.hessian_degenerate))
            @printf("  Minima: %d\n", total_minima)
            @printf("  Saddles: %d\n", total_saddle)
            @printf("  Degenerate: %d\n", total_degen)
        end
    else
        println("  No critical points found.")
    end
    println()

    # =========================================================================
    # Step 6: Best Candidate Summary
    # =========================================================================
    println("STEP 6: Best Candidate Analysis")
    println("-" ^ 40)

    # Use get_quality_summary for consistent best recovery extraction
    summary = get_quality_summary(data)
    if summary.total_cps > 0
        @printf("Best recovery at degree %d:\n", summary.best_degree)
        @printf("  Point: [%s]\n", join([@sprintf("%.6f", x) for x in summary.best_point], ", "))
        @printf("  Distance to p_true: %.6e\n", summary.best_recovery_distance)
        @printf("  Relative error: %.2f%%\n", summary.best_recovery_error)
        @printf("  Success: %s\n", summary.success ? "✓" : "✗")
    else
        println("  No critical points found.")
    end
    println()

    # =========================================================================
    # Summary
    # =========================================================================
    println("=" ^ 70)
    println("PIPELINE COMPLETE")
    println("=" ^ 70)
    println()
    println("Next steps:")
    println("  1. For visualization: use globtimplots package")
    println("  2. For refinement: use refine_critical_points() from globtimpostprocessing")
    println("  3. For sweep analysis: use analyze_sweep() with multiple experiments")
    println()

    return data
end

# Run with command line argument or default
if abspath(PROGRAM_FILE) == @__FILE__
    exp_path = length(ARGS) >= 1 ? ARGS[1] : DEFAULT_EXP
    main(exp_path)
end
