"""
Interactive TUI (Text User Interface) for LV4D analysis using REPL.TerminalMenus.

Provides arrow-key navigation for selecting analysis type and parameters.
"""

using REPL.TerminalMenus

# ANSI color codes for TUI styling
const TUI_CYAN = "\e[36m"
const TUI_YELLOW = "\e[33m"
const TUI_GREEN = "\e[32m"
const TUI_DIM = "\e[2m"
const TUI_BOLD = "\e[1m"
const TUI_RESET = "\e[0m"

# ============================================================================
# Main Entry Point
# ============================================================================

"""
    lv4d(; results_root::String=find_results_root()) -> Union{DataFrame, NamedTuple, Nothing}

Interactive LV4D analysis with arrow-key menu navigation.

Launches an interactive TUI in the Julia REPL where you can:
1. Select analysis type (sweep, quality, convergence, compare)
2. Configure parameters through cascading menus
3. Run analysis and get results back as a DataFrame

# Returns
- For `sweep`: DataFrame with aggregated statistics
- For `quality`: Nothing (prints analysis)
- For `convergence`: NamedTuple with slopes and data
- For `compare`: Nothing (prints analysis)

# Example
```julia
using GlobtimPostProcessing.LV4DAnalysis

# Launch interactive mode
df = lv4d()

# Inspect results
first(df, 5)
```
"""
function lv4d(; results_root::String=find_results_root())
    println()
    println("$(TUI_BOLD)$(TUI_CYAN)LV4D INTERACTIVE ANALYSIS$(TUI_RESET)")
    println("$(TUI_DIM)─────────────────────────$(TUI_RESET)")
    println("$(TUI_DIM)Use ↑/↓ to navigate, Enter to select$(TUI_RESET)")
    println()

    # Step 1: Select analysis type
    analysis = _tui_select_analysis_type()
    analysis === nothing && return nothing

    # Step 2: Run analysis based on type
    return _tui_run_analysis(analysis, results_root)
end

# ============================================================================
# Analysis Type Selection
# ============================================================================

const ANALYSIS_TYPES = [
    :sweep => "Aggregate domain × degree analysis",
    :quality => "Single experiment diagnostics",
    :convergence => "Log-log convergence rate",
    :compare => "Method comparison (log vs standard)",
    :coverage => "Coverage analysis & gap detection",
    :pending => "Analyze pending experiments (pipeline)"
]

function _tui_select_analysis_type()::Union{Symbol, Nothing}
    options = ["$(String(k)) - $v" for (k, v) in ANALYSIS_TYPES]
    menu = RadioMenu(options, pagesize=4)
    choice = request("Select analysis type:", menu)

    choice == -1 && return nothing
    return ANALYSIS_TYPES[choice][1]
end

# ============================================================================
# Parameter Detection
# ============================================================================

"""
Detect available GN values from experiment directories.
"""
function _tui_detect_gn_values(results_root::String)::Vector{Int}
    experiments = find_experiments(results_root)
    gn_values = Set{Int}()

    for exp in experiments
        params = parse_experiment_name(basename(exp))
        params === nothing && continue
        push!(gn_values, params.GN)
    end

    return sort(collect(gn_values))
end

"""
Detect available degree values from experiment directories.
"""
function _tui_detect_degree_values(results_root::String; gn::Union{Int, Nothing}=nothing)::Vector{Int}
    experiments = find_experiments(results_root)
    degrees = Set{Int}()

    for exp in experiments
        params = parse_experiment_name(basename(exp))
        params === nothing && continue

        # Skip if GN filter is set and doesn't match
        if gn !== nothing && params.GN != gn
            continue
        end

        push!(degrees, params.degree_min)
        push!(degrees, params.degree_max)
    end

    return sort(collect(degrees))
end

"""
Detect available domain values from experiment directories.
"""
function _tui_detect_domain_values(results_root::String; gn::Union{Int, Nothing}=nothing)::Vector{Float64}
    experiments = find_experiments(results_root)
    domains = Set{Float64}()

    for exp in experiments
        params = parse_experiment_name(basename(exp))
        params === nothing && continue

        if gn !== nothing && params.GN != gn
            continue
        end

        push!(domains, params.domain)
    end

    return sort(collect(domains))
