---
name: qlik-data-modeling
description: "Star schema patterns, key resolution strategies, synthetic key prevention, QVD layer design, multi-app architecture patterns, source architecture consumption strategies, and associative engine behavior for Qlik Sense data modeling. Load when designing or reviewing data models."
---

# Qlik Data Modeling

## Overview

Qlik Sense's associative engine links tables through identically-named fields. Unlike relational databases with explicit JOIN syntax, Qlik creates associations automatically—any two tables sharing a field name are linked for selection propagation. This means **data modeling and field naming are inseparable**. A field name is not just a label; it is a structural decision that determines which tables associate, how users filter data, and whether the model produces correct results.

The fundamental constraint: **every pair of tables should share exactly one field name**. More than one shared field creates synthetic keys, which degrade performance and produce unexpected query results. Zero shared fields means the tables are data islands, unable to participate in selections.

This skill covers the patterns and decision frameworks for designing star schemas, resolving key strategies, preventing synthetic keys, organizing QVD layers, choosing multi-app architectures, and consuming different upstream source architectures (dimensional warehouses, normalized OLTP, Data Vault, pre-joined views, flat files).

---

## 1. Associative Engine Fundamentals

Qlik's associative engine links tables through field associations. Understanding this is the foundation for all data modeling decisions.

### How Associations Work

- **Automatic linking:** When two tables share a field name, Qlik automatically creates an association. No explicit JOIN statement is needed.
- **Single field per pair:** Each pair of tables should share exactly ONE field name. This single shared field is the key.
- **Selection propagation:** When a user selects a value in any field, that selection filters all associated tables. The propagation follows the association graph.
- **Global model:** All tables are automatically connected into a single associative model (unless explicitly disconnected via Generic database or data island techniques).
- **No explicit join order:** Qlik does not execute joins in sequence like SQL. All associations are evaluated simultaneously.

### The Field Naming Problem

Because tables associate through identically-named fields, field naming is a **structural decision**. An unprefixed `Status` field in both a Product table and an Order table creates an unintended association. This is silent—no error, no warning. Users select a product status, and order statuses are filtered automatically, producing incorrect results.

**Key principle:** Non-key fields must have unique names across the model (prefixed with their entity name using dot notation). Key fields must match exactly across tables that should associate.

---

## 2. Star Schema Design

Star schema—a fact table surrounded by dimension tables, each linked by a single key—is the foundation of Qlik data modeling.

- **Fact tables:** Event-oriented data with measures (quantities, amounts, counts). Often the largest table. Examples: Orders, OrderLine, Transactions, Sales.
- **Dimension tables:** Descriptive attributes (names, categories, hierarchies). Smaller, slower-changing. Examples: Product, Customer, Store, Date.
- **Grain:** The level of detail in a fact table (e.g., order line, daily sales). All facts in a table must share the same grain.
- **One key per dimension:** Each dimension links to the fact table through exactly one key field. If a dimension has multiple key fields needed by the fact, the model has a problem (likely requiring a link table).

### Field Naming in Star Schema

Every non-key field must be prefixed with its entity name using dot notation: `[Product.Category]`, `[Order.Status]`, `[Customer.Region]`. This prevents accidental associations and makes fields self-documenting. See `qlik-naming-conventions` skill for the full naming strategy.

### Bridge Tables for One-to-Many

When a dimension entity has a one-to-many attribute (a product with multiple categories, a customer with multiple email addresses), create a separate bridge table rather than concatenating or flattening. See `star-schema-patterns.md` for the complete pattern with "No Entry" rows.

### When to Flatten vs. Bridge

- **Bridge:** Use when an entity can have multiple values. If flattening requires an arbitrary dedup rule (e.g., "pick first"), that signals a bridge is needed.
- **Flatten:** Use when the relationship is genuinely 1:1 and the dedup rule is well-defined (e.g., "most recent address"). Implement via LEFT JOIN in the extraction or transform layer.

For detailed patterns, see `star-schema-patterns.md`.

---

## 3. Key Resolution Strategy

Choosing the right key type is critical for model correctness and performance. The decision framework below guides the choice.

### Natural Keys

Source provides reliable unique identifiers (customer ID, product ID, order number). **Pros:** Readable, debuggable, matches source. **Cons:** May contain PII, may not be truly unique across multiple sources, may be string (larger in memory).

**When to use:** Single-source models where the source provides stable, unique identifiers.

### Composite Keys

Concatenating multiple fields to form uniqueness (e.g., `source_id & '|' & record_id`). Use when no single field is unique. Construction pattern:

```qlik
AutoNumber(source_id & '|' & record_id) AS [%CompositeKey]
```

Or with hash for determinism:

```qlik
Hash128(source_id & '|' & record_id) AS [%CompositeKey]
```

The `%` prefix hides the key from end users via `SET HidePrefix = '%'`. See `qlik-naming-conventions` for the full convention.

**When to use:** Multi-source models where no single field uniquely identifies a record.

### Hash Keys

Using `Hash128()` or `Hash256()` to produce deterministic numeric keys. **Pros:** Deterministic across reloads (critical for incremental QVD patterns comparing keys), fixed size. **Cons:** Not human-readable.

**When to use:** When determinism across reloads is required (incremental loads need to compare keys to detect changes). Data Vault 2.0 hub keys often use hashes.

### AutoNumber Keys

Replaces string keys with sequential integers, reducing memory. **CRITICAL TRAP:** AutoNumber is non-deterministic across reloads. If load order changes, the same source record gets a different AutoNumber. This breaks incremental QVD patterns that rely on key stability.

```qlik
// BROKEN for incremental loads:
AutoNumber(source_id & '|' & record_id) AS [%CompositeKey]  // Changes on each reload!

// Use only in final model load for performance:
// Load from already-stable QVD, apply AutoNumber once, store result
```

**When to use:** Final model load ONLY, and only if you understand that the key will differ each reload. Never use AutoNumber in the QVD extraction layer.

### Decision Framework

| Scenario | Recommended | Rationale |
|----------|------------|-----------|
| Single source, unique identifier available | Natural key | Readable, matches source |
| Multiple sources, need composite uniqueness | Composite (hash or concat) | Only option for multi-source uniqueness |
| Incremental loads with key comparison needed | Hash128/256 | Deterministic across reloads |
| Final model load, large string keys, no incremental | AutoNumber | Memory optimization only |

---

## 4. Synthetic Key Prevention and Resolution

Synthetic keys occur when two tables share more than one field name. They degrade performance and produce unexpected aggregations.

### Common Causes

- **Technical fields in multiple tables:** `load_datetime`, `source_system`, `batch_id` present in multiple source tables.
- **Generic field names:** Unprefixed `Status`, `Code`, `Type`, `Name` appearing in multiple dimension tables.
- **Phantom fields from shared subroutines:** A subroutine with wildcard column lists injects unexpected fields.
- **RENAME FIELD operations:** `RENAME FIELD status TO account_status;` in one context, `RENAME FIELD status TO product_status;` in another, but the intermediate table already had status—result is ambiguous associations.

### Detection and Failure Mode

The data model viewer shows synthetic keys as dotted lines connecting table pairs with multiple shared fields. Query results become unpredictable: selecting a value propagates through multiple unintended associations, filtering more records than expected.

### Resolution Approaches

**Drop or rename non-key fields:** If `load_datetime` and `source_system` are metadata, not keys, drop them or prefix with table context.

```qlik
// WRONG: Multiple shared fields create synthetic keys
[Product]: LOAD product_id, load_datetime, source_system, name FROM product.qvd (qvd);
[Order]: LOAD order_id, load_datetime, source_system, order_total FROM order.qvd (qvd);

// RIGHT: Drop technical fields or prefix as entity attributes
[Product]: LOAD product_id, name FROM product.qvd (qvd);
[Order]: LOAD order_id, order_total FROM order.qvd (qvd);
```

**Use ApplyMap for lookups:** Instead of loading a lookup table that shares multiple fields, use ApplyMap to carry lookup values into the main table.

```qlik
// WRONG: Two tables share status_code and status_description
[OrderStatus]: LOAD order_id, status_code, status_description FROM status_ref.qvd (qvd);
[Order]: LOAD order_id, status_code FROM order.qvd (qvd);
// Result: Synthetic key from status_code + status_description

// RIGHT: ApplyMap the lookup
Map_Status: MAPPING LOAD status_code, status_description FROM status_ref.qvd (qvd);
[Order]: LOAD order_id, status_code, ApplyMap('Map_Status', status_code, Null()) AS [Order.Status]
FROM order.qvd (qvd);
```

**Prefix non-key fields with entity:** Use entity-prefix dot notation for all non-key fields.

```qlik
[Product]: LOAD product_id, name AS [Product.Name], status AS [Product.Status] FROM product.qvd (qvd);
[Order]: LOAD order_id, status AS [Order.Status] FROM order.qvd (qvd);
// No synthetic key: only product_id and order_id are shared
```

