# Source Architecture Consumption Patterns for Qlik

How to consume data from different upstream architectures: dimensional warehouses, normalized OLTP, Data Vault 2.0, pre-joined views, and flat files.

---

## Dimensional Warehouse

A dimensional warehouse (Kimball architecture) provides pre-built star schemas with surrogate keys and managed dimensions.

### Characteristics

- **Surrogate keys:** Integer primary keys (e.g., Customer_Surrogate_Key = 12345) assigned by the warehouse.
- **Slowly-changing dimensions:** May use SCD Type 1 (update in place) or Type 2 (historical versions with effective dates).
- **Fact tables:** Pre-aggregated or at transaction grain.
- **Denormalized:** Dimensions are already flattened; limited normalization.

### How to Identify

```sql
-- Warehouse schema example:
SELECT CustomerKey, EffectiveDate, EndDate, CustomerName, Region
FROM DIM_Customer;

SELECT OrderKey, CustomerKey, ProductKey, OrderDate, Amount, Qty
FROM FACT_Sales;
```

Surrogate keys are present; dimensional tables have business keys alongside surrogate keys.

### Key Resolution Approach

**Use the warehouse's surrogate keys directly** unless there's a reason to rebuild:

```qlik
[Customer]:
LOAD
    customer_key,              // Surrogate key from warehouse
    business_key,              // Business key for debugging
    [Customer.Name],
    [Customer.Region]
FROM [warehouse_customer.qvd] (qvd);

[Fact_Sales]:
LOAD
    sales_key,
    customer_key,              // Link via warehouse surrogate key
    product_key,
    [Sales.Amount],
    [Sales.Quantity]
FROM [warehouse_sales.qvd] (qvd);
```

**Pros:**
- Keys are already stable and unique.
- Warehouse maintains key relationships.
- No need to rebuild keys in Qlik.

**Cons:**
- Keys are not human-readable (limit debugging to business key).
- If warehouse changes surrogate key strategy, Qlik breaks.

### SCD Type 1 Handling

SCD Type 1 dimensions update in place (no history). Incremental load pattern is straightforward: insert new records, update existing records by business key.

```qlik
// Load current warehouse dimension
[_DimCustomerNew]:
LOAD customer_key, business_key, [Customer.Name], [Customer.Region]
FROM [warehouse_customer.qvd] (qvd);

// Load previously cached dimension from QVD
[_DimCustomerOld]:
LOAD * FROM [Transform_Customer.qvd] (qvd);

// Keep old records not in new load (orphaned records)
[DimCustomerFinal]:
LOAD * RESIDENT [_DimCustomerOld]
WHERE NOT EXISTS(business_key, business_key);

// Append new records
CONCATENATE([DimCustomerFinal])
LOAD * RESIDENT [_DimCustomerNew];

DROP TABLES [_DimCustomerOld], [_DimCustomerNew];
STORE [DimCustomerFinal] INTO [Transform_Customer.qvd] (qvd);
```

### SCD Type 2 Handling

SCD Type 2 dimensions maintain history. Each change creates a new row with effective-date and end-date timestamps.

```qlik
// Warehouse produces:
// customer_key | business_key | name | region | effective_date | end_date
// 1            | CUST001      | John | US     | 2025-01-01     | 2999-12-31 (current)
// 2            | CUST001      | John | EU     | 2024-01-01     | 2024-12-31 (history)

// Qlik consumption: Keep as-is, use effective_date/end_date for time-slicing
[Customer]:
LOAD
    customer_key,
    business_key,
    [Customer.Name],
    [Customer.Region],
    [Customer.EffectiveDate],
    [Customer.EndDate]
FROM [warehouse_customer.qvd] (qvd);

// In expressions, use:
// Sum({<[Customer.EffectiveDate] = {">=$(=vAsOfDate)"},
//      [Customer.EndDate] = {"<=$(=vAsOfDate)"}>} Sales)
// to show sales as of a specific date with the appropriate customer version.
```

