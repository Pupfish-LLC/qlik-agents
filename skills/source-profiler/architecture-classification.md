# Source Architecture Classification Guide

This guide helps you identify the source data architecture pattern (Dimensional Warehouse, Normalized OLTP, Data Vault 2.0, flat files, etc.) and classify each table within that architecture with its architectural role, key structure, mutability, and incremental load strategy.

The output of this classification is consumed by the data-architect agent in Phase 3 to design the Qlik data model and determine join strategies and key resolution approaches.

---

## Part 1: Identifying Overall Architecture Type

Use this decision tree to classify the source system's overall architecture pattern. Look at the table naming conventions, schema structure, and key design.

### Decision Tree

**1. Does the schema include tables with names like hub_*, link_*, sat_* or explicit hub/link/satellite naming?**
- YES → Go to Data Vault 2.0 (Section 2.3)
- NO → Continue to question 2

**2. Does the schema have tables with suffixes _dim, dim_, _fact, fact_, or explicit dimension/fact naming?**
- YES → Go to Dimensional Warehouse (Section 2.1)
- NO → Continue to question 3

**3. Does the schema consist primarily of normalized tables with many foreign keys, no explicit surrogate keys, and operational timestamps (created_at, updated_at)?**
- YES → Go to Normalized OLTP (Section 2.2)
- NO → Continue to question 4

**4. Are the source data files CSV, delimited text, or unstructured? Are there header rows with column names?**
- YES → Go to Flat Files / CSV (Section 2.4)
- NO → Continue to question 5

**5. Are the data accessed via REST API, webhooks, or third-party data service?**
- YES → Go to API Sources (Section 2.5)
- NO → Classify as "Other" and describe the schema manually

---

## Part 2: Architecture Type Signatures and Patterns

### 2.1 Dimensional Warehouse

**Also known as:** Star schema, kimball model

**Identification Criteria:**
- Explicit dimension table naming: `dim_customer`, `dim_product`, `dim_store`, `dim_date`
- Explicit fact table naming: `fact_orders`, `fact_sales`, `fact_returns`
- Dimension tables have surrogate keys (auto-increment integers): `customer_id`, `product_id`
- Dimension tables have business keys (natural identifiers from the source): `email`, `sku`, `account_number`
- Dimension tables often include SCD (Slowly Changing Dimension) columns: `effective_from`, `effective_to`, `is_current`, or `dw_insert_date`, `dw_update_date`
- Fact tables have composite keys: (`order_id`, `line_number`) or foreign keys pointing to dimension surrogate keys
- Fact tables have additive measures (amounts, counts) and non-additive dimensions (descriptions)

**Example Schema:**
```
dim_customer (customer_id, email, name, region, effective_from, effective_to, is_current)
dim_product (product_id, sku, category, price_at_load_date, effective_from, effective_to)
dim_date (date_id, date, year, quarter, month, day_of_week)
fact_orders (order_id, line_number, customer_id, product_id, date_id, quantity, amount)
```

**Key Characteristics:**
- **Predictable:** Easy to understand and design Qlik models around
- **Denormalized:** Dimension tables often have wide attribute lists (50+ columns) because every attribute is in the dimension
- **SCD handling:** SCD Type 1 (overwrite) or SCD Type 2 (version) approaches are explicit in the schema
- **Indexing:** Often has explicit indexing strategies (star join indexes in data warehouse systems)

**Consumption Strategy for Qlik:**
- Load all dimension tables as-is (usually small enough to fit in memory)
- Load fact tables with grain explicitly identified (order, order line, transaction)
- Use surrogate keys for associations
- If SCD Type 2: capture effective_from/effective_to and filter or join by date context
- Incremental loads often use `dw_insert_date` or `dw_update_date` to detect new/changed rows

### 2.2 Normalized OLTP

**Also known as:** Third-normal form (3NF), operational database

**Identification Criteria:**
- Tables decomposed to minimal redundancy: customer, orders, order_items, products, payments, shipments (many tables, each with narrow purpose)
- No explicit surrogate key columns; keys are business-oriented (`account_number`, `order_number`)
- If surrogate keys exist, they're usually sequential IDs with minimal metadata
- Operational timestamps abundant: `created_date`, `modified_date`, `deleted_flag`, `status`
- Foreign keys prevalent but often referenced through business keys, not surrogate keys
- No DW-specific columns like `effective_from`, `effective_to`, `dw_load_date`

