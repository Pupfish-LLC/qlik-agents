# Qlik Data Modeling Anti-Patterns

Common data modeling mistakes with specific failure modes and fixes.

---

## 1. Synthetic Keys from Generic Field Names

### The Wrong Way

```qlik
[Product]:
LOAD product_id, Status, Code, Type FROM product.qvd (qvd);

[Order]:
LOAD order_id, product_id, Status, Code, Type FROM order.qvd (qvd);
```

### Why It's Wrong

Both tables have `Status`, `Code`, and `Type` fields. Qlik silently creates synthetic keys linking Product and Order through ALL THREE FIELDS. The data model viewer shows a dotted line between the tables with "SyntheticKey" label.

**Failure mode:** Users select a product status, and order statuses are filtered unintentionally. Aggregations across both tables produce incorrect results. No error is raised; it appears to work until users discover inconsistent filtering.

### Detection

- Open the data model viewer; look for dotted lines indicating synthetic keys.
- Run a test selection: filter on product status, check if order rows disappear unexpectedly.
- Check field counts: if two tables share more than one field name, synthetic key is likely.

### The Fix

Prefix non-key fields with entity names:

```qlik
[Product]:
LOAD
    product_id,
    Status AS [Product.Status],
    Code AS [Product.Code],
    Type AS [Product.Type]
FROM product.qvd (qvd);

[Order]:
LOAD
    order_id,
    product_id,
    Status AS [Order.Status],
    Code AS [Order.Code],
    Type AS [Order.Type]
FROM order.qvd (qvd);
```

Now only `product_id` is shared, and no synthetic key is created.

---

## 2. AutoNumber in QVD Layer

### The Wrong Way

```qlik
// In Extract/Raw layer (storing to QVD)
[_RawOrder]:
LOAD
    AutoNumber(source_order_id & '|' & source_line_num) AS order_key,
    order_amount
FROM [source.qvd] (qvd);

STORE [_RawOrder] INTO [Raw_Order.qvd] (qvd);
```

### Why It's Wrong

AutoNumber assigns sequence numbers based on load order. Each reload reassigns numbers differently (if load order changes). The next day's reload produces different order_key values for the same source records.

**Failure mode:** Incremental load pattern tries to match old and new keys, finds no matches, and loads everything as new. Duplicates accumulate. Row counts grow indefinitely while no new source records exist.

### Detection

- Load Raw QVD, then reload and load again. Check if order_key values changed for the same records.
- Check row counts over time: rapid, unexplained growth indicates duplicate loading.

### The Fix

Use hash keys instead (deterministic) or defer AutoNumber to the final Model load:

```qlik
// OPTION 1: Use Hash (deterministic)
[_RawOrder]:
LOAD
    Hash128(source_order_id & '|' & source_line_num) AS order_key,
    order_amount
FROM [source.qvd] (qvd);

STORE [_RawOrder] INTO [Raw_Order.qvd] (qvd);

// OPTION 2: Defer AutoNumber to Model load (final consumption)
[Model_Order]:
LOAD
    AutoNumber(order_key) AS [%OrderKey],  // Non-deterministic, but Model QVD is not incremental
    order_amount
FROM [Transform_Order.qvd] (qvd);
```

Hash keys are deterministic; AutoNumber only belongs in the final model load.

---

## 3. Circular References from Multi-Fact Models

### The Wrong Way

```qlik
[Fact_Daily]:
LOAD
    [Date.Key],
    [Product.Key],
    [Store.Key],
    daily_amount
FROM [daily_sales.qvd] (qvd);

[Fact_Monthly]:
LOAD
    [Date.Key],
    [Product.Key],
    [Store.Key],
    monthly_amount
FROM [monthly_sales.qvd] (qvd);

// Both facts link to the same dimensions:
[Date]: LOAD [Date.Key], month_year FROM [dim_date.qvd] (qvd);
[Product]: LOAD [Product.Key], category FROM [dim_product.qvd] (qvd);
[Store]: LOAD [Store.Key], region FROM [dim_store.qvd] (qvd);
```

### Why It's Wrong

Qlik detects two paths from Daily to Monthly: Daily -> Date -> Monthly and Daily -> Product -> Monthly and Daily -> Store -> Monthly. Circular reference warning on reload. Filtering behavior becomes unpredictable.

