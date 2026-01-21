"""
Interactive mode and experiment selection for LV4D analysis.

Provides menu-driven interface for selecting experiments and analysis modes.
"""

# ============================================================================
# Experiment Selection
# ============================================================================

"""
    select_experiment(results_root::String=find_results_root(); limit::Int=15) -> String

Interactive experiment selection menu.

# Arguments
- `results_root::String`: Directory to search for experiments
- `limit::Int=15`: Maximum number of experiments to show

# Returns
Path to selected experiment directory.
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
# Interactive Mode
# ============================================================================

"""
    run_interactive(; results_root::Union{String, Nothing}=nothing)

Run interactive LV4D analysis menu.

Provides options for:
1. Quality analysis (single experiment)
2. Sweep analysis (aggregate)
3. Convergence analysis
4. Gradient threshold analysis
"""
function run_interactive(; results_root::Union{String, Nothing}=nothing)
    results_root = something(results_root, find_results_root())

    println()
    println("="^60)
    println("LV4D Analysis Tool - Interactive Mode")
    println("="^60)
    println()
    println("Results root: $results_root")
    println()

    while true
        println("Available analyses:")
        println("  1. Quality  - Single experiment CP diagnostics")
        println("  2. Sweep    - Aggregate domain × degree analysis")
        println("  3. Convergence - Log-log convergence rate")
        println("  4. Gradients   - Gradient threshold analysis")
        println("  5. Minima      - Local minima clustering")
        println("  q. Quit")
        println()

        print("Select analysis (1-5, q): ")
        choice = strip(readline())

        if choice == "q" || choice == "Q"
            println("Goodbye!")
            break
        elseif choice == "1"
            _run_quality_interactive(results_root)
        elseif choice == "2"
            _run_sweep_interactive(results_root)
        elseif choice == "3"
            _run_convergence_interactive(results_root)
        elseif choice == "4"
            _run_gradients_interactive(results_root)
        elseif choice == "5"
            _run_minima_interactive(results_root)
        else
            println("Invalid choice: $choice")
        end

        println()
    end
end

# ============================================================================
# Interactive Helpers
# ============================================================================

function _run_quality_interactive(results_root::String)
    println("\n--- Quality Analysis ---")
    experiment_dir = select_experiment(results_root)
    analyze_quality(experiment_dir; verbose=true)
end

function _run_sweep_interactive(results_root::String)
    println("\n--- Sweep Analysis ---")
    print("Save output files? (y/n, default y): ")
    save_input = strip(readline())
    save_output = isempty(save_input) || lowercase(save_input) == "y"

    print("Show distributions? (y/n, default y): ")
    verbose_input = strip(readline())
    verbose = isempty(verbose_input) || lowercase(verbose_input) == "y"

    analyze_sweep(results_root; verbose=verbose, save_output=save_output)
end

function _run_convergence_interactive(results_root::String)
    println("\n--- Convergence Analysis ---")

    print("GN value (default 8): ")
    gn_input = strip(readline())
    gn = isempty(gn_input) ? 8 : parse(Int, gn_input)

    print("Degree min (default 4): ")
    deg_min_input = strip(readline())
    degree_min = isempty(deg_min_input) ? 4 : parse(Int, deg_min_input)

    print("Degree max (default 12): ")
    deg_max_input = strip(readline())
    degree_max = isempty(deg_max_input) ? 12 : parse(Int, deg_max_input)

    print("Export CSV for plotting? (y/n, default n): ")
    export_input = strip(readline())
    export_csv = lowercase(export_input) == "y"

    analyze_convergence(results_root; gn=gn, degree_min=degree_min, degree_max=degree_max, export_csv=export_csv)
end

function _run_gradients_interactive(results_root::String)
    println("\n--- Gradient Threshold Analysis ---")

    print("Tolerance (default 0.1): ")
    tol_input = strip(readline())
    tolerance = isempty(tol_input) ? 0.1 : parse(Float64, tol_input)

    analyze_gradient_thresholds(results_root; tolerance=tolerance)
end

function _run_minima_interactive(results_root::String)
    println("\n--- Local Minima Analysis ---")

    # Select experiment first
    experiment_dir = select_experiment(results_root)

    # Look for refinement results
    csv_candidates = [
        joinpath(experiment_dir, "refinement_comparison.csv"),
        joinpath(experiment_dir, "refined_results.csv")
    ]

    csv_path = nothing
    for candidate in csv_candidates
        if isfile(candidate)
            csv_path = candidate
            break
        end
    end

    if csv_path === nothing
        # Search for any refinement CSV
        for f in readdir(experiment_dir)
            if occursin("refine", lowercase(f)) && endswith(f, ".csv")
                csv_path = joinpath(experiment_dir, f)
                break
            end
        end
    end

    if csv_path === nothing
        println("No refinement results found in $(basename(experiment_dir))")
        println("Run refine_results.jl first to generate refinement data.")
        return
    end

    println("Using: $(basename(csv_path))")

    # Load p_true from config
    config_path = joinpath(experiment_dir, "experiment_config.json")
    if !isfile(config_path)
        error("experiment_config.json not found - cannot determine p_true")
    end

    config = JSON.parsefile(config_path)
    p_true = Float64.(config["p_true"])

    print("Cluster threshold (default 0.05): ")
    thresh_input = strip(readline())
    cluster_threshold = isempty(thresh_input) ? 0.05 : parse(Float64, thresh_input)

    analyze_local_minima(csv_path, p_true; cluster_threshold=cluster_threshold)
end