end

# ============================================================================
# Menu Selection Helpers
# ============================================================================

function _tui_select_gn(results_root::String)::Union{Int, Nothing}
    gn_values = _tui_detect_gn_values(results_root)

    if isempty(gn_values)
        println("$(TUI_YELLOW)No experiments found with valid GN values.$(TUI_RESET)")
        return nothing
    end

    if length(gn_values) == 1
        println("$(TUI_DIM)Using GN=$(gn_values[1]) (only available value)$(TUI_RESET)")
        return gn_values[1]
    end

    options = string.(gn_values)
    menu = RadioMenu(options, pagesize=min(8, length(options)))
    choice = request("Select GN value:", menu)

    choice == -1 && return nothing
    return gn_values[choice]
end

function _tui_select_degree_range(results_root::String; gn::Union{Int, Nothing}=nothing)::Union{Tuple{Int, Int}, Nothing}
    degrees = _tui_detect_degree_values(results_root; gn=gn)

    if isempty(degrees)
        println("$(TUI_YELLOW)No experiments found with valid degree values.$(TUI_RESET)")
        return nothing
    end

    min_deg, max_deg = extrema(degrees)

    # If only one degree, no choice needed
    if length(degrees) == 1
        println("$(TUI_DIM)Using degree=$(degrees[1]) (only available value)$(TUI_RESET)")
        return (degrees[1], degrees[1])
    end

    # Common options
    options = String[]
    ranges = Tuple{Int, Int}[]

    # Full range option
    push!(options, "$(min_deg)-$(max_deg) (all available)")
    push!(ranges, (min_deg, max_deg))

    # Subset ranges based on available degrees
    for (lo, hi) in [(4, 10), (4, 12), (8, 12), (6, 10)]
        if lo >= min_deg && hi <= max_deg && lo < hi && (lo, hi) != (min_deg, max_deg)
            push!(options, "$lo-$hi")
            push!(ranges, (lo, hi))
        end
    end

    # Single degree options (only for degrees that exist)
    for d in sort(degrees)
        push!(options, "$d (single degree)")
        push!(ranges, (d, d))
    end

    menu = RadioMenu(options, pagesize=min(10, length(options)))
    choice = request("Select degree range:", menu)

    choice == -1 && return nothing
    return ranges[choice]
end

function _tui_select_domain_filter(results_root::String; gn::Union{Int, Nothing}=nothing)::Union{Float64, Nothing}
    domains = _tui_detect_domain_values(results_root; gn=gn)

    if isempty(domains)
        println("$(TUI_YELLOW)No experiments found with valid domain values.$(TUI_RESET)")
        return nothing
    end

    min_domain = minimum(domains)
    max_domain = maximum(domains)

    # Build options based on actual available domains
    options = String[]
    values = Float64[]

    # Standard thresholds - only show if experiments exist at or below that threshold
    standard_thresholds = [0.002, 0.005, 0.010, 0.050, 0.100]

    for thresh in standard_thresholds
        # Only add threshold if at least one experiment has domain ≤ thresh
        if min_domain <= thresh && thresh <= max_domain
            n_matching = count(d -> d <= thresh, domains)
            label = @sprintf("≤ %.4f (%d experiments)", thresh, n_matching)
            if thresh == 0.005
                label = @sprintf("≤ %.4f (%d experiments, default)", thresh, n_matching)
            end
            push!(options, label)
            push!(values, thresh)
        end
    end

    # Always add "all domains" option
    n_total = length(domains)
    if max_domain <= 0.01
        label = @sprintf("All domains (≤ %.4f, %d experiments)", max_domain, n_total)
    else
        label = @sprintf("All domains (≤ %.2f, %d experiments)", max_domain, n_total)
    end
    push!(options, label)
    push!(values, max_domain)

    # Remove duplicates (in case max_domain equals a threshold)
    unique_pairs = unique(collect(zip(options, values)))
    options = [p[1] for p in unique_pairs]
    values = [p[2] for p in unique_pairs]

    if length(options) == 1
        println("$(TUI_DIM)Using domain filter: $(options[1])$(TUI_RESET)")
        return values[1]
    end

    menu = RadioMenu(options, pagesize=min(6, length(options)))
    choice = request("Select domain filter:", menu)

    choice == -1 && return nothing
    return values[choice]
