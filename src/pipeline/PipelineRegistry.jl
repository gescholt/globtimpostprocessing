"""
    PipelineRegistry.jl - Consolidated experiment registry with persistence and indexing

Tracks which experiments have been discovered, analyzed, and their current status.
Provides indexed lookups for fast parameter-based queries and coverage analysis.

This is the canonical experiment registry system, consolidating functionality from
the former ExperimentParameterIndex.jl.

# Features
- Persistent registry with JSON serialization
- Proper ExperimentParams struct (not Dict{String, Any})
- Indexed lookups (by_hash, by_gn, by_domain) for O(1) queries
- Coverage matrix and missing params detection
- Objective-agnostic (supports LV4D, Deuflhard, FitzHugh-Nagumo, etc.)

Registry is stored at `~/.globtim/pipeline_registry.json`
"""

using Dates
using JSON
using Printf
using PrettyTables

# ============================================================================
# Types
# ============================================================================

"""
    ExperimentStatus

Status of an experiment in the pipeline.
"""
@enum ExperimentStatus begin
    DISCOVERED      # Found but not yet analyzed
    ANALYZING       # Currently being analyzed
    ANALYZED        # Analysis complete
    FAILED          # Analysis failed
end

"""
    ExperimentParams

Extracted parameters from an experiment directory name.

# Fields
- `GN::Int`: Grid nodes (collocation points per dimension)
- `deg_min::Int`: Minimum polynomial degree
- `deg_max::Int`: Maximum polynomial degree
- `domain::Float64`: Domain range (±domain around true parameters)
- `seed::Union{Int, String, Nothing}`: Random seed (if specified)
- `basis::String`: Basis type (default: "chebyshev")
- `timestamp::Union{DateTime, Nothing}`: Experiment timestamp
- `objective::String`: Objective function type (e.g., "lotka_volterra_4d", "deuflhard", "fitzhugh_nagumo")
"""
struct ExperimentParams
    GN::Int
    deg_min::Int
    deg_max::Int
    domain::Float64
    seed::Union{Int, String, Nothing}
    basis::String
    timestamp::Union{DateTime, Nothing}
    objective::String
end

# Constructor with defaults
function ExperimentParams(;
    GN::Int,
    deg_min::Int,
    deg_max::Int,
    domain::Float64,
    seed::Union{Int, String, Nothing}=nothing,
    basis::String="chebyshev",
    timestamp::Union{DateTime, Nothing}=nothing,
    objective::String="unknown"
)
    ExperimentParams(GN, deg_min, deg_max, domain, seed, basis, timestamp, objective)
end

# Pretty printing
function Base.show(io::IO, p::ExperimentParams)
    seed_str = p.seed === nothing ? "" : ", seed=$(p.seed)"
    ts_str = p.timestamp === nothing ? "" : ", $(Dates.format(p.timestamp, "yyyy-mm-dd"))"
    obj_str = p.objective == "unknown" ? "" : " [$(p.objective)]"
    print(io, "ExperimentParams(GN=$(p.GN), deg=$(p.deg_min)-$(p.deg_max), domain=$(p.domain)$(seed_str)$(ts_str))$(obj_str)")
end

"""
    ParameterCoverage

Summary of parameter coverage in the registry.
"""
struct ParameterCoverage
    gn_values::Vector{Int}
    domain_values::Vector{Float64}
    degree_combinations::Vector{Tuple{Int,Int}}  # (deg_min, deg_max)
    coverage_matrix::Matrix{Int}  # GN (rows) × domain (cols) = count
    total_experiments::Int
    unique_param_combinations::Int
end

# ============================================================================
# Parameter Hash Functions (forward declarations needed for types)
# ============================================================================

"""
    compute_params_hash(GN, deg_min, deg_max, domain) -> String

Compute a canonical hash string for parameter combination.
Used for grouping experiments with identical core parameters.
"""
function compute_params_hash(GN::Int, deg_min::Int, deg_max::Int, domain::Float64)::String
    @sprintf("GN%d_deg%d-%d_dom%.6e", GN, deg_min, deg_max, domain)
end

