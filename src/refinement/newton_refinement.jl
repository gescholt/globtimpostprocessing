"""
    Newton-Based Critical Point Refinement

Refines raw polynomial critical points to true critical points of the objective
function by solving ∇f(x) = 0 using Newton's method on the gradient.

Unlike Nelder-Mead refinement (which only finds local minima), Newton's method
on the gradient equation finds critical points of ALL types: minima, maxima,
and saddle points. This is essential for building reference sets from refinement
when analytically known critical points are not available.

Created: 2026-02-04
"""

# Note: ForwardDiff, FiniteDiff, LinearAlgebra are imported in main module

"""
    CriticalPointRefinementResult

Result of refining a single point to a critical point via Newton's method on ∇f = 0.

# Fields
- `point::Vector{Float64}`: The refined critical point
- `gradient_norm::Float64`: ||∇f(point)|| at convergence
- `objective_value::Float64`: f(point) at the refined point
- `converged::Bool`: Whether Newton's method converged to tolerance
- `iterations::Int`: Number of Newton iterations performed
- `cp_type::Symbol`: Classification (`:min`, `:max`, `:saddle`, `:degenerate`)
- `eigenvalues::Vector{Float64}`: Hessian eigenvalues at the refined point
- `initial_gradient_norm::Float64`: ||∇f|| at the starting point (for diagnostics)
"""
struct CriticalPointRefinementResult
    point::Vector{Float64}
    gradient_norm::Float64
    objective_value::Float64
    converged::Bool
    iterations::Int
    cp_type::Symbol
    eigenvalues::Vector{Float64}
    initial_gradient_norm::Float64
end

"""
    refine_to_critical_point(
        objective,
        initial_point::Vector{Float64};
        gradient_method::Symbol = :finitediff,
        tol::Float64 = 1e-8,
        max_iterations::Int = 100,
        bounds::Union{Nothing, Vector{Tuple{Float64,Float64}}} = nothing,
        hessian_tol::Float64 = 1e-6,
        damping::Float64 = 1.0,
        min_damping::Float64 = 0.01,
    ) -> CriticalPointRefinementResult

Refine a raw polynomial critical point to a true critical point of `f` by solving
`∇f(x) = 0` via damped Newton's method.

Newton's method iterates: `x_{k+1} = x_k - α * H(x_k)^{-1} * ∇f(x_k)`
where H is the Hessian and α is a damping factor.

Unlike Nelder-Mead (which only finds minima), this finds critical points of
**all types**: minima, maxima, and saddle points.

# Arguments
- `objective`: Callable objective function f(x::Vector{Float64}) -> Float64
- `initial_point::Vector{Float64}`: Starting point (raw polynomial CP)

# Keyword Arguments
- `gradient_method::Symbol`: `:forwarddiff` or `:finitediff` (default: `:finitediff` for ODE compatibility)
- `tol::Float64`: Convergence tolerance on ||∇f(x)|| (default: 1e-8)
- `max_iterations::Int`: Maximum Newton iterations (default: 100)
- `bounds`: Box constraints as Vector{Tuple{Float64,Float64}}. If provided, iterates are clamped to stay in-domain.
- `hessian_tol::Float64`: Tolerance for Hessian eigenvalue classification (default: 1e-6)
- `damping::Float64`: Initial damping factor α ∈ (0, 1] (default: 1.0 = undamped Newton)
- `min_damping::Float64`: Minimum damping before giving up on a step (default: 0.01)

# Returns
- `CriticalPointRefinementResult`: Refined point with convergence info and CP classification.

# Algorithm
Uses damped Newton's method with the following safeguards:
1. If the Hessian is singular or near-singular, uses a regularized pseudo-inverse
2. If a full Newton step increases ||∇f||, the damping factor is halved until
   the step reduces the gradient norm or `min_damping` is reached
3. Iterates are clamped to box constraints if provided

# Example
```julia
f(x) = (x[1]^2 + x[2]^2 - 1)^2 + x[1]^2  # has saddle points
result = refine_to_critical_point(f, [0.5, 0.8]; gradient_method=:forwarddiff)
result.cp_type  # :min, :saddle, etc.
result.converged  # true/false
```
"""
function refine_to_critical_point(
    objective,
    initial_point::Vector{Float64};
    gradient_method::Symbol = :finitediff,
    tol::Float64 = 1e-8,
    max_iterations::Int = 100,
    bounds::Union{Nothing, Vector{Tuple{Float64,Float64}}} = nothing,
    hessian_tol::Float64 = 1e-6,
    damping::Float64 = 1.0,
    min_damping::Float64 = 0.01,
)::CriticalPointRefinementResult

    n = length(initial_point)
    x = copy(initial_point)

    # Unpack bounds for internal clamping
    lb, ub = split_bounds(bounds)

    0.0 < damping <= 1.0 || error("damping must be in (0, 1], got $damping")
    0.0 < min_damping <= damping || error("min_damping must be in (0, damping], got $min_damping")

    # Gradient computation dispatch
    compute_grad = if gradient_method == :forwarddiff
        pt -> ForwardDiff.gradient(objective, pt)
    elseif gradient_method == :finitediff
        pt -> FiniteDiff.finite_difference_gradient(objective, pt)
    else
        error("Unknown gradient_method: $gradient_method. Use :forwarddiff or :finitediff")
    end

    # Hessian computation dispatch
    compute_hess = if gradient_method == :forwarddiff
        pt -> ForwardDiff.hessian(objective, pt)
    elseif gradient_method == :finitediff
        # Finite-difference Hessian from finite-difference gradient
        pt -> FiniteDiff.finite_difference_hessian(objective, pt)
    else
        error("unreachable")
    end

    # Initial gradient
    grad = compute_grad(x)
    grad_norm = LinearAlgebra.norm(grad)
    initial_grad_norm = grad_norm

    converged = grad_norm < tol
    iterations = 0

    while !converged && iterations < max_iterations
        iterations += 1

        # Compute Hessian
        H = compute_hess(x)
        H_sym = LinearAlgebra.Symmetric(H)

        # Solve Newton step: H * step = -grad
        # Use eigen-decomposition for robustness (handles singular/near-singular H)
        eig = LinearAlgebra.eigen(H_sym)
        eigenvalues = eig.values
        V = eig.vectors

        # Regularized pseudo-inverse: skip directions with tiny eigenvalues
        abs_max_eig = maximum(abs, eigenvalues)
        reg_threshold = max(1e-12, 1e-10 * abs_max_eig)

        # Compute step in eigenbasis: step = -V * diag(1/λ_i) * V' * grad
        # (skip eigenvalues below threshold)
        Vt_grad = V' * grad
        step = zeros(n)
        for i in 1:n
            if abs(eigenvalues[i]) > reg_threshold
                step .-= (Vt_grad[i] / eigenvalues[i]) .* V[:, i]
            end
        end

        # Damped line search: ensure step reduces ||∇f||
        α = damping
        x_new = x .+ α .* step
        _clamp_to_bounds!(x_new, lb, ub)
        grad_new = compute_grad(x_new)
        grad_norm_new = LinearAlgebra.norm(grad_new)

        while grad_norm_new > grad_norm && α > min_damping
            α *= 0.5
            x_new = x .+ α .* step
            _clamp_to_bounds!(x_new, lb, ub)
            grad_new = compute_grad(x_new)
            grad_norm_new = LinearAlgebra.norm(grad_new)
        end

        x = x_new
        grad = grad_new
        grad_norm = grad_norm_new
        converged = grad_norm < tol
    end

    # Classify the result via Hessian eigenvalues
    H_final = compute_hess(x)
    eig_final = LinearAlgebra.eigvals(LinearAlgebra.Symmetric(H_final))
    cp_type = _classify_eigenvalues(eig_final, hessian_tol)

    obj_value = objective(x)

    return CriticalPointRefinementResult(
        x, grad_norm, obj_value, converged, iterations,
        cp_type, collect(eig_final), initial_grad_norm,
    )
