"""
Refinement Configuration

Provides configuration structs and presets for critical point refinement.

Created: 2025-11-22 (Architecture cleanup)
"""

# ============================================================================
# Bounds helpers
# ============================================================================

"""
    lower_bounds(bounds::Vector{Tuple{Float64,Float64}}) -> Vector{Float64}

Extract lower bounds from paired (lo, hi) tuples.
"""
lower_bounds(bounds::Vector{Tuple{Float64,Float64}}) = [b[1] for b in bounds]

"""
    upper_bounds(bounds::Vector{Tuple{Float64,Float64}}) -> Vector{Float64}

Extract upper bounds from paired (lo, hi) tuples.
"""
upper_bounds(bounds::Vector{Tuple{Float64,Float64}}) = [b[2] for b in bounds]

"""
    split_bounds(bounds) -> (Vector{Float64}, Vector{Float64}) or (nothing, nothing)

Split paired bounds into (lower, upper) vectors. Returns (nothing, nothing) if bounds is nothing.
"""
split_bounds(::Nothing) = (nothing, nothing)
split_bounds(bounds::Vector{Tuple{Float64,Float64}}) = (lower_bounds(bounds), upper_bounds(bounds))

# ============================================================================
# RefinementConfig
# ============================================================================

"""
    RefinementConfig

Configuration for critical point refinement.

# Fields
- `method::Optim.AbstractOptimizer`: Optim.jl method (default: NelderMead() for gradient-free)
- `max_time_per_point::Union{Nothing, Float64}`: Timeout per point in seconds (default: 30.0)
- `f_abstol::Float64`: Function convergence tolerance (default: 1e-6)
- `x_abstol::Float64`: Parameter convergence tolerance (default: 1e-6)
- `max_iterations::Int`: Max iterations per point (default: 300)
- `parallel::Bool`: Use distributed refinement (default: false, not yet implemented)
- `robust_mode::Bool`: Return Inf on objective failure instead of error (default: true)
- `show_progress::Bool`: Display progress counter (default: true)
- `gradient_method::Symbol`: Gradient computation method for validation (:forwarddiff or :finitediff)
- `gradient_tolerance::Float64`: Tolerance for gradient norm validation (default: 1e-8, use 1e-4 for ODE)
- `bounds::Union{Nothing, Vector{Tuple{Float64,Float64}}}`: Box constraints as (lo, hi) tuples (default: nothing = unconstrained)

# Presets
Use `ode_refinement_config()` for ODE-based objectives (longer timeouts, robust mode, finitediff).

# Examples
```julia
# Default config (general-purpose, uses ForwardDiff)
config = RefinementConfig()

# ODE-specific config (longer timeout, robust mode, uses FiniteDiff)
config_ode = ode_refinement_config()

# Custom config with bounds
config_custom = RefinementConfig(
    max_time_per_point = 60.0,
    f_abstol = 1e-8,
    bounds = [(0.0, 1.0), (0.0, 2.0)],
    gradient_method = :finitediff
)
```
"""
struct RefinementConfig
    method::Optim.AbstractOptimizer
    max_time_per_point::Union{Nothing, Float64}
    f_abstol::Float64
    x_abstol::Float64
    max_iterations::Int
    parallel::Bool
    robust_mode::Bool
    show_progress::Bool
    gradient_method::Symbol
    gradient_tolerance::Float64
    bounds::Union{Nothing, Vector{Tuple{Float64,Float64}}}
end

"""
    RefinementConfig(; kwargs...)

Construct RefinementConfig with keyword arguments.

# Keyword Arguments
- `method = Optim.NelderMead()`: Optimization method (gradient-free by default)
- `max_time_per_point = 30.0`: Timeout per point in seconds
- `f_abstol = 1e-6`: Function convergence tolerance
- `x_abstol = 1e-6`: Parameter convergence tolerance
- `max_iterations = 300`: Maximum iterations per point
- `parallel = false`: Use parallel refinement (not yet implemented)
- `robust_mode = true`: Return Inf on objective failure
- `show_progress = true`: Display progress counter
- `gradient_method = :forwarddiff`: Gradient method (:forwarddiff or :finitediff)
- `gradient_tolerance = 1e-8`: Gradient norm tolerance for validation (use 1e-4 for ODE)
- `bounds = nothing`: Box constraints as Vector{Tuple{Float64,Float64}} or nothing

# Examples
```julia
# Default config
config = RefinementConfig()

# Custom tolerances
config = RefinementConfig(f_abstol=1e-8, x_abstol=1e-8)

# Silent mode
config = RefinementConfig(show_progress=false)

# Numerical gradients for ODE objectives
config = RefinementConfig(gradient_method=:finitediff)
```
"""
function RefinementConfig(;
    method::Optim.AbstractOptimizer = Optim.NelderMead(),
    max_time_per_point::Union{Nothing, Float64} = 30.0,
    f_abstol::Float64 = 1e-6,
    x_abstol::Float64 = 1e-6,
    max_iterations::Int = 300,
    parallel::Bool = false,
    robust_mode::Bool = true,
    show_progress::Bool = true,
    gradient_method::Symbol = :forwarddiff,
    gradient_tolerance::Float64 = 1e-8,
    bounds::Union{Nothing, Vector{Tuple{Float64,Float64}}} = nothing
)
    return RefinementConfig(
        method,
        max_time_per_point,
        f_abstol,
        x_abstol,
        max_iterations,
        parallel,
        robust_mode,
        show_progress,
        gradient_method,
        gradient_tolerance,
        bounds
    )
end

"""
    ode_refinement_config(; kwargs...)

ODE-specific preset for refinement configuration.

Uses longer timeouts, robust mode, and numerical gradients optimized for ODE parameter
estimation problems where objective evaluations involve solving stiff ODEs.

# Keyword Arguments
- `max_time_per_point = 60.0`: 2x longer timeout for stiff ODEs
- `gradient_tolerance = 1e-4`: Realistic tolerance for ODE solver accuracy (~1e-6 solver tolerance)
- `kwargs...`: Additional arguments passed to RefinementConfig

# Examples
```julia
using GlobtimPostProcessing

# Standard ODE preset
config = ode_refinement_config()

# ODE preset with custom timeout
config = ode_refinement_config(max_time_per_point=120.0)

# ODE preset with custom tolerance
config = ode_refinement_config(f_abstol=1e-8)
```

# Notes
- Always uses gradient-free NelderMead (ForwardDiff incompatible with ODE solvers)
- Robust mode enabled (returns Inf on ODE solver failure)
- Uses FiniteDiff for gradient validation (ForwardDiff incompatible with ODE solvers)
- Longer timeout to handle stiff problems
"""
function ode_refinement_config(;
    max_time_per_point::Float64 = 60.0,
    gradient_tolerance::Float64 = 1e-4,
    kwargs...
)
    return RefinementConfig(;
        method = Optim.NelderMead(),  # Gradient-free required for ODE
        max_time_per_point = max_time_per_point,
        robust_mode = true,  # Return Inf on ODE solver failure
        gradient_method = :finitediff,  # Numerical gradients for ODE objectives
        gradient_tolerance = gradient_tolerance,  # Realistic for ODE solver accuracy (~1e-6)
        kwargs...
    )
end