See `qlik-load-script` skill for full SCD Type 2 dual-timestamp incremental patterns.

### Common Pitfalls

**Ignoring SCD type:** Treating SCD Type 2 as Type 1 loses history. Always check warehouse metadata.

**Hard-coding effective dates:** Building filters on specific dates instead of parameterized date selection breaks historical analysis.

**Surrogate key drift:** If warehouse rebuilds surrogate keys (rare but catastrophic), Qlik keys break. Maintain a mapping table of old-to-new keys for transition periods.

---

## Normalized OLTP

Normalized OLTP systems (SAP, ERP, CRM) use 3NF schema: many tables, primary/foreign keys, minimal redundancy.

### Characteristics

- **Highly normalized:** Many small tables linked via foreign keys.
- **Transaction-oriented:** Data designed for insert/update operations, not analytics.
- **Operational flags:** Status, state, type fields everywhere (common sources of synthetic keys).
- **No denormalization:** Must join multiple tables to get complete business entities.

### How to Identify

```sql
-- OLTP schema example (many tables, foreign keys):
SELECT OrderID, OrderDate, CustomerID, TotalAmount FROM Orders;
SELECT OrderID, LineNum, ProductID, Qty, UnitPrice FROM OrderDetails;
SELECT ProductID, ProductName, CategoryID FROM Products;
SELECT CategoryID, CategoryName FROM Categories;

-- Customer data split across tables:
SELECT CustomerID, Name FROM Customers;
SELECT CustomerID, AddressLine1, City FROM Addresses;
SELECT CustomerID, PhoneNumber FROM Phones;
```

Many small tables with explicit foreign keys.

### Key Resolution Approach

**Use source primary/foreign keys directly** in Qlik (no surrogate key rebuilding needed). The source PK/FK structure is stable and correct.

```qlik
[Order]:
LOAD
    order_id,                  // PK from OLTP
    customer_id,               // FK to Customer
    order_date,
    [Order.Total]
FROM [oltp_order.qvd] (qvd);

[Customer]:
LOAD
    customer_id,               // PK
    [Customer.Name]
FROM [oltp_customer.qvd] (qvd);
```

### Denormalization Strategy

**Option 1: Join in SQL extraction layer** (before storing to Raw QVD):

```sql
-- SQL SELECT in Qlik extraction script
SELECT
    o.order_id,
    o.customer_id,
    c.name,
    c.region,
    o.order_amount
FROM oltp_orders o
LEFT JOIN oltp_customers c ON o.customer_id = c.customer_id;
```

**Pros:** Raw QVD contains denormalized data; Transform layer is simpler.
**Cons:** Large Raw QVD (denormalization duplicates attributes).

**Option 2: Join in Qlik Transform layer** (keep Raw normalized, denormalize in Transform):

```qlik
// Raw layer: preserve source structure
[_RawOrder]: LOAD order_id, customer_id, order_amount FROM [oltp_order.qvd] (qvd);
[_RawCustomer]: LOAD customer_id, name, region FROM [oltp_customer.qvd] (qvd);

// Transform layer: join
[Transform_Order]:
LOAD
    o.order_id,
    o.customer_id,
    c.name AS [Customer.Name],
    c.region AS [Customer.Region],
    o.order_amount AS [Order.Amount]
FROM _RawOrder AS o
LEFT JOIN _RawCustomer AS c ON o.customer_id = c.customer_id;

DROP TABLES [_RawOrder], [_RawCustomer];
STORE [Transform_Order] INTO [Transform_Order.qvd] (qvd);
```

**Pros:** Modular, easy to debug. Transform layer owns the join logic.
**Cons:** Additional processing step.

**Choose Option 1** if extraction is straightforward (few joins). **Choose Option 2** if extraction is complex or will be reused by multiple Transform patterns.

### Transaction Table Handling

OLTP transaction tables are append-only (orders, invoices, payments). Incremental load pattern is straightforward: load only new records since last load.

