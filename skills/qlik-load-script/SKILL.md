---
name: qlik-load-script
description: "Script syntax reference, QVD optimization, incremental load patterns (insert-only, insert/update, insert/update/delete, dual-timestamp for SCD2), master calendar generation, variable definitions, error handling, logging patterns, null handling patterns, diagnostic and validation patterns, subroutine integration, and platform gotchas (SET vs LET, dollar-sign expansion timing, SET variable comma limitation). Load when writing, reviewing, or debugging Qlik load scripts, QVD operations, STORE/LOAD syntax, preceding LOAD, NullAsValue, script organization, or data quality defensive coding."
---

# Qlik Load Script

Qlik script resembles SQL but is a fundamentally different language. It runs inside the Qlik associative engine, not a relational database. The most critical rule: **Qlik script is NOT SQL.** The single most predictable failure mode for AI-generated scripts is SQL syntax inside LOAD statements. Before writing any LOAD statement, internalize Section 1 below. Before writing any variable function, internalize Section 3.

This skill covers script mechanics, QVD operations, incremental loads, null handling, error handling, diagnostics, variable patterns, master calendar, and subroutine integration. It does NOT cover naming conventions (see `qlik-naming-conventions`), data model design (see `qlik-data-modeling`), expression syntax (see `qlik-expressions`), or optimization strategies (see `qlik-performance`).

## 1. Script Generation Constraints (CRITICAL)

These SQL constructs do NOT exist in Qlik LOAD statements. Using them causes reload errors or silent failures.

| SQL Syntax | Why It Fails | Qlik Alternative |
|---|---|---|
| `HAVING` | Not a keyword in Qlik script | Preceding LOAD with `WHERE` on aggregated field |
| `Count(*)` | No wildcard aggregation | `Count(field_name)` with explicit field |
| `SELECT DISTINCT` | SELECT is for SQL pass-through only | `LOAD DISTINCT` |
| `IS NULL` / `IS NOT NULL` | Operator syntax not supported | `IsNull(field)` / `NOT IsNull(field)` |
| `BETWEEN` | Not a keyword | `field >= low AND field <= high` |
| `IN (list)` | Not supported | `Match(field, v1, v2)` or `WildMatch()` |
| `CASE WHEN` | Not a keyword | `IF()`, `Pick()`, or `Match()` |
| `LIMIT` | Not a keyword | `WHERE RowNo() <= N` on RESIDENT |
| Table aliases (`FROM t1`) | Not supported in LOAD | Full table names in brackets |

**Exception:** `SQL SELECT` pass-through statements to database connections CAN use native SQL syntax including all of the above. The constraint applies only to LOAD/RESIDENT operations.

### Dollar-Sign Expansion Safety

Every `$(variable(...))` call must be checked for commas in arguments. Inside `$()`, commas separate parameters, not expression arguments. Nesting a function with commas breaks parameter parsing.

```qlik
// WRONG -- ApplyMap's commas parsed as $1/$2/$3/$4 boundaries:
$(vMyFunc(ApplyMap('MyMap', field1, 'default')))

// RIGHT -- write inline when expression contains commas:
IF(IsNull(field1), 'default', ApplyMap('MyMap', Lower(field1), field1)) AS [My.Field]
```

**Common violations:** `$(v(ApplyMap(...)))`, `$(v(PurgeChar(f, '...')))`, `$(v(IF(x, y, z)))`. When a variable function cannot wrap an expression due to commas, write the equivalent logic inline with a comment explaining why.

### QUALIFY/UNQUALIFY

QUALIFY prefixes field names with their table name to prevent unintended associations. It is one way to avoid synthetic keys, but aliasing fields with `AS` in the LOAD statement is equally valid and often clearer since it gives you explicit control over each field name. Use whichever approach fits the situation.

**If using QUALIFY:** `QUALIFY *;` qualifies ALL fields, including key fields. After QUALIFY, immediately UNQUALIFY your join keys before any LOAD statements:

```qlik
QUALIFY *;
UNQUALIFY [%Customer.Key], [%Order.Key];  // Keep keys associating
// ... table loads ...
UNQUALIFY *;  // Reset after the block
```

