---
name: data-quality-validator
description: Post-load data quality validation patterns for Qlik development. Provides query templates for null rate analysis, referential integrity checks, value distribution analysis, row count validation, orphaned record detection, sparse field identification, and duplicate detection. Usable by the qa-reviewer when MCP or post-load data access is available. Also provides patterns for embedding validation checks directly into load scripts. Load when performing data quality validation or writing diagnostic scripts.
---

## Overview

Post-load data quality validation catches issues that successful reloads can mask. Scripts reload without errors yet contain incorrect data: synthetic keys, orphaned records, unexpected nulls, duplicate keys, or value anomalies. This skill covers two usage contexts:

1. **QA Reviewer (post-load inspection)** — qa-reviewer runs validation queries against loaded data or via MCP database connections, producing a Data Quality Validation Report
2. **Script Developer (embedded checks)** — script-developer embeds validation checks directly in load scripts, reporting issues during reload via TRACE or error-handling framework

The skill provides actionable query templates and patterns for both contexts.

---

## Section 1: Validation Categories

### 1. Null Rate Analysis

**What it catches:** Fields with unexpected null rates. Key fields should have 0% nulls. Dimension fields may have expected nulls (handled by NullAsValue) or unexpected ones indicating missing source data.

### 2. Referential Integrity

**What it catches:** Foreign keys in fact tables that don't match any primary key in the corresponding dimension. Orphaned records that reference non-existent dimension members.

### 3. Value Distribution

**What it catches:** Unexpected values ('test', 'TBD', encoding artifacts), values outside expected ranges, categorical fields with unexpected cardinality (too many or too few unique values).

### 4. Row Count Validation

**What it catches:** Actual row counts differ significantly from expected counts (from source profile). May indicate incomplete loads, accidental filtering, or incremental load logic errors.

### 5. Duplicate Detection

**What it catches:** Records with duplicate primary keys (key uniqueness violation), full-row duplicates (all field values identical), which corrupt dimensional relationships.

### 6. Sparse Field Analysis

**What it catches:** Fields populated for <10% of records (configurable threshold). Candidates for removal or NullAsValue handling.

### 7. Field Type Consistency

**What it catches:** Fields where Qlik inferred a different type than expected (text loaded as numeric string, or vice versa), indicating data quality issues or mapping errors.

---

## Section 2: Embedded Script Validation Patterns

Validation checks embedded in load scripts run during reload, catching issues before the app is stored.

### Row Count Validation Pattern

```qlik
LET vExpectedRows = 50000;  // From source profile
LET vActualRows = NoOfRows('TableName');
IF $(vActualRows) < $(vExpectedRows) * 0.9 THEN
    TRACE [WARNING] TableName row count $(vActualRows) is more than 10% below expected $(vExpectedRows);
END IF
```

### Key Uniqueness Check Pattern

```qlik
[_DupCheck]:
LOAD [Order.Key], Count([Order.Key]) AS _dup_count
RESIDENT [Orders]
GROUP BY [Order.Key];

LET vDupCount = 0;
[_DupSummary]:
LOAD Count([Order.Key]) AS _total_dups
RESIDENT [_DupCheck]
WHERE _dup_count > 1;
LET vDupCount = Peek('_total_dups', 0, '_DupSummary');
DROP TABLES [_DupCheck], [_DupSummary];

IF $(vDupCount) > 0 THEN
    TRACE [WARNING] Orders has $(vDupCount) duplicate key values;
END IF
```

### Null Rate Check Pattern

```qlik
LET vNullCount = 0;
[_NullCheck]:
LOAD Count(*) - Count([Order.Key]) AS _null_count
RESIDENT [Orders];
LET vNullCount = Peek('_null_count', 0, '_NullCheck');
DROP TABLE [_NullCheck];

IF $(vNullCount) > 0 THEN
    TRACE [CRITICAL] Orders.[Order.Key] has $(vNullCount) null values;
END IF
```

