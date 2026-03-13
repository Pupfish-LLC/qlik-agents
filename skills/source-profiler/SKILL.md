---
name: source-profiler
description: Data source profiling capability for Qlik development. When MCP connections are available, provides query templates and profiling procedures to assess source schemas, field types, cardinality, null rates, sample values, and data quality indicators. When MCP is unavailable, generates a structured Source Profile Template for manual completion. Includes source architecture classification (annotating tables with architectural role, key structure, mutability, incremental load pattern, and consumption implications). Load during requirements gathering or source profiling phases.
---

## Source Profiling for Data-Driven Architecture

Before designing a Qlik data model, you must understand the source data: what tables exist, what fields are in each table, what data types they use, how many distinct values exist in each field, whether null values are present, and what the source system's architecture pattern is (dimensional warehouse, normalized OLTP, Data Vault 2.0, flat files, etc.). Building a data model on incorrect assumptions about cardinality, key uniqueness, or data types produces models that fail on reload or produce silent data errors.

Source profiling is Phase 2 of the pipeline. The requirements-analyst invokes this skill with a **two-path design:**

- **Path A (MCP Available):** The requirements-analyst uses MCP database connections to run profiling queries directly against the source, automatically discovering schema metadata, cardinality, null rates, and sample values.
- **Path B (MCP Unavailable):** The requirements-analyst generates a structured **Source Profile Template** (see `profile-template.md`) for the developer to fill from their database tools (SQL Server Management Studio, pgAdmin, DBeaver, etc.).

Both paths produce the same standardized **Source Profile Report** that the data-architect uses in Phase 3 to design the Qlik data model.

The skill also includes **source architecture classification**, which annotates each table with its architectural role (Dimension, Fact, Lookup, Hub, Link, Satellite, etc.) and consumption implications (how Qlik should load and associate this table).

## Two-Path Profiling Workflow

### Path A: MCP Available

When the project has MCP database connections configured:

1. **Identify available data connections** from the Project Specification (Phase 1 output). Each connection has a name, type (ODBC, REST, etc.), and target (server, database, API endpoint).

2. **For each connection, run schema discovery queries** (provided below by database type) to list all tables and their fields.

3. **For each table, run column-level profiling queries** to assess:
   - Field name and data type (exactly as stored in source)
   - Cardinality (distinct value count)
   - Null rate (percentage of null values)
   - Min/Max values (for numeric and date fields)
   - Sample values (3-5 representative values)

4. **Classify each table's architectural role** (see Section 3 below) based on schema inspection: Is it a dimension (relatively static, has keys)? A fact (event records, larger row count)? A lookup table? A Data Vault hub, link, or satellite?

5. **Compile into Source Profile Report** using the standardized format defined in Section 6.

6. **Validate for completeness** and present to developer for confirmation.

### Path B: MCP Unavailable

When MCP connections are not available:

1. **Generate the Source Profile Template** (from `profile-template.md` in this skill directory) and provide it to the developer.

2. **Provide clear instructions** for the developer to fill the template using their own database tools:
   - Row counts: Run `SELECT COUNT(*) FROM [table_name]`
   - Cardinality: Run `SELECT COUNT(DISTINCT [column_name]) FROM [table_name]`
   - Sample values: Run `SELECT DISTINCT [column_name] FROM [table_name] LIMIT 5`
   - Data types: Query the database system catalog (information_schema for SQL databases)

3. **Developer completes the template** and returns it.

4. **Validate the completed template** for completeness (all required fields filled, sample values are realistic, no missing tables).

5. **The completed template IS the Source Profile Report.** No further transformation is needed.

## Column-Level Profiling Detail

For each column in a table, capture:

### 1. Column Metadata

- **Column name** — Exactly as it appears in the source system (e.g., `product_id`, `ProductName`, `CATEGORY_CODE`)
- **Data type** — Source system data type: VARCHAR(50), INT, DATETIME, DECIMAL(10,2), etc.
- **Nullable** — Whether the column allows NULL values (yes/no)

