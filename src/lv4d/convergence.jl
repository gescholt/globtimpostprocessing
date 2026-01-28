"""
Log-log convergence analysis for LV4D domain sweep.

Computes convergence rate: error ∝ domain^α
"""

# ============================================================================
# Result Type
# ============================================================================

"""
Result of convergence analysis with concise REPL display.

Fields:
- `slopes`: Dict mapping degree → convergence rate α
- `data`: Dict mapping degree → Dict(domain → Vector of recovery errors)
- `l2_data`: Dict mapping degree → Dict(domain → Vector of L2 norms)
"""
struct ConvergenceResult
    slopes::Dict{Int, Float64}
    data::Dict{Int, Dict{Float64, Vector{Float64}}}
    l2_data::Dict{Int, Dict{Float64, Vector{Float64}}}
end

function Base.show(io::IO, r::ConvergenceResult)
    print(io, "ConvergenceResult(")
    if isempty(r.slopes)
        print(io, "no data")
    else
        print(io, length(r.slopes), " degrees: ")
        for (i, (deg, α)) in enumerate(sort(collect(r.slopes)))
            i > 1 && print(io, ", ")
            print(io, "deg", deg, "→α=", round(α, digits=2))
        end
    end
    print(io, ")")
end

# ============================================================================
# Main Analysis Function
# ============================================================================

"""
    analyze_convergence(results_root::Union{String, Nothing}, filter::ExperimentFilter; export_csv::Bool=false)

Analyze convergence rate using ExperimentFilter for experiment selection.

# Arguments
- `results_root::Union{String, Nothing}`: Path to LV4D results directory, or `nothing` to search all
- `filter::ExperimentFilter`: Filter specification (should specify gn and degree range)
- `export_csv::Bool=false`: Whether to export data for plotting

# Example
```julia
filter = ExperimentFilter(gn=fixed(8), degree=sweep(4, 12))
analyze_convergence(nothing, filter; export_csv=true)
```
"""
function analyze_convergence(results_root::Union{String, Nothing}, filter::ExperimentFilter; export_csv::Bool=false)
    # Extract gn and degree range from filter
    gn = filter.gn isa FixedValue ? filter.gn.value : 8
    degree_min = filter.degree isa SweepRange ? filter.degree.min :
                 filter.degree isa FixedValue ? filter.degree.value : 4
    degree_max = filter.degree isa SweepRange ? filter.degree.max :
                 filter.degree isa FixedValue ? filter.degree.value : 10

    analyze_convergence(results_root; gn=gn, degree_min=degree_min, degree_max=degree_max,
                       export_csv=export_csv)
end

"""
    analyze_convergence(results_root::Union{String, Nothing}; gn::Int=8, degree_min::Int=4, degree_max::Int=10,
                       export_csv::Bool=false)

Analyze convergence rate from domain sweep experiments.

# Arguments
- `results_root::Union{String, Nothing}`: Path to LV4D results directory, or `nothing` to search all
- `gn::Int=8`: Filter experiments by GN value
- `degree_min::Int=4`: Minimum polynomial degree to include
- `degree_max::Int=10`: Maximum polynomial degree to include
- `export_csv::Bool=false`: Whether to export data for plotting

# Output Structure
1. Header explaining what we're computing
2. PER-DEGREE SCALING table with rates and interpretation
"""
function analyze_convergence(results_root::Union{String, Nothing}; gn::Int=8, degree_min::Int=4, degree_max::Int=10,
                            export_csv::Bool=false)
    # --- Header ---
    println()
    println("CONVERGENCE ANALYSIS (GN=$gn, degrees $degree_min-$degree_max)")
    println("─" ^ 50)
    println("Metric: recovery_error ∝ domain^α")
    println()

    # Collect data for all degrees in range
    all_data = Dict{Int, Dict{Float64, Vector{Float64}}}()
    all_l2_data = Dict{Int, Dict{Float64, Vector{Float64}}}()

    for degree in degree_min:degree_max
        data, l2_data = _collect_convergence_data(results_root; gn=gn, degree=degree)
        if !isempty(data)
            all_data[degree] = data
            all_l2_data[degree] = l2_data
        end
    end

    if isempty(all_data)
        println("No data found matching GN=$gn, degrees ∈ [$degree_min, $degree_max]")
        return ConvergenceResult(Dict{Int,Float64}(), all_data, all_l2_data)
    end

    # Compute slopes for each degree
    all_slopes = Dict{Int, Float64}()
    for degree in sort(collect(keys(all_data)))
        data = all_data[degree]
        if length(data) >= 2
            slope, _ = _compute_convergence_rate_silent(data)
            all_slopes[degree] = slope
        end
    end

    # --- PER-DEGREE SCALING table ---
    _print_convergence_table(all_slopes)

    # Export combined data if requested (only when results_root is specified)
    if export_csv && results_root !== nothing
        _export_convergence_analysis_csv(results_root, all_data, all_l2_data, gn)
    end

    return ConvergenceResult(all_slopes, all_data, all_l2_data)
