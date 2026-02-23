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
- `final_trust_radius::Float64`: Trust-region radius Δ at termination (NaN if not applicable)
- `rejected_steps::Int`: Number of trust-region step rejections (ρ < 0)
- `f_safeguard_count::Int`: Number of times the f-value safeguard prevented a plateau jump
- `trace::Vector{Vector{Float64}}`: Iteration trajectory (empty unless `trace=true` was passed)
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
    final_trust_radius::Float64
    rejected_steps::Int
    f_safeguard_count::Int
    trace::Vector{Vector{Float64}}
end

# Backward-compatible constructor: existing callers pass 11 positional args (pre-trace)
function CriticalPointRefinementResult(
    point::Vector{Float64}, gradient_norm::Float64, objective_value::Float64,
    converged::Bool, iterations::Int, cp_type::Symbol,
    eigenvalues::Vector{Float64}, initial_gradient_norm::Float64,
    final_trust_radius::Float64, rejected_steps::Int, f_safeguard_count::Int,
)
    CriticalPointRefinementResult(
        point, gradient_norm, objective_value, converged, iterations,
        cp_type, eigenvalues, initial_gradient_norm,
        final_trust_radius, rejected_steps, f_safeguard_count, Vector{Float64}[],
    )
end

# Backward-compatible constructor: existing callers pass 8 positional args
function CriticalPointRefinementResult(
    point::Vector{Float64}, gradient_norm::Float64, objective_value::Float64,
    converged::Bool, iterations::Int, cp_type::Symbol,
    eigenvalues::Vector{Float64}, initial_gradient_norm::Float64,
)
    CriticalPointRefinementResult(
        point, gradient_norm, objective_value, converged, iterations,
        cp_type, eigenvalues, initial_gradient_norm, NaN, 0, 0, Vector{Float64}[],
    )
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
        trust_radius_fraction::Float64 = 0.1,
        trust_expand::Float64 = 2.0,
        trust_shrink::Float64 = 0.25,
        max_f_increase_factor::Float64 = 10.0,
        patience::Int = 10,
        min_improvement_ratio::Float64 = 0.99,
    ) -> CriticalPointRefinementResult

Refine a raw polynomial critical point to a true critical point of `f` by solving
`∇f(x) = 0` via trust-region Newton's method.

The Newton step `H⁻¹∇f` is computed via eigendecomposition (robust to singular Hessians),
then clipped to a trust-region radius Δ. The trust region expands when steps are productive
(good agreement between the quadratic model and actual ‖∇f‖² reduction) and shrinks when
steps are unproductive. An objective-value safeguard prevents steps that jump to flat
plateaus far from the current basin.

Most polynomial CPs are spurious. The early-exit mechanism (controlled by `patience` and
`min_improvement_ratio`) cheaply rejects CPs that show no progress.

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
- `trust_radius_fraction::Float64`: Initial trust-region radius as fraction of domain
  diameter (default: 0.1). For a [0,100]² domain (diameter ≈ 141), Δ₀ ≈ 14.
- `trust_expand::Float64`: Factor to expand Δ when ρ > 0.75 (default: 2.0)
- `trust_shrink::Float64`: Factor to shrink Δ when ρ < 0.25 or step rejected (default: 0.25)
- `max_f_increase_factor::Float64`: Reject step if f(x_new) > factor × max(|f(x)|, 1).
  Prevents jumps from a narrow well to a flat plateau. (default: 10.0)
- `patience::Int`: Check for progress every this many iterations (default: 10)
- `min_improvement_ratio::Float64`: Bail if best gradient norm hasn't improved by
  this ratio of the initial (default: 0.99 = require at least 1% improvement)

