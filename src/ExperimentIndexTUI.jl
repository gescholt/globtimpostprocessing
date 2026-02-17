"""
    ExperimentIndexTUI.jl - Interactive TUI for experiment parameter index

Provides arrow-key navigation for querying experiment parameters and coverage.
Uses the consolidated PipelineRegistry for persistence and indexed lookups.

# Usage
```julia
using GlobtimPostProcessing

# Launch interactive mode
experiments()
```
"""

using REPL.TerminalMenus
using Printf
using Dates

# Import from Pipeline module
using ..Pipeline: PipelineRegistry, load_pipeline_registry, save_pipeline_registry
using ..Pipeline: ExperimentEntry, ExperimentParams, ExperimentStatus
using ..Pipeline: get_parameter_coverage, ParameterCoverage, print_coverage_matrix
using ..Pipeline: get_experiments_by_params, has_experiment_with_params, get_experiments_for_params
using ..Pipeline: get_unique_params, get_missing_params, print_query_results
using ..Pipeline: scan_for_experiments!, default_results_root

# ANSI color codes for TUI styling
const IDX_CYAN = "\e[36m"
const IDX_YELLOW = "\e[33m"
const IDX_GREEN = "\e[32m"
const IDX_RED = "\e[31m"
const IDX_DIM = "\e[2m"
const IDX_BOLD = "\e[1m"
const IDX_RESET = "\e[0m"

# ============================================================================
# Main Entry Point
# ============================================================================

"""
    experiments(; results_root::String=default_results_root()) -> Nothing

Interactive experiment parameter index with arrow-key menu navigation.

Launches an interactive TUI where you can:
1. View parameter coverage matrix
2. Check if specific parameters exist
3. Find experiments by criteria
4. List all unique parameter combinations
5. Identify missing experiments

# Example
```julia
using GlobtimPostProcessing

# Launch interactive mode
experiments()
```
"""
function experiments(; results_root::Union{String, Nothing}=nothing)
    # Find results root
    actual_root = if results_root !== nothing
        results_root
    else
        _idx_find_results_root()
    end

    if actual_root === nothing
        println("$(IDX_RED)Could not find results directory.$(IDX_RESET)")
        println("Set GLOBTIM_RESULTS_ROOT or pass results_root argument.")
        return nothing
    end

    println()
    println("$(IDX_BOLD)$(IDX_CYAN)EXPERIMENT PARAMETER INDEX$(IDX_RESET)")
    println("$(IDX_DIM)──────────────────────────$(IDX_RESET)")
    println("$(IDX_DIM)Use ↑/↓ to navigate, Enter to select$(IDX_RESET)")
    println()

    # Load registry and scan for new experiments
    println("$(IDX_DIM)Loading registry and scanning for experiments...$(IDX_RESET)")
    registry = load_pipeline_registry(results_root=actual_root)
    scan_for_experiments!(registry; pattern="lotka_volterra_4d")
    save_pipeline_registry(registry)

    num_experiments = length(registry.experiments)
    num_unique = length(registry.by_hash)
    println("$(IDX_GREEN)✓$(IDX_RESET) Found $(IDX_BOLD)$(num_experiments)$(IDX_RESET) experiments, $(IDX_BOLD)$(num_unique)$(IDX_RESET) unique combinations")
    println()

    # Main menu loop
    while true
        action = _idx_select_action()
        action === nothing && break

        _idx_run_action(action, registry)
        println()
    end

    println("$(IDX_DIM)Exited experiment index.$(IDX_RESET)")
    return nothing
end

# ============================================================================
# Action Selection
# ============================================================================

const IDX_ACTIONS = [
    :coverage => "Show coverage matrix (GN × domain)",
    :has => "Check if parameters exist",
    :find => "Find experiments by criteria",
    :list => "List all parameter combinations",
    :missing => "Show missing experiments",
    :details => "Show experiment details",
]

function _idx_select_action()::Union{Symbol, Nothing}
    options = ["$(String(k)) - $v" for (k, v) in IDX_ACTIONS]
    push!(options, "Exit")

    menu = RadioMenu(options, pagesize=length(options))
    choice = request("Select action:", menu)

    choice == -1 && return nothing
    choice == length(options) && return nothing  # Exit selected

    return IDX_ACTIONS[choice][1]
end

# ============================================================================
# Action Implementations
# ============================================================================

