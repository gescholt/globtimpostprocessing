# ValleyWalking.jl
# Trace positive-dimensional minima (valleys) using predictor-corrector methods

using LinearAlgebra: norm, dot, eigen, Symmetric, cond, pinv
using ForwardDiff: gradient, hessian
using Printf: @printf

"""
Configuration for valley walking algorithms.

# Fields
- `gradient_tolerance`: Maximum gradient norm to consider a point critical (default: 1e-4)
- `eigenvalue_threshold`: Threshold for near-zero Hessian eigenvalues (default: 1e-3)
- `initial_step_size`: Starting step size for walking (default: 0.05)
- `max_steps`: Maximum number of steps per direction (default: 200)
- `max_projection_iter`: Maximum Newton iterations for projection (default: 10)
- `projection_tol`: Tolerance for projection onto valley (default: 1e-10)
- `method`: Walking method `:newton_projection` or `:predictor_corrector` (default: :newton_projection)
"""
@kwdef struct ValleyWalkConfig
    gradient_tolerance::Float64 = 1e-4
    eigenvalue_threshold::Float64 = 1e-3
    initial_step_size::Float64 = 0.05
    max_steps::Int = 200
    max_projection_iter::Int = 10
    projection_tol::Float64 = 1e-10
    method::Symbol = :newton_projection
end

"""
Result of tracing a valley from a starting point.

# Fields
- `start_point`: The initial critical point
- `path_positive`: Path traced in positive tangent direction
- `path_negative`: Path traced in negative tangent direction
- `arc_length`: Total arc length of both paths
- `n_points`: Total number of points in both paths
- `valley_dimension`: Number of near-zero Hessian eigenvalues (0 if not a valley)
- `method`: Walking method used
- `converged`: Whether the trace completed successfully
"""
struct ValleyTraceResult
    start_point::Vector{Float64}
    path_positive::Vector{Vector{Float64}}
    path_negative::Vector{Vector{Float64}}
    arc_length::Float64
    n_points::Int
    valley_dimension::Int
    method::Symbol
    converged::Bool
end

"""
    detect_valley(f, point, config::ValleyWalkConfig) -> (is_valley, directions, valley_dimension)

Detect if a point lies on a positive-dimensional minimum (valley).

Returns `(true, directions, dim)` if the point is a valley point, where `directions`
is a matrix whose columns are the valley tangent directions and `dim` is the
number of near-zero Hessian eigenvalues (the valley dimension).
Returns `(false, nothing, 0)` otherwise.
"""
function detect_valley(f, point::AbstractVector, config::ValleyWalkConfig)
    grad = gradient(f, point)
    hess = hessian(f, point)
    eigendecomp = eigen(Symmetric(hess))

    grad_norm = norm(grad)
    valley_mask = abs.(eigendecomp.values) .< config.eigenvalue_threshold
    valley_dimension = sum(valley_mask)

    is_critical = grad_norm < config.gradient_tolerance
    is_valley = is_critical && (valley_dimension > 0)

    if is_valley
        valley_directions = eigendecomp.vectors[:, valley_mask]
        return true, valley_directions, valley_dimension
    end
    return false, nothing, 0
end

"""
    project_to_valley(f, point; max_iter=10, tol=1e-10) -> Vector

Project a point onto the critical manifold (∇f(x) = 0) using Newton's method.

Uses the full Newton step `x -= H \\ ∇f` to find the nearest critical point.
This correctly handles valleys where the minimum value is nonzero (e.g. parameter
estimation error functions with irreducible residual).
"""
function project_to_valley(f, point::AbstractVector; max_iter::Int=10, tol::Float64=1e-10)
    x = Vector{Float64}(point)
    for _ in 1:max_iter
        g = gradient(f, x)
        norm(g) < tol && break
        H = hessian(f, x)
        # Use Symmetric for numerical stability; fallback to pinv if singular
        Hs = Symmetric(H)
        cond_H = cond(Hs)
        if cond_H < 1e12
            x .-= Hs \ g
        else
            x .-= pinv(Hs) * g
        end
    end
    return x
end

