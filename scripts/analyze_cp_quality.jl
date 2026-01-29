#!/usr/bin/env julia
"""
Analyze critical point quality with focus on distance to ground truth.

Displays:
1. Histogram of ||x - p*|| distance to true parameters (PRIMARY METRIC)
2. Histogram of ||∇f(x)|| gradient norms (validates if polynomial CP is near true CP)
3. Histogram of |f(x) - w_d(x)| evaluation errors (polynomial quality diagnostic)
4. Summary table sorted by distance to truth (best recovery first)

Usage:
    julia --project=globtim globtim/experiments/lv4d_2025/analyze_cp_quality.jl [results_dir]

If no directory is provided, shows interactive menu of recent experiments.
"""

const SCRIPT_DIR = @__DIR__
const PROJECT_ROOT = abspath(joinpath(SCRIPT_DIR, "..", ".."))

using Pkg
Pkg.activate(PROJECT_ROOT)

using CSV
using DataFrames
using Statistics
using Printf
using UnicodePlots
using PrettyTables
using JSON3
using LinearAlgebra
import REPL
using REPL.TerminalMenus

function degree_summary(df::DataFrame)::Union{DataFrame, Nothing}
    hasproperty(df, :gradient_norm) || return nothing
    hasproperty(df, :eval_error) || return nothing

    gdf = groupby(df, :degree)
    summary = combine(gdf,
        nrow => :count,
        :gradient_norm => (x -> minimum(filter(!isnan, x))) => :grad_min,
        :gradient_norm => (x -> median(filter(!isnan, x))) => :grad_med,
        :gradient_norm => (x -> maximum(filter(!isnan, x))) => :grad_max,
        :eval_error => (x -> minimum(filter(!isnan, x))) => :err_min,
        :eval_error => (x -> maximum(filter(!isnan, x))) => :err_max
    )
    sort!(summary, :degree)
    return summary
end

function list_experiments(results_root::String; limit::Int=15)::Vector{String}
    isdir(results_root) || return String[]
    dirs = filter(isdir, readdir(results_root, join=true))
    sorted = sort(dirs, by=mtime, rev=true)
    return sorted[1:min(limit, length(sorted))]
end

function select_experiment()::String
    results_root::String = joinpath(dirname(PROJECT_ROOT), "globtim_results", "lotka_volterra_4d")
    experiments = list_experiments(results_root)
    isempty(experiments) && error("No experiments found in: $results_root")

    options = map(experiments) do exp
        name = basename(exp)
        age = time() - mtime(exp)
        age_str = age < 60 ? "$(round(Int, age))s" :
                  age < 3600 ? "$(round(Int, age/60))m" :
                  age < 86400 ? "$(round(Int, age/3600))h" : "$(round(Int, age/86400))d"
        "$name ($age_str ago)"
    end

    menu = RadioMenu(options, pagesize=15)
    println("\nSelect experiment (most recent first):")
    choice = request(menu)
    choice == -1 && error("Selection cancelled")
    return experiments[choice]
end