"""
    compute_params_hash(p::ExperimentParams) -> String

Generate hash from ExperimentParams struct.
"""
function compute_params_hash(p::ExperimentParams)::String
    compute_params_hash(p.GN, p.deg_min, p.deg_max, p.domain)
end

# Alias for backward compatibility
const params_hash = compute_params_hash

# ============================================================================
# ExperimentParams JSON Serialization
# ============================================================================

# JSON serialization for ExperimentParams
function Base.Dict(p::ExperimentParams)
    Dict{String, Any}(
        "GN" => p.GN,
        "deg_min" => p.deg_min,
        "deg_max" => p.deg_max,
        "domain" => p.domain,
        "seed" => p.seed,
        "basis" => p.basis,
        "timestamp" => p.timestamp === nothing ? nothing : string(p.timestamp),
        "objective" => p.objective
    )
end

# Constructor from Dict (for JSON loading)
function ExperimentParams(d::AbstractDict)
    timestamp = get(d, "timestamp", nothing)
    if timestamp !== nothing && timestamp isa String
        try
            timestamp = DateTime(timestamp)
        catch
            # Try alternative format
            try
                timestamp = DateTime(timestamp, "yyyymmdd_HHMMSS")
            catch
                timestamp = nothing
            end
        end
    end

    ExperimentParams(
        d["GN"],
        d["deg_min"],
        d["deg_max"],
        d["domain"],
        get(d, "seed", nothing),
        get(d, "basis", "chebyshev"),
        timestamp,
        get(d, "objective", "unknown")
    )
end

# ============================================================================
# ExperimentEntry
# ============================================================================

"""
    ExperimentEntry

Registry entry for a single experiment.

# Fields
- `path::String`: Full path to experiment directory
- `name::String`: Directory name
- `discovered_at::DateTime`: When experiment was discovered
- `completed_at::Union{DateTime, Nothing}`: When experiment completed
- `analyzed_at::Union{DateTime, Nothing}`: When analysis was run
- `status::ExperimentStatus`: Current pipeline status
- `params::Union{ExperimentParams, Nothing}`: Extracted parameters
- `params_hash::String`: Canonical hash for indexed lookup
"""
struct ExperimentEntry
    path::String
    name::String
    discovered_at::DateTime
    completed_at::Union{DateTime, Nothing}
    analyzed_at::Union{DateTime, Nothing}
    status::ExperimentStatus
    params::Union{ExperimentParams, Nothing}
    params_hash::String
end

# Constructor from Dict (for JSON loading)
function ExperimentEntry(d::AbstractDict)
    # First try to get params from the "params" field
    params = if haskey(d, "params") && d["params"] !== nothing
        ExperimentParams(d["params"])
    else
        # If no params in data, try to extract from the name
        name = d["name"]
        extract_params_from_name(name)
    end

    params_hash_val = if params !== nothing
        compute_params_hash(params)
    else
        get(d, "params_hash", "")
    end

    ExperimentEntry(
        d["path"],
        d["name"],
        DateTime(d["discovered_at"]),
        d["completed_at"] === nothing ? nothing : DateTime(d["completed_at"]),
        d["analyzed_at"] === nothing ? nothing : DateTime(d["analyzed_at"]),
        ExperimentStatus(d["status"]),
        params,
        params_hash_val
    )
end

# Convert to Dict (for JSON saving)
function Base.Dict(e::ExperimentEntry)
    Dict{String, Any}(
        "path" => e.path,
        "name" => e.name,
        "discovered_at" => string(e.discovered_at),
        "completed_at" => e.completed_at === nothing ? nothing : string(e.completed_at),
        "analyzed_at" => e.analyzed_at === nothing ? nothing : string(e.analyzed_at),
        "status" => Int(e.status),
        "params" => e.params === nothing ? nothing : Dict(e.params),
        "params_hash" => e.params_hash
    )
end

# ============================================================================
# PipelineRegistry
# ============================================================================

