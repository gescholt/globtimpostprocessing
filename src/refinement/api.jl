"""
Refinement API

High-level API functions for refining critical points from globtim experiments.

Created: 2025-11-22 (Architecture cleanup)
"""

# Note: Colors are handled via PrettyTables Crayons in print_refinement_summary()

"""
    refine_experiment_results(experiment_dir, objective_func, config=RefinementConfig(); degree=nothing)

Load raw critical points from globtim output directory and refine them
using local optimization on the original objective function.

# Arguments
- `experiment_dir::String`: Path to globtim output (contains `critical_points_raw_deg_*.csv`)
- `objective_func`: Original objective callable `f(p::Vector{Float64}) -> Float64` (Function or callable struct)
- `config::RefinementConfig`: Refinement configuration (default: gradient-free NelderMead)

# Keyword Arguments
- `degree::Union{Int,Nothing}=nothing`: Specific polynomial degree to load. Defaults to highest degree found.

# Returns
- `RefinedExperimentResult`: Refined points + comparison with raw points

# Files Created
- `critical_points_refined_deg_X.csv`: Refined critical points
- `refinement_comparison_deg_X.csv`: Raw vs refined side-by-side (includes gradient norms)
- `refinement_summary_deg_X.json`: Statistics (convergence, improvement, timing, gradient validation)

# Examples
```julia
using GlobtimPostProcessing

# Load and refine with default config (highest degree)
refined = refine_experiment_results(
    "/path/to/experiment_dir",
    objective_func
)

# Refine a specific degree
refined = refine_experiment_results(
    "/path/to/experiment_dir",
    objective_func,
    ode_refinement_config();
    degree=8
)

# Access results
println("Converged: ", refined.n_converged, "/", refined.n_raw)
println("Mean improvement: ", refined.mean_improvement)
println("Best refined value: ", refined.best_refined_value)

# Best parameter estimate
best_params = refined.refined_points[refined.best_refined_idx]
println("Best estimate: ", best_params)
```

# Notes
- Automatically finds highest degree CSV if multiple degrees present (unless `degree` specified)
- Falls back to old filename format (`critical_points_deg_X.csv`) for compatibility
- Progress messages show refinement status for each point
- Failed refinements are tracked but excluded from refined_points
- Gradient validation automatically runs on converged points (||∇f(x*)|| ≈ 0 check)
"""
function refine_experiment_results(
    experiment_dir::String,
    objective_func,
    config::RefinementConfig = RefinementConfig();
    degree::Union{Int,Nothing} = nothing
)
    # 1. Load raw critical points from CSV
    raw_data = load_raw_critical_points(experiment_dir; degree=degree)

    # 2. Refine using batch processor
    start_time = time()

    refinement_results = refine_critical_points_batch(
        objective_func,
        raw_data.points;
        method = config.method,
        bounds = config.bounds,
        max_time = config.max_time_per_point,
        f_abstol = config.f_abstol,
        x_abstol = config.x_abstol,
        max_iterations = config.max_iterations,
        show_progress = config.show_progress
    )

    total_time = time() - start_time

    # 3. Separate converged/failed/timeout
    converged_indices = findall(r -> r.converged, refinement_results)
    failed_indices = findall(r -> !r.converged && !r.timed_out, refinement_results)
    timeout_indices = findall(r -> r.timed_out, refinement_results)

    n_converged = length(converged_indices)
    n_failed = length(failed_indices)
    n_timeout = length(timeout_indices)

    # 4. Extract data for converged points
    refined_points = [refinement_results[i].refined for i in converged_indices]
    refined_values = [refinement_results[i].value_refined for i in converged_indices]
    improvements = [refinement_results[i].improvement for i in converged_indices]

    # All raw values and convergence status
    raw_values = [r.value_raw for r in refinement_results]
    convergence_status = [r.converged for r in refinement_results]
    iterations = [r.iterations for r in refinement_results]

    # 5. Compute statistics
    if n_converged > 0
        mean_improvement = Statistics.mean(improvements)
        max_improvement = maximum(improvements)

        best_refined_idx = argmin(refined_values)
        best_refined_value = refined_values[best_refined_idx]
    else
        mean_improvement = 0.0
        max_improvement = 0.0
        best_refined_idx = 0
        best_refined_value = Inf
    end

    best_raw_idx = argmin(raw_values)
    best_raw_value = raw_values[best_raw_idx]

    # 6. Create result struct
    result = RefinedExperimentResult(
        raw_data.points,        # raw_points
        refined_points,          # refined_points
        raw_values,              # raw_values
        refined_values,          # refined_values
        improvements,            # improvements
        convergence_status,      # convergence_status
        iterations,              # iterations
        raw_data.n_points,       # n_raw
        n_converged,             # n_converged
        n_failed,                # n_failed
        n_timeout,               # n_timeout
        mean_improvement,        # mean_improvement
        max_improvement,         # max_improvement
        best_raw_idx,            # best_raw_idx
        best_refined_idx,        # best_refined_idx
        best_raw_value,          # best_raw_value
        best_refined_value,      # best_refined_value
        experiment_dir,          # output_dir
        raw_data.degree,         # degree
        total_time,              # total_time
        config                   # refinement_config
    )

    # 7a. Raw gradient validation — check ||∇f(x_raw)|| at raw critical points
    raw_gradient_norms = compute_gradient_norms(
        raw_data.points, objective_func;
        gradient_method=config.gradient_method
    )

    # 7b. Refined gradient validation (if we have refined points)
    gradient_validation = if n_converged > 0
        validate_critical_points(refined_points, objective_func;
                                tolerance=config.gradient_tolerance,
                                gradient_method=config.gradient_method)
    else
        nothing
    end

    # 8. Save results (with Tier 1 diagnostics and gradient validation)
    save_refined_results(experiment_dir, result, raw_data.degree, refinement_results;
                        gradient_validation=gradient_validation,
                        raw_gradient_norms=raw_gradient_norms)

    # 9. Print formatted summary
    print_refinement_summary(result, gradient_validation, raw_gradient_norms)

    return result