end

"""
    analyze_convergence(; gn::Int=8, degree_min::Int=4, degree_max::Int=10, export_csv::Bool=false)

Convenience method that finds results root automatically.
"""
function analyze_convergence(; gn::Int=8, degree_min::Int=4, degree_max::Int=10, export_csv::Bool=false)
    results_root = find_results_root()
    analyze_convergence(results_root; gn=gn, degree_min=degree_min, degree_max=degree_max, export_csv=export_csv)
end

"""
    analyze_convergence(filter::ExperimentFilter; export_csv::Bool=false)

Convenience method that finds results root automatically and uses filter.
"""
function analyze_convergence(filter::ExperimentFilter; export_csv::Bool=false)
    results_root = find_results_root()
    analyze_convergence(results_root, filter; export_csv=export_csv)
end

# ============================================================================
# Helper Functions
# ============================================================================

function _collect_convergence_data(results_root::Union{String, Nothing}; gn::Int, degree::Int)
    data = Dict{Float64, Vector{Float64}}()      # domain => [recovery_errors...]
    l2_data = Dict{Float64, Vector{Float64}}()   # domain => [L2_norms...]

    # Match both deg8-8 (single degree) and deg4-12 (degree range) formats
    # We parse the degree range and check if our target degree is included
    pattern = Regex("lv4d_GN$(gn)_deg(\\d+)-(\\d+)_domain")

    # Get all experiment directories
    exp_dirs = find_experiments(results_root)
    for dir in exp_dirs
        basename_dir = basename(dir)

        m_deg = match(pattern, basename_dir)
        m_deg === nothing && continue

        deg_min = parse(Int, m_deg.captures[1])
        deg_max = parse(Int, m_deg.captures[2])

        # Check if this experiment includes our target degree
        # For single-degree experiments (deg8-8), only include if degree matches
        # For multi-degree experiments (deg4-12), include if degree is in range
        if deg_min == deg_max
            # Single degree experiment
            deg_min == degree || continue
        else
            # Multi-degree experiment - skip for now as they don't have per-degree results
            # These experiments report aggregate results across all degrees
            continue
        end

        # Extract domain from directory name
        m = match(r"domain([0-9.]+)_seed", basename_dir)
        m === nothing && continue
        domain = parse(Float64, m.captures[1])

        # Read results_summary.json
        summary_file = joinpath(dir, "results_summary.json")
        isfile(summary_file) || continue

        results = JSON.parsefile(summary_file)
        isempty(results) && continue
        haskey(results[1], "recovery_error") || continue

        recovery = results[1]["recovery_error"]
        l2 = get(results[1], "L2_norm", NaN)

        if !haskey(data, domain)
            data[domain] = Float64[]
            l2_data[domain] = Float64[]
        end
        push!(data[domain], recovery)
        push!(l2_data[domain], l2)
    end

    return data, l2_data
