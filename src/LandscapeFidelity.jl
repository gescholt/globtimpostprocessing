"""
    LandscapeFidelity.jl

Assess how well polynomial approximant critical points correspond to
objective function basins of attraction.

# Overview

When we find critical points of the polynomial approximant P(x), we want to know:
**Does this polynomial minimum lead to a real objective minimum in the same basin?**

This module provides principled checks that go beyond naive distance thresholds.

# Quality Metrics

1. **Objective Proximity**: Do f(x*) and f(x_min) have similar values?
2. **Hessian Basin**: Does x* lie within the quadratic basin around x_min?
3. **Composite Assessment**: Combine multiple criteria with confidence scores

# Quick Start (REPL)

```julia
using GlobtimPostProcessing

# Define your objective function
f(x) = sum((x .- 0.5).^2)  # Simple quadratic

# Polynomial found a minimum at:
x_star = [0.48, 0.52, 0.49, 0.51]

# Local optimization converged to:
x_min = [0.50, 0.50, 0.50, 0.50]

# Check if they're in the same basin
result = check_objective_proximity(x_star, x_min, f)
println("Same basin: ", result.is_same_basin)
println("Relative difference: ", result.metric)

# More rigorous: use Hessian-based basin estimation
using ForwardDiff
H = ForwardDiff.hessian(f, x_min)
result = check_hessian_basin(x_star, x_min, f, H)
println("Inside basin: ", result.is_same_basin)
println("Relative distance: ", result.metric)
```

# Integration with Experiment Results

```julia
# Load experiment
results = load_experiment_results("path/to/experiment")

# Get critical points DataFrame
df = results.critical_points

# For each polynomial minimum, assess fidelity
for row in eachrow(df)
    if row.point_classification == "minimum"
        x_star = [row.x1, row.x2, row.x3, row.x4]

        # Run local optimization from x_star on your objective
        x_min = optimize_from_point(objective, x_star)

        # Check basin membership
        result = assess_landscape_fidelity(x_star, x_min, objective)
        println("Fidelity: ", result.confidence)
    end
end
```
"""

using LinearAlgebra
using Statistics

"""
    ObjectiveProximityResult

Result from objective function proximity check.

# Fields
- `is_same_basin::Bool`: Whether points are considered in same basin
- `metric::Float64`: Relative objective function difference
- `f_star::Float64`: Objective value at polynomial critical point
- `f_min::Float64`: Objective value at refined minimum
"""
struct ObjectiveProximityResult
    is_same_basin::Bool
    metric::Float64
    f_star::Float64
    f_min::Float64
end

"""
    HessianBasinResult

Result from Hessian-based basin estimation check.

# Fields
- `is_same_basin::Bool`: Whether x* is inside estimated basin
- `metric::Float64`: Relative distance (distance / basin_radius)
- `distance::Float64`: Euclidean distance between points
- `basin_radius::Float64`: Estimated basin radius
- `min_eigenvalue::Float64`: Smallest Hessian eigenvalue (curvature)
"""
struct HessianBasinResult
    is_same_basin::Bool
    metric::Float64
    distance::Float64
    basin_radius::Float64
    min_eigenvalue::Float64
end

"""
    LandscapeFidelityResult

Comprehensive landscape fidelity assessment combining multiple criteria.

# Fields
- `is_same_basin::Bool`: Overall assessment (consensus of criteria)
- `confidence::Float64`: Confidence score [0,1] (fraction of criteria agreeing)
- `criteria::Vector{NamedTuple}`: Individual criterion results
- `x_star::Vector{Float64}`: Polynomial critical point
- `x_min::Vector{Float64}`: Refined minimum
"""
struct LandscapeFidelityResult
    is_same_basin::Bool
    confidence::Float64
    criteria::Vector{NamedTuple}
    x_star::Vector{Float64}
    x_min::Vector{Float64}
end

