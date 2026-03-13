# Optimization Patterns

Escalation strategies for when one or more of the three optimization metrics (Base RAM, Peak RAM, Reload Time) approach or exceed acceptable limits. These patterns are NOT default practice for every app. Each pattern includes a "When to reach for this" gate.

---

## Pattern 1: Key Encoding Strategies

**When to reach for this:** Fact tables exceed ~1M rows AND key fields are string-based with high cardinality (>10K distinct values). If your largest fact table is under 1M rows, skip this entirely.

### AutoNumberHash for the Primary Composite Key

Use `AutoNumberHash256()` for the single most consequential composite key. This is typically the grain key of the largest fact table. It hashes the input fields, then autonumbers the hash result to produce the densest possible integer encoding.

```qlik
// Composite key from three source fields — autonumbered to a dense integer sequence:
AutoNumberHash256([Source.OrderID], [Source.LineNum], [Source.ShipDate]) AS [%OrderLineKey]
```

Why only one: AutoNumberHash uses the default (unnamed) AutoID counter. If multiple keys share this counter, they compete for sequence positions, producing gaps. Reserve it for the key with the highest row count impact.

Like all AutoNumber variants, AutoNumberHash256 is non-deterministic across separate reload operations. The same input may produce a different integer in a different reload. All tables sharing this key must be loaded in the same reload execution.

### AutoNumber with Named AutoID for Secondary Keys

```qlik
// Each key gets its own dense integer sequence:
AutoNumber([Customer.NaturalKey], 'AutoID_Customer') AS [%CustomerKey]
AutoNumber([Product.SKU], 'AutoID_Product') AS [%ProductKey]
```

The second parameter creates a separate counter. Without it, all `AutoNumber()` calls share one counter, and sequences become sparse (wasting symbol table space).

### Hash as a Peak RAM Alternative

AutoNumber must hold the original value AND the autonumbered integer simultaneously during encoding. For very large tables, this doubles Peak RAM for the key field during that phase of the reload.

If Peak RAM is the binding constraint, use `Hash128()` or `Hash256()` instead. Hash produces a fixed-width numeric output in a single pass with no temporary duplication.

```qlik
// No peak RAM spike, but slightly larger Base RAM than autonumbered integers:
Hash128([Source.OrderID], [Source.LineNum]) AS [%OrderLineKey]
```

**Trade-off summary:**

| Strategy | Base RAM | Peak RAM | Reload Time | Debuggability |
|----------|----------|----------|-------------|---------------|
| AutoNumberHash256 | Lowest (dense int) | Higher (temp duplication) | Slower (encoding pass) | Low |
| AutoNumber (named) | Low (dense int per key) | Higher (temp duplication) | Slower | Low |
| Hash128/256 | Medium (hash values) | Neutral (single pass) | Neutral | Low |
| Raw string keys | Highest | Lowest (no encoding) | Fastest | Highest |

---

## Pattern 2: Memory Choreography

**When to reach for this:** Peak RAM during reload approaches the environment's memory limit, causing OOM failures or excessive swap. If reloads complete without memory pressure, this pattern adds complexity for no benefit.

### Principle: Front-Load Heavy Operations

The reload script executes sequentially. Early in the script, only a few tables exist in memory, so available headroom is greatest. Schedule operations with large temporary memory footprints (joins, concatenations, heavy transformations) early, before dimension tables and other persistent structures accumulate.

```qlik
// EARLY in script — memory is mostly free:
// Do the big join that temporarily doubles the fact table in memory
[_StagingFact]:
LOAD * FROM [lib://DataFiles/RawTransactions.qvd] (qvd);

LEFT JOIN ([_StagingFact])
LOAD * FROM [lib://DataFiles/TransactionDetails.qvd] (qvd);
// Peak RAM spike happens here, but headroom is available

// Store result and free memory immediately:
STORE [_StagingFact] INTO [lib://DataFiles/JoinedFact.qvd] (qvd);
DROP TABLE [_StagingFact];

// LATER in script — memory is more constrained:
// Load the pre-joined QVD (optimized load, no peak spike)
[Fact.Transactions]:
LOAD * FROM [lib://DataFiles/JoinedFact.qvd] (qvd);
```

