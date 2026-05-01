"""
    CPVerification

Level 0 oracle utilities for verifying critical points.

This module provides independent verification of critical points using
ForwardDiff for exact (AD) gradients and Hessians, plus neighborhood
sampling. It is the foundation for all higher-level verification tests.

Functions:
- verify_critical_point(f, x; grad_tol) — gradient norm check (0a)
- classify_by_hessian(f, x; tol) — Hessian eigendecomposition (0b)
- verify_local_minimum(f, x; radius, n_samples) — neighborhood sampling (0c)
- verify_and_classify(f, x; ...) — combined verification (0d)
- find_all_critical_points(f, bounds, dim; ...) — multi-start discovery (0e)
"""
module CPVerification

using ForwardDiff
using LinearAlgebra

export verify_critical_point,
    classify_by_hessian,
    verify_local_minimum,
    verify_and_classify,
    find_all_critical_points,
    VerifiedCP

# ============================================================================
# VerifiedCP struct
# ============================================================================

"""
    VerifiedCP

A verified critical point with full characterization.

Fields:
- `point::Vector{Float64}` — location in parameter space
- `classification::Symbol` — :minimum, :maximum, :saddle, or :degenerate
- `value::Float64` — objective function value f(point)
- `grad_norm::Float64` — ‖∇f(point)‖
- `eigenvalues::Vector{Float64}` — Hessian eigenvalues (sorted)
- `neighborhood_confirmed::Bool` — whether neighborhood sampling confirms classification
"""
Base.@kwdef struct VerifiedCP
    point::Vector{Float64}
    classification::Symbol
    value::Float64
    grad_norm::Float64
    eigenvalues::Vector{Float64}
    neighborhood_confirmed::Bool
end

# ============================================================================
# 0a: verify_critical_point
# ============================================================================

"""
    verify_critical_point(f, x; grad_tol=1e-8) -> Bool

Check whether `x` is a critical point of `f` by computing the gradient
via ForwardDiff and checking ‖∇f(x)‖ < grad_tol.
"""
function verify_critical_point(f, x::AbstractVector; grad_tol::Float64 = 1e-8)
    g = ForwardDiff.gradient(f, x)
    return norm(g) < grad_tol
end

# ============================================================================
# 0b: classify_by_hessian
# ============================================================================

"""
    classify_by_hessian(f, x; tol=1e-6) -> Symbol

Classify a point by the eigenvalues of the Hessian of `f` at `x`.

Returns:
- `:minimum` — all eigenvalues > tol
- `:maximum` — all eigenvalues < -tol
- `:saddle` — mixed signs (some > tol, some < -tol)
- `:degenerate` — at least one eigenvalue with |λ| ≤ tol
"""
function classify_by_hessian(f, x::AbstractVector; tol::Float64 = 1e-6)
    H = ForwardDiff.hessian(f, x)
    eigenvalues = sort(real.(eigvals(H)))
    return _classify_eigenvalues(eigenvalues, tol)
end

"""
    _classify_eigenvalues(eigenvalues, tol) -> Symbol

Internal: classify based on sorted eigenvalues.
"""
function _classify_eigenvalues(eigenvalues::AbstractVector, tol::Real)
    has_positive = any(λ -> λ > tol, eigenvalues)
    has_negative = any(λ -> λ < -tol, eigenvalues)
    has_zero = any(λ -> abs(λ) ≤ tol, eigenvalues)

    if has_zero
        return :degenerate
    elseif has_positive && has_negative
        return :saddle
    elseif has_positive
        return :minimum
    elseif has_negative
        return :maximum
    else
        # All eigenvalues exactly zero (within tol) — degenerate
        return :degenerate
    end
end

# ============================================================================
# 0c: verify_local_minimum
# ============================================================================

"""
    verify_local_minimum(f, x; radius=1e-4, n_samples=1000) -> Bool

Verify that `x` is a local minimum by sampling `n_samples` random points
in a ball of given `radius` around `x` and checking that f(x) ≤ f(y)
for all sampled points y.
"""
function verify_local_minimum(
    f,
    x::AbstractVector;
    radius::Float64 = 1e-4,
    n_samples::Int = 1000,
)
    f_x = f(x)
    dim = length(x)

    for _ in 1:n_samples
        # Sample uniformly from the ball of given radius
        direction = randn(dim)
        direction ./= norm(direction)
        r = radius * rand()^(1/dim)  # uniform in ball
        y = x .+ r .* direction
        f_y = f(y)

        if f_y < f_x - eps(Float64) * max(1.0, abs(f_x))
            return false
        end
    end

    return true
