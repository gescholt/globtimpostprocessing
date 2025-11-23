# Trajectory Analysis Implementation

**Date:** October 2025
**Status:** ✅ Complete
**Approach:** Test-Driven Development (TDD)

## Overview

Implemented comprehensive trajectory analysis functionality for evaluating critical points found by the GlobTim optimizer. This allows researchers to determine which critical points represent true parameter recovery versus spurious solutions.

## Architecture

### 1. ObjectiveFunctionRegistry Module

**Purpose:** Load and reconstruct objective functions from experiment metadata

**Location:** `src/ObjectiveFunctionRegistry.jl`

**Key Functions:**
- `load_dynamical_systems_module()` - Loads DynamicalSystems from Globtim
- `resolve_model_function(name, module)` - Resolves string name to Julia function
- `validate_config(config)` - Validates experiment configuration
- `reconstruct_error_function(config)` - Rebuilds error function from config

**Design Principles:**
- NO FALLBACKS: Errors if model unknown or config incomplete
- Adaptive: Works with any model function in DynamicalSystems
- Type-safe: Full validation before processing

**Tests:** `test/test_objective_function_registry.jl`, `test/test_objective_function_registry_implementation.jl`

---

### 2. TrajectoryEvaluator Module

**Purpose:** Solve ODE trajectories and evaluate critical point quality

**Location:** `src/TrajectoryEvaluator.jl`

**Key Functions:**
- `solve_trajectory(config, parameters)` - Solve ODE with given parameters
- `compute_trajectory_distance(traj1, traj2, norm_type)` - Compute trajectory distance (L1, L2, Linf)
- `evaluate_critical_point(config, critical_point)` - Comprehensive critical point evaluation
- `compare_trajectories(config, p_true, p_found)` - Detailed trajectory comparison

**Features:**
- Supports arbitrary number of outputs
- Multiple distance metrics (L1, L2, Linf)
- Parameter space and trajectory space distances
- Validates dimensions and handles solver failures

**Tests:** `test/test_trajectory_evaluator.jl`

---

### 3. TrajectoryComparison Module

**Purpose:** High-level analysis combining parameter recovery and trajectory evaluation

**Location:** `src/TrajectoryComparison.jl`

**Key Functions:**
- `load_critical_points_for_degree(exp_path, degree)` - Load CSV for specific degree
- `evaluate_all_critical_points(config, df)` - Batch evaluation with augmented DataFrame
- `rank_critical_points(df, by)` - Rank by parameter/trajectory distance
- `identify_parameter_recovery(df, threshold)` - Filter recovery candidates
- `analyze_experiment_convergence(exp_path)` - Convergence analysis across degrees
- `generate_comparison_report(exp_path, format)` - Formatted reports (text/markdown/JSON)
- `compare_degrees(exp_path, deg1, deg2)` - Compare two polynomial degrees
- `analyze_campaign_parameter_recovery(campaign_path)` - Campaign-level aggregation

**Features:**
- Convergence tracking across polynomial degrees
- Multiple output formats (text, markdown, JSON)
- Campaign-level aggregation
- Parameter recovery identification with configurable threshold

**Tests:** `test/test_trajectory_comparison.jl`

---

### 4. Interactive Analysis Mode

**Purpose:** User-facing interactive trajectory analysis

**Location:** `analyze_experiments.jl` (mode 4)

**Functions Added:**
- `analyze_trajectories_interactive(exp_path)` - Main interactive mode
- `inspect_critical_point(cp_row, config, degree)` - Detailed critical point inspection

**Features:**
- Convergence summary across degrees
- Select polynomial degree to analyze
- View top 20 critical points ranked by parameter distance
- Interactive critical point selection
- Detailed metrics for each critical point:
  - Parameter values (found vs true)
  - Objective function value
  - Parameter distance (L2)
  - Trajectory distance (L2)
  - Recovery status (YES/NO)
  - Component-wise parameter comparison

**User Workflow:**
```
1. Select campaign
2. Select experiment
3. Choose mode 4 (Interactive trajectory analysis)
4. View convergence summary
5. Select polynomial degree
6. Browse top critical points
7. Inspect individual critical points
8. Compare parameters component-wise
```

---

## Test Coverage

### Unit Tests (TDD Specifications)
1. `test_objective_function_registry.jl` - API specification
2. `test_objective_function_registry_implementation.jl` - Implementation verification
3. `test_trajectory_evaluator.jl` - TDD specification for trajectory solving
4. `test_trajectory_comparison.jl` - TDD specification for high-level analysis

### Integration Tests
- `test_trajectory_analysis_e2e.jl` - End-to-end pipeline validation
  - ObjectiveFunctionRegistry integration
  - TrajectoryEvaluator integration
  - TrajectoryComparison integration
  - Full pipeline integration
  - Error handling

**Test Results:** All tests designed and ready to run after loading Globtim dependencies

---

## Usage Examples

### Programmatic Usage

