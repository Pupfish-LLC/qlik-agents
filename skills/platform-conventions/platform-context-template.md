# Platform Context Document

**Project:** [project name from Phase 1 specification]
**Date:** [completion date]
**Status:** [Draft | Confirmed]
**Source Materials:** [list of files from inputs/ that were analyzed: inputs/existing-apps/, inputs/platform-libraries/, inputs/upstream-architecture/]

---

## 1. Subroutine Inventory

Catalog of all reusable subroutines available in the platform. Each entry includes name, parameters, purpose, known limitations, and usage examples. Shared subroutines are candidates for reuse in this project.

### Subroutine Catalog

| Subroutine Name | Parameters | Purpose | Known Limitations | Example Usage |
|---|---|---|---|---|
| [SUB name] | [param1, param2, ...] | [What this subroutine does] | [What it does NOT handle] | [Example call] |

**Completed Example:**

| Subroutine Name | Parameters | Purpose | Known Limitations | Example Usage |
|---|---|---|---|---|
| MergeAndDrop | pTableName, pKeyField, pSourceTable, pTargetTable | Merges source table into target table using specified key field, then drops source table. Used to consolidate transformed data into model layer. | Single primary key only. Assumes key uniqueness (does not handle composite keys or duplicate keys). Requires source table and target table to already exist in memory. No error recovery if merge fails. | `CALL MergeAndDrop('Product', 'product_key', 'Transform_Product', 'Model_Product');` |
| ApplyMasterCalendar | pDateField, pTableName, pCalendarTable | Joins master calendar table to any table containing a date field. Creates associations for time-based aggregations (year, quarter, month, week, day). | Assumes calendar table already exists. Date field must be numeric (days since December 30, 1899) or DATE data type. Does not handle time-of-day precision beyond date. | `CALL ApplyMasterCalendar('Order.Date', 'Orders', 'MasterCalendar');` |

---

## 2. Naming Convention Map

Comparison of platform naming conventions against framework defaults. The "Decision" column indicates which convention this project will adopt.

### Field Naming Conventions

| Element | Platform Convention | Framework Default | Decision |
|---|---|---|---|
| Non-key fields | [observed pattern, e.g., `product_category` or `Product.Category`] | Entity.Attribute (e.g., `Product.Category`) | [platform \| framework \| hybrid] |
| Composite key fields | [e.g., `%` prefix vs. no prefix] | `%CompositeKey` (e.g., `%StoreScope`) | [platform \| framework \| hybrid] |
| Source system keys | [e.g., `product_id`, `_key` suffix] | `_key` suffix (e.g., `product_key`) | [platform \| framework \| hybrid] |
| Hidden fields | [e.g., HidePrefix, HideSuffix] | HidePrefix = '%', HideSuffix = '_key' | [platform \| framework \| hybrid] |

### Table Naming Conventions

| Element | Platform Convention | Framework Default | Decision |
|---|---|---|---|
| Dimension tables | [e.g., `dim_product`, `Product`] | Descriptive singular (e.g., `Product`) | [platform \| framework \| hybrid] |
| Fact tables | [e.g., `fact_orders`, `Orders`] | Action nouns (e.g., `Orders`) | [platform \| framework \| hybrid] |
| Temp/staging tables | [e.g., `_` prefix, `temp_` prefix] | `_` prefix (e.g., `_RawProducts`) | [platform \| framework \| hybrid] |
| Mapping/lookup tables | [e.g., `Map_`, `lkp_` prefix] | `Map_` prefix (e.g., `Map_StatusCode`) | [platform \| framework \| hybrid] |

### Variable and Expression Naming

| Element | Platform Convention | Framework Default | Decision |
|---|---|---|---|
| Variable prefix | [e.g., `v`, `var_`, no prefix] | `v` prefix (e.g., `vTotalRevenue`) | [platform \| framework \| hybrid] |
| Expression names | [e.g., "Total Revenue", "TotalRevenue", naming pattern] | Business-readable (e.g., `Total Revenue`) | [platform \| framework \| hybrid] |
| Master measure pattern | [observed pattern] | [MeasureType MeasureName], e.g., `Total Revenue` | [platform \| framework \| hybrid] |

### QVD and File Naming

