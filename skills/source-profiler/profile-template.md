# Source Profile Template

Use this template to manually profile data sources when MCP connections are not available. Complete one section per table. Use your database tools (SQL Server Management Studio, pgAdmin, DBeaver, etc.) to gather the required information.

**Instructions:**
1. For each source table, copy the table template below and fill in the values.
2. Row count: Execute `SELECT COUNT(*) FROM [TableName]`
3. Cardinality per column: Execute `SELECT COUNT(DISTINCT [ColumnName]) FROM [TableName]` (or `SELECT COUNT(DISTINCT ColumnName) FROM TableName` for unquoted names)
4. Null rate: Execute `SELECT COUNT(*) FROM [TableName] WHERE [ColumnName] IS NULL` and divide by row count
5. Sample values: Execute `SELECT DISTINCT [ColumnName] FROM [TableName] LIMIT 5` (adjust LIMIT as needed; different databases use different syntax)
6. Data types: Query the database system catalog (INFORMATION_SCHEMA.COLUMNS for SQL databases, etc.)

**Estimated time to complete:** 1-2 hours for a typical 10-20 table source, depending on table sizes and query performance.

---

## Source System: [Source System Name]

**Connection Details:**
- Type: [ODBC | OLEDB | REST | Folder | Other]
- Target: [Database server, schema, or API endpoint]
- Sample connection string or path: [Example: `server=db-prod.company.com;database=DataWarehouse` or `https://api.salesforce.com/v57.0`]

**Overall Architecture:** [Dimensional Warehouse | Normalized OLTP | Data Vault 2.0 | Flat Files/CSV | API | Other]

**Tables in this source:** [Count or list of table names]

---

## COMPLETED EXAMPLE: dim_customer

**Copy this as a template for each of your tables. This example is based on a retail data warehouse.**

### Metadata

| Attribute | Value |
|-----------|-------|
| Table Name | dim_customer |
| Row Count | 125,400 |
| Primary Key | customer_id |
| Key Uniqueness | Confirmed unique (SELECT COUNT(*), COUNT(DISTINCT customer_id) both return 125,400) |
| Refresh Pattern | Full refresh nightly (entire table reloaded) |

### Architectural Classification

| Classification | Value |
|---|---|
| Role | Dimension (slowly-changing dimension) |
| Key Structure | Surrogate key (customer_id is auto-increment integer) with business key (email is unique account identifier) |
| Mutability | SCD Type 2 (attributes overwritten, effective_from / effective_to versioning) |
| Incremental Load Pattern | Full refresh (no incremental approach; entire dimension reloaded nightly) |
| Consumption Implication | Load surrogate key as association to fact tables. Join on customer_id. Filter for is_current=1 when modeling current customer state. Handle historical versions with dual timestamp or version flag. |

### Column Inventory

| Column Name | Data Type | Cardinality | Null % | Min | Max | Sample Values | Notes |
|---|---|---|---|---|---|---|---|
| customer_id | INT | 125,400 | 0% | 1 | 125,400 | [1, 50000, 125400] | Auto-increment primary key, never null |
| email | VARCHAR(100) | 125,350 | 0.04% | [null] | [z@example.com] | [alice@example.com, bob@example.com, charlie@example.com] | Business key, almost unique (few duplicates). Some records have null email. |
| customer_name | VARCHAR(100) | ~110,000 | 2% | [null] | [Zoe Smith] | [Alice Johnson, Bob Williams, Charlie Brown] | Full name. ~2,500 nulls (legacy records). Average length 25 characters. |
| customer_segment | VARCHAR(50) | 5 | 0% | [null] | [Premium] | [Standard, Premium, VIP, Inactive, New] | Status values only. No nulls. Used for RLS. |
| created_date | DATE | ~2000 | 0% | 2015-01-01 | 2026-03-01 | [2015-03-15, 2020-06-20, 2025-11-10] | Customer acquisition date. No nulls. Earliest customer from 2015. |
| effective_from | DATE | ~2000 | 0% | 2015-01-01 | 2026-03-01 | [2015-03-15, 2020-06-20, 2025-11-10] | SCD Type 2 versioning start date. Matches created_date for first version. |
| effective_to | DATE | ~2000 | 15% | 2016-01-01 | 2026-03-01 | [2016-04-30, 2022-08-15, 2025-12-31] | SCD Type 2 versioning end date. Null for current versions (is_current=1). ~18,810 records have null effective_to. |
| is_current | TINYINT | 2 | 0% | 0 | 1 | [0, 1] | Flag: 1 = current version, 0 = historical. Use to filter to current state. |
| address | VARCHAR(200) | ~120,000 | 5% | [null] | [Zoe Way, ...] | [123 Main St, 456 Oak Ave, 789 Pine Rd] | Mutable field. Changes captured by SCD2. ~6,270 nulls. |
| city | VARCHAR(50) | ~8,000 | 2% | [null] | [Zoe City] | [New York, Los Angeles, Chicago] | City name. ~2,508 nulls. |
| state | VARCHAR(2) | 52 | 1% | [null] | [ZZ] | [NY, CA, TX] | US state code. ~1,254 nulls (international addresses). 50 states plus DC and military codes. |
| country | VARCHAR(50) | 3 | 0% | [null] | [USA] | [USA, Canada, Mexico] | Country. Only 3 distinct values. No nulls. |
| phone | VARCHAR(20) | ~120,000 | 10% | [null] | [999-999-9999] | [555-0100, 555-0200, 555-0300] | Phone number. ~12,540 nulls. Multiple formats observed. |

