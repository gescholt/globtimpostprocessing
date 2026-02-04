"""
    Capture Analysis

Analyzes how well computed polynomial critical points capture known critical points
of the objective function. Given a set of known critical points (with types: min, max,
saddle) and a set of computed points, computes capture rates at multiple adaptive
tolerance levels with per-type breakdowns.

The key metric is: what fraction of ALL known critical points in the domain have
at least one computed polynomial critical point nearby (set-based matching)?

Created: 2026-02-04 (Capture analysis for multi-critical-point objectives)
"""

# Note: LinearAlgebra, Statistics, PrettyTables, Printf are imported in main module

"""
    KnownCriticalPoints

A set of known critical points of an objective function, with their values and types.

# Fields
- `points::Vector{Vector{Float64}}`: Coordinates of each known critical point
- `values::Vector{Float64}`: Objective function value f(x) at each point
- `types::Vector{Symbol}`: Type of each critical point (`:min`, `:max`, `:saddle`)
- `domain_diameter::Float64`: Euclidean diameter of the domain (norm of diagonal)

# Constructor
    KnownCriticalPoints(points, values, types, lower_bounds, upper_bounds)

Computes `domain_diameter = norm(upper_bounds - lower_bounds)` from the bounds.

# Example
```julia
points = [[0.0, 0.0], [1.0, 1.0], [0.5, 0.5]]
values = [0.0, 2.0, 1.0]
types = [:min, :min, :saddle]
lb = [-2.0, -2.0]
ub = [2.0, 2.0]
known = KnownCriticalPoints(points, values, types, lb, ub)
```
"""
struct KnownCriticalPoints
    points::Vector{Vector{Float64}}
    values::Vector{Float64}
    types::Vector{Symbol}
    domain_diameter::Float64
end

const VALID_CP_TYPES = Set([:min, :max, :saddle])

"""
    KnownCriticalPoints(points, values, types, lower_bounds, upper_bounds)

Construct `KnownCriticalPoints` from bounds, computing domain diameter automatically.

# Arguments
- `points::Vector{Vector{Float64}}`: Known critical point coordinates
- `values::Vector{Float64}`: f(x) at each known critical point
- `types::Vector{Symbol}`: Type of each CP (`:min`, `:max`, `:saddle`)
- `lower_bounds::Vector{Float64}`: Lower bounds of the domain
- `upper_bounds::Vector{Float64}`: Upper bounds of the domain

# Errors
- If `points` is empty
- If `points`, `values`, `types` have different lengths
- If any type is not in `{:min, :max, :saddle}`
- If `lower_bounds` and `upper_bounds` have different lengths
"""
function KnownCriticalPoints(
    points::Vector{Vector{Float64}},
    values::Vector{Float64},
    types::Vector{Symbol},
    lower_bounds::Vector{Float64},
    upper_bounds::Vector{Float64}
)
    isempty(points) && error("KnownCriticalPoints: points must be non-empty")

    n = length(points)
    length(values) == n || error("KnownCriticalPoints: values length ($(length(values))) must match points length ($n)")
    length(types) == n || error("KnownCriticalPoints: types length ($(length(types))) must match points length ($n)")
    length(lower_bounds) == length(upper_bounds) || error(
        "KnownCriticalPoints: lower_bounds length ($(length(lower_bounds))) must match upper_bounds length ($(length(upper_bounds)))"
    )

    ndim = length(lower_bounds)
    for (i, pt) in enumerate(points)
        length(pt) == ndim || error(
            "KnownCriticalPoints: point $i has dimension $(length(pt)), expected $ndim (from bounds)"
        )
    end

    for (i, t) in enumerate(types)
        t in VALID_CP_TYPES || error("KnownCriticalPoints: invalid type $(repr(t)) at index $i. Must be one of $VALID_CP_TYPES")
    end

    domain_diameter = LinearAlgebra.norm(upper_bounds - lower_bounds)

    return KnownCriticalPoints(points, values, types, domain_diameter)
end

