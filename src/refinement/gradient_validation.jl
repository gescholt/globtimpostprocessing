"""
Gradient Norm Validation

Provides gradient norm computation and validation for critical points.
A true critical point should have ||∇f(x*)|| ≈ 0.

Uses ForwardDiff.jl for automatic differentiation to compute gradients.

Created: 2025-11-27 (Issue: Gradient validation plan)
"""

# Note: ForwardDiff is imported in main GlobtimPostProcessing.jl

"""
    GradientValidationResult

Result of gradient validation for a set of critical points.

# Fields
- `norms::Vector{Float64}`: Gradient norms ||∇f(x)|| for each point
- `valid::Vector{Bool}`: Whether each point passes validation (norm < tolerance)
- `n_valid::Int`: Number of valid critical points
- `n_invalid::Int`: Number of invalid critical points
- `tolerance::Float64`: Tolerance used for validation
- `mean_norm::Float64`: Mean gradient norm across all points
- `max_norm::Float64`: Maximum gradient norm
- `min_norm::Float64`: Minimum gradient norm
"""
struct GradientValidationResult
    norms::Vector{Float64}
    valid::Vector{Bool}
    n_valid::Int
    n_invalid::Int
    tolerance::Float64
    mean_norm::Float64
    max_norm::Float64
    min_norm::Float64
end

"""
    compute_gradient_norms(points, objective; gradient_method=:forwarddiff) -> Vector{Float64}

Compute gradient norms at critical points.

For each point x, computes ||∇f(x)||₂ (Euclidean norm of gradient).

# Arguments
- `points::Vector{Vector{Float64}}`: Critical points to evaluate
- `objective::Function`: Objective function f(x::Vector{Float64}) -> Float64
- `gradient_method::Symbol`: `:forwarddiff` (default) or `:finitediff`

# Returns
- `Vector{Float64}`: Gradient norms for each point

# Examples
```julia
f(x) = (x[1] - 1.0)^2 + (x[2] - 2.0)^2
points = [[1.0, 2.0], [0.9, 1.9]]  # First is true critical point
norms = compute_gradient_norms(points, f)
# norms ≈ [0.0, 0.283...]  # First near zero, second has nonzero gradient

# For ODE-based objectives, use numerical gradients
norms = compute_gradient_norms(points, ode_objective; gradient_method=:finitediff)
```

# Notes
- `:forwarddiff`: Uses ForwardDiff.gradient (fast, exact for algebraic functions)
- `:finitediff`: Uses FiniteDiff.finite_difference_gradient (works with ODE objectives)
- Returns Inf if gradient computation fails
- Computation is done point-by-point (no parallelization)
"""
function compute_gradient_norms(
    points::Vector{Vector{Float64}},
    objective::Function;
    gradient_method::Symbol = :forwarddiff
)::Vector{Float64}
    norms = Vector{Float64}(undef, length(points))

    for (i, pt) in enumerate(points)
        try
            grad = if gradient_method == :forwarddiff
                ForwardDiff.gradient(objective, pt)
            elseif gradient_method == :finitediff
                FiniteDiff.finite_difference_gradient(objective, pt)
            else
                error("Unknown gradient_method: $gradient_method. Use :forwarddiff or :finitediff")
            end
            norms[i] = LinearAlgebra.norm(grad)
        catch e
            # If gradient computation fails, return Inf
            norms[i] = Inf
        end
    end

    return norms
end

"""
    compute_gradient_norm(point, objective; gradient_method=:forwarddiff) -> Float64

Compute gradient norm at a single critical point.

# Arguments
- `point::Vector{Float64}`: Critical point to evaluate
- `objective::Function`: Objective function f(x::Vector{Float64}) -> Float64
- `gradient_method::Symbol`: `:forwarddiff` (default) or `:finitediff`

# Returns
- `Float64`: Gradient norm ||∇f(point)||₂

# Examples
```julia
f(x) = (x[1] - 1.0)^2 + (x[2] - 2.0)^2
norm = compute_gradient_norm([1.0, 2.0], f)  # Returns ≈ 0.0

# For ODE objectives
norm = compute_gradient_norm(point, ode_func; gradient_method=:finitediff)
```
"""
function compute_gradient_norm(
    point::Vector{Float64},
    objective::Function;
    gradient_method::Symbol = :forwarddiff
)::Float64
    try
        grad = if gradient_method == :forwarddiff
            ForwardDiff.gradient(objective, point)
        elseif gradient_method == :finitediff
            FiniteDiff.finite_difference_gradient(objective, point)
        else
            error("Unknown gradient_method: $gradient_method. Use :forwarddiff or :finitediff")
        end
        return LinearAlgebra.norm(grad)
    catch e
        return Inf
    end
end