QUALIFY and UNQUALIFY are state toggles that affect subsequent LOADs, not retroactive. Forgetting to UNQUALIFY key fields is the most common QUALIFY error. The result is silent: no error, no warning, just a data model with no associations.

**Double-qualification trap:** If fields are already entity-prefixed (e.g., `Customer.Name`), QUALIFY prepends the table name, producing `TableName.Customer.Name`. This breaks all downstream field references. Skip QUALIFY entirely when the naming convention already prevents ambiguity.

## 2. SET vs LET

`SET` preserves the right side as literal text (a template). `LET` evaluates the right side immediately.

```qlik
// SET preserves the template -- $1 placeholders stay unevaluated:
SET vDualBool = IF(Match($1, 'true') > 0, Dual('$2', 1), Dual('$3', 0));

// LET evaluates immediately -- use for computed values:
LET vRowCount = NoOfRows('MyTable');
LET vToday = Num(Today());
```

**Rule:** Use `SET` for variable functions containing quotes, Dual(), or `$1` placeholders. Use `LET` for simple value assignments where you need the result now.

**Critical:** `SET` does not evaluate function calls. `SET HidePrefix=Chr(37);` assigns the literal string `Chr(37)`, not the `%` character. To assign a computed value, use `LET HidePrefix=Chr(37);` or `SET HidePrefix='%';`. This applies to all function calls on the right side of SET, including `Chr()`, `Num()`, `Date()`, `Today()`, `Time()`, etc.

## 3. Dollar-Sign Expansion

Inside `$()`, commas are parameter delimiters. This is the #1 source of reload errors in scripts using SET variable functions.

```qlik
// The comma in PurgeChar breaks the variable call:
// WRONG: $(vCleanNull(PurgeChar(field, '[]')))
// The engine sees: $1=PurgeChar(field, $2='[]')

// RIGHT -- write inline with comment:
// Cannot use vCleanNull here (comma in PurgeChar args)
IF(IsNull(PurgeChar(given_names, '[]{}' & Chr(34)))
   OR Len(Trim(PurgeChar(given_names, '[]{}' & Chr(34)))) = 0,
   Null(),
   Trim(PurgeChar(given_names, '[]{}' & Chr(34))))  AS [Name.Given]
```

Only pass simple field names or literals (no commas) as arguments to variable functions.

**Null variable expansion:** If a `LET` assignment evaluates to null, the variable is empty. `IF $(emptyVar) >= 0 THEN` becomes `IF >= 0 THEN` — a syntax error. Guard at assignment time with a default: `LET vX = Alt(NoOfRows('MaybeGone'), -1);` or check before expansion: `IF '$(vX)' <> '' AND $(vX) >= 0 THEN`. This applies to any function that can return null (`NoOfRows` on dropped/nonexistent tables, `Peek` past end of table, `FieldValue` out of range, etc.).

## 4. Preceding LOAD

Two LOAD statements sharing one source. The inner LOAD executes first. The outer LOAD can reference fields calculated by the inner.

```qlik
[MyTable]:
LOAD *, IF([Age] < 18, 'Minor', 'Adult') AS [Age.Category]
;
LOAD
    Floor((Today() - birth_date) / 365.25) AS [Age],
    other_field
RESIDENT [_Source];
```

**When to use:** Avoid repeating the same complex expression in nested IFs. Calculate once in the inner LOAD, reference in the outer. Also used as the Qlik replacement for `HAVING`: aggregate in inner LOAD, filter on the aggregate in outer LOAD with `WHERE`.

## 5. Null Handling (Summary)

Three strategies, each for a different scenario:

**vCleanNull variable function:** For string-encoded nulls ("null", "NaN", "n/a", "[null]") from ETL pipelines and data lakes. `IsNull()` does NOT catch these. See `null-handling-patterns.md` and `script-templates/clean-null-function.qvs`.

**NullAsValue:** For sparse dimension fields where NULL should display as "No Entry" in filter panes. Field-specific and stateful (persists until reset). Field names must match OUTPUT aliases, not source names. Never use on key fields (breaks associations) or measure fields (breaks Sum/Avg). See `null-handling-patterns.md`.