```qlik
// Incremental: only load orders after the max previously loaded
LET vLastLoadDate = '2026-01-31';

[_NewOrders]:
LOAD order_id, customer_id, order_amount, order_date
FROM [oltp_order.qvd] (qvd)
WHERE order_date > DATE '$(vLastLoadDate)';

// Store in Transform QVD
STORE [_NewOrders] INTO [Transform_Order.qvd] (qvd);
```

Update `vLastLoadDate` after successful load (store in a metadata table or as a LET variable in the script).

### Mutable Master Data Handling

OLTP dimensions (Customer, Product, Store) are mutable and updated in place. Use SCD Type 1 incremental pattern.

```qlik
// Load current snapshot
[_CurrentProduct]:
LOAD product_id, product_name, category_id FROM [oltp_product.qvd] (qvd);

// Load previously cached version
[_PreviousProduct]:
LOAD * FROM [Transform_Product.qvd] (qvd);

// Merge: keep old records not in new load, append new/updated records
[Transform_Product]:
LOAD * RESIDENT [_PreviousProduct]
WHERE NOT EXISTS(product_id, product_id);

CONCATENATE([Transform_Product])
LOAD * RESIDENT [_CurrentProduct];

DROP TABLES [_CurrentProduct], [_PreviousProduct];
STORE [Transform_Product] INTO [Transform_Product.qvd] (qvd);
```

### Common Pitfalls

**Over-normalizing in Qlik:** Keeping data in 3NF in Qlik defeats the purpose. Denormalize to star schema for BI.

**Ignoring surrogate key absence:** OLTP keys are natural keys (customer_id, product_id). Use them as-is; no need to create surrogate keys unless PK stability is a concern.

**Duplicate joins:** Joining Customer to Order, then joining Address to Order separately. Group all joins in one place (either SQL extraction or Transform join).

---

## Data Vault 2.0

Data Vault 2.0 is a hybrid normalized/dimensional architecture designed for enterprise data warehousing.

### Characteristics

- **Hub tables:** One row per business entity (Customer, Product, Order). Columns: business key + metadata (load date, source system).
- **Link tables:** Relationships between hubs. Columns: hub keys + metadata.
- **Satellite tables:** Attributes for hubs (Customer_Attributes, Customer_Contact). Columns: hub key + effective dates + attributes. Multiple satellites per hub.
- **Composite business keys:** Multi-field keys (source_system | customer_id).
- **Dual timestamps:** Effective_from and effective_to for SCD Type 2 tracking.

### How to Identify

```sql
-- Data Vault 2.0 schema example:
SELECT HubKey, BusinessKey, LoadDate FROM HUB_Customer;
SELECT HubKey1, HubKey2, LinkKey, LoadDate FROM LNK_CustomerOrder;
SELECT HubKey, SatelliteKey, BusinessKey, EffectiveFrom, EffectiveTo, Name, Region
FROM SAT_Customer_Attributes;
```

Hubs are small, links are sparse, satellites are wide with time-slicing columns.

### Hub/Link/Satellite Merge Strategy

Flatten the Data Vault structure into Qlik dimensions and facts.

```qlik
// 1. Load Hub
[_Hub]:
LOAD
    hub_key,
    business_key
FROM [dv_hub_customer.qvd] (qvd);

// 2. Load Satellites and concatenate
[_Satellite]:
LOAD
    hub_key,
    [Customer.Name],
    [Customer.Region],
    effective_from AS [Customer.EffectiveFrom],
    effective_to AS [Customer.EffectiveTo]
FROM [dv_sat_customer_attributes.qvd] (qvd);

// 3. Load Contact Satellite
[_ContactSat]:
LOAD
    hub_key,
    [Customer.Phone],
    [Customer.Email],
    effective_from,
    effective_to
FROM [dv_sat_customer_contact.qvd] (qvd);

// 4. Merge Hub + Attributes Satellite
[_MergedCustomer]:
LOAD
    [_Hub].hub_key,
    [_Hub].business_key,
    [_Satellite].[Customer.Name],
    [_Satellite].[Customer.Region],
    [_Satellite].[Customer.EffectiveFrom],
    [_Satellite].[Customer.EffectiveTo]
RESIDENT [_Hub]
LEFT JOIN (_Satellite)
ON [_Hub].hub_key = [_Satellite].hub_key;

// 5. Add Contact attributes (left join to preserve attribute sparseness)
[Customer]:
LOAD
    [_MergedCustomer].*,
    [_ContactSat].[Customer.Phone],
    [_ContactSat].[Customer.Email]
RESIDENT [_MergedCustomer]
LEFT JOIN (_ContactSat)
ON [_MergedCustomer].hub_key = [_ContactSat].hub_key
AND [_MergedCustomer].[Customer.EffectiveFrom] = [_ContactSat].effective_from;

DROP TABLES [_Hub], [_Satellite], [_ContactSat], [_MergedCustomer];
STORE [Customer] INTO [Transform_Customer.qvd] (qvd);
```