end

"""
    refine_critical_points(raw_result, objective_func, config=RefinementConfig())

Refine critical points from a RawExperimentResult object (in-memory).

This is a convenience wrapper that delegates to `refine_experiment_results()`.

# Arguments
- `raw_result`: Object with `output_dir` field (e.g., from `run_standard_experiment()`)
- `objective_func`: Original objective callable (Function or callable struct)
- `config::RefinementConfig`: Refinement configuration

# Returns
- `RefinedExperimentResult`: Refined results

# Examples
```julia
using Globtim, GlobtimPostProcessing

# Run experiment (globtim)
raw = Globtim.run_standard_experiment(
    objective_function = my_objective, objective_name = "my_problem",
    problem_params = nothing, bounds = bounds,
    experiment_config = config, output_dir = "results/my_experiment"
)

# Refine (globtimpostprocessing)
refined = refine_critical_points(raw, my_objective, ode_refinement_config())
```
"""
function refine_critical_points(
    raw_result,
    objective_func,
    config::RefinementConfig = RefinementConfig()
)
    # Extract output directory from result object
    if !hasfield(typeof(raw_result), :output_dir)
        error("raw_result must have an output_dir field")
    end

    return refine_experiment_results(
        raw_result.output_dir,
        objective_func,
        config
    )
end

