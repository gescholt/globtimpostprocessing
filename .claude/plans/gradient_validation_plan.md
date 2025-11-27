# Gradient Norm Validation Plan

## Overview

Add gradient norm validation to verify that found critical points are actually critical (||∇f(x*)|| ≈ 0).

---

## Implementation

**Package**: `globtimpostprocessing`
**File**: `src/refinement/gradient_validation.jl` (new file)

### Functions to Add

```julia
"""
Compute gradient norms at critical points using ForwardDiff
"""
function compute_gradient_norms(
    points::Vector{Vector{Float64}},
    objective::Function
) -> Vector{Float64}

"""
Validate critical points by gradient norm threshold
"""
function validate_critical_points(
    points::Vector{Vector{Float64}},
    objective::Function;
    tolerance::Float64 = 1e-6
) -> NamedTuple{(:norms, :valid, :n_valid, :n_invalid)}

"""
Add gradient validation to refinement results
"""
function add_gradient_validation!(
    comparison_df::DataFrame,
    objective::Function;
    tolerance::Float64 = 1e-6
)
```

### Integration Points

1. Add to `refine_experiment_results()` output
2. Include in `refinement_summary_deg_X.json`
3. Export gradient norms to CSV comparison file

---

## Files to Modify/Create

| File | Action |
|------|--------|
| `src/refinement/gradient_validation.jl` | CREATE |
| `src/refinement/core_refinement.jl` | MODIFY (integrate gradient validation) |
| `src/GlobtimPostProcessing.jl` | MODIFY (export new functions) |

---

## Dependencies

- `ForwardDiff` (for gradient computation) - check if already in Project.toml

---

## Success Criteria

1. Gradient norms computed for all refined critical points
2. Validation returns count of valid/invalid points
3. Integration with existing refinement workflow
