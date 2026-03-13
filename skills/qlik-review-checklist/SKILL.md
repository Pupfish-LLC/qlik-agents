---
name: QA Review Checklist for Qlik
description: Complete QA checklist used by the qa-reviewer agent for validating Qlik development artifacts. Covers data model integrity, naming convention compliance, script quality, expression correctness, security gaps, cross-artifact consistency, blocked dependency audit, and data quality validation. Also available for manual invocation outside the pipeline via /qlik-review-checklist.
---

# QA Review Checklist for Qlik

## Overview

This checklist provides comprehensive QA validation for all Qlik development artifacts produced across the Qlik Development Framework pipeline (Phases 0–8). It is consumed primarily by the `qa-reviewer` agent during four review passes:

- **Phase 3 Lightweight Review** — Data model specification validation (Critical severity only)
- **Phase 4 Script Execution Validation** — Load script and data model validation (Critical + Warning)
- **Phase 5 Expression Execution Validation** — Expression correctness validation (Critical + Warning)
- **Phase 7 Comprehensive Review** — All artifacts, all severities (Critical + Warning + Suggestion)

The checklist can also be invoked manually outside the pipeline via `/qlik-review-checklist` for ad-hoc QA reviews.

## Severity Definitions

- **Critical:** Blocks pipeline advancement. Reload fails, data integrity violated, security exposure, or fundamental design flaw. This includes expressions that are structurally invalid and guaranteed to produce incorrect results (e.g., nested aggregation without Aggr(), TOTAL placed inside set analysis braces). An expression that cannot evaluate correctly is a data integrity violation.
- **Warning:** Should be fixed before moving forward. Potential data quality issue, naming inconsistency, performance degradation, or best-practice violation.
- **Suggestion:** Improvement recommendation. Code clarity, minor optimization, or pattern consistency.

## Review Pass Types

| Pass | Scope | Applicable Categories | Severity Focus |
|------|-------|----------------------|-----------------|
| **Phase 3 Lightweight** | Data model spec | Data Model Integrity, Naming Convention Compliance, Cross-Artifact Consistency (basic) | Critical only |
| **Phase 4 Script** | Load scripts, final model | Script Syntax, Performance, Data Model Integrity, Naming Compliance, Security, Cross-Artifact Consistency | Critical + Warning |
| **Phase 5 Expressions** | Expression catalog, variables | Expression Correctness, Naming Compliance, Cross-Artifact Consistency | Critical + Warning |
| **Phase 7 Comprehensive** | All artifacts (Phases 0–6) | All categories (9 total) | Critical + Warning + Suggestion |

## Validation Categories (9 total)

1. **Script Syntax** (9 items) — Dollar-sign expansion safety, SQL construct prohibition, function arguments, block balance, NullAsValue scope, RENAME collisions
2. **Performance** (3 items) — Redundant disk reads, repeated expressions, temp table cleanup
3. **Data Model Integrity** (8 items) — Synthetic keys, associations, auto-concatenation, QUALIFY interaction, null handling, grain alignment, circular references, key consistency
4. **Naming Convention Compliance** (5 items) — Entity-prefix dot notation, key field conventions, variable naming, table naming, cross-layer consistency
5. **Expression Correctness** (7 items) — Set analysis syntax, TOTAL qualifier, null handling, field references, dollar-sign expansion, calculation conditions, structurally invalid aggregation
6. **Security** (5 items) — PII exposure, Section Access STAR handling, reduction field case-sensitivity, completeness, OMIT field correctness
7. **Cross-Artifact Consistency** (4 items) — Expressions reference existing fields, viz specs reference existing expressions, scripts use platform subroutines, field name consistency
8. **Blocked Dependency Audit** (3 items) — Placeholder documentation, downstream flags, pipeline state alignment
9. **Data Quality Validation** (5 items) — Null rate analysis, referential integrity, value distribution, row counts, orphaned records

## How to Use This Checklist

1. **Load `checklist.md`** for detailed check items, verification methods, and finding format examples.
2. **For each applicable review pass** (Phase 3/4/5/7), iterate through checklist items marked for that pass.
3. **Document all findings** using the standardized Finding Format (see checklist.md).
4. **Organize findings** by category and severity in the output report.
5. **Flag execution validation requests** — If Phase 4 or Phase 5, pause and flag specific validation requests to the developer.
6. **Verify Critical finding resolution** — For Phase 7, ensure all Critical findings from earlier passes are resolved before closing.

## Finding Format

```
[ID]: [Title]
- Severity: [Critical | Warning | Suggestion]
- Category: [category_name]
- Location: [artifact_path]:[line number] or [location description]
- Finding: [Detailed description of what is wrong]
- Impact: [What breaks or what negative consequence occurs]
- Recommended Fix: [Specific action to resolve]
```

**Example:**
```
[S-1.1]: Dollar-sign expansion with nested function
- Severity: Critical
- Category: Script Syntax
- Location: artifacts/04-scripts/load-main.qvs:42
- Finding: $(variable(...)) contains ApplyMap with comma-separated arguments
- Impact: Variable expansion will fail during reload, breaking script execution
- Recommended Fix: Rewrite inline without variable wrapping to avoid comma nesting
```

## Review Pass Applicability Summary

| Category | Phase 3 | Phase 4 | Phase 5 | Phase 7 |
|----------|:---:|:---:|:---:|:---:|
| Script Syntax | — | ✓ | — | ✓ |
| Performance | — | ✓ | — | ✓ |
| Data Model Integrity | ✓ | ✓ | — | ✓ |
| Naming Convention Compliance | ✓ | ✓ | ✓ | ✓ |
| Expression Correctness | — | — | ✓ | ✓ |
| Security | — | ✓ | — | ✓ |
| Cross-Artifact Consistency | (basic) | ✓ | ✓ | ✓ |
| Blocked Dependency Audit | — | (light) | (light) | ✓ |
| Data Quality Validation | — | ✓ | — | ✓ |

## See Also

- **checklist.md** — Full detailed checklist with all items (1.1–9.5), verification methods, and examples
- **qlik-naming-conventions** — Field naming, key conventions, variable naming, cross-layer strategies
- **qlik-load-script** — Script syntax rules, QVD operations, incremental loads, null handling
- **qlik-data-modeling** — Data model design patterns, synthetic key prevention, grain management
- **qlik-expressions** — Expression syntax, set analysis, null handling in measures
- **qlik-performance** — Optimization strategies, QVD load modes, preceding LOAD patterns
