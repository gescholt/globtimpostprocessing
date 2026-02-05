"""
    Experiment Display

Reusable display and orchestration functions for the experiment pipeline.
These functions extract common patterns from demo scripts into library code,
supporting the 3-step pipeline: Setup → Run Globtim → Post-Process.

Functions:
- `print_experiment_header`: Setup banner + key-value summary table
- `print_poly_summary_table`: Step 2 results → polynomial approximation summary
- `compute_degree_capture_results`: Step 3 data — capture analysis per successful degree
- `run_degree_analyses`: Step 3 orchestration — gradient validation + refinement per degree
- `print_degree_analysis_table`: Step 3 display — gradient + refinement results
- `build_degree_convergence_info`: Step 3 data — cross-reference degree/gradient/capture data
- `find_best_estimate`: Step 3 data — find best minimum across all degrees
- `print_parameter_recovery_table`: Step 3 display — per-parameter recovery table
- `print_recovery_verdict`: Step 3 display — parameter recovery verdict banner
- `print_best_minimum`: Step 3 display — best minimum + colored banner (benchmark experiments)
- `print_error_banner`: Step 3 display — red error banner for no-results cases
"""

# ─── Setup display ────────────────────────────────────────────────────────────

"""
    print_experiment_header(title, setup_pairs; io=stdout)

Print a styled experiment header banner and a key-value setup summary table.

# Arguments
- `title::String`: Title text for the banner (e.g., "Deuflhard 4D: Capture Analysis")
- `setup_pairs::Matrix{String}`: N×2 matrix of [label value; label value; ...] pairs
- `io::IO`: Output stream (default: stdout)

# Example
```julia
setup = ["Function" "Deuflhard 4D"; "Dimension" "4"; "Grid" "12^4 = 20736"]
print_experiment_header("Deuflhard 4D Demo", setup)
```
"""
function print_experiment_header(title::String, setup_pairs::Matrix{String}; io::IO=stdout)
    W = 80
    printstyled(io, "="^W * "\n"; color=:blue, bold=true)
    printstyled(io, " " * title * "\n"; color=:white, bold=true)
    printstyled(io, "="^W * "\n"; color=:blue, bold=true)

    pretty_table(io, setup_pairs;
        show_header=false,
        tf=tf_borderless,
        alignment=[:r, :l],
        highlighters=(
            Highlighter((_, i, j) -> j == 1, bold=true, foreground=:cyan),
        ),
        vlines=[1],
    )
end

# ─── Step 2 results display ──────────────────────────────────────────────────

"""
    print_poly_summary_table(degree_results; show_timing_breakdown=false, io=stdout)

Print a polynomial approximation summary table from degree results.

Columns: Degree, # CPs, L2 err, Best f(x), Status, [Poly time, HC Solve,] Total.
When `show_timing_breakdown=true`, includes the Poly time and HC Solve columns
(requires `polynomial_construction_time` and `critical_point_solving_time` fields).

# Arguments
- `degree_results`: Vector of degree result objects with fields: `degree`, `n_critical_points`,
  `l2_approx_error`, `best_objective`, `status`, `total_computation_time`, and optionally
  `polynomial_construction_time`, `critical_point_solving_time`.
- `show_timing_breakdown::Bool`: Whether to show Poly/HC columns (default: false)
- `io::IO`: Output stream (default: stdout)
"""
function print_poly_summary_table(degree_results; show_timing_breakdown::Bool=false, io::IO=stdout)
    print_section("Polynomial Approximation (Globtim)"; io=io)

    n = length(degree_results)
    n_cols = show_timing_breakdown ? 8 : 6
    data = Matrix{Any}(undef, n, n_cols)

    for (row, dr) in enumerate(degree_results)
        col = 1
        data[row, col] = dr.degree; col += 1
        data[row, col] = dr.n_critical_points; col += 1
        data[row, col] = fmt_sci(dr.l2_approx_error); col += 1
        data[row, col] = dr.best_objective !== nothing ? fmt_sci(dr.best_objective) : "N/A"; col += 1
        data[row, col] = dr.status; col += 1
        if show_timing_breakdown
            data[row, col] = fmt_time(dr.polynomial_construction_time); col += 1
            data[row, col] = fmt_time(dr.critical_point_solving_time); col += 1
        end
        data[row, col] = fmt_time(dr.total_computation_time)
    end

    status_col = 5
    header = if show_timing_breakdown
        ["Degree", "# CPs", "L2 err", "Best f(x)", "Status", "Poly time", "HC Solve", "Total"]
    else
        ["Degree", "# CPs", "L2 err", "Best f(x)", "Status", "Time"]
    end
    alignment = if show_timing_breakdown
        [:r, :r, :r, :r, :c, :r, :r, :r]
    else
        [:r, :r, :r, :r, :c, :r]
    end

    styled_table(io, data;
        header=header,
        alignment=alignment,
        highlighters=(
            Highlighter((d, i, j) -> j == status_col && d[i, status_col] == "success",
                foreground=:green, bold=true),
            Highlighter((d, i, j) -> j == status_col && d[i, status_col] != "success",
                foreground=:red, bold=true),
        ),
    )