### Data Quality Flags

- **Null handling:** Several columns have nulls (email 0.04%, customer_name 2%, address 5%, phone 10%). Null rate is reasonable; no fields have excessive nulls (>50%).
- **String encoding:** No string-encoded nulls detected (e.g., 'null' as text). Actual NULL values used.
- **Date consistency:** Dates are consistent DATE type. No mixed format issues.
- **Key integrity:** Primary key is unique and never null. Business key (email) is almost unique (~99.96% unique) but has duplicates; investigate during Phase 2 detailed profiling.

### Cross-Table Notes

- **Referential Integrity:** dim_customer is a dimension. Expected to have foreign key references from fact_orders (customer_id). Verify in Phase 2 that all customer_ids in fact_orders exist in dim_customer.
- **SCD Type 2 Handling:** This dimension uses SCD Type 2 (slowly changing dimension, version tracking). Qlik load script must:
  - Load all historical versions (do NOT filter for is_current=1 during load; keep history for time-travel analysis)
  - Join fact tables on customer_id + date association (use effective_from and effective_to to capture which version was current on the order date)
- **Null Handling:** Nulls in address, city, state, phone are legitimate (international records, privacy-opted-out, etc.). Do not treat as data quality issues. Qlik NullAsValue() may be needed for filter panes.

---

## Template: [Table Name 1]

**Copy this template for each table in your source. Fill in all values. Remove this template after copying.**

### Metadata

| Attribute | Value |
|-----------|-------|
| Table Name | [Exactly as in source database] |
| Row Count | [SELECT COUNT(*) FROM table_name] |
| Primary Key | [Which column(s) form the unique key?] |
| Key Uniqueness | [Confirmed unique / Violations found / Composite key required / No key] |
| Refresh Pattern | [Full refresh / Append-only / Insert/Update / Insert/Update/Delete] |

### Architectural Classification

| Classification | Value |
|---|---|
| Role | [Dimension / Fact / Lookup / Staging / Hub / Link / Satellite / Bridge / Snapshot / Aggregate / Reference] |
| Key Structure | [Natural key / Surrogate key / Composite key / Hash key / No key] |
| Mutability | [Immutable / Mutable / SCD Type 1 / SCD Type 2 / Temporal] |
| Incremental Load Pattern | [Full refresh / Insert-by-timestamp / Insert/Update-by-timestamp / Dual-timestamp / File-level detection / Not applicable] |
| Consumption Implication | [One sentence: How should Qlik consume this table? Example: "Fact grain is order line. Load with insert-by-timestamp incremental pattern. Join on order_id and order_line_number."] |

### Column Inventory

| Column Name | Data Type | Cardinality | Null % | Min | Max | Sample Values | Notes |
|---|---|---|---|---|---|---|---|
| [col1] | [type] | [count or ~range] | [%] | [val] | [val] | [val1, val2, val3] | [Any quality flags] |
| [col2] | [type] | [count or ~range] | [%] | [val] | [val] | [val1, val2, val3] | [Any quality flags] |

### Data Quality Flags

- [Any issues: string-encoded nulls, mixed types, encoding artifacts, sparse fields, duplicate key candidates, etc.]

### Cross-Table Notes

- [Referential integrity status: Does this table have foreign keys? Do values exist in related tables?]
- [Relationship cardinality to other tables: One-to-one / One-to-many / Many-to-many]
- [Field naming collisions with other tables: Are there fields with the same name in different tables that should NOT associate?]

---

## Template: [Table Name 2]

### Metadata

| Attribute | Value |
|-----------|-------|
| Table Name | [Exactly as in source database] |
| Row Count | [SELECT COUNT(*) FROM table_name] |
| Primary Key | [Which column(s) form the unique key?] |
| Key Uniqueness | [Confirmed unique / Violations found / Composite key required / No key] |
| Refresh Pattern | [Full refresh / Append-only / Insert/Update / Insert/Update/Delete] |