# Returns
- `CriticalPointRefinementResult`: Refined point with convergence info, CP classification,
  and trust-region diagnostics (final Δ, rejected step count, f-safeguard count).
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
    trust_radius_fraction::Float64 = 0.1,
    trust_expand::Float64 = 2.0,
    trust_shrink::Float64 = 0.25,
    max_f_increase_factor::Float64 = 10.0,
    patience::Int = 10,
    min_improvement_ratio::Float64 = 0.99,
    trace::Bool = false,
)::CriticalPointRefinementResult

    n = length(initial_point)
    x = copy(initial_point)

    # Trajectory recording: collect accepted iterates when trace=true
    trace_points = trace ? [copy(x)] : Vector{Float64}[]

    # Unpack bounds for internal clamping
    lb, ub = split_bounds(bounds)

    # Validate trust-region parameters
    0.0 < trust_radius_fraction <= 1.0 || error("trust_radius_fraction must be in (0, 1], got $trust_radius_fraction")
    trust_expand > 1.0 || error("trust_expand must be > 1, got $trust_expand")
    0.0 < trust_shrink < 1.0 || error("trust_shrink must be in (0, 1), got $trust_shrink")
    max_f_increase_factor > 1.0 || error("max_f_increase_factor must be > 1, got $max_f_increase_factor")

    # Trust-region radius: fraction of domain diameter (or 1.0 if no bounds)
    domain_diameter = if lb !== nothing && ub !== nothing
        LinearAlgebra.norm(ub .- lb)
    else
        1.0  # dimensionless fallback when no bounds provided
    end
    Δ = trust_radius_fraction * domain_diameter
    Δ_min = 1e-15 * domain_diameter  # floor to prevent Δ → 0

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

    # Initial gradient and objective value
    grad = compute_grad(x)
    if !all(isfinite, grad)
        return CriticalPointRefinementResult(
            x, Inf, NaN, false, 0, :unknown, Float64[], Inf, Δ, 0, 0,
        )
    end
    grad_norm = LinearAlgebra.norm(grad)
    initial_grad_norm = grad_norm
    best_grad_norm = grad_norm
    f_current = objective(x)  # needed for f-value safeguard

    converged = grad_norm < tol
    iterations = 0
    rejected_steps = 0
    f_safeguard_count = 0
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

        # Compute full Newton step in eigenbasis: step = -V * diag(1/λ_i) * V' * grad
        Vt_grad = V' * grad
        step = zeros(n)
        for i in 1:n
            if abs(eigenvalues[i]) > reg_threshold
                step .-= (Vt_grad[i] / eigenvalues[i]) .* V[:, i]
            end
        end

        # Trust-region clipping: if ||step|| > Δ, scale to trust boundary
        step_norm = LinearAlgebra.norm(step)
        if step_norm > Δ
            step .*= (Δ / step_norm)
            step_norm = Δ
        end

        # Trial point
        x_trial = x .+ step
        _clamp_to_bounds!(x_trial, lb, ub)
        grad_trial = compute_grad(x_trial)

        if !all(isfinite, grad_trial)
            # ODE blowup at trial point — reject step, shrink trust region
            Δ = max(Δ * trust_shrink, Δ_min)
            rejected_steps += 1
            continue
        end

        grad_norm_trial = LinearAlgebra.norm(grad_trial)
        f_trial = objective(x_trial)

        # Objective-value safeguard: reject step if f jumps to a plateau
        f_threshold = max_f_increase_factor * max(abs(f_current), 1.0)
        if isfinite(f_trial) && isfinite(f_current) && f_trial > f_threshold
            Δ = max(Δ * trust_shrink, Δ_min)
            rejected_steps += 1
            f_safeguard_count += 1
            continue
        end

        # Quality ratio: ρ = (actual reduction in ||∇f||²) / (predicted reduction)
        # Predicted reduction from quadratic model: ||g||² - ||g + H*s||²
        Hs = H_sym * step
        predicted_grad_after = grad .+ Hs
        actual_reduction   = grad_norm^2 - grad_norm_trial^2
        predicted_reduction = grad_norm^2 - LinearAlgebra.norm(predicted_grad_after)^2

        ρ = if abs(predicted_reduction) < 1e-30
            # Predicted reduction ≈ 0: model is flat here, accept if actual improved
            actual_reduction > 0 ? 1.0 : 0.0
        else
            actual_reduction / predicted_reduction
        end

        # Step acceptance/rejection
        if ρ > 0
            # Accept step
            x = x_trial
            grad = grad_trial
            grad_norm = grad_norm_trial
            f_current = f_trial
            best_grad_norm = min(best_grad_norm, grad_norm)
            converged = grad_norm < tol
            trace && push!(trace_points, copy(x))
        else
            # Reject step — x, grad, f_current unchanged
            rejected_steps += 1
        end

        # Trust-region radius update
        if ρ > 0.75
            Δ = min(Δ * trust_expand, domain_diameter)
        elseif ρ < 0.25
            Δ = max(Δ * trust_shrink, Δ_min)
        end
        # else: Δ unchanged (0.25 ≤ ρ ≤ 0.75)
    end

    obj_value = f_current  # already tracked during iteration

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
        cp_type, eigenvalues, initial_grad_norm, Δ, rejected_steps, f_safeguard_count,
        trace_points,
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