### Composite Key Handling

Data Vault business keys are often composite (source_system | customer_id). Hash the composite for a stable key:

```qlik
[Hub]:
LOAD
    hub_key,
    Hash128(source_system & '|' & customer_id) AS business_key_hash,
    [Hub.Source],
    [Hub.LoadDate]
FROM [dv_hub_customer.qvd] (qvd);
```

Use the hashed key for Qlik associations. Keep the source business key for debugging.

### Dual-Timestamp Incremental Pattern (CRITICAL)

Data Vault satellites use effective_from and effective_to for SCD Type 2. Incremental loads must capture BOTH newly created records AND records whose effective_to changed (previously current records that were closed).

```qlik
// Load last successful load timestamp
LET vLastLoadTime = '2026-01-31 23:59:59';

// Load satellites where effective_from > vLastLoadTime OR effective_to > vLastLoadTime
[_NewSatellites]:
LOAD
    hub_key,
    [Customer.Name],
    [Customer.Region],
    effective_from,
    effective_to
FROM [dv_sat_customer_attributes.qvd] (qvd)
WHERE effective_from > TIMESTAMP '$(vLastLoadTime)'
   OR effective_to > TIMESTAMP '$(vLastLoadTime)';

// Merge with previously loaded satellites
[Transform_Customer]:
LOAD * FROM [Transform_Customer_Sat.qvd] (qvd);

CONCATENATE([Transform_Customer])
LOAD * RESIDENT [_NewSatellites];

// Dedup: keep most recent version per hub_key (highest effective_to)
[Transform_Customer_Final]:
LOAD
    hub_key,
    [Customer.Name],
    [Customer.Region],
    effective_from,
    effective_to
RESIDENT [Transform_Customer]
WHERE hub_key & effective_to = Concat(hub_key, Max(effective_to) OVER (PARTITION BY hub_key))
      OR (effective_to IS NULL);

DROP TABLE [Transform_Customer];
RENAME TABLE [Transform_Customer_Final] TO [Transform_Customer];
STORE [Transform_Customer] INTO [Transform_Customer_Sat.qvd] (qvd);
```

**Critical:** The dual-timestamp pattern must capture BOTH conditions:
- **effective_from > vLastLoadTime** — New records
- **effective_to > vLastLoadTime** — Previously current records that were closed

Missing the second condition = **silent data loss**. The app appears to load successfully but misses records that transitioned from current to history.

See `qlik-load-script` skill for complete implementation details.

### Common Pitfalls

**Ignoring effective_to:** Treating Data Vault as Type 1 (keeping only current records) loses historical context. Always preserve the full time-sliced history in Qlik.

**Not capturing closures:** Incremental loads that only filter on effective_from miss records where effective_to changed. This is a silent failure—the load succeeds but data is incomplete.

**Composite key oversimplification:** Using raw concatenation instead of hashing for composite keys makes the key non-deterministic if load order changes. Always hash composite keys in Qlik.

---

## Pre-Joined Views and Materialized Exports