end

function _print_convergence_summary(data::Dict{Float64, Vector{Float64}},
                                   l2_data::Dict{Float64, Vector{Float64}})
    domains = sort(collect(keys(data)))

    println()
    println("Column definitions:")
    println("  Domain    = Domain half-width (parameter search region = p_center ± domain)")
    println("  N         = Number of experiments at this domain size")
    println("  Recov<5%  = % of experiments with ||p_best - p_true||/||p_true|| < 5%")
    println("  RecErr%   = Mean relative parameter recovery error × 100")
    println("  L2_norm   = Mean polynomial approximation error ||f - w_d||_L2")
    println()
    @printf("%-8s  %5s  %8s  %10s  %10s  %10s\n",
            "Domain", "N", "Recov<5%", "RecErr%", "Std%", "L2_norm")
    println("-"^70)

    for d in domains
        n = length(data[d])
        pass_rate = sum(data[d] .< 0.05) / n * 100
        mean_rec = mean(data[d]) * 100
        std_rec = std(data[d]) * 100
        mean_l2 = haskey(l2_data, d) ? mean(l2_data[d]) : NaN

        @printf("%-8.3f  %5d  %7.0f%%  %9.1f%%  %9.1f%%  %10.1f\n",
                d, n, pass_rate, mean_rec, std_rec, mean_l2)
    end
    println("="^70)
end

function _compute_convergence_rate(data::Dict{Float64, Vector{Float64}})
    domains = sort(collect(keys(data)))

    mean_domains = Float64[]
    mean_recovery = Float64[]

    for d in domains
        push!(mean_domains, d)
        push!(mean_recovery, mean(data[d]))
    end

    # Fit line to log-log data
    log_d = log10.(mean_domains)
    log_r = log10.(mean_recovery)

    # Simple linear regression
    n = length(log_d)
    slope = (n * sum(log_d .* log_r) - sum(log_d) * sum(log_r)) /
            (n * sum(log_d.^2) - sum(log_d)^2)
    intercept = (sum(log_r) - slope * sum(log_d)) / n

    # Print log-log data for external plotting
    println()
    println("Log-log data (for plotting):")
    println("log10(domain), log10(mean_recovery)")
    for i in eachindex(mean_domains)
        @printf("%.3f, %.3f\n", log10(mean_domains[i]), log10(mean_recovery[i]))
    end

    return slope, intercept
end

"""
    _compute_convergence_rate_silent(data)

Compute convergence rate without printing.
"""
function _compute_convergence_rate_silent(data::Dict{Float64, Vector{Float64}})
    domains = sort(collect(keys(data)))

    mean_domains = Float64[]
    mean_recovery = Float64[]

    for d in domains
        push!(mean_domains, d)
        push!(mean_recovery, mean(data[d]))
    end

    log_d = log10.(mean_domains)
    log_r = log10.(mean_recovery)

    n = length(log_d)
    slope = (n * sum(log_d .* log_r) - sum(log_d) * sum(log_r)) /
            (n * sum(log_d.^2) - sum(log_d)^2)
    intercept = (sum(log_r) - slope * sum(log_d)) / n

    return slope, intercept
end

"""
    _print_convergence_table(all_slopes)

Print the PER-DEGREE SCALING table with interpretations.
"""
function _print_convergence_table(all_slopes::Dict{Int, Float64})
    println("PER-DEGREE SCALING")

    degrees = sort(collect(keys(all_slopes)))

    # Build table columns
    deg_col = degrees
    rate_col = [@sprintf("%.2f", all_slopes[d]) for d in degrees]

    # Interpret rates
    interp_col = String[]
    for d in degrees
        α = all_slopes[d]
        if α < 0.5
            push!(interp_col, "Sub-linear (slow)")
        elseif α < 1.1
            push!(interp_col, "Linear convergence")
        elseif α < 1.8
            push!(interp_col, "Super-linear convergence")
        else
            push!(interp_col, "Quadratic convergence")
        end
    end

    display_df = DataFrame(
        "Deg" => deg_col,
        "α (rate)" => rate_col,
        "Interpretation" => interp_col
    )

    pretty_table(display_df;
        header = ["Deg", "α (rate)", "Interpretation"],
        alignment = [:r, :r, :l],
        crop = :none,
        tf = tf_unicode_rounded
    )