**Failure mode:** Reload succeeds with warning. Users select a date, and both daily and monthly facts filter (producing mixed granularities and incorrect totals).

### Detection

- Reload produces: "Circular reference detected."
- Data model viewer shows a loop visually.
- Test: select a date, check if both facts change (they should be independent or linked via a link table).

### The Fix

Create a link table to break the circle:

```qlik
[_Link]:
LOAD DISTINCT [Date.Key], [Product.Key], [Store.Key] RESIDENT [Fact_Daily]
CONCATENATE LOAD DISTINCT [Date.Key], [Product.Key], [Store.Key] RESIDENT [Fact_Monthly];

// Drop original fact associations
DROP TABLE [Fact_Daily], [Fact_Monthly];

// Recreate facts with link table as intermediary
[Fact_Daily]:
LOAD [Date.Key], [Product.Key], [Store.Key], daily_amount FROM [daily_sales.qvd] (qvd);

[Fact_Monthly]:
LOAD [Date.Key], [Product.Key], [Store.Key], monthly_amount FROM [monthly_sales.qvd] (qvd);

// Link table is the hub; facts and dimensions radiate from it
```

Now facts associate to Link, and Link associates to dimensions. No circular reference.

---

## 4. QUALIFY on Pre-Prefixed Fields

### The Wrong Way

```qlik
// Fields already have entity prefix: [Customer.Name], [Order.Status]
[Customer]: LOAD customer_id, [Customer.Name] FROM customer.qvd (qvd);
[Order]: LOAD order_id, customer_id, [Order.Status] FROM order.qvd (qvd);

// But someone adds QUALIFY to prevent synthetic keys:
QUALIFY *;
UNQUALIFY customer_id, order_id;
```

### Why It's Wrong

QUALIFY prepends the table name to all fields. `[Customer.Name]` becomes `[Customer.Customer.Name]`. Field references in expressions now fail because the UI field is `[Customer.Customer.Name]`, not `[Customer.Name]`.

**Failure mode:** Expressions evaluate to NULL. Dashboard cells show "-" (no data). No error is raised; it's silent.

### Detection

- Data model viewer shows field names like `[Customer.Customer.Name]` (double-prefix).
- Expressions reference `[Customer.Name]`, which no longer exists.

### The Fix

Skip QUALIFY if fields are already prefixed. Explicit column lists in LOAD prevent synthetic keys without QUALIFY:

```qlik
// CORRECT: No QUALIFY, explicit column lists ensure only one shared field
[Customer]:
LOAD
    customer_id,
    [Customer.Name],
    [Customer.Region]
FROM customer.qvd (qvd);

[Order]:
LOAD
    order_id,
    customer_id,     // Only this field is shared
    [Order.Status],
    [Order.Amount]
FROM order.qvd (qvd);
```

The explicit column lists prevent synthetic keys without QUALIFY.

---

## 5. Star Schema with Multiple Shared Fields

### The Wrong Way

```qlik
[Order]:
LOAD
    order_id,
    [Order.Amount]
FROM order.qvd (qvd);

[OrderDetail]:
LOAD
    order_id,
    detail_id,
    [Detail.Quantity]
FROM orderdetail.qvd (qvd);

// Both tables share order_id. To make OrderDetail link to Order,
// a developer adds another "linking" field (synthetic key!):

CONCATENATE([OrderDetail])
LOAD order_id, 1 AS [Link], quantity FROM temp;
// Now OrderDetail and Order share order_id AND Link
```

### Why It's Wrong

"For convenience," two tables share multiple fields. This always creates synthetic keys. The "Link" field was intended to force a connection, but it creates an unintended synthetic association through both fields.

**Failure mode:** Synthetic key degrades performance. Qlik must evaluate both shared fields, not just the intended key.

### Detection

- Data model viewer shows synthetic key (dotted line with two+ shared fields).

### The Fix

Keep ONE key between tables:

```qlik
[Order]:
LOAD
    order_id,
    [Order.Amount]
FROM order.qvd (qvd);

[OrderDetail]:
LOAD
    order_id,
    detail_id,
    [Detail.Quantity]
FROM orderdetail.qvd (qvd);

// Just one shared field: order_id. No synthetic key.
```

---

## 6. Missing Bridge Table for One-to-Many

### The Wrong Way

