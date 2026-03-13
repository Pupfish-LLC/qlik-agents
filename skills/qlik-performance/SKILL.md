---
name: qlik-performance
description: |
  Performance optimization for Qlik Sense: three-metric framework (Base RAM, Peak RAM, Reload Time),
  key encoding hierarchy, QVD optimized load rules, expression performance (If vs set analysis,
  Aggr caution, master items for caching), memory choreography, and data reduction techniques.
  Load when optimizing or reviewing performance-sensitive artifacts.
---

# Qlik Performance Optimization

## Core Principle

Qlik Sense stores all loaded data in RAM. Performance optimization targets three metrics that often conflict:

| Metric | What It Measures | Why It Matters |
|--------|-----------------|----------------|
| **Base RAM** | Memory footprint after reload completes | Must stay under app size limits, which vary by tenant and space configuration |
| **Peak RAM** | Highest memory consumption during reload | Must stay under reload memory limits, which vary by tenant and space configuration |
| **Reload Time** | Wall-clock duration of full reload | Must stay under reload duration limits, which vary by tenant and space configuration |

**Trade-off awareness is mandatory.** Strategies that reduce one metric often increase another:

- `AutoNumber()` reduces Base RAM (integer keys replace strings) but increases Peak RAM and Reload Time (engine must hold original + autonumbered values simultaneously during encoding).
- Pre-calculated fields reduce query response time but increase Base RAM and Reload Time.
- Aggressive date-range filtering reduces all three metrics but limits historical analysis.

When generating or reviewing scripts, always identify which metric you are optimizing and note the trade-off. Do not apply optimization patterns blindly. Many are only necessary when one or more metrics approach their limits.

---

## 1. Key Encoding

String-based keys consume significantly more memory than numeric keys in large tables. Encode keys when fact tables exceed ~1M rows or key fields have high cardinality.

### Encoding Hierarchy

Apply in this order of preference:

**Default:** `AutoNumber(field, 'AutoID_KeyName')` — Use for most key encoding needs. The second parameter creates a separate, named AutoID counter per key, maintaining a dense integer sequence. Without the second parameter, all AutoNumber calls share one counter, producing sparse sequences that waste symbol table space.

For scenarios requiring more aggressive encoding or where AutoNumber constraints are problematic, see the full encoding hierarchy in `optimization-patterns.md` (Pattern 1), which covers `AutoNumberHash256`, `Hash128/256`, and the trade-offs between them.

### AutoNumber Is Non-Deterministic Across Load Operations

AutoNumber (and AutoNumberHash) assigns integers based on the order values are encountered during a single reload execution. The same source value may receive a different integer in a different load statement, a different script, or even the same script if row order changes. This means:

- You cannot autonumber a key in an extract script and expect a separate transform script to produce matching integers for the same source values.
- Within a single script, all tables that share an autonumbered key must be loaded in the same reload execution so the engine assigns consistent integers across the join.
- If keys must be consistent across separate reload operations (e.g., a three-tier extract/transform/model architecture), use `Hash128()` or `Hash256()` instead. Hash functions are deterministic: the same input always produces the same output regardless of when or where the function runs.

### Symbol Table Behavior

Autonumbered fields produce sequential integers that serve as their own symbols. Symbol table RAM consumption for these fields is effectively zero. However, if a downstream table copy loads an autonumbered field out of its original order (e.g., after a join reorders rows), the engine may allocate a full symbol table. Adding `ORDER BY key_field ASC` or sorting during load restores the zero-cost optimization.

### When NOT to Encode

Skip key encoding for small dimensions (<100K rows), low-cardinality fields, or fields that developers need to read during debugging. The memory savings on small tables are negligible and encoding reduces debuggability.

---

## 2. QVD Optimized Load

A QVD optimized load reads QVD blocks directly into memory, skipping decompression and deserialization. Optimized loads are roughly 10x faster than standard QVD reads.

### What Preserves Optimized Load

- Field renaming with `AS` aliases
- Loading a subset of fields (you do not need to load all fields)
- `WHERE Exists(field_name)` — one-parameter form only
- `LOAD DISTINCT`
- `CONCATENATE` with another table

### What Breaks Optimized Load

- Any transformation or function call on a field: `Num(id)`, `Upper(name)`, `Date(date_field)`, `ApplyMap()`
- Adding derived/calculated fields (e.g., `1 AS [Counter]`)
- Two-parameter `Exists()`: `WHERE Exists(field_name, match_value)`
- Any WHERE clause other than one-parameter `Exists()`
- Aliasing the field used inside `WHERE Exists()` (the Exists field must keep its original name)
- Loading into a mapping table (`MAPPING LOAD ... FROM qvd`)
- `Map field_name Using map_table`

### Preceding LOAD Pattern

When transformations are needed, use a preceding LOAD to keep the inner (QVD) load optimized:

```qlik
[Dimension.Customer]:
LOAD *,
     Upper([Customer.Name]) AS [Customer.NameUpper];
LOAD *
FROM [lib://DataFiles/Customer.qvd] (qvd);
// Inner load: optimized (fast block read)
// Outer load: transforms in-memory (much faster than re-reading QVD)
```

### Single-Read Rule

Every QVD file should be read from disk exactly once per reload. If multiple mapping tables or subsets are needed from the same source, load to a temp table once and create maps/subsets from RESIDENT.

```qlik
[_ProductTemp]:
LOAD * FROM [lib://DataFiles/Product.qvd] (qvd);

[Map_ProductName]: MAPPING LOAD [Product.Key], [Product.Name] RESIDENT [_ProductTemp];
[Map_ProductCategory]: MAPPING LOAD [Product.Key], [Product.Category] RESIDENT [_ProductTemp];

DROP TABLE [_ProductTemp];
```

