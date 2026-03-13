# Qlik Naming Convention Reference

Supplementary reference for the `qlik-naming-conventions` skill. Contains extended cross-layer naming walkthrough, reserved word list, character restrictions, and the naming decision quick-reference table.

---

## 1. Extended Cross-Layer Naming Walkthrough

This walkthrough traces 10 fields from a generic relational source (dimension and fact tables with surrogate keys) through all ETL layers to the UI. This is the most common source pattern Qlik projects encounter.

### Source Tables

- `dim_account` (account_id, account_name, cust_region, cust_segment, email, join_date)
- `dim_product` (product_id, product_name, category_name, brand, unit_cost, tags)
- `dim_store` (store_id, store_name, store_city, store_state, district)
- `fact_orders` (order_id, account_id, store_id, order_date, order_status_code, total_amount)
- `fact_order_lines` (orderline_id, order_id, product_id, quantity, line_amount, discount_pct)

### Full Cross-Layer Mapping

| Source Field | Source Table | Extract Layer (Raw QVD) | Transform Layer | DataModel Layer | UI Display |
|---|---|---|---|---|---|
| `account_id` | dim_account | `account_id` | `customer_key` | `customer_key` (hidden by HideSuffix) | Hidden from users |
| `account_name` | dim_account | `account_name` | `Account.Name` | `Customer.Name` | Direct field reference |
| `cust_region` | dim_account | `cust_region` | `Account.Region` | `Customer.Region` | Via `$(vCustomerRegion)` |
| `cust_segment` | dim_account | `cust_segment` | `Account.Segment` | `Customer.Segment` | Via `$(vCustomerSegment)` |
| `product_id` | dim_product | `product_id` | `product_key` | `product_key` (hidden by HideSuffix) | Hidden from users |
| `product_name` | dim_product | `product_name` | `Product.Name` | `Product.Name` | Direct field reference |
| `category_name` | dim_product | `category_name` | `Product.Category` | `Product.Category` | Via `$(vProductCategory)` |
| `tags` | dim_product | `tags` | `Product.Tag` (SubField expansion, bridge table) | `Product.Tag` | Direct field reference |
| `order_status_code` | fact_orders | `order_status_code` | `Order.Status` (via ApplyMap) | `Order.Status` | Direct field reference |
| `line_amount` | fact_order_lines | `line_amount` | `OrderLine.Revenue` | `OrderLine.Revenue` | Via `$(vTotalRevenue)` |

### Key Observations

**Source keys become standardized keys.** The source `account_id` is renamed to `customer_key` at the Transform layer to align with the project's key suffix convention (`_key`) and the business entity name. Key standardization happens at Transform because key consistency must be established before tables are joined.

**Not every field gets renamed at the DataModel layer.** `Product.Name`, `Product.Category`, and `Order.Status` keep their Transform layer names because the business already uses "Product" and "Order." Only the `Account` -> `Customer` rename is needed.

**Not every field gets a variable.** Only fields commonly used in expressions (`Customer.Region`, `Product.Category`, `OrderLine.Revenue`) get variable indirection. Display-only fields like `Customer.Name` or `Product.Name` are referenced directly.

**Structural transformations change cardinality, not just names.** The `tags` field (a delimited string like `"electronics,sale,featured"`) is expanded via SubField at the Transform layer into a bridge table `ProductTag` with fields `product_key` and `Product.Tag`. One source field becomes two tables. The bridge table naming (`ProductTag`) follows the convention for bridge tables: descriptive of the relationship, no prefix.

### Mapping RENAME for the DataModel Layer

```qlik
// This runs AFTER all tables are loaded and joined in the DataModel layer.
// It renames Account.* fields to Customer.* in one declarative operation.

FieldMap:
Mapping LOAD old_name, new_name INLINE [old_name, new_name
Account.Name, Customer.Name
Account.Region, Customer.Region
Account.Segment, Customer.Segment
Account.Join Date, Customer.Join Date
Account.Email, Customer.Email
Account.City, Customer.City
];
Rename Fields using FieldMap;
```

### Variable Definitions (.qvs snippet)