"""
    validate_critical_points(
        points::Vector{Vector{Float64}},
        objective::Function;
        tolerance::Float64 = 1e-6,
        gradient_method::Symbol = :forwarddiff
    ) -> GradientValidationResult

Validate critical points by checking if gradient norms are below tolerance.

A true critical point should satisfy ||∇f(x*)|| ≈ 0. This function computes
gradient norms and classifies points as valid (norm < tolerance) or invalid.

# Arguments
- `points::Vector{Vector{Float64}}`: Critical points to validate
- `objective::Function`: Objective function f(x::Vector{Float64}) -> Float64
- `tolerance::Float64 = 1e-6`: Maximum gradient norm for valid critical point
- `gradient_method::Symbol = :forwarddiff`: Gradient method (:forwarddiff or :finitediff)

# Returns
- `GradientValidationResult`: Validation results with norms, validity, and statistics

# Examples
```julia
f(x) = (x[1] - 1.0)^2 + (x[2] - 2.0)^2
points = [[1.0, 2.0], [1.001, 2.001], [0.5, 1.0]]

result = validate_critical_points(points, f; tolerance=1e-4)
println("Valid: ", result.n_valid, "/", length(points))
println("Norms: ", result.norms)

# For ODE objectives, use numerical gradients
result = validate_critical_points(points, ode_func; gradient_method=:finitediff)
```

# Notes
- Points with gradient norm < tolerance are classified as valid
- Points with Inf gradient norm (computation failed) are invalid
- Use stricter tolerance (e.g., 1e-8) for high-precision validation
- Use relaxed tolerance (e.g., 1e-4) for approximate validation
- Use `gradient_method=:finitediff` for ODE-based objectives
"""
function validate_critical_points(
    points::Vector{Vector{Float64}},
    objective::Function;
    tolerance::Float64 = 1e-6,
    gradient_method::Symbol = :forwarddiff
)::GradientValidationResult
    # Compute gradient norms
    norms = compute_gradient_norms(points, objective; gradient_method=gradient_method)

    # Classify points
    valid = norms .< tolerance
    n_valid = sum(valid)
    n_invalid = length(points) - n_valid

    # Compute statistics (excluding Inf values for mean)
    finite_norms = filter(isfinite, norms)
    if isempty(finite_norms)
        mean_norm = Inf
        max_norm = Inf
        min_norm = Inf
    else
        mean_norm = Statistics.mean(finite_norms)
        max_norm = maximum(finite_norms)
        min_norm = minimum(finite_norms)
    end

    return GradientValidationResult(
        norms,
        valid,
        n_valid,
        n_invalid,
        tolerance,
        mean_norm,
        max_norm,
        min_norm
    )
end

"""
    add_gradient_validation!(
        comparison_df::DataFrame,
        objective::Function;
        tolerance::Float64 = 1e-6,
        use_refined::Bool = true,
        gradient_method::Symbol = :forwarddiff
    ) -> GradientValidationResult

Add gradient validation columns to a refinement comparison DataFrame.

Extracts points from the DataFrame, computes gradient norms, and adds
new columns for gradient norm and validity.

# Arguments
- `comparison_df::DataFrame`: Refinement comparison DataFrame (from save_refined_results)
- `objective::Function`: Objective function f(x::Vector{Float64}) -> Float64
- `tolerance::Float64 = 1e-6`: Tolerance for gradient norm validation
- `use_refined::Bool = true`: Use refined points (true) or raw points (false)
- `gradient_method::Symbol = :forwarddiff`: Gradient method (:forwarddiff or :finitediff)

# Returns
- `GradientValidationResult`: Validation result summary

# Side Effects
Adds the following columns to comparison_df:
- `gradient_norm`: ||∇f(x)||₂ for each point
- `gradient_valid`: Whether point passes validation (norm < tolerance)

# Examples
```julia
# Load comparison DataFrame
df = CSV.read("refinement_comparison_deg_12.csv", DataFrame)

# Add gradient validation
result = add_gradient_validation!(df, objective_func; tolerance=1e-6)
println("Valid critical points: ", result.n_valid)

# For ODE objectives, use numerical gradients
result = add_gradient_validation!(df, ode_func; gradient_method=:finitediff)

# Save updated DataFrame
CSV.write("refinement_comparison_deg_12.csv", df)
```

# Notes
- Modifies DataFrame in place
- For refined points, uses columns named `refined_dim1`, `refined_dim2`, etc.
- For raw points, uses columns named `raw_dim1`, `raw_dim2`, etc.
- Points with NaN coordinates (failed refinement) get Inf gradient norm
- Use `gradient_method=:finitediff` for ODE-based objectives
"""
function add_gradient_validation!(
    comparison_df::DataFrame,
    objective::Function;
    tolerance::Float64 = 1e-6,
    use_refined::Bool = true,
    gradient_method::Symbol = :forwarddiff
)::GradientValidationResult
    # Determine column prefix based on whether using refined or raw points
    prefix = use_refined ? "refined_dim" : "raw_dim"

    # Find dimension columns
    dim_cols = filter(c -> startswith(String(c), prefix), names(comparison_df))
    sort!(dim_cols, by = c -> parse(Int, replace(String(c), prefix => "")))

    if isempty(dim_cols)
        error("No $(prefix)* columns found in DataFrame")
    end

    n_points = nrow(comparison_df)
    n_dims = length(dim_cols)

    # Extract points
    points = Vector{Vector{Float64}}(undef, n_points)
    for i in 1:n_points
        pt = Vector{Float64}(undef, n_dims)
        for (j, col) in enumerate(dim_cols)
            pt[j] = comparison_df[i, col]
        end
        points[i] = pt
    end

    # Compute gradient norms (handle NaN coordinates)
    norms = Vector{Float64}(undef, n_points)
    for (i, pt) in enumerate(points)
        if any(isnan, pt)
            norms[i] = Inf  # Can't compute gradient for NaN coordinates
        else
            norms[i] = compute_gradient_norm(pt, objective; gradient_method=gradient_method)
        end
    end

    # Classify points
    valid = norms .< tolerance
    n_valid = sum(valid)
    n_invalid = n_points - n_valid

    # Add columns to DataFrame
    comparison_df[!, :gradient_norm] = norms
    comparison_df[!, :gradient_valid] = valid

    # Compute statistics (excluding Inf values)
    finite_norms = filter(isfinite, norms)
    if isempty(finite_norms)
        mean_norm = Inf
        max_norm = Inf
        min_norm = Inf
    else
        mean_norm = Statistics.mean(finite_norms)
        max_norm = maximum(finite_norms)
        min_norm = minimum(finite_norms)
    end

    return GradientValidationResult(
        norms,
        valid,
        n_valid,
        n_invalid,
        tolerance,
        mean_norm,
        max_norm,
        min_norm
    )
end