```julia
using Pkg
Pkg.activate("globtimpostprocessing")

include("src/TrajectoryComparison.jl")
using .TrajectoryComparison

# Analyze single experiment convergence
convergence = analyze_experiment_convergence("/path/to/experiment")

println("Degrees analyzed: ", convergence.degrees)
for deg in convergence.degrees
    println("Degree $deg:")
    println("  Critical points: ", convergence.num_critical_points_by_degree[deg])
    println("  Recoveries: ", convergence.num_recoveries_by_degree[deg])
    println("  Best param distance: ", convergence.best_param_distance_by_degree[deg])
end

# Generate markdown report
report = generate_comparison_report("/path/to/experiment", :markdown)
write("convergence_report.md", report)

# Campaign analysis
campaign_df = analyze_campaign_parameter_recovery("/path/to/campaign")
CSV.write("campaign_summary.csv", campaign_df)
```

### Interactive Usage

```bash
cd globtimpostprocessing
julia analyze_experiments.jl

# Then:
# 1. Select campaign
# 2. Select experiment
# 3. Choose mode 4
# 4. View convergence summary
# 5. Select degree
# 6. Browse and inspect critical points
```

---

## Design Principles

### 1. No Fallbacks
- All modules ERROR when encountering missing data or invalid configurations
- No fake/default data generated
- Clear error messages explain what went wrong

### 2. TDD Approach
- Tests written FIRST (specifications)
- Implementation follows test requirements
- Ensures API correctness and usability

### 3. Modularity
- Each module has single responsibility
- Clear dependencies (ObjectiveFunctionRegistry → TrajectoryEvaluator → TrajectoryComparison)
- Reusable components

### 4. Flexibility
- Works with any DynamicalSystems model
- Supports arbitrary parameter dimensions
- Multiple distance metrics and output formats

### 5. User-Focused
- Interactive mode for exploration
- Clear visual output with colors
- Component-wise parameter comparison

---

## Integration with Existing System

### Fits into GlobTim Workflow:
```
1. Run experiment (globtimcore) → generates critical_points_deg_N.csv
2. Post-processing (globtimpostprocessing):
   a. Mode 1: Single experiment statistics
   b. Mode 2: Campaign aggregation
   c. Mode 3: Parameter recovery table
   d. Mode 4: ✨ NEW Interactive trajectory analysis ✨
```

### Dependencies:
- Globtim package (for DynamicalSystems module)
- ModelingToolkit.jl (for ODE solving)
- DataFrames.jl, CSV.jl (for data handling)
- JSON3.jl (for config loading)
- LinearAlgebra, Statistics (standard library)

---

## Files Created

### Source Code
- `src/ObjectiveFunctionRegistry.jl` (345 lines)
- `src/TrajectoryEvaluator.jl` (357 lines)
- `src/TrajectoryComparison.jl` (485 lines)

### Tests
- `test/test_objective_function_registry.jl` (167 lines)
- `test/test_objective_function_registry_implementation.jl` (216 lines)
- `test/test_trajectory_evaluator.jl` (196 lines)
- `test/test_trajectory_comparison.jl` (301 lines)
- `test/test_trajectory_analysis_e2e.jl` (381 lines)

### Modified Files
- `analyze_experiments.jl` (+167 lines)
  - Added mode 4
  - Added `analyze_trajectories_interactive()`
  - Added `inspect_critical_point()`

### Documentation
- `docs/TRAJECTORY_ANALYSIS_IMPLEMENTATION.md` (this file)

**Total:** ~2,615 lines of code and tests

---

## Next Steps

### Testing
1. Run unit tests with real Globtim environment:
   ```bash
   cd globtimpostprocessing
   julia test/test_objective_function_registry_implementation.jl
   julia test/test_trajectory_analysis_e2e.jl
   ```

2. Test interactive mode with real experiment data:
   ```bash
   julia analyze_experiments.jl --path ../globtimcore/experiments/lotka_volterra_4d_study/hpc_results
   ```

### Future Enhancements
1. **Visualization:** Add trajectory plotting (true vs found)
2. **Export:** Save evaluated critical points to CSV
3. **Filtering:** Interactive filtering by distance threshold
4. **Comparison plots:** Parameter space visualization
5. **Batch mode:** Non-interactive batch evaluation for automation

---

## Summary

Implemented complete trajectory analysis pipeline using TDD methodology:

✅ **ObjectiveFunctionRegistry** - Model loading and error function reconstruction
✅ **TrajectoryEvaluator** - ODE solving and trajectory distance computation
✅ **TrajectoryComparison** - Convergence analysis and reporting
✅ **Interactive Mode 4** - User-friendly critical point inspection
✅ **Comprehensive Tests** - Unit tests and E2E integration tests
✅ **Documentation** - This implementation guide

**Result:** Researchers can now interactively evaluate which critical points represent true parameter recovery, understand convergence across polynomial degrees, and generate detailed comparison reports.

---

**Author:** GlobTim Development Team
**Implementation Date:** October 2025
**Methodology:** Test-Driven Development
**Status:** ✅ Complete and ready for testing
