"""
Critical Point Refinement - Core Algorithms

Provides local optimization refinement for critical points found by HomotopyContinuation.jl
using Optim.jl to improve numerical accuracy from ~1e-10 to ~1e-16.

Uses gradient-free optimization (NelderMead) by default for robustness with ODE-based
objectives and noisy/stiff problems.

Originally from globtimcore/src/CriticalPointRefinement.jl
Moved to globtimpostprocessing in 2025-11-22 (Architecture cleanup)

Usage:
```julia
using GlobtimPostProcessing

# Single point refinement (gradient-free)
result = refine_critical_point(objective_func, initial_point)

# Batch refinement
results = refine_critical_points_batch(objective_func, points_array)
```

Created: 2025-09-30 (Issue #109)
Updated: 2025-11-22 (Moved to globtimpostprocessing)
"""

# Note: using Optim is done in main GlobtimPostProcessing.jl

"""
Result of refining a single critical point.

Fields (original):
- `refined::Vector{Float64}`: Refined critical point coordinates
- `value_raw::Float64`: Objective function value at initial point
- `value_refined::Float64`: Objective function value at refined point
- `converged::Bool`: Whether Optim.jl converged (backward compatibility)
- `iterations::Int`: Number of optimization iterations
- `improvement::Float64`: |f(refined) - f(raw)|
- `timed_out::Bool`: Whether refinement exceeded max_time
- `error_message::Union{String,Nothing}`: Error message if refinement failed (nothing if no error)

Tier 1 Diagnostics (zero-cost, always available):
- `f_calls::Int`: Objective function evaluations
- `g_calls::Int`: Gradient evaluations (0 for gradient-free methods)
- `h_calls::Int`: Hessian evaluations (typically 0)
- `time_elapsed::Float64`: Actual optimization time in seconds
- `x_converged::Bool`: Parameter convergence (x_tol)
- `f_converged::Bool`: Function value convergence (f_tol)
- `g_converged::Bool`: Gradient norm convergence (g_tol, gradient methods only)
- `iteration_limit_reached::Bool`: Hit max iteration limit
- `convergence_reason::Symbol`: Primary stopping reason (:x_tol, :f_tol, :g_tol, :iterations, :timeout, :error)
"""
struct RefinementResult
    # Original fields (backward compatibility)
    refined::Vector{Float64}
    value_raw::Float64
    value_refined::Float64
    converged::Bool
    iterations::Int
    improvement::Float64
    timed_out::Bool
    error_message::Union{String,Nothing}

    # Tier 1 Diagnostics (Phase 2)
    f_calls::Int
    g_calls::Int
    h_calls::Int
    time_elapsed::Float64
    x_converged::Bool
    f_converged::Bool
    g_converged::Bool
    iteration_limit_reached::Bool
    convergence_reason::Symbol
end

