"""
Refinement Configuration

Provides configuration structs and presets for critical point refinement.

Created: 2025-11-22 (Architecture cleanup)
"""

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

# Presets
Use `ode_refinement_config()` for ODE-based objectives (longer timeouts, robust mode, finitediff).

# Examples
```julia
# Default config (general-purpose, uses ForwardDiff)
config = RefinementConfig()

# ODE-specific config (longer timeout, robust mode, uses FiniteDiff)
config_ode = ode_refinement_config()

# Custom config with numerical gradients
config_custom = RefinementConfig(
    max_time_per_point = 60.0,
    f_abstol = 1e-8,
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
    gradient_method::Symbol = :forwarddiff
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
        gradient_method
    )
end

"""
    ode_refinement_config(; kwargs...)

ODE-specific preset for refinement configuration.

Uses longer timeouts, robust mode, and numerical gradients optimized for ODE parameter
estimation problems where objective evaluations involve solving stiff ODEs.

# Keyword Arguments
- `max_time_per_point = 60.0`: 2x longer timeout for stiff ODEs
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
    kwargs...
)
    return RefinementConfig(;
        method = Optim.NelderMead(),  # Gradient-free required for ODE
        max_time_per_point = max_time_per_point,
        robust_mode = true,  # Return Inf on ODE solver failure
        gradient_method = :finitediff,  # Numerical gradients for ODE objectives
        kwargs...
    )
end
