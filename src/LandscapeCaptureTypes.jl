# LandscapeCaptureTypes.jl
# Data types and JSON loaders for landscape capture analysis
#
# Promoted from experiments/sandbox/plot_landscape_capture.jl into the
# GlobtimPostProcessing package. These types hold visualization-oriented
# summaries of degree sweep and subdivision experiments for landscape
# capture diagnostics (CP counts, refinement paths, leaf spatial data).
#
# For the comprehensive analysis-oriented subdivision result type, see
# SubdivisionResult in SubdivisionTreeAnalysis.jl.

using JSON #==============================================================================#

#                    DATA TYPES                                                #

"""
    LandscapeRefinementDetails

Per-critical-point refinement diagnostics for landscape capture visualization.

Stores the raw → refined refinement path for every candidate CP, including
convergence status, classification, gradient norms, and iteration counts.
This is the data needed for refinement diagnostic panels (scatter plots of
raw→refined paths, gradient norm histograms, outcome bars).

# Fields
- `raw_points::Vector{Vector{Float64}}`: Pre-refinement critical point locations
- `refined_points::Vector{Vector{Float64}}`: Post-refinement critical point locations
- `converged::Vector{Bool}`: Whether each CP refinement converged
- `cp_types::Vector{String}`: Classification of each refined CP (`"min"`, `"saddle"`, `"max"`, `"unknown"`)
- `gradient_norms::Vector{Float64}`: Gradient norm at each refined CP (`NaN` if unavailable)
- `objective_values::Vector{Float64}`: Objective value at each refined CP (`NaN` if unavailable)
- `iterations::Vector{Int}`: Number of refinement iterations for each CP
"""
struct LandscapeRefinementDetails
    raw_points::Vector{Vector{Float64}}
    refined_points::Vector{Vector{Float64}}
    converged::Vector{Bool}
    cp_types::Vector{String}
    gradient_norms::Vector{Float64}
    objective_values::Vector{Float64}
    iterations::Vector{Int}
end

"""
    LandscapeMethodResult

Summary of a single method's critical point results for landscape comparison.

Represents either a single-domain polynomial degree sweep entry or a
subdivision experiment result. Used for comparing CP counts and capture
curves across methods.

# Fields
- `label::String`: Display label (e.g. `"deg 4"`, `"subdiv 4→8"`)
- `degree::Int`: Polynomial degree (initial degree for subdivision)
- `n_min::Int`: Number of local minima found
- `n_saddle::Int`: Number of saddle points found
- `n_max::Int`: Number of local maxima found
- `n_verified::Int`: Total verified CPs (after deduplication)
- `cp_points::Vector{Vector{Float64}}`: Refined critical point locations
- `cp_values::Vector{Float64}`: Objective values at refined CPs
- `cp_types::Vector{String}`: Classification of each refined CP
- `best_objective::Union{Float64, Nothing}`: Best (lowest) objective among minima
- `refinement::Union{LandscapeRefinementDetails, Nothing}`: Per-CP refinement diagnostics
- `is_subdivision::Bool`: Whether this is a subdivision (vs single-domain) result
"""
struct LandscapeMethodResult
    label::String
    degree::Int
    n_min::Int
    n_saddle::Int
    n_max::Int
    n_verified::Int
    cp_points::Vector{Vector{Float64}}
    cp_values::Vector{Float64}
    cp_types::Vector{String}
    best_objective::Union{Float64,Nothing}
    refinement::Union{LandscapeRefinementDetails,Nothing}
    is_subdivision::Bool
end

"""
    LandscapeSubdivisionData

Spatial data from a subdivision experiment for visualization.

Holds leaf bounds, L2 errors, and degree metadata for drawing domain
partition plots (colored rectangles), volume histograms, and error heatmaps.

# Fields
- `leaf_bounds::Vector{Vector{Vector{Float64}}}`: Per-leaf bounds `[leaf][dim] → [lo, hi]`
- `leaf_l2_errors::Vector{Float64}`: Per-leaf L2 approximation errors
- `n_leaves::Int`: Total number of leaves
- `degree::Int`: Initial polynomial degree
- `max_degree::Int`: Maximum degree (equals `degree` if no degree bumping)
- `label::String`: Display label (e.g. `"subdiv deg 4"`, `"subdiv 4→8"`)
"""
struct LandscapeSubdivisionData
    leaf_bounds::Vector{Vector{Vector{Float64}}}   # [leaf][dim] → [lo, hi]
    leaf_l2_errors::Vector{Float64}
    n_leaves::Int
    degree::Int
    max_degree::Int
    label::String
