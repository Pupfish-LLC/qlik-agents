# Data Quality Validation Queries

Complete query templates organized by validation category. Includes both Qlik Resident syntax (runs during reload) and SQL syntax (for MCP source comparison). All queries use entity-prefix dot notation for field names.

---

## 1. Null Rate Analysis

### Qlik Resident Query

```qlik
// Check null rate for multiple fields in a table
[_Diag_NullRate]:
LOAD
    'Orders' AS ValidationTable,
    'Order.Key' AS FieldName,
    Count([Order.Key]) AS NonNullCount,
    NoOfRows('Orders') AS TotalRows,
    NoOfRows('Orders') - Count([Order.Key]) AS NullCount,
    Round((NoOfRows('Orders') - Count([Order.Key])) / NoOfRows('Orders') * 100, 0.01) AS NullRate_Pct
RESIDENT [Orders];

// Concatenate additional field checks
CONCATENATE([_Diag_NullRate])
LOAD
    'Orders' AS ValidationTable,
    'Order.Amount' AS FieldName,
    Count([Order.Amount]) AS NonNullCount,
    NoOfRows('Orders') AS TotalRows,
    NoOfRows('Orders') - Count([Order.Amount]) AS NullCount,
    Round((NoOfRows('Orders') - Count([Order.Amount])) / NoOfRows('Orders') * 100, 0.01) AS NullRate_Pct
RESIDENT [Orders];

CONCATENATE([_Diag_NullRate])
LOAD
    'Orders' AS ValidationTable,
    'Order.CustomerKey' AS FieldName,
    Count([Order.CustomerKey]) AS NonNullCount,
    NoOfRows('Orders') AS TotalRows,
    NoOfRows('Orders') - Count([Order.CustomerKey]) AS NullCount,
    Round((NoOfRows('Orders') - Count([Order.CustomerKey])) / NoOfRows('Orders') * 100, 0.01) AS NullRate_Pct
RESIDENT [Orders];

// Flag issues where null rate exceeds threshold (e.g., 5% for key fields, 10% for optional fields)
LET vNullRateThreshold = 0.05;  // 5%
[_NullRateIssues]:
NoConcatenate
LOAD * WHERE NullRate_Pct > $(vNullRateThreshold) * 100;
LOAD * RESIDENT [_Diag_NullRate];

LET vNullIssueCount = NoOfRows('_NullRateIssues');
IF $(vNullIssueCount) > 0 THEN
    TRACE [WARNING] Found $(vNullIssueCount) fields with null rate exceeding threshold;
ELSE
    DROP TABLE [_NullRateIssues];
END IF
```

### SQL Query (Source Comparison)

```sql
-- SQL Server / PostgreSQL compatible
SELECT
    'Orders' AS ValidationTable,
    'Order.Amount' AS FieldName,
    COUNT(*) AS TotalRows,
    COUNT(CASE WHEN order_amount IS NULL THEN 1 END) AS NullCount,
    ROUND(
        CAST(COUNT(CASE WHEN order_amount IS NULL THEN 1 END) AS FLOAT) /
        COUNT(*) * 100,
        2
    ) AS NullRate_Pct
FROM orders
GROUP BY 1, 2
HAVING COUNT(CASE WHEN order_amount IS NULL THEN 1 END) > CAST(COUNT(*) AS FLOAT) * 0.05
ORDER BY NullRate_Pct DESC;
```

---

## 2. Referential Integrity (Orphaned Records)

### Qlik Resident Query