**Example Schema:**
```
customer (customer_id, account_number, name, email, created_date, modified_date)
orders (order_id, order_number, customer_id, order_date, status, created_date)
order_items (order_item_id, order_id, product_id, quantity, unit_price, created_date)
products (product_id, sku, name, category, price, created_date, modified_date)
payments (payment_id, order_id, payment_date, amount, payment_method)
shipments (shipment_id, order_id, shipment_date, carrier, tracking_number)
```

**Key Characteristics:**
- **Highly normalized:** Tables are linked through many foreign keys, producing many joins
- **Transaction-oriented:** Each table represents a business entity or transaction type
- **No pre-aggregation:** Unlike dimensional warehouses, no pre-calculated aggregates; must aggregate on demand
- **Mutable:** Records are updated in place (no versioning); soft-delete flags used

**Consumption Strategy for Qlik:**
- Do NOT load raw OLTP schema into Qlik; the many-to-many relationships and heavy normalization produce cartesian products
- Instead, use OLTP as a source for ETL: extract normalized tables, transform (denormalize) into a dimensional model, load into Qlik
- If loading raw OLTP directly (not recommended), create composite keys to avoid producing too many synthetic keys in Qlik
- Incremental loads use `created_date`, `modified_date`, or status flags; identify which tables are insert-only vs. insert/update vs. insert/update/delete
- Handle mutable status fields carefully: a status change updates the record in place; capture history via versioning in Qlik if needed

### 2.3 Data Vault 2.0

**Also known as:** Hub-link-satellite (HLS) model

**Identification Criteria:**
- Explicit table naming conventions: `hub_*`, `link_*`, `sat_*` or clear hub/link/satellite suffixes
- Hub tables: contain business keys and a `hub_hash_key` (32-char hex hash), `load_date`, `record_source`
  - Example: `hub_customer (customer_hash_key, customer_id, load_date, record_source)` where `customer_id` is the business key
- Link tables: contain foreign keys to multiple hubs and a `link_hash_key`
  - Example: `link_customer_product_order (link_hash_key, customer_hash_key, product_hash_key, order_hash_key, load_date, record_source)`
- Satellite tables: contain descriptive attributes, linked to a hub or link via hash key, with `load_date` and `load_end_date` (or `effective_from`/`effective_to`)
  - Example: `sat_customer_details (customer_hash_key, load_date, load_end_date, name, email, region, record_source)`
- Every table includes `load_date` and `record_source` columns (metadata about when data was loaded and from which source system)
- Hash keys are deterministic (computed from business keys), enabling idempotent loads

**Example Schema:**
```
hub_customer (customer_hash_key, customer_id, load_date, record_source)
hub_product (product_hash_key, product_id, load_date, record_source)
hub_order (order_hash_key, order_id, load_date, record_source)

link_customer_order (link_hash_key, customer_hash_key, order_hash_key, load_date, record_source)
link_order_product (link_hash_key, order_hash_key, product_hash_key, load_date, record_source)

sat_customer_profile (customer_hash_key, load_date, load_end_date, name, email, region, record_source)
sat_product_attributes (product_hash_key, load_date, load_end_date, category, price, description, record_source)
sat_order_context (order_hash_key, load_date, load_end_date, status, order_date, record_source)
```

