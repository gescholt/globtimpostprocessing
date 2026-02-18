"""
    Newton-Based Critical Point Refinement

Refines raw polynomial critical points to true critical points of the objective
function by solving ∇f(x) = 0 using Newton's method on the gradient.

Unlike Nelder-Mead refinement (which only finds local minima), Newton's method
on the gradient equation finds critical points of ALL types: minima, maxima,
and saddle points. This is essential for building reference sets from refinement
when analytically known critical points are not available.

Most polynomial CPs are **spurious** — they are artifacts of the polynomial
approximation, not real critical points of the objective. The refinement pipeline
uses early exit (patience) to cheaply discard spurious CPs and only spend
computational effort on promising ones.

Created: 2026-02-04
"""

# Note: ForwardDiff, FiniteDiff, LinearAlgebra, Printf are imported in main module

# ═══════════════════════════════════════════════════════════════════════════════
# Early exit — modular improvement criterion
# ═══════════════════════════════════════════════════════════════════════════════

"""
    _should_continue(iteration, best_grad_norm, initial_grad_norm;
                     patience=10, min_improvement_ratio=0.99) -> Bool

Check whether Newton refinement is making sufficient progress. Called
periodically (every `patience` iterations) to decide whether to continue
or bail early on a spurious polynomial CP.

Returns `false` (bail out) if the best gradient norm seen so far hasn't
improved by at least `(1 - min_improvement_ratio)` relative to the initial
gradient norm.

# Arguments
- `iteration`: Current Newton iteration number
- `best_grad_norm`: Best (lowest) gradient norm seen so far
- `initial_grad_norm`: Gradient norm at the starting point

# Keyword Arguments
- `patience::Int`: Check every this many iterations (default: 10)
- `min_improvement_ratio::Float64`: Bail if `best < ratio * initial` is NOT satisfied.
  Default 0.99 means: require at least 1% improvement. Very generous — only rejects
  CPs showing essentially zero progress.
"""
function _should_continue(
    iteration::Int,
    best_grad_norm::Float64,
    initial_grad_norm::Float64;
    patience::Int = 10,
    min_improvement_ratio::Float64 = 0.99,
)::Bool
    # Don't check before patience window
    if iteration < patience
        return true
    end
    # Only check at patience intervals
    if iteration % patience != 0
        return true
    end
    # Continue if gradient has improved sufficiently
    return best_grad_norm < min_improvement_ratio * initial_grad_norm
end

# ═══════════════════════════════════════════════════════════════════════════════
# Single-point refinement
# ═══════════════════════════════════════════════════════════════════════════════