**Explicit column lists:** Instead of wildcards, load only intended columns. This prevents phantom fields.

```qlik
// WRONG: Wildcard from subroutine may load unexpected fields
[Result]: LOAD * FROM [_SubroutineOutput] (qvd);

// RIGHT: Explicit column list
[Result]: LOAD key_field, attribute1, attribute2 FROM [_SubroutineOutput] (qvd);
```

### QUALIFY / UNQUALIFY Strategy (from qlik-model.md)

QUALIFY prefixes all field names with `TableName.` to prevent unintended associations. However, it interacts poorly with fields already prefixed.

**When to use QUALIFY:**
- Loading multiple raw tables from source systems where fields like `status`, `code`, `type` would collide.
- Early-stage exploration scripts where the data model is not yet defined.

**When NOT to use QUALIFY:**
- When upstream processing already prefixed fields with entity notation (e.g., `Order.Status`, `Product.Category`). QUALIFY would produce `TableName.Order.Status` (double-prefix).
- When explicit column lists in each LOAD already prevent field name collisions.
- When key fields need to match across tables for association.

**If fields are already prefixed, skip QUALIFY:**

```qlik
// CORRECT: Upstream already prefixed all non-key fields.
// Explicit column list ensures only the key field is shared.
// Do NOT add QUALIFY—it would double-prefix.
[Orders]: LOAD order_id, [Order.Status], [Order.Amount] FROM order.qvd (qvd);
[OrderDetails]: LOAD order_id, [OrderDetail.Quantity] FROM orderdetail.qvd (qvd);
```

For detailed anti-patterns, see `anti-patterns.md`.

---

## 5. QVD Layer Architecture

QVD files (Qlik View Data) are binary storage optimized for load speed. Organizing QVDs into layers reduces coupling, enables incremental loads, and simplifies debugging.

### Three-Layer Pattern (Complex Projects)

| Layer | Purpose | Naming | Refresh | Content |
|-------|---------|--------|---------|---------|
| **Raw** | Extract from source, store as-is | Raw_*TableName*.qvd | Incremental by source | Source field names preserved, no transformations |
| **Transform** | Apply business rules, field renaming, data quality | Transform_*TableName*.qvd | Full refresh (depends on Raw) | Entity-prefixed fields, clean data, cross-source joins |
| **Model** | Final star schema assembly, composite key generation | Model_*TableName*.qvd | Full refresh (depends on Transform) | Star schema tables, mapping renames, ready for BI |

**When to use 3 layers:** Large data volumes, complex ETL, multiple consumers, incremental load patterns.

### Two-Layer Pattern (Simpler Projects)

Combine Raw + Transform into a single Extract layer:

| Layer | Purpose | Naming |
|-------|---------|--------|
| **Extract** | Load from source, apply light transforms, store | Extract_*TableName*.qvd |
| **Model** | Star schema assembly, field renames | Model_*TableName*.qvd |

**When to use 2 layers:** Small-to-medium data, simple model, single consumer.

### QVD Naming Conventions

See `qlik-naming-conventions` skill for full file naming conventions. Summary:
- Layer prefix + table name: `Raw_Orders.qvd`, `Transform_Product.qvd`
- Date stamp for incremental archive: `Raw_Orders_20260301.qvd`

### Optimization: QVD Optimized Read

Loading a QVD with no WHERE clause and no field transformations triggers **optimized read** (~100x faster than database). Preserve optimized read by:
- Simple field aliasing in LOAD: `LOAD customer_id AS [Customer.Key]` — still optimized
- NO WHERE clause
- NO preceding LOAD transformations
- NO Map() function calls

Any of these force **standard read** (still ~10x faster than database but slower than optimized):

```qlik
// Optimized read:
LOAD * FROM [lib://QVDs/Customers.qvd] (qvd);

// Optimized read (field rename allowed):
LOAD customer_id AS [Customer.Key], name AS [Customer.Name]
FROM [lib://QVDs/Customers.qvd] (qvd);

// Standard read (WHERE forces unpack):
LOAD * FROM [lib://QVDs/Customers.qvd] (qvd)
WHERE NOT EXISTS([Customer.Key]);
```

---

## 6. Multi-App Architecture

Single app vs. multi-app is a deployment decision with profound implications for scaling, team organization, and reload dependencies. The choice depends on data volume, model complexity, team size, and refresh requirements.

### Decision Framework