**Note:** The `Count(*)` syntax above applies only to Resident LOADs that are counting rows in a GROUP BY context. In other LOAD contexts, use `Count(field_name)` (never `Count(*)` in the context of aggregating a specific field).

### Integration with Error Handling

If error-handling.qvs is loaded, use the LogMessage subroutine instead of raw TRACE:

```qlik
IF $(vDupCount) > 0 THEN
    CALL LogMessage('WARNING', 'Data Quality', 'Orders has ' & $(vDupCount) & ' duplicate keys');
END IF
```

---

## Section 3: Post-Load Validation Queries

When MCP database connectivity or post-load data access is available, deeper analysis is possible. See `validation-queries.md` for complete query templates.

Queries run against the loaded Qlik data model (via engine API or diagnostic scripts) or against source databases (via MCP) to compare source vs. loaded data. Output is a Data Quality Validation Report consumed by the qa-reviewer.

---

## Section 4: Data Quality Validation Report Format

This output format is the contract between qa-reviewer and data validators:

```markdown
# Data Quality Validation Report

**Date:** [date]
**App:** [app name]
**Validation Type:** [Embedded Script | Post-Load | MCP Source Comparison]

## Summary
- Tables Validated: [N]
- Critical Issues: [N]
- Warnings: [N]
- Clean: [N]

## Findings

### [Table Name]
| Check | Result | Details |
|-------|--------|---------|
| Row Count | [PASS/WARN/FAIL] | Expected: N, Actual: N |
| Key Uniqueness | [PASS/WARN/FAIL] | [N] duplicate keys found |
| Null Rate ([Order.Key]) | [PASS/WARN/FAIL] | [N]% null |
| Null Rate ([Order.Amount]) | [PASS/WARN/FAIL] | [N]% null |
| Value Distribution | [PASS/WARN/FAIL] | [N] unexpected values ('test', 'TBD') found |
| Referential Integrity | [PASS/WARN/FAIL] | [N] orphaned [Customer.Key] references |
| Sparse Fields | [PASS/WARN/FAIL] | [field_list] populated <10% |

### Recommendations
- [List any data quality issues requiring script fixes or downstream handling]
- [List any expected anomalies to document as known limitations]
```

---

## Section 5: Cross-Reference to Diagnostic Patterns

The qlik-load-script skill includes `diagnostic-patterns.md`, which documents TRACE-based logging and basic row count checks during reload. The data-quality-validator extends beyond those basic patterns with deeper analysis queries.

**Distinction:**
- **diagnostic-patterns.md** — Lightweight TRACE milestone tracking, row count logging, file existence checks, error capture during reload. Use for real-time reload monitoring.
- **data-quality-validator** — Comprehensive post-load validation (null rates, referential integrity, value distributions, duplicates). Use for detailed data quality inspection after reload completes.

Cross-reference diagnostic-patterns.md when embedding simple row count checks; use data-quality-validator when performing detailed QA analysis.

---

## Validation Query Structure

All queries in `validation-queries.md` follow these conventions:

- **Qlik Resident queries** — Run during reload as RESIDENT LOADs, no SQL syntax
- **SQL queries** — Provided for MCP source comparison (SQL Server, PostgreSQL, ANSI generic)
- **Field naming** — All examples use entity-prefix dot notation: `[Customer.Key]`, `[Order.Amount]`
- **Parameterization** — Queries accept table and field names as parameters for reuse
- **Threshold-based** — Null rate, sparsity, cardinality checks use configurable thresholds (e.g., "flag if >10% null")

---

## Quality Standards for Validation Queries

- **All Qlik code is syntactically valid** — No SQL syntax in LOAD statements; uses Count(field) not Count(*) for aggregation
- **Every query is reusable** — Parameterized for any table/field combination
- **Thresholds are configurable** — Alerts fire based on project-specific rules (null rate %, sparsity %, cardinality range)
- **Output is structured** — Validation report format is consistent and machine-parseable
- **No duplication with diagnostic-patterns.md** — Cross-reference instead of repeating TRACE patterns

---

## Next Steps

See `validation-queries.md` for complete query templates organized by validation category.