### 2. Cardinality and Uniqueness

- **Cardinality** — Approximate distinct value count. Range is fine (e.g., "~500 distinct products" vs. "~5M distinct transactions").
- **Null rate** — Percentage of rows where the column is NULL. If cardinality includes NULLs, note separately.
- **Uniqueness** — If this column is or could be a key, note whether values are unique (no duplicates). Check for composite key opportunities (e.g., does `[order_id, line_number]` form a unique key?).

### 3. Value Ranges and Sample Values

- **Min/Max** — For numeric fields, the minimum and maximum values. For date fields, the earliest and latest dates.
- **Sample values** — 3-5 representative values. For categorical fields, include common values. For numeric fields, show the range. Example: `['Active', 'Inactive', 'Pending']` or `[100, 5000, 99999]`.

### 4. Pattern Notes

- **String-encoded nulls** — Fields containing string values that represent missing data: `'null'`, `'NaN'`, `'none'`, `'n/a'`, `'[null]'`. These are data quality issues.
- **Mixed data types** — Columns that contain both numeric and string values. Qlik will attempt type coercion, often incorrectly.
- **Encoding artifacts** — Non-printable characters, leading/trailing spaces, bracket artifacts (`[`, `]`) that appear in string values.
- **Date format inconsistencies** — Different date formats in the same column (some records `YYYY-MM-DD`, others `MM/DD/YYYY`).

## MCP Profiling Queries by Database Type

When MCP connections are available, use these query templates to profile sources. Adapt field and table names to match the source.

### SQL Server / Azure SQL

**Schema Discovery (list all tables and columns):**
```sql
SELECT
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo'  -- Adjust schema name as needed
ORDER BY TABLE_NAME, ORDINAL_POSITION;
```

**Column-Level Profiling (run once per table):**
```sql
SELECT
    '[ColumnName]' AS column_name,
    COUNT(*) AS row_count,
    COUNT(DISTINCT [ColumnName]) AS cardinality,
    CAST(100.0 * SUM(CASE WHEN [ColumnName] IS NULL THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS null_percent,
    CAST(MIN([ColumnName]) AS VARCHAR(50)) AS min_value,
    CAST(MAX([ColumnName]) AS VARCHAR(50)) AS max_value,
    STRING_AGG(DISTINCT CAST([ColumnName] AS VARCHAR(50)), ', ') WITHIN GROUP (ORDER BY CAST([ColumnName] AS VARCHAR(50))) AS sample_values
FROM [TableName]
WHERE [ColumnName] IS NOT NULL;
```

### PostgreSQL

**Schema Discovery:**
```sql
SELECT
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'  -- Adjust schema name as needed
ORDER BY table_name, ordinal_position;
```

**Column-Level Profiling:**
```sql
SELECT
    'ColumnName' AS column_name,
    COUNT(*) AS row_count,
    COUNT(DISTINCT "ColumnName") AS cardinality,
    ROUND(100.0 * SUM(CASE WHEN "ColumnName" IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_percent,
    MIN("ColumnName"::TEXT) AS min_value,
    MAX("ColumnName"::TEXT) AS max_value,
    STRING_AGG(DISTINCT "ColumnName"::TEXT, ', ' ORDER BY "ColumnName"::TEXT) AS sample_values
FROM "TableName"
WHERE "ColumnName" IS NOT NULL
LIMIT 5;
```

### MySQL

**Schema Discovery:**
```sql
SELECT
    TABLE_NAME,
    COLUMN_NAME,
    COLUMN_TYPE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'database_name'  -- Adjust database name as needed
ORDER BY TABLE_NAME, ORDINAL_POSITION;
```

