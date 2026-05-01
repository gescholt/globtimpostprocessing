"""
    ground_truth_functions.jl

Benchmark test functions for Level 1 ground truth generation.
Each function is defined with its domain, dimension, and analytically
known critical points (where available).

These are INDEPENDENT definitions — no dependency on Globtim or LibFunctions.
This ensures the ground truth is truly independent of the pipeline.
"""
module GroundTruthFunctions

using LinearAlgebra
export BENCHMARK_FUNCTIONS, BenchmarkFunction

"""
    BenchmarkFunction

A benchmark function with metadata for ground truth generation.

Fields:
- `name::String` — human-readable name
- `f::Function` — the objective function f: ℝⁿ → ℝ
- `dim::Int` — dimension
- `bounds::Vector{Tuple{Float64,Float64}}` — search domain per dimension
- `known_minima::Vector{Vector{Float64}}` — analytically known local minima (may be empty)
- `known_maxima::Vector{Vector{Float64}}` — analytically known local maxima (may be empty)
- `known_saddles::Vector{Vector{Float64}}` — analytically known saddle points (may be empty)
- `n_expected_minima::Union{Int,Nothing}` — expected number of local minima in domain (nothing if unknown)
"""
struct BenchmarkFunction
    name::String
    f::Function
    dim::Int
    bounds::Vector{Tuple{Float64,Float64}}
    known_minima::Vector{Vector{Float64}}
    known_maxima::Vector{Vector{Float64}}
    known_saddles::Vector{Vector{Float64}}
    n_expected_minima::Union{Int,Nothing}
end

# ============================================================================
# 1. Sphere (quadratic) — trivial baseline
# ============================================================================
sphere_2d(x) = x[1]^2 + x[2]^2

const SPHERE_2D = BenchmarkFunction(
    "sphere_2d",
    sphere_2d,
    2,
    [(-5.12, 5.12), (-5.12, 5.12)],
    [[0.0, 0.0]],         # single global minimum
    Vector{Float64}[],     # no maxima in bounded domain (boundary only)
    Vector{Float64}[],     # no saddles
    1,
)

# ============================================================================
# 2. Himmelblau — 4 minima, 1 maximum, 4 saddle points
# ============================================================================
himmelblau(x) = (x[1]^2 + x[2] - 11)^2 + (x[1] + x[2]^2 - 7)^2

const HIMMELBLAU = BenchmarkFunction(
    "himmelblau",
    himmelblau,
    2,
    [(-5.0, 5.0), (-5.0, 5.0)],
    [[3.0, 2.0], [-2.805118, 3.131312], [-3.779310, -3.283186], [3.584428, -1.848126]],
    [[-0.270845, -0.923039],],
    Vector{Float64}[],  # saddle points will be discovered numerically
    4,
)

# ============================================================================
# 3. Six-hump camel — 2 global + 4 local minima/maxima
# ============================================================================
sixhump_camel(x) = (4 - 2.1*x[1]^2 + x[1]^4/3)*x[1]^2 + x[1]*x[2] + (-4 + 4*x[2]^2)*x[2]^2

# The six-hump camel has 6 extrema total:
# 2 global minima at approximately (±0.0898, ∓0.7126) with f ≈ -1.0316
# 2 local minima at approximately (±1.7036, ∓0.7961) with f ≈ -0.2155 (approx)
#   Actually, the standard analysis: it has 2 global minima and 2 local minima
#   plus 2 saddle points within a typical domain. The exact count depends on domain.
const SIXHUMP_CAMEL = BenchmarkFunction(
    "sixhump_camel",
    sixhump_camel,
    2,
    [(-3.0, 3.0), (-2.0, 2.0)],
    [
        [0.0898, -0.7126],   # global minimum, f ≈ -1.0316
        [-0.0898, 0.7126],   # global minimum, f ≈ -1.0316
    ],
    Vector{Float64}[],  # local maxima discovered numerically
    Vector{Float64}[],  # saddle points discovered numerically
    nothing,  # exact count depends on domain — discover numerically
)