end

# ============================================================================
# 0d: verify_and_classify
# ============================================================================

"""
    verify_and_classify(f, x; grad_tol=1e-8, hessian_tol=1e-6,
                        radius=1e-4, n_samples=1000) -> NamedTuple

Combined verification and classification of point `x` for function `f`.

Returns a NamedTuple with fields:
- `is_critical::Bool` — whether ‖∇f(x)‖ < grad_tol
- `classification::Symbol` — :minimum/:maximum/:saddle/:degenerate
- `grad_norm::Float64` — ‖∇f(x)‖
- `eigenvalues::Vector{Float64}` — sorted Hessian eigenvalues
- `neighborhood_confirmed::Bool` — sampling confirms local minimum
- `value::Float64` — f(x)
"""
function verify_and_classify(
    f,
    x::AbstractVector;
    grad_tol::Float64 = 1e-8,
    hessian_tol::Float64 = 1e-6,
    radius::Float64 = 1e-4,
    n_samples::Int = 1000,
)
    # Compute gradient
    g = ForwardDiff.gradient(f, x)
    grad_norm = norm(g)
    is_critical = grad_norm < grad_tol

    # Compute Hessian and classify
    H = ForwardDiff.hessian(f, x)
    eigenvalues = sort(real.(eigvals(H)))
    classification = _classify_eigenvalues(eigenvalues, hessian_tol)

    # Neighborhood sampling (only meaningful if actually near a minimum)
    neighborhood_confirmed =
        verify_local_minimum(f, x; radius = radius, n_samples = n_samples)

    value = f(x)

    return (
        is_critical = is_critical,
        classification = classification,
        grad_norm = grad_norm,
        eigenvalues = eigenvalues,
        neighborhood_confirmed = neighborhood_confirmed,
        value = value,
    )
end

# ============================================================================
# 0e: find_all_critical_points
# ============================================================================

"""
    find_all_critical_points(f, bounds, dim; n_starts=200, method=:newton,
                              grad_tol=1e-8, hessian_tol=1e-6,
                              dedup_tol=1e-4, max_iter=1000) -> Vector{VerifiedCP}

Find critical points of `f` via multi-start optimization of ‖∇f‖².

Each random start point is refined by minimizing g(x) = ‖∇f(x)‖² using
a simple gradient descent on g (which uses second-order info of f via
ForwardDiff). Points where ‖∇f‖ < grad_tol are kept, classified, and
deduplicated.

Arguments:
- `f` — objective function f: ℝⁿ → ℝ
- `bounds` — vector of (lo, hi) tuples, one per dimension
- `dim` — problem dimension
- `n_starts` — number of random starting points
- `method` — :newton (minimizes ‖∇f‖² via ForwardDiff)
- `grad_tol` — tolerance for ‖∇f(x)‖ to accept as critical
- `hessian_tol` — tolerance for eigenvalue classification
- `dedup_tol` — Euclidean distance for deduplication
- `max_iter` — max iterations for each refinement
"""
function find_all_critical_points(
    f,
    bounds::Vector{<:Tuple},
    dim::Int;
    n_starts::Int = 200,
    method::Symbol = :newton,
    grad_tol::Float64 = 1e-8,
    hessian_tol::Float64 = 1e-6,
    dedup_tol::Float64 = 1e-4,
    max_iter::Int = 1000,
)
    # Validate inputs
    length(bounds) == dim || error("bounds must have $dim entries, got $(length(bounds))")

    # The function we minimize: g(x) = ‖∇f(x)‖²
    # Critical points of f are global minima of g (where g = 0)
    grad_f(x) = ForwardDiff.gradient(f, x)
    g(x) = sum(abs2, grad_f(x))

    raw_critical_points = Vector{VerifiedCP}()

    for _ in 1:n_starts
        # Random start within bounds
        x0 = [lo + rand() * (hi - lo) for (lo, hi) in bounds]

        # Solve ∇f = 0 via Newton with gradient descent fallback
        x = _minimize_grad_norm_squared(g, x0, bounds, max_iter, grad_tol; f = f)

        # Check if we found a critical point of f
        gf = grad_f(x)
        gn = norm(gf)

        if gn < grad_tol
            # Classify
            H = ForwardDiff.hessian(f, x)
            eigenvalues = sort(real.(eigvals(H)))
            classification = _classify_eigenvalues(eigenvalues, hessian_tol)
            fval = f(x)
            neighborhood_confirmed =
                verify_local_minimum(f, x; radius = 1e-4, n_samples = 500)

            push!(
                raw_critical_points,
                VerifiedCP(
                    point = x,
                    classification = classification,
                    value = fval,
                    grad_norm = gn,
                    eigenvalues = eigenvalues,
                    neighborhood_confirmed = neighborhood_confirmed,
                ),
            )
        end
    end

    # Deduplicate
    return _deduplicate_cps(raw_critical_points, dedup_tol)
