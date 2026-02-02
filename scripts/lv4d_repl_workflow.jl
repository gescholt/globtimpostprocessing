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
    - find_by_params(GN=16): Filter experiments by parameters
    - coverage(): Show parameter coverage matrix
=#

# ============================================================================
# ANSI Terminal Colors (matching TUI patterns)
# ============================================================================

const CYAN = "\e[36m"
const YELLOW = "\e[33m"
const GREEN = "\e[32m"
const RED = "\e[31m"
const DIM = "\e[2m"
const BOLD = "\e[1m"
const RESET = "\e[0m"

# Status helpers
_success(msg) = println("$(GREEN)✓$(RESET) $msg")
_warning(msg) = println("$(YELLOW)⚠$(RESET) $msg")
_info(msg) = println("$(DIM)ℹ $msg$(RESET)")
_error(msg) = println("$(RED)✗$(RESET) $msg")

# ============================================================================
# Package Loading (quiet)
# ============================================================================

using Pkg
redirect_stderr(devnull) do
    Pkg.activate(joinpath(@__DIR__, ".."), io=devnull)
end
using GlobtimPostProcessing
using GlobtimPostProcessing.Pipeline
using GlobtimPostProcessing.Pipeline: DISCOVERED, ANALYZING, ANALYZED, FAILED
using GlobtimPostProcessing.Pipeline: get_experiments_by_params, get_parameter_coverage, print_coverage_matrix
using GlobtimPostProcessing.LV4DAnalysis
using DataFrames
using PrettyTables
using Printf

# ============================================================================
# Registry Setup
# ============================================================================

if !@isdefined(registry) || !isa(registry, PipelineRegistry)
    global registry = load_pipeline_registry()
else
    _info("Using existing registry, call reload_registry!() to refresh")
end
n_new = scan_for_experiments!(registry)
if n_new > 0
    _info("Discovered $n_new new experiments")
    save_pipeline_registry(registry)
end

"""Reload the registry from disk"""
function reload_registry!()
    global registry = load_pipeline_registry()
    n_new = scan_for_experiments!(registry)
    if n_new > 0
        save_pipeline_registry(registry)
    end
    _success("Registry reloaded: $(length(registry.experiments)) experiments")
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
        _info("Removed: $(basename(path))")
    end
    if save && !isempty(failed)
        save_pipeline_registry(registry)
    end
    _success("Removed $(length(failed)) failed experiments")
    return failed
end

# ============================================================================
# Parameter Query Functions
# ============================================================================

"""
    find_by_params(; GN=nothing, domain=nothing, deg_min=nothing, deg_max=nothing)

Filter experiments by parameters. Returns vector of experiment entries.

# Example
```julia
find_by_params(GN=16)                    # All GN=16 experiments
find_by_params(GN=16, domain=0.08)       # GN=16 with domain=0.08
find_by_params(deg_min=4, deg_max=12)    # Specific degree range
```
"""
function find_by_params(; GN=nothing, domain=nothing, deg_min=nothing, deg_max=nothing)
    results = get_experiments_by_params(registry; GN, domain, deg_min, deg_max)
    if isempty(results)
        _warning("No experiments match the specified parameters")
    else
        _success("Found $(length(results)) matching experiments")
    end
    return results
end

"""
    coverage()

Show parameter coverage matrix for all experiments in the registry.
Displays a grid of GN × domain combinations with experiment counts.
"""
function coverage()
    cov = get_parameter_coverage(registry)
    println()
    println("$(BOLD)Parameter Coverage Matrix$(RESET)")
    println("$(DIM)─────────────────────────$(RESET)")
    print_coverage_matrix(cov)
    println()
end

# ============================================================================
# LV4D Analysis Shortcuts
# ============================================================================

"""Quick analysis of single LV4D experiment"""
function analyze_lv4d(path::String; verbose::Bool=true)
    exp = load_experiment(path)

    if verbose
        println()
        println("$(BOLD)$(CYAN)Experiment: $(experiment_id(exp))$(RESET)")
        println("$(DIM)" * "─"^60 * "$(RESET)")
        println("Degrees: ", available_degrees(exp))

        # Quality summary
        if has_critical_points(exp)
            cps = critical_points(exp)
            _success("$(nrow(cps)) critical points found")
        end

        # Degree results
        dr = degree_results(exp)
        if dr !== nothing && !isempty(dr)
            println("\n$(BOLD)Degree Results:$(RESET)")
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

"""
    list_lv4d(; limit::Int=20)

List LV4D experiments with indices in a formatted table.
"""
function list_lv4d(; limit::Int=20)
    paths = lv4d_experiments()
    n = min(limit, length(paths))

    if n == 0
        _warning("No LV4D experiments found")
        return
    end

    # Build table data
    data = Matrix{Any}(undef, n, 5)
    for (i, path) in enumerate(paths[1:n])
        entry = registry.experiments[path]
        p = entry.params
        data[i, 1] = i
        data[i, 2] = p === nothing ? "-" : p.GN
        data[i, 3] = p === nothing ? "-" : "$(p.deg_min)-$(p.deg_max)"
        data[i, 4] = p === nothing ? "-" : @sprintf("%.2e", p.domain)
        # Color status
        status = entry.status
        data[i, 5] = if status == ANALYZED
            "$(GREEN)analyzed$(RESET)"
        elseif status == FAILED
            "$(RED)failed$(RESET)"
        elseif status == ANALYZING
            "$(YELLOW)analyzing$(RESET)"
        else
            "$(DIM)pending$(RESET)"
        end
    end

    println()
    println("$(BOLD)LV4D Experiments$(RESET) $(DIM)($(length(paths)) total)$(RESET)")
    pretty_table(data,
        header = ["#", "GN", "Deg", "Domain", "Status"],
        alignment = [:r, :r, :c, :r, :l],
        tf = tf_unicode_rounded,
        show_subheader = false
    )

    if length(paths) > limit
        _info("$(length(paths) - limit) more experiments not shown (use limit=N to see more)")
    end
end

# ============================================================================
# Print Summary
# ============================================================================

println()
println("$(BOLD)$(CYAN)LV4D Post-Processing Workflow$(RESET)")
println("$(DIM)─────────────────────────────$(RESET)")

lv4d_paths = lv4d_experiments()
n_analyzed = length(analyzed_experiments())
n_pending = length(discovered_experiments())
n_failed = length(failed_experiments())

_success("$(length(registry.experiments)) experiments in registry")
println("  $(GREEN)$n_analyzed$(RESET) analyzed, $(YELLOW)$n_pending$(RESET) pending, $(RED)$n_failed$(RESET) failed")
println("  $(DIM)$(length(lv4d_paths)) are LV4D experiments$(RESET)")

println()
println("$(BOLD)Commands:$(RESET)")
println("  $(CYAN)list_lv4d()$(RESET)             Show experiments with indices")
println("  $(CYAN)analyze_lv4d(1)$(RESET)         Analyze by index")
println("  $(CYAN)analyze_lv4d(path)$(RESET)      Analyze by path")
println("  $(CYAN)find_by_params(GN=16)$(RESET)   Filter by parameters")
println("  $(CYAN)coverage()$(RESET)              Show parameter coverage matrix")
println("  $(CYAN)failed_experiments()$(RESET)    List failed experiments")
println("  $(CYAN)remove_failed!()$(RESET)        Remove all failed from registry")
println("  $(CYAN)reload_registry!()$(RESET)      Reload registry from disk")
println("  $(CYAN)lv4d()$(RESET)                  Launch interactive TUI")
println()