"""
    print_refinement_summary(result, gradient_validation, raw_gradient_norms)

Print a compact refinement summary.

Reports convergence stats, objective improvement, raw gradient norms (how close
raw critical points are to actual critical points of f), and refined gradient validation.
"""
function print_refinement_summary(
    result::RefinedExperimentResult,
    gradient_validation::Union{GradientValidationResult, Nothing},
    raw_gradient_norms::Union{Vector{Float64}, Nothing} = nothing
)
    # Line 1: Convergence
    conv_rate = round(100 * result.n_converged / result.n_raw, digits=1)
    println("Critical points: $(result.n_raw) raw → $(result.n_converged) refined ($conv_rate%)")

    # Line 2: Improvement (if converged)
    if result.n_converged > 0
        improvement = round(100 * (1 - result.best_refined_value / result.best_raw_value), digits=1)
        @printf("Best objective: %.2e → %.2e (%.1f%% improvement)\n",
                result.best_raw_value, result.best_refined_value, improvement)
    end

    # Line 3: Raw gradient norms — how close are raw critical points to true critical points of f?
    if raw_gradient_norms !== nothing
        finite_norms = filter(isfinite, raw_gradient_norms)
        if !isempty(finite_norms)
            sorted = sort(finite_norms)
            med = sorted[div(length(sorted) + 1, 2)]
            @printf("Raw ||∇f||: min=%.2e, median=%.2e, mean=%.2e, max=%.2e (%d/%d finite)\n",
                    minimum(sorted), med, Statistics.mean(sorted), maximum(sorted),
                    length(finite_norms), length(raw_gradient_norms))
        else
            println("Raw ||∇f||: all gradient computations failed")
        end
    end

    # Line 4: Refined gradient validation (if available)
    if gradient_validation !== nothing
        n_total = length(gradient_validation.norms)
        grad_rate = round(100 * gradient_validation.n_valid / n_total, digits=1)
        mean_norm = isnan(gradient_validation.mean_norm) ? 0.0 : gradient_validation.mean_norm
        @printf("Refined ||∇f||: %d/%d valid (%.1f%%), mean=%.2e\n",
                gradient_validation.n_valid, n_total, grad_rate, mean_norm)
    end
    println()
end

"""
    print_comparison_table(result, gradient_validation; raw_gradient_norms, n_show=10, sort_by=:refined_value)

Print a comparison table of raw vs refined critical points using PrettyTables.

# Arguments
- `result::RefinedExperimentResult`: Refinement results
- `gradient_validation::Union{GradientValidationResult, Nothing}`: Optional refined gradient validation
- `raw_gradient_norms::Union{Vector{Float64}, Nothing}`: Optional raw gradient norms ||∇f(x_raw)||
- `n_show::Int = 10`: Number of points to display (use `Inf` for all)
- `sort_by::Symbol = :refined_value`: Sort by `:raw_value`, `:refined_value`, `:improvement`, or `:index`

# Examples
```julia
result = refine_experiment_results(dir, objective)
print_comparison_table(result)  # Show top 10 by refined value

# Show all points sorted by improvement
print_comparison_table(result; n_show=Inf, sort_by=:improvement)
```
"""
function print_comparison_table(
    result::RefinedExperimentResult,
    gradient_validation::Union{GradientValidationResult, Nothing} = nothing;
    raw_gradient_norms::Union{Vector{Float64}, Nothing} = nothing,
    n_show::Union{Int, Float64} = 10,
    sort_by::Symbol = :refined_value
)
    cr_bold = Crayon(bold = true)
    cr_cyan = Crayon(foreground = :cyan)

    n_display = isinf(n_show) ? result.n_raw : min(Int(n_show), result.n_raw)

    # Build indices based on sort order
    indices = collect(1:result.n_raw)
    if sort_by == :raw_value
        sort!(indices, by = i -> result.raw_values[i])
    elseif sort_by == :refined_value
        # Sort converged first by refined value, then non-converged
        sort!(indices, by = i -> begin
            if result.convergence_status[i]
                converged_idx = sum(result.convergence_status[1:i])
                return result.refined_values[converged_idx]
            else
                return Inf
            end
        end)
    elseif sort_by == :improvement
        sort!(indices, by = i -> begin
            if result.convergence_status[i]
                converged_idx = sum(result.convergence_status[1:i])
                return -result.improvements[converged_idx]  # Negative for descending
            else
                return 0.0
            end
        end, rev = true)
    end
    # :index keeps original order

    indices = indices[1:n_display]

    function format_sci_short(x::Float64)
        if isnan(x) || isinf(x)
            return "N/A"
        end
        @sprintf("%.3e", x)
    end

    # Determine columns: Idx, Raw Val, ||∇f|| raw, Ref Val, Improv, [||∇f|| ref]
    has_raw_grads = raw_gradient_norms !== nothing
    has_ref_grads = gradient_validation !== nothing

    n_cols = 4  # Idx, Raw Val, Ref Val, Improv
    if has_raw_grads
        n_cols += 1
    end
    if has_ref_grads
        n_cols += 1
    end
    data = Matrix{Any}(undef, n_display, n_cols)

    for (row, i) in enumerate(indices)
        col = 1
        data[row, col] = i  # Index
        col += 1
        data[row, col] = format_sci_short(result.raw_values[i])
        col += 1

        # Raw gradient norm (one per raw point, always available if provided)
        if has_raw_grads
            data[row, col] = format_sci_short(raw_gradient_norms[i])
            col += 1
        end

        if result.convergence_status[i]
            converged_idx = sum(result.convergence_status[1:i])
            data[row, col] = format_sci_short(result.refined_values[converged_idx])
            col += 1
            data[row, col] = format_sci_short(result.improvements[converged_idx])
            col += 1
            if has_ref_grads
                data[row, col] = format_sci_short(gradient_validation.norms[converged_idx])
            end
        else
            data[row, col] = "N/A"  # Ref Val
            col += 1
            data[row, col] = "N/A"  # Improv
            col += 1
            if has_ref_grads
                data[row, col] = "N/A"
            end
        end
    end

    # Build header and alignment dynamically
    header_vec = ["Idx", "Raw Val"]
    if has_raw_grads
        push!(header_vec, "||∇f|| raw")
    end
    push!(header_vec, "Ref Val", "Improv")
    if has_ref_grads
        push!(header_vec, "||∇f|| ref")
    end

    alignment = fill(:r, n_cols)

    println()
    println(cr_bold(cr_cyan("Raw vs Refined (showing $n_display of $(result.n_raw))")))
    println()

    styled_table(data;
        header = header_vec,
        alignment = alignment,
    )
    println()
