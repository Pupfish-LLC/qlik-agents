---
name: qlik-naming-conventions
description: "Field naming with entity-prefix dot notation, table naming, variable naming (v prefix), expression naming, file naming (.qvs, QVD), key field conventions (% prefix, HideSuffix), cross-layer field mapping from source through extract/transform/model to UI, field rename layer using Mapping RENAME, variable-to-field-name alignment, and naming anti-patterns. Load when naming, renaming, prefixing, aliasing, or mapping fields, tables, variables, or expressions in Qlik Sense."
---

## Qlik Sense Naming Conventions

Naming in Qlik Sense is not cosmetic. The associative engine links tables through identically-named fields. Every field name is a potential association. An unprefixed `Status` field in two tables silently links them, producing synthetic keys or incorrect aggregations with no error message. Naming IS data modeling.

The single most important rule: **prefix every non-key field with its entity name using dot notation** (`Product.Category`, `Order.Status`). This one convention prevents the majority of accidental associations, makes fields self-documenting in filter panes, and eliminates the need for QUALIFY on pre-prefixed fields.

This skill covers field naming, key field naming, table naming, variable naming, expression naming, file naming, and the cross-layer naming strategy that traces a field from source system through every ETL layer to the UI.

## 1. Field Naming

### Entity-Prefix Dot Notation

All non-key fields use `Entity.Attribute` format:

```qlik
// CORRECT: Entity-prefixed fields prevent accidental associations
[Product.Category], [Product.Name], [Order.Status], [Customer.Region]
```

Why this works:
- Prevents accidental associations between tables that happen to share attribute names
- Makes fields self-documenting in filter panes and self-service content (users see `Product.Category`, not just `Category`)
- Eliminates the need for QUALIFY on pre-prefixed fields

When to use: all non-key fields in the data model.
When NOT to use: key fields intended to link tables. Keys must match exactly across tables to form associations.

### Anti-Pattern: Unprefixed Fields

```qlik
// WRONG: Both tables have a field called "Status"
Product:
LOAD product_key, Status FROM products.qvd (qvd);

Orders:
LOAD order_key, product_key, Status FROM orders.qvd (qvd);
// RESULT: Qlik silently associates Product and Orders through BOTH
// product_key AND Status, creating a synthetic key. Selections on
// "Status" in a filter pane now filter both tables simultaneously,
// producing incorrect counts. No error is raised.
```

Fix: rename to `[Product.Status]` and `[Order.Status]`.

### Field Name Character Rules

- **Square brackets** enclose field names with spaces, dots, or special characters: `[Order.Ship Date]`
- Dot notation IS allowed in field names. The dot is just a character, not a property accessor.
- **Case sensitivity:** Field names are case-insensitive for association purposes but preserve case for display. `Product.Category` and `product.category` will associate, but the display shows whichever was loaded first.
- **Avoid these characters in field names:** `=`, `;`, curly braces `{}`, and square brackets inside field names (use them only as delimiters). Dollar sign `$` is reserved for system fields (`$Table`, `$Field`).
- **Avoid script keywords as unquoted field names.** If unavoidable, enclose in square brackets: `[Select]`, `[Set]`, `[Load]`. See `naming-reference.md` for the complete reserved word list.
- Double quotes can also delimit field names (`"Product.Category"`), but square brackets are the Qlik convention.

## 2. Key Field Naming

Key fields link tables. They must match EXACTLY across every table that shares them. Never alias or prefix a key field differently in different tables.

### Composite Keys

Composite keys created in the DataModel layer use the `%` prefix, hidden from end users by `HidePrefix`:

```qlik
SET HidePrefix = '%';

// Creating a composite key
LOAD *,
    [Store.Region] & '|' & [Store.District] AS [%ScopeKey]
RESIDENT [_SomeTable];
```

### Source System Keys

Source system keys use a consistent suffix convention, hidden by `HideSuffix`:

```qlik
SET HideSuffix = '_key';

// Source keys like product_key, order_key, customer_key are hidden
// from users but remain available for associations in the data model
```

Both `HidePrefix` and `HideSuffix` can coexist in the same script.

### Anti-Pattern: Inconsistent Key Names

```qlik
// WRONG: Key named differently in each table
Product:
LOAD product_id, [Product.Name] FROM products.qvd (qvd);

OrderLine:
LOAD orderline_key, prod_key, [OrderLine.Qty] FROM orderlines.qvd (qvd);
// RESULT: No association between Product and OrderLine.
// Qlik only links through identical field names.
// product_id != prod_key, so the tables are islands.
```

Fix: use `product_key` in both tables, or rename during load so the key field has one consistent name.

## 3. Table Naming

### Conventions

