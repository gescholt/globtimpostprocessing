"""
Shared menu utilities for unified TUI.

Provides reusable menu components and styling for the interactive interface.
"""

# ============================================================================
# ANSI Terminal Colors
# ============================================================================

const UNIFIED_TUI_CYAN = "\e[36m"
const UNIFIED_TUI_YELLOW = "\e[33m"
const UNIFIED_TUI_GREEN = "\e[32m"
const UNIFIED_TUI_RED = "\e[31m"
const UNIFIED_TUI_DIM = "\e[2m"
const UNIFIED_TUI_BOLD = "\e[1m"
const UNIFIED_TUI_RESET = "\e[0m"

# ============================================================================
# Header and Formatting
# ============================================================================

"""
    tui_header(title::String)

Print a styled TUI header.
"""
function tui_header(title::String)
    println()
    println("$(UNIFIED_TUI_BOLD)$(UNIFIED_TUI_CYAN)$title$(UNIFIED_TUI_RESET)")
    println(UNIFIED_TUI_DIM * ("─"^length(title)) * UNIFIED_TUI_RESET)
    println("$(UNIFIED_TUI_DIM)Use ↑/↓ to navigate, Enter to select$(UNIFIED_TUI_RESET)")
    println()
end

"""
    tui_section(title::String)

Print a section divider with title.
"""
function tui_section(title::String)
    println()
    println("$(UNIFIED_TUI_DIM)── $title ──$(UNIFIED_TUI_RESET)")
end

"""
    tui_success(msg::String)

Print a success message.
"""
function tui_success(msg::String)
    println("$(UNIFIED_TUI_GREEN)✓$(UNIFIED_TUI_RESET) $msg")
end

"""
    tui_warning(msg::String)

Print a warning message.
"""
function tui_warning(msg::String)
    println("$(UNIFIED_TUI_YELLOW)⚠ $msg$(UNIFIED_TUI_RESET)")
end

"""
    tui_error(msg::String)

Print an error message.
"""
function tui_error(msg::String)
    println("$(UNIFIED_TUI_RED)✗ $msg$(UNIFIED_TUI_RESET)")
end

"""
    tui_info(msg::String)

Print an info message.
"""
function tui_info(msg::String)
    println("$(UNIFIED_TUI_DIM)ℹ $msg$(UNIFIED_TUI_RESET)")
end

"""
    tui_running(msg::String)

Print a "running" status message.
"""
function tui_running(msg::String)
    println()
    println("$(UNIFIED_TUI_CYAN)▶ $msg$(UNIFIED_TUI_RESET)")
    println()
end

"""
    tui_divider()

Print a simple divider line.
"""
function tui_divider()
    println("$(UNIFIED_TUI_DIM)────────────────────────────────────$(UNIFIED_TUI_RESET)")
end

# ============================================================================
# Results Root Discovery
# ============================================================================

"""
    find_unified_results_root() -> String

Find the results directory using environment variable or default locations.

Checks in order:
1. GLOBTIM_RESULTS_ROOT environment variable
2. Relative paths from common locations
"""
function find_unified_results_root()::String
    # Check environment variable first
    results_root = get(ENV, "GLOBTIM_RESULTS_ROOT", nothing)
    if results_root !== nothing && isdir(results_root)
        return results_root
    end

    # Try common relative paths
    possible_roots = [
        joinpath(dirname(dirname(dirname(@__DIR__))), "globtim_results"),
        joinpath(dirname(dirname(@__DIR__)), "globtim_results"),
        expanduser("~/GlobalOptim/globtim_results")
    ]

    for root in possible_roots
        if isdir(root)
            return root
        end
    end

    error("Could not find results directory. Set GLOBTIM_RESULTS_ROOT environment variable.")
end

# ============================================================================
# Experiment Type Menu
# ============================================================================

"""
    select_experiment_type() -> Union{ExperimentType, Nothing}

Show menu to select experiment type.

Returns the selected ExperimentType singleton or nothing if cancelled.
"""
function select_experiment_type()::Union{ExperimentType, Nothing}
    # Build options from SUPPORTED_TYPES
    options = String[]
    for (typ, desc) in SUPPORTED_TYPES
        push!(options, "$(type_name(typ)) - $desc")
    end
    push!(options, "Auto-detect from path")

    menu = RadioMenu(options, pagesize=min(8, length(options)))
    choice = request("Select experiment type:", menu)

    choice == -1 && return nothing

    # Handle auto-detect option
    if choice == length(options)
        return nothing  # Signal auto-detect
    end

    return SUPPORTED_TYPES[choice][1]
end

# ============================================================================
# Results Source Menu
# ============================================================================

"""
    ResultsSource

Enum-like struct for results source selection.
"""
struct ResultsSource
    type::Symbol  # :recent, :path, :registry
    value::String
end

"""
    select_results_source(results_root::String) -> Union{ResultsSource, Nothing}

Show menu to select results source.
"""
function select_results_source(results_root::String)::Union{ResultsSource, Nothing}
    options = [
        "Browse recent experiments",
        "Enter path manually",
        "Pipeline registry (pending)"
    ]

    menu = RadioMenu(options, pagesize=3)
    choice = request("Select results source:", menu)

    choice == -1 && return nothing

    if choice == 1
        return ResultsSource(:recent, results_root)
    elseif choice == 2
        print("Enter experiment path: ")
        path = strip(readline())
        isempty(path) && return nothing
        return ResultsSource(:path, path)
    else
        return ResultsSource(:registry, results_root)
    end