end

"""
    RefinementDistanceResult

Container for refinement distance metrics.

# Fields
- `distances::Vector{Float64}`: ||refined[i] - raw[i]|| for each converged point
- `mean_distance::Float64`: Mean refinement distance
- `max_distance::Float64`: Maximum refinement distance
- `best_point_distance::Float64`: Distance for the best refined point
- `relative_distances::Union{Vector{Float64}, Nothing}`: distances / domain_diameter (if domain_size provided)
- `mean_relative::Union{Float64, Nothing}`: Mean relative distance
- `best_point_relative::Union{Float64, Nothing}`: Relative distance for best point
"""
struct RefinementDistanceResult
    distances::Vector{Float64}
    mean_distance::Float64
    max_distance::Float64
    best_point_distance::Float64
    relative_distances::Union{Vector{Float64}, Nothing}
    mean_relative::Union{Float64, Nothing}
    best_point_relative::Union{Float64, Nothing}
end

"""
    compute_refinement_distances(result::RefinedExperimentResult; domain_size::Union{Float64, Nothing}=nothing)

Compute spatial distances between raw and refined critical points.

# Arguments
- `result::RefinedExperimentResult`: Refinement results
- `domain_size::Union{Float64, Nothing}`: Domain radius for relative distance calculation

# Returns
- `RefinementDistanceResult`: Distance metrics

# Example
```julia
refined = refine_experiment_results(dir, objective, config)
distances = compute_refinement_distances(refined; domain_size=0.0005)
println("Best point moved: ", distances.best_point_distance)
println("Relative to domain: ", distances.best_point_relative * 100, "%")
```
"""
function compute_refinement_distances(
    result::RefinedExperimentResult;
    domain_size::Union{Float64, Nothing} = nothing
)
    if result.n_converged == 0
        return RefinementDistanceResult(
            Float64[], NaN, NaN, NaN, nothing, nothing, nothing
        )
    end

    # Compute distances for each converged point
    distances = Float64[]
    converged_count = 0
    for (i, converged) in enumerate(result.convergence_status)
        if converged
            converged_count += 1
            raw_pt = result.raw_points[i]
            refined_pt = result.refined_points[converged_count]
            push!(distances, LinearAlgebra.norm(refined_pt - raw_pt))
        end
    end

    mean_dist = Statistics.mean(distances)
    max_dist = maximum(distances)
    best_dist = distances[result.best_refined_idx]

    # Relative distances (if domain_size provided)
    if domain_size !== nothing
        domain_diameter = 2 * domain_size
        relative = distances ./ domain_diameter
        mean_rel = mean_dist / domain_diameter
        best_rel = best_dist / domain_diameter
    else
        relative = nothing
        mean_rel = nothing
        best_rel = nothing
    end

    return RefinementDistanceResult(
        distances, mean_dist, max_dist, best_dist,
        relative, mean_rel, best_rel
    )
end