"""
    PipelineRegistry

Central registry for pipeline state tracking with indexed lookups.

# Fields
- `experiments::Dict{String, ExperimentEntry}`: Path => entry mapping
- `by_hash::Dict{String, Vector{String}}`: params_hash => paths (for O(1) param lookup)
- `by_gn::Dict{Int, Vector{String}}`: GN => paths
- `by_domain::Dict{Float64, Vector{String}}`: domain => paths
- `results_root::String`: Root directory for experiment results
- `last_scan::Union{DateTime, Nothing}`: Last scan timestamp
- `config::Dict{String, Any}`: Configuration options
"""
mutable struct PipelineRegistry
    experiments::Dict{String, ExperimentEntry}
    by_hash::Dict{String, Vector{String}}
    by_gn::Dict{Int, Vector{String}}
    by_domain::Dict{Float64, Vector{String}}
    results_root::String
    last_scan::Union{DateTime, Nothing}
    config::Dict{String, Any}
end

# Default constructor
function PipelineRegistry(; results_root::String=default_results_root())
    PipelineRegistry(
        Dict{String, ExperimentEntry}(),
        Dict{String, Vector{String}}(),
        Dict{Int, Vector{String}}(),
        Dict{Float64, Vector{String}}(),
        results_root,
        nothing,
        Dict{String, Any}()
    )
end

# Pretty printing for PipelineRegistry
function Base.show(io::IO, r::PipelineRegistry)
    n_exp = length(r.experiments)
    n_hash = length(r.by_hash)
    n_gn = length(r.by_gn)
    n_domain = length(r.by_domain)

    # Count by status
    status_counts = Dict{ExperimentStatus, Int}()
    for entry in values(r.experiments)
        status_counts[entry.status] = get(status_counts, entry.status, 0) + 1
    end

    print(io, "PipelineRegistry(")
    print(io, "$n_exp experiments")
    if !isempty(status_counts)
        status_parts = String[]
        for s in [ANALYZED, DISCOVERED, ANALYZING, FAILED]
            if haskey(status_counts, s)
                push!(status_parts, "$(status_counts[s]) $(lowercase(string(s)))")
            end
        end
        print(io, " [", join(status_parts, ", "), "]")
    end
    print(io, ", $n_hash param combinations, $n_gn GN values, $n_domain domains")
    if r.last_scan !== nothing
        print(io, ", last scan: ", Dates.format(r.last_scan, "yyyy-mm-dd HH:MM"))
    end
    print(io, ")")
end

# ============================================================================
# Path Utilities
# ============================================================================

"""
    default_registry_path() -> String

Get the default registry file path (~/.globtim/pipeline_registry.json).
"""
function default_registry_path()::String
    globtim_dir = joinpath(homedir(), ".globtim")
    mkpath(globtim_dir)
    return joinpath(globtim_dir, "pipeline_registry.json")
end

"""
    default_results_root() -> String

Get the default results root directory.
"""
function default_results_root()::String
    # Check environment variable first
    if haskey(ENV, "GLOBTIM_RESULTS_ROOT")
        return ENV["GLOBTIM_RESULTS_ROOT"]
    end

    # Try relative to GlobalOptim
    current = pwd()
    for _ in 1:5
        candidate = joinpath(current, "globtim_results")
        if isdir(candidate)
            return candidate
        end
        current = dirname(current)
    end

    # Fall back to home directory
    return joinpath(homedir(), "globtim_results")
end

# ============================================================================
# Index Management
# ============================================================================

"""
    rebuild_indices!(registry::PipelineRegistry)

Rebuild all index structures from experiments. Call after loading or
when indices may be out of sync.
"""
function rebuild_indices!(registry::PipelineRegistry)
    # Clear indices
    empty!(registry.by_hash)
    empty!(registry.by_gn)
    empty!(registry.by_domain)

    # Rebuild from experiments
    for (path, entry) in registry.experiments
        _index_entry!(registry, path, entry)
    end

    return registry
end