function _idx_run_action(action::Symbol, registry::PipelineRegistry)
    println()

    if action == :coverage
        _idx_show_coverage(registry)
    elseif action == :has
        _idx_check_has(registry)
    elseif action == :find
        _idx_find_experiments(registry)
    elseif action == :list
        _idx_list_params(registry)
    elseif action == :missing
        _idx_show_missing(registry)
    elseif action == :details
        _idx_show_details(registry)
    end
end

# ============================================================================
# Coverage Matrix
# ============================================================================

function _idx_show_coverage(registry::PipelineRegistry)
    println("$(IDX_CYAN)▶ Parameter Coverage$(IDX_RESET)")
    println()

    coverage = get_parameter_coverage(registry)
    print_coverage_matrix(coverage)
end

# ============================================================================
# Check if Parameters Exist
# ============================================================================

function _idx_check_has(registry::PipelineRegistry)
    println("$(IDX_CYAN)▶ Check Parameter Existence$(IDX_RESET)")
    println()

    # Select GN
    gn = _idx_select_gn(registry)
    gn === nothing && return

    # Select domain
    domain = _idx_select_domain(registry)
    domain === nothing && return

    # Select degree range
    deg_range = _idx_select_degree_range(registry)
    deg_range === nothing && return
    deg_min, deg_max = deg_range

    # Check
    exists = has_experiment_with_params(registry; GN=gn, domain=domain, deg_min=deg_min, deg_max=deg_max)

    println()
    println("$(IDX_DIM)────────────────────────────────────$(IDX_RESET)")
    domain_str = domain >= 0.01 ? @sprintf("%.3f", domain) : @sprintf("%.1e", domain)
    println("Query: GN=$(IDX_BOLD)$gn$(IDX_RESET), domain=$(IDX_BOLD)$domain_str$(IDX_RESET), deg=$(IDX_BOLD)$deg_min-$deg_max$(IDX_RESET)")
    println()

    if exists
        experiments = get_experiments_for_params(registry; GN=gn, domain=domain, deg_min=deg_min, deg_max=deg_max)
        println("$(IDX_GREEN)✓ YES$(IDX_RESET) - Found $(length(experiments)) experiment(s):")
        for exp in experiments
            seed_str = if exp.params !== nothing && exp.params.seed !== nothing
                " (seed=$(exp.params.seed))"
            else
                ""
            end
            println("  • $(exp.name)$seed_str")
        end
    else
        println("$(IDX_RED)✗ NO$(IDX_RESET) - No experiments found with these parameters")
    end
end

# ============================================================================
# Find Experiments
# ============================================================================

function _idx_find_experiments(registry::PipelineRegistry)
    println("$(IDX_CYAN)▶ Find Experiments$(IDX_RESET)")
    println()

    # Build filter criteria
    criteria = Dict{Symbol, Any}()

    # GN filter (optional)
    if _idx_ask_filter("Filter by GN?")
        gn = _idx_select_gn(registry)
        gn !== nothing && (criteria[:GN] = gn)
    end

    # Domain filter (optional)
    if _idx_ask_filter("Filter by domain range?")
        domain_range = _idx_select_domain_range(registry)
        domain_range !== nothing && (criteria[:domain_range] = domain_range)
    end

    # Degree filter (optional)
    if _idx_ask_filter("Filter by degree?")
        deg_range = _idx_select_degree_range(registry)
        if deg_range !== nothing
            criteria[:deg_min] = deg_range[1]
            criteria[:deg_max] = deg_range[2]
        end
    end

    # Query
    results = get_experiments_by_params(registry; criteria...)

    println()
    println("$(IDX_DIM)────────────────────────────────────$(IDX_RESET)")
    print_query_results(results; limit=15)
end

# ============================================================================
# List Parameters
# ============================================================================

function _idx_list_params(registry::PipelineRegistry)
    println("$(IDX_CYAN)▶ Unique Parameter Combinations$(IDX_RESET)")
    println()

    params = get_unique_params(registry)

    println("Found $(IDX_BOLD)$(length(params))$(IDX_RESET) unique combinations:")
    println("$(IDX_DIM)────────────────────────────────────$(IDX_RESET)")

    for p in params
        domain_str = p.domain >= 0.01 ? @sprintf("%.3f", p.domain) : @sprintf("%.1e", p.domain)
        count_str = p.count == 1 ? "1 exp" : "$(p.count) exps"
        println("  GN=$(IDX_BOLD)$(p.GN)$(IDX_RESET)  deg=$(p.deg_min)-$(p.deg_max)  domain=$(domain_str)  ($count_str)")
    end