end

# ============================================================================
# CSV Export for Convergence Analysis
# ============================================================================

"""
    _export_convergence_analysis_csv(results_root, all_data, all_l2_data, gn)

Export convergence analysis data for plotting.

Creates a CSV with columns suitable for log-log convergence plots per degree.
"""
function _export_convergence_analysis_csv(results_root::String,
                                         all_data::Dict{Int, Dict{Float64, Vector{Float64}}},
                                         all_l2_data::Dict{Int, Dict{Float64, Vector{Float64}}},
                                         gn::Int)
    output_dir = joinpath(results_root, "sweep_analysis")
    mkpath(output_dir)

    # Create per-observation DataFrame
    rows = NamedTuple[]
    for degree in sort(collect(keys(all_data)))
        data = all_data[degree]
        l2_data = all_l2_data[degree]

        for domain in sort(collect(keys(data)))
            recovery_errors = data[domain]
            l2_norms = get(l2_data, domain, fill(NaN, length(recovery_errors)))

            for (i, (rec, l2)) in enumerate(zip(recovery_errors, l2_norms))
                push!(rows, (
                    GN = gn,
                    degree = degree,
                    domain = domain,
                    seed = i,  # Inferred seed (not actual)
                    recovery_error = rec,
                    L2_norm = l2,
                    log10_domain = log10(domain),
                    log10_recovery = log10(max(rec, 1e-16)),
                    log10_L2 = isnan(l2) ? NaN : log10(max(l2, 1e-16)),
                    success = rec < 0.05
                ))
            end
        end
    end

    df = DataFrame(rows)

    # Write per-observation data
    output_file = joinpath(output_dir, "lv4d_convergence_by_degree.csv")
    CSV.write(output_file, df)

    # Also create aggregated summary
    summary_rows = NamedTuple[]
    for degree in sort(collect(keys(all_data)))
        data = all_data[degree]
        l2_data = all_l2_data[degree]

        for domain in sort(collect(keys(data)))
            recovery_errors = data[domain]
            l2_norms = get(l2_data, domain, Float64[])

            push!(summary_rows, (
                GN = gn,
                degree = degree,
                domain = domain,
                n_samples = length(recovery_errors),
                mean_recovery = mean(recovery_errors),
                std_recovery = std(recovery_errors),
                mean_L2 = isempty(l2_norms) ? NaN : mean(filter(!isnan, l2_norms)),
                std_L2 = isempty(l2_norms) ? NaN : std(filter(!isnan, l2_norms)),
                success_rate = mean(recovery_errors .< 0.05),
                log10_domain = log10(domain),
                log10_mean_recovery = log10(max(mean(recovery_errors), 1e-16))
            ))
        end
    end

    summary_df = DataFrame(summary_rows)
    summary_file = joinpath(output_dir, "lv4d_convergence_summary.csv")
    CSV.write(summary_file, summary_df)

    println()
    println("="^80)
    println("EXPORTED CONVERGENCE DATA")
    println("="^80)
    println()
    println("Per-observation data: $output_file")
    println("Aggregated summary:   $summary_file")
    println()
    println("Use with globtimplots.LV4DPlots:")
    println("  using GlobtimPlots, DataFrames, CSV")
    println("  df = CSV.read(\"$summary_file\", DataFrame)")
    println("  fig = plot_lv4d_convergence_rate(df)")
    println()

    return output_file, summary_file
end