end

# ─── Step 3 capture analysis ─────────────────────────────────────────────────

"""
    compute_degree_capture_results(degree_results, known_cps) -> Vector{Tuple{Int, CaptureResult}}

Compute capture analysis for each successful degree. Filters out failed degrees
and degrees with zero critical points.

# Arguments
- `degree_results`: Vector of degree result objects (from `run_standard_experiment`)
- `known_cps::KnownCriticalPoints`: Ground truth critical points

# Returns
- `Vector{Tuple{Int, CaptureResult}}`: One `(degree, CaptureResult)` per successful degree
"""
function compute_degree_capture_results(
    degree_results,
    known_cps::KnownCriticalPoints,
)::Vector{Tuple{Int, CaptureResult}}
    results = Tuple{Int, CaptureResult}[]
    for dr in degree_results
        if dr.status != "success" || dr.n_critical_points == 0
            continue
        end
        cr = compute_capture_analysis(known_cps, dr.critical_points)
        push!(results, (dr.degree, cr))
    end
    return results
end

# ─── Step 3 orchestration ────────────────────────────────────────────────────

"""
    DegreeAnalysisResult

Type alias for the per-degree analysis tuple: `(degree, GradientValidationResult, RefinedExperimentResult)`.
"""
const DegreeAnalysisResult = Tuple{Int, GradientValidationResult, RefinedExperimentResult}

"""
    run_degree_analyses(degree_results, objective, output_dir, refinement_config; ...) -> Vector{DegreeAnalysisResult}

For each successful degree: validate gradient norms and refine critical points.
Returns a vector of `(degree, GradientValidationResult, RefinedExperimentResult)` tuples.

# Arguments
- `degree_results`: Vector of degree result objects (from `run_standard_experiment`)
- `objective::Function`: Objective function for refinement (may be Float64-wrapped)
- `output_dir::String`: Experiment output directory (where raw CP CSVs are stored)
- `refinement_config::RefinementConfig`: Configuration for Nelder-Mead refinement

# Keyword Arguments
- `gradient_method::Symbol = :forwarddiff`: Gradient computation method (`:forwarddiff` or `:finitediff`)
- `gradient_objective::Function = objective`: Objective for gradient computation (may differ from
  `objective` if the latter has type annotations blocking AD)
- `io::IO = stdout`: Output stream for progress messages

# Example
```julia
analyses = run_degree_analyses(degree_results, objective, output_dir, ref_config;
                                gradient_method=:forwarddiff, gradient_objective=deuflhard_4d)
```
"""
function run_degree_analyses(
    degree_results,
    objective::Function,
    output_dir::String,
    refinement_config::RefinementConfig;
    gradient_method::Symbol = :forwarddiff,
    gradient_objective::Function = objective,
    io::IO = stdout,
)::Vector{DegreeAnalysisResult}

    results = DegreeAnalysisResult[]

    for dr in degree_results
        if dr.status != "success" || dr.n_critical_points == 0
            continue
        end

        gv = validate_critical_points(dr.critical_points, gradient_objective;
                                       gradient_method=gradient_method)

        println(io, "  Refining degree $(dr.degree) ($(dr.n_critical_points) points)...")
        refined = refine_experiment_results(output_dir, objective, refinement_config;
                                             degree=dr.degree)

        push!(results, (dr.degree, gv, refined))
    end

    return results