```qlik
// A product can have multiple categories (one-to-many)
// But developer flattens to one row per product:

[Product]:
LOAD
    product_id,
    product_name,
    Concat(DISTINCT category, ', ') AS categories_list  // Flattened!
FROM [raw_product.qvd] (qvd);

[ProductCategory]:
LOAD product_id, category FROM [raw_product_category.qvd] (qvd);
```

### Why It's Wrong

The `categories_list` field concatenates all categories for a product into a single string. The ProductCategory table still exists (redundant). Users cannot filter by individual categories from the string field; the string is display-only.

**Failure mode:** Users select "Electronics" from filter pane and expect products in that category to show. But the string match `categories_list LIKE '*Electronics*'` is fragile and doesn't match products in "Electronics Accessories."

### Detection

- Check if a dimension has been concatenated into a single field (comma-separated list).
- Check if the same data exists as separate table (redundancy).

### The Fix

Create a bridge table instead:

```qlik
// Bridge table: one row per product-category pair
[ProductCategory]:
LOAD DISTINCT
    product_id,
    category AS [Product.Category]
FROM [raw_product_category.qvd] (qvd);

[Product]:
LOAD DISTINCT
    product_id,
    product_name
FROM [raw_product.qvd] (qvd);

// Product -> product_id -> ProductCategory
// Users select a category, ProductCategory filters, Product shows matching products
```

---

## 7. Wide Format for Expanding Dimensions

### The Wrong Way

```qlik
// Coverage flags for sources (hard-coded columns)
[EntitySourceCoverage]:
LOAD
    entity_id,
    In_Source_A,    // 1 or 0
    In_Source_B,    // 1 or 0
    In_Source_C     // 1 or 0
FROM coverage.qvd (qvd);

// Expressions reference individual columns:
// Sum({<In_Source_A = {1}>} Amount)
```

### Why It's Wrong

When a new source (Source D) is added, the script must be updated:
- SQL query: add source_d column
- Qlik LOAD: add In_Source_D field
- All expressions: update conditions to include Source D

Every new dimension requires changes in multiple places. Wide format is brittle and does not scale.

**Failure mode:** Source D data is loaded but excluded from aggregations because expressions still reference A, B, C only.

### Detection

- Hard-coded column names in script (Source_A, Source_B, Source_C).
- Expressions with explicit conditions for each column (IF(In_Source_A, ...) OR IF(In_Source_B, ...)).

### The Fix

Use normalized (long) format:

```qlik
// Normalized: one row per entity-source pair
[EntitySourceCoverage]:
LOAD DISTINCT
    entity_id,
    source_name AS [Source.Name]
FROM coverage_normalized.qvd (qvd);

// Expressions are simple and stable:
// Sum(Amount)  -- automatically sums across all sources
// Users filter by [Source.Name] instead
```

New sources appear automatically without script changes.

---

## 8. Ignoring Source Architecture

### The Wrong Way

```qlik
// Developer treats all sources the same:

// Data Vault (hub/link/satellite structure):
[Customer]:
LOAD customer_hub_key, business_key FROM dv_customer_hub.qvd (qvd);

[CustomerAttributes]:
LOAD customer_hub_key, [Customer.Name], effective_from, effective_to
FROM dv_customer_sat.qvd (qvd);

// But loads as-is without merging hub/satellite:
// Result: Two tables with only customer_hub_key shared
// Users cannot see both hub key and attributes together (missing merge)

// OLTP (normalized, transaction-oriented):
[Order]:
LOAD order_id, customer_id, amount FROM oltp_order.qvd (qvd);

[OrderLine]:
LOAD order_id, line_id, product_id, quantity FROM oltp_orderline.qvd (qvd);

// But doesn't denormalize; left as-is
// Result: Many small tables, complex navigation, users need manual joins
```

### Why It's Wrong

Different source architectures require different consumption patterns:
- **Data Vault** requires merge of hubs and satellites into dimensions.
- **OLTP** requires denormalization into star schema.
- **Dimensional warehouse** can be loaded directly.
- **Flat files** require deduplication and grain validation.

Ignoring the source architecture produces incomplete or brittle models.

**Failure mode:** Data Vault attributes don't link correctly (missing merge). OLTP requires too many user joins. Pre-joined views have wrong grain (undetected duplicates).

### Detection

- Does the model structure match the source? (e.g., Data Vault hub + satellites merged into dimensions?)
- Are there redundant tables (flattened relationships that should have been left as lookup)?