end

function _tui_select_experiment(results_root::String)::Union{String, Nothing}
    experiments = list_recent_experiments(results_root; limit=15)

    if isempty(experiments)
        println("$(TUI_YELLOW)No experiments found in: $results_root$(TUI_RESET)")
        return nothing
    end

    # Build options with age info
    options = map(experiments) do exp
        name = basename(exp)
        age = time() - mtime(exp)
        age_str = format_age(age)
        "$name ($age_str ago)"
    end

    menu = RadioMenu(options, pagesize=min(12, length(options)))
    choice = request("Select experiment:", menu)

    choice == -1 && return nothing
    return experiments[choice]
end

function _tui_select_comparison_experiment(results_root::String)::Union{String, Nothing}
    comparison_dirs = find_comparison_experiments(results_root; limit=10)

    if isempty(comparison_dirs)
        println("$(TUI_YELLOW)No comparison experiments found in: $results_root$(TUI_RESET)")
        return nothing
    end

    options = map(comparison_dirs) do dir
        name = basename(dir)
        age = time() - mtime(dir)
        age_str = format_age(age)
        "$name ($age_str ago)"
    end

    menu = RadioMenu(options, pagesize=min(10, length(options)))
    choice = request("Select comparison experiment:", menu)

    choice == -1 && return nothing
    return comparison_dirs[choice]
end

# ============================================================================
# Analysis Execution
# ============================================================================

function _tui_run_analysis(analysis::Symbol, results_root::String)
    println()

    if analysis == :sweep
        return _tui_run_sweep(results_root)
    elseif analysis == :quality
        return _tui_run_quality(results_root)
    elseif analysis == :convergence
        return _tui_run_convergence(results_root)
    elseif analysis == :compare
        return _tui_run_comparison(results_root)
    elseif analysis == :coverage
        return _tui_run_coverage(results_root)
    elseif analysis == :pending
        return _tui_run_pending(results_root)
    else
        error("Unknown analysis type: $analysis")
    end
end

function _tui_run_sweep(results_root::String)
    # Select GN
    gn = _tui_select_gn(results_root)
    gn === nothing && return nothing

    # Select degree range
    deg_range = _tui_select_degree_range(results_root; gn=gn)
    deg_range === nothing && return nothing
    degree_min, degree_max = deg_range

    # Select domain filter
    domain_max = _tui_select_domain_filter(results_root; gn=gn)
    domain_max === nothing && return nothing

    # Show selection summary
    println()
    println("$(TUI_DIM)────────────────────────────────────$(TUI_RESET)")
    deg_str = degree_min == degree_max ? "$degree_min" : "$degree_min-$degree_max"
    println("$(TUI_GREEN)✓$(TUI_RESET) GN=$(TUI_BOLD)$gn$(TUI_RESET), degree=$(TUI_BOLD)$deg_str$(TUI_RESET), domain≤$(TUI_BOLD)$domain_max$(TUI_RESET)")
    println("$(TUI_DIM)────────────────────────────────────$(TUI_RESET)")
    println()
    println("$(TUI_CYAN)▶ Running sweep analysis...$(TUI_RESET)")
    println()

    # Use the filter interface
    filter = ExperimentFilter(
        gn = fixed(gn),
        degree = sweep(degree_min, degree_max),
        domain = SweepRange(0.0, domain_max),
        seed = nothing
    )

    return analyze_sweep(results_root, filter)
end

