# analyze_convergence.jl
# Log-log convergence analysis for LV4D domain sweep
#
# Run: julia --project=. experiments/lv4d_2025/analyze_convergence.jl

using JSON
using Statistics
using Printf

const RESULTS_DIR = joinpath(dirname(dirname(@__DIR__)), "globtim_results", "lotka_volterra_4d")

# Collect data from all lv4d_GN8_deg8-8 experiments
function collect_data()
    data = Dict{Float64, Vector{Float64}}()  # domain => [recovery_errors...]
    l2_data = Dict{Float64, Vector{Float64}}()  # domain => [L2_norms...]

    for dir in readdir(RESULTS_DIR, join=true)
        basename_dir = basename(dir)
        if !startswith(basename_dir, "lv4d_GN8_deg8-8_domain")
            continue
        end

        # Extract domain from directory name
        m = match(r"domain([0-9.]+)_seed", basename_dir)
        if m === nothing
            continue
        end
        domain = parse(Float64, m.captures[1])

        # Read results_summary.json
        summary_file = joinpath(dir, "results_summary.json")
        if !isfile(summary_file)
            continue
        end

        results = JSON.parsefile(summary_file)
        if isempty(results) || !haskey(results[1], "recovery_error")
            continue
        end

        recovery = results[1]["recovery_error"]
        l2 = results[1]["L2_norm"]

        if !haskey(data, domain)
            data[domain] = Float64[]
            l2_data[domain] = Float64[]
        end
        push!(data[domain], recovery)
        push!(l2_data[domain], l2)
    end

    return data, l2_data
end

# Print summary table
function print_summary(data, l2_data)
    domains = sort(collect(keys(data)))

    println()
    println("="^70)
    println("LV4D Convergence Summary (GN=8, degree=8)")
    println("="^70)
    println()
    @printf("%-8s  %5s  %8s  %10s  %10s  %10s\n",
            "Domain", "N", "Pass%", "Mean Rec", "Std Rec", "Mean L2")
    println("-"^70)

    for d in domains
        n = length(data[d])
        pass_rate = sum(data[d] .< 0.05) / n * 100
        mean_rec = mean(data[d]) * 100
        std_rec = std(data[d]) * 100
        mean_l2 = mean(l2_data[d])

        @printf("%-8.3f  %5d  %7.0f%%  %9.1f%%  %9.1f%%  %10.1f\n",
                d, n, pass_rate, mean_rec, std_rec, mean_l2)
    end
    println("="^70)
end

# Compute convergence rate from log-log fit
function compute_convergence_rate(data)
    domains = sort(collect(keys(data)))

    mean_domains = Float64[]
    mean_recovery = Float64[]

    for d in domains
        push!(mean_domains, d)
        push!(mean_recovery, mean(data[d]))
    end

    # Fit line to log-log data (linear regression on log-transformed data)
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

# Main
function main()
    println("Collecting data from: $RESULTS_DIR")
    data, l2_data = collect_data()

    if isempty(data)
        error("No data found!")
    end

    println("Found $(length(data)) domains, $(sum(length(v) for v in values(data))) total experiments")

    print_summary(data, l2_data)

    slope, _ = compute_convergence_rate(data)

    println()
    println("="^70)
    @printf("CONVERGENCE RATE: error ∝ domain^%.2f\n", slope)
    println("="^70)
    println()
end

main()