"""
    check_objective_proximity(x_star::Vector{Float64},
                              x_min::Vector{Float64},
                              objective::Function;
                              tolerance::Float64=0.05,
                              abs_tolerance::Float64=1e-6) -> ObjectiveProximityResult

Check if two points are in the same basin based on objective function values.

# Arguments
- `x_star`: Polynomial critical point
- `x_min`: Refined minimum from local optimization
- `objective`: Objective function f(x)
- `tolerance`: Relative tolerance (default: 5%)
- `abs_tolerance`: Absolute tolerance for global minima (default: 1e-6)

# Returns
`ObjectiveProximityResult` with basin membership assessment

# Algorithm
Uses hybrid absolute/relative criterion to handle both global and local minima:

1. **Global minima** (both f_star and f_min < abs_tolerance):
   - Points considered in same basin if both near zero
   - Returns absolute difference as metric

2. **Local minima** (f_min >= abs_tolerance):
   - Uses relative difference: |f(x*) - f(x_min)| / |f(x_min)|
   - Points in same basin if relative difference < tolerance

# Example
```julia
f(x) = sum(x.^2)
x_star = [0.01, 0.02]  # Near global minimum
x_min = [0.0, 0.0]     # Exact global minimum

result = check_objective_proximity(x_star, x_min, f)
@assert result.is_same_basin  # Both at global minimum (f ≈ 0)
```

# Rationale
If the polynomial minimum gives nearly the same objective value as the
refined minimum, they likely lie in the same level set and basin, even
if spatially separated. The hybrid criterion prevents spurious failures
when optimizing to global minima (f ≈ 0).

**Pros**: Scale-invariant, handles global minima correctly, no derivatives needed
**Cons**: Can give false positives in flat regions
"""
function check_objective_proximity(x_star::Vector{Float64},
                                   x_min::Vector{Float64},
                                   objective::Function;
                                   tolerance::Float64=0.05,
                                   abs_tolerance::Float64=1e-6)
    f_star = objective(x_star)
    f_min = objective(x_min)

    # Asymmetric hybrid criterion: handle global minima correctly
    if abs(f_min) < abs_tolerance
        # f_min ≈ 0 (global minimum case)
        # Check if f_star is also small (using tolerance, not abs_tolerance)
        # This allows f_star to be larger than abs_tolerance but still near zero
        is_same_basin = abs(f_star) < tolerance
        metric = abs(f_star - f_min)  # Report absolute difference
    else
        # Standard relative difference for non-zero minima
        rel_diff = abs(f_star - f_min) / abs(f_min)
        is_same_basin = rel_diff < tolerance
        metric = rel_diff
    end

    return ObjectiveProximityResult(is_same_basin, metric, f_star, f_min)
end

"""
    estimate_basin_radius(x_min::Vector{Float64},
                         objective::Function,
                         hessian_min::Matrix{Float64};
                         threshold_factor::Float64=0.1) -> Float64

Estimate basin of attraction radius using local quadratic approximation.

# Arguments
- `x_min`: Local minimum location
- `objective`: Objective function f(x)
- `hessian_min`: Hessian matrix H_f(x_min)
- `threshold_factor`: Fraction of f(x_min) to use as threshold (default: 10%)

# Returns
Estimated basin radius in Euclidean norm

# Algorithm
At a local minimum, f(x) ≈ f(x_min) + ½(x - x_min)ᵀ H (x - x_min)

The basin radius r where f increases by Δf:
    ½ λ_min r² = Δf
    r = √(2Δf / λ_min)

where λ_min is the smallest eigenvalue (weakest curvature direction).

# Example
```julia
f(x) = sum(x.^2)  # Minimum at origin
x_min = [0.0, 0.0]
H = [2.0 0.0; 0.0 2.0]  # ∇²f = 2I

r = estimate_basin_radius(x_min, f, H)
# r ≈ 0 (global minimum, threshold_factor * 0 = 0)
```

# Notes
- Returns NaN if minimum is degenerate (λ_min ≤ 0)
- Assumes local quadratic approximation is valid
- Larger threshold_factor → larger estimated basin
"""
function estimate_basin_radius(x_min::Vector{Float64},
                              objective::Function,
                              hessian_min::Matrix{Float64};
                              threshold_factor::Float64=0.1)
    # Compute eigenvalues
    eigenvalues = eigvals(hessian_min)
    λ_min = minimum(eigenvalues)

    # Check if it's actually a minimum
    if λ_min <= 1e-10
        return NaN  # Not a minimum or degenerate
    end

    # Threshold: acceptable increase in objective value
    f_min = objective(x_min)
    Δf_threshold = threshold_factor * abs(f_min)

    # Handle case where f_min ≈ 0 (global minimum)
    if abs(f_min) < 1e-10
        Δf_threshold = threshold_factor  # Absolute threshold
    end

    # Quadratic approximation: ½ λ_min r² = Δf
    basin_radius = sqrt(2 * Δf_threshold / λ_min)

    return basin_radius
end