| Factor | Single App | QVD Gen/Con | Extract/Transform/Model/UI | Binary Load |
|--------|-----------|-----------|--------------------------|------------|
| **Data volume** | <1GB in memory | 1-10GB | >10GB | Shared model, <1GB per app |
| **Model complexity** | ≤10 tables | 10-30 tables | 30+ tables | Simple (shared model) |
| **Teams** | 1-2 developers | 1-3 teams (clear ownership) | 3+ teams | Separate concerns, 1 shared model |
| **Consumers** | 1-2 apps | 2-5 apps from same data | 5+ apps | Multiple dashboards, 1 model |
| **Refresh schedule** | All tables same cadence | Generator daily, consumers variable | Each layer independent | All consumers same cadence |

### Single App Pattern

All extraction, transformation, and modeling in one app. Suitable for small data, simple models, rapid prototyping.

**Pros:** Simplicity, no reload orchestration.
**Cons:** Scaling limited by single reload cycle time, hard to share model across teams.

### QVD Generator / Consumer Pattern

Most common multi-app pattern. Generator app(s) extract and transform data, store QVDs. Consumer app(s) load from QVDs to build distinct models or dashboards.

**Pros:** Source isolation (generator handles all source system connectivity), multiple consumers from one extract, consumers can have different refresh schedules and models.
**Cons:** Additional complexity, QVD storage management, reload orchestration.

For detailed architecture and reload dependencies, see `multi-app-architecture.md`.

### Extract / Transform / Model / UI Split

Four separate apps, each with a specific purpose:
1. **Extract app:** Loads from sources, stores Raw QVDs.
2. **Transform app:** Cleans data, applies business rules, stores Transform QVDs.
3. **Model app:** Builds star schema, stores Model QVDs (and may load them for validation, then drop).
4. **UI app:** Loads Model QVDs, builds dashboards and master items.

**When justified:** Very large data, complex ETL orchestration, multiple development teams, each owning a layer.

### Binary Load Pattern

Loads the entire in-memory model from another app: `binary [other_app_id];`. Must be the first statement in the script.

**Pros:** Eliminates QVD storage; consumer app shares exact model from generator.
**Cons:** All-or-nothing (cannot filter fields), no incremental load possible, generator reload triggers all consumers automatically.

For detailed patterns and reload dependency management, see `multi-app-architecture.md`.

---

## 7. Source Architecture Consumption

Different upstream architectures require fundamentally different consumption patterns. A normalized OLTP schema requires denormalization and transaction handling. A Data Vault 2.0 requires hub/link/satellite merge with dual-timestamp logic. Pre-joined views hide complexity and may drift.

### Architecture Types

| Type | Characteristics | Key Challenge | Qlik Strategy |
|------|-----------------|----------------|---------------|
| **Dimensional Warehouse** | Pre-built star schema, surrogate keys, possibly SCD Type 2 | Surrogate key stability, SCD handling | Use warehouse star schema directly or rebuild for Qlik |
| **Normalized OLTP** | Many tables, primary/foreign keys, designed for transactions | Denormalization, transaction handling | Join in SQL extract or Qlik transform layer |
| **Data Vault 2.0** | Hub/Link/Satellite structure, composite business keys, dual timestamps | Merge complexity, dual-timestamp incremental logic | Flatten hub/link/sat into dimensions, use dual-timestamp incremental |
| **Pre-Joined Views** | Materialized or on-demand views, grain may vary | Schema drift, hidden complexity, potential duplicates from joins | Validate schema, detect grain, deduplicate if needed |
| **Flat Files / CSV** | Delimiter-separated, may contain embedded delimiters, may have header issues | Format validation, encoding, file rotation | Header validation, delimiter handling, timestamp-based incremental detection |

For detailed patterns per architecture, see `source-consumption-patterns.md`.

---

## 8. Grain Alignment Across Multiple Fact Tables

When multiple fact tables at different grains share the same dimensions, connecting them directly produces incorrect aggregations. A daily fact and a monthly fact cannot both connect to the same date dimension.

### The Problem

```
Fact_Daily ----[Date.Key]----> Dim_Date
Fact_Monthly ----[Date.Key]----> Dim_Date

When user selects a date, both facts filter. But summing quantities across both facts
mixes daily and monthly data—double-counting or incorrect totals.
```

### Solutions

**Link Table Pattern:** Create a composite key unifying the grain:

```qlik
[_Link]:
LOAD DISTINCT [Date.Key], [Product.Key], 'Daily' AS [Fact.Type] RESIDENT [Fact_Daily]
CONCATENATE LOAD DISTINCT [Date.Key], [Product.Key], 'Monthly' AS [Fact.Type] RESIDENT [Fact_Monthly];

[Fact_Daily] -> [_Link] <- [Fact_Monthly]
[_Link] -> [Date.Key] -> Dim_Date
```

