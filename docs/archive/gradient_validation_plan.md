# Gradient Norm Validation Plan

**Status**: ✅ **IMPLEMENTED** (2025-11-28)
**Commit**: See branch `claude/gradient-validation-01X7Y33uXnDr8ZCY2wLuKVwf`

---

## Overview

Add gradient norm validation to verify that found critical points are actually critical (||∇f(x*)|| ≈ 0).

---

## Implementation

**Package**: `globtimpostprocessing`
**File**: `src/refinement/gradient_validation.jl` (new file)

### Functions Added

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
) -> GradientValidationResult

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

1. ✅ Automatically called by `refine_experiment_results()` for converged points
2. ✅ Included in `refinement_summary_deg_X.json`
3. ✅ Gradient norms exported to CSV comparison file

---

## Files Modified/Created

| File | Action | Status |
|------|--------|--------|
| `src/refinement/gradient_validation.jl` | CREATE | ✅ |
| `src/refinement/api.jl` | MODIFY (integrate gradient validation) | ✅ |
| `src/refinement/io.jl` | MODIFY (save gradient validation) | ✅ |
| `src/GlobtimPostProcessing.jl` | MODIFY (export new functions) | ✅ |
| `Project.toml` | MODIFY (add ForwardDiff) | ✅ |

---

## Dependencies

- ✅ `ForwardDiff` added to Project.toml

---

## Success Criteria

1. ✅ Gradient norms computed for all refined critical points
2. ✅ Validation returns count of valid/invalid points
3. ✅ Integration with existing refinement workflow