Batch version of [`refine_to_critical_point`](@ref). Refines each point independently
using trust-region Newton.

Output is designed for large batches where most CPs are spurious:
- **Accepted/converged CPs** are printed immediately with trust-region diagnostics
- **Rejected CPs** are silent; a compact progress line updates every 20 CPs
- A final summary shows totals including trust-region rejection and f-safeguard counts

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

    # Running counters for progress display
    n_conv = 0
    n_accepted = 0
    n_rejected = 0
    total_tr_rejections = 0
    total_f_safeguards = 0

    for (i, pt) in enumerate(points)
        t_start = time()
        results[i] = refine_to_critical_point(objective, pt;
            accept_tol=accept_tol, f_accept_tol=f_accept_tol, kwargs...)
        r = results[i]
        elapsed = time() - t_start
        cumulative_time += elapsed
        total_tr_rejections += r.rejected_steps
        total_f_safeguards += r.f_safeguard_count

        # Classify result
        is_f_accepted = f_accept_tol !== nothing && r.objective_value < f_accept_tol
        is_useful = r.converged || r.gradient_norm < accept_tol || is_f_accepted

        if r.converged
            n_conv += 1
        elseif is_useful
            n_accepted += 1
        else
            n_rejected += 1
        end

        # Print accepted/converged CPs immediately (these are rare and informative)
        if is_useful
            status = if r.converged
                "converged"
            elseif r.gradient_norm < accept_tol
                "accepted "
            else
                "accepted*"
            end
            # Trust-region diagnostics: rejected steps and f-safeguard
            tr_parts = String[]
            r.rejected_steps > 0 && push!(tr_parts, "$(r.rejected_steps) rej")
            r.f_safeguard_count > 0 && push!(tr_parts, "f-guard")
            tr_str = isempty(tr_parts) ? "" : " ($(join(tr_parts, ", ")))"

            f_str = is_f_accepted && !r.converged && r.gradient_norm >= accept_tol ?
                @sprintf("  f<%.0e", f_accept_tol) : ""
            @printf("    ✓ CP %d/%d: %s %3d iters%s (%4.1fs)  |∇f| %.2e  f=%.2e  Δ=%.2e  (%s)%s\n",
                i, n_pts, status, r.iterations, tr_str, elapsed,
                r.gradient_norm, r.objective_value,
                r.final_trust_radius, r.cp_type, f_str)
        end

        # Progress line — overwrite in-place (every 20 CPs or at the end)
        if !is_useful && (i % 20 == 0 || i == n_pts)
            avg_time = cumulative_time / i
            remaining = avg_time * (n_pts - i)
            eta_str = if remaining >= 60
                @sprintf("ETA ~%.0fm", remaining / 60)
            elseif remaining >= 5
                @sprintf("ETA ~%.0fs", remaining)
            else
                ""
            end
            pct = round(Int, 100 * i / n_pts)
            @printf("    Refining: %d/%d (%d%%) | %d conv, %d acc, %d rej | %d TR rej%s\r",
                i, n_pts, pct, n_conv, n_accepted, n_rejected, total_tr_rejections,
                isempty(eta_str) ? "" : " | $eta_str")
            flush(stdout)
        end
    end

    # Clear progress line and print final summary
    print("    " * " "^80 * "\r")
    total_time = time() - t_total
    n_grad_accepted = count(r -> !r.converged && r.gradient_norm < accept_tol, results)
    n_f_accepted_final = count(r -> !r.converged && r.gradient_norm >= accept_tol &&
                         f_accept_tol !== nothing && r.objective_value < f_accept_tol, results)

    # Main CP summary
    if f_accept_tol !== nothing && n_f_accepted_final > 0
        @printf("    Summary: %d converged, %d grad-accepted, %d f-accepted (f<%.0e), %d rejected  (%.1fs)\n",
            n_conv, n_grad_accepted, n_f_accepted_final, f_accept_tol, n_rejected, total_time)
    else
        @printf("    Summary: %d converged, %d accepted, %d rejected  (%.1fs)\n",
            n_conv, n_accepted, n_rejected, total_time)
    end
    # Trust-region summary (only if there were any rejections or safeguards)
    if total_tr_rejections > 0 || total_f_safeguards > 0
        @printf("    Trust-region: %d step rejections, %d f-safeguards across %d CPs\n",
            total_tr_rejections, total_f_safeguards, n_pts)
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

