# Refinement Diagnostics Requirements

**Status**: Requirements Document
**Last Updated**: 2025-11-24
**Related Packages**: globtimpostprocessing (primary), globtimcore (reference)

## Overview

This document specifies requirements and future directions for capturing comprehensive diagnostics from the local optimization (refinement) process used to improve critical points found by polynomial approximation methods.

## Current State

### globtimcore - Real-Time HPC Analysis

**Location**: `globtimcore/src/refine.jl`
**Function**: `analyze_critical_points()`

**Current Diagnostics Captured**:
- Basic convergence status (`converged::Bool`)
- Iteration count
- Hessian eigenvalues (for critical point classification)
- Basin sizes
- Gradient norms (via ForwardDiff)

**Design Philosophy**: Minimal overhead for HPC environments. Focus on critical point characterization (minima/maxima/saddles) rather than exhaustive optimization diagnostics.

### globtimpostprocessing - Offline Comprehensive Analysis

**Location**: `globtimpostprocessing/src/refinement/`
**Function**: `refine_experiment_results()`

**Current Diagnostics Captured** (as of 2025-11-24):

```julia
struct RefinementResult
    refined::Vector{Float64}           # Refined point coordinates
    value_raw::Float64                  # Objective at initial point
    value_refined::Float64              # Objective at refined point
    converged::Bool                     # Binary convergence flag
    iterations::Int                     # Number of iterations
    improvement::Float64                # |f(refined) - f(raw)|
    timed_out::Bool                     # Timeout flag
    error_message::Union{String,Nothing} # Error if failed
end
```

**Design Philosophy**: Post-hoc refinement of saved critical points. Can afford more comprehensive diagnostics since not running on HPC during expensive experiments.

## Problem Statement

**Current Issue**: When refinement fails (0% convergence rate), we lack diagnostic information to understand:
- Why did optimization fail? (parameter convergence? function convergence? gradient issues?)
- How expensive was each refinement attempt? (function evaluations, timing)
- Are we close to converging? (gradient norms, tolerance margins)

**Impact**: Cannot iterate on refinement configuration effectively. No visibility into optimization behavior.

## Requirements: Tier 1 (High Priority)

### Zero-Cost Diagnostics

These diagnostics are **always available** from `Optim.OptimizationResults` with no performance overhead (no trace storage needed).

#### 1. Fine-Grained Convergence Reasons

**Currently**: Single `converged::Bool` flag
**Required**: Separate flags for each convergence criterion

```julia
# From Optim.jl result object (free)
x_converged::Bool              # Parameter convergence (x_tol)
f_converged::Bool              # Function value convergence (f_tol)
g_converged::Bool              # Gradient norm convergence (g_tol)
iteration_limit_reached::Bool  # Hit max iterations
```

**Value**: Understand *why* optimization succeeded/failed. Example:
- If `f_converged=true` but `x_converged=false`: Near flat region, may need tighter x_tol
- If `iteration_limit_reached=true`: May need more iterations or better starting point

**Implementation**:
```julia
# Extract from Optim result
x_conv = Optim.x_converged(result)
f_conv = Optim.f_converged(result)
g_conv = Optim.g_converged(result)
iter_limit = Optim.iteration_limit_reached(result)

# Derive primary reason
convergence_reason = if timed_out
    :timeout
elseif g_conv
    :g_tol  # Gradient norm (best indicator for critical point)
elseif f_conv
    :f_tol  # Function value converged
elseif x_conv
    :x_tol  # Parameters stopped changing
elseif iter_limit
    :iterations  # Hit limit without converging
else
    :error  # Other failure
end
```

#### 2. Function/Gradient Call Counts

**Currently**: Not captured
**Required**: Track computational cost per point

```julia
f_calls::Int  # Objective function evaluations
g_calls::Int  # Gradient evaluations (0 for NelderMead)
h_calls::Int  # Hessian evaluations (rare)
```

**Value**:
- Identify expensive points (high f_calls suggests difficult basin)
- Profile performance (is objective function the bottleneck?)
- Compare gradient-based (low f_calls) vs gradient-free (high f_calls) methods

**Implementation**:
```julia
f_calls = Optim.f_calls(result)
g_calls = Optim.g_calls(result)
h_calls = Optim.h_calls(result)
```