Pre-joined views are delivered by the upstream system as single tables (views, exported CSVs, or API responses) combining multiple logical entities.

### Characteristics

- **Denormalized:** All attributes in one table.
- **Schema drift:** The view definition may change over time (new columns, dropped columns, renamed columns).
- **Grain ambiguity:** The row-level grain may not be obvious (one row per order? per order line?).
- **Potential duplicates:** If the join produces many-to-many, duplicates may appear without warning.

### How to Identify

```
Source provides: Sales_View (order_id, customer_id, customer_name, product_id, product_name, qty, amount)
```

Single denormalized table combining Customer, Product, and Order information.

### Grain Validation

**Always validate the grain before consuming:**

```qlik
// Load and count distinct keys
[_SalesView]: LOAD order_id, order_line_id FROM [sales_view.qvd] (qvd);

// If one row per order_id, should be unique
LET vOrderCount = COUNT(DISTINCT order_id);
LET vRowCount = NoOfRows('_SalesView');

IF $(vOrderCount) = $(vRowCount) THEN
    TRACE One row per order -- grain is order;
ELSEIF $(vOrderCount) < $(vRowCount) / 100 THEN
    TRACE One order has many rows -- grain is order_line;
END IF

DROP TABLE [_SalesView];
```

### Deduplication Strategy

If the join produces unintended duplicates, identify the root cause and deduplicate:

```qlik
// Source: Order + OrderLine joined to Product creates:
// order_id | order_line_id | order_date | order_amount | product_id | product_name
// The dedup rule: is order_amount per order, or per line?

// If per line (order_amount is line amount):
[Transform_OrderLine]:
LOAD DISTINCT
    order_id,
    order_line_id,
    order_date,
    order_amount,
    product_id,
    [Product.Name]
RESIDENT [SalesView];

// If per order (order_amount is duplicated for each line):
[_OrderLineDedup]:
LOAD DISTINCT
    order_id,
    order_line_id,
    product_id
FROM [SalesView];

[Transform_Order]:
LOAD
    order_id,
    order_date,
    Sum(order_amount) / Count(DISTINCT product_id) AS [Order.Amount]
RESIDENT [_OrderLineDedup]
GROUP BY order_id, order_date;
```

### Schema Drift Handling

Upstream view definitions may change. Detect schema changes before consuming:

```qlik
// Validate expected columns exist
LET vExpectedCols = 'order_id,customer_id,customer_name,product_id,product_name,qty,amount';

[_ViewSchema]:
LOAD FieldName() FROM [sales_view.qvd] (qvd) WHERE 1=0;  // Load structure only

// Check each expected column exists (pseudo-code; Qlik doesn't have native schema introspection)
// In practice, use a subroutine that loops through fields and validates
```

Document schema assumptions: "SalesView must have columns X, Y, Z." Alert when unexpected columns appear or expected columns vanish.

### Common Pitfalls

**Assuming grain:** Never assume one row per order. Always validate.

**Ignoring schema drift:** View definitions change; hard-coded column names break. Either validate on each load or use external schema tracking.

**Deduplication without understanding:** Grouping/dedup without understanding whether order_amount is per-order or per-line produces wrong results.

---

## Flat Files and CSV Dumps

Flat files (CSV, TSV, Excel exports, API JSON flattened to CSV) are simple but require careful validation.

### Characteristics

- **No schema:** Column names and types inferred (may be wrong).
- **Format variations:** Delimiters, quotes, line endings may differ.
- **Encoding issues:** UTF-8 vs. ANSI vs. Latin-1.
- **Header validation:** Column count and names may vary across files.

### How to Identify

```
Source provides: orders_20260301.csv, orders_20260302.csv, ...
Header: order_id,customer_id,product_id,order_date,amount,status
```

Time-stamped or rotating flat files.

### Header Validation Pattern