"""
    _index_entry!(registry, path, entry)

Add a single entry to all index structures.
"""
function _index_entry!(registry::PipelineRegistry, path::String, entry::ExperimentEntry)
    if entry.params === nothing
        return
    end

    params = entry.params

    # Index by hash
    if !isempty(entry.params_hash)
        if !haskey(registry.by_hash, entry.params_hash)
            registry.by_hash[entry.params_hash] = String[]
        end
        push!(registry.by_hash[entry.params_hash], path)
    end

    # Index by GN
    if !haskey(registry.by_gn, params.GN)
        registry.by_gn[params.GN] = String[]
    end
    push!(registry.by_gn[params.GN], path)

    # Index by domain (rounded for float comparison)
    domain_key = round(params.domain, sigdigits=6)
    if !haskey(registry.by_domain, domain_key)
        registry.by_domain[domain_key] = String[]
    end
    push!(registry.by_domain[domain_key], path)
end

"""
    _remove_from_indices!(registry, path, entry)

Remove a single entry from all index structures.
"""
function _remove_from_indices!(registry::PipelineRegistry, path::String, entry::ExperimentEntry)
    if entry.params === nothing
        return
    end

    # Remove from hash index
    if !isempty(entry.params_hash) && haskey(registry.by_hash, entry.params_hash)
        filter!(p -> p != path, registry.by_hash[entry.params_hash])
        if isempty(registry.by_hash[entry.params_hash])
            delete!(registry.by_hash, entry.params_hash)
        end
    end

    # Remove from GN index
    gn = entry.params.GN
    if haskey(registry.by_gn, gn)
        filter!(p -> p != path, registry.by_gn[gn])
        if isempty(registry.by_gn[gn])
            delete!(registry.by_gn, gn)
        end
    end

    # Remove from domain index
    domain_key = round(entry.params.domain, sigdigits=6)
    if haskey(registry.by_domain, domain_key)
        filter!(p -> p != path, registry.by_domain[domain_key])
        if isempty(registry.by_domain[domain_key])
            delete!(registry.by_domain, domain_key)
        end
    end
end

# ============================================================================
# Registry I/O
# ============================================================================

"""
    load_pipeline_registry(; path=nothing, results_root=nothing) -> PipelineRegistry

Load pipeline registry from JSON file, or create new if doesn't exist.
Automatically rebuilds indices after loading.
"""
function load_pipeline_registry(;
    path::Union{String, Nothing}=nothing,
    results_root::Union{String, Nothing}=nothing
)::PipelineRegistry
    registry_path = something(path, default_registry_path())
    actual_results_root = something(results_root, default_results_root())

    if isfile(registry_path)
        try
            data = JSON.parsefile(registry_path)

            # Check schema version
            version = get(data, "version", "1.0")
            if version != "2.0"
                @warn "Registry version mismatch (found $version, expected 2.0). Migrating..."
            end

            experiments = Dict{String, ExperimentEntry}()
            for (k, v) in get(data, "experiments", Dict())
                experiments[k] = ExperimentEntry(v)
            end

            registry = PipelineRegistry(
                experiments,
                Dict{String, Vector{String}}(),  # Will rebuild
                Dict{Int, Vector{String}}(),
                Dict{Float64, Vector{String}}(),
                get(data, "results_root", actual_results_root),
                data["last_scan"] === nothing ? nothing : DateTime(data["last_scan"]),
                get(data, "config", Dict{String, Any}())
            )

            # Rebuild indices from loaded experiments
            rebuild_indices!(registry)

            return registry
        catch e
            @warn "Failed to load registry, creating new" exception=e
            return PipelineRegistry(results_root=actual_results_root)
        end
    else
        return PipelineRegistry(results_root=actual_results_root)
    end
end

"""
    save_pipeline_registry(registry; path=nothing)

Save pipeline registry to JSON file.
"""
function save_pipeline_registry(registry::PipelineRegistry; path::Union{String, Nothing}=nothing)
    registry_path = something(path, default_registry_path())

    experiments_dict = Dict{String, Any}()
    for (k, v) in registry.experiments
        experiments_dict[k] = Dict(v)
    end

    data = Dict{String, Any}(
        "experiments" => experiments_dict,
        "results_root" => registry.results_root,
        "last_scan" => registry.last_scan === nothing ? nothing : string(registry.last_scan),
        "config" => registry.config,
        "version" => "2.0"  # Updated schema version
    )

    mkpath(dirname(registry_path))
    open(registry_path, "w") do io
        JSON.print(io, data, 2)
    end