# ============================================================================
# 4. Rosenbrock 2D — single minimum at [1, 1]
# ============================================================================
rosenbrock_2d(x) = (1 - x[1])^2 + 100*(x[2] - x[1]^2)^2

const ROSENBROCK_2D = BenchmarkFunction(
    "rosenbrock_2d",
    rosenbrock_2d,
    2,
    [(-5.0, 5.0), (-5.0, 5.0)],
    [[1.0, 1.0]],         # single global minimum
    Vector{Float64}[],
    Vector{Float64}[],
    1,
)

# ============================================================================
# 5. Deuflhard 2D — multiple CPs, discovered numerically
# ============================================================================
deuflhard_2d(x) = (exp(x[1]^2 + x[2]^2) - 3)^2 + (x[1] + x[2] - sin(3*(x[1] + x[2])))^2

const DEUFLHARD_2D = BenchmarkFunction(
    "deuflhard_2d",
    deuflhard_2d,
    2,
    [(-1.2, 1.2), (-1.2, 1.2)],
    Vector{Float64}[],    # no analytically known minima
    Vector{Float64}[],
    Vector{Float64}[],
    nothing,              # number of minima unknown — discover
)

# ============================================================================
# 6. Styblinski-Tang 2D — separable, known minima
# ============================================================================
styblinski_tang_2d(x) = 0.5 * sum(xi^4 - 16*xi^2 + 5*xi for xi in x)

# Each dimension has local minima at approximately ±2.903534
# In 2D: 4 local minima (all combinations of ±2.903534)
# Global minimum at (-2.903534, -2.903534) with f ≈ -78.332
# Also has saddle points from mixing the local min of each dimension
const STYBLINSKI_TANG_2D = BenchmarkFunction(
    "styblinski_tang_2d",
    styblinski_tang_2d,
    2,
    [(-5.0, 5.0), (-5.0, 5.0)],
    [
        [-2.903534, -2.903534],   # global minimum
        [-2.903534, 2.746803],    # local minimum (approx — one dim at secondary)
        [2.746803, -2.903534],    # local minimum
        [2.746803, 2.746803],     # local minimum
    ],
    Vector{Float64}[],
    Vector{Float64}[],
    4,
)

# ============================================================================
# 7. Rastrigin 2D — regular grid of minima
# ============================================================================
rastrigin_2d(x) = 20 + x[1]^2 - 10*cos(2π*x[1]) + x[2]^2 - 10*cos(2π*x[2])

# In [-5.12, 5.12]^2: local minima at all integer points (i, j)
# That's 11 × 11 = 121 minima from (-5,-5) to (5,5)
# Global minimum at (0, 0) with f = 0
const RASTRIGIN_2D = BenchmarkFunction(
    "rastrigin_2d",
    rastrigin_2d,
    2,
    [(-5.12, 5.12), (-5.12, 5.12)],
    [[0.0, 0.0]],         # global minimum (only listing global here)
    Vector{Float64}[],
    Vector{Float64}[],
    121,                   # 11 × 11 grid of minima at integer points
)

# ============================================================================
# 8. Deuflhard 4D — composition of two 2D Deuflhards
# ============================================================================
deuflhard_4d(x) = deuflhard_2d(x[1:2]) + deuflhard_2d(x[3:4])

const DEUFLHARD_4D = BenchmarkFunction(
    "deuflhard_4d",
    deuflhard_4d,
    4,
    [(-1.2, 1.2), (-1.2, 1.2), (-1.2, 1.2), (-1.2, 1.2)],
    Vector{Float64}[],    # discovered numerically
    Vector{Float64}[],
    Vector{Float64}[],
    nothing,              # number unknown — discover
)

# ============================================================================
# Master list
# ============================================================================

const BENCHMARK_FUNCTIONS = [
    SPHERE_2D,
    HIMMELBLAU,
    SIXHUMP_CAMEL,
    ROSENBROCK_2D,
    DEUFLHARD_2D,
    STYBLINSKI_TANG_2D,
    RASTRIGIN_2D,
    DEUFLHARD_4D,
]

end  # module GroundTruthFunctions
