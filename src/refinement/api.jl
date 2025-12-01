"""
Refinement API

High-level API functions for refining critical points from globtimcore experiments.

Created: 2025-11-22 (Architecture cleanup)
"""

# Terminal colors for summary output
const RESET = "\033[0m"
const BOLD = "\033[1m"
const GREEN = "\033[32m"
const YELLOW = "\033[33m"
const RED = "\033[31m"
const CYAN = "\033[36m"
const DIM = "\033[2m"

"""
    refine_experiment_results(experiment_dir, objective_func, config=RefinementConfig())

Load raw critical points from globtimcore output directory and refine them
using local optimization on the original objective function.

# Arguments
- `experiment_dir::String`: Path to globtimcore output (contains `critical_points_raw_deg_*.csv`)
- `objective_func::Function`: Original objective function `f(p::Vector{Float64}) -> Float64`
- `config::RefinementConfig`: Refinement configuration (default: gradient-free NelderMead)

# Returns
- `RefinedExperimentResult`: Refined points + comparison with raw points

# Files Created
- `critical_points_refined_deg_X.csv`: Refined critical points
- `refinement_comparison_deg_X.csv`: Raw vs refined side-by-side (includes gradient norms)
- `refinement_summary_deg_X.json`: Statistics (convergence, improvement, timing, gradient validation)

# Examples
```julia
using GlobtimPostProcessing

# Load and refine with default config
refined = refine_experiment_results(
    "../globtim_results/lv4d_exp_20251122_143022",
    objective_func
)

# Use ODE-specific config
refined = refine_experiment_results(
    "../globtim_results/lv4d_exp_20251122_143022",
    objective_func,
    ode_refinement_config()
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
- Automatically finds highest degree CSV if multiple degrees present
- Falls back to old filename format (`critical_points_deg_X.csv`) for compatibility
- Progress messages show refinement status for each point
- Failed refinements are tracked but excluded from refined_points
- Gradient validation automatically runs on converged points (||∇f(x*)|| ≈ 0 check)
"""
function refine_experiment_results(
    experiment_dir::String,
    objective_func::Function,
    config::RefinementConfig = RefinementConfig()
)
    println("="^80)
    println("Critical Point Refinement")
    println("="^80)
    println("Experiment directory: $experiment_dir")
    println("Config: $(typeof(config.method)), timeout=$(config.max_time_per_point)s, ",
            "tol=$(config.f_abstol)")
    println()

    # 1. Load raw critical points from CSV
    println("Loading raw critical points...")
    raw_data = load_raw_critical_points(experiment_dir)
    println("  Found $(raw_data.n_points) critical points at degree $(raw_data.degree)")
    println("  Source: $(basename(raw_data.source_file))")
    println()

    # 2. Refine using batch processor
    start_time = time()

    refinement_results = refine_critical_points_batch(
        objective_func,
        raw_data.points;
        method = config.method,
        max_time = config.max_time_per_point,
        f_abstol = config.f_abstol,
        x_abstol = config.x_abstol,
        max_iterations = config.max_iterations,
        show_progress = config.show_progress
    )

    total_time = time() - start_time
    println()

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

    # 7. Gradient validation (if we have refined points)
    gradient_validation = if n_converged > 0
        println("Validating gradient norms ($(config.gradient_method))...")
        validate_critical_points(refined_points, objective_func;
                                tolerance=config.f_abstol,
                                gradient_method=config.gradient_method)
    else
        nothing
    end

    # 8. Save results (with Tier 1 diagnostics and gradient validation)
    save_refined_results(experiment_dir, result, raw_data.degree, refinement_results;
                        gradient_validation=gradient_validation)

    # 9. Print formatted summary
    print_refinement_summary(result, gradient_validation)

    return result
end