```qlik
// Find orders referencing non-existent customers
[_CustomerKeys]:
LOAD DISTINCT [Customer.Key] AS _lookup_key RESIDENT [Customers];

[_Diag_OrphanedOrders]:
LOAD [Order.Key], [Order.CustomerKey] AS OrphanedForeignKey
RESIDENT [Orders]
WHERE NOT EXISTS(_lookup_key, [Order.CustomerKey]);

DROP TABLE [_CustomerKeys];

LET vOrphanCount = NoOfRows('_Diag_OrphanedOrders');
IF $(vOrphanCount) > 0 THEN
    TRACE [ERROR] Found $(vOrphanCount) orders with non-existent customer references;
ELSE
    TRACE [OK] All orders reference valid customers;
    DROP TABLE [_Diag_OrphanedOrders];
END IF

// Repeat pattern for other dimension relationships:
// Orders → Products
// Orders → Regions
// OrderLineItems → Orders (if hierarchical)
```

### SQL Query (Source Comparison)

```sql
-- SQL Server
SELECT
    COUNT(DISTINCT o.order_id) AS OrphanedRecordCount,
    'Orders referencing non-existent Customers' AS IssueType
FROM orders o
LEFT OUTER JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- PostgreSQL (same syntax)
SELECT
    COUNT(DISTINCT o.order_id) AS OrphanedRecordCount,
    'Orders referencing non-existent Customers' AS IssueType
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;
```

---

## 3. Value Distribution Analysis

### Qlik Resident Query

```qlik
// Top-N values and frequency per dimension
[_Diag_TopValues]:
LOAD [Customer.Region], Count([Order.Key]) AS RegionOrderCount
RESIDENT [Orders]
GROUP BY [Customer.Region]
ORDER BY RegionOrderCount DESC;

// Use preceding LOAD to limit to top 10
[_TopRegions]:
NoConcatenate
LOAD * WHERE RowNo() <= 10;
LOAD [Customer.Region], RegionOrderCount
RESIDENT [_Diag_TopValues];

DROP TABLE [_Diag_TopValues];

// Detect suspect values ('test', 'TBD', NULL-like strings)
[_SuspectValues]:
LOAD [Customer.Region]
RESIDENT [Orders]
WHERE
    [Customer.Region] = 'test' OR
    [Customer.Region] = 'TBD' OR
    [Customer.Region] = 'null' OR
    [Customer.Region] = 'N/A' OR
    [Customer.Region] = 'UNKNOWN' OR
    [Customer.Region] = '[null]';

LET vSuspectCount = NoOfRows('_SuspectValues');
IF $(vSuspectCount) > 0 THEN
    TRACE [WARNING] Found $(vSuspectCount) suspect values in Customer.Region;
ELSE
    DROP TABLE [_SuspectValues];
END IF

// Cardinality check: expect Region to have 4-6 unique values
[_CardinalityCheck]:
LOAD Count(DISTINCT [Customer.Region]) AS RegionCount
RESIDENT [Orders];

LET vRegionCount = Peek('RegionCount', 0, '_CardinalityCheck');
DROP TABLE [_CardinalityCheck];

IF $(vRegionCount) < 4 OR $(vRegionCount) > 6 THEN
    TRACE [WARNING] Customer.Region cardinality is $(vRegionCount); expected 4-6 unique values;
END IF
```

### SQL Query (Source Comparison)

```sql
-- Top-10 value frequency
SELECT TOP 10
    customer_region,
    COUNT(*) AS Frequency,
    ROUND(CAST(COUNT(*) AS FLOAT) / (SELECT COUNT(*) FROM orders) * 100, 2) AS Pct_of_Total
FROM orders
GROUP BY customer_region
ORDER BY Frequency DESC;

-- Detect suspect values
SELECT
    customer_region,
    COUNT(*) AS SuspectCount
FROM orders
WHERE customer_region IN ('test', 'TBD', 'null', 'N/A', 'UNKNOWN', '[null]')
GROUP BY customer_region;
```

---

## 4. Row Count Validation

### Qlik Resident Query