**Null guards on date arithmetic:** `Floor((Today() - NULL_date) / 365.25)` produces ~125, not NULL. Always wrap date math in `IF(IsNull(date_field), Null(), ...)`. See `null-handling-patterns.md`.

**Decision framework:**
| Field Type | Strategy |
|---|---|
| String dimensions from external sources | vCleanNull |
| Sparse dimensions for filter pane display | NullAsValue |
| Date/numeric calculations | Explicit IsNull guards |
| Key fields | Never mask nulls (they indicate data quality issues) |

## 6. Data-Driven Patterns

**Range bucketing via mapping expansion:** Replace nested IFs with inline data + mapping table + ApplyMap. Edit the inline table to change buckets, no code changes needed.

```qlik
[_Def]: LOAD * INLINE [from, to, label, sort
0,  17, 0-17,  1
18, 24, 18-24, 2
65, 200, 65+,  7] (delimiter is ',');

_Map: MAPPING LOAD Num#(from) + IterNo() - 1, Dual(Trim(label), Num#(sort))
RESIDENT [_Def] WHILE Num#(from) + IterNo() - 1 <= Num#(to);
DROP TABLE [_Def];

ApplyMap('_Map', [Age], Dual('Unknown', 0)) AS [Age.Group]
```

**Boolean fields via Dual:** `Dual('Active', 1)` enables text display AND numeric aggregation (`Sum([Is.Active])` = count of active). Wrap in a SET variable function for reuse. See `script-templates/clean-null-function.qvs` for vDualBool.

**Metadata-driven table loading:** Define an inline metadata table (TableName, SourceTable, PrimaryKey, Enabled) and loop through it with FOR/Peek. Adding a new table = adding a metadata row.

```qlik
FOR i = 0 TO NoOfRows('_Metadata') - 1
    LET vTableName = Peek('TableName', $(i), '_Metadata');
    LET vEnabled   = Peek('Enabled', $(i), '_Metadata');
    IF '$(vEnabled)' = 'Y' THEN
        [$(vTableName)]:
        LOAD * FROM [lib://Connection/$(vTableName).qvd] (qvd);
    END IF
NEXT i
```

## 7. QVD Operations

### STORE Syntax
```qlik
STORE * FROM [TableName] INTO [lib://Connection/path/file.qvd] (qvd);
STORE Field1, Field2 FROM [TableName] INTO [lib://Connection/file.qvd] (qvd);
```

One table per STORE.

### QVD Read Modes

QVD files support two read modes. Optimized read is ~10x faster than standard QVD read and ~100x faster than reading from a database. Standard read is still ~10x faster than database.

**What preserves optimized read:**
- `LOAD *` (all fields, no transforms)
- Field subsetting (loading specific fields by name)
- Field renaming with `AS` (e.g., `source_col AS [New.Name]`)
- `LOAD DISTINCT`
- `CONCATENATE` load
- One-parameter `EXISTS(field)` / `NOT EXISTS(field)` (single field name, no second argument)
- Preceding LOAD above the QVD LOAD (the inner QVD read remains optimized; the preceding load processes in-memory after the fast read)

**What forces standard read:**
- Transformations or functions on fields (e.g., `Upper(name)`, `Date#(date_field)`)
- Derived/calculated fields (e.g., `field1 & '-' & field2 AS CompositeKey`)
- Two-parameter `EXISTS(field, expression)` (the expression form)
- WHERE clauses other than one-parameter EXISTS (e.g., `WHERE amount > 0`)
- `Map...Using` applied to fields being loaded
- `MAPPING LOAD` from QVD

```qlik
// Optimized -- no transforms, no WHERE:
LOAD * FROM [lib://QVDs/Customers.qvd] (qvd);

// Optimized -- field rename and subset:
LOAD customer_id AS [Customer.Key], name AS [Customer.Name]
FROM [lib://QVDs/Customers.qvd] (qvd);

// Optimized -- one-parameter NOT EXISTS:
LOAD * FROM [lib://QVDs/Orders.qvd] (qvd)
WHERE NOT EXISTS([Order.Key]);

// Standard -- two-parameter EXISTS forces unpack:
LOAD * FROM [lib://QVDs/Orders.qvd] (qvd)
WHERE NOT EXISTS([Existing.Key], [Order.Key]);

// Standard -- transformation on field:
LOAD Upper(name) AS [Customer.Name]
FROM [lib://QVDs/Customers.qvd] (qvd);
```