function _tui_run_quality(results_root::String)
    exp_dir = _tui_select_experiment(results_root)
    exp_dir === nothing && return nothing

    # Show selection summary
    println()
    println("$(TUI_DIM)────────────────────────────────────$(TUI_RESET)")
    println("$(TUI_GREEN)✓$(TUI_RESET) Experiment: $(TUI_BOLD)$(basename(exp_dir))$(TUI_RESET)")
    println("$(TUI_DIM)────────────────────────────────────$(TUI_RESET)")
    println()
    println("$(TUI_CYAN)▶ Running quality analysis...$(TUI_RESET)")

    analyze_quality(exp_dir)
    return nothing
end

function _tui_run_convergence(results_root::String)
    # Select GN
    gn = _tui_select_gn(results_root)
    gn === nothing && return nothing

    # Select degree range
    deg_range = _tui_select_degree_range(results_root; gn=gn)
    deg_range === nothing && return nothing
    degree_min, degree_max = deg_range

    # Ask about CSV export
    export_csv = _tui_select_export_csv()

    # Show selection summary
    println()
    println("$(TUI_DIM)────────────────────────────────────$(TUI_RESET)")
    deg_str = degree_min == degree_max ? "$degree_min" : "$degree_min-$degree_max"
    csv_str = export_csv ? ", export CSV" : ""
    println("$(TUI_GREEN)✓$(TUI_RESET) GN=$(TUI_BOLD)$gn$(TUI_RESET), degree=$(TUI_BOLD)$deg_str$(TUI_RESET)$csv_str")
    println("$(TUI_DIM)────────────────────────────────────$(TUI_RESET)")
    println()
    println("$(TUI_CYAN)▶ Running convergence analysis...$(TUI_RESET)")

    return analyze_convergence(results_root; gn=gn, degree_min=degree_min,
                              degree_max=degree_max, export_csv=export_csv)
end

function _tui_run_comparison(results_root::String)
    comp_dir = _tui_select_comparison_experiment(results_root)
    comp_dir === nothing && return nothing

    # Show selection summary
    println()
    println("$(TUI_DIM)────────────────────────────────────$(TUI_RESET)")
    println("$(TUI_GREEN)✓$(TUI_RESET) Comparison: $(TUI_BOLD)$(basename(comp_dir))$(TUI_RESET)")
    println("$(TUI_DIM)────────────────────────────────────$(TUI_RESET)")
    println()
    println("$(TUI_CYAN)▶ Running comparison analysis...$(TUI_RESET)")

    data = load_comparison_data(comp_dir)
    analyze_comparison(data)
    return nothing
end

function _tui_select_export_csv()::Bool
    options = ["No", "Yes - Export CSV for plotting"]
    menu = RadioMenu(options, pagesize=2)
    choice = request("Export CSV for plotting?", menu)

    choice == -1 && return false
    return choice == 2
end

function _tui_run_pending(results_root::String)
    println("$(TUI_CYAN)▶ Loading pipeline registry...$(TUI_RESET)")

    # Import Pipeline module
    Pipeline = Main.GlobtimPostProcessing.Pipeline

    # Load registry
    registry = Pipeline.load_pipeline_registry(results_root=results_root)

    # Scan for new experiments
    new_count = Pipeline.scan_for_experiments!(registry)
    if new_count > 0
        println("$(TUI_GREEN)Found $new_count new experiments$(TUI_RESET)")
    end

    # Get pending experiments
    pending = Pipeline.get_pending_experiments(registry)

    if isempty(pending)
        println()
        println("$(TUI_DIM)No pending experiments to analyze.$(TUI_RESET)")
        Pipeline.print_pipeline_status(registry)
        return nothing
    end

    # Show pending experiments
    println()
    println("$(TUI_BOLD)Pending experiments: $(length(pending))$(TUI_RESET)")
    println("$(TUI_DIM)────────────────────────────────────$(TUI_RESET)")
    for (i, entry) in enumerate(pending[1:min(10, length(pending))])
        completed_dt = something(entry.completed_at, entry.discovered_at)
        age = time() - Dates.datetime2unix(completed_dt)
        age_str = format_age(age)
        println("  $i. $(entry.name) ($age_str ago)")
    end
    if length(pending) > 10
        println("  ... and $(length(pending) - 10) more")
    end
    println("$(TUI_DIM)────────────────────────────────────$(TUI_RESET)")

    # Ask what to do
    options = ["Analyze all pending", "Analyze first 5", "Show pipeline status", "Cancel"]
    menu = RadioMenu(options, pagesize=4)
    choice = request("Select action:", menu)

    choice == -1 && return nothing

    if choice == 1
        # Analyze all
        println()
        Pipeline.analyze_pending!(registry; verbose=true)
        Pipeline.save_pipeline_registry(registry)
    elseif choice == 2
        # Analyze first 5
        println()
        Pipeline.analyze_pending!(registry; verbose=true, limit=5)
        Pipeline.save_pipeline_registry(registry)
    elseif choice == 3
        # Show status
        Pipeline.print_pipeline_status(registry)
    else
        println("$(TUI_YELLOW)Cancelled.$(TUI_RESET)")
    end

    return nothing