end

# ============================================================================
# Parameter Extraction
# ============================================================================

# Objective-specific directory name patterns
const EXPERIMENT_PATTERNS = Dict(
    "lotka_volterra_4d" => r"lv4d_GN(\d+)_deg(\d+)-(\d+)_(?:dom|domain)([\d.e+-]+)(?:_seed(\d+|random))?_(\d{8}_\d{6})",
    "deuflhard" => r"deuflhard_GN(\d+)_deg(\d+)-(\d+)_dom([\d.e+-]+)(?:_seed(\d+|random))?_(\d{8}_\d{6})",
    "fitzhugh_nagumo" => r"fhn_GN(\d+)_deg(\d+)-(\d+)_dom([\d.e+-]+)(?:_seed(\d+|random))?_(\d{8}_\d{6})",
)

"""
    extract_params_from_name(name::String; objective::String="auto") -> Union{ExperimentParams, Nothing}

Extract experiment parameters from directory name.

# Arguments
- `name`: Directory name to parse
- `objective`: Objective function type, or "auto" to detect from name prefix

# Returns
- `ExperimentParams` if successfully parsed, `nothing` otherwise
"""
function extract_params_from_name(name::String; objective::String="auto")::Union{ExperimentParams, Nothing}
    # Auto-detect objective from prefix
    detected_objective = if objective == "auto"
        if startswith(name, "lv4d_")
            "lotka_volterra_4d"
        elseif startswith(name, "deuflhard_")
            "deuflhard"
        elseif startswith(name, "fhn_")
            "fitzhugh_nagumo"
        else
            "unknown"
        end
    else
        objective
    end

    # Try the specific pattern first, then fall back to generic LV4D pattern
    patterns_to_try = if haskey(EXPERIMENT_PATTERNS, detected_objective)
        [EXPERIMENT_PATTERNS[detected_objective]]
    else
        # Try all patterns
        collect(values(EXPERIMENT_PATTERNS))
    end

    for pattern in patterns_to_try
        m = match(pattern, name)
        if m !== nothing
            GN = parse(Int, m.captures[1])
            deg_min = parse(Int, m.captures[2])
            deg_max = parse(Int, m.captures[3])
            domain = parse(Float64, m.captures[4])

            seed_str = m.captures[5]
            seed = if seed_str === nothing
                nothing
            elseif seed_str == "random"
                "random"
            else
                parse(Int, seed_str)
            end

            timestamp_str = m.captures[6]
            timestamp = try
                DateTime(timestamp_str, "yyyymmdd_HHMMSS")
            catch
                nothing
            end

            return ExperimentParams(
                GN=GN,
                deg_min=deg_min,
                deg_max=deg_max,
                domain=domain,
                seed=seed,
                timestamp=timestamp,
                objective=detected_objective
            )
        end
    end

    return nothing
end

# ============================================================================
# Registry Operations
# ============================================================================

"""
    add_experiment!(registry, path, name; completed_at=nothing, params=nothing)

Add a new experiment to the registry with proper indexing.

# Arguments
- `registry`: PipelineRegistry to modify
- `path`: Full path to experiment directory
- `name`: Directory name
- `completed_at`: When experiment completed (optional)
- `params`: ExperimentParams (optional, will extract from name if not provided)
"""
function add_experiment!(
    registry::PipelineRegistry,
    path::String,
    name::String;
    completed_at::Union{DateTime, Nothing}=nothing,
    params::Union{ExperimentParams, Nothing}=nothing
)
    # Extract params from name if not provided
    actual_params = if params !== nothing
        params
    else
        extract_params_from_name(name)
    end

    # Compute hash
    params_hash_val = if actual_params !== nothing
        compute_params_hash(actual_params)
    else
        ""
    end

    entry = ExperimentEntry(
        path,
        name,
        now(),
        completed_at,
        nothing,
        DISCOVERED,
        actual_params,
        params_hash_val
    )

    # Remove old entry from indices if exists
    if haskey(registry.experiments, path)
        _remove_from_indices!(registry, path, registry.experiments[path])
    end

    # Add to experiments dict
    registry.experiments[path] = entry

    # Add to indices
    _index_entry!(registry, path, entry)

    return entry