**Column-Level Profiling:**
```sql
SELECT
    'ColumnName' AS column_name,
    COUNT(*) AS row_count,
    COUNT(DISTINCT ColumnName) AS cardinality,
    ROUND(100.0 * SUM(CASE WHEN ColumnName IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_percent,
    MIN(CAST(ColumnName AS CHAR)) AS min_value,
    MAX(CAST(ColumnName AS CHAR)) AS max_value,
    GROUP_CONCAT(DISTINCT CAST(ColumnName AS CHAR) SEPARATOR ', ') AS sample_values
FROM TableName
WHERE ColumnName IS NOT NULL
LIMIT 5;
```

### Generic ANSI SQL Fallback

When the above database-specific queries don't work, use this generic approach (may be slower, works on most databases):

```sql
SELECT
    'ColumnName' AS column_name,
    COUNT(*) AS row_count,
    COUNT(DISTINCT ColumnName) AS cardinality,
    ROUND(100.0 * SUM(CASE WHEN ColumnName IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_percent,
    CAST(MIN(ColumnName) AS VARCHAR(50)) AS min_value,
    CAST(MAX(ColumnName) AS VARCHAR(50)) AS max_value
FROM TableName;
```

## Table-Level Profiling

For each table, capture:

- **Table name** — Exactly as it appears in the source system
- **Row count** — Current record count. Use `SELECT COUNT(*) FROM [table]`
- **Row count growth** — If available from audit tables or logs: rows added per day/week/month. Helps size QVDs and predict reload times.
- **Primary key** — Which column(s) form the unique key. Confirm uniqueness with `SELECT COUNT(*), COUNT(DISTINCT key_columns) FROM table`. If counts differ, the key is not unique.
- **Key uniqueness status** — "Confirmed unique", "Violations found", "Composite key required", or "No key"
- **Timestamp fields** — Which columns indicate record creation (created_at, insert_date), modification (updated_at, modified_date), or soft-delete (is_deleted, deleted_date)?
- **Refresh pattern** — How is this table updated in the source? Full refresh every load, append-only (inserts only), insert/update (upsert), insert/update/delete (with soft-delete flag)?

## Source Architecture Classification

This is the skill's unique contribution beyond standard column-level profiling. Each table's architectural role determines HOW Qlik should consume it (key strategy, incremental load approach, association rules).

See `architecture-classification.md` for the detailed classification decision tree, per-role consumption guide, and architecture type signatures.

For each table, classify:

1. **Architectural Role** — What is this table's purpose in the source system? Options: Dimension, Fact, Lookup, Staging, Hub (Data Vault), Link (Data Vault), Satellite (Data Vault), Bridge, Snapshot, Aggregate, Reference
2. **Key Structure** — What identifies a unique record? Options: Natural key, Surrogate key, Composite key, Hash key, No key
3. **Mutability** — How does the table change over time? Options: Immutable (append-only), Mutable (updated in place), SCD Type 1 (attributes overwritten), SCD Type 2 (versioned with effective dates), Temporal (bi-temporal with bi-temporal timestamps)
4. **Incremental Load Pattern** — How should Qlik incrementally load this table? Options: Full refresh, Insert-by-timestamp, Insert/Update-by-timestamp, Dual-timestamp (for SCD2), File-level detection (flat files), Not applicable
5. **Consumption Implication** — One-sentence guidance for how Qlik should join and aggregate this table. Example: "Surrogate key dimension with SCD Type 2 versioning. Use dual-timestamp incremental load. Join on surrogate key; filter for is_current=true when modeling current state."

## Cross-Table Profiling

When MCP is available, validate relationships between tables:

### Referential Integrity Checks

For fact tables with foreign keys pointing to dimensions, verify:
- Do all foreign key values in the fact table exist as primary keys in the dimension? Example: Does every `product_id` in `fact_orders` exist in `dim_product`?
- Run: `SELECT COUNT(DISTINCT fk_column) FROM fact_table WHERE fk_column NOT IN (SELECT pk_column FROM dim_table)`
- If count > 0, orphaned records exist.

### Field Name Collisions