"""
    CriticalPointRefinementResult

Result of refining a single point to a critical point via Newton's method on ∇f = 0.

# Fields
- `point::Vector{Float64}`: The refined critical point
- `gradient_norm::Float64`: ||∇f(point)|| at convergence
- `objective_value::Float64`: f(point) at the refined point
- `converged::Bool`: Whether Newton's method converged to tolerance
- `iterations::Int`: Number of Newton iterations performed
- `cp_type::Symbol`: Classification (`:min`, `:max`, `:saddle`, `:degenerate`, `:unknown`)
- `eigenvalues::Vector{Float64}`: Hessian eigenvalues at the refined point (empty if skipped)
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
        accept_tol::Float64 = Inf,
        f_accept_tol::Union{Nothing, Float64} = nothing,
        max_iterations::Int = 100,
        bounds = nothing,
        hessian_tol::Float64 = 1e-6,
        damping::Float64 = 1.0,
        min_damping::Float64 = 0.01,
        patience::Int = 10,
        min_improvement_ratio::Float64 = 0.99,
    ) -> CriticalPointRefinementResult

Refine a raw polynomial critical point to a true critical point of `f` by solving
`∇f(x) = 0` via damped Newton's method.

Most polynomial CPs are spurious. This function uses an early-exit mechanism
(controlled by `patience` and `min_improvement_ratio`) to cheaply reject CPs
that show no progress, avoiding wasted iterations on artifacts.

# Arguments
- `objective`: Callable objective function f(x::Vector{Float64}) -> Float64
- `initial_point::Vector{Float64}`: Starting point (raw polynomial CP)

# Keyword Arguments
- `gradient_method::Symbol`: `:forwarddiff` or `:finitediff` (default: `:finitediff`)
- `tol::Float64`: Convergence tolerance on ||∇f(x)|| (default: 1e-8)
- `accept_tol::Float64`: Relaxed acceptance tolerance on gradient norm. CPs with
  `grad_norm < accept_tol` are considered useful even if not strictly converged.
  Hessian classification is only computed for converged or accepted CPs; rejected CPs
  get `cp_type=:unknown` and empty eigenvalues, saving expensive Hessian evaluations
  on spurious CPs. (default: `Inf` = always classify)
- `f_accept_tol::Union{Nothing, Float64}`: Function-value acceptance tolerance. CPs with
  `f(x) < f_accept_tol` are accepted regardless of gradient norm. This handles ODE
  objectives where gradient norms are naturally large but a point in a flat valley near
  the minimum is scientifically useful. (default: `nothing` = disabled)
- `max_iterations::Int`: Maximum Newton iterations (default: 100)
- `bounds`: Box constraints as Vector{Tuple{Float64,Float64}}. Iterates are clamped in-domain.
- `hessian_tol::Float64`: Tolerance for Hessian eigenvalue classification (default: 1e-6)
- `damping::Float64`: Initial damping factor α ∈ (0, 1] (default: 1.0)
- `min_damping::Float64`: Minimum damping before giving up on a step (default: 0.01)
- `patience::Int`: Check for progress every this many iterations (default: 10)
- `min_improvement_ratio::Float64`: Bail if best gradient norm hasn't improved by
  this ratio of the initial (default: 0.99 = require at least 1% improvement)

# Returns
- `CriticalPointRefinementResult`: Refined point with convergence info and CP classification.
  For rejected CPs (not converged, `grad_norm >= accept_tol`, and `f(x) >= f_accept_tol`),
  `cp_type` is `:unknown` and `eigenvalues` is empty (Hessian computation skipped).
"""
function refine_to_critical_point(
    objective,
    initial_point::Vector{Float64};
    gradient_method::Symbol = :finitediff,
    tol::Float64 = 1e-8,
    accept_tol::Float64 = Inf,
    f_accept_tol::Union{Nothing, Float64} = nothing,
    max_iterations::Int = 100,
    bounds::Union{Nothing, Vector{Tuple{Float64,Float64}}} = nothing,
    hessian_tol::Float64 = 1e-6,
    damping::Float64 = 1.0,
    min_damping::Float64 = 0.01,
    patience::Int = 10,
    min_improvement_ratio::Float64 = 0.99,
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
        pt -> FiniteDiff.finite_difference_hessian(objective, pt)
    else
        error("unreachable")
    end

    # Initial gradient
    grad = compute_grad(x)
    if !all(isfinite, grad)
        # Objective blows up at this point (e.g. ODE divergence near boundary)
        return CriticalPointRefinementResult(
            x, Inf, NaN, false, 0, :unknown, Float64[], Inf,
        )
    end
    grad_norm = LinearAlgebra.norm(grad)
    initial_grad_norm = grad_norm
    best_grad_norm = grad_norm

    converged = grad_norm < tol
    iterations = 0
    early_exit = false

    while !converged && iterations < max_iterations
        iterations += 1

        # Early exit check: bail if no progress
        if !_should_continue(iterations, best_grad_norm, initial_grad_norm;
                             patience=patience, min_improvement_ratio=min_improvement_ratio)
            early_exit = true
            break
        end

        # Compute Hessian
        H = compute_hess(x)

        # Guard against Inf/NaN in Hessian (e.g. ODE blowup near domain boundary)
        if !all(isfinite, H)
            early_exit = true
            break
        end

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
        best_grad_norm = min(best_grad_norm, grad_norm)
        converged = grad_norm < tol
    end

    obj_value = objective(x)

    # Classify the result via Hessian eigenvalues — but only for useful CPs.
    # Rejected CPs (not converged, gradient above accept_tol, f(x) above f_accept_tol)
    # get :unknown classification and empty eigenvalues, saving an expensive Hessian
    # evaluation on spurious CPs.
    f_accepted = f_accept_tol !== nothing && obj_value < f_accept_tol
    is_useful = converged || grad_norm < accept_tol || f_accepted
    if is_useful
        H_final = compute_hess(x)
        if all(isfinite, H_final)
            eig_final = LinearAlgebra.eigvals(LinearAlgebra.Symmetric(H_final))
            cp_type = _classify_eigenvalues(eig_final, hessian_tol)
            eigenvalues = collect(eig_final)
        else
            cp_type = :unknown
            eigenvalues = Float64[]
        end
    else
        cp_type = :unknown
        eigenvalues = Float64[]
    end

    return CriticalPointRefinementResult(
        x, grad_norm, obj_value, converged, iterations,
        cp_type, eigenvalues, initial_grad_norm,
    )
end

# ═══════════════════════════════════════════════════════════════════════════════
# Batch refinement
# ═══════════════════════════════════════════════════════════════════════════════

"""
    refine_to_critical_points(
        objective,
        points::Vector{Vector{Float64}};
        accept_tol::Float64 = Inf,
        f_accept_tol::Union{Nothing, Float64} = nothing,
        kwargs...
    ) -> Vector{CriticalPointRefinementResult}

Batch version of [`refine_to_critical_point`](@ref). Refines each point independently.

Prints a one-line summary per CP with 4-way status:
- `converged` — gradient norm below strict tolerance
- `accepted`  — gradient norm below relaxed `accept_tol` (useful CP, Hessian computed)
- `accepted*` — function value below `f_accept_tol` (valley CP, Hessian computed)
- `rejected`  — spurious CP (Hessian skipped, `cp_type=:unknown`)

Lines show ↓/↑ arrows indicating gradient improvement direction, and ETA is shown
inline every 5 CPs during long runs. A summary line follows the per-CP output.

# Returns
- `Vector{CriticalPointRefinementResult}`: One result per input point.
"""
function refine_to_critical_points(
    objective,
    points::Vector{Vector{Float64}};
    accept_tol::Float64 = Inf,
    f_accept_tol::Union{Nothing, Float64} = nothing,
    kwargs...
)::Vector{CriticalPointRefinementResult}
    n_pts = length(points)
    results = Vector{CriticalPointRefinementResult}(undef, n_pts)
    t_total = time()
    cumulative_time = 0.0

    for (i, pt) in enumerate(points)
        t_start = time()
        results[i] = refine_to_critical_point(objective, pt;
            accept_tol=accept_tol, f_accept_tol=f_accept_tol, kwargs...)
        r = results[i]
        elapsed = time() - t_start
        cumulative_time += elapsed

        # 4-way status label
        is_f_accepted = f_accept_tol !== nothing && r.objective_value < f_accept_tol
        status = if r.converged
            "converged"
        elseif r.gradient_norm < accept_tol
            "accepted "
        elseif is_f_accepted
            "accepted*"
        else
            "rejected "
        end

        # Gradient direction arrow
        arrow = r.gradient_norm <= r.initial_gradient_norm ? "↓" : "↑"

        # CP type — show for any accepted CP (meaningful classification)
        is_useful = r.converged || r.gradient_norm < accept_tol || is_f_accepted
        type_str = is_useful ? "  ($(r.cp_type))" : ""

        # Annotation for f-accepted CPs
        f_str = is_f_accepted && !r.converged && r.gradient_norm >= accept_tol ?
            @sprintf("  f<%.0e", f_accept_tol) : ""

        # ETA — show inline every 5th CP (after at least 5 have run)
        eta_str = ""
        if i >= 5 && i % 5 == 0 && i < n_pts
            avg_time = cumulative_time / i
            remaining = avg_time * (n_pts - i)
            if remaining >= 60
                eta_str = @sprintf("  [ETA: ~%.0fm]", remaining / 60)
            elseif remaining >= 5
                eta_str = @sprintf("  [ETA: ~%.0fs]", remaining)
            end
        end

        @printf("    CP %2d/%d: %s %3d iters (%5.1fs)  |∇f| %.2e %s %.2e  f=%.2e%s%s%s\n",
            i, n_pts, status,
            r.iterations, elapsed, r.initial_gradient_norm, arrow, r.gradient_norm,
            r.objective_value, type_str, f_str, eta_str)
    end

    # Summary line
    n_conv = count(r -> r.converged, results)
    n_grad_accepted = count(r -> !r.converged && r.gradient_norm < accept_tol, results)
    n_f_accepted = count(r -> !r.converged && r.gradient_norm >= accept_tol &&
                         f_accept_tol !== nothing && r.objective_value < f_accept_tol, results)
    n_rejected = n_pts - n_conv - n_grad_accepted - n_f_accepted
    println()
    if f_accept_tol !== nothing && n_f_accepted > 0
        @printf("    %d converged, %d grad-accepted, %d f-accepted (f<%.0e), %d rejected in %.1fs\n",
            n_conv, n_grad_accepted, n_f_accepted, f_accept_tol, n_rejected, time() - t_total)
    else
        @printf("    %d converged, %d accepted, %d rejected in %.1fs\n",
            n_conv, n_grad_accepted + n_f_accepted, n_rejected, time() - t_total)
    end
    return results
end

# ═══════════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════════

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
