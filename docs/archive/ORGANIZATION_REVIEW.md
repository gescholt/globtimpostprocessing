# Repository Organization Analysis & Recommendations

**Date**: 2025-11-23
**Status**: Post Phase 1 Integration Review

## Current State Analysis

### Root-Level Markdown Files (6 files)

| File | Size | Purpose | Status |
|------|------|---------|--------|
| `README.md` | 4.4K | Main repository documentation | ✅ Keep |
| `CHANGELOG.md` | 6.5K | Version history | ✅ Keep |
| `REFINEMENT_PHASE1_STATUS.md` | 7.4K | Original Phase 1 status (pre-integration) | ⚠️ **Redundant** |
| `PHASE1_INTEGRATION_VERIFIED.md` | 7.1K | Integration verification checklist | ⚠️ **Redundant** |
| `TESTING_PHASE1.md` | 5.0K | Testing guide and troubleshooting | ⚠️ **Redundant** |
| `PHASE1_INTEGRATION_SUMMARY.md` | 11K | **Complete integration summary** | ✅ **Master Doc** |

**Issues**:
- **4 Phase 1 documents** with overlapping content
- Root directory cluttered with temporary/intermediate docs
- No clear "source of truth" for Phase 1

### Documentation Directory Structure

```
docs/
├── planning/              # Feature plans → Should become GitHub issues
│   ├── CONSOLIDATION_PLAN.md (21K)
│   └── ANALYSIS_PLAN_20251014.md (17K)
│
├── completed/             # Done features → Archive or delete
│   ├── TRAJECTORY_ANALYSIS_IMPLEMENTATION.md (9.6K)
│   ├── ANALYSIS_ENHANCEMENT_REVIEW.md (11K)
│   └── vegalite_tidier_integration.md (7.7K)
│
├── guides/                # User guides → Keep active
│   ├── QUICK_START.md (4.2K)
│   ├── README_VEGALITE.md (3.1K)
│   └── QUICK_ANALYSIS_GUIDE.md (4.8K)
│
├── archive/               # Historical docs
│   ├── bug-fixes/VERIFICATION_REPORT.md (6.9K)
│   ├── LANDSCAPE_FIDELITY_TEST_PLAN.md (17K)
│   ├── LANDSCAPE_FIDELITY_TEST_RESULTS.md (11K)
│   ├── tidier_vega_guide.md (12K)
│   └── README.md (1.2K)
│
└── (root docs/)           # Active specifications
    ├── LANDSCAPE_FIDELITY_GUIDE.md (9.1K)
    ├── CODE_REVIEW_BEST_PRACTICES.md (17K)
    ├── EXPERIMENT_STRUCTURE_SPEC.md (11K)
    └── DOC_ORGANIZATION_SUMMARY.md (7.0K)
```

**Issues**:
- `completed/` directory should be moved to archive or deleted
- `planning/` docs should become GitHub issues, then archive
- Root docs/ has mixed purposes (guides vs specs vs meta-docs)

### Other Directories

```
collected_experiments_20251013_083530/  # ⚠️ Should not be in repo
├── campaign_lotka_volterra_4d_extended_degrees/
├── campaign_lv4d_domain_sweep/
├── parameter_analysis/
└── COLLECTION_SUMMARY.md (9.1K)

archived_scripts/          # ✅ Good - contains old scripts
└── README.md (415 bytes)

examples/                  # ✅ Keep - example code
scripts/                   # ✅ Keep - utility scripts
src/                       # ✅ Keep - source code
```

**Issues**:
- **`collected_experiments_20251013_083530/`** is experimental data - should be in `.gitignore`
- Takes up space and is specific to one person's analysis

## 📋 Recommendations

### 1. **Consolidate Phase 1 Documentation** ⭐ HIGH PRIORITY

**Action**: Merge 4 Phase 1 docs into 1 master document

**Keep**:
- ✅ `PHASE1_INTEGRATION_SUMMARY.md` (most comprehensive)

**Archive** → `docs/archive/phase1/`:
```bash
mkdir -p docs/archive/phase1
mv REFINEMENT_PHASE1_STATUS.md docs/archive/phase1/
mv PHASE1_INTEGRATION_VERIFIED.md docs/archive/phase1/
mv TESTING_PHASE1.md docs/archive/phase1/
```

**Add to Archive README**:
```markdown
## Phase 1 Refinement - Historical Documents

These documents tracked the Phase 1 integration process:
- `REFINEMENT_PHASE1_STATUS.md` - Original status before integration
- `PHASE1_INTEGRATION_VERIFIED.md` - Verification checklist during integration
- `TESTING_PHASE1.md` - Testing troubleshooting during integration

**Current documentation**: See `/PHASE1_INTEGRATION_SUMMARY.md`
```

**Benefit**: Single source of truth, cleaner root directory

---

