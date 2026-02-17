"""
Main entry point for unified post-processing TUI.

Provides postprocess() function that guides users through experiment analysis.
"""

# ============================================================================
# Main Entry Point
# ============================================================================

"""
    postprocess(; results_root::Union{String, Nothing}=nothing) -> Union{DataFrame, NamedTuple, Nothing}

Interactive unified post-processing TUI.

Launches an interactive terminal interface where you can:
1. Select experiment type (LV4D, Deuflhard, etc.) or auto-detect
2. Select results source (browse recent, enter path)
3. Select analysis mode (type-specific options)
4. Configure parameters through cascading menus
5. Run analysis and get results

# Arguments
- `results_root::Union{String, Nothing}`: Optional results directory (auto-detected if nothing)

# Returns
- Analysis results (type depends on analysis mode):
  - DataFrame for sweep/convergence analysis
  - NamedTuple for detailed results
  - Nothing if cancelled or analysis prints to console

# Example
```julia
using GlobtimPostProcessing

# Launch interactive mode
result = postprocess()

# If result is a DataFrame, inspect it
if result isa DataFrame
    first(result, 5)
end
```

# Workflow

```
postprocess()
    │
    ├── Step 1: Select experiment type
    │     → LV4D / Deuflhard / Auto-detect
    │
    ├── Step 2: Select results source
    │     → Browse recent / Enter path
    │
    ├── Step 3: Select analysis mode (type-dispatched)
    │     LV4D: quality / sweep / convergence / compare / coverage
    │
    ├── Step 4: Configure parameters (menus)
    │     GN values, degree range, domain filter, etc.
    │
    └── Step 5: Run & display results
          → Load → Analyze → Tables/Summary → Return DataFrame
```
"""
function postprocess(; results_root::Union{String, Nothing}=nothing)
    # Get results root
    root = results_root === nothing ? find_unified_results_root() : results_root

    tui_header("UNIFIED POST-PROCESSING")

    # Step 1: Select experiment type
    exp_type = select_experiment_type()

    # Step 2: Select results source and get experiment path
    source = select_results_source(root)
    source === nothing && return nothing

    exp_path = _resolve_experiment_path(source, root, exp_type)
    exp_path === nothing && return nothing

    # Auto-detect type if needed
    if exp_type === nothing
        exp_type = detect_experiment_type(exp_path)
        tui_info("Detected experiment type: $(type_name(exp_type))")
    end

    # Step 3: Select analysis mode
    analysis_mode = select_analysis_mode(exp_type)
    analysis_mode === nothing && return nothing

    # Step 4 & 5: Run analysis (dispatched by type and mode)
    return _run_unified_analysis(exp_type, analysis_mode, exp_path, root)
end

# ============================================================================
# Path Resolution
# ============================================================================

"""
    _resolve_experiment_path(source::ResultsSource, root::String, type_filter) -> Union{String, Nothing}

Resolve experiment path from results source selection.
"""
function _resolve_experiment_path(source::ResultsSource, root::String,
                                   type_filter::Union{ExperimentType, Nothing})::Union{String, Nothing}
    if source.type == :recent
        return select_recent_experiment(root; type_filter=type_filter)
    elseif source.type == :path
        path = expanduser(source.value)
        if !isdir(path)
            tui_error("Directory not found: $path")
            return nothing
        end
        return path
    else
        return nothing
    end
end

# ============================================================================
# Analysis Dispatch
# ============================================================================

"""
    _run_unified_analysis(type::ExperimentType, mode::Symbol, path::String, root::String)

Dispatch to type-specific analysis handler.
"""
function _run_unified_analysis(type::ExperimentType, mode::Symbol, path::String, root::String)
    # LV4D has its own comprehensive TUI - delegate to it
    if type isa LV4DType
        return _run_lv4d_analysis(mode, path, root)
    end

    # Generic analysis for other types
    return _run_generic_analysis(type, mode, path)
end

"""
    _run_lv4d_analysis(mode::Symbol, path::String, root::String)

Run LV4D-specific analysis using existing LV4DAnalysis TUI functions.
"""
function _run_lv4d_analysis(mode::Symbol, path::String, root::String)
    LV4DAnalysis = Main.GlobtimPostProcessing.LV4DAnalysis

    # Determine if path is single experiment or results root
    is_single = is_single_experiment(path)

    if mode == :quality
        if !is_single
            # Need to select specific experiment
            exp_dir = select_recent_experiment(root; type_filter=LV4D)
            exp_dir === nothing && return nothing
            path = exp_dir
        end

        tui_running("Running quality analysis...")
        LV4DAnalysis.analyze_quality(path)
        return nothing

    elseif mode == :sweep
        # Use the results root for sweep analysis
        sweep_root = is_single ? dirname(path) : root

        # If root doesn't have LV4D experiments, try to find lv4d subdir
        if !any(e -> startswith(basename(e), "lv4d_"), readdir(sweep_root, join=true))
            lv4d_dir = joinpath(sweep_root, "lotka_volterra_4d")
            if isdir(lv4d_dir)
                sweep_root = lv4d_dir
            end
        end

        tui_running("Running sweep analysis...")
        # Use default filter for now - could add TUI for filter configuration
        experiments = LV4DAnalysis.load_sweep_experiments(sweep_root)
        if isempty(experiments)
            tui_warning("No experiments found for sweep analysis")
            return nothing
        end

        # Run sweep with loaded experiments
        return LV4DAnalysis.analyze_sweep(experiments)

    elseif mode == :convergence
        tui_running("Running convergence analysis...")
        return LV4DAnalysis.analyze_convergence(root)

    elseif mode == :compare
        # Find comparison experiments
        comp_dir = LV4DAnalysis.find_comparison_experiments(root; limit=10)
        if isempty(comp_dir)
            tui_warning("No comparison experiments found")
            return nothing
        end

        # Show menu to select
        options = [basename(d) for d in comp_dir]
        menu = RadioMenu(options, pagesize=min(8, length(options)))
        choice = request("Select comparison experiment:", menu)
        choice == -1 && return nothing

        tui_running("Running comparison analysis...")
        data = LV4DAnalysis.load_comparison_data(comp_dir[choice])
        LV4DAnalysis.analyze_comparison(data)
        return nothing

    elseif mode == :coverage
        tui_running("Running coverage analysis...")
        # Use default coverage settings
        report = LV4DAnalysis.analyze_coverage(root)
        LV4DAnalysis.print_coverage_report(report)
        return report

    else
        tui_error("Unknown analysis mode: $mode")
        return nothing
    end