end

# ============================================================================
# Show Missing
# ============================================================================

function _idx_show_missing(registry::PipelineRegistry)
    println("$(IDX_CYAN)▶ Missing Parameter Combinations$(IDX_RESET)")
    println()

    # Select target GN values
    gn_values = _idx_multi_select_gn(registry)
    isempty(gn_values) && return

    # Select target domain values
    domain_values = _idx_multi_select_domains(registry)
    isempty(domain_values) && return

    # Select degree range
    deg_range = _idx_select_target_degree_range()
    deg_range === nothing && return

    # Generate all degree combinations
    target_degrees = [(deg_range[1], deg_range[2])]  # Full range
    for d in deg_range[1]:deg_range[2]
        push!(target_degrees, (d, d))  # Single degrees
    end

    # Find missing
    missing = get_missing_params(registry, gn_values, domain_values, target_degrees)

    println()
    println("$(IDX_DIM)────────────────────────────────────$(IDX_RESET)")
    println("Target GNs: $(join(gn_values, ", "))")
    println("Target domains: $(join([@sprintf("%.3g", d) for d in domain_values], ", "))")
    println("Target degrees: $(deg_range[1])-$(deg_range[2])")
    println()

    if isempty(missing)
        println("$(IDX_GREEN)✓ All parameter combinations are covered!$(IDX_RESET)")
    else
        println("$(IDX_YELLOW)Missing $(length(missing)) combinations:$(IDX_RESET)")
        println()

        # Group by GN
        by_gn = Dict{Int, Vector}()
        for m in missing
            if !haskey(by_gn, m.GN)
                by_gn[m.GN] = []
            end
            push!(by_gn[m.GN], m)
        end

        for gn in sort(collect(keys(by_gn)))
            println("  GN=$gn:")
            for m in by_gn[gn][1:min(10, length(by_gn[gn]))]
                domain_str = m.domain >= 0.01 ? @sprintf("%.3f", m.domain) : @sprintf("%.1e", m.domain)
                println("    • deg=$(m.deg_min)-$(m.deg_max), domain=$domain_str")
            end
            if length(by_gn[gn]) > 10
                println("    ... and $(length(by_gn[gn]) - 10) more")
            end
        end
    end
end

# ============================================================================
# Show Details
# ============================================================================

function _idx_show_details(registry::PipelineRegistry)
    println("$(IDX_CYAN)▶ Experiment Details$(IDX_RESET)")
    println()

    # Select an experiment
    if isempty(registry.experiments)
        println("$(IDX_YELLOW)No experiments found.$(IDX_RESET)")
        return
    end

    # Sort by timestamp (newest first)
    entries = collect(values(registry.experiments))
    sorted = sort(entries, by=e -> begin
        if e.params !== nothing && e.params.timestamp !== nothing
            e.params.timestamp
        else
            DateTime(0)
        end
    end, rev=true)
    recent = sorted[1:min(15, length(sorted))]

    options = map(recent) do entry
        age_str = if entry.params !== nothing && entry.params.timestamp !== nothing
            age = now() - entry.params.timestamp
            days = Dates.value(age) ÷ (1000 * 60 * 60 * 24)
            days == 0 ? "today" : "$days days ago"
        else
            "unknown"
        end
        "$(entry.name) ($age_str)"
    end

    menu = RadioMenu(options, pagesize=min(12, length(options)))
    choice = request("Select experiment:", menu)

    choice == -1 && return

    entry = recent[choice]

    println()
    println("$(IDX_DIM)────────────────────────────────────$(IDX_RESET)")
    println("$(IDX_BOLD)$(entry.name)$(IDX_RESET)")
    println("$(IDX_DIM)────────────────────────────────────$(IDX_RESET)")
    println("  Path: $(entry.path)")

    if entry.params !== nothing
        p = entry.params
        println("  GN: $(p.GN)")
        println("  Degree: $(p.deg_min)-$(p.deg_max)")
        domain_str = p.domain >= 0.01 ? @sprintf("%.4f", p.domain) : @sprintf("%.2e", p.domain)
        println("  Domain: $domain_str")
        println("  Seed: $(something(p.seed, "not specified"))")
        println("  Objective: $(p.objective)")
        if p.timestamp !== nothing
            println("  Timestamp: $(Dates.format(p.timestamp, "yyyy-mm-dd HH:MM:SS"))")
        end
    else
        println("  (No parameters extracted)")
    end