### Store-and-Drop for Very Tall Tables

When a staging table is very large and only needed for a later phase, store it to QVD immediately after creation, drop it, and reload it when needed. The QVD optimized reload is fast and avoids holding the table in memory across intermediate phases.

### Drop Immediately After Last Use

Every temp table should be dropped on the line immediately following its last consumer. Do not batch DROP statements at the end of a section. Each deferred drop inflates Peak RAM across all intervening operations.

---

## Pattern 3: Date Guardrails

**When to reach for this:** The model uses `IntervalMatch()`, date spine generation (`While`/`IterNo()` loops), or any row-multiplication operation driven by date ranges. A single out-of-range date (year 1900, year 9999) can generate millions of spurious rows.

### Parameterized Date Validation

Define expected date boundaries as variables and validate before any row-generation operation:

```qlik
// Set expected boundaries (adjust per project):
LET vDateMin = Num(MakeDate(2015, 1, 1));
LET vDateMax = Num(MakeDate(2030, 12, 31));

// In the load that feeds IntervalMatch or date spine:
WHERE Num([StartDate]) >= $(vDateMin)
  AND Num([EndDate]) <= $(vDateMax)
  AND Num([EndDate]) >= Num([StartDate]);
```

### Why This Matters

IntervalMatch generates one row per interval-date intersection. A record with StartDate = 1900-01-01 and EndDate = 2030-12-31 generates ~47,000 rows from a single source record. Multiply by thousands of such records and the fact table explodes, consuming all available RAM and causing reload failure.

Date guardrails are cheap insurance. Add them whenever date-driven row multiplication exists in the script, regardless of current data quality.

---

## Pattern 4: DropUnusedFields Subroutine

**When to reach for this:** The model loads from wide source tables (30+ fields) and only a subset reaches the final data model. Particularly valuable when source schemas change over time and unused fields accumulate silently.

### Configurable Field Cleanup

```qlik
// Subroutine: collects field names first, then drops non-allowlisted fields.
// Two-pass approach avoids index-shift issues from dropping fields mid-iteration.
SUB DropUnusedFields

  // Pass 1: collect all current field names into variables
  LET vFieldCount = NoOfFields();
  FOR i = 0 TO $(vFieldCount) - 1
    LET vField_$(i) = FieldName($(i));
  NEXT i

  // Pass 2: evaluate each collected name and drop if not in allowlist
  FOR i = 0 TO $(vFieldCount) - 1
    LET vCheckField = vField_$(i);
    // Never drop key fields or system fields:
    IF NOT WildMatch('$(vCheckField)', '*Key', '%*') THEN
      // Check if field is in the allowlist:
      IF NOT Exists('AllowedField', '$(vCheckField)') THEN
        TRACE Dropping unused field: $(vCheckField);
        DROP FIELD [$(vCheckField)];
      END IF
    END IF
  NEXT i

END SUB

// Usage:
// 1. Create an inline allowlist table with a single field 'AllowedField'
//    listing every field name you want to keep
// 2. Call the subroutine after all tables are loaded
// 3. Drop the allowlist table
```

### Safety Rules

- Never drop fields matching `*Key` or `%*` patterns (link fields).
- Log dropped fields via TRACE so the reload log documents what was removed.
- Run after all tables are loaded but before STORE operations.

---

## Pattern 5: If() to Set Analysis Conversion

**When to reach for this:** Expression response times exceed 200ms, AND the slow expression uses `If()` inside an aggregation to filter records. This is a correctness improvement as much as a performance one, since set analysis results are cached and If() results are not.

### Common Conversions