"""
    refine_critical_point(objective_func, initial_point; method=NelderMead(), options...)

Refine a single critical point using local optimization with adaptive tolerances.

# Arguments
- `objective_func`: Function to minimize, signature f(x::Vector{Float64}) -> Float64
- `initial_point::Vector{Float64}`: Initial guess from HomotopyContinuation
- `method`: Optimization method (default: NelderMead() - gradient-free, robust)
- `f_abstol::Float64`: Absolute function tolerance for convergence (default: 1e-6, relaxed for robustness)
- `x_abstol::Float64`: Absolute parameter tolerance for convergence (default: 1e-6)
- `max_time::Union{Float64,Nothing}`: Maximum time in seconds per refinement (default: nothing = no timeout)
- `max_iterations::Int`: Maximum number of iterations (default: 300, balanced for speed/convergence)

# Returns
`RefinementResult` with refined point, values, convergence status, and improvement

# Examples
```julia
# Define objective function
f(x) = (x[1] - 1.875)^2 + (x[2] - 1.5)^2 + x[3]^2 + x[4]^2

# Refine point from HomotopyContinuation
initial = [1.87, 1.49, 0.01, 0.01]
result = refine_critical_point(f, initial)

if result.converged
    println("Refined to: ", result.refined)
    println("Improvement: ", result.improvement)
elseif result.timed_out
    println("Refinement timed out: ", result.error_message)
else
    println("Refinement failed")
end
```

# Notes
- Uses adaptive tolerance strategy: relaxed tolerances for robustness
- NelderMead by default (simplex method, gradient-free, robust for ODE problems)
- Convergence criteria relaxed from 1e-10 to 1e-6 for practical convergence
- With max_time set, refinement will be interrupted if it exceeds the time limit
"""
function refine_critical_point(
    objective_func,
    initial_point::Vector{Float64};
    method = Optim.NelderMead(),
    f_abstol::Float64 = 1e-6,
    x_abstol::Float64 = 1e-6,
    max_time::Union{Float64,Nothing} = nothing,
    max_iterations::Int = 300
)
    # Evaluate at initial point
    value_raw = objective_func(initial_point)

    # If initial value is non-finite, skip refinement
    if !isfinite(value_raw)
        return RefinementResult(
            initial_point,
            value_raw,
            value_raw,
            false,  # not converged
            0,
            0.0,
            false,  # not timed out
            "Initial evaluation returned non-finite value: $value_raw",
            # Tier 1 diagnostics (error case)
            1,  # f_calls (initial evaluation)
            0,  # g_calls
            0,  # h_calls
            0.0,  # time_elapsed
            false,  # x_converged
            false,  # f_converged
            false,  # g_converged
            false,  # iteration_limit_reached
            :error  # convergence_reason
        )
    end

    # Refine with Optim.jl (with optional timeout)
    try
        start_time = time()

        # Create optimization options
        opt_options = Optim.Options(
            f_abstol = f_abstol,
            x_abstol = x_abstol,
            time_limit = max_time === nothing ? Inf : max_time,
            iterations = max_iterations
        )

        result = Optim.optimize(
            objective_func,
            initial_point,
            method,
            opt_options
        )

        elapsed_time = time() - start_time

        # Check if timed out
        timed_out = max_time !== nothing && elapsed_time >= max_time

        # Extract results
        refined_point = Optim.minimizer(result)
        value_refined = Optim.minimum(result)

        # Tier 1 Diagnostics: Extract fine-grained convergence info
        x_conv = Optim.x_converged(result)
        f_conv = Optim.f_converged(result)
        g_conv = Optim.g_converged(result)
        iter_limit = Optim.iteration_limit_reached(result)

        # Extract call counts
        f_calls = Optim.f_calls(result)
        g_calls = Optim.g_calls(result)
        h_calls = Optim.h_calls(result)

        # Extract actual optimization time (may differ from elapsed_time)
        time_run = Optim.time_run(result)

        # Determine primary convergence reason
        convergence_reason = if timed_out
            :timeout
        elseif g_conv
            :g_tol  # Gradient norm converged (best for critical points)
        elseif f_conv
            :f_tol  # Function value converged
        elseif x_conv
            :x_tol  # Parameters converged
        elseif iter_limit
            :iterations  # Hit iteration limit without converging
        elseif !Optim.converged(result)
            :error  # Failed for other reason
        else
            :unknown  # Converged but unclear reason
        end

        error_msg = if timed_out
            "Refinement timed out after $(round(elapsed_time, digits=1))s"
        elseif !Optim.converged(result)
            "Refinement did not converge ($(Optim.iterations(result)) iterations)"
        else
            nothing
        end

        return RefinementResult(
            refined_point,
            value_raw,
            value_refined,
            Optim.converged(result),
            Optim.iterations(result),
            abs(value_refined - value_raw),
            timed_out,
            error_msg,
            # Tier 1 diagnostics
            f_calls,
            g_calls,
            h_calls,
            time_run,
            x_conv,
            f_conv,
            g_conv,
            iter_limit,
            convergence_reason
        )
    catch e
        # If optimization fails (e.g., non-finite values, errors), return initial point
        error_msg = if isa(e, InterruptException)
            rethrow(e)  # Don't catch user interrupts
        else
            "Optimization error: $(sprint(showerror, e))"
        end

        return RefinementResult(
            initial_point,
            value_raw,
            value_raw,
            false,  # not converged
            0,
            0.0,
            false,  # not timed out (errored instead)
            error_msg,
            # Tier 1 diagnostics (error case)
            1,  # f_calls (initial evaluation)
            0,  # g_calls
            0,  # h_calls
            0.0,  # time_elapsed
            false,  # x_converged
            false,  # f_converged
            false,  # g_converged
            false,  # iteration_limit_reached
            :error  # convergence_reason
        )
    end