# ═══════════════════════════════════════════════════════════════════════════════
# NelderMead → CriticalPointRefinementResult adapter
# ═══════════════════════════════════════════════════════════════════════════════

"""
    _wrap_neldermead_as_cpresult(
        r::RefinementResult, objective;
        gradient_method, hessian_tol, bounds, initial_point
    ) -> CriticalPointRefinementResult

Convert a NelderMead `RefinementResult` (from `core_refinement.jl`) into a
`CriticalPointRefinementResult` so both refinement paths produce the same type
for downstream consumers.

Computes gradient norm and Hessian eigenvalues at the refined point for CP
classification. This is a one-shot evaluation (not iterative), so cost is
negligible compared to the refinement itself.

When `initial_point` is provided, builds a 2-point trace `[initial_point, refined]`
for trajectory visualization on level set plots.
"""
function _wrap_neldermead_as_cpresult(
    r::RefinementResult,
    objective;
    gradient_method::Symbol = :finitediff,
    hessian_tol::Float64 = 1e-6,
    bounds::Union{Nothing, Vector{Tuple{Float64,Float64}}} = nothing,
    initial_point::Union{Nothing, Vector{Float64}} = nothing,
)::CriticalPointRefinementResult
    point = r.refined

    # Compute gradient norm at refined point
    grad = if gradient_method == :forwarddiff
        ForwardDiff.gradient(objective, point)
    elseif gradient_method == :finitediff
        FiniteDiff.finite_difference_gradient(objective, point)
    else
        error("Unknown gradient_method: $gradient_method (expected :forwarddiff or :finitediff)")
    end

    gradient_norm = if all(isfinite, grad)
        LinearAlgebra.norm(grad)
    else
        Inf
    end

    # Compute Hessian eigenvalues for CP classification
    cp_type = :unknown
    eigenvalues = Float64[]
    if all(isfinite, grad)
        H = if gradient_method == :forwarddiff
            ForwardDiff.hessian(objective, point)
        else
            FiniteDiff.finite_difference_hessian(objective, point)
        end
        if all(isfinite, H)
            eig_vals = LinearAlgebra.eigvals(LinearAlgebra.Symmetric(H))
            cp_type = _classify_eigenvalues(eig_vals, hessian_tol)
            eigenvalues = collect(eig_vals)
        end
    end

    return CriticalPointRefinementResult(
        point,
        gradient_norm,
        r.value_refined,
        r.converged,
        r.iterations,
        cp_type,
        eigenvalues,
        Inf,    # initial_gradient_norm — not available from NelderMead
        NaN,    # final_trust_radius — N/A for NelderMead
        0,      # rejected_steps — N/A
        0,      # f_safeguard_count — N/A
        # 2-point trace (start → end) for trajectory visualization.
        # NelderMead doesn't record per-iteration points, but the start→end line
        # is sufficient for plotting refinement paths on level set plots.
        initial_point !== nothing ? [copy(initial_point), copy(point)] : Vector{Float64}[],
    )
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