```qlik
// BEFORE — If() evaluates per record:
Sum(If([Year] = 2024, [Sales.Amount], 0))
// AFTER — set analysis filters before aggregation:
Sum({<[Year] = {2024}>} [Sales.Amount])

// BEFORE — If() with multiple conditions:
Sum(If([Year] = 2024 AND [Region] = 'North', [Sales.Amount], 0))
// AFTER — set analysis with multiple field filters:
Sum({<[Year] = {2024}, [Region] = {'North'}>} [Sales.Amount])

// BEFORE — If() for period comparison:
Sum(If([Year] = Year(Today()), [Sales.Amount], 0))
  - Sum(If([Year] = Year(Today()) - 1, [Sales.Amount], 0))
// AFTER — variable-driven set analysis:
Sum({<[Year] = {$(=Year(Today()))}>} [Sales.Amount])
  - Sum({<[Year] = {$(=Year(Today()) - 1)}>} [Sales.Amount])
```

### When If() Is Correct

`If()` is appropriate when the conditional logic selects between different measures or applies different calculations per record within the aggregation, not when it filters which records to include.

```qlik
// CORRECT use of If() — choosing between two fields per record:
Sum(If([Order.Type] = 'Return', -[Item.Amount], [Item.Amount]))
```

---

## Pattern 6: Calculation Condition Patterns

**When to reach for this:** A visualization uses `Aggr()`, `Rank()`, or `Count(DISTINCT ...)` over dimensions with >500 distinct values, causing visible lag on sheet load or selection changes.

### Single-Value Requirement

```qlik
SET vCalcCond_SingleCustomer = GetSelectedCount([Customer.Key]) = 1;
SET vCalcMsg_SingleCustomer = 'Select exactly one customer to view comparison';
```

### Cardinality Limit

```qlik
SET vCalcCond_TopProducts = GetSelectedCount([Product.Key]) <= 200
  OR GetSelectedCount([Product.Key]) = 0;
SET vCalcMsg_TopProducts = 'Select 200 or fewer products to view ranking';
```

Note: The `OR ... = 0` clause allows the chart to render when NO products are selected (showing all, which may be acceptable depending on total cardinality). Adjust based on the specific visualization's tolerance.

### Row Count Threshold

```qlik
SET vCalcCond_MinData = GetPossibleCount([Transaction.Key]) >= 50;
SET vCalcMsg_MinData = 'Insufficient data for meaningful analysis. Broaden your selections.';
```

---

## Pattern 7: Three-Tier Transformation Architecture

**When to reach for this:** Reload Peak RAM significantly exceeds Base RAM (2x or more), indicating that intermediate transformation tables accumulate in memory. Also useful when the same source data feeds multiple apps, since the intermediate QVD tier can be shared.

### Architecture

```
Tier 1: Extract (Raw QVDs)
  LOAD * FROM source → STORE → DROP
  One QVD per source table. No transformations.

Tier 2: Transform
  LOAD from Raw QVDs → apply cleanup, key encoding, joins → STORE → DROP
  Produces model-ready QVDs.

Tier 3: Model
  LOAD * from Tier 2 QVDs (optimized loads, no transformations)
  Final in-memory data model.
```

### Key Encoding Constraint

AutoNumber cannot be used across tiers. Because each tier runs as a separate reload (or separate section with tables dropped between phases), AutoNumber will assign different integers to the same source values in each tier. Use `Hash128()` or `Hash256()` for key encoding when keys must be consistent across separate reload operations. Hash functions are deterministic, so the same input produces the same output regardless of which tier performs the encoding.

### Why It Helps

Without tiers, transformation tables accumulate in memory alongside their raw sources. A 10GB raw extract being joined and transformed can spike Peak RAM to 25-30GB as intermediate results stack up.

With tiers, each phase stores its output and drops its tables before the next phase begins. Peak RAM never exceeds the single largest table being processed at any given moment, plus the cost of the operation being performed on it.