end

"""
    update_experiment_status!(registry, path, status; analyzed_at=nothing)

Update the status of an experiment in the registry.
"""
function update_experiment_status!(
    registry::PipelineRegistry,
    path::String,
    status::ExperimentStatus;
    analyzed_at::Union{DateTime, Nothing}=nothing
)
    if !haskey(registry.experiments, path)
        error("Experiment not found in registry: $path")
    end

    old = registry.experiments[path]
    registry.experiments[path] = ExperimentEntry(
        old.path,
        old.name,
        old.discovered_at,
        old.completed_at,
        status == ANALYZED ? something(analyzed_at, now()) : old.analyzed_at,
        status,
        old.params,
        old.params_hash
    )
end

"""
    get_pending_experiments(registry) -> Vector{ExperimentEntry}

Get all experiments with DISCOVERED status (not yet analyzed).
"""
function get_pending_experiments(registry::PipelineRegistry)::Vector{ExperimentEntry}
    pending = ExperimentEntry[]
    for (_, entry) in registry.experiments
        if entry.status == DISCOVERED
            push!(pending, entry)
        end
    end
    sort!(pending, by=e -> something(e.completed_at, e.discovered_at))
    return pending
end

"""
    get_analyzed_experiments(registry) -> Vector{ExperimentEntry}

Get all experiments with ANALYZED status.
"""
function get_analyzed_experiments(registry::PipelineRegistry)::Vector{ExperimentEntry}
    analyzed = ExperimentEntry[]
    for (_, entry) in registry.experiments
        if entry.status == ANALYZED
            push!(analyzed, entry)
        end
    end
    return analyzed
end

"""
    experiment_exists(registry, path) -> Bool

Check if an experiment is already in the registry.
"""
function experiment_exists(registry::PipelineRegistry, path::String)::Bool
    return haskey(registry.experiments, path)
end

# ============================================================================
# Indexed Queries (O(1) lookups using indices)
# ============================================================================

"""
    get_experiments_by_params(registry; GN=nothing, domain=nothing, deg_min=nothing, deg_max=nothing, domain_range=nothing) -> Vector{ExperimentEntry}

Query experiments matching specified parameter criteria.
Uses indices for fast lookup when possible.

# Example
```julia
# Find all GN=16 experiments (O(1) via index)
exps = get_experiments_by_params(registry; GN=16)

# Find experiments with specific params
exps = get_experiments_by_params(registry; GN=16, domain=0.08, deg_min=4, deg_max=12)
```
"""
function get_experiments_by_params(
    registry::PipelineRegistry;
    GN::Union{Int, Nothing}=nothing,
    domain::Union{Float64, Nothing}=nothing,
    deg_min::Union{Int, Nothing}=nothing,
    deg_max::Union{Int, Nothing}=nothing,
    domain_range::Union{Tuple{Float64,Float64}, Nothing}=nothing
)::Vector{ExperimentEntry}
    # Use exact hash lookup if all params specified
    if GN !== nothing && domain !== nothing && deg_min !== nothing && deg_max !== nothing
        hash = compute_params_hash(GN, deg_min, deg_max, domain)
        if haskey(registry.by_hash, hash)
            return [registry.experiments[p] for p in registry.by_hash[hash]]
        else
            return ExperimentEntry[]
        end
    end

    # Use GN index for initial filtering if specified
    candidates = if GN !== nothing && haskey(registry.by_gn, GN)
        [registry.experiments[p] for p in registry.by_gn[GN]]
    else
        collect(values(registry.experiments))
    end

    results = ExperimentEntry[]
    for entry in candidates
        if entry.params === nothing
            continue
        end

        params = entry.params

        # GN filter (already applied if using index)
        if GN !== nothing && params.GN != GN
            continue
        end

        # Domain filter
        if domain !== nothing && !isapprox(params.domain, domain, rtol=1e-6)
            continue
        end

        # Domain range filter
        if domain_range !== nothing
            if params.domain < domain_range[1] || params.domain > domain_range[2]
                continue
            end
        end

        # Degree filters
        if deg_min !== nothing && params.deg_min != deg_min
            continue
        end
        if deg_max !== nothing && params.deg_max != deg_max
            continue
        end

        push!(results, entry)
    end

    return results