### 2. **Archive Completed Feature Docs** ⭐ MEDIUM PRIORITY

**Action**: Move `docs/completed/` → `docs/archive/completed/`

```bash
mv docs/completed docs/archive/completed
```

Update `docs/archive/README.md`:
```markdown
## Completed Features

Historical implementation documents:
- `completed/TRAJECTORY_ANALYSIS_IMPLEMENTATION.md` - Trajectory analysis (Oct 2025)
- `completed/ANALYSIS_ENHANCEMENT_REVIEW.md` - Analysis enhancements (Oct 2025)
- `completed/vegalite_tidier_integration.md` - VegaLite integration (Oct 2025)

These features are now part of the main codebase.
```

**Benefit**: Clearer separation of active vs historical docs

---

### 3. **Convert Planning Docs to GitHub Issues** ⭐ MEDIUM PRIORITY

**Action**: Extract issues from planning docs, then archive

From `docs/planning/CONSOLIDATION_PLAN.md`:
- Create GitHub issue: "Consolidate campaign analysis workflows"
- Create GitHub issue: "Improve error handling in batch processing"

From `docs/planning/ANALYSIS_PLAN_20251014.md`:
- Create GitHub issue: "Implement advanced parameter recovery analysis"
- Create GitHub issue: "Add campaign comparison visualizations"

Then move to archive:
```bash
mv docs/planning docs/archive/planning
```

**Benefit**: Track work in GitHub, archive historical plans

---

### 4. **Reorganize Root docs/** ⭐ LOW PRIORITY

**Current Structure** (mixed purposes):
```
docs/
├── LANDSCAPE_FIDELITY_GUIDE.md          # User guide
├── CODE_REVIEW_BEST_PRACTICES.md        # Developer guide
├── EXPERIMENT_STRUCTURE_SPEC.md         # Technical spec
└── DOC_ORGANIZATION_SUMMARY.md          # Meta-doc
```

**Proposed Structure**:
```
docs/
├── specs/                               # Technical specifications
│   ├── EXPERIMENT_STRUCTURE.md          # Rename: remove SPEC suffix
│   └── LANDSCAPE_FIDELITY_API.md        # Rename: clarify it's API spec
│
├── guides/                              # User & dev guides
│   ├── user/
│   │   ├── QUICK_START.md              # Already here
│   │   ├── QUICK_ANALYSIS_GUIDE.md     # Already here
│   │   └── VEGALITE_USAGE.md           # Rename from README_VEGALITE
│   └── developer/
│       ├── CODE_REVIEW.md              # Rename from CODE_REVIEW_BEST_PRACTICES
│       └── LANDSCAPE_FIDELITY.md       # Move from root, clarify usage
│
└── archive/                             # Keep as is
    └── DOC_ORGANIZATION_SUMMARY.md      # Meta-doc about cleanup
```

**Benefit**: Clear separation by audience (user vs developer vs spec)

---

### 5. **Remove Experiment Data from Repo** ⭐ HIGH PRIORITY

**Action**: Remove collected experiments and add to .gitignore

```bash
# Add to .gitignore
echo "collected_experiments_*/" >> .gitignore

# Remove from repo (if not needed)
git rm -r collected_experiments_20251013_083530/
# OR move to separate location outside repo
```

**Benefit**: Smaller repo, cleaner history, no personal data in version control

---

### 6. **Simplify Archive Structure** ⭐ LOW PRIORITY

**Current**:
```
docs/archive/
├── bug-fixes/
│   └── VERIFICATION_REPORT.md
├── LANDSCAPE_FIDELITY_TEST_PLAN.md
├── LANDSCAPE_FIDELITY_TEST_RESULTS.md
├── tidier_vega_guide.md
└── README.md
```

**Proposed**:
```
docs/archive/
├── README.md                            # Index of all archived docs
├── phase1/                              # Phase 1 integration docs
│   ├── REFINEMENT_PHASE1_STATUS.md
│   ├── PHASE1_INTEGRATION_VERIFIED.md
│   └── TESTING_PHASE1.md
├── completed-features/                  # Implemented features
│   ├── trajectory-analysis/
│   ├── vegalite-integration/
│   └── analysis-enhancements/
├── planning/                            # Old planning docs (moved to issues)
│   ├── CONSOLIDATION_PLAN.md
│   └── ANALYSIS_PLAN_20251014.md
└── testing/                             # Old test plans/results
    ├── landscape-fidelity/
    │   ├── TEST_PLAN.md
    │   └── TEST_RESULTS.md
    └── bug-fixes/
        └── VERIFICATION_REPORT.md
```

**Benefit**: Better organized history, easier to find old docs

---

## 📊 Priority Matrix