"""
    refine_critical_points(raw_result, objective_func, config=RefinementConfig())

Refine critical points from a RawExperimentResult object (in-memory).

This is a convenience wrapper that delegates to `refine_experiment_results()`.

# Arguments
- `raw_result`: Object with `output_dir` field (e.g., from `run_standard_experiment()`)
- `objective_func::Function`: Original objective function
- `config::RefinementConfig`: Refinement configuration

# Returns
- `RefinedExperimentResult`: Refined results

# Examples
```julia
using Globtim, GlobtimPostProcessing

# Run experiment (globtimcore)
raw = Globtim.run_standard_experiment(objective_func, domain_bounds, config)

# Refine (globtimpostprocessing)
refined = refine_critical_points(raw, objective_func, ode_refinement_config())
```
"""
function refine_critical_points(
    raw_result,
    objective_func::Function,
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
    print_refinement_summary(result, gradient_validation)

Print a formatted refinement summary using PrettyTables with colors.
"""
function print_refinement_summary(
    result::RefinedExperimentResult,
    gradient_validation::Union{GradientValidationResult, Nothing}
)
    # Color helpers
    function color_rate(rate::Float64)
        if rate >= 0.8
            return "$(GREEN)$(round(rate * 100, digits=1))%$(RESET)"
        elseif rate >= 0.5
            return "$(YELLOW)$(round(rate * 100, digits=1))%$(RESET)"
        else
            return "$(RED)$(round(rate * 100, digits=1))%$(RESET)"
        end
    end

    function format_sci(x::Float64)
        if x == Inf || x == -Inf || isnan(x)
            return "$(DIM)N/A$(RESET)"
        end
        @sprintf("%.4e", x)
    end

    # Build summary data
    convergence_rate = result.n_converged / result.n_raw

    # Section 1: Convergence Statistics
    conv_data = Any[
        "$(BOLD)Total Points$(RESET)"      "$(CYAN)$(result.n_raw)$(RESET)"
        "$(GREEN)✓$(RESET) Converged"      "$(result.n_converged) ($(color_rate(convergence_rate)))"
        "$(RED)✗$(RESET) Failed"           "$(result.n_failed)"
        "$(YELLOW)⏱$(RESET) Timeout"       "$(result.n_timeout)"
    ]

    println()
    println("$(BOLD)$(CYAN)╔══════════════════════════════════════════════════════════════════════════════╗$(RESET)")
    println("$(BOLD)$(CYAN)║$(RESET)                        $(BOLD)REFINEMENT SUMMARY$(RESET)                                $(BOLD)$(CYAN)║$(RESET)")
    println("$(BOLD)$(CYAN)╚══════════════════════════════════════════════════════════════════════════════╝$(RESET)")
    println()

    # Convergence table
    println("$(BOLD)Convergence$(RESET)")
    pretty_table(conv_data,
        header = ["Metric", "Value"],
        alignment = [:l, :r],
        tf = tf_unicode_rounded,
        show_header = false,
        crop = :none)

    # Section 2: Improvement Statistics (only if converged > 0)
    if result.n_converged > 0
        println()
        println("$(BOLD)Improvement$(RESET)")

        improvement_data = Any[
            "Mean improvement"     format_sci(result.mean_improvement)
            "Max improvement"      format_sci(result.max_improvement)
            "Best raw value"       format_sci(result.best_raw_value)
            "$(GREEN)Best refined value$(RESET)" "$(GREEN)$(format_sci(result.best_refined_value))$(RESET)"
            "Overall gain"         format_sci(result.best_raw_value - result.best_refined_value)
        ]

        pretty_table(improvement_data,
            header = ["Metric", "Value"],
            alignment = [:l, :r],
            tf = tf_unicode_rounded,
            show_header = false,
            crop = :none)
    end

    # Section 3: Gradient Validation (if available)
    if gradient_validation !== nothing
        println()
        grad_rate = gradient_validation.n_valid / length(gradient_validation.norms)

        grad_data = Any[
            "Valid critical points" "$(gradient_validation.n_valid)/$(length(gradient_validation.norms)) ($(color_rate(grad_rate)))"
            "Mean ||∇f||"           format_sci(gradient_validation.mean_norm)
            "Max ||∇f||"            format_sci(gradient_validation.max_norm)
            "Tolerance"             "$(gradient_validation.tolerance)"
        ]

        println("$(BOLD)Gradient Validation$(RESET)")
        pretty_table(grad_data,
            header = ["Metric", "Value"],
            alignment = [:l, :r],
            tf = tf_unicode_rounded,
            show_header = false,
            crop = :none)
    end

    # Section 4: Timing
    println()
    println("$(DIM)Total time: $(@sprintf("%.2f", result.total_time)) seconds$(RESET)")
    println()
end