function analyze_results(results_dir::String)::Nothing
    # Find critical point CSV files
    all_files::Vector{String} = readdir(results_dir, join=true)
    csv_files = filter(f -> startswith(basename(f), "critical_points_deg_") && endswith(f, ".csv"), all_files)
    isempty(csv_files) && error("No critical_points_deg_*.csv files found in: $results_dir")

    # Load p_true from experiment config
    config_path = joinpath(results_dir, "experiment_config.json")
    isfile(config_path) || error("experiment_config.json not found in: $results_dir")
    config = JSON3.read(read(config_path, String))
    p_true = Float64.(config.p_true)
    dim = length(p_true)

    # Load and combine
    dfs::Vector{DataFrame} = DataFrame[]
    for f in csv_files
        df = CSV.read(f, DataFrame)
        m = match(r"critical_points_deg_(\d+)\.csv", basename(f))
        m !== nothing && (df[!, :degree] .= parse(Int, m.captures[1]))
        push!(dfs, df)
    end
    df = vcat(dfs...)

    # Compute distance to true parameters for each critical point
    x_cols::Vector{Symbol} = [Symbol("x$i") for i in 1:dim]
    all_cols_exist::Bool = all(c -> hasproperty(df, c), x_cols)
    if all_cols_exist
        distances::Vector{Float64} = [norm([row[c] for c in x_cols] .- p_true) for row in eachrow(df)]
        df[!, :dist_to_true] = distances
    end

    println("\n" * "="^70)
    println("Critical Point Quality Analysis")
    println("="^70)
    println("Results: $(basename(results_dir))")
    println("Total critical points: $(nrow(df))")
    @printf("True parameters: [%s]\n", join([@sprintf("%.4f", p) for p in p_true], ", "))

    # Degree summary table (when multiple degrees)
    if length(unique(df.degree)) > 1
        summary = degree_summary(df)
        if summary !== nothing
            println("\n" * "-"^70)
            println("Degree Summary")
            println("-"^70)

            headers = ["deg", "#CPs", "min ‖∇f‖", "med ‖∇f‖", "max ‖∇f‖", "min |f-w|", "max |f-w|"]
            ft_summary = (v, _, j) -> begin
                if j >= 3 && v isa Number && !isnan(v)
                    @sprintf("%.2e", v)
                else
                    string(v)
                end
            end
            pretty_table(summary, header=headers, formatters=(ft_summary,),
                        alignment=:r, crop=:none, tf=tf_unicode_rounded)
        end
    end

    # Histogram 1: Distance to true parameters (PRIMARY METRIC)
    if hasproperty(df, :dist_to_true)
        dists = filter(!isnan, df.dist_to_true)
        if !isempty(dists)
            println("\n" * "-"^70)
            println("||x - p*|| distance to true parameters (log₁₀)")
            println("-"^70)
            log_dists = log10.(max.(dists, 1e-16))
            nbins = max(5, min(15, length(log_dists) ÷ 3 + 1))
            plt = histogram(log_dists, nbins=nbins, vertical=true, height=10, width=60,
                           xlabel="log₁₀(||x-p*||)", title="")
            println(plt)
            best_recovery = minimum(dists)
            @printf("  n=%d | best=%.2e | [%.2e, %.2e]\n",
                    length(dists), best_recovery, minimum(dists), maximum(dists))
        end
    end

    # Histogram 2: Gradient norms (validates if polynomial CP is near true CP of f)
    GRADIENT_TOL = 1e-6
    if hasproperty(df, :gradient_norm)
        grads = filter(!isnan, df.gradient_norm)
        if !isempty(grads)
            println("\n" * "-"^70)
            println("||∇f(x)|| at polynomial CPs (log₁₀; valid if <-6)")
            println("-"^70)
            log_grads = log10.(max.(grads, 1e-16))
            nbins = max(5, min(15, length(log_grads) ÷ 3 + 1))
            plt = histogram(log_grads, nbins=nbins, vertical=true, height=10, width=60,
                           xlabel="log₁₀(||∇f||)", title="")
            println(plt)
            valid_count = count(g -> g < GRADIENT_TOL, grads)
            @printf("  n=%d | [%.2e, %.2e] | %d valid (||∇f||<1e-6)\n",
                    length(grads), minimum(grads), maximum(grads), valid_count)
        end
    end

    # Histogram 3: Evaluation errors (secondary - polynomial quality diagnostic)
    if hasproperty(df, :eval_error)
        errs = filter(!isnan, df.eval_error)
        if !isempty(errs)
            println("\n" * "-"^70)
            println("|f(x) - w_d(x)| evaluation error (log₁₀ scale; polynomial quality)")
            println("-"^70)
            log_errs = log10.(max.(errs, 1e-16))
            nbins = max(5, min(15, length(log_errs) ÷ 3 + 1))
            plt = histogram(log_errs, nbins=nbins, vertical=true, height=10, width=60,
                           xlabel="log₁₀(|f-w|)", title="")
            println(plt)
            @printf("  n=%d | [%.2e, %.2e]\n",
                    length(errs), minimum(errs), maximum(errs))
        end
    end

    # Summary table
    println("\n" * "-"^70)
    println("Critical Points Summary")
    println("-"^70)

    # Build table data - order: degree, f(x), ||x-p*||, ||∇f||, |f-w|
    cols_to_show = [:degree]
    hasproperty(df, :z) && push!(cols_to_show, :z)
    hasproperty(df, :dist_to_true) && push!(cols_to_show, :dist_to_true)
    hasproperty(df, :gradient_norm) && push!(cols_to_show, :gradient_norm)
    hasproperty(df, :eval_error) && push!(cols_to_show, :eval_error)
    hasproperty(df, :critical_type) && push!(cols_to_show, :critical_type)

    # Sort by distance to truth (best recovery first), then by degree
    sort_cols = hasproperty(df, :dist_to_true) ? [:dist_to_true, :degree] : [:degree]
    sorted_df = sort(df, sort_cols)
    table_df = select(sorted_df, cols_to_show)

    # Column headers
    header_map = Dict(
        :degree => "deg",
        :z => "f(x)",
        :dist_to_true => "||x-p*||",
        :gradient_norm => "||∇f||",
        :eval_error => "|f-w|",
        :critical_type => "type"
    )
    headers = [get(header_map, c, string(c)) for c in cols_to_show]

    # Formatter for scientific notation
    ft_sci = (v, _, j) -> begin
        col = cols_to_show[j]
        if col in [:z, :dist_to_true, :gradient_norm, :eval_error] && v isa Number && !isnan(v)
            @sprintf("%.2e", v)
        else
            string(v)
        end
    end

    pretty_table(table_df, header=headers, formatters=(ft_sci,),
                 alignment=:r, crop=:none, tf=tf_unicode_rounded)

    println()
end

# Main
results_dir = length(ARGS) >= 1 ? ARGS[1] : select_experiment()
analyze_results(results_dir)