end

"""
    print_degree_analysis_table(degree_analyses; io=stdout)

Print a summary table of gradient validation + refinement results per degree.

Columns: Deg, # CPs, min ||∇f||, med ||∇f||, Converged, Best raw, Best ref, Time.
Highlights: best gradient row (green), best refined value (green).

# Arguments
- `degree_analyses::Vector{DegreeAnalysisResult}`: Output from `run_degree_analyses`
- `io::IO`: Output stream (default: stdout)
"""
function print_degree_analysis_table(
    degree_analyses::Vector{DegreeAnalysisResult};
    io::IO = stdout,
)
    isempty(degree_analyses) && return

    n = length(degree_analyses)
    data = Matrix{Any}(undef, n, 8)

    for (row, (deg, gv, ref)) in enumerate(degree_analyses)
        data[row, 1] = deg
        data[row, 2] = length(gv.norms)
        data[row, 3] = fmt_sci(gv.min_norm)
        data[row, 4] = fmt_sci(gv.median_norm)
        data[row, 5] = "$(ref.n_converged)/$(ref.n_raw) ($(fmt_pct(ref.n_converged, ref.n_raw)))"
        data[row, 6] = fmt_sci(ref.best_raw_value)
        data[row, 7] = ref.n_converged > 0 ? fmt_sci(ref.best_refined_value) : "N/A"
        data[row, 8] = fmt_time(ref.total_time)
    end

    best_grad_row = argmin([gv.min_norm for (_, gv, _) in degree_analyses])
    best_ref_row = argmin([ref.n_converged > 0 ? ref.best_refined_value : Inf
                           for (_, _, ref) in degree_analyses])

    styled_table(io, data;
        header=["Deg", "# CPs", "min ||∇f||", "med ||∇f||", "Converged",
                "Best raw", "Best ref", "Time"],
        alignment=[:r, :r, :r, :r, :r, :r, :r, :r],
        highlighters=(
            Highlighter((_, i, j) -> i == best_grad_row && j == 3, foreground=:green, bold=true),
            Highlighter((_, i, j) -> i == best_ref_row && j == 7, foreground=:green, bold=true),
        ),
    )
end

# ─── Step 3 data construction ─────────────────────────────────────────────────

"""
    build_degree_convergence_info(degree_results, degree_analyses, degree_capture_results)

Cross-reference degree results, gradient/refinement analyses, and capture results
to build `DegreeConvergenceInfo` structs for `print_degree_convergence_summary`.

Selects the best objective per degree: prefers refined value, falls back to raw.

# Arguments
- `degree_results`: Vector of degree result objects (from `run_standard_experiment`)
- `degree_analyses::Vector{DegreeAnalysisResult}`: Output from `run_degree_analyses`
- `degree_capture_results::Vector{Tuple{Int, CaptureResult}}`: Capture results per degree

# Returns
- `Vector{DegreeConvergenceInfo}`: One entry per degree in `degree_capture_results`
"""
function build_degree_convergence_info(
    degree_results,
    degree_analyses::Vector{DegreeAnalysisResult},
    degree_capture_results::Vector{Tuple{Int, CaptureResult}},
)::Vector{DegreeConvergenceInfo}

    gv_map = Dict(deg => gv for (deg, gv, _) in degree_analyses)
    ref_map = Dict(deg => ref for (deg, _, ref) in degree_analyses)
    dr_map = Dict(dr.degree => dr for dr in degree_results)

    infos = DegreeConvergenceInfo[]
    for (deg, _) in degree_capture_results
        dr = dr_map[deg]
        gv = get(gv_map, deg, nothing)
        ref = get(ref_map, deg, nothing)

        best_obj = if ref !== nothing && ref.n_converged > 0
            ref.best_refined_value
        elseif dr.best_objective !== nothing
            dr.best_objective
        else
            nothing
        end

        push!(infos, DegreeConvergenceInfo(
            deg,
            dr.l2_approx_error,
            dr.n_critical_points,
            gv !== nothing ? gv.min_norm : nothing,
            best_obj,
        ))
    end

    return infos