### The Fix

Identify the source architecture and apply the correct consumption pattern:

```qlik
// Data Vault: Merge hub + satellite into dimension
[_Hub]: LOAD customer_hub_key, business_key FROM dv_customer_hub.qvd (qvd);
[_Sat]: LOAD customer_hub_key, [Customer.Name], effective_from, effective_to
FROM dv_customer_sat.qvd (qvd);

[Customer]:
LOAD
    [_Hub].customer_hub_key,
    [_Hub].business_key,
    [_Sat].[Customer.Name],
    [_Sat].effective_from,
    [_Sat].effective_to
RESIDENT [_Hub]
LEFT JOIN (_Sat) ON [_Hub].customer_hub_key = [_Sat].customer_hub_key;

DROP TABLES [_Hub], [_Sat];

// OLTP: Denormalize and create star schema
[Customer]:
LOAD customer_id, [Customer.Name], [Customer.Region] FROM oltp_customer.qvd (qvd);

[Order]:
LOAD
    order_id,
    customer_id,
    [Order.Amount]
FROM oltp_order.qvd (qvd) INNER JOIN customer_data;
```

---

## 9. Disconnected Tables (Data Islands)

### The Wrong Way

```qlik
[Sales]:
LOAD product_id, amount FROM sales.qvd (qvd);

[Product]:
LOAD product_id, name FROM product.qvd (qvd);

[Budget]:
LOAD budget_id, amount FROM budget.qvd (qvd);
// Budget has no key linking it to Sales or Product
```

### Why It's Wrong

Budget table has no shared key with other tables. Qlik cannot propagate selections to it. The Budget table is an island; selections on Product or Sales don't filter Budget.

**Failure mode:** Users select a product and expect budget to reflect that product's budget. Instead, budget remains constant (doesn't filter).

### Detection

- Data model viewer shows tables in separate clusters (no connecting lines).
- Selections on one cluster don't affect the other cluster.

### The Fix

Add a link key:

```qlik
[Sales]:
LOAD product_id, amount FROM sales.qvd (qvd);

[Product]:
LOAD product_id, name FROM product.qvd (qvd);

[Budget]:
LOAD product_id, budget_amount FROM budget.qvd (qvd);
// Now Budget shares product_id with Product and Sales
```

All tables now associate through product_id.

---

## 10. Over-Modeling

### The Wrong Way

```qlik
// Tiny lookup tables created as full tables:

[StatusCode]:
LOAD status_code, status_description FROM status_ref.qvd (qvd);

[OrderStatus]:
LOAD order_id, status_code FROM order.qvd (qvd);

// Separate table created just to map status codes to descriptions
// Adds complexity without benefit
```

### Why It's Wrong

A lookup table with only two fields (code, description) adds a full table to the data model for minimal benefit. It reduces flexibility: users must filter on status_code to affect status_description. ApplyMap is simpler.

**Failure mode:** Model complexity grows unnecessarily. The status_code table may cause synthetic keys if field names collide. Performance overhead from extra association.

### Detection