end

"""
    refine_critical_points_batch(objective_func, points; method=NelderMead(), options...)

Refine multiple critical points in batch with progress tracking.

# Arguments
- `objective_func`: Function to minimize
- `points::Vector{Vector{Float64}}`: Array of initial points from HomotopyContinuation
- `method`: Optimization method (default: NelderMead() - gradient-free)
- `f_abstol::Float64`: Absolute function tolerance (default: 1e-6)
- `x_abstol::Float64`: Absolute parameter tolerance (default: 1e-6)
- `max_time::Union{Float64,Nothing}`: Maximum time per point in seconds (default: nothing = no timeout)
- `max_iterations::Int`: Maximum number of iterations (default: 300, balanced for speed/convergence)
- `show_progress::Bool`: Show progress counter (default: true)

# Returns
`Vector{RefinementResult}`: Results for each point (same order as input)

# Examples
```julia
# Refine multiple points
points = [
    [1.87, 1.49, 0.01, 0.01],
    [1.88, 1.51, -0.01, -0.01],
    [1.86, 1.48, 0.02, 0.00]
]

# Refine with 30s timeout per point
results = refine_critical_points_batch(f, points, max_time=30.0)

# Separate converged and failed
converged_results = filter(r -> r.converged, results)
failed_results = filter(r -> !r.converged, results)
timed_out_results = filter(r -> r.timed_out, results)

println("Converged: ", length(converged_results), "/", length(results))
println("Timed out: ", length(timed_out_results), "/", length(results))
if !isempty(converged_results)
    using Statistics
    println("Mean improvement: ", mean(r.improvement for r in converged_results))
end
```

# Notes
- Processes points sequentially (not parallelized)
- Each refinement is independent, so failed refinements don't affect others
- For large batches, consider parallel processing with `pmap()`
- Uses gradient-free NelderMead by default for robustness
- With max_time set, each refinement will timeout if it exceeds the limit
- Progress counter shows which point is being refined (e.g., "Refining 3/15...")
"""
function refine_critical_points_batch(
    objective_func,
    points::Vector{Vector{Float64}};
    method = Optim.NelderMead(),
    f_abstol::Float64 = 1e-6,
    x_abstol::Float64 = 1e-6,
    max_time::Union{Float64,Nothing} = nothing,
    max_iterations::Int = 300,
    show_progress::Bool = true
)
    refined_results = RefinementResult[]
    n_points = length(points)

    for (i, pt) in enumerate(points)
        if show_progress
            print("  Refining point $i/$n_points...")
            flush(stdout)
        end

        result = refine_critical_point(
            objective_func, pt;
            method=method,
            f_abstol=f_abstol,
            x_abstol=x_abstol,
            max_time=max_time,
            max_iterations=max_iterations
        )

        push!(refined_results, result)

        # Show result status
        if show_progress
            if result.converged
                println(" ✓")
            elseif result.timed_out
                println(" ⏱ TIMEOUT ($(result.error_message))")
            else
                println(" ✗ ($(result.error_message))")
            end
        end
    end

    return refined_results
end