end

"""
    has_experiment_with_params(registry; GN, domain, deg_min, deg_max) -> Bool

Check if an experiment with the specified parameters exists in the registry.
Uses hash index for O(1) lookup.
"""
function has_experiment_with_params(
    registry::PipelineRegistry;
    GN::Int,
    domain::Float64,
    deg_min::Int,
    deg_max::Int
)::Bool
    hash = compute_params_hash(GN, deg_min, deg_max, domain)
    return haskey(registry.by_hash, hash) && !isempty(registry.by_hash[hash])
end

"""
    get_experiments_for_params(registry; GN, domain, deg_min, deg_max) -> Vector{ExperimentEntry}

Get all experiments matching exact parameter combination.
Uses hash index for O(1) lookup.
"""
function get_experiments_for_params(
    registry::PipelineRegistry;
    GN::Int,
    domain::Float64,
    deg_min::Int,
    deg_max::Int
)::Vector{ExperimentEntry}
    hash = compute_params_hash(GN, deg_min, deg_max, domain)
    if !haskey(registry.by_hash, hash)
        return ExperimentEntry[]
    end
    return [registry.experiments[p] for p in registry.by_hash[hash]]
end

"""
    get_unique_params(registry) -> Vector{NamedTuple}

Get all unique parameter combinations in the registry with counts.
"""
function get_unique_params(registry::PipelineRegistry)
    rows = NamedTuple{(:GN, :deg_min, :deg_max, :domain, :count), Tuple{Int, Int, Int, Float64, Int}}[]

    for (hash, paths) in registry.by_hash
        if isempty(paths)
            continue
        end
        entry = registry.experiments[paths[1]]
        if entry.params === nothing
            continue
        end
        p = entry.params
        push!(rows, (
            GN = p.GN,
            deg_min = p.deg_min,
            deg_max = p.deg_max,
            domain = p.domain,
            count = length(paths)
        ))
    end

    sort!(rows, by = r -> (r.GN, r.domain, r.deg_min, r.deg_max))
    return rows
end

# Alias for backward compatibility with old API
function list_unique_params(registry::PipelineRegistry)
    get_unique_params(registry)
end

# ============================================================================
# Coverage Analysis
# ============================================================================

"""
    get_parameter_coverage(registry) -> ParameterCoverage

Compute coverage statistics for the registry.

Returns a `ParameterCoverage` object with:
- Unique GN values
- Unique domain values
- Coverage matrix (GN × domain → experiment count)
"""
function get_parameter_coverage(registry::PipelineRegistry)::ParameterCoverage
    # Collect unique values
    gn_set = Set{Int}()
    domain_set = Set{Float64}()
    degree_set = Set{Tuple{Int,Int}}()

    for (_, entry) in registry.experiments
        if entry.params === nothing
            continue
        end
        p = entry.params
        push!(gn_set, p.GN)
        push!(domain_set, round(p.domain, sigdigits=6))
        push!(degree_set, (p.deg_min, p.deg_max))
    end

    gn_values = sort(collect(gn_set))
    domain_values = sort(collect(domain_set))
    degree_combinations = sort(collect(degree_set))

    # Build coverage matrix
    gn_idx = Dict(gn => i for (i, gn) in enumerate(gn_values))
    domain_idx = Dict(d => i for (i, d) in enumerate(domain_values))

    coverage = zeros(Int, length(gn_values), length(domain_values))

    for (_, entry) in registry.experiments
        if entry.params === nothing
            continue
        end
        p = entry.params
        i = get(gn_idx, p.GN, nothing)
        j = get(domain_idx, round(p.domain, sigdigits=6), nothing)
        if i !== nothing && j !== nothing
            coverage[i, j] += 1
        end
    end

    return ParameterCoverage(
        gn_values,
        domain_values,
        degree_combinations,
        coverage,
        length(registry.experiments),
        length(registry.by_hash)
    )
end