- Tables with 2-3 fields that are purely lookup mappings.
- No filtering needed on lookup attributes (users don't care about status codes, only descriptions).

### The Fix

Use ApplyMap instead:

```qlik
[Map_Status]: MAPPING LOAD status_code, status_description FROM status_ref.qvd (qvd);

[Order]:
LOAD
    order_id,
    status_code,
    ApplyMap('Map_Status', status_code, 'Unknown') AS [Order.Status]
FROM order.qvd (qvd);

DROP TABLE status_ref;
```

One fewer table in the model, simpler script, same functionality.

---

## 11. Missing "No Entry" Rows in Bridge Tables

### The Wrong Way

```qlik
// Bridge table for products with categories
[ProductCategory]:
LOAD product_id, category FROM raw_product_category.qvd (qvd);

// But a product with no categories is excluded
// When user selects a category, that product disappears entirely
```

### Why It's Wrong

If a product has no categories, it doesn't appear in ProductCategory. When a user selects a category, the bridge filters to matching products, and products without categories are not shown (they have no bridge row).

**Failure mode:** Users see incomplete product lists. Products without categories seem to disappear when category is selected.

### Detection

- Row counts: COUNT(DISTINCT product_id) in bridge != COUNT(DISTINCT product_id) in Product.
- Test: select a category, check if all products are visible.

### The Fix

Add "No Entry" rows for missing attributes:

```qlik
[_Bridge]:
LOAD product_id, category FROM raw_product_category.qvd (qvd);

[_HasCategory]:
LOAD DISTINCT product_id AS _has_cat RESIDENT [_Bridge];

[ProductCategory]:
LOAD * RESIDENT [_Bridge]
CONCATENATE LOAD DISTINCT product_id, 'No Entry' AS category
FROM [Product] WHERE NOT EXISTS(_has_cat, product_id);

DROP TABLE [_HasCategory];
```

Now all products appear, with "No Entry" for missing categories.

---

## 12. Incorrect Grain Alignment

### The Wrong Way

```qlik
[Fact_Daily]:
LOAD [Date.Key], [Product.Key], daily_amount FROM daily_sales.qvd (qvd);

[Fact_Monthly]:
LOAD [Date.Key], [Product.Key], monthly_amount FROM monthly_sales.qvd (qvd);

[Dim_Date]:
LOAD [Date.Key], date, month FROM dim_date.qvd (qvd);

// Both facts connect to the same date dimension
// Selecting a date filters both facts
// Summing daily_amount + monthly_amount produces mixed granularities
```

### Why It's Wrong

Daily and monthly facts have different grains. Connecting both to the same dimension produces incorrect aggregations: daily amounts repeat for each day in the month while monthly amount is constant, creating overstatement.

**Failure mode:** Sum by month produces wildly incorrect numbers (daily amounts counted multiple times).

### Detection

- Two fact tables with different logical grains (daily, monthly, weekly).
- Both linking to the same dimension (date, product).

### The Fix

Use a link table or type field:

```qlik
[_Link]:
LOAD DISTINCT [Date.Key], [Product.Key], 'Daily' AS [Fact.Type]
RESIDENT [Fact_Daily]
CONCATENATE LOAD DISTINCT [Date.Key], [Product.Key], 'Monthly' AS [Fact.Type]
RESIDENT [Fact_Monthly];

[Fact_Daily]:
LOAD [Date.Key], [Product.Key], daily_amount FROM daily_sales.qvd (qvd);

[Fact_Monthly]:
LOAD [Date.Key], [Product.Key], monthly_amount FROM monthly_sales.qvd (qvd);

[Dim_Date]:
LOAD [Date.Key], date, month FROM dim_date.qvd (qvd);

// Link table intermediates the association
// Users filter by [Fact.Type] to choose which fact to aggregate
```

Or concatenate facts with type field and filter on type.

---

## Summary Table

| Anti-Pattern | Failure Mode | Detection | Fix |
|--------------|-------------|-----------|-----|
| Synthetic keys from generic names | Silent unintended filtering, incorrect aggregations | Data model viewer: dotted line, multiple shared fields | Entity-prefix non-key fields |
| AutoNumber in QVD layer | Non-deterministic keys break incremental loads, duplicates accumulate | Reload twice, check keys differ | Use Hash or defer AutoNumber |
| Circular references | Unpredictable filtering, reload warning | Reload message "Circular reference" | Add link table |
| QUALIFY on pre-prefixed fields | Expressions evaluate to NULL | Data model: double-prefix fields | Skip QUALIFY on pre-prefixed fields |
| Multiple shared fields | Synthetic key performance penalty | Data model viewer | Keep one key between table pairs |
| Missing bridge table | Data loss for one-to-many relationships | Hard-coded fields, arbitrary "first" selection | Create bridge table |
| Wide format expansion | Script breaks when dimensions grow | Hard-coded column names | Use normalized (long) format |
| Ignoring source architecture | Incomplete or incorrect model (missing merges, wrong structure) | Model structure doesn't match source | Apply source-specific consumption pattern |
| Disconnected tables | Selections don't propagate between clusters | Data model shows separate islands | Add shared key field |
| Over-modeling | Unnecessary complexity, model bloat | Tiny lookup tables (2-3 fields) | Use ApplyMap instead |
| Missing "No Entry" rows | Products/dimensions disappear during filtering | Row count mismatch between bridge and parent | Add "No Entry" rows via aliased EXISTS |
| Incorrect grain alignment | Mixed granularities in aggregations, incorrect totals | Multiple facts with different grains linking to same dimension | Use link table or type field |