### Load Once, Create Multiple Maps

Never read the same QVD from disk multiple times. Load to temp, create maps from resident, drop temp.

```qlik
[_Temp]: LOAD key, field_a, field_b FROM [file.qvd] (qvd);
Map_A: MAPPING LOAD key, field_a RESIDENT [_Temp];
Map_B: MAPPING LOAD key, field_b RESIDENT [_Temp];
DROP TABLE [_Temp];
```

### Binary Load
`binary [app_id_or_path];` must be the FIRST statement in the script (before SET). Loads data tables and section access data only (no sheets, variables, master items). Only ONE binary statement per script.

## 8. Incremental Load Patterns (Summary)

| Source Pattern | Strategy | Key Requirement |
|---|---|---|
| Append-only transactions | Insert-only (by timestamp/key) | Monotonic key or reliable timestamp |
| Mutable dimension (SCD1) | Insert/update (by ModifiedDate) | Reliable modification timestamp |
| Full-refresh staging | Full replace each cycle | None |
| SCD Type 2 dimension | **Dual-timestamp** (effective_from + effective_to) | Both timestamps tracked |
| Mutable with deletes | Insert/update/delete | Change detection + deletion flag or full-key comparison |

**Critical:** The dual-timestamp SCD Type 2 pattern must capture BOTH newly created records AND records whose effective_to changed (previously current records that were closed). Missing the closure condition = silent data loss. See `incremental-load-patterns.md` for complete working code and `script-templates/dual-timestamp-incremental.qvs` for the ready-to-use template.

## 9. Master Calendar

A master calendar provides a continuous date dimension with custom periods (fiscal year, relative date flags). It must derive date ranges from loaded data, never hard-coded. Must produce Dual-sorted month fields for correct sort with text display. See `script-templates/master-calendar.qvs` for the production-ready template.

## 10. Error Handling and Logging

- **TRACE:** `TRACE === Phase: Extract ===;` for milestones. `TRACE Rows loaded: $(vRowCount);` for row counts. Use `%%` to output a literal `%` character (single `%` is interpreted as a format specifier).
- **ScriptError / ScriptErrorCount:** ScriptErrorCount is **cumulative** across the entire reload. After a non-critical error is logged and continued, all subsequent `IF ScriptErrorCount > 0` checks will also be true. Always capture `LET vPreErrors = ScriptErrorCount;` before an operation and compare `IF ScriptErrorCount > $(vPreErrors)` after. See `script-templates/error-handling.qvs` for the correct pattern.
- **ScriptErrorList:** Concatenated list of all errors, line-feed separated. Use for logging.
- **ErrorMode:** `SET ErrorMode = 1;` (0=continue on error, 1=stop on error, 2=immediate fail). In Qlik Sense and Qlik Cloud, ErrorMode=1 is the default and recommended setting. ErrorMode=0 allows the script to continue after errors, which is useful for non-critical fallback paths but requires careful ScriptErrorCount checking.
- **File existence:** `IF NOT IsNull(FileTime('lib://path/file.qvd')) THEN` to check before loading.
- **Field value inspection at script time:** To get min/max of a loaded field, use a Resident LOAD: `[_Temp]: LOAD Min(Field) AS _min, Max(Field) AS _max Resident MyTable; LET vMin = Peek('_min', 0, '_Temp'); DROP TABLE [_Temp];`. For symbol table iteration, use `FieldValue('Field', n)` with `FieldValueCount('Field')`. Note: `fieldvaluelist` is a `FOR EACH` loop keyword (like `filelist` and `dirlist`), not a general-purpose function — it cannot be used in LET assignments or as an argument to other functions.

See `script-templates/error-handling.qvs` for the error handling and logging framework (preferred for production scripts). See `diagnostic-patterns.md` for standalone TRACE templates and validation queries. **These are alternatives, not complements.** If using error-handling.qvs, use its `LogRowCount` subroutine. The standalone `LogLoadCount` in diagnostic-patterns.md is for scripts that don't include the full framework.

## 11. NoConcatenate and Auto-Concatenation