"""
    CaptureResult

Result of capture analysis: how well computed critical points cover known critical points.

Contains per-known-CP distances, multi-tolerance capture rates, and per-type breakdowns.

# Fields
- `distances::Vector{Float64}`: Min distance from each known CP to nearest computed CP
- `nearest_indices::Vector{Int}`: Index of nearest computed CP for each known CP
- `tolerance_fractions::Vector{Float64}`: Tolerance levels as fractions of domain diameter (sorted ascending)
- `tolerance_values::Vector{Float64}`: Absolute tolerance distances
- `captured_at::Vector{BitVector}`: `captured_at[t][k]` = was known CP k captured at tolerance t?
- `capture_rates::Vector{Float64}`: Fraction of known CPs captured at each tolerance
- `type_capture_rates::Dict{Symbol, Vector{Float64}}`: Per-type capture rates at each tolerance
- `n_known::Int`: Number of known critical points
- `n_computed::Int`: Number of computed critical points
- `domain_diameter::Float64`: Domain diameter used for adaptive tolerance
- `type_counts::Dict{Symbol, Int}`: Count of each CP type in known set
"""
struct CaptureResult
    distances::Vector{Float64}
    nearest_indices::Vector{Int}
    tolerance_fractions::Vector{Float64}
    tolerance_values::Vector{Float64}
    captured_at::Vector{BitVector}
    capture_rates::Vector{Float64}
    type_capture_rates::Dict{Symbol, Vector{Float64}}
    n_known::Int
    n_computed::Int
    domain_diameter::Float64
    type_counts::Dict{Symbol, Int}
end

"""
    compute_capture_analysis(known, computed_points; tolerance_fractions) -> CaptureResult

Compute capture analysis: for each known critical point, find the nearest computed point
and determine capture rates at multiple adaptive tolerance levels.

Uses set-based matching: a known CP is "captured" at tolerance `tol` if ANY computed
critical point is within Euclidean distance `tol` of it.

# Arguments
- `known::KnownCriticalPoints`: The set of known critical points with types
- `computed_points::Vector{Vector{Float64}}`: Computed polynomial critical points
- `tolerance_fractions::Vector{Float64}`: Tolerance levels as fractions of domain diameter.
  Default: `[0.01, 0.025, 0.05, 0.1]` (1%, 2.5%, 5%, 10% of domain diameter)

# Returns
- `CaptureResult`: Full capture analysis with per-type breakdowns

# Example
```julia
known = KnownCriticalPoints(
    [[0.0, 0.0], [1.0, 1.0]],
    [0.0, 2.0],
    [:min, :saddle],
    [-2.0, -2.0], [2.0, 2.0]
)
computed = [[0.01, -0.01], [0.5, 0.5], [0.99, 1.01]]
result = compute_capture_analysis(known, computed)
println("Capture rate at 5%: ", result.capture_rates[3])
```

# Notes
- If `computed_points` is empty, all distances are `Inf` and all capture rates are `0.0`
- Tolerance fractions are sorted ascending internally
- Domain diameter is taken from `known.domain_diameter`
"""
function compute_capture_analysis(
    known::KnownCriticalPoints,
    computed_points::Vector{Vector{Float64}};
    tolerance_fractions::Vector{Float64} = [0.01, 0.025, 0.05, 0.1]
)::CaptureResult
    n_known = length(known.points)
    n_computed = length(computed_points)

    # Sort tolerance fractions ascending
    tol_fracs = sort(tolerance_fractions)
    tol_values = tol_fracs .* known.domain_diameter

    # Handle empty computed points: all known CPs are missed
    if n_computed == 0
        distances = fill(Inf, n_known)
        nearest_indices = zeros(Int, n_known)
        captured_at = [falses(n_known) for _ in tol_fracs]
        capture_rates = zeros(Float64, length(tol_fracs))

        # Per-type rates (all zero)
        type_counts = StatsBase.countmap(known.types)
        type_capture_rates = Dict{Symbol, Vector{Float64}}()
        for (tp, _) in type_counts
            type_capture_rates[tp] = zeros(Float64, length(tol_fracs))
        end

        return CaptureResult(
            distances, nearest_indices,
            tol_fracs, tol_values, captured_at, capture_rates,
            type_capture_rates,
            n_known, n_computed, known.domain_diameter, type_counts
        )
    end

    # For each known CP, find minimum distance and nearest computed CP
    # Computed per-row to avoid O(n_known * n_computed) matrix allocation
    distances = Vector{Float64}(undef, n_known)
    nearest_indices = Vector{Int}(undef, n_known)
    for k in 1:n_known
        best_dist = Inf
        best_idx = 0
        for c in 1:n_computed
            d = LinearAlgebra.norm(known.points[k] - computed_points[c])
            if d < best_dist
                best_dist = d
                best_idx = c
            end
        end
        distances[k] = best_dist
        nearest_indices[k] = best_idx
    end

    # Compute capture at each tolerance level
    n_tol = length(tol_fracs)
    captured_at = Vector{BitVector}(undef, n_tol)
    capture_rates = Vector{Float64}(undef, n_tol)
    for t in 1:n_tol
        captured_at[t] = distances .<= tol_values[t]
        capture_rates[t] = sum(captured_at[t]) / n_known
    end

    # Per-type capture rates
    type_counts = StatsBase.countmap(known.types)
    type_capture_rates = Dict{Symbol, Vector{Float64}}()
    for (tp, count) in type_counts
        type_mask = known.types .== tp
        rates = Vector{Float64}(undef, n_tol)
        for t in 1:n_tol
            n_captured_of_type = sum(captured_at[t] .& type_mask)
            rates[t] = n_captured_of_type / count
        end
        type_capture_rates[tp] = rates
    end

    return CaptureResult(
        distances, nearest_indices,
        tol_fracs, tol_values, captured_at, capture_rates,
        type_capture_rates,
        n_known, n_computed, known.domain_diameter, type_counts
    )