```qlik
// Expected counts from source profile (set during configuration phase)
SET vExpectedCustomers = 150000;
SET vExpectedOrders = 2500000;

// After loading
LET vActualCustomers = NoOfRows('Customers');
LET vActualOrders = NoOfRows('Orders');

// Create validation summary table
[_RowCountValidation]:
LOAD * INLINE [
    TableName, ExpectedRows, ActualRows, RowCountStatus
];

// Populate with row count results
CONCATENATE([_RowCountValidation])
LOAD
    'Customers' AS TableName,
    $(vExpectedCustomers) AS ExpectedRows,
    $(vActualCustomers) AS ActualRows,
    IF($(vActualCustomers) >= $(vExpectedCustomers) * 0.9 AND $(vActualCustomers) <= $(vExpectedCustomers) * 1.1, 'PASS', 'WARN') AS RowCountStatus
AUTOGENERATE 1;

CONCATENATE([_RowCountValidation])
LOAD
    'Orders' AS TableName,
    $(vExpectedOrders) AS ExpectedRows,
    $(vActualOrders) AS ActualRows,
    IF($(vActualOrders) >= $(vExpectedOrders) * 0.9 AND $(vActualOrders) <= $(vExpectedOrders) * 1.1, 'PASS', 'WARN') AS RowCountStatus
AUTOGENERATE 1;

// Alert on failures (>10% variance)
[_RowCountIssues]:
LOAD TableName, ExpectedRows, ActualRows, RowCountStatus
RESIDENT [_RowCountValidation]
WHERE RowCountStatus = 'WARN';

LET vRowCountIssues = NoOfRows('_RowCountIssues');
IF $(vRowCountIssues) > 0 THEN
    TRACE [WARNING] $(vRowCountIssues) tables have row count variance >10%%;
ELSE
    DROP TABLE [_RowCountIssues];
END IF
```

### SQL Query (Source Comparison)

```sql
-- Compare actual source rows vs. expected (from profile)
SELECT
    'Customers' AS TableName,
    150000 AS ExpectedRows,
    COUNT(*) AS ActualRows,
    ROUND(CAST(ABS(COUNT(*) - 150000) AS FLOAT) / 150000 * 100, 2) AS Variance_Pct,
    CASE
        WHEN COUNT(*) >= 150000 * 0.9 AND COUNT(*) <= 150000 * 1.1 THEN 'PASS'
        ELSE 'WARN'
    END AS Status
FROM customers;

UNION ALL

SELECT
    'Orders' AS TableName,
    2500000 AS ExpectedRows,
    COUNT(*) AS ActualRows,
    ROUND(CAST(ABS(COUNT(*) - 2500000) AS FLOAT) / 2500000 * 100, 2) AS Variance_Pct,
    CASE
        WHEN COUNT(*) >= 2500000 * 0.9 AND COUNT(*) <= 2500000 * 1.1 THEN 'PASS'
        ELSE 'WARN'
    END AS Status
FROM orders;
```

---

## 5. Duplicate Detection

### Qlik Resident Query - Primary Key Uniqueness

```qlik
// Detect duplicate primary keys using preceding LOAD + WHERE (no HAVING)
[_KeyCount]:
LOAD [Customer.Key], Count([Customer.Key]) AS KeyFrequency
RESIDENT [Customers]
GROUP BY [Customer.Key];

[_DuplicateKeys]:
NoConcatenate
LOAD [Customer.Key], KeyFrequency
WHERE KeyFrequency > 1;
LOAD [Customer.Key], KeyFrequency
RESIDENT [_KeyCount];

DROP TABLE [_KeyCount];

LET vDupKeyCount = NoOfRows('_DuplicateKeys');
IF $(vDupKeyCount) > 0 THEN
    TRACE [CRITICAL] Customers table has $(vDupKeyCount) duplicate keys!;
ELSE
    TRACE [OK] Customer.Key is unique;
    DROP TABLE [_DuplicateKeys];
END IF
```

### Qlik Resident Query - Full-Row Duplicates