end

# ============================================================================
# Menu Helpers
# ============================================================================

function _idx_find_results_root()::Union{String, Nothing}
    # Check environment variable
    if haskey(ENV, "GLOBTIM_RESULTS_ROOT")
        return ENV["GLOBTIM_RESULTS_ROOT"]
    end

    # Search common locations
    candidates = [
        joinpath(pwd(), "globtim_results"),
        joinpath(dirname(pwd()), "globtim_results"),
        joinpath(homedir(), "GlobalOptim", "globtim_results"),
    ]

    for c in candidates
        if isdir(c)
            return c
        end
    end

    return nothing
end

function _idx_ask_filter(prompt::String)::Bool
    options = ["Yes", "No"]
    menu = RadioMenu(options, pagesize=2)
    choice = request(prompt, menu)
    return choice == 1
end

function _idx_select_gn(registry::PipelineRegistry)::Union{Int, Nothing}
    gn_values = sort(collect(keys(registry.by_gn)))

    if isempty(gn_values)
        println("$(IDX_YELLOW)No GN values found.$(IDX_RESET)")
        return nothing
    end

    options = string.(gn_values)
    menu = RadioMenu(options, pagesize=min(8, length(options)))
    choice = request("Select GN:", menu)

    choice == -1 && return nothing
    return gn_values[choice]
end

function _idx_select_domain(registry::PipelineRegistry)::Union{Float64, Nothing}
    domain_values = sort(collect(keys(registry.by_domain)))

    if isempty(domain_values)
        println("$(IDX_YELLOW)No domain values found.$(IDX_RESET)")
        return nothing
    end

    options = [d >= 0.01 ? @sprintf("%.4f", d) : @sprintf("%.2e", d) for d in domain_values]
    menu = RadioMenu(options, pagesize=min(10, length(options)))
    choice = request("Select domain:", menu)

    choice == -1 && return nothing
    return domain_values[choice]
end

function _idx_select_domain_range(registry::PipelineRegistry)::Union{Tuple{Float64, Float64}, Nothing}
    domain_values = sort(collect(keys(registry.by_domain)))

    if isempty(domain_values)
        println("$(IDX_YELLOW)No domain values found.$(IDX_RESET)")
        return nothing
    end

    min_d, max_d = extrema(domain_values)

    # Build options
    options = String[]
    ranges = Tuple{Float64, Float64}[]

    # All domains
    push!(options, "All domains ($(@sprintf("%.4g", min_d)) - $(@sprintf("%.4g", max_d)))")
    push!(ranges, (min_d, max_d))

    # Small domains
    if min_d <= 0.01
        push!(options, "Small domains (≤ 0.01)")
        push!(ranges, (0.0, 0.01))
    end

    # Medium domains
    if min_d <= 0.1 && max_d >= 0.01
        push!(options, "Medium domains (0.01 - 0.1)")
        push!(ranges, (0.01, 0.1))
    end

    # Large domains
    if max_d >= 0.1
        push!(options, "Large domains (≥ 0.1)")
        push!(ranges, (0.1, max_d))
    end

    menu = RadioMenu(options, pagesize=length(options))
    choice = request("Select domain range:", menu)

    choice == -1 && return nothing
    return ranges[choice]
end

function _idx_select_degree_range(registry::PipelineRegistry)::Union{Tuple{Int, Int}, Nothing}
    # Collect all degree values from experiments
    degrees = Set{Int}()
    for (_, entry) in registry.experiments
        if entry.params !== nothing
            push!(degrees, entry.params.deg_min)
            push!(degrees, entry.params.deg_max)
        end
    end

    if isempty(degrees)
        println("$(IDX_YELLOW)No degree values found.$(IDX_RESET)")
        return nothing
    end

    sorted_degs = sort(collect(degrees))
    min_deg, max_deg = extrema(sorted_degs)

    # Build options
    options = String[]
    ranges = Tuple{Int, Int}[]

    # Full range
    push!(options, "$min_deg-$max_deg (all)")
    push!(ranges, (min_deg, max_deg))

    # Common ranges
    for (lo, hi) in [(4, 8), (4, 10), (4, 12), (6, 10), (6, 12), (8, 12)]
        if lo >= min_deg && hi <= max_deg && (lo, hi) != (min_deg, max_deg)
            push!(options, "$lo-$hi")
            push!(ranges, (lo, hi))
        end
    end

    # Single degrees
    for d in sorted_degs
        push!(options, "$d (single)")
        push!(ranges, (d, d))
    end

    menu = RadioMenu(options, pagesize=min(10, length(options)))
    choice = request("Select degree range:", menu)

    choice == -1 && return nothing
    return ranges[choice]