### When to Skip

For small-to-medium apps (Base RAM under ~4GB), the complexity of three tiers is not worth the Peak RAM savings. A single-pass script with disciplined temp table drops is sufficient.

---

## Pattern 8: ApplyMap for Most-Recent Record

**When to reach for this:** The model needs the latest value from a slowly changing dimension or event log, and a full join would duplicate fact rows or inflate the model unnecessarily.

### Pattern

```qlik
// Build a mapping from the source, sorted so the most recent record is first.
// MAPPING LOAD keeps the first value encountered for duplicate keys.
[Map_LatestStatus]:
MAPPING LOAD [Entity.Key], [Status.Value]
RESIDENT [_StatusHistory]
ORDER BY [Event.Date] DESC;

// Apply to the target table:
[Dimension.Entity]:
LOAD *,
     ApplyMap('Map_LatestStatus', [Entity.Key], 'Unknown') AS [Entity.CurrentStatus]
RESIDENT [_EntityBase];
```

This avoids a GROUP BY or window-function-style approach that would require a full resident scan with aggregation. ApplyMap is a hash lookup, executing in O(1) per row.

---

## Pattern 9: Optimization Workflow

**When to reach for this:** One or more of the three metrics (Base RAM, Peak RAM, Reload Time) exceeds acceptable limits and targeted fixes have not resolved the issue. This is the systematic approach for tracking down the root cause.

### Cycle

1. **Profile:** Identify the largest tables by row count and field count. Check reload log for phase timings. Note which tables persist longest during reload.
2. **Hypothesize:** Based on the profile, identify the single most likely bottleneck. Form a specific prediction: "Dropping the audit fields from the transaction table should reduce Base RAM by approximately 2GB."
3. **Adjust:** Make ONE change. Not two. Not five. One.
4. **Reload:** Run a full reload (or use `EXIT SCRIPT` after the relevant section to isolate the measurement).
5. **Measure:** Compare the metric against the pre-change baseline. Did it improve? By how much? Was the prediction accurate?
6. **Decide:** Keep the change if it improved the target metric without unacceptably degrading another. Revert if it didn't help or introduced a worse trade-off.

### Using EXIT SCRIPT for Focused Profiling

When the bottleneck is suspected to be in a specific phase, add `EXIT SCRIPT;` after that phase to measure it in isolation without waiting for the full reload to complete.

```qlik
// Temporarily isolate the extract phase:
[_RawOrders]: LOAD * FROM [lib://DataFiles/Orders.qvd] (qvd);
TRACE === Extract complete. Rows: $(=NoOfRows('_RawOrders')) ===;
EXIT SCRIPT;  // Remove after profiling
```

### Discipline

The value of this cycle is in its one-change-at-a-time discipline. Multiple simultaneous changes make it impossible to attribute improvement or regression to any specific action. When optimization is needed, slow and methodical beats fast and chaotic.

---

## Pattern 10: Data Volume Estimation

**When to reach for this:** Planning phase of any app expected to load >10M rows or >2GB of source data. Also useful retroactively when an existing app's reload time or memory consumption has grown beyond expectations.

### Documentation Template

```qlik
// ===== DATA VOLUME ESTIMATION =====
// Source: [describe source system and table]
// Source records: ~NM rows, ~N bytes/row = NGB raw
//
// After date filter (N months): ~NM rows (N% reduction)
// After field removal (N fields dropped): ~N bytes/row
// After key encoding: ~N bytes/row (key fields reduced from N to N bytes)
//
// Expected final model:
//   Fact table: NM rows × N bytes = NGB
//   Dim tables: N total ≈ NGB
//   Total Base RAM: ~NGB
//   Estimated Peak RAM: ~NGB (2x largest staging table)
//   Target Reload Time: N minutes
```

Document this at the top of the script or in a dedicated section. When performance issues surface later, this history enables targeted investigation rather than guessing.