end

# Use StatsBase.countmap for type counting (already a dependency of the module)

"""
    missed_critical_points(result, known; tolerance_index) -> Vector{NamedTuple}

Get details of known critical points that were NOT captured at a given tolerance level.

# Arguments
- `result::CaptureResult`: Output from `compute_capture_analysis`
- `known::KnownCriticalPoints`: The known critical points
- `tolerance_index::Int`: Which tolerance level to check (default: last/largest)

# Returns
Vector of named tuples with fields:
- `index::Int`: Index in the known points array
- `point::Vector{Float64}`: Coordinates of the missed CP
- `value::Float64`: f(x) at the missed CP
- `type::Symbol`: Type of the missed CP
- `nearest_distance::Float64`: Distance to the nearest computed CP

# Example
```julia
missed = missed_critical_points(result, known)
for m in missed
    println("Missed CP #\$(m.index) at \$(m.point), type=\$(m.type), nearest=\$(m.nearest_distance)")
end
```
"""
function missed_critical_points(
    result::CaptureResult,
    known::KnownCriticalPoints;
    tolerance_index::Int = length(result.tolerance_fractions)
)::Vector{@NamedTuple{index::Int, point::Vector{Float64}, value::Float64, type::Symbol, nearest_distance::Float64}}
    1 <= tolerance_index <= length(result.tolerance_fractions) || error(
        "tolerance_index $tolerance_index out of range [1, $(length(result.tolerance_fractions))]"
    )

    captured = result.captured_at[tolerance_index]
    missed = @NamedTuple{index::Int, point::Vector{Float64}, value::Float64, type::Symbol, nearest_distance::Float64}[]

    for k in 1:result.n_known
        if !captured[k]
            push!(missed, (
                index = k,
                point = known.points[k],
                value = known.values[k],
                type = known.types[k],
                nearest_distance = result.distances[k]
            ))
        end
    end

    return missed
end

