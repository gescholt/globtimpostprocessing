#=
LV4D Post-Processing REPL Workflow
==================================

Usage in Julia REPL:
    include("scripts/lv4d_repl_workflow.jl")

This provides:
    - registry: Loaded PipelineRegistry
    - lv4d_experiments(): Get all LV4D experiment paths
    - failed_experiments(): Get failed experiments
    - remove_failed!(): Remove all failed experiments
    - analyze_lv4d(path): Quick single-experiment analysis
    - analyze_lv4d(1): Analyze by index
=#

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using GlobtimPostProcessing
using GlobtimPostProcessing.Pipeline
using GlobtimPostProcessing.Pipeline: DISCOVERED, ANALYZING, ANALYZED, FAILED
using GlobtimPostProcessing.LV4DAnalysis
using DataFrames

# ============================================================================
# Registry Setup
# ============================================================================

println("Loading registry...")
if !@isdefined(registry) || !isa(registry, PipelineRegistry)
    global registry = load_pipeline_registry()
else
    println("  (Using existing registry, call reload_registry!() to refresh)")
end
n_new = scan_for_experiments!(registry)
if n_new > 0
    println("  Discovered $n_new new experiments")
    save_pipeline_registry(registry)
end
println("  $(length(registry.experiments)) experiments loaded")

"""Reload the registry from disk"""
function reload_registry!()
    global registry = load_pipeline_registry()
    n_new = scan_for_experiments!(registry)
    if n_new > 0
        save_pipeline_registry(registry)
    end
    println("Registry reloaded: $(length(registry.experiments)) experiments")
    return registry
end

# ============================================================================
# LV4D Experiment Helpers
# ============================================================================

"""Get all LV4D experiment paths from registry"""
function lv4d_experiments()
    [path for (path, _) in registry.experiments
     if contains(lowercase(path), "lotka_volterra_4d")]
end

"""Get experiments by status"""
function experiments_by_status(status::ExperimentStatus)
    [path for (path, entry) in registry.experiments if entry.status == status]
end

"""Get failed experiments"""
failed_experiments() = experiments_by_status(FAILED)

"""Get analyzed experiments"""
analyzed_experiments() = experiments_by_status(ANALYZED)

"""Get discovered (pending) experiments"""
discovered_experiments() = experiments_by_status(DISCOVERED)

"""Remove all failed experiments from registry"""
function remove_failed!(; save::Bool=true)
    failed = failed_experiments()
    for path in failed
        remove_experiment!(registry, path)
        println("  Removed: $(basename(path))")
    end
    if save && !isempty(failed)
        save_pipeline_registry(registry)
    end
    println("Removed $(length(failed)) failed experiments")
    return failed
end

# ============================================================================
# LV4D Analysis Shortcuts
# ============================================================================

"""Quick analysis of single LV4D experiment"""
function analyze_lv4d(path::String; verbose::Bool=true)
    exp = load_experiment(path)

    if verbose
        println("\n" * "="^60)
        println("Experiment: $(experiment_id(exp))")
        println("="^60)
        println("Degrees: ", available_degrees(exp))

        # Quality summary
        if has_critical_points(exp)
            cps = critical_points(exp)
            println("Critical points: ", nrow(cps))
        end

        # Degree results
        dr = degree_results(exp)
        if dr !== nothing && !isempty(dr)
            println("\nDegree Results:")
            println(dr[:, [:degree, :L2_norm, :critical_points, :recovery_error]])
        end
    end

    return exp
end

"""Analyze LV4D experiment by index (1-based)"""
function analyze_lv4d(idx::Int; kwargs...)
    paths = lv4d_experiments()
    if idx < 1 || idx > length(paths)
        error("Index $idx out of range (1-$(length(paths)))")
    end
    analyze_lv4d(paths[idx]; kwargs...)
end

"""List LV4D experiments with indices"""
function list_lv4d(; limit::Int=20)
    paths = lv4d_experiments()
    println("\nLV4D Experiments ($(length(paths)) total):")
    println("-"^60)
    for (i, path) in enumerate(paths[1:min(limit, length(paths))])
        entry = registry.experiments[path]
        status_str = string(entry.status)
        params = entry.params
        if params !== nothing
            println("  $i. GN=$(params.GN), deg=$(params.deg_min)-$(params.deg_max), domain=$(params.domain) [$status_str]")
        else
            println("  $i. $(basename(path)) [$status_str]")
        end
    end
    if length(paths) > limit
        println("  ... and $(length(paths) - limit) more")
    end
end

# ============================================================================
# Print Summary
# ============================================================================

println("\n" * "="^60)
println("LV4D Post-Processing Workflow Ready")
println("="^60)

lv4d_paths = lv4d_experiments()
failed = failed_experiments()
analyzed = analyzed_experiments()
discovered = discovered_experiments()
println("  LV4D experiments: $(length(lv4d_paths))")
println("  Status: $(length(analyzed)) analyzed, $(length(discovered)) pending, $(length(failed)) failed")

println("\nAvailable commands:")
println("  lv4d_experiments()      # List all LV4D experiment paths")
println("  list_lv4d()             # Show experiments with indices")
println("  failed_experiments()    # List failed experiments")
println("  remove_failed!()        # Remove all failed from registry")
println("  analyze_lv4d(path)      # Quick analysis of experiment")
println("  analyze_lv4d(1)         # Analyze by index")
println("  reload_registry!()      # Reload registry from disk")
println("  lv4d()                  # Launch interactive TUI")
println()