When a new table has the same number of fields AND matching field names as an existing table, Qlik **silently concatenates** rows into the existing table. The new table name is never registered. Subsequent `NoOfRows('NewTable')` returns NULL. `DROP TABLE [NewTable]` fails.

```qlik
// BROKEN -- _Dedup merges into _Collector (same field: key_field):
[_Collector]: LOAD key_field FROM [source.qvd] (qvd);
[_Dedup]: LOAD DISTINCT key_field RESIDENT [_Collector]; // auto-concatenates!

// FIXED -- NoConcatenate forces a separate table:
[_Dedup]: NoConcatenate LOAD DISTINCT key_field RESIDENT [_Collector];
```

**Convention:** Use `NoConcatenate` whenever creating a temporary or working table that should be standalone. This is standard defensive practice when you know the table is single-purpose and should not merge with anything else, regardless of whether you've confirmed a field overlap exists.

**Mapping LOAD tables are invisible to meta-functions.** Tables created via `Mapping LOAD` are consumed at `ApplyMap()` time and do not persist as named tables in the data model. `NoOfRows('MappingTableName')`, `FieldValueCount()`, `FieldName()`, and all other table/field meta-functions return null or -1 for Mapping tables. Never use these functions to validate Mapping tables. Instead, validate indirectly by checking the row count of the downstream table that consumes the mapping (e.g., if the target table loads 0 rows, the mapping was likely empty or misconfigured).

## 12. EXISTS Symbol Space Behavior

`EXISTS(field, value)` checks the **entire symbol space** (all tables with that field name), not one table. This includes values already loaded in the current statement.

**Cross-table contamination:** If `[Dimension]`, `[_TempA]`, and `[_TempB]` all have `key_field`, then `WHERE NOT EXISTS(key_field)` checks all three. This produces unexpected zero-row results.

**Self-referencing dedup (documented gotcha):** `WHERE NOT EXISTS(field)` using one-parameter form checks values that have already been loaded **during the current LOAD statement**, not just previously loaded tables. The symbol table updates row by row as the load progresses. When a value loads, it immediately becomes "existing." The next row with the same value sees it as already existing and is skipped. Result: only the **first occurrence** of each value loads. This is intentional Qlik behavior but often unintended by the developer.

```qlik
// Only loads ONE row per customer_id, even if source has duplicates:
LOAD * FROM [lib://QVDs/Orders.qvd] (qvd)
WHERE NOT EXISTS(customer_id);

// To load ALL rows for non-existing keys, alias the lookup field
// so the current load's values don't pollute the check:
[_Existing]:
LOAD DISTINCT customer_id AS _existing_cust RESIDENT [Customers];

LOAD * FROM [lib://QVDs/Orders.qvd] (qvd)
WHERE NOT EXISTS(_existing_cust, customer_id);

DROP TABLE [_Existing];
```

**Workaround:** When you need `NOT EXISTS` to check against a previously loaded table without the self-referencing dedup effect, load the lookup field into a separate table under a different name, then use the two-parameter form: `WHERE NOT EXISTS(aliased_field, source_field)`. Note that the two-parameter form forces standard QVD read mode.

**Solution for cross-table contamination: Always alias the EXISTS lookup field:**

```qlik
[_HasDetail]:
LOAD DISTINCT key_field AS _has_detail RESIDENT [_DetailBest];

CONCATENATE([_DetailBest])
LOAD DISTINCT key_field, 'No Entry' AS [Detail.Value]
RESIDENT [Dimension]
WHERE NOT EXISTS(_has_detail, key_field);

DROP TABLE [_HasDetail];
```

## 13. Subroutine Integration

**Include external files:** `$(Must_Include=lib://Connection/path/file.qvs);` fails the reload if the file is missing. `$(Include=...)` silently skips.

**Call subroutines:** `CALL SubName(param1, param2);` after the include.

**Phantom field prevention:** Some shared subroutines initialize empty inline tables. If column parameters are wildcards or improperly specified, phantom fields appear in results. Always verify subroutine output contains only expected fields. After calling a subroutine, check by iterating fields in script:

```qlik
FOR vFldIdx = 1 TO NoOfFields('$(vResultTable)')
    LET vFldName = FieldName($(vFldIdx), '$(vResultTable)');
    TRACE Field $(vFldIdx): $(vFldName);
NEXT vFldIdx
```

**Composite key workaround:** When a subroutine handles only single keys but you need composite keys, concatenate key parts before calling and split after, or bypass the subroutine and implement the logic directly.

## 14. Script Organization

| Approach | When to Use |
|---|---|
| Tabs (in-app sections) | Simple single-app projects, all code visible in one editor |
| Include files (.qvs) | Multi-app projects, shared code, version control |
| Numeric prefix | `01_Config.qvs`, `02_Extract_SourceA.qvs`, `03_Transform.qvs` |

**Split when** a single tab exceeds ~500 lines. Split by logical function (config, extract per source, transform, model load, calendar, diagnostics).

**Script execution manifest:** A documentation file listing each script file, its purpose, dependencies, and run order.

## 15. Placeholder Logic for Blocked Dependencies

When a source table is unavailable (empty, schema not finalized, upstream not delivered), produce a documented empty table with the expected schema. The pipeline continues with placeholders rather than blocking.

```qlik
// PLACEHOLDER: Product loyalty data not yet available
// Source: loyalty_program.product_affinity (via lib://LoyaltyDB)
// Resolves when: Loyalty team delivers API access (ETA: Q2 2026)
// Remove this block and uncomment the SQL SELECT below when resolved.
TRACE [WARNING] Using placeholder for Product.Loyalty -- source not available;
[ProductLoyalty]:
LOAD * INLINE [
    Product.Key, Loyalty.Tier, Loyalty.Points
] (delimiter is ',');
```

Every placeholder must include: what it replaces, expected source, resolution condition, and a TRACE warning. The orchestrator tracks these in `.pipeline-state.json` for downstream impact analysis.

## 16. Cross-Layer Field Rename Mechanics

Three mechanisms for renaming fields in scripts, from simple to systematic:

- **Aliasing in LOAD:** `source_field AS [UI.Field.Name]` — use for per-field transforms during extraction or model load.
- **RENAME FIELD:** `RENAME FIELD old_name TO [New.Name];` — use for individual post-load renames. **Collision warning:** RENAME FIELD affects ALL tables containing that field name. If `region` exists in both `[Customers]` and `[Products]`, `RENAME FIELD region TO [Customer.Region]` renames it in both tables. Use Mapping RENAME or aliasing in LOAD when you need table-specific renames.
- **Mapping RENAME:** Bulk rename from a mapping table. Use for systematic cross-layer renaming (e.g., all raw extract names to model-layer names in one operation). Same cross-table behavior as RENAME FIELD, so ensure source field names are unique across tables before applying.

```qlik
[_RenameMap]: MAPPING LOAD old_name, new_name INLINE [
old_name, new_name
acct_status, Customer.Status
ship_addr_line1, Customer.ShipAddress
] (delimiter is ',');
RENAME FIELDS USING [_RenameMap];
```

See `qlik-naming-conventions` for the naming strategy (what names to use at each layer).

## 17. String Functions

**PurgeChar** strips multiple characters in one call. Always requires two arguments:
```qlik
// WRONG -- missing second argument:
PurgeChar(my_field)
// RIGHT:
PurgeChar(my_field, '[]{}' & Chr(34))
```

**SubField + IterNo** for array expansion:
```qlik
LOAD key_field,
    Trim(SubField(clean_list, ',', IterNo())) AS [Expanded.Value]
RESIDENT [Source]
WHILE Len(Trim(SubField(clean_list, ',', IterNo()))) > 0;
```

Clean delimiters with PurgeChar before expanding.

## Supporting Files

- `incremental-load-patterns.md` -- Complete incremental load patterns with working code
- `null-handling-patterns.md` -- vCleanNull, NullAsValue, null guard patterns
- `diagnostic-patterns.md` -- TRACE templates, row count logging, validation queries
- `script-templates/master-calendar.qvs` -- Production-ready master calendar
- `script-templates/error-handling.qvs` -- Error handling and logging framework
- `script-templates/clean-null-function.qvs` -- Null-cleaning variable functions
- `script-templates/dual-timestamp-incremental.qvs` -- SCD Type 2 incremental load
