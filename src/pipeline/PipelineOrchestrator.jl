"""
    PipelineOrchestrator.jl - Run analysis on pending experiments

Orchestrates the analysis workflow for discovered experiments.
"""

using Dates

# ANSI color codes
const ORCH_CYAN = "\e[36m"
const ORCH_YELLOW = "\e[33m"
const ORCH_GREEN = "\e[32m"
const ORCH_RED = "\e[31m"
const ORCH_DIM = "\e[2m"
const ORCH_BOLD = "\e[1m"
const ORCH_RESET = "\e[0m"

# ============================================================================
# Analysis Functions
# ============================================================================

"""
    analyze_experiment!(registry, entry; verbose=true) -> Bool

Run analysis on a single experiment.

Returns true if analysis succeeded, false otherwise.
"""
function analyze_experiment!(
    registry::PipelineRegistry,
    entry::ExperimentEntry;
    verbose::Bool=true
)::Bool
    exp_path = entry.path
    exp_name = entry.name

    if verbose
        println("$(ORCH_CYAN)▶ Analyzing:$(ORCH_RESET) $exp_name")
    end

    # Mark as analyzing
    update_experiment_status!(registry, exp_path, ANALYZING)
    save_pipeline_registry(registry)

    try
        # Detect experiment type and run appropriate analysis
        exp_type = discover_experiment_type(exp_path)

        if exp_type == :lv4d
            _analyze_lv4d_experiment(exp_path; verbose=verbose)
        else
            if verbose
                println("$(ORCH_YELLOW)  Unknown experiment type: $exp_type - skipping detailed analysis$(ORCH_RESET)")
            end
        end

        # Mark as analyzed
        update_experiment_status!(registry, exp_path, ANALYZED)
        save_pipeline_registry(registry)

        if verbose
            println("$(ORCH_GREEN)✓$(ORCH_RESET) Analysis complete: $exp_name")
        end

        return true
    catch e
        # Mark as failed
        update_experiment_status!(registry, exp_path, FAILED)
        save_pipeline_registry(registry)

        if verbose
            println("$(ORCH_RED)✗$(ORCH_RESET) Analysis failed: $exp_name")
            println("$(ORCH_DIM)  Error: $e$(ORCH_RESET)")
        end

        return false
    end
end

"""
    _analyze_lv4d_experiment(exp_path; verbose=true)

Run LV4D-specific analysis on an experiment.
"""
function _analyze_lv4d_experiment(exp_path::String; verbose::Bool=true)
    # Load experiment config
    config_path = joinpath(exp_path, "experiment_config.json")
    if !isfile(config_path)
        if verbose
            println("$(ORCH_DIM)  No config file found$(ORCH_RESET)")
        end
        return
    end

    config = JSON.parsefile(config_path)

    # Load results summary
    summary_path = joinpath(exp_path, "results_summary.json")
    if !isfile(summary_path)
        if verbose
            println("$(ORCH_DIM)  No results summary found$(ORCH_RESET)")
        end
        return
    end

    results = JSON.parsefile(summary_path)

    # Compute summary statistics
    if verbose
        GN = get(config, "GN", "?")
        domain = get(config, "domain_range", "?")
        seed = get(config, "seed", "?")
        println("$(ORCH_DIM)  GN=$GN, domain=$domain, seed=$seed$(ORCH_RESET)")

        # Summary from results
        if !isempty(results)
            degrees_run = length(results)
            successful = count(r -> get(r, "success", false), results)
            println("$(ORCH_DIM)  Degrees run: $degrees_run, successful: $successful$(ORCH_RESET)")

            # Best L2 norm
            l2_norms = [get(r, "L2_norm", Inf) for r in results if get(r, "success", false)]
            if !isempty(l2_norms)
                best_l2 = minimum(l2_norms)
                println("$(ORCH_DIM)  Best L2 norm: $(round(best_l2, sigdigits=4))$(ORCH_RESET)")
            end

            # Best recovery error
            recovery_errors = [get(r, "recovery_error", Inf) for r in results if get(r, "success", false)]
            if !isempty(recovery_errors) && any(isfinite, recovery_errors)
                best_recovery = minimum(filter(isfinite, recovery_errors))
                println("$(ORCH_DIM)  Best recovery error: $(round(best_recovery, sigdigits=4))$(ORCH_RESET)")
            end
        end
    end

    # Create analysis summary file
    analysis_summary = Dict{String, Any}(
        "analyzed_at" => string(now()),
        "experiment_path" => exp_path,
        "config" => config,
        "results_count" => length(results),
        "successful_count" => count(r -> get(r, "success", false), results)
    )

    summary_output = joinpath(exp_path, ".analysis_summary.json")
    open(summary_output, "w") do io
        JSON.print(io, analysis_summary, 2)
    end
end

# ============================================================================
# Batch Analysis
# ============================================================================