Scan for field names that appear in multiple tables but are NOT intended as associations:
- Example: Both `Orders` and `Returns` tables have a `Status` field, but they're different status domains (order status vs. return status). In Qlik, identical field names create associations. These should be prefixed in the DataModel layer: `Order.Status`, `Return.Status`.
- This is a design decision, not a data quality issue. Surface it for the data architect's awareness.

### Relationship Mapping

For key-linked tables, identify the relationship cardinality:
- One-to-one: `product_id` in `dim_product` is unique; `product_id` in a product_details table is also unique.
- One-to-many: `customer_id` in `dim_customer` is unique; `customer_id` in `fact_orders` appears many times.
- Many-to-many: Order IDs and Product IDs are linked through a `order_line_items` table.

## Data Quality Indicators

During profiling, flag these data quality issues. They don't block profiling but inform the data architect's decisions:

### String-Encoded Nulls

Fields containing string values like `'null'`, `'NaN'`, `'none'`, `'n/a'` to represent missing data. These appear as valid values to Qlik, polluting filter panes. Flag for Qlik-side NullAsValue or source-side data cleaning.

### Mixed Data Types

Columns with both numeric and string values. Qlik attempts type coercion, often incorrectly. Flag for explicit casting in Qlik load script.

### Encoding Artifacts

Non-printable characters, leading/trailing spaces, bracket artifacts. Flag for data cleaning in Transform layer.

### Sparse Fields

Fields populated for less than 10% of records. Decide in Qlik: Should this be a separate dimension table (join only when populated) or handled via NullAsValue?

### Duplicate Key Candidates

If a table is supposed to have a unique primary key but the profiling query shows duplicates (`cardinality < row_count`), flag it. The data architect may need to create a composite key or investigate whether the table is actually append-only with key reuse.

## Source Profile Report Format

This is the standardized output format produced by both Path A (MCP) and Path B (manual template). The data-architect agent in Phase 3 consumes this format directly.

```markdown
# Source Profile Report

**Completion Date:** [date]
**Profiling Method:** [MCP queries | Manual template completion]

## Source Systems

### [Source System Name]

**Connection Details:**
- Type: [ODBC | REST | Folder | Other]
- Target: [Server, database, endpoint]
- Sample connection string: [example]

**Overall Architecture:** [Dimensional Warehouse | Normalized OLTP | Data Vault 2.0 | Flat Files/CSV | API | Other]

**Tables Profiled:** [count]

---

#### [Table Name]

**Metadata:**
- Row Count: [N]
- Primary Key: [field(s)]
- Key Uniqueness: [Confirmed | Violations found]
- Refresh Pattern: [Full refresh | Insert-by-timestamp | Insert/Update-by-timestamp | Dual-timestamp | File-level]

**Architectural Classification:**
- Role: [Dimension | Fact | Lookup | Hub | Link | Satellite | ...]
- Key Structure: [Natural key | Surrogate key | Composite key | Hash key]
- Mutability: [Immutable | Mutable | SCD Type 1 | SCD Type 2 | Temporal]
- Incremental Load Pattern: [Full refresh | Insert-by-timestamp | ...]

**Consumption Implication:**
[One sentence describing how Qlik should load and join this table]

**Column Inventory:**

| Column Name | Data Type | Cardinality | Null % | Min | Max | Sample Values | Notes |
|---|---|---|---|---|---|---|---|
| [name] | [type] | [count or ~range] | [%] | [value] | [value] | [val1, val2, val3] | [Any data quality flags] |

**Data Quality Flags:**
- [Any issues found: string-encoded nulls, mixed types, orphaned records, etc.]

**Cross-Table Notes:**
- [Referential integrity status]
- [Field name collision notes]
- [Relationship cardinality to other tables]

---

## Summary

[1-2 paragraph summary of overall source architecture, key tables, profiling completeness, and any significant data quality concerns]
```

## Supporting Documents

For source architecture classification decision logic and detailed role-specific consumption guidance, read `architecture-classification.md` in this skill directory.

For the structured profiling template used when MCP is unavailable, read `profile-template.md` in this skill directory.