end

"""
    _minimize_grad_norm_squared(g, x0, bounds, max_iter, tol; f=nothing)

Find a critical point of `f` by solving ∇f(x) = 0 using Newton's method
with fallback to gradient descent on g(x) = ‖∇f(x)‖².

When `f` is provided, uses Newton's method: x_{k+1} = x_k - H⁻¹ ∇f(x_k)
with backtracking line search on g. Falls back to gradient descent on g
when the Hessian is singular.
"""
function _minimize_grad_norm_squared(
    g,
    x0::Vector{Float64},
    bounds::Vector{<:Tuple},
    max_iter::Int,
    tol::Float64;
    f = nothing,
)
    x = copy(x0)
    target = tol^2  # g = ‖∇f‖², so g < tol² means ‖∇f‖ < tol
    dim = length(x)

    β = 0.5       # backtracking factor
    min_α = 1e-15

    for _ in 1:max_iter
        gval = g(x)
        if gval < target
            break
        end

        # Try Newton step on ∇f = 0 if f is available
        step = nothing
        if f !== nothing
            try
                grad = ForwardDiff.gradient(f, x)
                H = ForwardDiff.hessian(f, x)
                # Use damped solve to handle near-singular Hessians
                F = lu(H; check = false)
                if issuccess(F)
                    newton_step = F \ grad
                    if norm(newton_step) < 100 * norm(x .+ 1)  # sanity check
                        step = newton_step
                    end
                end
            catch
                # Hessian computation failed — fall through to gradient descent
            end
        end

        # Fall back to gradient descent on g if Newton failed
        if step === nothing
            dg = ForwardDiff.gradient(g, x)
            dg_norm = norm(dg)
            if dg_norm < 1e-16
                break  # stuck
            end
            # Normalize and use adaptive step size
            step = dg ./ dg_norm * min(0.1, sqrt(gval))
        end

        # Backtracking line search on g
        α = 1.0
        x_new = x .- α .* step
        _clamp_to_bounds!(x_new, bounds)

        while g(x_new) >= gval && α > min_α
            α *= β
            x_new .= x .- α .* step
            _clamp_to_bounds!(x_new, bounds)
        end

        if α ≤ min_α
            break  # line search failed
        end

        x .= x_new
    end

    return x
end

"""
    _clamp_to_bounds!(x, bounds)

Clamp each component of `x` to its corresponding bounds.
"""
function _clamp_to_bounds!(x::Vector{Float64}, bounds::Vector{<:Tuple})
    for i in eachindex(x)
        lo, hi = bounds[i]
        x[i] = clamp(x[i], lo, hi)
    end
    return x
end

"""
    _deduplicate_cps(cps, tol)

Remove duplicate critical points: keep the one with smallest grad_norm
from each cluster of points within `tol` Euclidean distance.
"""
function _deduplicate_cps(cps::Vector{VerifiedCP}, tol::Float64)
    isempty(cps) && return cps

    # Sort by grad_norm (keep best representatives)
    sorted = sort(cps, by = cp -> cp.grad_norm)
    unique_cps = VerifiedCP[]

    for cp in sorted
        is_duplicate = false
        for existing in unique_cps
            if norm(cp.point - existing.point) < tol
                is_duplicate = true
                break
            end
        end
        if !is_duplicate
            push!(unique_cps, cp)
        end
    end

    return unique_cps
end

end  # module CPVerification