end #==============================================================================#

#                    JSON PARSERS                                               #

"""
    parse_landscape_refinement(d::AbstractDict) -> LandscapeRefinementDetails

Parse a `refinement_details` JSON dictionary into a [`LandscapeRefinementDetails`](@ref).

The dictionary must contain keys: `"raw_points"`, `"refined_points"`, `"converged"`,
`"cp_types"`, `"gradient_norms"`, `"objective_values"`, `"iterations"`.

`nothing` values in `gradient_norms` and `objective_values` are converted to `NaN`.
"""
function parse_landscape_refinement(d::AbstractDict)
    for key in (
        "raw_points",
        "refined_points",
        "converged",
        "cp_types",
        "gradient_norms",
        "objective_values",
        "iterations",
    )
        haskey(d, key) || error("Missing required key '$key' in refinement_details")
    end

    return LandscapeRefinementDetails(
        Vector{Float64}[Float64.(p) for p in d["raw_points"]],
        Vector{Float64}[Float64.(p) for p in d["refined_points"]],
        Bool.(d["converged"]),
        String.(d["cp_types"]),
        Float64[v === nothing ? NaN : Float64(v) for v in d["gradient_norms"]],
        Float64[v === nothing ? NaN : Float64(v) for v in d["objective_values"]],
        Int.(d["iterations"]),
    )
end

"""
    load_landscape_degree_sweep(path::String) -> NamedTuple

Load a degree sweep JSON result for landscape capture analysis.

Returns a NamedTuple with fields:
- `problem::String`: Problem identifier
- `bounds::Vector{Vector{Float64}}`: Domain bounds `[[lo, hi], ...]`
- `p_true::Vector{Float64}`: True parameter vector
- `methods::Vector{LandscapeMethodResult}`: Per-degree results
- `crashed_degrees::Vector{Int}`: Degrees that crashed during sweep

# JSON structure
```json
{
  "problem": "lv2d_sciml",
  "bounds": [[0, 100], [0, 100]],
  "p_true": [0.2, 0.3],
  "degrees": [
    {
      "degree": 4,
      "n_min": 1, "n_saddle": 0, "n_max": 0, "n_verified": 1,
      "cp_points": [[0.21, 0.31]], "cp_values": [0.001], "cp_types": ["min"],
      "best_objective": 0.001,
      "refinement_details": { ... }
    },
    { "degree": 20, "error": "SingularException" }
  ]
}
```

# Example
```julia
sweep = load_landscape_degree_sweep("results/lv2d_degree_sweep.json")
println(sweep.problem)
for m in sweep.methods
    println("  \$(m.label): \$(m.n_min) minima")
end
```
"""
function load_landscape_degree_sweep(path::String)
    !isfile(path) && error("File not found: $path")
    endswith(path, ".json") || error("Expected .json file, got: $path")

    data = JSON.parsefile(path)

    haskey(data, "problem") || error("Missing 'problem' in $path")
    haskey(data, "degrees") || error("Missing 'degrees' in $path")
    haskey(data, "bounds") || error("Missing 'bounds' in $path")
    haskey(data, "p_true") || error("Missing 'p_true' in $path")

    problem = String(data["problem"])
    bounds = [[Float64(b[1]), Float64(b[2])] for b in data["bounds"]]
    p_true = Float64.(data["p_true"])

    methods = LandscapeMethodResult[]
    crashed_degrees = Int[]

    for d in data["degrees"]
        deg = Int(d["degree"])

        # Crashed degrees have an "error" key
        if haskey(d, "error")
            push!(crashed_degrees, deg)
            continue
        end

        # Verified CP details
        cp_points =
            haskey(d, "cp_points") ? Vector{Float64}[Float64.(p) for p in d["cp_points"]] :
            Vector{Float64}[]
        cp_values = haskey(d, "cp_values") ? Float64.(d["cp_values"]) : Float64[]
        cp_types = haskey(d, "cp_types") ? String.(d["cp_types"]) : String[]

        # Refinement details
        refinement =
            haskey(d, "refinement_details") ?
            parse_landscape_refinement(d["refinement_details"]) : nothing

        best_obj = get(d, "best_objective", nothing)
        best_obj = best_obj isa Number ? Float64(best_obj) : nothing

        push!(
            methods,
            LandscapeMethodResult(
                "deg $deg",
                deg,
                Int(get(d, "n_min", 0)),
                Int(get(d, "n_saddle", 0)),
                Int(get(d, "n_max", 0)),
                Int(get(d, "n_verified", 0)),
                cp_points,
                cp_values,
                cp_types,
                best_obj,
                refinement,
                false,
            ),
        )
    end

    return (; problem, bounds, p_true, methods, crashed_degrees)