"""
    print_capture_summary(result, known; io=stdout)

Print a formatted summary of capture analysis results.

Outputs three tables:
1. **Overall capture rates** at each tolerance level
2. **Per-type capture rates** (min/max/saddle breakdown)
3. **Missed critical points** at the largest tolerance level

# Arguments
- `result::CaptureResult`: Output from `compute_capture_analysis`
- `known::KnownCriticalPoints`: The known critical points
- `io::IO`: Output stream (default: `stdout`)
"""
function print_capture_summary(
    result::CaptureResult,
    known::KnownCriticalPoints;
    io::IO = stdout
)
    n_tol = length(result.tolerance_fractions)

    # --- Table 1: Overall capture rates ---
    overall_data = Matrix{Any}(undef, n_tol, 4)
    for t in 1:n_tol
        n_captured = sum(result.captured_at[t])
        overall_data[t, 1] = @sprintf("%.1f%%", result.tolerance_fractions[t] * 100)
        overall_data[t, 2] = @sprintf("%.4f", result.tolerance_values[t])
        overall_data[t, 3] = "$n_captured / $(result.n_known)"
        overall_data[t, 4] = @sprintf("%.1f%%", result.capture_rates[t] * 100)
    end

    println(io)
    pretty_table(io, overall_data;
        header = ["Tol (frac)", "Tol (abs)", "Captured", "Rate"],
        title = "Capture Analysis ($(result.n_computed) computed vs $(result.n_known) known CPs, domain diam = $(@sprintf("%.4f", result.domain_diameter)))",
        alignment = [:r, :r, :c, :r],
        crop = :none
    )

    # --- Table 2: Per-type capture rates ---
    unique_types = sort(collect(keys(result.type_counts)))
    if length(unique_types) > 1
        type_header = ["Tol (frac)"]
        for tp in unique_types
            push!(type_header, "$(tp) ($(result.type_counts[tp]))")
        end

        type_data = Matrix{Any}(undef, n_tol, 1 + length(unique_types))
        for t in 1:n_tol
            type_data[t, 1] = @sprintf("%.1f%%", result.tolerance_fractions[t] * 100)
            for (j, tp) in enumerate(unique_types)
                rate = result.type_capture_rates[tp][t]
                type_data[t, 1 + j] = @sprintf("%.1f%%", rate * 100)
            end
        end

        println(io)
        pretty_table(io, type_data;
            header = type_header,
            title = "Per-Type Capture Rates",
            alignment = :r,
            crop = :none
        )
    end

    # --- Table 3: Missed CPs at largest tolerance ---
    missed = missed_critical_points(result, known; tolerance_index = n_tol)
    if !isempty(missed)
        n_dims = length(known.points[1])
        missed_header = ["#", "Type", "f(x)", "Nearest dist"]
        for d in 1:n_dims
            push!(missed_header, "x$d")
        end

        max_display = 20
        display_missed = length(missed) <= max_display ? missed : missed[1:max_display]

        missed_data = Matrix{Any}(undef, length(display_missed), 4 + n_dims)
        for (i, m) in enumerate(display_missed)
            missed_data[i, 1] = m.index
            missed_data[i, 2] = string(m.type)
            missed_data[i, 3] = @sprintf("%.6f", m.value)
            missed_data[i, 4] = @sprintf("%.6f", m.nearest_distance)
            for d in 1:n_dims
                missed_data[i, 4 + d] = @sprintf("%.6f", m.point[d])
            end
        end

        n_total_missed = length(missed)
        title_suffix = n_total_missed > max_display ? ", showing first $max_display of $n_total_missed" : ""
        println(io)
        pretty_table(io, missed_data;
            header = missed_header,
            title = "Missed Critical Points (at tol = $(@sprintf("%.4f", result.tolerance_values[n_tol]))$title_suffix)",
            alignment = :r,
            crop = :none
        )
    else
        println(io)
        println(io, "All $(result.n_known) known critical points captured at tolerance $(@sprintf("%.4f", result.tolerance_values[n_tol]))")
    end
end

"""
    print_degree_capture_convergence(degree_results; io=stdout)

Print how capture rate improves with polynomial degree.

# Arguments
- `degree_results::Vector{Tuple{Int, CaptureResult}}`: Pairs of (degree, capture_result)
- `io::IO`: Output stream (default: `stdout`)

# Example
```julia
results = [(4, result4), (6, result6), (8, result8)]
print_degree_capture_convergence(results)
```
"""
function print_degree_capture_convergence(
    degree_results::Vector{Tuple{Int, CaptureResult}};
    io::IO = stdout
)
    isempty(degree_results) && error("degree_results must be non-empty")

    # Validate that all results used the same tolerance fractions
    tol_fracs = degree_results[1][2].tolerance_fractions
    for (i, (deg, res)) in enumerate(degree_results)
        res.tolerance_fractions == tol_fracs || error(
            "Inconsistent tolerance_fractions: degree $(deg) (entry $i) has " *
            "$(res.tolerance_fractions) but expected $tol_fracs (from first entry)"
        )
    end

    header = ["Degree", "# Computed"]
    for tf in tol_fracs
        push!(header, @sprintf("rate@%.1f%%", tf * 100))
    end

    n_rows = length(degree_results)
    n_cols = 2 + length(tol_fracs)
    data = Matrix{Any}(undef, n_rows, n_cols)

    for (i, (deg, res)) in enumerate(degree_results)
        data[i, 1] = deg
        data[i, 2] = res.n_computed
        for (t, rate) in enumerate(res.capture_rates)
            data[i, 2 + t] = @sprintf("%.1f%%", rate * 100)
        end
    end

    println(io)
    pretty_table(io, data;
        header = header,
        title = "Capture Rate vs Polynomial Degree",
        alignment = :r,
        crop = :none
    )
end

# --- Mapping from CriticalPointClassification.jl String types to our Symbol types ---

const _CLASSIFICATION_TO_SYMBOL = Dict{String, Symbol}(
    "minimum" => :min,
    "maximum" => :max,
    "saddle" => :saddle,
    "degenerate" => :saddle  # treat degenerate as saddle for capture purposes
)