"""
    analyze_pending!(registry; verbose=true, limit=nothing) -> NamedTuple

Analyze all pending experiments in the registry.

# Returns
Named tuple with fields:
- `analyzed::Int`: Number successfully analyzed
- `failed::Int`: Number that failed
- `total::Int`: Total pending experiments
"""
function analyze_pending!(
    registry::PipelineRegistry;
    verbose::Bool=true,
    limit::Union{Int, Nothing}=nothing
)
    pending = get_pending_experiments(registry)
    total = length(pending)

    if limit !== nothing
        pending = pending[1:min(limit, length(pending))]
    end

    if isempty(pending)
        if verbose
            println("$(ORCH_DIM)No pending experiments to analyze.$(ORCH_RESET)")
        end
        return (analyzed=0, failed=0, total=0)
    end

    if verbose
        println()
        println("$(ORCH_BOLD)Analyzing $(length(pending)) pending experiments$(ORCH_RESET)")
        println("$(ORCH_DIM)─────────────────────────────────────$(ORCH_RESET)")
    end

    analyzed = 0
    failed = 0

    for (i, entry) in enumerate(pending)
        if verbose
            println()
            println("[$i/$(length(pending))]")
        end

        success = analyze_experiment!(registry, entry; verbose=verbose)
        if success
            analyzed += 1
        else
            failed += 1
        end
    end

    if verbose
        println()
        println("$(ORCH_DIM)─────────────────────────────────────$(ORCH_RESET)")
        println("$(ORCH_GREEN)Analyzed:$(ORCH_RESET) $analyzed  $(ORCH_RED)Failed:$(ORCH_RESET) $failed  $(ORCH_DIM)Total pending: $total$(ORCH_RESET)")
    end

    return (analyzed=analyzed, failed=failed, total=total)
end

# ============================================================================
# Watch Mode
# ============================================================================

"""
    watch_and_analyze(registry; interval=60, max_iterations=nothing, verbose=true)

Watch for new experiments and analyze them automatically.

# Keyword Arguments
- `interval::Int`: Seconds between scans (default: 60)
- `max_iterations::Union{Int, Nothing}`: Maximum iterations (nothing = infinite)
- `verbose::Bool`: Print status messages (default: true)
"""
function watch_and_analyze(
    registry::PipelineRegistry;
    interval::Int=60,
    max_iterations::Union{Int, Nothing}=nothing,
    verbose::Bool=true
)
    if verbose
        println()
        println("$(ORCH_BOLD)$(ORCH_CYAN)PIPELINE WATCH MODE$(ORCH_RESET)")
        println("$(ORCH_DIM)─────────────────────────$(ORCH_RESET)")
        println("$(ORCH_DIM)Scanning every $interval seconds$(ORCH_RESET)")
        println("$(ORCH_DIM)Results root: $(registry.results_root)$(ORCH_RESET)")
        println("$(ORCH_DIM)Press Ctrl+C to stop$(ORCH_RESET)")
        println()
    end

    iteration = 0
    try
        while true
            iteration += 1

            if max_iterations !== nothing && iteration > max_iterations
                if verbose
                    println("$(ORCH_DIM)Max iterations reached.$(ORCH_RESET)")
                end
                break
            end

            # Scan for new experiments
            new_count = scan_for_experiments!(registry)
            save_pipeline_registry(registry)

            if verbose && new_count > 0
                println("$(ORCH_GREEN)Found $new_count new experiments$(ORCH_RESET)")
            end

            # Analyze pending
            result = analyze_pending!(registry; verbose=verbose)

            if verbose && (result.analyzed > 0 || result.failed > 0)
                println()
            end

            # Status line
            pending_count = length(get_pending_experiments(registry))
            analyzed_count = length(get_analyzed_experiments(registry))
            timestamp = Dates.format(now(), "HH:MM:SS")

            if verbose
                print("\r$(ORCH_DIM)[$timestamp] Pending: $pending_count | Analyzed: $analyzed_count | Next scan in $interval s$(ORCH_RESET)          ")
            end

            # Sleep
            sleep(interval)
        end
    catch e
        if e isa InterruptException
            if verbose
                println()
                println("$(ORCH_YELLOW)Watch mode stopped.$(ORCH_RESET)")
            end
        else
            rethrow(e)
        end
    end
end

# ============================================================================
# Status Functions
# ============================================================================

"""
    get_pipeline_status(registry) -> NamedTuple

Get current pipeline status summary.
"""
function get_pipeline_status(registry::PipelineRegistry)
    pending = 0
    analyzing = 0
    analyzed = 0
    failed = 0

    for (_, entry) in registry.experiments
        if entry.status == DISCOVERED
            pending += 1
        elseif entry.status == ANALYZING
            analyzing += 1
        elseif entry.status == ANALYZED
            analyzed += 1
        elseif entry.status == FAILED
            failed += 1
        end
    end

    total = length(registry.experiments)
    last_scan = registry.last_scan

    return (
        total=total,
        pending=pending,
        analyzing=analyzing,
        analyzed=analyzed,
        failed=failed,
        last_scan=last_scan,
        results_root=registry.results_root
    )
end

"""
    print_pipeline_status(registry)

Print formatted pipeline status.
"""
function print_pipeline_status(registry::PipelineRegistry)
    status = get_pipeline_status(registry)

    println()
    println("$(ORCH_BOLD)Pipeline Status$(ORCH_RESET)")
    println("$(ORCH_DIM)─────────────────────────$(ORCH_RESET)")
    println("  Results root: $(ORCH_BOLD)$(status.results_root)$(ORCH_RESET)")
    last_scan_str = status.last_scan === nothing ? "never" : Dates.format(status.last_scan, "yyyy-mm-dd HH:MM:SS")
    println("  Last scan:    $(last_scan_str)")
    println()
    println("  $(ORCH_CYAN)Total:$(ORCH_RESET)     $(status.total)")
    println("  $(ORCH_YELLOW)Pending:$(ORCH_RESET)   $(status.pending)")
    println("  $(ORCH_CYAN)Analyzing:$(ORCH_RESET) $(status.analyzing)")
    println("  $(ORCH_GREEN)Analyzed:$(ORCH_RESET)  $(status.analyzed)")
    println("  $(ORCH_RED)Failed:$(ORCH_RESET)    $(status.failed)")
    println()
end