**Key Characteristics:**
- **Hub-centric:** Hubs define the core business entities. Links define relationships. Satellites define attributes.
- **Immutable:** All tables are insert-only (no updates). Slowly changing attributes are handled via satellite versioning (load_date, load_end_date).
- **Scalable:** Easy to add new satellites without changing hub/link structure.
- **Auditability:** load_date and record_source provide complete lineage.
- **Hash keys:** Deterministic hashing of business keys enables idempotent processing (loading the same source record twice doesn't create duplicates).

**Consumption Strategy for Qlik (Complex):**
- Do NOT load raw Data Vault schema into Qlik; the many satellites and hash-key associations will produce a confusing model
- Instead, use Data Vault as a staging area and create a dimensional model on top for Qlik
- If you must load raw vault for advanced use cases:
  - Load hub tables with business keys (create associations to fact tables via business keys, not hash keys)
  - Load relevant satellites (filter to `load_end_date IS NULL` for current attributes)
  - Handle link tables as bridge tables (many-to-many relationships) if modeling them explicitly
  - Use `load_date` for temporal analysis (when did this attribute become current?)
- **Best practice:** Create an intermediate staging area that denormalizes the vault into a dimensional model before loading Qlik

### 2.4 Flat Files / CSV

**Identification Criteria:**
- Source data is files (CSV, delimited text, fixed-width, JSON Lines)
- Files have header rows with column names
- One file = one table (though a single logical table may be split across multiple files, especially date-partitioned files like `orders_2024_01.csv`, `orders_2024_02.csv`)
- No inherent key structure; keys are defined by column content, not metadata
- Files are often stored in a data lake or cloud storage (S3, Azure Blob, etc.)
- File naming conventions may include dates or batch numbers: `customer_202601.csv`, `orders_batch_001.csv`

**Example Schema:**
```
files/
  customer.csv (columns: customer_id, name, email, region)
  product.csv (columns: product_id, sku, category, price)
  orders_2024_01.csv (columns: order_id, customer_id, product_id, order_date, quantity, amount)
  orders_2024_02.csv (columns: order_id, customer_id, product_id, order_date, quantity, amount)
  orders_2024_03.csv (columns: order_id, customer_id, product_id, order_date, quantity, amount)
```

**Key Characteristics:**
- **Schema is implicit:** No database metadata; column names and types are inferred from header rows and sample data
- **Append-only:** Typically new files are added; existing files are not modified
- **Date-partitioned:** Large datasets are often split by date (`orders_YYYY_MM.csv`) to enable incremental processing
- **No constraints:** No primary key or foreign key constraints enforced; must be enforced at load time
- **Type inference:** Data types are not explicitly stored; must be inferred from content

**Consumption Strategy for Qlik:**
- Each file → one Qlik table
- Establish keys explicitly in Qlik (not in source)
- Handle date-partitioned files as separate loads and concatenate: `LOAD * FROM orders_2024_01.csv (txt, codepage is 1252, embedded labels, delimiter is ',')` then `CONCATENATE LOAD * FROM orders_2024_02.csv (...)`
- Implement incremental loads by processing only new/changed files
- Handle missing or null values explicitly (are empty fields nulls or empty strings?)

### 2.5 API Sources

**Identification Criteria:**
- Data accessed via REST API, GraphQL, webhooks, or third-party SaaS connectors
- Response format is typically JSON or XML
- No persistent schema; schema is defined by API documentation
- Request parameters control filtering, pagination, or date ranges
- Rate limits or pagination controls determine extraction strategy

**Example API Signature:**
```
GET /api/customers?page=1&limit=100
GET /api/orders?filter[created_after]=2024-01-01&include=items,customer
GET /api/products?search=category:electronics
```

**Key Characteristics:**
- **Dynamic schema:** Fields and structure may change between API versions; version management required
- **Pagination:** Must handle paginated responses (page number, cursor, limit)
- **No direct SQL:** Cannot run ad hoc queries; must use API endpoints as-is
- **Rate limits:** API may restrict request frequency; batch and cache API responses
- **Eventual consistency:** Real-time updates may be delayed

**Consumption Strategy for Qlik:**
- Use Qlik Cloud connectors or REST scripts to extract data
- Flatten nested JSON structures into tabular format
- Handle pagination in loop structures (iterate through pages)
- Implement caching of API responses to avoid rate-limit issues
- Full vs. incremental depends on API capabilities: Does API support date filtering or delta queries? Or must you always pull full result set?
- Timestamp fields (`updated_at`, `created_at`) often control incremental extraction

---

## Part 3: Per-Table Architectural Role Classification

Once you've identified the overall architecture type, classify each table within that architecture. This section describes each role and how Qlik should consume it.

### Dimension

**Also called:** Reference, lookup table

**Characteristics:**
- Relatively static data (low update frequency)
- Smaller cardinality (100s to 100Ks of rows)
- Descriptive attributes (name, category, status, region)
- Often has both surrogate key (for associations) and business key (for integration)
- May include SCD columns for versioning

**Key Structure:** Usually surrogate key or composite key

**Mutability:** Immutable (append-only) or SCD Type 1/2 (versioned)

**Incremental Load Pattern:** Full refresh (small tables reload quickly) or insert-only (if SCD Type 2)

**Consumption Implication:** Load all dimensions into memory. Use surrogate key for fast joins to facts. Filter SCD Type 2 versions by effective date when needed. Example: "Load all customer dimensions (100K rows). Use customer_id for join to orders. For current state, filter is_current=1."

### Fact

**Also called:** Transactional table, event table

**Characteristics:**
- Large row count (Ms to 100Ms of rows)
- Represents events or transactions (orders, clicks, payments)
- Grain explicitly defined (order line, daily sales per store, etc.)
- Contains foreign keys to dimensions
- Contains measures (additive metrics like amount, count; non-additive like price)
- Often has effective or transaction timestamps

**Key Structure:** Composite (multiple dimension keys + sequence number) or surrogate

**Mutability:** Immutable (append-only in data warehouse); if from OLTP, may be mutable

**Incremental Load Pattern:** Insert-by-timestamp (load records where transaction_date > last reload date) or full refresh (if small or source doesn't support filtering)

**Consumption Implication:** Load facts with timestamp-based filtering for efficiency (do not reload entire fact table every day). Join to dimensions on foreign keys. Be aware of grain (order vs. order line) to avoid double-counting. Example: "Load orders incrementally (insert-by-order_date > max previous load). Join on customer_id and product_id to dimensions. Grain is order line."

### Lookup / Reference

**Characteristics:**
- Static reference data (codes, categories, hierarchies)
- Small cardinality
- Used to decode or categorize other fields
- May be maintained manually or loaded from external reference

**Key Structure:** Natural key or business key

**Mutability:** Immutable or SCD Type 1

**Incremental Load Pattern:** Full refresh (small tables, infrequent changes)

**Consumption Implication:** Load once per reload. Use for ApplyMap or join to categorize or decode other fields. Example: "Load status codes (10 rows). Use for ApplyMap on order.status to add human-readable labels."

### Staging

**Characteristics:**
- Temporary tables used during ETL (marked with `_` prefix in Qlik convention)
- Not meant to be visible to end users
- Should be dropped after use
- Used to hold intermediate transformation results

**Key Structure:** Usually none (or temporary keys)

**Mutability:** Mutable (constantly re-created)

**Incremental Load Pattern:** Full refresh (recomputed from source on each reload)

**Consumption Implication:** Load staging table, perform transformations, drop. Example: "_TransformedOrders: Load raw orders, clean nulls, apply mappings, drop original raw table."

### Hub (Data Vault)

**Characteristics:**
- Contains core business entities and their business keys
- Immutable (insert-only)
- Contains hash key (deterministic hash of business key)
- Contains load_date and record_source

**Key Structure:** Hash key of business key(s)

**Mutability:** Immutable

**Incremental Load Pattern:** Insert-only (hash-based deduplication prevents duplicates)

**Consumption Implication:** Use hub business keys to associate to fact tables, not hash keys. Example: "Load hub_customer. Join fact_orders on customer_id (business key), not customer_hash_key."

### Link (Data Vault)

**Characteristics:**
- Many-to-many relationships between hubs
- Links two or more hub hash keys
- Immutable
- Contains load_date and record_source

**Key Structure:** Composite of hub hash keys

**Mutability:** Immutable

**Incremental Load Pattern:** Insert-only

**Consumption Implication:** Use link tables as bridge tables to join multiple dimensions. Example: "Link connects customer, product, order hubs. Use to model 'which customers bought which products when.' Create bridge table in Qlik model."

### Satellite (Data Vault)

**Characteristics:**
- Descriptive attributes linked to a hub or link
- May contain multiple satellite tables per hub (one per subject area)
- Immutable (versioned; load_date, load_end_date mark versions)
- Contains load_date and record_source

**Key Structure:** Hub/link hash key + load_date (composite)

**Mutability:** Immutable with versioning

**Incremental Load Pattern:** Insert-only (new versions inserted; old versions closed via load_end_date)

**Consumption Implication:** Filter to current version (load_end_date IS NULL) for current state. Include load_date for temporal analysis. Example: "Load sat_customer_profile. Filter load_end_date IS NULL for current attributes. Use load_date to analyze attribute change history."

### Bridge

**Characteristics:**
- Enables many-to-many relationships (e.g., products can have multiple categories; categories can have multiple products)
- Often derived from flattened or delimited source data
- Contains keys to two or more dimension tables
- Grain may be many-to-many or one-side-with-qualifier

**Key Structure:** Composite of related dimension keys

**Mutability:** Usually immutable or SCD Type 1

**Incremental Load Pattern:** Full refresh

**Consumption Implication:** Use bridge to create many-to-many associations without synthetic keys. Example: "ProductCategory bridge: product_id, category_id. Enables filtering by category and seeing all products in that category without synthetic keys."

### Snapshot

**Characteristics:**
- Represents a point-in-time capture of a dimension (e.g., "customer state on 2024-01-31")
- One record per entity per period (customer per month, account per day)
- Non-additive (cannot aggregate snapshots across periods; they overlap)

**Key Structure:** Entity key + period key (e.g., customer_id, date)

**Mutability:** Immutable

**Incremental Load Pattern:** Insert-only (new snapshots added)

**Consumption Implication:** Use for period-over-period analysis. Do NOT aggregate across periods. Example: "Customer balance snapshot (customer_id, month_end_date, balance). Analysis: balance on date X, change from Jan to Feb. NOT: sum of balances over the year."

### Aggregate

**Characteristics:**
- Pre-calculated summary table (e.g., daily sales per store)
- Grain is coarser than base facts (day, week, month vs. transaction)
- Contains aggregated measures

**Key Structure:** Aggregate key (e.g., store_id, date)

**Mutability:** Usually immutable

**Incremental Load Pattern:** Insert-only or full refresh at aggregate grain

**Consumption Implication:** Use for performance optimization when base facts are too large. Include both aggregate and detail in model for Qlik to choose. Example: "Load both fact_daily_sales (aggregate) and fact_transactions (detail). Qlik optimizes performance based on field selection."

---

## Part 4: Consumption Implications Matrix

Quick-reference table matching architecture type, table role, and recommended Qlik consumption strategy:

| Architecture | Role | Key Approach | Incremental Strategy | Common Pitfall | Qlik Mitigation |
|---|---|---|---|---|---|
| Dimensional Warehouse | Dimension (SCD 1) | Surrogate key | Full refresh | Overwriting historical versions | Keep SCD Type 1 dimensions small; accept data loss for non-critical attributes |
| Dimensional Warehouse | Dimension (SCD 2) | Surrogate key + date filter | Dual-timestamp (insert new version, close old) | Missing closed records | Load both open and closed versions; join facts by effective_from/effective_to |
| Dimensional Warehouse | Fact | Composite (dim keys) | Insert-by-transaction-date | Late-arriving facts | Include lookback window in date filter (e.g., last 7 days of previous month) |
| Dimensional Warehouse | Fact | Surrogate key | Insert-by-dw_load_date | Confusing business key with surrogate | Always join facts to dimensions on surrogate, not business key |
| Normalized OLTP | Transaction | Natural (order_id, item_seq) | Insert/Update-by-timestamp | Many-to-many synthetic keys | Denormalize to star schema in ETL; do not load raw 3NF into Qlik |
| Normalized OLTP | Operational | Natural (customer_id) | Full refresh | Mutable status fields | Capture status history via SCD Type 2 in ETL layer |
| Data Vault 2.0 | Hub | Business key + hash | Insert-only (hash dedup) | Hash key collisions (theoretical, very rare) | Use business key for joins, not hash key. Hash key is internal |
| Data Vault 2.0 | Link | Composite of hub hashes | Insert-only | Incorrect interpretation of many-to-many | Create bridge table in Qlik model; use business keys, not hash keys |
| Data Vault 2.0 | Satellite | Hub hash + load_date | Insert-only (versioning) | Including closed versions in aggregates | Filter load_end_date IS NULL for current state. Include load_date for temporal join logic |
| Flat Files | Csv (Dimension) | Natural or surrogate | Full file refresh | Missing files in date-partition sequence | Check file naming; implement fallback for missing dates |
| Flat Files | Csv (Fact) | Composite | File-level detection (new files only) | Double-loading if files are re-delivered | Implement idempotent loading (hash check or deduplication by business key) |
| API | API endpoint | Natural key | Full pull or API delta | Rate limits on large extracts | Implement caching layer; batch requests; use delta APIs if available |
| API | Paginated endpoint | Natural key | Insert-only (append to previous extract) | Missing pages or duplicate records | Store cursor/page state; implement duplicate detection by business key |

---

## Practical Examples

### Example 1: Retail Dimensional Warehouse

**Architecture Type:** Dimensional Warehouse

**Tables:**
1. **dim_customer** → Dimension (SCD Type 2) → Load all versions; filter by effective dates when joining facts
2. **dim_product** → Dimension (SCD Type 1) → Load current attributes; accept that price changes overwrite history
3. **dim_date** → Dimension (non-SCD) → Load all dates; use for calendar associations
4. **fact_sales** → Fact → Load via insert-by-transaction-date; join to dim_ tables on surrogate keys

**Qlik Model Design:**
- Associations: fact_sales.customer_id → dim_customer.customer_id, fact_sales.product_id → dim_product.product_id
- SCD 2 handling: Include effective_from, effective_to in dim_customer. When analyzing historical data, join fact_sales.transaction_date between effective_from and effective_to.

### Example 2: Normalized OLTP

**Architecture Type:** Normalized OLTP (do not load raw)

**Tables:** customer, orders, order_items, products, shipments

**ETL Strategy (not shown in Qlik, but necessary in source):**
- Extract: Pull normalized tables as-is
- Transform: Denormalize into dimensional star (Customer dimension, Product dimension, Order fact with line grain)
- Load into Qlik: The transformed dimensional model, not raw 3NF

**Why:** Raw 3NF in Qlik produces many joins, synthetic keys, and slow queries. Denormalize in ETL (cheap); query fast in Qlik (expensive).

### Example 3: Data Vault 2.0

**Architecture Type:** Data Vault 2.0

**Tables:** hub_customer, link_customer_order, sat_customer_profile, sat_order_context

**Qlik Model (Simplified Approach):**
- Create intermediate dimensional model from vault (denormalize satellites, flatten links)
- Load that dimensional model into Qlik, not raw vault
- OR load hubs + filtered satellites, flatten in Qlik (more memory-intensive)

**Key Point:** Data Vault is a staging layer optimized for operational analytics and auditability, not OLAP query speed. Transform vault to dimensional for Qlik.

### Example 4: API Source (Salesforce)

**Architecture Type:** API

**Data:** Contacts (customers), Accounts (company accounts), Opportunities (deals)

**Qlik Load Strategy:**
- Extract contacts via REST → Qlik table (Contact dimension)
- Extract accounts via REST → Qlik table (Account dimension)
- Extract opportunities via REST → Qlik table (Opportunity fact)
- Join Opportunity.AccountId to Account.Id, Opportunity.ContactId to Contact.Id
- Implement caching: Store API responses to QVD between reloads to avoid rate limits

**Incremental Strategy:**
- Check if Salesforce API supports LastModifiedDate filtering; if so, load only records modified since last reload
- If not, implement full refresh with deduplication by Id

---

## Decision Checklist for Your Source

When profiling your source, answer these questions to guide classification:

- [ ] What is the overall architecture type (dimensional, normalized, vault, flat files, API)?
- [ ] For each table: Is it a dimension, fact, lookup, or staging table?
- [ ] For each table: Does it have a surrogate key, natural key, composite key, or no key?
- [ ] For each table: Is it immutable (append-only), mutable (update-in-place), or versioned (SCD Type 2)?
- [ ] For each dimension: If SCD Type 2, which columns mark the effective period (effective_from/effective_to, load_date/load_end_date, version_number)?
- [ ] For each fact: What is the grain (order, order line, daily aggregation)?
- [ ] For each table: Can it support insert-by-timestamp incremental loads, or must it be full-refreshed?
- [ ] Are there many-to-many relationships? Which bridge/link tables represent them?
- [ ] Which tables contain foreign keys? Are they valid (all referenced records exist)?
- [ ] Which tables are candidates for date-partitioned or file-partitioned loading (flat files)?
- [ ] Are there string-encoded nulls, mixed data types, or other data quality issues that affect incremental detection?

