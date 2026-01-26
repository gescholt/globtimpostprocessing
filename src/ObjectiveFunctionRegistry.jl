"""
ObjectiveFunctionRegistry Module

Adaptive reconstruction of objective functions from experiment configuration files.

This module provides:
1. Loading of DynamicalSystems module from Globtim
2. Resolution of model function names (strings) to actual Julia functions
3. Validation of experiment configuration
4. Reconstruction of error/objective functions from config metadata

Design Principles:
- NO FALLBACKS: Error if anything is missing or incorrect
- Adaptive: Works with any model function defined in DynamicalSystems
- Type-safe: Validates all inputs before proceeding

Author: GlobTim Team
Created: October 2025 (Issue #TBD)
"""
module ObjectiveFunctionRegistry

export load_dynamical_systems_module, resolve_model_function,
       validate_config, reconstruct_error_function

"""
    load_dynamical_systems_module(globtim_root::String)

Load the DynamicalSystems module from Globtim/Examples/systems/DynamicalSystems.jl.

# Arguments
- `globtim_root`: Path to the Globtim package root directory (optional, defaults to GLOBTIM_ROOT env var or auto-search)

# Returns
- The DynamicalSystems module

# Throws
- ErrorException if Globtim root not found
- ErrorException if DynamicalSystems.jl not found at expected path
"""
function load_dynamical_systems_module(globtim_root::Union{String, Nothing}=nothing)
    # Get Globtim package root
    try
        # Priority: 1) function arg, 2) environment variable, 3) search for it
        if isnothing(globtim_root)
            globtim_root = get(ENV, "GLOBTIM_ROOT", nothing)
        end

        if isnothing(globtim_root)
            # Try to find it by searching upwards from common experiment locations
            possible_paths = [
                "../globtim",  # From globtimpostprocessing directory (ACTIVE)
                "../../globtim",  # From experiment subdirectory
                joinpath(homedir(), "GlobalOptim", "globtim"),  # Absolute path
                # Backward compatibility (archived name)
                "../globtimcore",
                "../../globtimcore",
                joinpath(homedir(), "GlobalOptim", "globtimcore"),
            ]

            for path in possible_paths
                if isdir(path) && isfile(joinpath(path, "Project.toml"))
                    globtim_root = abspath(path)
                    break
                end
            end
        end

        if isnothing(globtim_root) || !isdir(globtim_root)
            error("""
                Cannot locate Globtim package root.

                Please provide it via:
                1. Function argument: load_dynamical_systems_module("/path/to/globtim")
                2. Environment variable: ENV["GLOBTIM_ROOT"] = "/path/to/globtim"
                3. Ensure globtim is in a standard location relative to this script
                """)
        end

        # Construct path to DynamicalSystems.jl
        ds_path = joinpath(globtim_root, "Examples", "systems", "DynamicalSystems.jl")

        if !isfile(ds_path)
            error("""
                DynamicalSystems.jl not found at expected location:
                $ds_path

                Expected structure: Globtim/Examples/systems/DynamicalSystems.jl
                """)
        end

        # Include the file - this evaluates it in Main
        Base.include(Main, ds_path)

        # Return the module
        if isdefined(Main, :DynamicalSystems)
            return Main.DynamicalSystems
        else
            error("DynamicalSystems module was not defined after including $ds_path")
        end

    catch e
        if e isa ErrorException && (contains(e.msg, "Cannot locate Globtim") || contains(e.msg, "DynamicalSystems.jl not found"))
            rethrow(e)
        else
            error("""
                Failed to load DynamicalSystems module.
                Error: $e

                Make sure Globtim root path is correct and DynamicalSystems.jl exists.
                """)
        end
    end
end

"""
    resolve_model_function(model_func_name::String, ds_module)

Resolve a model function name (string) to the actual Julia function.

# Arguments
- `model_func_name`: Name of the model function (e.g., "define_daisy_ex3_model_4D")
- `ds_module`: The DynamicalSystems module

# Returns
- The actual Julia function that can be called

# Throws
- ErrorException if model_func_name not found in module
"""
function resolve_model_function(model_func_name::String, ds_module)
    # Convert string to symbol
    model_sym = Symbol(model_func_name)

    # Check if function exists in module
    if !isdefined(ds_module, model_sym)
        error("""
            Model function '$model_func_name' not found in DynamicalSystems module.

            Available functions can be checked with:
                names(DynamicalSystems)

            Common model functions:
            - define_daisy_ex3_model_4D
            - define_lotka_volterra_3D_model
            - define_lotka_volterra_2D_model
            - define_fitzhugh_nagumo_3D_model
            """)
    end

    # Get the function
    model_func = getfield(ds_module, model_sym)

    # Verify it's callable
    if !isa(model_func, Function)
        error("""
            '$model_func_name' exists but is not a Function.
            Type: $(typeof(model_func))
            """)
    end

    return model_func