"""
    get_valley_tangent(f, point, prev_dir, config) -> Vector or nothing

Get tangent direction from Hessian null space, maintaining continuity with previous direction.
Returns `nothing` if no valley tangent exists at this point.
"""
function get_valley_tangent(f, point::AbstractVector, prev_dir::AbstractVector, config::ValleyWalkConfig)
    hess = hessian(f, point)
    eigendecomp = eigen(hess)
    mask = abs.(eigendecomp.values) .< config.eigenvalue_threshold
    any(mask) || return nothing

    dirs = eigendecomp.vectors[:, mask]
    best = dirs[:, 1]
    for j in 1:size(dirs, 2)
        abs(dot(dirs[:, j], prev_dir)) > abs(dot(best, prev_dir)) && (best = dirs[:, j])
    end
    dot(best, prev_dir) < 0 && (best = -best)
    return best / norm(best)
end

"""
    walk_newton_projection(f, start_point, initial_direction, config) -> Vector{Vector{Float64}}

Walk along valley using Newton projection method.
Takes tangent steps then projects back onto the valley.
"""
function walk_newton_projection(f, start_point::AbstractVector, initial_direction::AbstractVector,
                                 config::ValleyWalkConfig)
    steps = [Vector{Float64}(start_point)]
    current = Vector{Float64}(start_point)
    direction = initial_direction / norm(initial_direction)
    step_size = config.initial_step_size

    for _ in 1:config.max_steps
        tangent = get_valley_tangent(f, current, direction, config)
        isnothing(tangent) && break
        direction = tangent

        # Take tangent step
        candidate = current + step_size * direction
        # Project back onto valley
        projected = project_to_valley(f, candidate;
                                      max_iter=config.max_projection_iter,
                                      tol=config.projection_tol)

        # Accept if projection didn't move too far
        if norm(projected - candidate) < step_size
            current = projected
            push!(steps, copy(current))
            step_size = min(step_size * 1.1, 0.2)
        else
            step_size *= 0.5
            step_size < 1e-8 && break
        end
    end
    return steps
end

"""
    walk_predictor_corrector(f, start_point, initial_direction, config) -> Vector{Vector{Float64}}

Walk along valley using predictor-corrector method.
Predicts with tangent step, corrects with Newton projection, adapts step size.
"""
function walk_predictor_corrector(f, start_point::AbstractVector, initial_direction::AbstractVector,
                                   config::ValleyWalkConfig)
    steps = [Vector{Float64}(start_point)]
    current = Vector{Float64}(start_point)
    direction = initial_direction / norm(initial_direction)
    step_size = config.initial_step_size

    for _ in 1:config.max_steps
        tangent = get_valley_tangent(f, current, direction, config)
        isnothing(tangent) && break
        direction = tangent

        # Predictor: tangent step
        predicted = current + step_size * direction
        # Corrector: Newton projection
        corrected = project_to_valley(f, predicted;
                                      max_iter=config.max_projection_iter,
                                      tol=config.projection_tol)

        correction_size = norm(corrected - predicted)
        if correction_size < 0.5 * step_size
            # Good step - accept and maybe increase step size
            current = corrected
            push!(steps, copy(current))
            step_size = min(step_size * 1.2, 0.3)
        elseif correction_size < step_size
            # Okay step - accept but reduce step size
            current = corrected
            push!(steps, copy(current))
            step_size *= 0.8
        else
            # Bad step - reduce step size and retry
            step_size *= 0.5
            step_size < 1e-8 && break
        end
    end
    return steps
end