- **Dimension tables:** Descriptive singular nouns: `Product`, `Customer`, `Store`, `Calendar`
- **Fact tables:** Action or event nouns: `Orders`, `OrderLine`, `Transactions`, `Returns`
- **Temp/working tables:** `_` prefix signals "must be dropped before model is complete": `_RawProducts`, `_TransformStaging`
- **Mapping tables:** `Map_` prefix: `Map_CategoryDesc`, `Map_StatusCode`
- **Bridge tables:** Descriptive of the relationship: `ProductCategory`, `CustomerSegment`
- Table names with spaces require square brackets: `[Order Details]`

### Anti-Pattern: Undropped Temp Tables

```qlik
// WRONG: Temp table loaded but never dropped
_StagingProducts:
LOAD * FROM staging.qvd (qvd);

// ... processing continues, but _StagingProducts is never dropped
// RESULT: _StagingProducts appears in the data model, sharing fields
// with the final Product table, creating synthetic keys. The _
// prefix is just a naming hint; Qlik does not auto-drop these.
```

Fix: always `DROP TABLE [_StagingProducts];` after its data has been consumed.

## 4. Variable Naming

### Conventions

- All variables use `v` prefix: `vTotalRevenue`, `vCustomerRegion`, `vCurrentPeriod`
- Use `SET` for expression templates (formulas stored as text, expanded at evaluation time via dollar-sign expansion)
- Use `LET` for computed values (evaluated once at script runtime)
- This skill covers naming only. The `qlik-load-script` skill covers SET vs. LET behavioral mechanics.

### Two Types of Variables

Variables serve two distinct purposes, and the naming convention (`v` prefix) applies to both:

- **Field-reference variables** abstract a field name for maintainability: `SET vCustomerRegion = [Customer.Region];`. If the field is renamed, you update one variable instead of dozens of expressions.
- **Expression variables** contain aggregation logic: `SET vTotalRevenue = Sum([OrderLine.Revenue]);`. These are the building blocks for master measures and calculated KPIs.

Both types must reference final DataModel layer field names (see Section 7).

### Variable-to-Field-Name Alignment

Expression variables must reference final **UI field names**, not intermediate layer names:

```qlik
// CORRECT: Variable references the final DataModel layer field name
SET vCustomerRegion = [Customer.Region];

// WRONG: Variable references the Transform layer name
SET vCustomerRegion = [Account.Region];
// After Mapping RENAME, [Account.Region] no longer exists.
// The expression evaluates to NULL with no error.
```

Pattern: `v` + entity name + attribute name. `vCustomerRegion` references `[Customer.Region]`. The naming makes the connection obvious.

### When to Use Variable Indirection

- Fields referenced in expressions get variables (`vCustomerRegion`, `vTotalRevenue`)
- Fields used only in filter panes or simple selections get direct references
- If a field appears in 3+ expressions, wrap it in a variable for maintainability

## 5. Expression Naming

### Master Measures

Business-readable names: `Total Revenue`, `Order Count`, `Avg Order Value`, `Return Rate`

Backed by variables following the pattern: master measure `Total Revenue` uses variable `vTotalRevenue`.

### Master Dimensions

Descriptive of what the user sees: `Product Category`, `Customer Region`, `Order Month`

### Calculated Dimensions

Prefix with context when the dimension is derived: `Revenue Tier`, `Order Size Group`, `Customer Segment`

## 6. File Naming

### Script Files (.qvs)

Numeric prefix for execution order within an app:

```
01_Config.qvs           -- Variables, connections, environment setup
02_Extract_Orders.qvs   -- Source extraction per system
03_Extract_Products.qvs
04_Transform.qvs        -- Cross-source joins, business rules, data quality
05_QVD_Generate.qvs     -- Store transformed tables to QVD
06_Model_Load.qvs       -- Star schema assembly, field rename layer
07_Calendar.qvs         -- Master calendar generation
08_Variables.qvs        -- Expression variable definitions
09_SectionAccess.qvs    -- Security scaffold
10_Diagnostics.qvs      -- Post-load validation queries
```

For multi-app architectures, each app has its own script set with the app name or purpose as a directory.

### QVD Files

Layer prefix + table name, optionally with date stamp for incremental loads:

```
Raw_Orders.qvd              -- Extract layer, raw source data
Transform_Product.qvd       -- Transform layer, cleaned and joined
Model_Product.qvd           -- Model layer, final star schema table
Raw_Orders_20260301.qvd     -- Date-stamped for incremental archive
```

## 7. Cross-Layer Naming Strategy

This is the hardest naming problem. A field's name changes as it flows from the source system through extraction, transformation, data modeling, and UI display. Getting this wrong means expressions reference nonexistent fields, rename layers silently drop data, and developers waste hours tracing field lineage.

### The Layers