```qlik
// Detect rows where ALL fields are identical
[_RowHash]:
LOAD
    [Customer.Key],
    [Customer.Name],
    [Customer.Region],
    Concat([Customer.Key] & '|' & [Customer.Name] & '|' & [Customer.Region]) AS _row_hash
RESIDENT [Customers];

[_FullRowDups]:
LOAD _row_hash, Count(_row_hash) AS DupCount
RESIDENT [_RowHash]
GROUP BY _row_hash;

[_FullRowDupFlags]:
NoConcatenate
LOAD _row_hash, DupCount
WHERE DupCount > 1;
LOAD _row_hash, DupCount
RESIDENT [_FullRowDups];

DROP TABLES [_RowHash], [_FullRowDups];

LET vFullRowDupCount = NoOfRows('_FullRowDupFlags');
IF $(vFullRowDupCount) > 0 THEN
    TRACE [WARNING] Found $(vFullRowDupCount) full-row duplicates in Customers;
ELSE
    DROP TABLE [_FullRowDupFlags];
END IF
```

### SQL Query (Source Comparison)

```sql
-- Duplicate primary keys
SELECT
    customer_key,
    COUNT(*) AS KeyFrequency
FROM customers
GROUP BY customer_key
HAVING COUNT(*) > 1
ORDER BY KeyFrequency DESC;

-- Full-row duplicates
SELECT
    customer_key,
    customer_name,
    customer_region,
    COUNT(*) AS DupCount
FROM customers
GROUP BY customer_key, customer_name, customer_region
HAVING COUNT(*) > 1
ORDER BY DupCount DESC;
```

---

## 6. Sparse Field Analysis

### Qlik Resident Query

```qlik
// Check population rate for each field in a table
[_FieldStats]:
LOAD
    'Orders' AS TableName,
    'Order.Discount' AS FieldName,
    NoOfRows('Orders') AS TotalRows,
    Count([Order.Discount]) AS PopulatedCount,
    Round(Count([Order.Discount]) / NoOfRows('Orders') * 100, 0.01) AS Population_Pct
RESIDENT [Orders];

// Add more fields
CONCATENATE([_FieldStats])
LOAD
    'Orders' AS TableName,
    'Order.ShippingNotes' AS FieldName,
    NoOfRows('Orders') AS TotalRows,
    Count([Order.ShippingNotes]) AS PopulatedCount,
    Round(Count([Order.ShippingNotes]) / NoOfRows('Orders') * 100, 0.01) AS Population_Pct
RESIDENT [Orders];

CONCATENATE([_FieldStats])
LOAD
    'Orders' AS TableName,
    'Order.SpecialRequest' AS FieldName,
    NoOfRows('Orders') AS TotalRows,
    Count([Order.SpecialRequest]) AS PopulatedCount,
    Round(Count([Order.SpecialRequest]) / NoOfRows('Orders') * 100, 0.01) AS Population_Pct
RESIDENT [Orders];

// Flag sparse fields (populated <10%)
LET vSparsityThreshold = 10;  // 10%
[_SparseFields]:
NoConcatenate
LOAD TableName, FieldName, Population_Pct
WHERE Population_Pct < $(vSparsityThreshold);
LOAD TableName, FieldName, Population_Pct
RESIDENT [_FieldStats];

LET vSparseCount = NoOfRows('_SparseFields');
IF $(vSparseCount) > 0 THEN
    TRACE [INFO] Found $(vSparseCount) fields with <$(vSparsityThreshold)% population rate;
ELSE
    DROP TABLE [_SparseFields];
END IF

DROP TABLE [_FieldStats];
```

### SQL Query (Source Comparison)

```sql
-- Field population rates
SELECT
    'Orders' AS TableName,
    'Order.Discount' AS FieldName,
    COUNT(*) AS TotalRows,
    COUNT(order_discount) AS PopulatedCount,
    ROUND(CAST(COUNT(order_discount) AS FLOAT) / COUNT(*) * 100, 2) AS Population_Pct
FROM orders
WHERE CAST(COUNT(order_discount) AS FLOAT) / COUNT(*) < 0.10
GROUP BY 1, 2
ORDER BY Population_Pct ASC;
```

---