end

"""
    load_landscape_subdivision(path::String) -> NamedTuple

Load a subdivision experiment JSON for landscape capture analysis.

Returns a NamedTuple with fields:
- `method::LandscapeMethodResult`: The subdivision result as a method entry
- `subdiv_data::LandscapeSubdivisionData`: Spatial data for visualization

This loads the same JSON format as [`load_subdivision_result`](@ref) but produces
visualization-oriented types instead of the comprehensive `SubdivisionResult`.

# Example
```julia
result = load_landscape_subdivision("results/lv2d_deg4to8.json")
println(result.method.label)         # "subdiv 4→8"
println(result.subdiv_data.n_leaves) # 12
```
"""
function load_landscape_subdivision(path::String)
    !isfile(path) && error("File not found: $path")
    endswith(path, ".json") || error("Expected .json file, got: $path")

    data = JSON.parsefile(path)

    haskey(data, "parameters") || error("Missing 'parameters' section in $path")
    haskey(data, "tree") || error("Missing 'tree' section in $path")

    params = data["parameters"]
    tree = data["tree"]
    refined = get(data, "refined", nothing)

    deg = Int(params["degree"])
    max_deg = Int(get(params, "max_degree", deg))
    label = max_deg > deg ? "subdiv $deg→$max_deg" : "subdiv deg $deg"

    has_refined = refined !== nothing && get(refined, "n_after_dedup", 0) > 0

    # Verified CPs from refined section
    cp_points =
        has_refined && haskey(refined, "points") ?
        Vector{Float64}[Float64.(p) for p in refined["points"]] : Vector{Float64}[]
    cp_values =
        has_refined && haskey(refined, "objective_values") ?
        Float64.(refined["objective_values"]) : Float64[]
    cp_types =
        has_refined && haskey(refined, "cp_types") ? String.(refined["cp_types"]) : String[]

    # Refinement details
    refinement =
        haskey(data, "refinement_details") ?
        parse_landscape_refinement(data["refinement_details"]) : nothing

    best_obj =
        has_refined ?
        get(refined, "best_min_objective", get(refined, "best_objective", nothing)) :
        nothing
    best_obj = best_obj isa Number ? Float64(best_obj) : nothing

    method = LandscapeMethodResult(
        label,
        deg,
        has_refined ? Int(get(refined, "n_min", 0)) : 0,
        has_refined ? Int(get(refined, "n_saddle", 0)) : 0,
        has_refined ? Int(get(refined, "n_max", 0)) : 0,
        has_refined ? Int(get(refined, "n_after_dedup", 0)) : 0,
        cp_points,
        cp_values,
        cp_types,
        best_obj,
        refinement,
        true,
    )

    # Subdivision spatial data
    leaf_bounds =
        haskey(tree, "leaf_bounds") ?
        [Vector{Float64}[Float64.(b) for b in lb] for lb in tree["leaf_bounds"]] :
        Vector{Vector{Float64}}[]
    leaf_l2_errors =
        haskey(tree, "leaf_l2_errors") ? Float64.(tree["leaf_l2_errors"]) : Float64[]

    subdiv_data = LandscapeSubdivisionData(
        leaf_bounds,
        leaf_l2_errors,
        Int(get(tree, "n_total_leaves", 0)),
        deg,
        max_deg,
        label,
    )

    return (; method, subdiv_data)
end