"""
    _classification_string_to_symbol(s::String) -> Symbol

Map CriticalPointClassification.jl output (`"minimum"`, `"maximum"`, `"saddle"`, `"degenerate"`)
to capture analysis symbols (`:min`, `:max`, `:saddle`).
"""
function _classification_string_to_symbol(s::String)::Symbol
    haskey(_CLASSIFICATION_TO_SYMBOL, s) || error("Unknown classification: $(repr(s))")
    return _CLASSIFICATION_TO_SYMBOL[s]
end

"""
    build_known_cps_from_2d_product(
        objective_2d::Function,
        points_2d::Vector{Vector{Float64}},
        lower_bounds::Vector{Float64},
        upper_bounds::Vector{Float64};
        hessian_tol::Float64 = 1e-6
    ) -> KnownCriticalPoints

Build 4D known critical points from 2D critical points for a separable function
`f(x₁,x₂,x₃,x₄) = g(x₁,x₂) + g(x₃,x₄)`.

Takes the Cartesian product of the 2D critical points to form all N² 4D critical points,
classifies each by combining the Hessian eigenvalue analysis of both 2D components.

Uses `classify_critical_point` from `CriticalPointClassification.jl` for Hessian-based
classification of each 2D component, then combines types:
- min + min → min
- max + max → max
- everything else → saddle

# Arguments
- `objective_2d::Function`: The 2D component function g(x) where f = g(x₁₂) + g(x₃₄)
- `points_2d::Vector{Vector{Float64}}`: Known 2D critical points of g
- `lower_bounds::Vector{Float64}`: Lower bounds of the 4D domain
- `upper_bounds::Vector{Float64}`: Upper bounds of the 4D domain
- `hessian_tol::Float64`: Tolerance for eigenvalue sign classification (default: 1e-6)

# Returns
- `KnownCriticalPoints`: All N² 4D critical points with values and types

# Example
```julia
deuflhard_2d(x) = (exp(x[1]^2 + x[2]^2) - 3)^2 + (x[1] + x[2] - sin(3(x[1] + x[2])))^2
pts_2d = [[0.0, 0.0], [0.741, 0.741], ...]  # from CSV
known_4d = build_known_cps_from_2d_product(
    deuflhard_2d, pts_2d,
    [-1.2, -1.2, -1.2, -1.2], [1.2, 1.2, 1.2, 1.2]
)
```
"""
function build_known_cps_from_2d_product(
    objective_2d::Function,
    points_2d::Vector{Vector{Float64}},
    lower_bounds::Vector{Float64},
    upper_bounds::Vector{Float64};
    hessian_tol::Float64 = 1e-6
)::KnownCriticalPoints
    isempty(points_2d) && error("points_2d must be non-empty")
    length(lower_bounds) == 4 || error("lower_bounds must be 4D, got $(length(lower_bounds))D")
    length(upper_bounds) == 4 || error("upper_bounds must be 4D, got $(length(upper_bounds))D")

    n_2d = length(points_2d)

    # Classify each 2D point using Hessian eigenvalues
    types_2d = Vector{Symbol}(undef, n_2d)
    vals_2d = Vector{Float64}(undef, n_2d)
    for i in 1:n_2d
        vals_2d[i] = objective_2d(points_2d[i])
        H = ForwardDiff.hessian(objective_2d, points_2d[i])
        eigs = eigvals(Symmetric(H))
        class_str = classify_critical_point(collect(eigs); tol = hessian_tol)
        types_2d[i] = _classification_string_to_symbol(class_str)
    end

    # Build all N^2 4D combinations
    n_4d = n_2d^2
    points_4d = Vector{Vector{Float64}}(undef, n_4d)
    values_4d = Vector{Float64}(undef, n_4d)
    types_4d = Vector{Symbol}(undef, n_4d)

    idx = 0
    for i in 1:n_2d, j in 1:n_2d
        idx += 1
        points_4d[idx] = vcat(points_2d[i], points_2d[j])
        values_4d[idx] = vals_2d[i] + vals_2d[j]

        # Combine types: min+min=min, max+max=max, else saddle
        if types_2d[i] == :min && types_2d[j] == :min
            types_4d[idx] = :min
        elseif types_2d[i] == :max && types_2d[j] == :max
            types_4d[idx] = :max
        else
            types_4d[idx] = :saddle
        end
    end

    return KnownCriticalPoints(points_4d, values_4d, types_4d, lower_bounds, upper_bounds)
end