```qlik
// Load file with inferred header
[_RawOrder]:
LOAD *
FROM [lib://data/orders_$(vFileDate).csv] (txt, codepage is 1252, embedded labels);

// Validate expected columns exist
LET vExpectedFields = 'order_id,customer_id,product_id,order_date,amount';
LET vFieldCount = NoOfFields('_RawOrder');
TRACE Fields loaded: $(vFieldCount);

// Check schema manually or via subroutine
IF $(vFieldCount) <> 5 THEN
    TRACE ERROR: Expected 5 fields, found $(vFieldCount);
    SET ErrorMode = 1;  // Stop reload
END IF
```

### Incremental Detection by Timestamp or Filename

Flat files are typically full exports of current data. Detect which files are new:

```qlik
// Incremental: only load files after the last successful load
LET vLastLoadDate = '20260228';  // YYYYMMDD format

[_OrderFileList]:
LOAD FileBaseName() AS file_name, FileTime() AS file_time
FROM [lib://data/orders_*.csv];

// Filter to files newer than last load
[_FilesToLoad]:
LOAD file_name
RESIDENT [_OrderFileList]
WHERE file_time > TIMESTAMP '$(vLastLoadDate)';

// Load all files matching filtered list
FOR each vFile IN [SELECT DISTINCT file_name FROM _FilesToLoad]
    [_OrderNew]:
    LOAD * FROM [lib://data/$(vFile)] (txt, embedded labels);

    // Dedup if needed (flat files may have overlapping rows across exports)
    CONCATENATE([OrderFinal])
    LOAD * RESIDENT [_OrderNew] WHERE NOT EXISTS(order_id);

    DROP TABLE [_OrderNew];
NEXT vFile
```

### Delimiter and Encoding Handling

CSV files may use different delimiters and encodings:

```qlik
// Comma-delimited, UTF-8 (default)
LOAD * FROM [file.csv] (txt, codepage is 65001);

// Tab-delimited, ANSI (Latin-1)
LOAD * FROM [file.tsv] (txt, codepage is 1252, separator is '\t');

// Semicolon-delimited (common in European CSVs)
LOAD * FROM [file.csv] (txt, codepage is 65001, separator is ';');
```

Hardcode encoding/delimiter or autodetect via file inspection.

### Embedded Delimiters and Quoted Fields

CSV files with embedded delimiters must quote fields:

```
order_id,customer_name,address
1,"Smith, John","123 Main St, Apt 4"
2,"Doe, Jane","456 Oak Ave, Suite 200"
```

Qlik handles quoted fields natively if the CSV is well-formed. If not, preprocess:

```qlik
// Trust Qlik's quote handling (works for most files)
LOAD * FROM [file.csv] (txt, embedded labels);

// If quotes are not used correctly, clean before loading
// This is rare and usually indicates a data quality issue upstream.
```

### Common Pitfalls

**No header validation:** Assuming columns are present without checking.

**Encoding mismatch:** Loading UTF-8 file as ANSI produces garbage characters.

**Not deduplicating incremental loads:** Flat file exports may overlap; must dedup by key.

**Schema drift:** Column count or order changes silently. Always validate.

---

## Source Architecture Decision Summary

| Architecture | When Used | Key Approach | Incremental | Denormalization | Complexity |
|--------------|-----------|--------------|-------------|-----------------|------------|
| **Dimensional Warehouse** | Pre-built BI schema | Use surrogate keys directly | Per SCD type | Already done | Low |
| **Normalized OLTP** | Transaction systems (ERP, CRM) | Use PK/FK directly | Transaction append + SCD1 | Required in Transform | Medium |
| **Data Vault 2.0** | Enterprise warehouse | Merge hubs/satellites, hash composites | Dual-timestamp (critical!) | Flatten satellites to dims | High |
| **Pre-Joined Views** | Materialized views, API exports | Validate grain, dedup | File timestamp | Already done | Medium |
| **Flat Files** | CSV/TSV dumps, exports | Validate headers, encoding | Filename/timestamp + dedup | Required if normalized | Low |

**Key takeaway:** Different architectures require fundamentally different consumption strategies. Treating Data Vault like flat files (or vice versa) causes silent data loss or incorrect models.