end

"""
    BestEstimate

Result from `find_best_estimate`: the best minimum found across all degrees.
"""
const BestEstimate = @NamedTuple{value::Float64, point::Vector{Float64}, degree::Int, source::String}

"""
    find_best_estimate(degree_results, degree_analyses) -> Union{Nothing, BestEstimate}

Find the best minimum estimate across all degrees, preferring refined over raw.

Returns `nothing` if no estimate is available, or a NamedTuple with fields:
- `value::Float64`: Best objective value
- `point::Vector{Float64}`: Best parameter estimate
- `degree::Int`: Degree that produced it
- `source::String`: "refined" or "raw"

# Arguments
- `degree_results`: Vector of degree result objects (from `run_standard_experiment`)
- `degree_analyses::Vector{DegreeAnalysisResult}`: Output from `run_degree_analyses`
"""
function find_best_estimate(
    degree_results,
    degree_analyses::Vector{DegreeAnalysisResult},
)::Union{Nothing, BestEstimate}

    best_value = Inf
    best_point = nothing
    best_degree = 0
    best_source = "raw"

    # First pass: check refined results
    for (deg, _, ref) in degree_analyses
        if ref.n_converged > 0 && ref.best_refined_value < best_value
            best_value = ref.best_refined_value
            best_point = ref.refined_points[ref.best_refined_idx]
            best_degree = deg
            best_source = "refined"
        end
    end

    # Second pass: fall back to raw results
    if best_point === nothing
        for dr in degree_results
            if dr.best_estimate !== nothing && dr.best_objective !== nothing && dr.best_objective < best_value
                best_value = dr.best_objective
                best_point = dr.best_estimate
                best_degree = dr.degree
                best_source = "raw"
            end
        end
    end

    best_point === nothing && return nothing
    return (value=best_value, point=best_point, degree=best_degree, source=best_source)
end

"""
    find_best_raw_estimate(degree_results) -> Union{Nothing, BestEstimate}

Find the best raw (un-refined) estimate across all degrees.
Useful for comparing raw vs refined in parameter recovery tables.

Returns `nothing` if no raw estimate is available.
"""
function find_best_raw_estimate(
    degree_results,
)::Union{Nothing, BestEstimate}
    best_value = Inf
    best_point = nothing
    best_degree = 0

    for dr in degree_results
        if dr.best_estimate !== nothing && dr.best_objective !== nothing && dr.best_objective < best_value
            best_value = dr.best_objective
            best_point = dr.best_estimate
            best_degree = dr.degree
        end
    end

    best_point === nothing && return nothing
    return (value=best_value, point=best_point, degree=best_degree, source="raw")
end

# ─── Step 3 display: parameter recovery ───────────────────────────────────────