"""
    check_hessian_basin(x_star::Vector{Float64},
                        x_min::Vector{Float64},
                        objective::Function,
                        hessian_min::Matrix{Float64};
                        threshold_factor::Float64=0.1) -> HessianBasinResult

Check if polynomial critical point lies within Hessian-estimated basin.

# Arguments
- `x_star`: Polynomial critical point
- `x_min`: Refined minimum from local optimization
- `objective`: Objective function f(x)
- `hessian_min`: Hessian matrix at x_min
- `threshold_factor`: Basin size parameter (default: 10%)

# Returns
`HessianBasinResult` with basin membership assessment

# Algorithm
1. Estimate basin radius using local quadratic approximation
2. Compute Euclidean distance d = ||x* - x_min||
3. Check if d < r_basin
4. Return relative distance d/r as metric

# Example
```julia
using ForwardDiff

f(x) = sum((x .- 0.5).^2)
x_min = [0.5, 0.5]
x_star = [0.51, 0.49]  # Close to minimum

H = ForwardDiff.hessian(f, x_min)
result = check_hessian_basin(x_star, x_min, f, H)

@assert result.is_same_basin
println("Distance: ", result.distance)
println("Basin radius: ", result.basin_radius)
println("Relative: ", result.metric)
```

# Rationale
Uses the geometry of the objective function's Hessian to define a
scale-adaptive basin size. Points with metric < 1.0 are inside the basin.

**Pros**: Geometrically rigorous, adapts to local curvature
**Cons**: Requires Hessian computation (expensive)
"""
function check_hessian_basin(x_star::Vector{Float64},
                            x_min::Vector{Float64},
                            objective::Function,
                            hessian_min::Matrix{Float64};
                            threshold_factor::Float64=0.1)
    # Estimate basin radius
    r_basin = estimate_basin_radius(x_min, objective, hessian_min,
                                    threshold_factor=threshold_factor)

    # Compute distance
    distance = norm(x_star - x_min)

    # Check if inside basin
    if isnan(r_basin)
        # Degenerate case - fall back to objective proximity would be better
        return HessianBasinResult(false, Inf, distance, NaN, NaN)
    end

    relative_distance = distance / r_basin
    is_inside = relative_distance < 1.0

    # Get minimum eigenvalue for reporting
    λ_min = minimum(eigvals(hessian_min))

    return HessianBasinResult(is_inside, relative_distance, distance, r_basin, λ_min)
end

"""
    assess_landscape_fidelity(x_star::Vector{Float64},
                             x_min::Vector{Float64},
                             objective::Function;
                             hessian_min::Union{Matrix{Float64}, Nothing}=nothing,
                             obj_tolerance::Float64=0.05,
                             threshold_factor::Float64=0.1) -> LandscapeFidelityResult

Comprehensive landscape fidelity assessment with multiple criteria.

# Arguments
- `x_star`: Polynomial critical point
- `x_min`: Refined minimum from local optimization
- `objective`: Objective function f(x)
- `hessian_min`: Optional Hessian at x_min (for rigorous check)
- `obj_tolerance`: Relative tolerance for objective proximity (default: 5%)
- `threshold_factor`: Basin size parameter for Hessian check (default: 10%)

# Returns
`LandscapeFidelityResult` with:
- Overall basin membership (majority vote)
- Confidence score [0, 1]
- Individual criterion results

# Algorithm
Applies multiple independent criteria:
1. **Objective proximity**: |f(x*) - f(x_min)| / |f(x_min)| < tolerance
2. **Hessian basin** (if Hessian provided): ||x* - x_min|| < r_basin
3. **Consensus**: Majority vote determines result

# Example (Quick check without Hessian)
```julia
f(x) = sum((x .- [0.2, 0.3]).^2)
x_star = [0.21, 0.29]
x_min = [0.20, 0.30]

result = assess_landscape_fidelity(x_star, x_min, f)
println("Same basin: ", result.is_same_basin)
println("Confidence: ", result.confidence)

for c in result.criteria
    println("  ", c.name, ": ", c.passed, " (", c.metric, ")")
end
```

# Example (Rigorous check with Hessian)
```julia
using ForwardDiff

f(x) = sum((x .- [0.2, 0.3]).^2)
x_star = [0.21, 0.29]
x_min = [0.20, 0.30]
H = ForwardDiff.hessian(f, x_min)

result = assess_landscape_fidelity(x_star, x_min, f, hessian_min=H)
println("Confidence: ", result.confidence)  # Higher with more criteria
```

# Interpretation
- `confidence = 1.0`: All criteria agree → high confidence
- `confidence = 0.5`: Split decision → uncertain case
- `confidence = 0.0`: All criteria disagree → different basins
"""
function assess_landscape_fidelity(x_star::Vector{Float64},
                                  x_min::Vector{Float64},
                                  objective::Function;
                                  hessian_min::Union{Matrix{Float64}, Nothing}=nothing,
                                  obj_tolerance::Float64=0.05,
                                  threshold_factor::Float64=0.1)
    criteria = NamedTuple[]

    # Criterion 1: Objective proximity (always available)
    obj_result = check_objective_proximity(x_star, x_min, objective,
                                          tolerance=obj_tolerance)
    push!(criteria, (
        name = "objective_proximity",
        passed = obj_result.is_same_basin,
        metric = obj_result.metric,
        description = "f(x*) ≈ f(x_min)"
    ))

    # Criterion 2: Hessian basin (if available)
    if hessian_min !== nothing
        hess_result = check_hessian_basin(x_star, x_min, objective, hessian_min,
                                         threshold_factor=threshold_factor)
        push!(criteria, (
            name = "hessian_basin",
            passed = hess_result.is_same_basin,
            metric = hess_result.metric,
            description = "||x* - x_min|| < r_basin"
        ))
    end

    # Consensus: majority vote
    num_passed = sum([c.passed for c in criteria])
    num_total = length(criteria)
    confidence = num_passed / num_total
    is_same_basin = confidence >= 0.5

    return LandscapeFidelityResult(is_same_basin, confidence, criteria, x_star, x_min)