end

# ============================================================================
# Coverage Analysis
# ============================================================================

function _tui_run_coverage(results_root::String)
    # Step 1: Multi-select GN values
    gn_values = _tui_multi_select_gn(results_root)
    isempty(gn_values) && return nothing

    # Step 2: Multi-select domain values
    domain_values = _tui_multi_select_domains(results_root)
    isempty(domain_values) && return nothing

    # Step 3: Select degree range
    deg_range = _tui_select_degree_range(results_root)
    deg_range === nothing && return nothing
    degree_min, degree_max = deg_range

    # Step 4: Select seed range
    seeds = _tui_select_seed_range()
    isempty(seeds) && return nothing

    # Show selection summary
    println()
    println("$(TUI_DIM)────────────────────────────────────$(TUI_RESET)")
    deg_str = degree_min == degree_max ? "$degree_min" : "$degree_min-$degree_max"
    seed_str = length(seeds) == 1 ? "$(seeds[1])" : "$(first(seeds)):$(last(seeds))"
    println("$(TUI_GREEN)✓$(TUI_RESET) GN=$(TUI_BOLD)$gn_values$(TUI_RESET), domains=$(TUI_BOLD)$domain_values$(TUI_RESET)")
    println("  degrees=$(TUI_BOLD)$deg_str$(TUI_RESET), seeds=$(TUI_BOLD)$seed_str$(TUI_RESET)")
    println("$(TUI_DIM)────────────────────────────────────$(TUI_RESET)")
    println()
    println("$(TUI_CYAN)▶ Running coverage analysis...$(TUI_RESET)")

    # Build degree sequence (even degrees only for LV4D)
    expected_degrees = degree_min:2:degree_max

    # Run coverage analysis
    report = analyze_coverage(results_root;
        expected_gn = gn_values,
        expected_domains = domain_values,
        expected_degrees = expected_degrees,
        expected_seeds = seeds
    )

    # Print report
    print_coverage_report(report)

    # If there are missing experiments, ask about gap-filling
    if !isempty(report.missing_keys)
        println()
        generate = _tui_ask_generate_gaps()

        if generate
            output_dir = _tui_select_output_directory()
            if output_dir !== nothing
                configs = generate_gap_filling_configs(report; output_dir=output_dir)
                println()
                println("$(TUI_GREEN)Generated $(length(configs)) config files in $(TUI_BOLD)$output_dir$(TUI_RESET)")
            end
        end
    end

    return report
end

"""
    _tui_multi_select_gn(results_root::String) -> Vector{Int}

Multi-select GN values from detected values using MultiSelectMenu.
"""
function _tui_multi_select_gn(results_root::String)::Vector{Int}
    gn_values = _tui_detect_gn_values(results_root)

    if isempty(gn_values)
        println("$(TUI_YELLOW)No experiments found with valid GN values.$(TUI_RESET)")
        return Int[]
    end

    if length(gn_values) == 1
        println("$(TUI_DIM)Using GN=$(gn_values[1]) (only available value)$(TUI_RESET)")
        return gn_values
    end

    options = string.(gn_values)
    menu = MultiSelectMenu(options; pagesize=min(8, length(options)))
    selected = request("Select GN values (space to toggle, enter to confirm):", menu)

    if isempty(selected)
        println("$(TUI_YELLOW)No GN values selected.$(TUI_RESET)")
        return Int[]
    end

    return [gn_values[i] for i in sort(collect(selected))]