#### 3. Per-Point Timing

**Currently**: Only total batch time (`total_time::Float64`)
**Required**: Timing per point

```julia
time_elapsed::Float64  # Actual optimization time (seconds)
```

**Value**:
- Identify slow points for investigation
- Better timeout analysis (did we timeout too early?)
- Validate that timeout configuration is effective

**Implementation**:
```julia
time_elapsed = Optim.time_run(result)
```

#### 4. Convergence Reason Enum

**Currently**: Not captured
**Required**: Primary reason for stopping

```julia
convergence_reason::Symbol  # :x_tol, :f_tol, :g_tol, :iterations, :timeout, :error
```

**Value**: High-level summary for filtering and reporting. Example:
```julia
# How many points failed due to timeout vs iteration limit?
count(r -> r.convergence_reason == :timeout, results)
count(r -> r.convergence_reason == :iterations, results)
```

### Enhanced RefinementResult Struct (Tier 1)

```julia
struct RefinementResult
    # Existing fields (unchanged)
    refined::Vector{Float64}
    value_raw::Float64
    value_refined::Float64
    converged::Bool  # Keep for backward compatibility
    iterations::Int
    improvement::Float64
    timed_out::Bool
    error_message::Union{String,Nothing}

    # NEW Tier 1 additions (always available, zero cost)
    f_calls::Int                    # Function evaluations
    g_calls::Int                    # Gradient evaluations
    h_calls::Int                    # Hessian evaluations
    time_elapsed::Float64           # Actual optimization time
    x_converged::Bool               # Parameter convergence
    f_converged::Bool               # Function convergence
    g_converged::Bool               # Gradient convergence
    iteration_limit_reached::Bool   # Hit iteration limit
    convergence_reason::Symbol      # Primary reason (:x_tol, :f_tol, etc.)
end
```

### CSV/JSON Output Updates (Tier 1)

**File**: `refinement_comparison_deg_X.csv`

**Add columns**:
- `f_calls`, `g_calls`, `h_calls`
- `time_elapsed`
- `x_converged`, `f_converged`, `g_converged`, `iter_limit`
- `convergence_reason`

**File**: `refinement_summary.json`

**Add statistics**:
```json
{
  "convergence_breakdown": {
    "g_tol": 12,
    "f_tol": 3,
    "x_tol": 1,
    "iterations": 2,
    "timeout": 5,
    "error": 0
  },
  "call_counts": {
    "mean_f_calls": 127.3,
    "max_f_calls": 450,
    "mean_g_calls": 64.1
  },
  "timing": {
    "mean_time_per_point": 2.3,
    "max_time_per_point": 29.8,
    "points_timed_out": 5
  }
}
```

## Requirements: Tier 2 (Medium Priority)

### Optional Advanced Diagnostics (Requires Trace)

These diagnostics require `store_trace=true` in Optim options, which has memory cost proportional to iterations.

#### 1. Final Gradient Norm (BFGS Only)

**Required**: Gradient norm at final iteration

```julia
final_gradient_norm::Union{Float64,Nothing}
```

**Value**: Verify critical point quality. True critical points should have ‖∇f‖ ≈ 0.

**Implementation**:
```julia
# Requires store_trace=true
if !isempty(Optim.trace(result))
    final_g_norm = last(Optim.trace(result)).g_norm
else
    final_g_norm = nothing
end
```

**Note**: For NelderMead (gradient-free), would need separate ForwardDiff call.

#### 2. Optimization Trajectory

**Required**: Full iteration history

```julia
trajectory::Union{Vector{OptimizationState},Nothing}
```

**Each trace entry contains**:
- `iteration::Int`
- `value::Float64` - Objective value
- `g_norm::Float64` - Gradient norm (BFGS) or simplex spread (NelderMead)
- `metadata::Dict` - Method-specific info (step sizes, Hessian approx, etc.)

**Value**:
- Visualize convergence paths (plotting in globtimplots)
- Diagnose slow convergence or oscillation
- Identify basin structure

**Cost**: Memory scales as O(iterations × dimensions)

**Implementation**:
```julia
# In RefinementConfig
store_trajectory::Bool = false  # Default off for memory

# If enabled, extract from result
trajectory = if config.store_trajectory
    Optim.trace(result)
else
    nothing
end
```