end

function _idx_select_target_degree_range()::Union{Tuple{Int, Int}, Nothing}
    options = [
        "4-12 (standard LV4D range)",
        "4-10",
        "4-8",
        "6-12",
        "8-12",
        "Custom"
    ]

    menu = RadioMenu(options, pagesize=length(options))
    choice = request("Select target degree range:", menu)

    choice == -1 && return nothing

    if choice == 1
        return (4, 12)
    elseif choice == 2
        return (4, 10)
    elseif choice == 3
        return (4, 8)
    elseif choice == 4
        return (6, 12)
    elseif choice == 5
        return (8, 12)
    else
        print("Enter degree range (e.g., 4:12): ")
        input = readline()
        try
            parts = split(strip(input), ":")
            return (parse(Int, parts[1]), parse(Int, parts[2]))
        catch e
            @debug "Could not parse degree range input" input exception=(e, catch_backtrace())
            println("$(IDX_YELLOW)Invalid format. Using 4-12.$(IDX_RESET)")
            return (4, 12)
        end
    end
end

function _idx_multi_select_gn(registry::PipelineRegistry)::Vector{Int}
    gn_values = sort(collect(keys(registry.by_gn)))

    if isempty(gn_values)
        println("$(IDX_YELLOW)No GN values found.$(IDX_RESET)")
        return Int[]
    end

    if length(gn_values) == 1
        println("$(IDX_DIM)Using GN=$(gn_values[1]) (only available)$(IDX_RESET)")
        return gn_values
    end

    options = string.(gn_values)
    menu = MultiSelectMenu(options; pagesize=min(8, length(options)))
    selected = request("Select GN values (space to toggle):", menu)

    if isempty(selected)
        return Int[]
    end

    return [gn_values[i] for i in sort(collect(selected))]
end

function _idx_multi_select_domains(registry::PipelineRegistry)::Vector{Float64}
    domain_values = sort(collect(keys(registry.by_domain)))

    if isempty(domain_values)
        println("$(IDX_YELLOW)No domain values found.$(IDX_RESET)")
        return Float64[]
    end

    if length(domain_values) == 1
        println("$(IDX_DIM)Using domain=$(domain_values[1]) (only available)$(IDX_RESET)")
        return domain_values
    end

    options = [d >= 0.01 ? @sprintf("%.4f", d) : @sprintf("%.2e", d) for d in domain_values]
    menu = MultiSelectMenu(options; pagesize=min(12, length(options)))
    selected = request("Select domain values (space to toggle):", menu)

    if isempty(selected)
        return Float64[]
    end

    return [domain_values[i] for i in sort(collect(selected))]
end

# ============================================================================
# select_experiments() - Returns ExperimentFilter for plotting
# ============================================================================

