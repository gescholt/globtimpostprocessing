# Documentation Organization Summary

**Date**: 2025-11-22
**Purpose**: Cleanup and reorganization of markdown documentation

## Overview

This repository had numerous markdown files scattered across different locations, many of which were:
- Duplicates (same content in multiple places)
- Implementation plans for partially completed features
- Historical documents about bugs that have been fixed
- Completed feature documentation

This cleanup organizes all documentation into a clear structure suitable for converting to GitHub issues.

## New Directory Structure

```
docs/
├── planning/              # Feature requests and implementation plans (→ GitHub issues)
│   ├── CONSOLIDATION_PLAN.md
│   └── ANALYSIS_PLAN_20251014.md
│
├── completed/             # Completed feature implementations (→ Archive or reference)
│   ├── TRAJECTORY_ANALYSIS_IMPLEMENTATION.md
│   ├── ANALYSIS_ENHANCEMENT_REVIEW.md
│   └── vegalite_tidier_integration.md
│
├── guides/                # Active user guides (→ Keep)
│   ├── QUICK_START.md
│   ├── README_VEGALITE.md
│   └── QUICK_ANALYSIS_GUIDE.md
│
├── archive/               # Historical documents
│   ├── bug-fixes/
│   │   └── VERIFICATION_REPORT.md
│   ├── LANDSCAPE_FIDELITY_TEST_PLAN.md
│   ├── LANDSCAPE_FIDELITY_TEST_RESULTS.md
│   ├── tidier_vega_guide.md
│   └── README.md
│
└── (root level docs - kept as specs)
    ├── LANDSCAPE_FIDELITY_GUIDE.md
    ├── CODE_REVIEW_BEST_PRACTICES.md
    ├── EXPERIMENT_STRUCTURE_SPEC.md
    └── DOC_ORGANIZATION_SUMMARY.md (this file)
```

## Changes Made

### 1. Removed Duplicates
**Files deleted from root** (identical copies exist in `docs/guides/`):
- `QUICK_START.md` → Use `docs/guides/QUICK_START.md`
- `README_VEGALITE.md` → Use `docs/guides/README_VEGALITE.md`

### 2. Organized Planning Documents
**Moved to `docs/planning/`** (for GitHub issue creation):
- `CONSOLIDATION_PLAN.md` - Script consolidation proposal (⚠️ PARTIALLY IMPLEMENTED)
  - **Status updated** to show what's implemented vs. what's missing
  - **Recommendation**: Split into separate GitHub issues for each unimplemented mode

- `ANALYSIS_PLAN_20251014.md` - Analysis plan for specific dataset
  - **Recommendation**: Convert to GitHub issues for:
    - Extended degree testing analysis (Issue #172 related)
    - Minimal 4D LV tests validation (Issue #139)
    - Parameter recovery experiments (Issue #117)
    - Basis comparison implementation

### 3. Archived Completed Work
**Moved to `docs/completed/`** (implementation documentation):
- `TRAJECTORY_ANALYSIS_IMPLEMENTATION.md` - ✅ Complete (October 2025)
  - Comprehensive trajectory analysis functionality
  - All modules implemented and tested

- `ANALYSIS_ENHANCEMENT_REVIEW.md` - ⚠️ Phase 1 complete, Phases 2-4 pending
  - Critical point quality analysis implemented
  - Convergence analysis pending
  - Comparative campaign analysis pending

- `vegalite_tidier_integration.md` - ✅ Phase 1 complete
  - Minimal L2 visualization working
  - Interactive features and additional metrics pending

### 4. Archived Historical Documents
**Moved to `docs/archive/`**:
- `VERIFICATION_REPORT.md` → `archive/bug-fixes/`
  - Documents Bug #1 (classification compilation) and Bug #2 (objective proximity)
  - Both bugs FIXED as of 2025-11-15
  - Kept for historical reference

- `tidier_vega_guide.md` → `archive/`
  - Comprehensive guide for VegaLite + Tidier integration
  - Superseded by simpler minimal approach in `README_VEGALITE.md`
  - Kept as reference for advanced features

### 5. Kept Active Documentation
**No changes - these remain active**:
- `LANDSCAPE_FIDELITY_GUIDE.md` - User guide for landscape fidelity assessment
- `CODE_REVIEW_BEST_PRACTICES.md` - Code review and optimization recommendations
- `EXPERIMENT_STRUCTURE_SPEC.md` - Specification for experiment file structure
- `CHANGELOG.md` - Project changelog
- `README.md` - Main project README
- `.claude/CLAUDE.md` - Project instructions for Claude Code

## Recommendations for GitHub Issues

### From CONSOLIDATION_PLAN.md
Create separate issues for:
1. **Enhanced analyze_experiments.jl modes**
   - Mode 1: Single experiment with quality checks + parameter recovery
   - Mode 2: Campaign-wide analysis with cross-experiment recovery
   - Mode 3: Basis comparison integration
   - Mode 5: Export campaign report (markdown/CSV/JSON)

2. **Configurable quality thresholds**
   - Create `quality_thresholds.toml`
   - Implement dimension-dependent L2 thresholds
   - Parameter recovery criteria
   - Convergence stagnation detection

3. **Deprecation plan**
   - Add redirects to old scripts
   - Migration guide for users

### From ANALYSIS_PLAN_20251014.md
Create issues for:
1. **Extended degree analysis** (Issue #172)
   - Analyze deg 4-18 convergence
   - Determine optimal degree
   - Identify plateau point

2. **Basis comparison tool enhancements**
   - Automated pair discovery
   - Visualization generation
   - Recommendation engine refinement

3. **Parameter recovery validation** (Issue #117)
   - Recovery quality metrics
   - Domain size impact analysis
   - Optimal degree determination

### From ANALYSIS_ENHANCEMENT_REVIEW.md
Create issues for:
1. **Phase 2: Multi-degree convergence analysis**
   - Convergence trajectory tracking
   - Solution stability metrics
   - Critical point accumulation analysis

2. **Phase 3: Comparative campaign analysis**
   - Parameter sensitivity analysis
   - Success/failure pattern detection
   - Efficiency metrics

3. **Phase 4: Visualization integration**
   - Auto-generate plots (delegate to globtimplots)
   - Export analysis results for plotting

## Metrics

**Before cleanup:**
- 21 markdown files across 5 locations
- 2 duplicate files in root
- Mixed organization (planning, completed, active)

**After cleanup:**
- 21 markdown files organized by type
- 0 duplicates
- Clear separation: planning → completed → active → archive
- Easy to identify what needs GitHub issues

## Next Steps

1. **Review this summary** with the team
2. **Create GitHub issues** from planning documents:
   - One issue per major feature in CONSOLIDATION_PLAN.md
   - Separate issues for each analysis type in ANALYSIS_PLAN_20251014.md
3. **Archive or update completed docs**:
   - Mark completed features in main README
   - Consider moving completed/ to wiki or website
4. **Update main README** to reference new organization
5. **Optional**: Create a `docs/README.md` explaining the structure

## Questions for Team

1. Should completed implementation docs go to a project wiki instead?
2. Are there any other features in the planning docs that are actually implemented?
3. Should CODE_REVIEW_BEST_PRACTICES.md recommendations be converted to issues?
4. Do we want to keep historical bug fix documentation or remove it?

---

**Created by**: Claude Code automated documentation cleanup
**Branch**: `claude/cleanup-markdown-docs-01MTJkKJ9DVqQXsV9v2KgWDD`