| Element | Platform Convention | Framework Default | Decision |
|---|---|---|---|
| QVD layer prefix | [e.g., `Raw_`, `Transform_`, `Model_`] | LayerPrefix_TableName.qvd (e.g., `Raw_Orders.qvd`) | [platform \| framework \| hybrid] |
| QVD date stamping | [e.g., `Table_20260301.qvd`, not used] | Optional for incremental: `Table_YYYYMMDD.qvd` | [platform \| framework \| hybrid] |
| Script file prefix | [e.g., numeric `01_`, `02_`, or other] | Numeric prefix for execution order (e.g., `01_Config.qvs`) | [platform \| framework \| hybrid] |

**Completed Example:**

| Element | Platform Convention | Framework Default | Decision |
|---|---|---|---|
| Non-key fields | `entity_attribute` (e.g., `product_name`, `order_status`) | Entity.Attribute (e.g., `Product.Name`, `Order.Status`) | Framework (project is greenfield, will adopt dot notation to match other platform Qlik apps deployed this year) |
| Key field suffixes | `_id` (e.g., `product_id`, `customer_id`) | `_key` (e.g., `product_key`) | Platform (existing shared subroutines expect `_id`; cost of refactoring exceeds benefit) |
| Dimension table prefix | `dim_` (e.g., `dim_product`) | Descriptive singular (e.g., `Product`) | Platform (maintains consistency with existing fact/dimension naming) |

---

## 3. Connection Catalog

All data connections (ODBC, OLEDB, REST, folder) available in the platform. Include name, type, target system, path pattern, QVD root, and environment variations.

### Data Connections

