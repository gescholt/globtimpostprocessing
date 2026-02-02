"""
Gradient validation threshold analysis for LV4D experiments.

Finds domain size where ≥50% of polynomial critical points have ||∇f|| < tolerance.
"""

# ============================================================================
# Main Analysis Function
# ============================================================================

"""
    analyze_gradient_thresholds(results_root::String; tolerance::Float64=0.1)

Analyze gradient validation thresholds across domain sweep.

# Arguments
- `results_root::String`: Path to LV4D results directory
- `tolerance::Float64=0.1`: Gradient norm tolerance threshold

# Output
Prints summary table and finds threshold domain for ≥50% validation.
"""
function analyze_gradient_thresholds(results_root::String; tolerance::Float64=0.1)
    println("="^70)
    println("LV4D Gradient Validation Analysis")
    println("="^70)
    println("Results directory: $results_root")
    println("Tolerance: $tolerance")
    println()

    # Collect data
    data = _collect_gradient_data(results_root)

    if isempty(data)
        error("No gradient data found!")
    end

    n_domains = length(data)
    n_norms = sum(length(v) for v in values(data))
    println("Found $n_domains domains, $n_norms total gradient norms")

    # Print summary
    _print_gradient_summary(data, tolerance)

    # Find threshold
    _find_validation_threshold(data, tolerance)
end

"""
    analyze_gradient_thresholds(; tolerance::Float64=0.1)

Convenience method that finds results root automatically.
"""
function analyze_gradient_thresholds(; tolerance::Float64=0.1)
    results_root = find_results_root()
    analyze_gradient_thresholds(results_root; tolerance=tolerance)
end

# ============================================================================
# Helper Functions
# ============================================================================

function _collect_gradient_data(results_root::String)::Dict{Float64, Vector{Float64}}
    data = Dict{Float64, Vector{Float64}}()  # domain => [gradient_norms...]

    for dir in readdir(results_root, join=true)
        basename_dir = basename(dir)
        startswith(basename_dir, "lv4d_") || continue

        # Extract domain from directory name
        m = match(r"domain([0-9.]+)", basename_dir)
        m === nothing && continue
        domain = parse(Float64, m.captures[1])

        # Find critical points CSV files
        csv_files = filter(readdir(dir)) do f
            startswith(f, "critical_points_deg") && endswith(f, ".csv")
        end

        for csv_file in csv_files
            csv_path = joinpath(dir, csv_file)
            df = CSV.read(csv_path, DataFrame)

            :gradient_norm in propertynames(df) || continue

            grad_norms = filter(!isnan, df.gradient_norm)
            isempty(grad_norms) && continue

            if !haskey(data, domain)
                data[domain] = Float64[]
            end
            append!(data[domain], grad_norms)
        end
    end

    return data
end

function _print_gradient_summary(data::Dict{Float64, Vector{Float64}}, tolerance::Float64)
    domains = sort(collect(keys(data)))

    println()
    println("What this measures:")
    println("  For each polynomial critical point x (where ∇w_d(x)=0), we evaluate ||∇f(x)||")
    println("  If ||∇f(x)|| < tolerance, the polynomial CP approximates a true CP of f")
    println("  This validates that polynomial CPs are near actual critical points of the objective")
    println()
    println("Column definitions:")
    println("  Domain    = Domain half-width (search region)")
    println("  N         = Total number of polynomial critical points across all experiments")
    println("  Valid%    = % with ||∇f(x)|| < $(tolerance) (true CPs of objective f)")
    println("  ||∇f||    = Gradient norm of objective f at polynomial critical points")
    println()
    @printf("%-8s  %5s  %8s  %12s  %12s  %12s\n",
            "Domain", "#CPs", "Valid%", "Min||∇f||", "Med||∇f||", "Max||∇f||")
    println("-"^70)

    for d in domains
        norms = data[d]
        n = length(norms)
        valid_count = count(g -> g < tolerance, norms)
        valid_rate = valid_count / n * 100
        min_norm = minimum(norms)
        med_norm = median(norms)
        max_norm = maximum(norms)

        @printf("%-8.4f  %5d  %7.0f%%  %12.2e  %12.2e  %12.2e\n",
                d, n, valid_rate, min_norm, med_norm, max_norm)
    end
    println("="^70)
end

function _find_validation_threshold(data::Dict{Float64, Vector{Float64}}, tolerance::Float64)
    domains = sort(collect(keys(data)))

    println()
    println("="^70)
    println("THRESHOLD ANALYSIS: Finding domain where ≥50% of CPs are valid")
    println("="^70)
    println()

    best_domain = nothing
    best_rate = 0.0

    for d in domains
        norms = data[d]
        valid_rate = count(g -> g < tolerance, norms) / length(norms) * 100

        if valid_rate >= 50.0 && best_domain === nothing
            best_domain = d
            best_rate = valid_rate
        end

        if valid_rate > best_rate
            best_rate = valid_rate
            if best_domain === nothing
                best_domain = d
            end
        end
    end

    if best_domain !== nothing && best_rate >= 50.0
        @printf("Threshold domain for ≥50%% validation: %.4f (rate: %.1f%%)\n",
                best_domain, best_rate)
    elseif best_domain !== nothing
        @printf("No domain achieves ≥50%% validation at tolerance %.1e\n", tolerance)
        @printf("Best: domain=%.4f with %.1f%% validation\n", best_domain, best_rate)
    else
        @printf("No domain achieves ≥50%% validation at tolerance %.1e\n", tolerance)
        @printf("Best validation rate: %.1f%% (all domains equal)\n", best_rate)
    end

    println("="^70)
    println()
end
