# Workflow Examples

Complete end-to-end examples for common analysis workflows.

## Example 1: Single Experiment Analysis

A complete workflow for analyzing a single experiment.

```julia
using GlobtimPostProcessing

# ============================================================
# 1. Setup
# ============================================================

experiment_dir = "path/to/lotka_volterra_4d_exp"

# Define objective function (must match experiment)
function lotka_volterra_objective(p::Vector{Float64})
    # ODE solver and trajectory matching
    # (implementation depends on your problem)
    return trajectory_distance(p)
end

# ============================================================
# 2. Quality Check
# ============================================================

println("=== Quality Assessment ===")

# L2 approximation quality
l2_result = check_l2_quality(experiment_dir)
println("L2 Grade: \$(l2_result.grade)")

# Stagnation check
stagnation = detect_stagnation(experiment_dir)
if stagnation.is_stagnant
    println("WARNING: Stagnation at degree \$(stagnation.stagnation_start_degree)")
end

# Distribution quality
dist = check_objective_distribution_quality(experiment_dir)
println("Outliers: \$(dist.num_outliers) (\$(round(100*dist.outlier_fraction, digits=1))%)")

# ============================================================
# 3. Critical Point Refinement
# ============================================================

println("\n=== Refinement ===")

# Use ODE-specific config for robust refinement
config = ode_refinement_config()
refined = refine_experiment_results(experiment_dir, lotka_volterra_objective, config)

# Summary printed automatically
# Additional details:
println("Converged: \$(refined.n_converged)/\$(refined.n_raw)")
println("Best raw value: \$(refined.best_raw_value)")
println("Best refined value: \$(refined.best_refined_value)")

# ============================================================
# 4. Parameter Recovery (if ground truth available)
# ============================================================

println("\n=== Parameter Recovery ===")

if has_ground_truth(experiment_dir)
    # Recovery from raw points
    raw_stats = compute_parameter_recovery_stats(experiment_dir)
    println("Raw recovery error: \$(raw_stats.min_distance)")

    # Recovery from refined points
    config = load_experiment_config(experiment_dir)
    p_true = config["p_true"]
    best_refined = refined.refined_points[refined.best_refined_idx]
    refined_distance = param_distance(best_refined, p_true)
    println("Refined recovery error: \$(refined_distance)")

    improvement = 100 * (1 - refined_distance / raw_stats.min_distance)
    println("Improvement: \$(round(improvement, digits=1))%")
else
    println("No ground truth available")
end

# ============================================================
# 5. Summary Report
# ============================================================

println("\n=== Summary ===")
println("Experiment: \$(experiment_dir)")
println("L2 Quality: \$(l2_result.grade)")
println("Convergence Rate: \$(round(100 * refined.n_converged / refined.n_raw, digits=1))%")
println("Best Objective: \$(refined.best_refined_value)")
```

## Example 2: Campaign Comparison

Comparing results across multiple experiments.

