"""
TrajectoryEvaluator Module

Evaluates critical points by solving ODEs and comparing trajectories.

This module provides:
1. Trajectory solving with arbitrary parameter values
2. Trajectory distance computation (L1, L2, Linf norms)
3. Critical point quality assessment
4. Comprehensive trajectory comparisons

Design Principles:
- NO FALLBACKS: Error if ODE solve fails or parameters invalid
- Reuses ObjectiveFunctionRegistry for model loading
- Supports arbitrary number of outputs
- Works with any DynamicalSystems model function

Author: GlobTim Team
Created: October 2025
"""
module TrajectoryEvaluator

export solve_trajectory, compute_trajectory_distance,
       evaluate_critical_point, compare_trajectories

using LinearAlgebra
using Statistics

# Import from ObjectiveFunctionRegistry
# It should be loaded by the parent module (TrajectoryComparison)
# If this module is being used standalone, include it here
if !isdefined(@__MODULE__, :ObjectiveFunctionRegistry)
    # Check if it exists in parent module
    parent_mod = parentmodule(@__MODULE__)
    if parent_mod != Main && isdefined(parent_mod, :ObjectiveFunctionRegistry)
        @info "Using ObjectiveFunctionRegistry from parent module"
        using ..ObjectiveFunctionRegistry: load_dynamical_systems_module,
                                          resolve_model_function,
                                          validate_config
    else
        @info "Loading ObjectiveFunctionRegistry from TrajectoryEvaluator"
        include("ObjectiveFunctionRegistry.jl")
        using .ObjectiveFunctionRegistry: load_dynamical_systems_module,
                                          resolve_model_function,
                                          validate_config
    end
else
    @info "ObjectiveFunctionRegistry already loaded in TrajectoryEvaluator"
    using .ObjectiveFunctionRegistry: load_dynamical_systems_module,
                                      resolve_model_function,
                                      validate_config
end

"""
    solve_trajectory(config::Dict, p_found::Vector) -> OrderedDict

Solve ODE system with given parameters and return trajectory data.

# Arguments
- `config`: Experiment configuration containing:
  - model_func: Name of model function
  - ic: Initial conditions
  - time_interval: [start_time, end_time]
  - num_points: Number of time points
- `p_found`: Parameter vector to use for solving

# Returns
- OrderedDict with time series data for each output variable
  Format: Dict("y1" => values, "y2" => values, "t" => times)

# Throws
- ErrorException if ODE solver fails
- ErrorException if parameters have wrong dimension
- ErrorException if model cannot be created
"""
function solve_trajectory(config::Dict, p_found::Vector)
    try
        # Load DynamicalSystems module
        ds_module = load_dynamical_systems_module()

        # Resolve model function
        model_func_name = config["model_func"]
        model_func = resolve_model_function(model_func_name, ds_module)

        # Create model (using invokelatest to handle world age issues with dynamically loaded functions)
        model, params, states, outputs = Base.invokelatest(model_func)

        # Validate parameter dimension
        if length(p_found) != length(params)
            error("""
                Parameter dimension mismatch.
                Expected $(length(params)) parameters (from model $model_func_name).
                Got $(length(p_found)) parameters.

                Model parameters: $params
                Provided: $p_found
                """)
        end

        # Extract configuration
        ic = collect(config["ic"])
        time_interval = collect(config["time_interval"])
        num_points = config["num_points"]

        # Access ModelingToolkit from DynamicalSystems module
        MTK = ds_module.ModelingToolkit

        # Create ODE problem
        problem = MTK.ODEProblem(
            MTK.complete(model),
            ic,
            time_interval,
            p_found
        )

        # Solve trajectory using sample_data from DynamicalSystems
        trajectory = ds_module.sample_data(
            problem,
            model,
            outputs,
            time_interval,
            p_found,
            ic,
            num_points
        )

        return trajectory

    catch e
        if e isa ErrorException && contains(e.msg, "Parameter dimension mismatch")
            rethrow(e)
        else
            error("""
                Failed to solve trajectory.

                Model: $(config["model_func"])
                Parameters: $p_found
                Initial conditions: $(config["ic"])
                Time interval: $(config["time_interval"])

                Error: $e

                Stacktrace:
                $(sprint(showerror, e, catch_backtrace()))
                """)
        end
    end
end

"""
    compute_trajectory_distance(traj_true, traj_found, norm_type::Symbol) -> Float64

Compute distance between two trajectories.

# Arguments
- `traj_true`: Reference trajectory (OrderedDict from solve_trajectory)
- `traj_found`: Comparison trajectory (OrderedDict from solve_trajectory)
- `norm_type`: Type of norm to use (:L1, :L2, or :Linf)

# Returns
- Scalar distance aggregated across all output variables

# Throws
- ErrorException if trajectories have different structure
- ErrorException if norm_type is unknown

# Properties
- d(A, A) = 0 (identical trajectories)
- d(A, B) = d(B, A) (symmetry)
- d(A, B) > 0 for A ≠ B (positive definite)
"""
function compute_trajectory_distance(traj_true, traj_found, norm_type::Symbol)
    # Validate norm type
    if !(norm_type in [:L1, :L2, :Linf])
        error("""
            Unknown norm type: $norm_type

            Supported norm types:
            - :L1 (Manhattan norm)
            - :L2 (Euclidean norm)
            - :Linf (Maximum norm)
            """)
    end

    # Get output variable names (exclude "t")
    true_keys = [k for k in keys(traj_true) if k != "t"]
    found_keys = [k for k in keys(traj_found) if k != "t"]

    # Validate structure
    if Set(true_keys) != Set(found_keys)
        error("""
            Trajectory structure mismatch.

            Reference trajectory outputs: $true_keys
            Comparison trajectory outputs: $found_keys

            Trajectories must have the same output variables.
            """)
    end

    # Compute distance for each output and aggregate
    distances = Float64[]

    for key in true_keys
        y_true = traj_true[key]
        y_found = traj_found[key]

        if length(y_true) != length(y_found)
            error("""
                Trajectory length mismatch for output '$key'.
                Reference: $(length(y_true)) points
                Comparison: $(length(y_found)) points
                """)
        end

        # Compute distance based on norm type
        diff = y_true .- y_found

        dist = if norm_type == :L1
            norm(diff, 1)
        elseif norm_type == :L2
            norm(diff, 2)
        else  # :Linf
            norm(diff, Inf)
        end

        push!(distances, dist)
    end

    # Aggregate distances across outputs (using L2 norm of the distance vector)
    return norm(distances, 2)