"""
    print_parameter_recovery_table(true_params, best_estimate; kwargs...)

Print a per-parameter comparison table: true value vs estimated value(s),
with absolute error, relative error, and an L2 summary row. Error columns
are color-coded (green < 1e-6, yellow < 1e-3, red >= 1e-3).

# Arguments
- `true_params::Vector{Float64}`: True parameter values
- `best_estimate::Vector{Float64}`: Best parameter estimate

# Keyword Arguments
- `raw_estimate::Union{Vector{Float64}, Nothing} = nothing`: Optional raw estimate for comparison
- `param_labels::Union{Vector{String}, Nothing} = nothing`: Labels for each parameter (default: `p_1, p_2, ...`)
- `source_label::String = "refined"`: Label for the best estimate column
- `degree::Union{Int, Nothing} = nothing`: Degree that produced the estimate (for section header)
- `io::IO = stdout`: Output stream
"""
function print_parameter_recovery_table(
    true_params::Vector{Float64},
    best_estimate::Vector{Float64};
    raw_estimate::Union{Vector{Float64}, Nothing} = nothing,
    param_labels::Union{Vector{String}, Nothing} = nothing,
    source_label::String = "refined",
    degree::Union{Int, Nothing} = nothing,
    io::IO = stdout,
)
    DIM = length(true_params)
    labels = param_labels !== nothing ? param_labels : ["p_$i" for i in 1:DIM]
    abs_errors = abs.(best_estimate .- true_params)
    rel_errors = abs_errors ./ abs.(true_params)

    has_raw = raw_estimate !== nothing
    n_cols = has_raw ? 6 : 5

    # Section header
    deg_str = degree !== nothing ? ", deg $degree" : ""
    print_section("Parameter Recovery (best across degrees$deg_str)"; io=io)

    # Data matrix: rows = params + summary
    data = Matrix{Any}(undef, DIM + 1, n_cols)
    for i in 1:DIM
        col = 1
        data[i, col] = labels[i]; col += 1
        data[i, col] = @sprintf("%.4f", true_params[i]); col += 1
        if has_raw
            data[i, col] = @sprintf("%.6f", raw_estimate[i]); col += 1
        end
        data[i, col] = @sprintf("%.6f", best_estimate[i]); col += 1
        data[i, col] = fmt_sci(abs_errors[i]); col += 1
        data[i, col] = fmt_sci(rel_errors[i])
    end

    # Summary row (L2 norm of errors)
    ref_l2 = LinearAlgebra.norm(best_estimate .- true_params)
    sr = DIM + 1
    col = 1
    data[sr, col] = "||.||_2"; col += 1
    data[sr, col] = ""; col += 1
    if has_raw
        data[sr, col] = fmt_sci(LinearAlgebra.norm(raw_estimate .- true_params)); col += 1
    end
    data[sr, col] = fmt_sci(ref_l2); col += 1
    data[sr, col] = ""
    data[sr, n_cols] = ""

    header = if has_raw
        ["param", "true", "raw est.", "$source_label est.", "abs error", "rel error"]
    else
        ["param", "true", "$source_label est.", "abs error", "rel error"]
    end

    abs_err_col = has_raw ? 5 : 4

    styled_table(io, data;
        header=header,
        alignment=fill(:r, n_cols),
        highlighters=(
            Highlighter((_, i, j) -> j == 1 && i <= DIM, bold=true, foreground=:cyan),
            Highlighter((_, i, j) -> i == DIM + 1, bold=true, foreground=:white),
            Highlighter((d, i, j) -> j == abs_err_col && i <= DIM && isa(d[i, j], String) &&
                tryparse(Float64, d[i, j]) !== nothing && parse(Float64, d[i, j]) < 1e-6,
                bold=true, foreground=:green),
            Highlighter((d, i, j) -> j == abs_err_col && i <= DIM && isa(d[i, j], String) &&
                tryparse(Float64, d[i, j]) !== nothing && 1e-6 <= parse(Float64, d[i, j]) < 1e-3,
                foreground=:yellow),
            Highlighter((d, i, j) -> j == abs_err_col && i <= DIM && isa(d[i, j], String) &&
                tryparse(Float64, d[i, j]) !== nothing && parse(Float64, d[i, j]) >= 1e-3,
                bold=true, foreground=:red),
        ),
        body_hlines=[DIM],
    )
end

# ─── Step 3 display: recovery verdict ──────────────────────────────────────────