```julia
using GlobtimPostProcessing
using DataFrames
using Statistics

# ============================================================
# 1. Load Campaign
# ============================================================

campaign_dir = "path/to/domain_sweep_campaign"
campaign = load_campaign_with_progress(campaign_dir)

println("Campaign: \$(campaign.campaign_id)")
println("Experiments: \$(length(campaign.experiments))")

# ============================================================
# 2. Build Comparison Table
# ============================================================

results = DataFrame(
    experiment = String[],
    domain_range = Float64[],
    degree = Int[],
    l2_grade = Symbol[],
    n_critical = Int[],
    convergence_rate = Float64[],
    recovery_error = Float64[]
)

for exp in campaign.experiments
    # Load config
    config = load_experiment_config(exp.source_path)

    # Quality check
    l2 = check_l2_quality(exp.source_path)

    # Refinement (simplified - just get convergence rate)
    # In practice, you'd run full refinement
    n_critical = size(exp.critical_points, 1)

    # Recovery
    recovery = if has_ground_truth(exp.source_path)
        stats = compute_parameter_recovery_stats(exp.source_path)
        stats.min_distance
    else
        NaN
    end

    push!(results, (
        experiment = exp.experiment_id,
        domain_range = config["domain_range"],
        degree = config["degree_max"],
        l2_grade = l2.grade,
        n_critical = n_critical,
        convergence_rate = 0.0,  # Placeholder
        recovery_error = recovery
    ))
end

# ============================================================
# 3. Analyze Trends
# ============================================================

println("\n=== Trends by Domain Size ===")

by_domain = groupby(results, :domain_range)
for group in by_domain
    domain = first(group.domain_range)
    mean_recovery = mean(filter(!isnan, group.recovery_error))
    n_excellent = count(g -> g == :excellent, group.l2_grade)

    println("Domain \$domain:")
    println("  Experiments: \$(nrow(group))")
    println("  Excellent L2: \$n_excellent")
    println("  Mean recovery: \$(mean_recovery)")
end

# ============================================================
# 4. Export Results
# ============================================================

CSV.write("campaign_comparison.csv", results)
println("\nResults saved to campaign_comparison.csv")
```

## Example 3: ODE Parameter Estimation Pipeline

Complete pipeline for ODE-based parameter estimation.

```julia
using GlobtimPostProcessing
using DifferentialEquations
using ForwardDiff

# ============================================================
# 1. Define ODE Problem
# ============================================================

# Lotka-Volterra predator-prey model
function lotka_volterra!(du, u, p, t)
    x, y = u
    alpha, beta, gamma, delta = p

    du[1] = alpha * x - beta * x * y
    du[2] = delta * x * y - gamma * y
end

# Reference trajectory (from known parameters)
p_true = [1.0, 0.5, 0.5, 0.5]
u0 = [1.0, 1.0]
tspan = (0.0, 10.0)
prob_true = ODEProblem(lotka_volterra!, u0, tspan, p_true)
sol_true = solve(prob_true, Tsit5())

# Objective function
function trajectory_objective(p)
    prob = remake(prob_true, p=p)
    sol = solve(prob, Tsit5(), saveat=0.1)

    if sol.retcode != :Success
        return 1e10  # Penalty for failed solve
    end

    # L2 distance to reference
    error = 0.0
    for i in eachindex(sol.t)
        t = sol.t[i]
        ref = sol_true(t)
        error += sum((sol.u[i] .- ref).^2)
    end
    return sqrt(error)
end

# ============================================================
# 2. Run Analysis
# ============================================================

experiment_dir = "path/to/lv_experiment"

# Quality check
l2 = check_l2_quality(experiment_dir)
println("L2 Grade: \$(l2.grade)")

# Refine with ODE-specific settings
config = ode_refinement_config()
refined = refine_experiment_results(experiment_dir, trajectory_objective, config)

# ============================================================
# 3. Validate Best Estimate
# ============================================================

best_estimate = refined.refined_points[refined.best_refined_idx]

println("\n=== Best Parameter Estimate ===")
println("Found: \$best_estimate")
println("True:  \$p_true")
println("Error: \$(param_distance(best_estimate, p_true))")

# Validate gradient
grad_norm = compute_gradient_norm(trajectory_objective, best_estimate)
println("Gradient norm: \$grad_norm")

# ============================================================
# 4. Landscape Fidelity Check
# ============================================================

# Load polynomial minimum
df = load_critical_points_for_degree(experiment_dir, refined.degree)
x_star = Vector(df[1, [:x1, :x2, :x3, :x4]])

# Check if in same basin
result = check_objective_proximity(x_star, best_estimate, trajectory_objective)
println("\nLandscape Fidelity:")
println("Same basin: \$(result.is_same_basin)")
println("Relative diff: \$(result.metric)")
```

## Example 4: Quality-Gated Pipeline

Only process high-quality experiments.