"""
    get_missing_params(registry, target_gns, target_domains, target_degrees) -> Vector{NamedTuple}

Identify which parameter combinations are missing from the registry.

# Arguments
- `target_gns`: Vector of target GN values
- `target_domains`: Vector of target domain values
- `target_degrees`: Vector of (deg_min, deg_max) tuples

# Returns
- Vector of missing parameter combinations as NamedTuples
"""
function get_missing_params(
    registry::PipelineRegistry,
    target_gns::Vector{Int},
    target_domains::Vector{Float64},
    target_degrees::Vector{Tuple{Int,Int}}
)
    missing = NamedTuple{(:GN, :domain, :deg_min, :deg_max), Tuple{Int, Float64, Int, Int}}[]

    for gn in target_gns
        for domain in target_domains
            for (deg_min, deg_max) in target_degrees
                if !has_experiment_with_params(registry; GN=gn, domain=domain, deg_min=deg_min, deg_max=deg_max)
                    push!(missing, (GN=gn, domain=domain, deg_min=deg_min, deg_max=deg_max))
                end
            end
        end
    end

    return missing
end

# ============================================================================
# Display Functions
# ============================================================================

"""
    format_domain(d::Float64) -> String

Format domain value for display (handles scientific notation).
"""
function format_domain(d::Float64)::String
    if d >= 0.01
        return @sprintf("%.3f", d)
    else
        return @sprintf("%.1e", d)
    end
end

"""
    print_coverage_matrix(coverage; io=stdout)

Print the parameter coverage matrix as a formatted table.
"""
function print_coverage_matrix(coverage::ParameterCoverage; io::IO=stdout)
    if isempty(coverage.gn_values) || isempty(coverage.domain_values)
        println(io, "No experiments in registry.")
        return
    end

    # Format domain values for headers
    domain_headers = [format_domain(d) for d in coverage.domain_values]

    # Build table data
    header = vcat(["GN"], domain_headers)

    data = Matrix{Any}(undef, length(coverage.gn_values), length(coverage.domain_values) + 1)
    for (i, gn) in enumerate(coverage.gn_values)
        data[i, 1] = "GN=$gn"
        for (j, _) in enumerate(coverage.domain_values)
            count = coverage.coverage_matrix[i, j]
            data[i, j+1] = count > 0 ? count : "-"
        end
    end

    println(io)
    println(io, "Parameter Coverage: GN × Domain")
    println(io, "="^70)

    pretty_table(io, data;
        header=header,
        alignment=:c,
        crop=:none
    )

    println(io)
    println(io, "Total: $(coverage.total_experiments) experiments, $(coverage.unique_param_combinations) unique parameter combinations")

    # Show degree combinations
    if length(coverage.degree_combinations) > 0
        degs = join(["$(d[1])-$(d[2])" for d in coverage.degree_combinations[1:min(10, end)]], ", ")
        if length(coverage.degree_combinations) > 10
            degs *= ", ..."
        end
        println(io, "Degree ranges: $degs")
    end
end

"""
    print_query_results(entries; io=stdout, limit=20)

Print query results in a formatted list.
"""
function print_query_results(
    entries::Vector{ExperimentEntry};
    io::IO=stdout,
    limit::Int=20
)
    if isempty(entries)
        println(io, "No experiments found matching criteria.")
        return
    end

    println(io)
    println(io, "Found $(length(entries)) experiments:")
    println(io, "="^70)

    display_entries = entries[1:min(limit, length(entries))]

    for (i, entry) in enumerate(display_entries)
        if entry.params === nothing
            println(io, "  $i. $(entry.name) (no params)")
            continue
        end
        p = entry.params
        seed_str = p.seed === nothing ? "" : " seed=$(p.seed)"
        ts_str = p.timestamp === nothing ? "" : " $(Dates.format(p.timestamp, "yyyy-mm-dd"))"
        println(io, "  $i. $(entry.name)")
        println(io, "     GN=$(p.GN), deg=$(p.deg_min)-$(p.deg_max), domain=$(format_domain(p.domain))$(seed_str)$(ts_str)")
    end

    if length(entries) > limit
        println(io, "  ... and $(length(entries) - limit) more")
    end
end
