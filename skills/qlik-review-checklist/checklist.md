# QA Review Checklist — Detailed Items

This document contains all checklist items (1.1–9.5) organized by category. Each item specifies severity, applicable review passes, verification methods, and finding format.

---

## 1. Script Syntax (9 items)

Validates script syntax, function usage, block balance, and variable scope. Ensures scripts can execute without reload errors.

**Applicable Review Passes:** Phase 4, Phase 7

### 1.1 Dollar-Sign Expansion Safety

- **Severity:** Critical
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Every `$(variable(...))` call must have arguments that do NOT contain nested function calls with commas
- **How to Verify:**
  - Search artifacts/04-scripts/*.qvs for all `$(`
  - For each match, verify the argument is: simple field name, simple literal, or function call with zero or one argument only
  - Flag any instance where argument contains `ApplyMap(`, `IF(`, `Pick(`, `PurgeChar(`, `SubField(`, `Match(`, or any other multi-parameter function
  - Special check: `SET` (not `LET`) must be used for variable functions containing quotes or `Dual()`
  - Scan exhaustively — this is the single most common Qlik reload error from variables
- **Finding Format:** `[S-1.1]: Dollar-sign expansion with nested function / Severity: Critical / Category: Script Syntax / Location: [file]:[line] / Finding: $(variable(...)) contains [problematic function] with comma-separated arguments / Impact: Variable expansion will fail during reload, breaking script execution / Recommended Fix: Rewrite [line] inline without variable wrapping, or restructure to avoid nested comma-containing functions`

### 1.2 SQL Constructs in LOAD Statements (9 SQL patterns)

- **Severity:** Critical
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** LOAD statements must NOT use SQL-only syntax. Qlik script is not SQL.
- **How to Verify:**
  - Search artifacts/04-scripts/*.qvs for LOAD statements (not `SQL SELECT` pass-through)
  - Scan for each of these SQL-only patterns (case-insensitive):
    1. `HAVING` — rewrite as filter LOAD or preceding LOAD + GROUP BY
    2. `Count(*)` — must be `Count(field_name)` with explicit field
    3. `SELECT DISTINCT` — use `LOAD DISTINCT` instead (LOAD keyword, not SELECT)
    4. `IS NULL` or `IS NOT NULL` in WHERE — use `IsNull(field)` or `NOT IsNull(field)` (function syntax)
    5. `BETWEEN` — rewrite as `field >= low AND field <= high`
    6. `IN (list)` — use `Match(field, val1, val2, ...)` or `WildMatch()`
    7. `CASE WHEN` — use `IF()`, `Pick()`, or `Match()` inside LOAD
    8. `LIMIT` — use `WHERE RowNo() <= N` on RESIDENT LOAD
    9. Table aliases like `FROM table t1` — use full table names in brackets, no aliases
  - Note: `SQL SELECT` pass-through statements to database connections CAN use native SQL syntax (all of above is valid in `SQL SELECT`)
- **Finding Format:** `[S-1.2]: SQL construct [construct name] in LOAD statement / Severity: Critical / Category: Script Syntax / Location: [file]:[line] / Finding: [construct] is SQL-only syntax, not valid in Qlik LOAD / Impact: Script reload will fail or produce silent data errors / Recommended Fix: Rewrite [line] using Qlik equivalent: [suggested replacement]`

### 1.3 Function Argument Counts

- **Severity:** Critical
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Three critical functions are frequently miscalled with wrong argument count
- **How to Verify:**
  - **PurgeChar(text, chars_to_remove)**: exactly 2 arguments required. Flag `PurgeChar(field)` with only 1 arg.
  - **SubField(text, delimiter, index)**: delimiter must be present when extracting specific element. Flag calls missing delimiter.
  - **ApplyMap('MapName', key, default)**: map name must be quoted; default must be present when fallback is needed. Flag unquoted map names or missing defaults.
  - Search artifacts/04-scripts/*.qvs for all instances of these functions
  - Verify argument count and quoting
- **Finding Format:** `[S-1.3]: Function [function name] called with incorrect argument count / Severity: Critical / Category: Script Syntax / Location: [file]:[line] / Finding: [function]([args]) expects [expected count] arguments, received [actual count] / Impact: Function will fail during reload or produce unexpected behavior / Recommended Fix: Rewrite as [function]([correct args])`

### 1.4 Block Balance

- **Severity:** Critical
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** IF/END IF, SUB/END SUB, and FOR/NEXT blocks must be balanced
- **How to Verify:**
  - Search artifacts/04-scripts/*.qvs for IF statements, SUB declarations, FOR loops
  - Count occurrences of opening vs closing keywords:
    - IF/THEN count vs END IF count (must equal)
    - SUB count vs END SUB count (must equal)
    - FOR/FOR EACH count vs NEXT count (must equal)
  - Special pattern: `IF NOT IsNull(FileTime(...))` must have matching `END IF`
  - Use editor find/replace to verify counts (Ctrl+H in most editors: search IF, count results; search END IF, count results)
- **Finding Format:** `[S-1.4]: Unbalanced [block type] blocks / Severity: Critical / Category: Script Syntax / Location: [file] / Finding: Found [n] opening [keyword] but [m] closing [END keyword] / Impact: Script will fail to parse or reload / Recommended Fix: Add missing [END keyword] statements or remove extra [keyword] statements to balance`

### 1.5 NullAsValue Scope

- **Severity:** Critical (if applied to keys/measures), Warning (if scope unclear)
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** NullAsValue is field-specific and stateful, persisting until reset. Must be used carefully.
- **How to Verify:**
  - Search artifacts/04-scripts/*.qvs for `NullAsValue`
  - For each occurrence, determine scope:
    - If scoped to single LOAD, verify `NullAsNull *` and `SET NullValue=;` reset immediately after
    - If scoped to persist, verify it's intentional and documented
  - Field names in `NullAsValue` must match output aliases (not source names). Cross-check against SELECT clause.
  - Flag any use of NullAsValue on key fields (breaks associations) or measure fields for Sum/Avg (converts NULL to string, breaking aggregation)
- **Finding Format:** `[S-1.5]: NullAsValue scope or target issue / Severity: [Critical | Warning] / Category: Script Syntax / Location: [file]:[line] / Finding: NullAsValue [fields] applied without proper reset OR targeting key/measure fields OR field names don't match output aliases / Impact: [Breaks associations | Destroys aggregation accuracy | Persists unintentionally to downstream LOADs] / Recommended Fix: [Add NullAsNull reset | Remove from key/measure fields | Correct field names to match output aliases]`

### 1.6 RENAME FIELD Collision

- **Severity:** Critical
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** RENAME FIELD [X] TO [Y] fails if [Y] already exists in the data model
- **How to Verify:**
  - Search artifacts/04-scripts/*.qvs for `RENAME FIELD`
  - For each RENAME statement, verify target field [Y] does not already exist in any table currently loaded
  - Search for multiple RENAME statements targeting the same destination (collision)
  - If multiple sources need same target name, verify each LOAD assigns target name directly instead of using RENAME after
- **Finding Format:** `[S-1.6]: RENAME FIELD collision / Severity: Critical / Category: Script Syntax / Location: [file]:[line] / Finding: RENAME FIELD [X] TO [Y] attempted but [Y] already exists in [table names] / Impact: Script reload will fail with collision error / Recommended Fix: Assign target name directly in SELECT/LOAD as [X] AS [Y] instead of using RENAME after fact, or resolve field name conflicts`

---

## 2. Performance (3 items)

Validates efficient resource usage, avoiding redundant operations and temporary table cleanup.

**Applicable Review Passes:** Phase 4, Phase 7

### 2.1 Redundant Disk Reads

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** QVD files should not be loaded from disk more than once (efficiency)
- **How to Verify:**
  - Search artifacts/04-scripts/*.qvs for all `LOAD ... FROM *.qvd`
  - For each .qvd file found, count occurrences of that filename
  - If count > 1, flag as redundant read
  - Acceptable pattern: load to temp resident, create multiple mapping tables from temp, then DROP temp
  - Note acceptable pattern when flagging to avoid false positive
- **Finding Format:** `[P-2.1]: Redundant disk read / Severity: Warning / Category: Performance / Location: [file]:[line numbers] / Finding: [filename].qvd loaded [n] times from disk / Impact: Unnecessary I/O overhead, slower reload / Recommended Fix: Load once to temp table, create multiple mapping tables or derivatives from temp, drop temp after use`

### 2.2 Repeated Expressions

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Identical complex expressions appearing multiple times in same LOAD (inefficient)
- **How to Verify:**
  - Search artifacts/04-scripts/*.qvs for complex expressions (nested IF, arithmetic combinations, function chains > 2 levels)
  - Identify expressions that appear 2+ times in the same SELECT/LOAD
  - Simple expressions (single function call, single field reference) are acceptable to repeat
- **Finding Format:** `[P-2.2]: Repeated complex expression / Severity: Warning / Category: Performance / Location: [file]:[line numbers] / Finding: Expression [expression text] appears [n] times in same LOAD / Impact: Redundant calculation, slower reload, harder to maintain / Recommended Fix: Use preceding LOAD to calculate once, reference result in outer LOAD`

### 2.3 Temp Table Cleanup

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Every temp table (prefixed `_`) must have corresponding DROP; MAPPING tables auto-drop
- **How to Verify:**
  - Search artifacts/04-scripts/*.qvs for table creates: `[_tablename]` or `_tablename`
  - For each temp table created (name starts with `_`), search for `DROP TABLE _tablename`
  - If not found, flag as missing DROP
  - Exception: Tables created via `MAPPING LOAD` are auto-dropped, do not manually drop
- **Finding Format:** `[P-2.3]: Missing temp table cleanup / Severity: Warning / Category: Performance / Location: [file] / Finding: Temp table [_tablename] created at [line] but no DROP TABLE found / Impact: Unnecessary memory usage, slower reload / Recommended Fix: Add DROP TABLE [_tablename] after all uses of temp table`

---

## 3. Data Model Integrity (8 items)

Validates data model structure, key relationships, synthetic key prevention, null handling, and grain alignment.

**Applicable Review Passes:** Phase 3, Phase 4, Phase 7

### 3.1 Synthetic Key Risk

- **Severity:** Critical
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Non-key fields appearing in multiple output tables create synthetic keys
- **How to Verify:**
  - After script execution (Phase 4), load app in Qlik Sense, open Data Model Viewer
  - Check for synthetic keys (fields named "$" or starting with "synthetic")
  - Search artifacts/04-scripts/*.qvs for field names that appear in multiple LOADs (e.g., source_system, load_datetime, Status, Code)
  - If field is not intended as join key, drop before storing in QVDs
  - Search for phantom fields from shared subroutines: verify subroutine output contains ONLY expected fields
  - Check that column parameter in subroutines is not a wildcard or improperly specified
- **Finding Format:** `[D-3.1]: Synthetic key risk / Severity: Critical / Category: Data Model Integrity / Location: [Data Model Viewer | file]:[line] / Finding: Field [fieldname] appears in [table1], [table2], [table3] but is not a key field, OR phantom field [fieldname] from subroutine output / Impact: Unintended associations created, memory bloat, slow query performance, incorrect analytical results / Recommended Fix: [Drop field before storing QVD | Correct subroutine column parameter | Add EXCEPT clause to exclude]`

### 3.2 Association Integrity

- **Severity:** Critical
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Bridge tables and key fields must have correct association structure
- **How to Verify:**
  - Identify bridge tables (one-to-many relationships)
  - Verify "No Entry" rows are present when parent entity must remain visible during bridge dimension selection
  - Verify all key fields used for association are NOT aliased or prefixed — they must match exactly across tables
  - Check association arrows in Data Model Viewer point in correct directions (many to one)
- **Finding Format:** `[D-3.2]: Association integrity issue / Severity: Critical / Category: Data Model Integrity / Location: [Data Model Viewer | file]:[line] / Finding: [Bridge table missing No Entry rows | Key field [keyname] aliased/prefixed inconsistently across tables | Association direction incorrect] / Impact: Parent entity disappears when selecting bridge dimension OR unintended associations formed / Recommended Fix: [Add No Entry rows | Ensure key field names match exactly | Correct association direction]`

### 3.3 Auto-Concatenation Traps

- **Severity:** Critical
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** When LOAD produces same field names as existing table, Qlik silently concatenates (new table name never registered)
- **How to Verify:**
  - Search artifacts/04-scripts/*.qvs for LOADs of temp tables whose fields might overlap with existing tables
  - If overlap detected and table is not intended to be concatenated, verify `NoConcatenate` keyword is present
  - After execution, check script completion messages for unexpected table concatenations
  - Note: aliased EXISTS pattern (`key AS _alias_name`) avoids this naturally
- **Finding Format:** `[D-3.3]: Auto-concatenation trap / Severity: Critical / Category: Data Model Integrity / Location: [file]:[line] / Finding: LOAD of [tablename] produces field names [field1, field2, ...] that match existing table [existing_tablename], no NoConcatenate / Impact: New table not registered, data silently concatenated, data model structure violated / Recommended Fix: Add NoConcatenate before LOAD, or rename fields to differentiate`

### 3.4 QUALIFY/UNQUALIFY Interaction with Prefixed Fields

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** If upstream fields already prefixed (e.g., Order.Status), QUALIFY * will double-prefix
- **How to Verify:**
  - Search artifacts/04-scripts/*.qvs for `QUALIFY` statements
  - Search upstream artifacts (Phase 2 source profile, Phase 3 data model spec) for evidence of entity-prefixed field names
  - If prefixed fields detected, verify QUALIFY is NOT applied OR if QUALIFY is applied, verify double-prefix is intentional
  - Check for documentation explaining why QUALIFY was omitted (if applicable)
- **Finding Format:** `[D-3.4]: QUALIFY/UNQUALIFY interaction issue / Severity: Warning / Category: Data Model Integrity / Location: [file]:[line] / Finding: [QUALIFY * applied to already-prefixed fields creating double-prefix | QUALIFY omitted, should be documented] / Impact: Field naming inconsistency, harder to manage, potential synthetic keys / Recommended Fix: [Remove QUALIFY if fields already prefixed, OR explicitly UNQUALIFY prefixed fields before QUALIFY * | Add comment documenting why QUALIFY omitted]`

### 3.5 Null Handling Gaps

- **Severity:** Warning (Critical if on key/measure fields)
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Null handling must be explicit and consistent
- **How to Verify:**
  - Search artifacts/04-scripts/*.qvs for date arithmetic (e.g., `today() - DateField`)
  - Flag any date arithmetic without null guard (produces large negative numbers, not NULL)
  - Search for fields that may contain literal `null`, `NaN`, `[null]` strings (IsNull() will NOT catch these)
  - Verify boolean Dual conversion handles NULL: `Dual('Unknown', -1)` not just `Dual('True', 1)`, `Dual('False', 0)`
- **Finding Format:** `[D-3.5]: Null handling gap / Severity: [Warning | Critical] / Category: Data Model Integrity / Location: [file]:[line] / Finding: [Date arithmetic without null guard | String field with literal 'null' strings not handled | Boolean without Unknown state] / Impact: [Large negative numbers in date fields | Null values invisible in UI | Boolean field missing Unknown state] / Recommended Fix: [Wrap date arithmetic in IF IsNull(..., NULL, today() - DateField) | Add UPPER() or conditional to catch string nulls | Add Dual('Unknown', -1) to boolean expression]`

### 3.6 Grain Alignment

- **Severity:** Warning (Critical if unaligned grains cause cartesian products)
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Fact tables at different grains must be explicitly handled
- **How to Verify:**
  - Identify all fact tables (typically large measure-containing tables)
  - Determine grain of each (e.g., transaction-level, daily summary, monthly aggregate)
  - If different grains detected, verify they are joined through compatible dimension keys
  - Check for cartesian products by looking for unexpected row count increases
  - Verify aggregation functions account for different grains (e.g., SUM on daily summary should not double-count)
- **Finding Format:** `[D-3.6]: Grain alignment issue / Severity: [Warning | Critical] / Category: Data Model Integrity / Location: [file]:[line] / Finding: Fact table [table1] at [grain1] and [table2] at [grain2] joined through [dimension], may cause cartesian expansion / Impact: Incorrect row counts, inflated measures, slow query performance / Recommended Fix: [Use bridge table to manage grain difference | Aggregate to common grain | Document expected behavior]`

### 3.7 Circular Reference Detection

- **Severity:** Critical
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Tables should not have circular join paths
- **How to Verify:**
  - After execution, examine Data Model Viewer for circular references
  - Trace association paths: if path from TableA → TableB → TableC → TableA exists, circular reference detected
  - Check script for unintended concatenations that might create cycles
- **Finding Format:** `[D-3.7]: Circular reference detected / Severity: Critical / Category: Data Model Integrity / Location: [Data Model Viewer] / Finding: Circular association path [TableA] → [TableB] → [TableC] → [TableA] / Impact: Infinite association loops, incorrect selection behavior, app instability / Recommended Fix: [Remove one association | Use bridge table | Restructure key relationships]`

### 3.8 Key Resolution Consistency

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Key fields used across multiple tables must be resolved consistently
- **How to Verify:**
  - Identify all key fields in data model (% prefix or _key suffix per naming conventions)
  - Verify each key field has single, consistent definition across all tables (same data type, same values)
  - Check for cases where same logical key appears with different names in different tables (field name inconsistency)
  - Verify no key field is modified by expressions (e.g., UPPER, TRIM) inconsistently between tables
- **Finding Format:** `[D-3.8]: Key resolution inconsistency / Severity: Warning / Category: Data Model Integrity / Location: [file]:[line] / Finding: Key field [keyname] defined inconsistently: [table1] as [type1], [table2] as [type2] OR key values transformed inconsistently (UPPER in [table1], raw in [table2]) / Impact: Failed associations, missing records, incorrect analytics / Recommended Fix: Standardize key field definition and transformation consistently across all tables`

---

## 4. Naming Convention Compliance (5 items)

Validates field naming, table naming, variable naming, and consistency across layers.

**Applicable Review Passes:** Phase 3, Phase 4, Phase 5, Phase 7

### 4.1 Entity-Prefix Dot Notation for Non-Key Fields

- **Severity:** Warning
- **Applicable Passes:** Phase 3, Phase 4, Phase 5, Phase 7
- **What to Check:** Non-key fields should use entity-prefix dot notation (e.g., [Customer.Name], [Order.Total])
- **How to Verify:**
  - Load artifacts/01-project-specification.md and artifacts/03-data-model-specification.md for naming conventions
  - Examine all non-key field names in final data model
  - Fields should follow pattern `[Entity].[FieldName]` (PascalCase for both parts)
  - Exception: fields that are keys (% prefix or _key suffix) or standard platform fields don't require dot notation
  - Search artifacts/04-scripts/*.qvs for any field assignments that violate this pattern
- **Finding Format:** `[N-4.1]: Field naming convention violation / Severity: Warning / Category: Naming Convention Compliance / Location: [file]:[line] OR [Data Model Viewer] / Finding: Field [fieldname] does not follow entity-prefix dot notation / Impact: Inconsistent naming makes model harder to navigate, violates platform standards / Recommended Fix: Rename [fieldname] to [Entity].[FieldName] using entity-prefix dot notation`

### 4.2 Key Field Conventions

- **Severity:** Warning
- **Applicable Passes:** Phase 3, Phase 4, Phase 5, Phase 7
- **What to Check:** Key fields must use % prefix OR _key suffix
- **How to Verify:**
  - Identify all key fields in data model (fields used in joins/associations)
  - Verify each key field name starts with `%` (e.g., %CustomerID) OR ends with `_key` (e.g., customer_key)
  - Check consistency: if some keys use %, all should use %; if some use _key, all should use _key
  - Exception: bridge table keys, special platform keys may have project-specific conventions (verify in spec)
- **Finding Format:** `[N-4.2]: Key field naming convention violation / Severity: Warning / Category: Naming Convention Compliance / Location: [Data Model Viewer] / Finding: Key field [keyname] does not use % prefix or _key suffix / Impact: Key fields not immediately identifiable, harder to understand associations / Recommended Fix: Rename to [%keyname] or [keyname_key] to match convention`

### 4.3 Variable Naming

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 5, Phase 7
- **What to Check:** Variables should use v prefix (e.g., vToday, vMaxDate)
- **How to Verify:**
  - Search artifacts/04-scripts/*.qvs and artifacts/05-expression-variables.qvs for all variable declarations (SET, LET)
  - Verify each variable name starts with `v` (e.g., vToday, vMaxDate, vAppVersion)
  - Exception: system variables (like $0, $1) or legacy variables documented in spec may be exempt
- **Finding Format:** `[N-4.3]: Variable naming convention violation / Severity: Warning / Category: Naming Convention Compliance / Location: [file]:[line] / Finding: Variable [varname] does not use v prefix / Impact: Variables not immediately identifiable, harder to distinguish from fields / Recommended Fix: Rename to [v + varname], e.g., [v + VarName]`

### 4.4 Table Naming Conventions

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Table names should follow consistent pattern per project specification
- **How to Verify:**
  - Load artifacts/01-project-specification.md and artifacts/03-data-model-specification.md for table naming rules
  - Examine all table names in data model and scripts
  - Typical conventions: PascalCase (Customer, Order, OrderLine) or lowercase_snake_case, with temp tables prefixed `_`
  - Verify consistency across all tables
  - Mapping tables should be clearly labeled (e.g., MapCustomerType) or use standard naming
- **Finding Format:** `[N-4.4]: Table naming inconsistency / Severity: Warning / Category: Naming Convention Compliance / Location: [file] OR [Data Model Viewer] / Finding: Table [tablename] does not follow project naming convention [expected pattern] / Impact: Model harder to understand, inconsistent structure / Recommended Fix: Rename table to follow convention, e.g., [corrected_name]`

### 4.5 Cross-Layer Naming Consistency

- **Severity:** Warning
- **Applicable Passes:** Phase 3, Phase 4, Phase 5, Phase 7
- **What to Check:** Field names should remain consistent across source → extract → transform → model → UI layers
- **How to Verify:**
  - Compare field names in: Phase 2 source profile, Phase 4 scripts, Phase 3 data model, Phase 6 viz specs, Phase 5 expressions
  - Track field name changes through each layer (aliasing is okay if documented, but unnecessary aliasing is not)
  - Ensure UI-facing field names (in expressions, viz specs) match final data model
  - Flag unexplained renamings that could confuse developers
- **Finding Format:** `[N-4.5]: Cross-layer naming inconsistency / Severity: Warning / Category: Naming Convention Compliance / Location: [source layer vs model layer] / Finding: Field [original_name] renamed to [new_name] at [layer transition point], inconsistently renamed elsewhere / Impact: Developers confused about field identity, hard to trace source-to-viz lineage / Recommended Fix: [Establish consistent renaming strategy and apply uniformly | Document why renaming necessary at this layer]`

---

## 5. Expression Correctness (6 items)

Validates expression syntax, null handling, field references, and calculation conditions.

**Applicable Review Passes:** Phase 5, Phase 7

### 5.1 Set Analysis Syntax Validation

- **Severity:** Critical
- **Applicable Passes:** Phase 5, Phase 7
- **What to Check:** Set analysis syntax must be valid
- **How to Verify:**
  - Load artifacts/05-expression-catalog.md and artifacts/05-expression-variables.qvs
  - For each expression containing set analysis (curly braces `{}`), verify syntax:
    - Modifiers: `<Field = {value}>`, `<Field = {>10}>` syntax correct
    - Wildcard `{*}`: selects all NON-NULL values. `<Field={*}>` excludes nulls for that field. Do NOT confuse with `<Field=>` which ignores selections (includes nulls).
    - Empty modifier `<Field=>`: clears/ignores user selections on that field. Does NOT exclude nulls. This is fundamentally different from `{*}`.
    - Operators: `{1,2}` (OR), `{1}-{2}` (difference), `{1}*{2}` (intersection)
    - Dollar-sign expansion: `<Field = {$(varname)}>` (verify varname is simple)
    - Nested set analysis not supported; use outer set only
  - Check for typos in field names (case-sensitive)
  - Verify set analysis is applied to correct aggregation function
- **Finding Format:** `[E-5.1]: Set analysis syntax error / Severity: Critical / Category: Expression Correctness / Location: [artifact]:[line] / Finding: Set analysis [set_expression] has invalid syntax: [error detail] / Impact: Expression will fail to evaluate or return incorrect results / Recommended Fix: Correct syntax to [corrected_expression]`

### 5.2 TOTAL Qualifier Usage

- **Severity:** Warning
- **Applicable Passes:** Phase 5, Phase 7
- **What to Check:** TOTAL qualifier must not be confused with set analysis
- **How to Verify:**
  - Search artifacts/05-expression-catalog.md for TOTAL keyword
  - Verify TOTAL is used correctly: `Sum(TOTAL Measure)` removes current dimension filtering
  - Flag invalid TOTAL placement: `Sum(TOTAL <field={value}> Measure)` is invalid because TOTAL cannot contain set modifiers. However, `Sum({<field={value}>} TOTAL Measure)` IS valid — set analysis first, then TOTAL qualifier. Do not confuse these two patterns.
  - Watch for TOTAL parsing ambiguity: `Sum({<...>}Total Field)` — Qlik parses `Total` as the TOTAL qualifier keyword (case-insensitive), NOT as part of a field name "Total Field." If a field is genuinely named "Total Something," it must be in square brackets: `[Total Something]`.
  - Verify TOTAL is only used when totaling across ALL dimension context is intended
  - Check expressions for cases where set analysis `{...}` should be used instead of TOTAL
- **Severity Escalation:** Escalate to **Critical** when TOTAL is placed inside set analysis braces (e.g., `Sum({TOTAL <Year={2024}>} Sales)`). This is structurally invalid. TOTAL must be outside the braces: `Sum({<Year={2024}>} TOTAL Sales)` or `Sum(TOTAL {<Year={2024}>} Sales)`.
- **Finding Format:** `[E-5.2]: TOTAL qualifier misuse / Severity: Warning / Category: Expression Correctness / Location: [artifact]:[line] / Finding: [Expression using TOTAL appears to intend set analysis | TOTAL used but alternative clearer] / Impact: [Incorrect totaling behavior | Hard to understand intent] / Recommended Fix: [Replace with set analysis {value} OR clarify why TOTAL necessary]`

### 5.7 Structurally Invalid Aggregation

- **Severity:** Critical
- **Applicable Passes:** Phase 5, Phase 7
- **What to Check:** Aggregation functions must not be directly nested. The engine cannot resolve two aggregation scopes simultaneously.
- **How to Verify:**
  - Search for patterns like `Avg(Sum(...))`, `Sum(Count(...))`, `Max(Sum(...))`, etc.
  - Check dollar-sign expansion: if a variable contains an aggregation (e.g., `SET vSales = Sum(Sales)`), using `$(vSales)` inside another aggregation expands to an invalid nested form at render time.
  - The only valid nesting pattern is via `Aggr()`: e.g., `Avg(Aggr(Sum(Sales), Customer))`.
- **Finding Format:** `[E-5.7]: Nested aggregation without Aggr() / Severity: Critical / Category: Expression Correctness / Location: [artifact]:[line] / Finding: [expression] directly nests aggregation functions / Impact: Structurally invalid — guaranteed incorrect results / Recommended Fix: Use Aggr() as intermediate step or restructure calculation`

### 5.3 Null Handling in Expressions

- **Severity:** Critical (if on key measure), Warning (if UI measure)
- **Applicable Passes:** Phase 5, Phase 7
- **What to Check:** Every aggregation expression must handle nulls appropriately
- **How to Verify:**
  - For each measure in artifacts/05-expression-catalog.md, verify null handling:
    - `Sum(Measure)` — nulls ignored (acceptable for sums)
    - `Avg(Measure)` — nulls ignored; if null rates high, consider noting
    - `Count(Measure)` — counts non-nulls only (acceptable)
    - `Count(*)` — counts all rows (use when null rate matters)
    - `Null()` — flag any expressions that intentionally return null without documentation
  - Verify ZERO() is used if 0 is intended for null/missing values (not NULL)
  - Check for division by zero (e.g., `Sum(A) / Sum(B)` when B might be zero)
- **Finding Format:** `[E-5.3]: Null handling gap in expression / Severity: [Critical | Warning] / Category: Expression Correctness / Location: [artifact]:[line] / Finding: [Aggregation function without null guard | Division by zero risk | NULL returned without justification] / Impact: [Nulls cause silent errors | Division by zero crashes expression | Unexpected blanks in UI] / Recommended Fix: [Add IF condition for null check | Use IF(Sum(B)=0, 0, Sum(A)/Sum(B)) for safe division | Document NULL return]`

### 5.4 Field References Match Data Model

- **Severity:** Critical
- **Applicable Passes:** Phase 5, Phase 7
- **What to Check:** All field references in expressions must exist in final data model
- **How to Verify:**
  - For each field reference in artifacts/05-expression-catalog.md, verify it exists in Phase 3 data model spec and Phase 4 final data model
  - Use Data Model Viewer (Phase 4 output) to confirm field presence
  - Verify field name casing matches (case-sensitive in Qlik expressions)
  - Flag references to intermediate layer fields (Phase 4 temp tables) that are not present in final model
  - Check for references to fields in upstream artifacts that were dropped during transformation
- **Finding Format:** `[E-5.4]: Field reference to non-existent field / Severity: Critical / Category: Expression Correctness / Location: [artifact]:[line] / Finding: Expression references [fieldname] which does not exist in data model / Impact: Expression will fail to evaluate, measure will show error / Recommended Fix: [Correct field name to match data model | Add field to data model via script modification]`

### 5.5 Dollar-Sign Expansion in SET Variables (Comma Rule)

- **Severity:** Critical
- **Applicable Passes:** Phase 5, Phase 7
- **What to Check:** SET variables containing dollar-sign expansion with embedded commas
- **How to Verify:**
  - Load artifacts/05-expression-variables.qvs
  - For each SET variable (not LET) containing `$()`, verify the variable expansion argument does NOT contain commas
  - Flag patterns like: `SET vVar = Sum($(variable(field1, field2)))` — invalid
  - Correct pattern: `SET vVar = Sum($(variable(field)))` — simple argument only
  - If variable expansion needs to produce comma-separated output (rare), must use LET + quote escaping, not SET
- **Finding Format:** `[E-5.5]: Comma in dollar-sign expansion within SET variable / Severity: Critical / Category: Expression Correctness / Location: [artifact]:[line] / Finding: SET variable [varname] contains $(variable(...)) with comma-containing argument [arg_detail] / Impact: Variable expansion will fail, expression will not evaluate / Recommended Fix: Extract nested function to separate variable or rewrite without variable expansion`

### 5.6 Calculation Condition Completeness

- **Severity:** Warning
- **Applicable Passes:** Phase 5, Phase 7
- **What to Check:** Master items or expressions with calculation conditions must have corresponding error messages
- **How to Verify:**
  - Search artifacts/05-expression-catalog.md for calculation conditions (IF statements used to suppress blank/zero display)
  - For each condition, verify paired message or default behavior is documented
  - Flag orphaned conditions (condition present but no user-facing message documenting what triggers suppression)
  - Verify calculation condition does not suppress legitimate zero results unintentionally
- **Finding Format:** `[E-5.6]: Incomplete calculation condition / Severity: Warning / Category: Expression Correctness / Location: [artifact]:[line] / Finding: Calculation condition [condition] defined but no corresponding message OR condition may suppress legitimate zero / Impact: [Users don't understand why measure is blank | Legitimate data hidden] / Recommended Fix: [Add message paired with condition | Review condition logic to ensure only invalid/missing data suppressed]`

---

## 6. Security (5 items)

Validates PII handling, Section Access correctness, and data access control.

**Applicable Review Passes:** Phase 4, Phase 7

### 6.1 PII Field Exposure

- **Severity:** Critical
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** PII fields (SSN, national ID, financial account, email, phone, address) should not be loaded without explicit justification
- **How to Verify:**
  - Scan artifacts/02-source-profile.md for identified PII fields
  - Check artifacts/04-scripts/*.qvs for any LOAD of PII fields into QVDs or final model
  - If PII loaded, verify artifacts/01-project-specification.md includes justification and data governance/retention policy
  - If no justification, flag for removal or row-level filtering via Section Access
  - Check for accidental PII in field names or metadata
- **Finding Format:** `[SC-6.1]: PII exposure without justification / Severity: Critical / Category: Security / Location: [file]:[line] / Finding: PII field [fieldname] (e.g., [SSN | email | phone]) loaded into [table] without documented justification / Impact: Compliance violation, data breach risk, regulatory exposure / Recommended Fix: [Remove PII field OR add Section Access row-level filtering OR document business justification and retention policy]`

### 6.2 Section Access STAR Field Handling

- **Severity:** Critical
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** If Section Access is present, STAR field must be handled correctly
- **How to Verify:**
  - If Section Access table exists, verify it is loaded
  - Check for STAR field in Section Access table (STAR indicates full access)
  - Verify STAR values are present for roles requiring full access
  - Verify row-level filters (reduction fields) are properly mapped to data model fields
- **Finding Format:** `[SC-6.2]: Section Access STAR field issue / Severity: Critical / Category: Security / Location: [artifacts/04-scripts/section-access.qvs] / Finding: [STAR field missing from Section Access table | STAR field values incorrect | Reduction fields not properly mapped] / Impact: Section Access will not function correctly, data visibility not restricted as intended / Recommended Fix: [Add STAR field to Section Access | Correct STAR values | Map reduction fields to data model fields]`

### 6.3 Reduction Field Case-Sensitivity Match

- **Severity:** Critical
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Section Access reduction field names must match data model field names exactly (case-sensitive)
- **How to Verify:**
  - If Section Access present, load Section Access table and final data model
  - For each reduction field in Section Access, verify exact case-sensitive match in data model
  - Example: `customer_key` in Section Access must match `customer_key` in model (not `Customer_Key` or `CUSTOMER_KEY`)
  - Use Data Model Viewer to confirm exact field names
- **Finding Format:** `[SC-6.3]: Section Access reduction field case mismatch / Severity: Critical / Category: Security / Location: [Section Access table] / Finding: Reduction field [field_in_section_access] does not case-sensitively match [corresponding_model_field] / Impact: Section Access filtering will fail, users may see restricted data / Recommended Fix: Correct Section Access field name to [corrected_name] with exact case match`

### 6.4 Section Access Table Completeness

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Section Access should cover all users/roles that need filtering
- **How to Verify:**
  - If Section Access present, verify it is complete for all security domains
  - Check that no user/role is left unfiltered (orphaned users)
  - Verify all reduction fields used in data are present in Section Access
  - Check for placeholder or hardcoded test access entries that should be replaced with production rules
- **Finding Format:** `[SC-6.4]: Section Access incomplete / Severity: Warning / Category: Security / Location: [artifacts/04-scripts/section-access.qvs] / Finding: [User/role missing from Section Access | Reduction field used in data but not in Section Access | Test/placeholder entries present] / Impact: [Some users lack access rules | Filtering inconsistent | Test data in production] / Recommended Fix: [Add missing access rules | Add reduction field to Section Access | Remove test entries and replace with production data]`

### 6.5 OMIT Field Correctness

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** If OMIT field used in Section Access, verify it is correctly applied
- **How to Verify:**
  - Search Section Access table for OMIT field values
  - Verify OMIT values exclude only rows that should be hidden (e.g., test regions, confidential dimensions)
  - Check that OMIT does not accidentally hide legitimate data
  - Verify OMIT is used only when exclusion is simpler than inclusion (prefer inclusion/positive filtering)
- **Finding Format:** `[SC-6.5]: OMIT field issue / Severity: Warning / Category: Security / Location: [artifacts/04-scripts/section-access.qvs] / Finding: OMIT field [field] values exclude [value], unclear if intentional OR OMIT used instead of explicit inclusion list / Impact: [Unintended data hidden | Security model unclear] / Recommended Fix: [Verify OMIT values are intentional | Consider replacing with explicit inclusion list for clarity]`

---

## 7. Cross-Artifact Consistency (4 items)

Validates alignment across multiple pipeline phases and artifacts.

**Applicable Review Passes:** Phase 3, Phase 4, Phase 5, Phase 6, Phase 7

### 7.1 Expressions Reference Existing Fields

- **Severity:** Critical
- **Applicable Passes:** Phase 5, Phase 7
- **What to Check:** Every field referenced in expressions must exist in final data model
- **How to Verify:**
  - Load artifacts/05-expression-catalog.md and final data model from Phase 4
  - For each field reference in every expression, search data model for exact match
  - Flag fields that exist in intermediate scripts but were dropped before final model
  - Check for typos in field names (case-sensitive)
- **Finding Format:** `[C-7.1]: Expression references non-existent field / Severity: Critical / Category: Cross-Artifact Consistency / Location: [expression catalog]:[expression ID] / Finding: Expression references [fieldname] which does not exist in final data model / Impact: Expression will fail when user interacts with measure / Recommended Fix: [Update expression to use correct field name | Restore field to data model]`

### 7.2 Viz Specs Reference Existing Expressions

- **Severity:** Critical
- **Applicable Passes:** Phase 6, Phase 7
- **What to Check:** Every expression referenced in viz specs must exist in expression catalog
- **How to Verify:**
  - Load artifacts/06-viz-specifications.md and artifacts/05-expression-catalog.md
  - For each sheet, object, measure in viz specs, verify referenced expression exists in catalog
  - Search for expression IDs or names and confirm they are defined
  - Flag references to expressions that exist in scripts but not in final catalog
- **Finding Format:** `[C-7.2]: Viz spec references non-existent expression / Severity: Critical / Category: Cross-Artifact Consistency / Location: [viz spec]:[sheet/object] / Finding: Viz [object] references expression [expr_id], not found in expression catalog / Impact: Viz will fail to load or show blank/error state / Recommended Fix: [Add missing expression to catalog | Update viz reference to existing expression ID]`

### 7.3 Scripts Use Correct Platform Subroutines

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** All subroutine calls in scripts should reference subroutines defined in platform libraries
- **How to Verify:**
  - Load artifacts/00-platform-context.md (lists available platform subroutines)
  - Search artifacts/04-scripts/*.qvs for SUB calls and CALL statements
  - For each subroutine invoked, verify it is defined in platform context
  - Check subroutine parameter count and types match definition
  - Flag references to subroutines that are not in platform libraries
- **Finding Format:** `[C-7.3]: Subroutine reference issue / Severity: Warning / Category: Cross-Artifact Consistency / Location: [file]:[line] / Finding: Script calls subroutine [subroutine_name] not found in platform subroutines / Impact: Script will fail to execute subroutine call / Recommended Fix: [Verify subroutine name spelling | Ensure platform library is included | Define custom subroutine if needed]`

### 7.4 Field Names Consistent Across All Artifacts

- **Severity:** Warning
- **Applicable Passes:** Phase 3, Phase 4, Phase 5, Phase 6, Phase 7
- **What to Check:** Field names should be consistent across data model spec, scripts, expressions, and viz specs
- **How to Verify:**
  - Compare field names in: Phase 3 data model spec, Phase 4 final data model, Phase 5 expressions, Phase 6 viz specs
  - Track field name through each layer
  - Flag unexplained inconsistencies (aliasing is okay if documented)
  - Ensure UI-facing field names are consistent with what developers expect
- **Finding Format:** `[C-7.4]: Field name inconsistency across artifacts / Severity: Warning / Category: Cross-Artifact Consistency / Location: [phase X] vs [phase Y] / Finding: Field [name_in_phase_x] referred to as [name_in_phase_y] in [phase Y], inconsistent naming / Impact: Developers confused about field identity, hard to trace changes / Recommended Fix: Standardize field name to single version across all artifacts`

---

## 8. Blocked Dependency Audit (3 items)

Validates dependency tracking and placeholder documentation per pipeline state.

**Applicable Review Passes:** Phase 4, Phase 7

### 8.1 Placeholder Implementation Documentation

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Any placeholder implementations (for blocked dependencies) must be documented with TRACE warnings
- **How to Verify:**
  - Load .pipeline-state.json and check `blockedDependencies` list
  - For each blocked dependency, search artifacts/04-scripts/*.qvs for placeholder implementations
  - Verify each placeholder has TRACE statement with explanation: `TRACE Placeholder: [dependency name] — [why blocked] — [expected behavior when resolved]`
  - Check that placeholder is marked with comment flag for easy identification
- **Finding Format:** `[BD-8.1]: Missing placeholder documentation / Severity: Warning / Category: Blocked Dependency Audit / Location: [file]:[line] / Finding: Placeholder implementation for [dependency] has no TRACE warning or documentation / Impact: Developers won't know placeholder is temporary, may commit incomplete solution / Recommended Fix: Add TRACE statement documenting placeholder and expected resolution`

### 8.2 Downstream Artifacts Flag Dependency on Placeholders

- **Severity:** Warning
- **Applicable Passes:** Phase 5, Phase 7
- **What to Check:** Any artifact downstream of a blocked dependency must be flagged as dependent on placeholder
- **How to Verify:**
  - Load .pipeline-state.json and identify blocked dependencies and their `downstreamImpacts`
  - For each downstream artifact, search for documentation or status comment indicating dependency on placeholder
  - Check that artifact status is marked as "draft-unvalidated" or "pending-dependency-resolution"
  - Verify artifact comment includes: "Depends on placeholder for [dependency], will need regeneration when [dependency] resolves"
- **Finding Format:** `[BD-8.2]: Downstream artifact missing dependency flag / Severity: Warning / Category: Blocked Dependency Audit / Location: [artifact] / Finding: Artifact depends on placeholder for [dependency] but does not flag dependency status / Impact: Developers may use incomplete artifact without knowing placeholder exists / Recommended Fix: Add comment to artifact documenting placeholder dependency and need for regeneration`

### 8.3 .pipeline-state.json Alignment with Artifacts

- **Severity:** Warning
- **Applicable Passes:** Phase 7
- **What to Check:** .pipeline-state.json should accurately reflect status of all artifacts and dependencies
- **How to Verify:**
  - Load .pipeline-state.json
  - For each artifact entry, verify status (draft/reviewed/approved/validated) matches actual artifact state
  - Check `blockedDependencies` list against actual placeholder implementations in scripts
  - Verify `executionValidation.requests` and `executionValidation.results` are synchronized
  - Confirm all completed phases are listed with correct phase numbers
- **Finding Format:** `[BD-8.3]: .pipeline-state.json alignment issue / Severity: Warning / Category: Blocked Dependency Audit / Location: [.pipeline-state.json] / Finding: [Phase status mismatch | Artifact status not matching actual state | Blocked dependency no longer blocked but not removed from list] / Impact: Pipeline state tracking inaccurate, future phases may use stale information / Recommended Fix: [Update .pipeline-state.json to reflect current artifact status and dependency state]`

---

## 9. Data Quality Validation (5 items)

Validates data quality when execution environment available. Requires successful script execution and loaded data.

**Applicable Review Passes:** Phase 4, Phase 7

### 9.1 Null Rate Analysis on Key Fields

- **Severity:** Critical (if nulls on key), Warning (if high null rate on measure)
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Key fields should have zero nulls; measure fields null rate should be acceptable
- **How to Verify:**
  - After script execution, run diagnostic query to measure null rates per field
  - For key fields (% prefix, _key suffix): flag if any nulls detected
  - For dimension fields: flag if null rate > 5% (configurable per spec)
  - For measure fields: note high null rates (> 20%) as warning, not critical
  - Use Qlik diagnostic script from artifacts/04-scripts/diagnostics/ if available
- **Finding Format:** `[DQ-9.1]: High null rate on [field type] field / Severity: [Critical | Warning] / Category: Data Quality Validation / Location: [table]:[field] / Finding: [Key field has [n] nulls | Dimension field has [x]% null rate | Measure field has [y]% null rate] / Impact: [Broken associations | Missing dimension values | Unreliable aggregation] / Recommended Fix: [Investigate source data quality | Add default values | Apply IsNull() filter in script]`

### 9.2 Referential Integrity Checks

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Foreign keys in fact tables should have corresponding primary keys in dimension tables
- **How to Verify:**
  - Identify fact and dimension tables
  - For each foreign key in fact table, count rows where key not in corresponding dimension
  - Flag orphaned records (fact rows with no matching dimension)
  - Report percentage of orphaned records (0% is ideal, >5% is warning, >10% is critical)
- **Finding Format:** `[DQ-9.2]: Referential integrity violation / Severity: [Warning | Critical] / Category: Data Quality Validation / Location: [fact table].[foreign_key] / Finding: [n] rows ([x]%) in [fact_table] have [foreign_key] values not in dimension [dimension_table] / Impact: Unlinked records in analytics, missing drill-down paths / Recommended Fix: [Investigate source data quality | Apply referential integrity filter in script | Update dimension to include orphaned keys]`

### 9.3 Value Distribution Analysis

- **Severity:** Suggestion
- **Applicable Passes:** Phase 7
- **What to Check:** Key dimensions should have reasonable value distributions (not all zeros, not single value dominating)
- **How to Verify:**
  - For each dimension field, count distinct values and top-10 value frequencies
  - Flag dimensions with only 1 distinct value (likely unneeded)
  - Flag dimensions where single value represents >95% of rows (likely data quality issue or expected, verify)
  - Check for unexpected text values in numeric dimensions
- **Finding Format:** `[DQ-9.3]: Unexpected value distribution / Severity: Suggestion / Category: Data Quality Validation / Location: [field] / Finding: [Field has only [n] distinct values | Single value [value] represents [x]% of rows | Unexpected values [unexpected_list] in numeric field] / Impact: [Field not useful for analysis | Possible data quality issue] / Recommended Fix: [Investigate source data | Verify field is necessary | Apply data filter or transformation if expected]`

### 9.4 Row Count Validation

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Table row counts should match expectations from source profile and data model spec
- **How to Verify:**
  - Compare final row counts to expected counts from Phase 2 source profile
  - Flag significant deviations (>10% difference) without explanation
  - Check for unexpectedly empty tables (0 rows)
  - Verify temp table cleanup: _ tables should be gone from final model
- **Finding Format:** `[DQ-9.4]: Row count mismatch / Severity: Warning / Category: Data Quality Validation / Location: [table] / Finding: [table] has [actual_count] rows, expected ~[expected_count] from source profile ([variance]% variance) / Impact: [Data completeness uncertain | Possible data load failure] / Recommended Fix: [Verify source data | Check script filters/WHERE clauses | Confirm TRACE output for load details]`

### 9.5 Orphaned Record Detection

- **Severity:** Warning
- **Applicable Passes:** Phase 4, Phase 7
- **What to Check:** Bridge tables and many-to-many relationships should not have unexplained orphaned records
- **How to Verify:**
  - For bridge tables, count records where parent or child key is null/missing
  - Compare to "No Entry" rows documented in data model spec
  - Flag orphaned records (key relationships not explained by "No Entry" pattern or expected design)
  - Verify orphaned records are intentional (e.g., "No Entry" pattern) or documented
- **Finding Format:** `[DQ-9.5]: Orphaned records detected / Severity: Warning / Category: Data Quality Validation / Location: [table] / Finding: Bridge table [bridge_table] has [n] orphaned records (parent/child key missing or unmatched) / Impact: Users may see unlinked data points in analysis / Recommended Fix: [Verify orphaned records are intentional "No Entry" rows | Investigate source data quality | Document orphaned pattern in data model spec]`

---

## Finding Format Reference

All findings, regardless of category, must follow this structure:

```
[ID]: [Title]
- Severity: [Critical | Warning | Suggestion]
- Category: [category_name]
- Location: [artifact_path]:[line number] or [location description]
- Finding: [Detailed description of what is wrong]
- Impact: [What breaks or what negative consequence occurs]
- Recommended Fix: [Specific action to resolve]
```

---

## Review Pass Applicability Summary

| Category | Phase 3 Lightweight | Phase 4 Script | Phase 5 Expressions | Phase 7 Comprehensive |
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