```julia
using GlobtimPostProcessing

# ============================================================
# Quality Gate Function
# ============================================================

function quality_gate(experiment_dir; min_grade=:good, max_outlier_frac=0.1)
    # L2 quality
    l2 = check_l2_quality(experiment_dir)
    if l2.grade == :poor
        return false, "L2 quality poor"
    end

    # Stagnation
    stagnation = detect_stagnation(experiment_dir)
    if stagnation.is_stagnant && stagnation.stagnant_count >= 3
        return false, "Severe stagnation"
    end

    # Outliers
    dist = check_objective_distribution_quality(experiment_dir)
    if dist.outlier_fraction > max_outlier_frac
        return false, "Too many outliers"
    end

    return true, "Passed"
end

# ============================================================
# Process Campaign with Quality Gate
# ============================================================

function process_with_quality_gate(campaign_dir, objective)
    campaign = load_campaign_results(campaign_dir)

    passed = []
    failed = []

    for exp in campaign.experiments
        ok, reason = quality_gate(exp.source_path)

        if ok
            push!(passed, exp)
        else
            push!(failed, (exp, reason))
        end
    end

    println("Quality Gate Results:")
    println("  Passed: \$(length(passed))")
    println("  Failed: \$(length(failed))")

    # Show failures
    for (exp, reason) in failed
        println("  - \$(exp.experiment_id): \$reason")
    end

    # Process passed experiments
    println("\nProcessing passed experiments...")

    results = []
    for exp in passed
        refined = refine_experiment_results(exp.source_path, objective)
        push!(results, refined)
    end

    return results
end
```

## Example 5: Batch Refinement Script

Script for batch processing many experiments.

```julia
#!/usr/bin/env julia

using GlobtimPostProcessing
using ProgressMeter
using Dates

# ============================================================
# Configuration
# ============================================================

const CAMPAIGN_DIR = ARGS[1]  # Pass as command line argument
const OUTPUT_DIR = get(ARGS, 2, "batch_results_\$(Dates.format(now(), "yyyymmdd_HHMMSS"))")

# ============================================================
# Define Objective (customize for your problem)
# ============================================================

function my_objective(p::Vector{Float64})
    # Your objective function here
    return sum(p.^2)  # Placeholder
end

# ============================================================
# Main
# ============================================================

function main()
    mkpath(OUTPUT_DIR)

    # Load campaign
    println("Loading campaign from: \$CAMPAIGN_DIR")
    campaign = load_campaign_results(CAMPAIGN_DIR)
    n = length(campaign.experiments)
    println("Found \$n experiments")

    # Process each experiment
    config = ode_refinement_config()
    summary = []

    @showprogress for exp in campaign.experiments
        try
            refined = refine_experiment_results(
                exp.source_path,
                my_objective,
                config
            )

            push!(summary, (
                id = exp.experiment_id,
                status = "success",
                n_converged = refined.n_converged,
                best_value = refined.best_refined_value
            ))
        catch e
            push!(summary, (
                id = exp.experiment_id,
                status = "failed",
                n_converged = 0,
                best_value = Inf
            ))
            @warn "Failed to process \$(exp.experiment_id): \$e"
        end
    end

    # Write summary
    summary_df = DataFrame(summary)
    CSV.write(joinpath(OUTPUT_DIR, "batch_summary.csv"), summary_df)

    # Report
    n_success = count(s -> s.status == "success", summary)
    println("\nBatch Complete:")
    println("  Successful: \$n_success / \$n")
    println("  Results in: \$OUTPUT_DIR")
end

main()
```

## Running the Examples

Save any example to a file and run:

```bash
julia --project=. example_script.jl
```

Or run interactively in the REPL:

```julia
include("example_script.jl")
```

## See Also

- [Getting Started](getting_started.md) - Basic concepts
- [Critical Point Refinement](refinement.md) - Refinement details
- [Campaign Analysis](campaign_analysis.md) - Multi-experiment analysis
- [API Reference](api_reference.md) - Full function documentation
