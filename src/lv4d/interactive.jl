"""
REPL utilities for LV4D analysis.

For CLI usage, use the analyze_lv4d script directly.
For Julia REPL, these utilities provide convenient experiment selection.
"""

# ============================================================================
# Experiment Selection Utilities
# ============================================================================

"""
    select_experiment(results_root::String=find_results_root(); limit::Int=15) -> String

Interactive experiment selection menu for Julia REPL.

Lists recent experiments and prompts user to select one.

# Arguments
- `results_root::String`: Directory to search for experiments
- `limit::Int=15`: Maximum number of experiments to show

# Returns
Path to selected experiment directory.

# Example (in Julia REPL)
```julia
using GlobtimPostProcessing.LV4DAnalysis
exp_dir = select_experiment()
analyze_quality(exp_dir)
```
"""
function select_experiment(results_root::String=find_results_root(); limit::Int=15)::String
    experiments = list_recent_experiments(results_root; limit=limit)

    if isempty(experiments)
        error("No experiments found in: $results_root")
    end

    # Build options with age info
    options = map(experiments) do exp
        name = basename(exp)
        age = time() - mtime(exp)
        age_str = format_age(age)
        "$name ($age_str ago)"
    end

    println("\nSelect experiment (most recent first):")
    for (i, opt) in enumerate(options)
        println("  $i. $opt")
    end

    print("\nEnter number (1-$(length(options))): ")
    choice_str = readline()
    choice = tryparse(Int, choice_str)

    if choice === nothing || choice < 1 || choice > length(options)
        error("Invalid selection: $choice_str")
    end

    return experiments[choice]
end

# ============================================================================
# Deprecated: Interactive Mode
# ============================================================================

"""
    run_interactive(; results_root::Union{String, Nothing}=nothing)

DEPRECATED: Interactive mode has been removed from the CLI.

For CLI usage, use subcommands directly:
    analyze_lv4d sweep
    analyze_lv4d quality <dir>
    analyze_lv4d convergence

For Julia REPL, call functions directly:
    analyze_sweep(results_root)
    analyze_quality(experiment_dir)
    analyze_convergence(results_root; gn=8)
"""
function run_interactive(; results_root::Union{String, Nothing}=nothing)
    println()
    println("NOTE: Interactive mode has been deprecated.")
    println()
    println("For CLI usage, use subcommands directly:")
    println("    analyze_lv4d sweep")
    println("    analyze_lv4d quality <dir>")
    println("    analyze_lv4d convergence")
    println()
    println("For Julia REPL, call functions directly:")
    println("    analyze_sweep(\"$(something(results_root, find_results_root()))\")")
    println("    analyze_quality(select_experiment())")
    println("    analyze_convergence(gn=8)")
    println()
end