"""
    select_experiments(; results_root::Union{String, Nothing}=nothing) -> Tuple{ExperimentFilter, String}

Interactive TUI for selecting experiments. Returns an `ExperimentFilter` suitable for
`LV4DAnalysis.query_to_dataframe()`.

Unlike `experiments()` which is display-only, this function returns a filter
for downstream processing (e.g., plotting).

# Returns
Tuple of:
- `LV4DAnalysis.ExperimentFilter`: Filter based on user selection (GN, domain)
- `String`: Path to experiments directory (for use with `query_to_dataframe`)

# Example
```julia
using GlobtimPostProcessing
using GlobtimPostProcessing.LV4DAnalysis

filter, results_path = select_experiments()
df = query_to_dataframe(results_path, filter)
```

See also: [`experiments`](@ref), [`LV4DAnalysis.ExperimentFilter`](@ref)
"""
function select_experiments(; results_root::Union{String, Nothing}=nothing)
    # Find results root
    actual_root = if results_root !== nothing
        results_root
    else
        _idx_find_results_root()
    end

    if actual_root === nothing
        error("Could not find results directory. Set GLOBTIM_RESULTS_ROOT or pass results_root argument.")
    end

    println()
    println("$(IDX_BOLD)$(IDX_CYAN)SELECT EXPERIMENTS$(IDX_RESET)")
    println("$(IDX_DIM)──────────────────$(IDX_RESET)")
    println("$(IDX_DIM)Use ↑/↓ to navigate, Enter to select$(IDX_RESET)")
    println()

    # Load registry and scan for new experiments
    println("$(IDX_DIM)Loading registry and scanning for experiments...$(IDX_RESET)")
    registry = load_pipeline_registry(results_root=actual_root)
    scan_for_experiments!(registry; pattern="lotka_volterra_4d")
    save_pipeline_registry(registry)

    println("$(IDX_GREEN)✓$(IDX_RESET) Found $(IDX_BOLD)$(length(registry.experiments))$(IDX_RESET) experiments")
    println()

    # Show coverage matrix
    _idx_show_coverage(registry)
    println()

    # Select GN
    println("$(IDX_CYAN)▶ Select parameters to filter$(IDX_RESET)")
    gn = _idx_select_gn_or_all(registry)

    # Select domain
    domain = _idx_select_domain_or_all(registry)

    # Build ExperimentFilter using LV4DAnalysis types (accessed at runtime)
    # Import here to avoid load-order dependency issues
    LV4D = parentmodule(@__MODULE__).LV4DAnalysis
    filter = LV4D.ExperimentFilter(
        gn = gn === nothing ? nothing : LV4D.fixed(gn),
        domain = domain === nothing ? nothing : LV4D.fixed(domain)
    )

    # Confirm selection
    println()
    println("$(IDX_DIM)────────────────────────────────────$(IDX_RESET)")
    filter_str = _format_selection(gn, domain)
    println("$(IDX_GREEN)✓$(IDX_RESET) Selected: $filter_str")

    # Compute the correct experiments path (handle both globtim_results and globtim_results/lotka_volterra_4d)
    experiments_path = if isdir(joinpath(actual_root, "lotka_volterra_4d"))
        joinpath(actual_root, "lotka_volterra_4d")
    else
        actual_root
    end

    return filter, experiments_path
end

"""
Select GN value with "All" option.
"""
function _idx_select_gn_or_all(registry::PipelineRegistry)::Union{Int, Nothing}
    gn_values = sort(collect(keys(registry.by_gn)))

    if isempty(gn_values)
        println("$(IDX_YELLOW)No GN values found.$(IDX_RESET)")
        return nothing
    end

    options = ["[All GN values]"; string.(gn_values)]
    menu = RadioMenu(options, pagesize=min(10, length(options)))
    choice = request("Select GN:", menu)

    choice == -1 && error("Selection cancelled")
    choice == 1 && return nothing  # "All" selected
    return gn_values[choice - 1]
end

"""
Select domain value with "All" option.
"""
function _idx_select_domain_or_all(registry::PipelineRegistry)::Union{Float64, Nothing}
    domain_values = sort(collect(keys(registry.by_domain)))

    if isempty(domain_values)
        println("$(IDX_YELLOW)No domain values found.$(IDX_RESET)")
        return nothing
    end

    options = ["[All domains]"; [d >= 0.01 ? @sprintf("%.4f", d) : @sprintf("%.2e", d) for d in domain_values]]
    menu = RadioMenu(options, pagesize=min(12, length(options)))
    choice = request("Select domain:", menu)

    choice == -1 && error("Selection cancelled")
    choice == 1 && return nothing  # "All" selected
    return domain_values[choice - 1]
end

"""
Format selection for display.
"""
function _format_selection(gn::Union{Int, Nothing}, domain::Union{Float64, Nothing})::String
    parts = String[]
    if gn === nothing
        push!(parts, "GN=all")
    else
        push!(parts, "GN=$gn")
    end
    if domain === nothing
        push!(parts, "domain=all")
    else
        domain_str = domain >= 0.01 ? @sprintf("%.4f", domain) : @sprintf("%.2e", domain)
        push!(parts, "domain=$domain_str")
    end
    return join(parts, ", ")
end