| Action | Priority | Impact | Effort | Recommended |
|--------|----------|--------|--------|-------------|
| Consolidate Phase 1 docs | ⭐⭐⭐ High | High | Low | **Do first** |
| Remove experiment data | ⭐⭐⭐ High | Medium | Low | **Do first** |
| Archive completed features | ⭐⭐ Medium | Medium | Low | **Do soon** |
| Convert planning to issues | ⭐⭐ Medium | High | Medium | **Do soon** |
| Reorganize root docs/ | ⭐ Low | Low | Medium | **Optional** |
| Simplify archive | ⭐ Low | Low | Low | **Optional** |

---

## 🚀 Quick Action Plan

### Immediate (< 5 minutes):

```bash
# 1. Consolidate Phase 1 docs
mkdir -p docs/archive/phase1
mv REFINEMENT_PHASE1_STATUS.md docs/archive/phase1/
mv PHASE1_INTEGRATION_VERIFIED.md docs/archive/phase1/
mv TESTING_PHASE1.md docs/archive/phase1/

# 2. Remove experiment data
echo "collected_experiments_*/" >> .gitignore
git rm -r collected_experiments_20251013_083530/
# Note: Commit message should explain this is personal data, not package code
```

### Short-term (< 30 minutes):

```bash
# 3. Archive completed features
mv docs/completed docs/archive/completed

# 4. Update archive README
# Add section explaining what's in archive/phase1/ and archive/completed/
```

### Medium-term (when creating issues):

```bash
# 5. Extract GitHub issues from planning docs
# Read docs/planning/*.md and create issues
# Then: mv docs/planning docs/archive/planning
```

---

## 📁 Proposed Final Structure

```
globtimpostprocessing/
├── README.md                            # Main documentation
├── CHANGELOG.md                         # Version history
├── PHASE1_INTEGRATION_SUMMARY.md        # Phase 1 master doc
│
├── .claude/
│   └── CLAUDE.md                        # Claude Code instructions
│
├── docs/
│   ├── guides/                          # User guides
│   │   ├── QUICK_START.md
│   │   ├── QUICK_ANALYSIS_GUIDE.md
│   │   └── README_VEGALITE.md
│   │
│   ├── specs/                           # (Optional) Technical specs
│   │   ├── EXPERIMENT_STRUCTURE.md
│   │   └── LANDSCAPE_FIDELITY_GUIDE.md
│   │
│   ├── CODE_REVIEW_BEST_PRACTICES.md   # Dev guide
│   │
│   └── archive/                         # Historical docs
│       ├── README.md                    # Archive index
│       ├── phase1/                      # Phase 1 integration history
│       ├── completed/                   # Implemented features
│       ├── planning/                    # Old plans (now issues)
│       └── testing/                     # Old test docs
│
├── src/                                 # Source code
├── test/                                # Tests
├── examples/                            # Example code
├── scripts/                             # Utility scripts
└── archived_scripts/                    # Old scripts
```

**Benefits**:
- ✅ Clear separation: active vs historical
- ✅ Single source of truth for each topic
- ✅ Easy to find current documentation
- ✅ Historical context preserved but not cluttering
- ✅ Cleaner root directory

---

## 🎯 Specific File Recommendations

### Merge/Delete:

| Files to Merge | Into | Reason |
|----------------|------|--------|
| REFINEMENT_PHASE1_STATUS.md<br>PHASE1_INTEGRATION_VERIFIED.md<br>TESTING_PHASE1.md | Archive → Keep only<br>PHASE1_INTEGRATION_SUMMARY.md | Redundant, superseded by summary |

### Archive:

| File | Move To | Reason |
|------|---------|--------|
| docs/completed/* | docs/archive/completed/ | Features are complete |
| docs/planning/* | docs/archive/planning/ | Convert to issues first |
| docs/LANDSCAPE_FIDELITY_TEST_*.md | docs/archive/testing/ | Tests complete |
| docs/tidier_vega_guide.md | docs/archive/completed/ | Feature complete |

### Keep & Rename (Optional):

| Current | Suggested | Reason |
|---------|-----------|--------|
| EXPERIMENT_STRUCTURE_SPEC.md | specs/EXPERIMENT_STRUCTURE.md | Clearer location |
| CODE_REVIEW_BEST_PRACTICES.md | guides/developer/CODE_REVIEW.md | Better categorization |
| README_VEGALITE.md | guides/VEGALITE_USAGE.md | Clearer name |

---

## Summary

**Current State**:
- 6 root-level markdown files (4 are Phase 1 duplicates)
- 25 total markdown files
- Mixed organization in docs/ (planning, completed, guides, archive)
- Experimental data in repo

**Recommended State**:
- 3 root-level markdown files (README, CHANGELOG, Phase 1 summary)
- Clear docs/guides/ and docs/archive/ separation
- No experimental data in repo
- Planning docs → GitHub issues

**Estimated Cleanup Time**: 30-60 minutes
**Estimated Benefit**: High (clearer structure, easier maintenance)