end

"""
    _run_generic_analysis(type::ExperimentType, mode::Symbol, path::String)

Run generic analysis for non-LV4D experiment types.
"""
function _run_generic_analysis(type::ExperimentType, mode::Symbol, path::String)
    # Load experiment using unified loader
    tui_info("Loading experiment: $(basename(path))")

    data = load_experiment(path; type=type)

    if mode == :quality
        tui_running("Running quality analysis...")
        _print_generic_quality(data)
        return nothing

    elseif mode == :convergence
        tui_running("Running convergence analysis...")
        return _compute_generic_convergence(data)

    else
        tui_error("Analysis mode '$mode' not yet implemented for $(type_name(type))")
        return nothing
    end
end

# ============================================================================
# Generic Analysis Functions
# ============================================================================

"""
    _print_generic_quality(data::BaseExperimentData)

Print quality diagnostics for generic experiment.
"""
function _print_generic_quality(data::BaseExperimentData)
    println()
    println("$(UNIFIED_TUI_BOLD)Experiment: $(data.experiment_id)$(UNIFIED_TUI_RESET)")
    println("$(UNIFIED_TUI_DIM)Type: $(type_name(data.experiment_type))$(UNIFIED_TUI_RESET)")
    println("$(UNIFIED_TUI_DIM)Path: $(data.path)$(UNIFIED_TUI_RESET)")
    println()

    # Degree results summary
    dr = data.degree_results
    if nrow(dr) > 0
        println("$(UNIFIED_TUI_BOLD)Degree Results:$(UNIFIED_TUI_RESET)")

        # Build summary table
        if hasproperty(dr, :degree) && hasproperty(dr, :L2_norm)
            headers = ["Degree", "L2 Norm", "Critical Points"]
            data_matrix = Matrix{Any}(undef, nrow(dr), 3)

            for (i, row) in enumerate(eachrow(dr))
                data_matrix[i, 1] = row.degree
                data_matrix[i, 2] = hasproperty(row, :L2_norm) ? @sprintf("%.2e", row.L2_norm) : "-"
                data_matrix[i, 3] = hasproperty(row, :critical_points) ? row.critical_points : "-"
            end

            styled_table(data_matrix; header=headers, alignment=[:r, :r, :r])
        else
            styled_table(dr; header=string.(names(dr)), alignment=:r)
        end
    else
        tui_warning("No degree results found")
    end

    # Critical points summary
    cp = data.critical_points
    if cp !== nothing && nrow(cp) > 0
        println()
        println("$(UNIFIED_TUI_BOLD)Critical Points: $(nrow(cp)) total$(UNIFIED_TUI_RESET)")

        # Show per-degree counts
        if hasproperty(cp, :degree)
            counts = combine(groupby(cp, :degree), nrow => :count)
            sort!(counts, :degree)
            for row in eachrow(counts)
                println("  Degree $(row.degree): $(row.count) points")
            end
        end
    else
        tui_warning("No critical points found")
    end
end

"""
    _compute_generic_convergence(data::BaseExperimentData) -> Union{DataFrame, Nothing}

Compute convergence metrics for generic experiment.
"""
function _compute_generic_convergence(data::BaseExperimentData)::Union{DataFrame, Nothing}
    dr = data.degree_results

    if nrow(dr) == 0 || !hasproperty(dr, :degree) || !hasproperty(dr, :L2_norm)
        tui_warning("Insufficient data for convergence analysis")
        return nothing
    end

    # Sort by degree
    sorted = sort(dr, :degree)

    # Filter valid L2 values
    valid_rows = filter(r -> !isnan(r.L2_norm) && r.L2_norm > 0, sorted)

    if nrow(valid_rows) < 2
        tui_warning("Need at least 2 valid degree results for convergence")
        return valid_rows
    end

    # Compute log-log slope if possible
    degrees = valid_rows.degree
    l2_norms = valid_rows.L2_norm

    log_degrees = log.(Float64.(degrees))
    log_l2 = log.(l2_norms)

    # Simple linear regression for slope
    n = length(log_degrees)
    x_mean = mean(log_degrees)
    y_mean = mean(log_l2)

    numerator = sum((log_degrees .- x_mean) .* (log_l2 .- y_mean))
    denominator = sum((log_degrees .- x_mean).^2)

    slope = denominator > 0 ? numerator / denominator : NaN

    println()
    println("$(UNIFIED_TUI_BOLD)Convergence Analysis:$(UNIFIED_TUI_RESET)")
    println("  Degrees: $(minimum(degrees)) - $(maximum(degrees))")
    println("  L2 norm range: $(@sprintf("%.2e", minimum(l2_norms))) - $(@sprintf("%.2e", maximum(l2_norms)))")
    if !isnan(slope)
        println("  Log-log slope: $(@sprintf("%.2f", slope))")
    end

    return valid_rows
end