end

"""
    batch_assess_fidelity(critical_points_df::DataFrame,
                         refined_points::Vector{Vector{Float64}},
                         objective::Function;
                         classification_col::Symbol=:point_classification,
                         hessian_min_list::Union{Vector{Matrix{Float64}}, Nothing}=nothing) -> DataFrame

Batch assessment of landscape fidelity for multiple critical points.

# Arguments
- `critical_points_df`: DataFrame with polynomial critical points
- `refined_points`: Vector of refined minimum locations (from local optimization)
- `objective`: Objective function
- `classification_col`: Column name for point classification (default: :point_classification)
- `hessian_min_list`: Optional vector of Hessian matrices at refined points

# Returns
DataFrame with original data plus new columns:
- `is_same_basin`: Boolean, consensus assessment
- `fidelity_confidence`: Confidence score [0,1]
- `objective_proximity_metric`: Relative f difference
- `hessian_basin_metric`: Relative distance (if Hessian provided)

# Example
```julia
# Load critical points
df = load_critical_points("path/to/critical_points_deg_4.csv")
classify_all_critical_points!(df)

# Run local optimization from each minimum
refined = []
for row in eachrow(df)
    if row.point_classification == "minimum"
        x_star = [row.x1, row.x2, row.x3, row.x4]
        x_min = my_optimizer(objective, x_star)
        push!(refined, x_min)
    end
end

# Batch assess
results = batch_assess_fidelity(df, refined, objective)

# Analyze
valid_captures = sum(results.is_same_basin)
println("Landscape fidelity: ", valid_captures / nrow(results))
```
"""
function batch_assess_fidelity(critical_points_df::DataFrame,
                              refined_points::Vector{Vector{Float64}},
                              objective::Function;
                              classification_col::Symbol=:point_classification,
                              hessian_min_list::Union{Vector{Matrix{Float64}}, Nothing}=nothing)
    # Prepare output columns
    n_points = length(refined_points)
    is_same_basin = Bool[]
    confidences = Float64[]
    obj_metrics = Float64[]
    hess_metrics = Union{Float64, Missing}[]

    # Filter for minima
    minima_mask = critical_points_df[!, classification_col] .== "minimum"
    minima_df = critical_points_df[minima_mask, :]

    if nrow(minima_df) != n_points
        error("Number of refined points ($(n_points)) doesn't match number of minima ($(nrow(minima_df)))")
    end

    # Assess each point
    for (i, row) in enumerate(eachrow(minima_df))
        # Extract polynomial critical point
        param_cols = filter(n -> occursin(r"^x\d+$", string(n)), propertynames(row))
        sorted_cols = sort(param_cols, by=x -> parse(Int, match(r"\d+", string(x)).match))
        x_star = Float64[row[col] for col in sorted_cols]

        x_min = refined_points[i]
        H_min = hessian_min_list !== nothing ? hessian_min_list[i] : nothing

        # Assess fidelity
        result = assess_landscape_fidelity(x_star, x_min, objective, hessian_min=H_min)

        push!(is_same_basin, result.is_same_basin)
        push!(confidences, result.confidence)

        # Extract metrics
        obj_crit = result.criteria[findfirst(c -> c.name == "objective_proximity", result.criteria)]
        push!(obj_metrics, obj_crit.metric)

        if H_min !== nothing
            hess_crit = result.criteria[findfirst(c -> c.name == "hessian_basin", result.criteria)]
            push!(hess_metrics, hess_crit.metric)
        else
            push!(hess_metrics, missing)
        end
    end

    # Add columns to DataFrame copy
    result_df = copy(minima_df)
    result_df[!, :is_same_basin] = is_same_basin
    result_df[!, :fidelity_confidence] = confidences
    result_df[!, :objective_proximity_metric] = obj_metrics
    result_df[!, :hessian_basin_metric] = hess_metrics

    return result_df
end