end

"""
    _tui_multi_select_domains(results_root::String) -> Vector{Float64}

Multi-select domain values from detected values using MultiSelectMenu.
"""
function _tui_multi_select_domains(results_root::String)::Vector{Float64}
    domains = _tui_detect_domain_values(results_root)

    if isempty(domains)
        println("$(TUI_YELLOW)No experiments found with valid domain values.$(TUI_RESET)")
        return Float64[]
    end

    if length(domains) == 1
        println("$(TUI_DIM)Using domain=$(domains[1]) (only available value)$(TUI_RESET)")
        return domains
    end

    # Format domain values for display
    options = [@sprintf("%.4f", d) for d in domains]
    menu = MultiSelectMenu(options; pagesize=min(10, length(options)))
    selected = request("Select domain values (space to toggle, enter to confirm):", menu)

    if isempty(selected)
        println("$(TUI_YELLOW)No domain values selected.$(TUI_RESET)")
        return Float64[]
    end

    return [domains[i] for i in sort(collect(selected))]
end

"""
    _tui_select_seed_range() -> Vector{Int}

Select seed range for coverage analysis.
"""
function _tui_select_seed_range()::Vector{Int}
    options = [
        "1:5 (5 seeds)",
        "1:3 (3 seeds)",
        "1 only (single seed)",
        "Custom range"
    ]
    menu = RadioMenu(options, pagesize=4)
    choice = request("Select seed range:", menu)

    choice == -1 && return Int[]

    if choice == 1
        return collect(1:5)
    elseif choice == 2
        return collect(1:3)
    elseif choice == 3
        return [1]
    else
        # Custom range input
        print("Enter seed range (e.g., 1:10): ")
        input = readline()
        try
            parts = split(strip(input), ":")
            if length(parts) == 2
                start = parse(Int, parts[1])
                stop = parse(Int, parts[2])
                return collect(start:stop)
            elseif length(parts) == 1
                return [parse(Int, parts[1])]
            else
                println("$(TUI_YELLOW)Invalid format. Using seed=1.$(TUI_RESET)")
                return [1]
            end
        catch
            println("$(TUI_YELLOW)Could not parse input. Using seed=1.$(TUI_RESET)")
            return [1]
        end
    end
end

"""
    _tui_ask_generate_gaps() -> Bool

Ask if user wants to generate gap-filling configs.
"""
function _tui_ask_generate_gaps()::Bool
    options = ["Yes - Generate gap-filling configs", "No"]
    menu = RadioMenu(options, pagesize=2)
    choice = request("Generate gap-filling configs?", menu)

    return choice == 1
end

"""
    _tui_select_output_directory() -> Union{String, Nothing}

Select or enter output directory for gap-filling configs.
"""
function _tui_select_output_directory()::Union{String, Nothing}
    default_dir = "experiments/fill_gaps/"

    options = [
        "experiments/fill_gaps/ (default)",
        "experiments/generated/",
        "Custom directory"
    ]
    menu = RadioMenu(options, pagesize=3)
    choice = request("Select output directory:", menu)

    choice == -1 && return nothing

    if choice == 1
        return default_dir
    elseif choice == 2
        return "experiments/generated/"
    else
        print("Enter output directory: ")
        input = strip(readline())
        return isempty(input) ? default_dir : input
    end
end

# ============================================================================
# Convenience Aliases
# ============================================================================

"""
    analyze_lv4d(; results_root::String=find_results_root())

Alias for `lv4d()` - Interactive LV4D analysis.
"""
const analyze_lv4d = lv4d