#### 3. Convergence Speed Metrics

**Required**: Characterize how fast optimization converges

```julia
convergence_rate::Union{Float64,Nothing}  # Improvement per iteration
iterations_to_tolerance::Union{Int,Nothing}  # Iterations until within tolerance
```

**Value**: Compare basins (fast-converging = good basin) and methods (BFGS vs NelderMead).

**Implementation**:
```julia
# From trajectory
if trajectory !== nothing
    values = [state.value for state in trajectory]
    convergence_rate = (values[end] - values[1]) / length(values)
end
```

### Enhanced RefinementConfig (Tier 2)

```julia
struct RefinementConfig
    # Existing fields...
    method::Optim.AbstractOptimizer
    max_time_per_point::Union{Nothing, Float64}
    f_abstol::Float64
    x_abstol::Float64
    max_iterations::Int
    parallel::Bool
    robust_mode::Bool
    show_progress::Bool

    # NEW Tier 2 additions
    store_trajectory::Bool              # Enable trajectory storage
    compute_final_gradient::Bool        # Compute ‖∇f‖ at end (for NelderMead)
end
```

## Requirements: Tier 3 (Future Directions)

### Specialized Advanced Analysis

These are low-priority or specialized use cases for algorithm development.

#### 1. Hessian Approximation (BFGS)

**Available**: Inverse Hessian approximation from BFGS trace metadata

**Value**: Second-order optimization diagnostics, curvature information

**Cost**: O(n²) storage per point

**Use Case**: Very specialized debugging, algorithm development

#### 2. Line Search History (Gradient Methods)

**Available**: Step sizes from trace metadata

**Value**: Line search diagnostics, identify poorly scaled problems

**Use Case**: Algorithm tuning, method comparison

#### 3. Simplex Evolution (NelderMead)

**Available**: `centroid_trace()`, `simplex_trace()` from Optim.jl

**Value**: Visualize simplex movement and deformation

**Cost**: High memory for gradient-free methods

**Use Case**: Gradient-free method development, basin visualization

#### 4. Adaptive Tolerance Selection

**Future Direction**: Automatically adjust tolerances based on problem characteristics

**Approach**:
- Tight tolerances (1e-10) for smooth, well-conditioned problems
- Relaxed tolerances (1e-4) for noisy ODE objectives
- Use gradient norm estimates to guide tolerance selection

#### 5. Multi-Method Refinement

**Future Direction**: Try multiple optimization methods sequentially

**Approach**:
```julia
# Try BFGS first (fast if gradients available)
# If fails, fall back to NelderMead (gradient-free)
# Track which method succeeded
method_used::Symbol  # :BFGS, :NelderMead, :SimulatedAnnealing
```

## Architecture

### Why globtimpostprocessing?

**Correct separation of concerns**:

| Package | Role | Refinement Use | Diagnostics Level |
|---------|------|----------------|-------------------|
| **globtimcore** | Optimization algorithms | Online during HPC runs | Minimal (lean for performance) |
| **globtimpostprocessing** | Analysis & reporting | Offline post-experiment | Comprehensive (extract all info) |
| **globtimplots** | Visualization | Plot trajectories/convergence | Uses data from postprocessing |