"""
    print_recovery_verdict(best, true_params; capture_verdict=nothing, io=stdout)

Print a styled verdict banner for parameter recovery experiments.

Computes `recovery_pct = ||best - true|| / ||true|| * 100` and classifies:
- SUCCESS (green): < 5%
- MODERATE (yellow): < 20%
- POOR (red): >= 20%

If `capture_verdict` is provided, also prints the capture rate line.

# Arguments
- `best::BestEstimate`: Best parameter estimate (from `find_best_estimate`)
- `true_params::Vector{Float64}`: True parameter values
- `capture_verdict::Union{CaptureVerdict, Nothing}`: Optional capture analysis verdict
- `io::IO`: Output stream (default: stdout)
"""
function print_recovery_verdict(
    best::BestEstimate,
    true_params::Vector{Float64};
    capture_verdict::Union{CaptureVerdict, Nothing} = nothing,
    io::IO = stdout,
)
    recovery_pct = LinearAlgebra.norm(best.point .- true_params) / LinearAlgebra.norm(true_params) * 100

    verdict_label = recovery_pct < 5.0 ? "SUCCESS" : recovery_pct < 20.0 ? "MODERATE" : "POOR"
    verdict_col = recovery_pct < 5.0 ? :green : recovery_pct < 20.0 ? :yellow : :red

    printstyled(io, "="^80 * "\n"; color=verdict_col, bold=true)
    printstyled(io, " RECOVERY [$verdict_label] — $(best.source), deg $(best.degree): " *
        "error = $(@sprintf("%.4f", recovery_pct))% of ||p_true||\n"; color=verdict_col, bold=true)

    if capture_verdict !== nothing
        cap_pct = @sprintf("%.1f", 100 * capture_verdict.capture_rate)
        printstyled(io, "  Capture: $(capture_verdict.n_captured)/$(capture_verdict.n_known)" *
            " ($cap_pct%) at $(100 * capture_verdict.tolerance_fraction)% tolerance" *
            " (deg $(capture_verdict.best_degree))\n"; color=:white)
    end

    printstyled(io, "="^80 * "\n"; color=verdict_col, bold=true)
end

# ─── Step 3 display: best minimum (benchmark experiments) ────────────────────

"""
    print_best_minimum(best; verdict=nothing, io=stdout)

Print the best minimum found and a closing verdict banner. For use after
`print_capture_verdict` in benchmark experiments where known critical points exist
(e.g., Deuflhard, Rosenbrock, Rastrigin).

The banner color is derived from the capture verdict quality:
- Green: capture rate >= 80%
- Yellow: capture rate >= 50%
- Red: otherwise (or no verdict provided)

# Arguments
- `best::BestEstimate`: Best parameter estimate (from `find_best_estimate`)
- `verdict::Union{CaptureVerdict, Nothing}`: Optional capture verdict for banner coloring
- `io::IO`: Output stream (default: stdout)
"""
function print_best_minimum(
    best::BestEstimate;
    verdict::Union{CaptureVerdict, Nothing} = nothing,
    io::IO = stdout,
)
    verdict_col = if verdict !== nothing
        verdict.capture_rate >= 0.80 ? :green :
        verdict.capture_rate >= 0.50 ? :yellow : :red
    else
        :white
    end

    printstyled(io, "  Best minimum: f(x*) = $(fmt_sci(best.value))" *
        " ($(best.source), deg $(best.degree))" *
        ",  x* = $(round.(best.point, digits=4))\n"; color=:white)
    printstyled(io, "="^80 * "\n"; color=verdict_col, bold=true)
end

# ─── Step 3 display: error banner ────────────────────────────────────────────

"""
    print_error_banner(message; io=stdout)

Print a red error banner with the given message, matching the verdict banner style.
Used for no-results cases (e.g., no critical points found, no parameter estimate).

# Arguments
- `message::String`: Error message to display
- `io::IO`: Output stream (default: stdout)
"""
function print_error_banner(message::String; io::IO=stdout)
    printstyled(io, "="^80 * "\n"; color=:red, bold=true)
    printstyled(io, " $message\n"; color=:red, bold=true)
    printstyled(io, "="^80 * "\n"; color=:red, bold=true)
end