```qlik
// Field-reference variables - abstract a field name for maintainability
SET vCustomerRegion = [Customer.Region];
SET vCustomerSegment = [Customer.Segment];
SET vProductCategory = [Product.Category];

// Expression variables - contain aggregation logic for KPIs
SET vTotalRevenue = Sum([OrderLine.Revenue]);
SET vOrderCount = Count(DISTINCT order_key);
SET vAvgOrderValue = Sum([OrderLine.Revenue]) / Count(DISTINCT order_key);

// WRONG - these reference Transform layer names that no longer exist:
// SET vCustomerRegion = [Account.Region];  // NULL after Mapping RENAME
```

### Note on Data Vault Sources

When the upstream source uses Data Vault 2.0 architecture, the Extract layer preserves DV naming conventions (hub_, sat_, link_ prefixes, _hk suffixes for hash keys). Key standardization at the Transform layer then converts DV hash keys to the project's key convention (e.g., `account_hk` -> `customer_key`). The cross-layer naming principles are identical; only the source field names and the key transformation step differ.

---

## 2. Qlik Reserved Words

These words are used as script statements, control keywords, prefixes, operators, or function names. Using them as unquoted field names can cause parse errors or unpredictable behavior. If you must use one as a field name, enclose it in square brackets.

### Script Statements (Regular)

`Alias`, `AutoNumber`, `Binary`, `Comment`, `Connect`, `Declare`, `Derive`, `Directory`, `Disconnect`, `Drop`, `Execute`, `FlushLog`, `Force`, `Let`, `Load`, `Map`, `NullAsNull`, `NullAsValue`, `Qualify`, `Rem`, `Rename`, `Search`, `Section`, `Select`, `Set`, `Sleep`, `SQL`, `SQLColumns`, `SQLTables`, `SQLTypes`, `Star`, `Store`, `Tag`, `Trace`, `Unmap`, `Unqualify`, `Untag`

### Script Control Statements

`Call`, `Do`, `Loop`, `While`, `Until`, `End`, `Exit`, `For`, `Next`, `Each`, `If`, `Then`, `ElseIf`, `Else`, `Sub`, `Switch`, `Case`, `Default`, `To`, `Step`

### Script Prefixes

`Add`, `Buffer`, `Concatenate`, `Crosstable`, `First`, `Generic`, `Hierarchy`, `HierarchyBelongsTo`, `Inner`, `IntervalMatch`, `Join`, `Keep`, `Left`, `Mapping`, `Merge`, `NoConcatenate`, `Outer`, `Replace`, `Right`, `Sample`, `Semantic`, `Unless`, `When`

### Keywords Used Within Statements

`As`, `From`, `Where`, `Group`, `By`, `Order`, `Distinct`, `Inline`, `Resident`, `Autogenerate`, `And`, `Or`, `Not`, `Like`, `True`, `False`, `Null`, `Is`, `Table`, `Field`, `Fields`, `Using`, `Into`

### Expression Reserved Words

These are used in chart expressions. Avoid as field names without brackets.

`Sum`, `Count`, `Avg`, `Min`, `Max`, `Only`, `If`, `Pick`, `Match`, `MixMatch`, `WildMatch`, `Class`, `Dual`, `Null`, `Text`, `Num`, `Date`, `Time`, `Timestamp`, `Interval`, `Money`, `Total`, `All`, `Aggr`, `Above`, `Below`, `Before`, `After`, `First`, `Last`, `NoOfRows`, `RowNo`, `Column`, `Dimensionality`, `ValueList`, `ValueLoop`, `RangeSum`, `RangeCount`, `RangeAvg`, `RangeMin`, `RangeMax`

### Safe Practice

When in doubt, wrap any potentially reserved word in square brackets:

```qlik
// Safe: brackets disambiguate
LOAD
    id,
    [Status] AS [Order.Status],
    [Type]   AS [Order.Type],
    [Date]   AS [Order.Date]
FROM orders.qvd (qvd);
```

---

## 3. Character Restrictions

### Field Names