"""
    trace_valley(f, start_point, config::ValleyWalkConfig) -> ValleyTraceResult

Trace a valley in both directions from a starting point.

First detects if the point is on a valley, then walks in both positive and
negative tangent directions using the specified method.
"""
function trace_valley(f, start_point::AbstractVector, config::ValleyWalkConfig=ValleyWalkConfig())
    is_valley, directions, vdim = detect_valley(f, start_point, config)

    if !is_valley
        return ValleyTraceResult(
            Vector{Float64}(start_point),
            [Vector{Float64}(start_point)],
            [Vector{Float64}(start_point)],
            0.0, 1, 0, config.method, false
        )
    end

    # Use first valley direction (traces a 1D curve even for higher-dim valleys)
    initial_dir = directions[:, 1]

    # Select walking method
    walk_func = if config.method == :predictor_corrector
        walk_predictor_corrector
    else
        walk_newton_projection
    end

    # Walk in both directions
    path_pos = walk_func(f, start_point, initial_dir, config)
    path_neg = walk_func(f, start_point, -initial_dir, config)

    # Compute arc length
    arc_len = sum(norm(path_pos[i+1] - path_pos[i]) for i in 1:length(path_pos)-1; init=0.0) +
              sum(norm(path_neg[i+1] - path_neg[i]) for i in 1:length(path_neg)-1; init=0.0)

    n_points = length(path_pos) + length(path_neg)

    return ValleyTraceResult(
        Vector{Float64}(start_point),
        path_pos, path_neg,
        arc_len, n_points, vdim, config.method, true
    )
end

"""
    trace_valleys_from_critical_points(f, df::DataFrame, config::ValleyWalkConfig) -> Vector{ValleyTraceResult}

Trace valleys from all critical points in a DataFrame.

Expects the DataFrame to have columns `:x1`, `:x2`, etc. for coordinates.
Only traces from points that are detected as valley points.
"""
function trace_valleys_from_critical_points(f, df::DataFrame, config::ValleyWalkConfig=ValleyWalkConfig())
    # Extract dimension columns
    dim_cols = sort(filter(c -> match(r"^x\d+$", String(c)) !== nothing, names(df)))
    isempty(dim_cols) && error("DataFrame must have columns x1, x2, ... for coordinates")

    results = ValleyTraceResult[]

    for i in 1:nrow(df)
        point = [df[i, col] for col in dim_cols]
        result = trace_valley(f, point, config)
        result.converged && push!(results, result)
    end

    return results
end

"""
    run_valley_analysis(objective, refinement_results; config) -> Vector{ValleyTraceResult}

Run valley walking analysis on degenerate critical points from Newton CP discovery.

Screens `refinement_results` for CPs with `cp_type == :degenerate` (near-zero Hessian
eigenvalues indicating a positive-dimensional critical manifold), then traces along
each valley using the configured walking method.

Prints a terminal summary of discovered valleys. Returns the trace results for
downstream use (e.g. plotting).

# Arguments
- `objective`: The objective function f(x)
- `refinement_results::Vector{CriticalPointRefinementResult}`: Refined CPs from
  `build_known_cps_from_refinement` (preserves `:degenerate` type and eigenvalues)
- `config::ValleyWalkConfig`: Walking algorithm configuration (default: `ValleyWalkConfig()`)

# Returns
- `Vector{ValleyTraceResult}`: One result per degenerate CP that was successfully traced
"""
function run_valley_analysis(
    objective,
    refinement_results::Vector{CriticalPointRefinementResult};
    config::ValleyWalkConfig = ValleyWalkConfig(),
)
    degenerate_cps = filter(r -> r.cp_type == :degenerate, refinement_results)
    n_total = length(refinement_results)
    n_degen = length(degenerate_cps)

    println()
    println("══ Valley Walking Analysis ════════════════════════════════════")

    if n_degen == 0
        println("  No degenerate CPs found (0 of $n_total have near-zero eigenvalues)")
        println()
        return ValleyTraceResult[]
    end

    println("  $n_degen degenerate CP$(n_degen > 1 ? "s" : "") detected (of $n_total total)")
    println()

    results = ValleyTraceResult[]
    for (i, cp) in enumerate(degenerate_cps)
        # Find the index in the original results for display
        cp_idx = findfirst(r -> r === cp, refinement_results)

        trace = trace_valley(objective, cp.point, config)

        status = trace.converged ? "converged" : "not converged"
        @printf("  CP %2d: dim=%d  arc_length=%.2f  points=%d  %s\n",
            cp_idx, trace.valley_dimension, trace.arc_length, trace.n_points, status)

        if trace.converged
            push!(results, trace)
        end
    end

    println()
    n_traced = length(results)
    if n_traced > 0
        println("  $n_traced valley$(n_traced > 1 ? "s" : "") successfully traced")
    else
        println("  No valleys could be traced (CPs may not lie exactly on a valley manifold)")
    end
    println()

    return results
end