## 7. Field Type Consistency

### Qlik Resident Query

This check is Qlik-specific. It detects fields where Qlik's dual value mechanism suggests mixed types (numeric vs. text loaded as strings).

```qlik
// For each field that should be numeric, verify it's not stored as text
[_TypeCheck]:
LOAD
    [Order.Quantity],
    Type([Order.Quantity]) AS FieldType
RESIDENT [Orders];

// Count rows where type inference differs
[_TypeIssues]:
LOAD FieldType, Count([Order.Quantity]) AS Count_of_Type
RESIDENT [_TypeCheck]
GROUP BY FieldType;

LET vTypeCount = NoOfRows('_TypeIssues');
IF $(vTypeCount) > 1 THEN
    TRACE [WARNING] Order.Quantity has mixed types (numeric and text detected);
ELSE
    DROP TABLE [_TypeIssues];
END IF

DROP TABLE [_TypeCheck];

// Alternative check: numeric fields with alphabetic characters
[_NonNumericOrders]:
LOAD [Order.Quantity]
RESIDENT [Orders]
WHERE [Order.Quantity] LIKE '*[a-zA-Z]*';  // Qlik LIKE for pattern matching

LET vNonNumericCount = NoOfRows('_NonNumericOrders');
IF $(vNonNumericCount) > 0 THEN
    TRACE [ERROR] Found $(vNonNumericCount) non-numeric values in Order.Quantity;
ELSE
    DROP TABLE [_NonNumericOrders];
END IF
```

---

## 8. String-Encoded Null Detection

### Qlik Resident Query

Detects string values that represent nulls ('null', 'NaN', 'none', 'n/a', '[null]') and should be converted to actual NULLs. Cross-references the `vCleanNull` variable pattern from qlik-load-script.

```qlik
// Detect string-encoded nulls
[_StringEncodedNulls]:
LOAD [Order.Quantity]
RESIDENT [Orders]
WHERE
    Lower([Order.Quantity]) = 'null' OR
    Lower([Order.Quantity]) = 'nan' OR
    Lower([Order.Quantity]) = 'none' OR
    Lower([Order.Quantity]) = 'n/a' OR
    Lower([Order.Quantity]) = '#n/a' OR
    [Order.Quantity] = '[null]' OR
    [Order.Quantity] = 'NA' OR
    [Order.Quantity] = '';

LET vStringNullCount = NoOfRows('_StringEncodedNulls');
IF $(vStringNullCount) > 0 THEN
    TRACE [WARNING] Found $(vStringNullCount) string-encoded null values in Order.Quantity;
    TRACE [INFO] Use vCleanNull variable to convert during load (see qlik-load-script);
ELSE
    DROP TABLE [_StringEncodedNulls];
END IF
```

### SQL Query (Source Comparison)

```sql
-- Detect string-encoded nulls in source
SELECT
    'Order.Quantity' AS FieldName,
    order_quantity AS SuspectValue,
    COUNT(*) AS Frequency
FROM orders
WHERE
    LOWER(order_quantity) IN ('null', 'nan', 'none', 'n/a', '#n/a') OR
    order_quantity = '[null]' OR
    order_quantity = '' OR
    order_quantity = 'NA'
GROUP BY order_quantity
ORDER BY Frequency DESC;
```

---

## Using These Queries

### During Reload (Embedded Checks)

1. Copy the Qlik Resident query pattern for your validation type
2. Parameterize table/field names to match your data model
3. Set thresholds (null rate %, sparsity %, cardinality range)
4. Embed in load script after relevant LOAD statements
5. Use TRACE or LogMessage to report findings

### Post-Load Inspection (MCP Comparison)

1. Copy the SQL query for your validation type
2. Execute against source database via MCP
3. Compare results against Qlik-loaded data using the Resident query
4. Document discrepancies in the Data Quality Validation Report

### Reporting

All validation queries output structured results that feed into the Data Quality Validation Report format defined in SKILL.md.