end

"""
    evaluate_critical_point(config::Dict, critical_point_row) -> NamedTuple

Evaluate quality of a critical point by comparing trajectories.

# Arguments
- `config`: Experiment configuration
- `critical_point_row`: DataFrame row or Dict containing:
  - x1, x2, ..., xN: Parameter values
  - z: Objective function value

# Returns
NamedTuple with:
- `p_found`: Found parameter values (Vector)
- `p_true`: True parameter values (Vector)
- `param_distance`: L2 distance in parameter space
- `trajectory_distance`: L2 distance in trajectory space
- `objective_value`: Objective function value at critical point

# Throws
- ErrorException if critical point has wrong dimension
- ErrorException if trajectory solve fails
"""
function evaluate_critical_point(config::Dict, critical_point_row)
    # Extract parameter values from critical point
    # Support both DataFrame rows and Dicts
    p_found = if haskey(critical_point_row, :x1) || haskey(critical_point_row, "x1")
        # Determine expected dimension from config
        n_params = length(config["p_true"])

        param_values = Float64[]
        for i in 1:n_params
            key_sym = Symbol("x$i")
            key_str = "x$i"

            if haskey(critical_point_row, key_sym)
                push!(param_values, critical_point_row[key_sym])
            elseif haskey(critical_point_row, key_str)
                push!(param_values, critical_point_row[key_str])
            else
                error("""
                    Critical point missing parameter x$i.
                    Expected $n_params parameters (x1 through x$n_params).
                    Available keys: $(keys(critical_point_row))
                    """)
            end
        end

        param_values
    else
        error("""
            Cannot extract parameters from critical point.
            Expected keys: x1, x2, ..., xN
            Got keys: $(keys(critical_point_row))
            """)
    end

    # Get true parameters
    p_true = collect(config["p_true"])

    # Validate dimensions
    if length(p_found) != length(p_true)
        error("""
            Parameter dimension mismatch in critical point.
            Expected: $(length(p_true)) parameters
            Found: $(length(p_found)) parameters

            True parameters: $p_true
            Found parameters: $p_found
            """)
    end

    # Compute parameter space distance
    param_distance = norm(p_found .- p_true, 2)

    # Solve trajectories
    traj_true = solve_trajectory(config, p_true)
    traj_found = solve_trajectory(config, p_found)

    # Compute trajectory space distance
    trajectory_distance = compute_trajectory_distance(traj_true, traj_found, :L2)

    # Extract objective value
    obj_key_sym = :z
    obj_key_str = "z"
    objective_value = if haskey(critical_point_row, obj_key_sym)
        critical_point_row[obj_key_sym]
    elseif haskey(critical_point_row, obj_key_str)
        critical_point_row[obj_key_str]
    else
        NaN  # Not all critical points have objective value
    end

    return (
        p_found = p_found,
        p_true = p_true,
        param_distance = param_distance,
        trajectory_distance = trajectory_distance,
        objective_value = objective_value
    )
end

"""
    compare_trajectories(config::Dict, p_true::Vector, p_found::Vector) -> NamedTuple

Comprehensive trajectory comparison with multiple distance metrics.

# Arguments
- `config`: Experiment configuration
- `p_true`: True/reference parameter values
- `p_found`: Vector to compare against

# Returns
NamedTuple with trajectory_true, trajectory_found, distances, and output_distances
"""
function compare_trajectories(config::Dict, p_true::Vector, p_found::Vector)
    # Solve both trajectories
    traj_true = solve_trajectory(config, p_true)
    traj_found = solve_trajectory(config, p_found)

    # Compute multiple distance metrics
    distances = Dict{Symbol, Float64}(
        :L1 => compute_trajectory_distance(traj_true, traj_found, :L1),
        :L2 => compute_trajectory_distance(traj_true, traj_found, :L2),
        :Linf => compute_trajectory_distance(traj_true, traj_found, :Linf)
    )

    # Compute per-output distances (L2 norm)
    output_keys = [k for k in keys(traj_true) if k != "t"]
    output_distances = Dict{String, Float64}()

    for key in output_keys
        y_true = traj_true[key]
        y_found = traj_found[key]
        output_distances[string(key)] = norm(y_true .- y_found, 2)
    end

    return (
        trajectory_true = traj_true,
        trajectory_found = traj_found,
        distances = distances,
        output_distances = output_distances
    )
end

end # module TrajectoryEvaluator