Users select from the grain they want (via [Fact.Type] filter) before aggregating.

**Concatenated Fact Table:** Union all facts into one table with a [Fact.Type] field:

```qlik
[Fact]:
LOAD [Date.Key], [Product.Key], Quantity AS [Fact.Quantity], 'Daily' AS [Fact.Type]
RESIDENT [Fact_Daily]
CONCATENATE LOAD [Date.Key], [Product.Key], Amount AS [Fact.Quantity], 'Monthly' AS [Fact.Type]
RESIDENT [Fact_Monthly];

[Fact] -> [Date.Key] -> Dim_Date
```

Business users filter by [Fact.Type] to choose which fact to aggregate.

**When to use each:**
- Link table: When facts share many dimension keys and need careful filtering logic.
- Concatenated fact: When facts have different granularities but common key structure (daily and monthly of the same metric).

For detailed patterns, see `star-schema-patterns.md`.

---

## 9. Circular Reference Detection and Resolution

Circular references occur when table A associates to B, B to C, and C back to A through shared fields.

### Common Scenario

Two fact tables both connect to the same two dimensions without a link table:

```
Fact_Daily ----[Product.Key]----> Dim_Product
  |
  +---[Store.Key]----> Dim_Store

Fact_Monthly ----[Product.Key]----> Dim_Product
  |
  +---[Store.Key]----> Dim_Store

Qlik finds two paths: Daily->Product->Monthly and Daily->Store->Monthly.
This circular reference is reported during reload, and the model may not behave predictably.
```

### How Qlik Reports It

- Reload warning: "Circular reference detected."
- Data model viewer shows the loop visually.

### Resolution

Use a link table to break the cycle:

```qlik
[_Link]:
LOAD DISTINCT [Product.Key], [Store.Key] RESIDENT [Fact_Daily]
CONCATENATE LOAD DISTINCT [Product.Key], [Store.Key] RESIDENT [Fact_Monthly];

[Fact_Daily] -> [_Link]
[Fact_Monthly] -> [_Link]
[_Link] -> [Product.Key] -> Dim_Product
[_Link] -> [Store.Key] -> Dim_Store
```

The link table decomposes the circular reference into a star with the link at the center.

**Alternative:** If the facts are truly independent, use Generic database or data islands to deliberately disconnect them. This is rarely the right answer in Qlik.

---

## Supporting Files

Detailed patterns, code examples, and decision frameworks are in the following supporting files:

- **`star-schema-patterns.md`** — Bridge tables with aliased EXISTS pattern, link tables, mapping tables via ApplyMap, normalized-over-wide pattern, HidePrefix/HideSuffix, dimension vs. fact classification.

- **`multi-app-architecture.md`** — Single app, QVD generator/consumer, extract/transform/model/UI split, binary load pattern, decision framework, reload dependency management.

- **`source-consumption-patterns.md`** — Dimensional warehouse consumption, normalized OLTP handling, Data Vault 2.0 hub/link/satellite merge with dual-timestamp incremental, pre-joined views schema drift detection, flat file validation and incremental patterns.

- **`anti-patterns.md`** — 10+ anti-patterns with specific failure modes and fixes: synthetic keys from generic names, AutoNumber in QVD layer, circular references, QUALIFY on pre-prefixed fields, multi-field associations, missing bridge tables, wide format expansion issues, source architecture ignorance, disconnected tables, over-modeling.

---

## Key Takeaways

1. **Field naming is structural.** Every non-key field must be unique across the model (entity-prefix dot notation). Key fields must match across tables that should associate.

2. **Synthetic keys are silent.** Qlik doesn't error when two tables share multiple fields. The data model viewer reveals the problem.

3. **One key per dimension.** Each dimension table links to facts through exactly one key field. More creates complexity; zero means data islands.

4. **QVD layers reduce coupling.** Raw/Transform/Model separation enables incremental loads and multi-consumer architectures.

5. **Source architecture determines consumption pattern.** Data Vault requires merge and dual-timestamp logic. OLTP requires denormalization. Dimensional warehouses may be consumed directly.

6. **Grain alignment matters.** Multiple fact tables at different grains need link tables or type flags to prevent incorrect aggregations.

7. **AutoNumber is a trap.** Non-deterministic across reloads, breaks incremental patterns. Use only in final model load.

8. **Multi-app architecture scales teams and data.** Generator/consumer pattern isolates sources and enables multiple consumers. Extract/Transform/Model/UI split is for very large, complex projects.