end

"""
    validate_config(config::Dict) -> Bool

Validate that experiment configuration contains all required fields.

# Arguments
- `config`: Dictionary containing experiment configuration

# Returns
- `true` if valid

# Throws
- ErrorException if required keys missing
- ErrorException if wrong types
- ErrorException if dimensional inconsistencies

# Required Keys
- `model_func::String`: Name of model function
- `p_true::Vector`: True parameter values
- `ic::Vector`: Initial conditions
- `time_interval::Vector`: [start_time, end_time]
- `num_points::Int`: Number of time points
"""
function validate_config(config::Dict)
    required_keys = ["model_func", "p_true", "ic", "time_interval", "num_points"]

    # Check for missing keys
    missing_keys = String[]
    for key in required_keys
        if !haskey(config, key)
            push!(missing_keys, key)
        end
    end

    if !isempty(missing_keys)
        error("""
            Experiment configuration is incomplete.
            Missing required keys: $(join(missing_keys, ", "))

            Required keys:
            - model_func: Name of model definition function (String)
            - p_true: True parameter values (Vector{Real})
            - ic: Initial conditions (Vector{Real})
            - time_interval: [start_time, end_time] (Vector{Real}, length 2)
            - num_points: Number of time points (Int)
            """)
    end

    # Type validation
    errors = String[]

    # model_func should be string
    if !(config["model_func"] isa AbstractString)
        push!(errors, "model_func must be a String, got $(typeof(config["model_func"]))")
    end

    # p_true should be array-like
    if !(config["p_true"] isa AbstractArray)
        push!(errors, "p_true must be an Array, got $(typeof(config["p_true"]))")
    end

    # ic should be array-like
    if !(config["ic"] isa AbstractArray)
        push!(errors, "ic must be an Array, got $(typeof(config["ic"]))")
    end

    # time_interval should be array-like with length 2
    if !(config["time_interval"] isa AbstractArray)
        push!(errors, "time_interval must be an Array, got $(typeof(config["time_interval"]))")
    elseif length(config["time_interval"]) != 2
        push!(errors, "time_interval must have length 2, got $(length(config["time_interval"]))")
    end

    # num_points should be integer
    if !(config["num_points"] isa Integer)
        push!(errors, "num_points must be an Integer, got $(typeof(config["num_points"]))")
    end

    if !isempty(errors)
        error("""
            Experiment configuration has type errors:
            $(join("  - " .* errors, "\n"))
            """)
    end

    # Dimensional consistency (if both p_true and ic are valid)
    # Note: Not all models require length(p_true) == length(ic),
    # but we check they are non-empty
    if length(config["p_true"]) == 0
        error("p_true cannot be empty")
    end

    if length(config["ic"]) == 0
        error("ic cannot be empty")
    end

    return true
end

"""
    reconstruct_error_function(config::Dict) -> Function

Reconstruct the objective/error function from experiment configuration.

This is the main entry point that:
1. Validates configuration
2. Loads DynamicalSystems module
3. Resolves model function
4. Creates model
5. Reconstructs error function using make_error_distance

# Arguments
- `config`: Experiment configuration dictionary

# Returns
- Callable error function: `f(p::Vector) -> Real`

# Throws
- ErrorException if any step fails (validation, loading, resolution, etc.)
"""
function reconstruct_error_function(config::Dict)
    # Step 1: Validate configuration
    validate_config(config)

    # Step 2: Load DynamicalSystems module
    ds_module = load_dynamical_systems_module()

    # Step 3: Resolve model function
    model_func_name = config["model_func"]
    model_func = resolve_model_function(model_func_name, ds_module)

    # Step 4: Create model
    try
        model, params, states, outputs = model_func()

        # Step 5: Extract parameters from config
        ic = collect(config["ic"])  # Convert JSON3.Array to Vector if needed
        p_true = collect(config["p_true"])
        time_interval = collect(config["time_interval"])
        num_points = config["num_points"]

        # Step 6: Get L2_norm from DynamicalSystems
        L2_norm = ds_module.L2_norm

        # Step 7: Create error function
        error_func = ds_module.make_error_distance(
            model,
            outputs,
            ic,
            p_true,
            time_interval,
            num_points,
            L2_norm
        )

        return error_func

    catch e
        error("""
            Failed to reconstruct error function from configuration.

            Model function: $model_func_name
            Error: $e

            Stacktrace:
            $(sprint(showerror, e, catch_backtrace()))
            """)
    end
end

end # module ObjectiveFunctionRegistry