end

# ============================================================================
# Recent Experiments Menu
# ============================================================================

"""
    select_recent_experiment(results_root::String; type_filter::Union{ExperimentType, Nothing}=nothing, limit::Int=15) -> Union{String, Nothing}

Show menu to select from recent experiments.

# Arguments
- `results_root`: Root directory to search
- `type_filter`: Optional type filter (show only experiments of this type)
- `limit`: Maximum number of experiments to show

# Returns
Path to selected experiment or nothing if cancelled.
"""
function select_recent_experiment(results_root::String;
                                 type_filter::Union{ExperimentType, Nothing}=nothing,
                                 limit::Int=15)::Union{String, Nothing}
    # Build list of experiments
    experiments = String[]

    # Walk through results_root looking for experiment directories
    for entry in readdir(results_root, join=true)
        if isdir(entry) && is_single_experiment(entry)
            # Apply type filter if specified
            if type_filter !== nothing
                detected = detect_experiment_type(entry)
                typeof(detected) != typeof(type_filter) && continue
            end
            push!(experiments, entry)
        end

        # Also check subdirectories (e.g., lotka_volterra_4d/)
        if isdir(entry)
            for subentry in readdir(entry, join=true)
                if isdir(subentry) && is_single_experiment(subentry)
                    if type_filter !== nothing
                        detected = detect_experiment_type(subentry)
                        typeof(detected) != typeof(type_filter) && continue
                    end
                    push!(experiments, subentry)
                end
            end
        end
    end

    if isempty(experiments)
        tui_warning("No experiments found in: $results_root")
        return nothing
    end

    # Sort by modification time (most recent first)
    sort!(experiments, by=mtime, rev=true)
    experiments = experiments[1:min(limit, length(experiments))]

    # Build options with age info
    options = map(experiments) do exp
        name = basename(exp)
        age = time() - mtime(exp)
        age_str = _format_age(age)
        typ = detect_experiment_type(exp)
        type_str = type_name(typ)
        "[$type_str] $name ($age_str ago)"
    end

    menu = RadioMenu(options, pagesize=min(12, length(options)))
    choice = request("Select experiment:", menu)

    choice == -1 && return nothing
    return experiments[choice]
end

"""
    _format_age(seconds::Real) -> String

Format a time duration in human-readable form.
"""
function _format_age(seconds::Real)::String
    if seconds < 60
        return "$(round(Int, seconds))s"
    elseif seconds < 3600
        return "$(round(Int, seconds/60))m"
    elseif seconds < 86400
        return "$(round(Int, seconds/3600))h"
    else
        return "$(round(Int, seconds/86400))d"
    end
end

# ============================================================================
# Analysis Mode Menus
# ============================================================================

"""
    AnalysisMode

Represents an analysis mode with its metadata.
"""
struct AnalysisMode
    id::Symbol
    name::String
    description::String
    supported_types::Vector{DataType}  # Which ExperimentType subtypes support this mode
end

"""
Standard analysis modes available for all types.
"""
const COMMON_ANALYSIS_MODES = [
    AnalysisMode(:quality, "Quality", "Single experiment diagnostics", [ExperimentType]),
    AnalysisMode(:convergence, "Convergence", "Degree convergence analysis", [ExperimentType]),
]

"""
LV4D-specific analysis modes.
"""
const LV4D_ANALYSIS_MODES = [
    AnalysisMode(:quality, "Quality", "Single experiment critical point diagnostics", [LV4DType]),
    AnalysisMode(:sweep, "Sweep", "Aggregate domain × degree analysis", [LV4DType]),
    AnalysisMode(:convergence, "Convergence", "Log-log convergence rate", [LV4DType]),
    AnalysisMode(:compare, "Compare", "Method comparison (log vs standard)", [LV4DType]),
    AnalysisMode(:coverage, "Coverage", "Coverage analysis & gap detection", [LV4DType]),
]

"""
    get_analysis_modes(type::ExperimentType) -> Vector{AnalysisMode}

Get available analysis modes for an experiment type.
"""
function get_analysis_modes(::LV4DType)
    return LV4D_ANALYSIS_MODES
end

function get_analysis_modes(::ExperimentType)
    return COMMON_ANALYSIS_MODES
end

"""
    select_analysis_mode(type::ExperimentType) -> Union{Symbol, Nothing}

Show menu to select analysis mode for given experiment type.
"""
function select_analysis_mode(type::ExperimentType)::Union{Symbol, Nothing}
    modes = get_analysis_modes(type)

    options = ["$(m.name) - $(m.description)" for m in modes]
    menu = RadioMenu(options, pagesize=min(8, length(options)))
    choice = request("Select analysis mode:", menu)

    choice == -1 && return nothing
    return modes[choice].id
end

# ============================================================================
# Confirmation Menu
# ============================================================================

"""
    confirm_selection(summary::String) -> Bool

Show confirmation with summary of selections.
"""
function confirm_selection(summary::String)::Bool
    println()
    tui_divider()
    tui_success(summary)
    tui_divider()
    println()

    options = ["Yes - Run analysis", "No - Cancel"]
    menu = RadioMenu(options, pagesize=2)
    choice = request("Proceed?", menu)

    return choice == 1
end