| Connection Name | Type | Target System | Path Pattern | QVD Root | Environment Variations |
|---|---|---|---|---|---|
| [Name] | [ODBC \| OLEDB \| REST \| Folder \| Other] | [Server, database, or endpoint] | [lib://ConnectionName/path/] | [Root folder for QVDs] | [Dev/Test/Prod differences] |

**Completed Example:**

| Connection Name | Type | Target System | Path Pattern | QVD Root | Environment Variations |
|---|---|---|---|---|---|
| WarehouseConnection | ODBC | SQL Server: db-prod.company.com / DataWarehouse | lib://WarehouseConnection/[Schema]/[Table].qvd | /data/qvd/warehouse/ | Dev: db-dev.company.com; Test: db-qa.company.com; Prod: db-prod.company.com |
| SalesSystemAPI | REST | Salesforce Production | lib://SalesforceAPI/sobjects/[object_type] | /data/qvd/salesforce/ | Dev uses sandbox.salesforce.com; Prod uses login.salesforce.com |
| SharedQVDFolder | Folder | Network share: \\company\data\qvd | lib://SharedQVD/ | \\company\data\qvd | All environments point to same network share (centralized QVD store) |

---

## 4. Reference App Analysis

For each reference application in the platform, document its architecture, patterns to adopt, patterns to avoid, and specific implementation details.

### Reference Application: [App Name]

**Architecture:** [Single-app / Multi-app with QVD flows]
**QVD Flow (if multi-app):** [Diagram or description: "Extract app produces Raw_*.qvd → Transform app consumes and produces Transform_*.qvd → Model app consumes and produces Model_*.qvd"]

**Patterns to Adopt (with examples):**
- [Pattern 1 and why it works well]: Example: "Uses entity-prefix field naming consistently. All non-key fields are prefixed. Result: No accidental synthetic keys, filter panes are self-documenting."
- [Pattern 2]: Example description
- [Pattern 3]: Example description

**Patterns to Avoid (with examples and reasons):**
- [Anti-pattern 1 and why it fails]: Example: "Temp tables loaded but not dropped. Result: Temp tables appear in the data model, sharing fields with final tables, creating synthetic keys."
- [Anti-pattern 2]: Example and consequence
- [Anti-pattern 3]: Example and consequence

**Field Naming Observed:**
- Key fields: [pattern observed]
- Dimension fields: [pattern observed]
- Fact fields: [pattern observed]
- Calculated fields: [pattern observed]

**Expression Patterns Used:**
- [Master measure pattern]: Example: "Total Revenue = Sum([Order.Amount]); Total Orders = Count(Distinct [Order.Order_ID])"
- [Master dimension pattern]: Example: [any observed patterns]
- [Set analysis patterns]: Example: [if used]

**Sheet Layout Patterns:**
- [Organization of filter panes, visualizations, navigation]

**Completed Example:**

### Reference Application: Orders and Fulfillment Platform

**Architecture:** Single-app (all extraction, transformation, and modeling in one app)
**QVD Flow:** Not applicable (no multi-app architecture)

**Patterns to Adopt:**
- Uses entity-prefix field naming (`Order.Status`, `Customer.Region`, `Product.Category`). Result: No synthetic keys, clean data model.
- Shared subroutines for calendar join (ApplyMasterCalendar) and incremental reload detection. Reusable across apps.
- TRACE diagnostic output at each ETL layer boundary (Extract, Transform, Model). Easy to troubleshoot reload issues.

**Patterns to Avoid:**
- Calendar table loaded twice (once raw, once in model layer). Should drop the raw version. Result: Unnecessary memory usage.
- Some expressions stored in app visuals instead of as master items. Result: Expressions are difficult to maintain and test.

**Field Naming Observed:**
- Key fields: Use `_id` suffix (`order_id`, `customer_id`, `product_id`)
- Dimension fields: Entity-prefix dot notation (`Customer.Name`, `Product.Category`)
- Fact fields: Entity-prefix dot notation (`Order.Amount`, `Order.Date`)
- Calculated fields: Use `_calc` suffix for derived fields (`Customer.Revenue_Calc`, `Order.NetAmount_Calc`)

**Expression Patterns Used:**
- Master measure pattern: "Total [Entity] [Measure]" (e.g., "Total Orders", "Total Revenue"). Backed by variable `v[Entity][Measure]`.
- Set analysis: Most aggregates use `{1}` to ignore selections on time dimensions, allowing year-over-year comparisons.

**Sheet Layout Patterns:**
- Left panel: Filters (date range, customer region, product category, order status)
- Center/right: KPIs (Total Revenue, Order Count, Avg Order Value), trend charts, and drill-down tables
- Navigation: Tabs per business function (Sales Overview, Customer Analytics, Product Performance)

---

## 5. Upstream Architecture Classification

Classification of the source data architecture (if profiled in Phase 2) and per-table architectural annotations.

**Overall Architecture Type:** [Dimensional Warehouse | Normalized OLTP | Data Vault 2.0 | Flat Files / CSV | API | Other]

### Per-Table Annotations

| Table Name | Architectural Role | Key Structure | Mutability | Incremental Load Pattern | Consumption Note |
|---|---|---|---|---|---|
| [source table] | [Dimension \| Fact \| Lookup \| Staging \| Hub \| Link \| Satellite \| Bridge \| Snapshot] | [Natural key \| Surrogate key \| Composite key \| Hash key \| No key] | [Immutable \| Mutable \| SCD Type 1 \| SCD Type 2 \| Temporal] | [Full refresh \| Insert-by-timestamp \| Insert/Update-by-timestamp \| Dual-timestamp \| File-level detection \| Not applicable] | [One sentence describing how Qlik should consume this table] |

**Status:** [Completed (Phase 2 source profiling done) | Pending source profiling (Phase 2 not yet executed)]

**Completed Example:**

**Overall Architecture Type:** Dimensional Warehouse

| Table Name | Architectural Role | Key Structure | Mutability | Incremental Load Pattern | Consumption Note |
|---|---|---|---|---|---|
| dim_customer | Dimension | Surrogate key (customer_id) with business key (account_number) | SCD Type 2 (effective_from, effective_to, is_current) | Insert-only hub, dual-timestamp for satellites | Load surrogate key as association; join on customer_id. Capture both open and closed records (effective_to < today). |
| fact_orders | Fact | Composite: (order_id, order_line_number) | Insert-only (fact tables immutable) | Insert-by-timestamp (order_date > max previous reload) | Grain is order line. Load all historical orders; incremental loads after initial full refresh. Key is composite; create bridge if needed. |
| dim_product | Dimension | Surrogate key (product_id) | SCD Type 1 (attributes overwritten) | Full refresh daily | Product hierarchy is denormalized in source. Surrogate key may change; join on business key (sku) or precompute product_id at extraction. |

---

## 6. Platform Constraints Register

Platform-level limits, deployment model, security model, and other constraints that affect development.

### Deployment Model

**Type:** [Cloud | Client-Managed | Hybrid]

**Details:** [Environment tiers, their purposes, and any development workflow (dev → test → prod)]

### Security Model

**Approach:** [Section Access | Stream Security | Identity Provider Integration | Other]

**Identity Provider:** [Okta | Azure AD | LDAP | Static credentials | Other]

**Section Access Table Location:** [Embedded in app | External connection | Other]

**Notes:** [Any special security requirements or constraints]

### Performance Boundaries

| Boundary | Limit | Impact |
|---|---|---|
| Maximum app size | [e.g., 2 GB] | [e.g., Must archive old QVDs if app exceeds size] |
| Maximum reload time | [e.g., 1 hour] | [e.g., Incremental loads required for large tables] |
| Maximum concurrent users | [e.g., 100] | [e.g., Aggregate tables or caching strategies required for heavy analytics] |
| Maximum number of associations | [e.g., No synthetic keys allowed] | [e.g., Field naming must prevent accidental associations] |

### Subroutine Limitations (Cross-Reference to Inventory)

- [Subroutine name]: [Known limitation from Inventory section]
- Example: "MergeAndDrop: Single primary key only; does not handle composite keys"

### Environment-Specific Constraints

**Development Environment:**
- [Constraint]: [Impact]

**Test Environment:**
- [Constraint]: [Impact]

**Production Environment:**
- [Constraint]: [Impact]

**Completed Example:**

### Deployment Model

**Type:** Cloud (Qlik Sense SaaS)

**Details:** Three environments: Development (personal dev space for developers), Test (shared test space for QA), Production (managed content space for end users). Promotion workflow: Develop in Dev space → Export to Test → Run validation suite → Import to Prod via change control ticket.

### Security Model

**Approach:** Stream Security with Section Access

**Identity Provider:** Azure AD

**Section Access Table Location:** External SQL Server table. Updated nightly via automated sync from Azure AD groups.

**Notes:** New developers must be added to Azure AD group "Qlik-Developers" to gain access to development environments. All apps in Production must have Section Access defined; dev/test apps do not require Section Access.

### Performance Boundaries

| Boundary | Limit | Impact |
|---|---|---|
| Maximum app size | 1.5 GB | QVD archive strategy for tables older than 2 years. Implement aggregate tables if app approaches 1.2 GB. |
| Maximum reload time | 90 minutes | Reload job scheduled nightly (11 PM - 1:30 AM). Incremental loads required for any table with >10M rows. |
| Maximum concurrent users | 50 | No more than 50 users may load the same app simultaneously. High-traffic apps implemented with in-memory caches and aggregate tables. |
| Synthetic key tolerance | Zero | Strict rule: No synthetic keys in production apps. Data architect reviews all data models. |

### Subroutine Limitations (Cross-Reference to Inventory)

- **MergeAndDrop:** Single primary key only. Use data architect for composite key merge strategies.
- **ApplyMasterCalendar:** Assumes date field is numeric or DATE type. Cannot handle bi-temporal date ranges.

### Environment-Specific Constraints

**Development Environment:**
- No size limits. QVDs may be stored locally or on network share.
- No reload time limits. Ad hoc reloads during development are unrestricted.
- No Section Access required.

**Test Environment:**
- Maximum app size: 1 GB. Must validate that app compresses to <1 GB before promotion to Prod.
- Reload time limit: 60 minutes. Must demonstrate reload completes within 60 minutes before promotion.
- Section Access required (matches production configuration).

**Production Environment:**
- Maximum app size: 1.5 GB. Apps exceeding 1.5 GB will be rejected at deployment gate.
- Reload time limit: 90 minutes. Changes that extend reload >90 minutes require architecture review.
- Section Access mandatory. All apps use Section Access with Azure AD group mapping.
- Change control: All app updates require ticket in change management system. Requires data architect approval.

---

## Notes and Reconciliation Decisions

Use this section to document any decisions made during Phase 0 that affect downstream development:

- [Decision 1]: [Reasoning and impact on Phases 1-8]
- [Decision 2]: [Reasoning and impact]
- [Convention conflict resolutions]: [Which convention was chosen and why]
- [Blocked dependencies]: [If any platform context was unavailable, note it here and plan for Phase 0 revisit]

**Completed Example:**

- **Naming Convention Reconciliation:** Platform uses `_id` suffix for keys; framework default is `_key`. Decision: Adopt platform `_id` to maintain compatibility with existing shared subroutines (MergeAndDrop, ApplyMasterCalendar). All keys in this project will use `_id` suffix.
- **Blocked Dependency:** Platform library documentation was not provided. Assumed subroutines in `inputs/platform-libraries/` are complete. Developer to confirm subroutine inventory in Phase 0 handoff.
- **Greenfield Decision:** No existing applications in `inputs/existing-apps/`. This is a greenfield project. Framework defaults will be used for all conventions. Platform Context Document serves as decision record.