**Rationale**:
- ✅ globtimpostprocessing owns the post-hoc refinement workflow
- ✅ Already uses Optim.jl and has RefinementResult structures
- ✅ Post-processing is about extracting maximum information
- ✅ No plotting (stays within architecture boundaries)
- ✅ No circular dependencies (postprocessing doesn't export to core)

### Relationship to globtimcore

**globtimcore** has `analyze_critical_points()` which also uses Optim.jl for refinement:

**Should globtimcore also add these diagnostics?**
- **No** (keep globtimcore lean for HPC)
- Different use case: real-time analysis vs offline deep-dive
- Acceptable duplication for separation of concerns

**Exception**: Tier 1 diagnostics (zero-cost) could be added to globtimcore if needed for online analysis, but not required.

## Implementation Roadmap

### Phase 1: Tier 1 Diagnostics (Core Requirements)

**Target**: globtimpostprocessing v1.1.0

**Tasks**:
1. Enhance `RefinementResult` struct with Tier 1 fields
2. Modify `refine_critical_point()` to extract diagnostics from Optim result
3. Update `save_refined_results()` to write new CSV columns
4. Enhance `refinement_summary.json` with convergence breakdown and statistics
5. Update documentation and examples
6. Add tests for new diagnostic fields

**Acceptance Criteria**:
- All Tier 1 fields populated for every refinement attempt
- CSV output includes call counts, timing, convergence flags
- JSON summary includes convergence breakdown statistics
- Zero regression in existing functionality
- Performance overhead < 1% (diagnostics are free)

### Phase 2: Tier 2 Diagnostics (Optional Advanced)

**Target**: globtimpostprocessing v1.2.0

**Tasks**:
1. Add `store_trajectory` option to RefinementConfig
2. Extract and store optimization trajectories when enabled
3. Compute final gradient norms (BFGS or via ForwardDiff)
4. Add trajectory export to JLD2 format (CSV too large)
5. Create trajectory analysis functions in globtimpostprocessing
6. Create trajectory plotting functions in globtimplots

**Acceptance Criteria**:
- Trajectories stored when `store_trajectory=true`
- Efficient storage format (JLD2 for trajectories, CSV for summary)
- Trajectory analysis functions (convergence speed, basin depth)
- Plotting functions in globtimplots (convergence plots, trajectory visualization)

### Phase 3: Specialized Analysis (Research Features)

**Target**: TBD (research-driven)

**Potential Additions**:
- Hessian approximation extraction (BFGS)
- Multi-method refinement strategies
- Adaptive tolerance selection
- Basin characterization metrics

## Testing Strategy

### Unit Tests

**Test**: Diagnostic extraction from Optim results
```julia
@testset "Tier 1 Diagnostics" begin
    # Simple quadratic: should converge quickly
    result = refine_critical_point(x -> sum(x.^2), [1.0, 1.0], config)

    @test result.converged == true
    @test result.f_calls > 0
    @test result.g_calls >= 0  # May be 0 for NelderMead
    @test result.time_elapsed > 0
    @test result.convergence_reason in [:x_tol, :f_tol, :g_tol]
end
```

### Integration Tests

**Test**: Full refinement workflow with diagnostics
```julia
@testset "Refinement Diagnostics Pipeline" begin
    # Run refinement on saved critical points
    refined = refine_experiment_results(experiment_dir, objective, config)

    # Check all points have diagnostics
    @test all(r -> r.f_calls > 0, refined.refinement_results)
    @test all(r -> r.convergence_reason !== :error, refined.refinement_results)

    # Check summary statistics
    summary = load_json(joinpath(experiment_dir, "refinement_summary.json"))
    @test haskey(summary, "convergence_breakdown")
    @test haskey(summary, "call_counts")
end
```

### Regression Tests

**Test**: Ensure diagnostics don't break existing functionality
```julia
@testset "Backward Compatibility" begin
    # Old code should still work
    refined = refine_experiment_results(experiment_dir, objective, config)
    @test refined.n_converged >= 0
    @test refined.best_refined_value < Inf
end
```

## Success Metrics

### Tier 1 Success Criteria

- **Coverage**: 100% of refinement attempts have complete diagnostics
- **Performance**: < 1% overhead vs current implementation
- **Actionability**: Can diagnose refinement failures from CSV/JSON output alone
- **Example**: "0% convergence because all points hit iteration limit (not timeout)"

### Tier 2 Success Criteria

- **Memory**: Trajectory storage opt-in with clear memory cost documentation
- **Analysis**: Can plot convergence trajectories and identify problematic basins
- **Integration**: globtimplots can visualize trajectories from saved data

## Related Documentation

- [globtimpostprocessing/.claude/CLAUDE.md](../../globtimpostprocessing/.claude/CLAUDE.md) - Package architecture
- [globtimcore/src/refine.jl](../src/refine.jl) - Core refinement implementation (for comparison)
- [Optim.jl Documentation](https://julianlsolvers.github.io/Optim.jl/stable/) - Upstream API reference

## Changelog

- **2025-11-24**: Initial requirements document created
  - Defined 3-tier priority system (Tier 1: zero-cost, Tier 2: optional, Tier 3: future)
  - Specified enhanced RefinementResult struct
  - Outlined implementation roadmap
  - Clarified architectural placement (globtimpostprocessing)