| Layer | Naming Rule | Example |
|-------|-------------|---------|
| **Source** | Whatever the source system uses | `cust_region` |
| **Extract** | Preserve source names exactly (raw QVD, no transformation) | `cust_region` |
| **Transform** | Apply entity-prefix using the internal entity name | `Account.Region` |
| **DataModel** | Rename if business entity differs from internal entity | `Customer.Region` |
| **UI** | Direct field reference or variable indirection | `$(vCustomerRegion)` |

### Concrete Examples

| Source Field | Extract Layer | Transform Layer | DataModel Layer | UI Display |
|--------------|---------------|-----------------|-----------------|------------|
| `category_name` (dim_product) | `category_name` (raw QVD) | `Product.Category` | `Product.Category` (no rename needed) | Direct field reference |
| `cust_region` (dim_account) | `cust_region` (raw QVD) | `Account.Region` | `Customer.Region` | Via `$(vCustomerRegion)` |
| `order_status_code` (fact_orders) | `order_status_code` (raw QVD) | `Order.Status` (via ApplyMap lookup) | `Order.Status` | Direct field reference |
| `tags` (dim_product) | `tags` (raw QVD) | `Product.Tag` (SubField expansion, bridge table `ProductTag`) | `Product.Tag` | Direct field reference |

What these examples show:
- **Extract preserves source names.** No renaming at extraction. The raw QVD is a faithful copy.
- **Transform applies entity-prefix** using the internal/technical entity name (`Account`, `Product`, `Order`).
- **DataModel may rename** when the business entity name differs (`Account` -> `Customer`). This is done via Mapping RENAME, not by reloading the table.
- **UI adds variable indirection** for fields commonly used in expressions. Simple display-only fields use direct references.
- **Not every field changes at every layer.** `Product.Category` passes through DataModel unchanged because the business already calls it "Product."
- **Structural transformations** can change cardinality, not just names. A delimited `tags` field expands via SubField into a bridge table `ProductTag` with fields `product_key` and `Product.Tag`. One source field becomes two tables.

### The Field Rename Layer (Mapping RENAME)

When business entity names differ from internal names, use `Mapping RENAME` at the DataModel layer boundary:

```qlik
FieldMap:
Mapping LOAD old_name, new_name INLINE [old_name, new_name
Account.Region, Customer.Region
Account.Name, Customer.Name
Account.Segment, Customer.Segment
Account.Join Date, Customer.Join Date
Account.Email, Customer.Email
Account.City, Customer.City
];
Rename Fields using FieldMap;
```

**When to use Mapping RENAME:**
- The business calls the entity something different than the technical model (`Account` vs. `Customer`)
- You need to align field names with an existing app's conventions in a brownfield project

**When NOT to use:**
- The entity name is already correct. Do not rename for the sake of renaming.
- Key fields. Never rename keys through Mapping RENAME; it breaks associations if not done consistently across all tables.

**Why Mapping RENAME over Resident reload:** Declarative, low memory cost, no table duplication. A Resident reload copies the entire table in memory just to rename fields.

### Variable-to-Field-Name Mapping

Variables that wrap field references must use the **final DataModel layer name**, not any intermediate layer name:

```qlik
// CORRECT: Uses the post-rename DataModel name
SET vCustomerRegion = [Customer.Region];
SET vCustomerSegment = [Customer.Segment];

// WRONG: Uses the Transform layer name (pre-rename)
SET vCustomerRegion = [Account.Region];
// After Mapping RENAME, [Account.Region] no longer exists.
// The expression evaluates to NULL with no error.
```

For extended cross-layer naming walkthrough with additional examples, see `naming-reference.md` in this skill directory.

## 8. Anti-Pattern Summary

| Anti-Pattern | Failure Mode | Fix |
|-------------|--------------|-----|
| Unprefixed non-key fields (`Status` in multiple tables) | Silent synthetic key; incorrect cross-table filtering | Prefix with entity: `Product.Status`, `Order.Status` |
| Inconsistent key names across tables (`product_id` vs. `prod_key`) | Broken association; tables become islands | Use one consistent key name everywhere |
| QUALIFY on already-prefixed fields | Double-prefix: `TableName.Product.Category` | Skip QUALIFY when fields are already entity-prefixed |
| Temp tables without `_` prefix left in model | Extra tables sharing fields, causing synthetic keys | Use `_` prefix AND always DROP after use |
| Variables referencing intermediate layer field names | Expression evaluates to NULL after Mapping RENAME | Always reference final DataModel layer names |
| Field names colliding with script keywords | Parse errors or unpredictable behavior | Enclose in square brackets: `[Set]`, or rename |
| Using `$` prefix for non-system fields | Collision with Qlik system fields | Reserve `$` for system fields only |

For extended cross-layer naming walkthrough with additional examples, Qlik reserved word list, and character restriction reference, see `naming-reference.md` in this skill directory.