| Character | Allowed? | Notes |
|-----------|----------|-------|
| Letters (a-z, A-Z) | Yes | Case-insensitive for association, preserves case for display |
| Numbers (0-9) | Yes | Can appear anywhere including first position |
| Space | Yes | Field name must be in square brackets: `[Ship Date]` |
| Period / dot (`.`) | Yes | Used for entity-prefix convention: `[Product.Category]` |
| Underscore (`_`) | Yes | Common in source system fields: `order_date` |
| Hyphen (`-`) | Yes | Must use brackets: `[Revenue - YTD]` |
| Equals (`=`) | Avoid | Reserved as operator in expressions |
| Semicolon (`;`) | Avoid | Statement terminator in script |
| Curly braces (`{}`) | Avoid | Set analysis delimiters in expressions |
| Square brackets (`[]`) | Delimiter only | Used to enclose field names, not as content within them |
| Dollar sign (`$`) | Reserved | System field prefix (`$Table`, `$Field`). Do not use for custom fields. |
| Hash / pound (`#`) | Use carefully | Allowed but can conflict with date/time format interpretation |
| Single quote (`'`) | Avoid | String literal delimiter |
| Double quote (`"`) | Delimiter only | Alternative to square brackets for field name quoting |
| Backslash (`\`) | Avoid | Path separator, can cause issues in some contexts |
| Forward slash (`/`) | Use carefully | Allowed in brackets but can conflict with division operator |
| Comma (`,`) | Avoid | Parameter separator in functions and SET statements |

### Table Names

Same rules as field names. Table names with spaces or special characters require square brackets. Convention: use simple names without spaces (`Product`, `Orders`, `_StagingOrders`).

### Variable Names

- Must start with a letter or underscore
- Can contain letters, numbers, underscores, and periods
- **Cannot contain spaces** (unlike field names)
- Period in variable names is allowed but discouraged (causes confusion with dollar-sign expansion: `$(v.MyVar)` works but looks like property access)
- Convention: camelCase with `v` prefix: `vTotalRevenue`, `vCurrentPeriod`

### QVD File Names

Follow the operating system's file naming rules. Avoid spaces (use underscores). Avoid special characters that are invalid in file paths on your target platform.

---

## 4. Naming Decision Quick-Reference

| Element | Convention | Example | Anti-Pattern |
|---------|-----------|---------|-------------|
| Non-key field | `Entity.Attribute` | `Product.Category` | `Status` (unprefixed, creates synthetic keys) |
| Key field (source) | Consistent suffix, HideSuffix | `customer_key` | `account_id` in one table, `cust_key` in another |
| Composite key | `%` prefix, HidePrefix | `%ScopeKey` | `CompositeKey` (visible to users, clutters UI) |
| Dimension table | Singular noun | `Product` | `tbl_dim_product` (over-decorated) |
| Fact table | Action/event noun | `Orders` | `fact_orders` (prefix adds no value in Qlik) |
| Temp table | `_` prefix | `_RawProducts` | `TempProducts` (no convention signal, easy to forget drop) |
| Mapping table | `Map_` prefix | `Map_CategoryDesc` | `CategoryLookup` (no signal it's a mapping table) |
| Bridge table | Descriptive | `ProductCategory` | `Bridge_1` (non-descriptive) |
| Variable (field ref) | `v` prefix + camelCase | `vCustomerRegion` | `CustomerRegion` (no prefix, ambiguous) |
| Variable (expression) | `v` prefix + camelCase | `vTotalRevenue` | `TotalRevenue` (no prefix, ambiguous) |
| Master measure | Business-readable | `Total Revenue` | `vTotalRevenue` (that's the variable, not the measure name) |
| Master dimension | User-facing description | `Product Category` | `Product.Category` (internal field name exposed as dimension name) |
| Script file | Numeric prefix + purpose | `02_Extract_Orders.qvs` | `orders.qvs` (no execution order signal) |
| QVD file | Layer prefix + table | `Raw_Orders.qvd` | `orders.qvd` (no layer signal) |
| Field rename (cross-layer) | Mapping RENAME | See Section 1 | Resident reload just to rename fields |

---

## 5. Cross-Layer Naming Checklist

Use this checklist when reviewing cross-layer naming consistency:

- [ ] Extract layer preserves source field names exactly (no renaming at extraction)
- [ ] Transform layer applies entity-prefix to all non-key fields
- [ ] Key fields are standardized at the Transform layer (e.g., `account_id` -> `customer_key`)
- [ ] DataModel layer uses Mapping RENAME (not Resident reload) when entity names change
- [ ] Mapping RENAME table covers ALL fields that need renaming, not just some
- [ ] Key fields are NOT included in the Mapping RENAME table
- [ ] Expression variables reference final DataModel layer field names (post-rename)
- [ ] Variable names clearly map to their field names (`vCustomerRegion` -> `[Customer.Region]`)
- [ ] Master measure and dimension names are business-readable, not technical field names
- [ ] No intermediate layer field names leak into the UI (no `Account.Region` if the DataModel renamed it to `Customer.Region`)