end

"""
    refine_to_critical_points(
        objective,
        points::Vector{Vector{Float64}};
        kwargs...
    ) -> Vector{CriticalPointRefinementResult}

Batch version of [`refine_to_critical_point`](@ref). Refines each point independently.

# Arguments
- `objective`: Callable objective function f(x::Vector{Float64}) -> Float64
- `points::Vector{Vector{Float64}}`: Raw polynomial critical points

All keyword arguments are forwarded to `refine_to_critical_point`.

# Returns
- `Vector{CriticalPointRefinementResult}`: One result per input point.
"""
function refine_to_critical_points(
    objective,
    points::Vector{Vector{Float64}};
    kwargs...
)::Vector{CriticalPointRefinementResult}
    results = Vector{CriticalPointRefinementResult}(undef, length(points))
    for (i, pt) in enumerate(points)
        results[i] = refine_to_critical_point(objective, pt; kwargs...)
    end
    return results
end

"""
    _clamp_to_bounds!(x, lower_bounds, upper_bounds)

Clamp `x` in-place to box constraints. No-op if bounds are `nothing`.
"""
function _clamp_to_bounds!(
    x::Vector{Float64},
    lower_bounds::Union{Nothing, Vector{Float64}},
    upper_bounds::Union{Nothing, Vector{Float64}},
)
    if lower_bounds !== nothing
        for i in eachindex(x)
            x[i] = max(x[i], lower_bounds[i])
        end
    end
    if upper_bounds !== nothing
        for i in eachindex(x)
            x[i] = min(x[i], upper_bounds[i])
        end
    end
    return x
end

"""
    _classify_eigenvalues(eigenvalues, tol) -> Symbol

Classify a critical point based on Hessian eigenvalues.
Returns `:min`, `:max`, `:saddle`, or `:degenerate`.
"""
function _classify_eigenvalues(eigenvalues::AbstractVector{<:Real}, tol::Float64)::Symbol
    n_pos = count(λ -> λ > tol, eigenvalues)
    n_neg = count(λ -> λ < -tol, eigenvalues)
    n_zero = count(λ -> abs(λ) <= tol, eigenvalues)

    if n_zero > 0
        return :degenerate
    elseif n_pos == length(eigenvalues)
        return :min
    elseif n_neg == length(eigenvalues)
        return :max
    else
        return :saddle
    end
end
