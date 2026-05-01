"""
    generate_ground_truth.jl

Level 1: Generate ground truth CSV files for benchmark functions.

Uses the L0 CP verification oracle (find_all_critical_points) to discover
all critical points in each benchmark function, then stores them as CSV.

For functions with analytically known minima, verifies that the oracle
finds them. For functions without, does multi-start with high n_starts.

Run with:
    julia --project=profiles/dev pkg/globtimpostprocessing/test/test_utils/generate_ground_truth.jl

Output directory: pkg/globtimpostprocessing/test/fixtures/ground_truth/
"""

using Printf
using LinearAlgebra

# Include dependencies
include(joinpath(@__DIR__, "cp_verification.jl"))
include(joinpath(@__DIR__, "ground_truth_functions.jl"))

using .CPVerification
using .GroundTruthFunctions

# ============================================================================
# Configuration
# ============================================================================

const OUTPUT_DIR = joinpath(@__DIR__, "..", "fixtures", "ground_truth")

# Per-function n_starts configuration (more starts for harder functions)
const N_STARTS_CONFIG = Dict(
    "sphere_2d" => 50,
    "himmelblau" => 300,
    "sixhump_camel" => 500,
    "rosenbrock_2d" => 100,
    "deuflhard_2d" => 1000,
    "styblinski_tang_2d" => 300,
    "rastrigin_2d" => 5000,   # 121 minima — need many starts
    "deuflhard_4d" => 3000,   # 4D needs more starts
)

# ============================================================================
# CSV writing
# ============================================================================

"""
    write_ground_truth_csv(filepath, cps, dim)

Write a vector of VerifiedCP to CSV with columns:
    x1, x2, ..., xN, value, grad_norm, classification, eigenvalue_1, ..., eigenvalue_N, neighborhood_confirmed
"""
function write_ground_truth_csv(
    filepath::String,
    cps::Vector{CPVerification.VerifiedCP},
    dim::Int,
)
    open(filepath, "w") do io
        # Header
        x_cols = join(["x$i" for i in 1:dim], ",")
        ev_cols = join(["eigenvalue_$i" for i in 1:dim], ",")
        println(
            io,
            "$x_cols,value,grad_norm,classification,$ev_cols,neighborhood_confirmed",
        )

        # Data rows
        for cp in cps
            x_str = join([@sprintf("%.15e", cp.point[i]) for i in 1:dim], ",")
            ev_str = join([@sprintf("%.15e", cp.eigenvalues[i]) for i in 1:dim], ",")
            println(
                io,
                "$x_str,$(@sprintf("%.15e", cp.value)),$(@sprintf("%.15e", cp.grad_norm)),$(cp.classification),$ev_str,$(cp.neighborhood_confirmed)",
            )
        end
    end
end

# ============================================================================
# Main generation
# ============================================================================

function generate_all()
    mkpath(OUTPUT_DIR)

    for bf in BENCHMARK_FUNCTIONS
        println("\n" * "="^60)
        println("Generating ground truth: $(bf.name) ($(bf.dim)D)")
        println("="^60)

        n_starts = get(N_STARTS_CONFIG, bf.name, 500)

        # Find all critical points
        t = @elapsed cps = find_all_critical_points(
            bf.f,
            bf.bounds,
            bf.dim;
            n_starts = n_starts,
            grad_tol = 1e-10,
            hessian_tol = 1e-6,
            dedup_tol = 1e-4,
        )

        # Classify counts
        minima = filter(cp -> cp.classification == :minimum, cps)
        maxima = filter(cp -> cp.classification == :maximum, cps)
        saddles = filter(cp -> cp.classification == :saddle, cps)
        degenerate = filter(cp -> cp.classification == :degenerate, cps)

        println(
            "  Found: $(length(cps)) CPs ($(length(minima)) min, $(length(maxima)) max, $(length(saddles)) saddle, $(length(degenerate)) degen)",
        )
        println("  Time: $(@sprintf("%.2f", t))s with $n_starts starts")

        # Verify analytically known minima are found
        if !isempty(bf.known_minima)
            println("  Checking $(length(bf.known_minima)) analytically known minima...")
            for (i, known) in enumerate(bf.known_minima)
                found = any(cp -> norm(cp.point - known) < 0.01, minima)
                status = found ? "✓" : "✗ MISSING"
                println("    $status minimum $i at $(round.(known; digits=4))")
                if !found
                    @warn "Analytically known minimum NOT found!" func_name=bf.name point=known
                end
            end
        end

        # Verify expected count
        if bf.n_expected_minima !== nothing
            if length(minima) == bf.n_expected_minima
                println("  ✓ Found expected $(bf.n_expected_minima) minima")
            else
                println(
                    "  ⚠ Found $(length(minima)) minima, expected $(bf.n_expected_minima)",
                )
            end
        end

        # Write CSV
        filepath = joinpath(OUTPUT_DIR, "$(bf.name)_critical_points.csv")
        write_ground_truth_csv(filepath, cps, bf.dim)
        println("  Wrote: $filepath")
    end

    println("\n" * "="^60)
    println("Ground truth generation complete!")
    println("Output: $OUTPUT_DIR")
    println("="^60)
end

# Run if invoked directly
if abspath(PROGRAM_FILE) == @__FILE__
    generate_all()
end