### Architectural Classification

| Classification | Value |
|---|---|
| Role | [Dimension / Fact / Lookup / Staging / Hub / Link / Satellite / Bridge / Snapshot / Aggregate / Reference] |
| Key Structure | [Natural key / Surrogate key / Composite key / Hash key / No key] |
| Mutability | [Immutable / Mutable / SCD Type 1 / SCD Type 2 / Temporal] |
| Incremental Load Pattern | [Full refresh / Insert-by-timestamp / Insert/Update-by-timestamp / Dual-timestamp / File-level detection / Not applicable] |
| Consumption Implication | [One sentence describing Qlik consumption strategy] |

### Column Inventory

| Column Name | Data Type | Cardinality | Null % | Min | Max | Sample Values | Notes |
|---|---|---|---|---|---|---|---|
| [col1] | [type] | [count or ~range] | [%] | [val] | [val] | [val1, val2, val3] | [Any quality flags] |
| [col2] | [type] | [count or ~range] | [%] | [val] | [val] | [val1, val2, val3] | [Any quality flags] |

### Data Quality Flags

- [Any issues]

### Cross-Table Notes

- [Referential integrity status]
- [Relationship cardinality]
- [Field naming collisions]

---

## Template: [Table Name 3]

### Metadata

| Attribute | Value |
|-----------|-------|
| Table Name | |
| Row Count | |
| Primary Key | |
| Key Uniqueness | |
| Refresh Pattern | |

### Architectural Classification

| Classification | Value |
|---|---|
| Role | |
| Key Structure | |
| Mutability | |
| Incremental Load Pattern | |
| Consumption Implication | |

### Column Inventory

| Column Name | Data Type | Cardinality | Null % | Min | Max | Sample Values | Notes |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

### Data Quality Flags

-

### Cross-Table Notes

-

---

## Profiling Query Reference

Use these queries in your database tool to gather profiling data:

### SQL Server

**Count all rows:**
```sql
SELECT COUNT(*) FROM [TableName]
```

**Cardinality and null count for one column:**
```sql
SELECT
    COUNT(DISTINCT [ColumnName]) AS cardinality,
    SUM(CASE WHEN [ColumnName] IS NULL THEN 1 ELSE 0 END) AS null_count,
    CAST(100.0 * SUM(CASE WHEN [ColumnName] IS NULL THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS null_percent
FROM [TableName]
```

**Sample values:**
```sql
SELECT DISTINCT TOP 5 [ColumnName] FROM [TableName] ORDER BY [ColumnName]
```

### PostgreSQL

**Count all rows:**
```sql
SELECT COUNT(*) FROM "TableName"
```

**Cardinality and null count for one column:**
```sql
SELECT
    COUNT(DISTINCT "ColumnName") AS cardinality,
    SUM(CASE WHEN "ColumnName" IS NULL THEN 1 ELSE 0 END) AS null_count,
    ROUND(100.0 * SUM(CASE WHEN "ColumnName" IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_percent
FROM "TableName"
```

**Sample values:**
```sql
SELECT DISTINCT "ColumnName" FROM "TableName" ORDER BY "ColumnName" LIMIT 5
```

### MySQL

**Count all rows:**
```sql
SELECT COUNT(*) FROM `TableName`
```

**Cardinality and null count for one column:**
```sql
SELECT
    COUNT(DISTINCT `ColumnName`) AS cardinality,
    SUM(CASE WHEN `ColumnName` IS NULL THEN 1 ELSE 0 END) AS null_count,
    ROUND(100.0 * SUM(CASE WHEN `ColumnName` IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_percent
FROM `TableName`
```

**Sample values:**
```sql
SELECT DISTINCT `ColumnName` FROM `TableName` ORDER BY `ColumnName` LIMIT 5
```

### Oracle

**Count all rows:**
```sql
SELECT COUNT(*) FROM TableName
```

**Cardinality and null count for one column:**
```sql
SELECT
    COUNT(DISTINCT ColumnName) AS cardinality,
    SUM(CASE WHEN ColumnName IS NULL THEN 1 ELSE 0 END) AS null_count,
    ROUND(100.0 * SUM(CASE WHEN ColumnName IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_percent
FROM TableName
```

**Sample values:**
```sql
SELECT DISTINCT ColumnName FROM TableName WHERE ROWNUM <= 5 ORDER BY ColumnName
```

---

## Completed Sections Summary

**Tables completed:** [X / Y]

**Tables requiring follow-up:**
- [Table name]: [Issue to resolve]

**Notes:**
- [Any blocked dependencies or outstanding questions]
- [Assumption made during profiling]
- [Validation steps needed in Phase 2]