---

## 3. Expression Performance

Expressions execute during user interaction. Inefficient expressions degrade sheet response time from <100ms (target) to >1s (unusable).

### If() vs Set Analysis

**This is the single highest-impact expression optimization decision.**

`If()` inside an aggregation evaluates at the record level. For a field with 1,000,000 records, that is 1,000,000 conditional evaluations per chart recalculation. `If()` results are NOT cached by the engine.

Set analysis filters records before aggregation begins, reducing the evaluation set. Set analysis results ARE cached and reused across objects that share the same set expression.

```qlik
// SLOW — evaluates If() for every record in the aggregation scope:
Sum(If([Region] = 'North', [Sales.Amount]))

// FAST — filters to North records first, then sums:
Sum({<[Region] = {'North'}>} [Sales.Amount])
```

**Rule:** Never use `If()` inside an aggregation to filter records. Use set analysis. Reserve `If()` for conditional logic that genuinely varies per record within the aggregated result (e.g., choosing between two measure fields).

### Aggr() Caution

`Aggr()` creates internal temporary tables and can greatly affect performance. It also produces inaccurate results when the table's visible dimensions differ from the dimensions specified inside `Aggr()`.

- Avoid nested `Aggr()` calls. Pre-calculate in the load script instead.
- For ranking, consider pre-calculating rank fields during load rather than using `Aggr(Rank(...), dimension)` at query time.
- When `Aggr()` is unavoidable, pair it with a calculation condition that limits the dimension cardinality.

### Master Items for Caching

The Qlik engine caches expression results for master measures but not for ad-hoc inline expressions. Defining frequently used measures as master items is a free performance improvement. Two charts using the same master measure share cached results. Two charts using identical inline expressions do not.

### Pre-Calculated Fields and Numeric Flags

For expressions evaluated on every user interaction against large fact tables, consider pre-calculating at load time:

```qlik
// In load script — evaluated once during reload:
IF(amount > 10000, 1, 0) AS [Flag.HighValue]

// In expression — simple field reference, no computation:
Sum({<[Flag.HighValue] = {1}>} [Sales.Amount])
```

Use numeric flags (1/0) rather than string flags ('Yes'/'No'). Numeric comparisons in set analysis are faster than string comparisons, and numeric fields consume less memory.

**Trade-off:** Each pre-calculated field increases Base RAM and Reload Time. Only pre-calculate when the expression runs on multiple sheets or the runtime evaluation is measurably slow.

### Calculation Conditions

Calculation conditions prevent expensive expression evaluation when the selection context cannot support the visualization. Pair every condition with a message variable explaining why the chart is suppressed.

```qlik
// Variables defined in load script or variable editor:
SET vCalcCond_ProductRank = GetSelectedCount([Product.Key]) <= 500;
SET vCalcMsg_ProductRank = 'Select 500 or fewer products to view ranking';
```

Use calculation conditions when:
- An expression uses `Aggr()` or `Rank()` over a high-cardinality dimension
- The visualization is meaningless without a specific selection (e.g., single-customer comparison)
- Expression evaluation time exceeds 500ms without selections

---

## 4. Memory Model Fundamentals

### Field Types

Choose the narrowest type that holds the value:

- **Integer:** ~4-8 bytes. Use for IDs, counts, flags.
- **Numeric (float):** ~8 bytes. Use for amounts, percentages, measurements.
- **String:** Full character length plus overhead. Use for names, descriptions, free text.

Qlik stores date fields internally as numeric serial values (days since December 30, 1899) with a text format overlay for display. A properly interpreted date field already has efficient numeric storage. The risk is loading date values as raw text strings without interpretation (e.g., loading '2024-01-15' as a plain string from a CSV without a Date() or Date# call). Ensure dates are interpreted as dates during load so the engine stores the numeric representation.

### Dual Values

A `Dual()` field stores both a text representation and a numeric value. Use Dual when a field must display as text (e.g., month names) AND sort numerically. Dual provides correct sort order in the data model itself, which is more reliable than chart-level sort overrides.

Do not remove Dual from dimension fields to "save memory." For low-cardinality fields (months, weekdays, status codes), the memory difference is negligible and removing Dual breaks sort behavior.

Dual optimization only matters for high-cardinality fields (>100K distinct values) where both representations are stored per value in the symbol table.

### Field Count

Every field has overhead regardless of row count. In raw/transform layers, load only fields needed downstream. Use explicit field lists rather than `LOAD *` from non-QVD sources.

### Temp Table Cleanup

Temporary tables (prefixed `_`) must be dropped immediately after their last use. Every `_` table requires a corresponding `DROP TABLE` before reload completes. Accumulated temp tables inflate Peak RAM.

---

## 5. Data Reduction

Reducing data at load time is always more efficient than filtering at query time.

### Load-Time Reduction (Default Approach)

- **Date range:** Load only the history window required by the spec. `WHERE [Date.Key] >= $(vMinDate)`
- **Field removal:** Drop fields not required by any downstream consumer.
- **Aggregation:** Summarize to weekly or monthly when daily granularity is not required.
- **Section Access data reduction:** Filter rows by user role at load time (most secure and most efficient).

### Runtime Reduction (When Load-Time Is Insufficient)

- Set analysis filters in expressions
- Calculation conditions to suppress evaluation

**Default to load-time reduction.** Use runtime reduction only when the filter criteria depend on user selections that cannot be known at reload time.

---

## References

For executable code patterns with escalation triggers, see `optimization-patterns.md` in this skill directory. Patterns there are gated by specific conditions (e.g., "when Base RAM exceeds budget") and should not be applied by default to every app.
