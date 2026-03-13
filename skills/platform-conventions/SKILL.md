---
name: platform-conventions
description: Captures existing platform patterns for brownfield Qlik projects. Provides structured templates for documenting existing app inventory, shared subroutine catalogs, naming convention maps, data connection standards, QVD storage conventions, and organizational coding standards. Used by requirements-analyst during Phase 0 context ingestion and by script-developer during Phase 4 for platform compatibility. Load when ingesting platform context or writing scripts that must integrate with existing platform conventions.
---

## Platform Context Ingestion for Brownfield Projects

Most real Qlik environments inherit existing conventions, subroutine libraries, naming standards, data connections, and deployment models. Ignoring this context produces scripts that don't integrate with the platform, violate local coding standards, or fail to call shared subroutines that solve the exact problem you're trying to solve. This skill provides the workflow and templates for capturing that context before development begins.

The **Platform Context Document** is Phase 0's output: a machine-readable, human-reviewable summary of existing platform patterns that downstream agents (requirements-analyst, data-architect, script-developer) use to align their work with the organization's existing architecture.

## Phase 0 Ingestion Workflow

The requirements-analyst executes these steps during Phase 0 to compile the Platform Context Document:

### Step 1: Check inputs/ for User-Provided Materials

Examine the following directories for user-provided platform context:

- **`inputs/existing-apps/`** — Exported .qvs scripts from reference applications (shows subroutine definitions, naming patterns, connection usage, QVD storage locations)
- **`inputs/platform-libraries/`** — Shared subroutine files or include files (defines reusable SUB blocks, common transformations, utility functions)
- **`inputs/upstream-architecture/`** — Source system documentation (schemas, table descriptions, architectural patterns already classified)

If any directory is empty, note it as "Not provided" in the Platform Context Document. The developer may need to provide this input manually.

### Step 2: Analyze Existing Scripts (Automated Extraction)

For each .qvs file in `inputs/existing-apps/`, extract the following patterns:

**Subroutine Definitions:**
- Search for `SUB` and `END SUB` blocks
- For each subroutine: record name, parameter list, purpose (infer from code context or comments), known limitations (e.g., "handles single primary key only"), usage patterns, and example calls
- Note any subroutines that manipulate fields or table structure (these affect naming downstream)

**Naming Convention Patterns:**
- Field names: Scan field definitions. Do they use entity-prefix dot notation (`Product.Category`), underscore separation (`product_category`), camelCase (`productCategory`)? Look for both dimension and fact table fields.
- Table names: Check for prefixes (`dim_`, `fact_`, `_temp`, `Map_`), suffixes, or other conventions
- Variable names: Scan for `SET` and `LET` statements. Do variables use `v` prefix? Other patterns?
- Expression patterns in master items (if stored in scripts): any naming conventions observed?

**Connection and Storage Conventions:**
- Every `LIB CONNECT` or connection reference: record connection name, path pattern (e.g., `lib://DataConnection/path/`), target system or folder
- Every `FROM ... (qvd)` statement: record QVD path and infer folder structure (layer-based? date-stamped? centralized?)
- Include file patterns: How are shared scripts referenced (`$(Include=...)`, direct file paths)?

**Architecture Patterns:**
- Is this a single app or multi-app architecture?
- If multi-app: trace QVD flows between apps (one app produces raw QVDs, another consumes and transforms)
- Incremental load patterns: Look for timestamp-based filtering, date-stamp file naming, or reload-previous logic
- Error handling patterns: TRACE statements, error message conventions, reload recovery logic

### Step 3: Identify Gaps Requiring Developer Input

Some platform context cannot be extracted from code alone. Communicate to the developer that the following require manual annotation:

- **Subroutine limitations not obvious from code.** Example: "Does MergeAndDrop handle composite keys?" Code may not test all cases.
- **Platform deployment model.** Is this Qlik Cloud, Client-Managed, or Hybrid? Development/Test/Production environments?
- **Security model.** Section Access approach? Identity provider (Okta, Azure AD, LDAP, static)?
- **QVD retention policies.** Are old date-stamped QVDs archived or deleted? Retention window?
- **Performance boundaries.** Known limits: maximum app size, maximum reload time, maximum concurrent users?
- **Connection string patterns.** How do connections vary between dev/test/prod environments?

### Step 4: Compile Platform Context Document

Use the template in `platform-context-template.md` to structure findings into six sections:

1. **Subroutine Inventory** — Each shared SUB with name, parameters, purpose, limitations, usage examples
2. **Naming Convention Map** — Platform naming patterns vs. framework defaults; developer decision on reconciliation
3. **Connection Catalog** — Each data connection with name, type, target, path pattern, environment variations
4. **Reference App Analysis** — Each reference app with architecture, patterns to adopt, patterns to avoid
5. **Upstream Architecture Classification** — Architecture type and per-table annotations (if Phase 2 source profiling has completed; otherwise "Pending")
6. **Platform Constraints Register** — Known limits, deployment model, security model, subroutine constraints

### Step 5: Present to Developer for Confirmation

The developer reviews the completed Platform Context Document and confirms:
- Subroutine inventory is complete and limitations are accurately captured
- Naming conventions reflect actual platform usage
- Connection catalog is complete and environment variations are correct
- Reference app patterns are representative
- No critical platform constraints are missing

Mark the document as **Confirmed** once approved.

## Extracting Patterns from Existing Scripts

This section provides detailed guidance on what to look for when reading .qvs files from `inputs/existing-apps/`.

### Subroutine Identification

Every `SUB ... END SUB` block is a candidate for reuse. Extract:

- **Name** — Exact subroutine name as defined
- **Parameters** — Comma-separated list of parameters in the SUB declaration, with any data type expectations
- **Purpose** — Inferred from code logic. If comments exist, use them; otherwise, describe what the subroutine does in one sentence
- **Known Limitations** — What this subroutine does NOT handle. Examples: "Only works with single primary keys, not composite"; "Assumes all fields are strings"; "Requires source_date timestamp field"
- **Usage Example** — A realistic call: `CALL MergeAndDrop('Product', 'product_key', 'Transform_Product', 'Model_Product');`

Example extracted entry (you'll see a completed one in the template):
```
Name: MergeAndDrop
Parameters: pTableName, pKeyField, pSourceTable, pTargetTable
Purpose: Merges source table into target table using key field, then drops source
Limitations: Single primary key only, assumes key uniqueness, no error recovery
Usage: CALL MergeAndDrop('Product', 'product_key', 'Transform_Product', 'Model_Product');
```

### Naming Convention Detection

Look for patterns, not just individual examples:

- **Field names:** Check 5-10 field names in both dimension and fact tables. Do they follow a consistent pattern? Entity-prefix dot notation? Underscores? camelCase?
- **Table names:** Do temp tables use `_` prefix? Do dimension tables have a `dim_` prefix? Fact tables `fact_`?
- **Variable names:** Search for SET or LET statements. Do all variables start with `v`? Other prefix patterns?
- **Expression names in master items:** If .qvs files define master items, what naming conventions are used (e.g., "Total Revenue", "Order Count")?

Record both the **observed platform convention** and the **framework default** (from `qlik-naming-conventions` skill). The data architect will reconcile in Phase 3.

### Connection and Storage Conventions

Every data connection is a candidate for reuse. Extract:

- **Connection name** (exactly as written in LIB CONNECT or folder connection)
- **Type** (ODBC, OLEDB, REST, Folder connection, QlikView connection)
- **Target** (database server, schema, folder path, or API endpoint)
- **Path pattern** (how QVDs or files are stored: `lib://DataConnection/path/layerPrefix_table.qvd`?)
- **QVD root location** (if QVDs are stored centrally: `/data/qvd/` or similar)
- **Environment variations** (e.g., "Dev points to `db-dev.company.com`, Prod points to `db-prod.company.com`")

### Architecture Patterns

Identify the data flow strategy:

- **Single-app:** All extraction, transformation, and modeling happens in one app
- **Multi-app:** Separate apps for Extract (produces raw QVDs) → Transform (consumes raw, produces transform QVDs) → Model (consumes transform QVDs, produces model tables)
- **Incremental load patterns:** Look for timestamp-based filtering, date-stamp file naming (e.g., `Raw_Orders_20260301.qvd`), or logic that loads "data since last reload"
- **Error handling:** Do scripts TRACE diagnostics? How are errors logged or signaled?

## Platform Context Document Sections

The Platform Context Document has six sections. See `platform-context-template.md` for the detailed template with sections, inline guidance, and completed examples.

### Section 1: Subroutine Inventory

Catalog all shared SUBs from `inputs/platform-libraries/` and `inputs/existing-apps/`. Format: table with columns Name, Parameters, Purpose, Known Limitations, Example Usage. Include a completed example row.

### Section 2: Naming Convention Map

Comparison table showing platform conventions vs. framework defaults for fields, tables, variables, and QVDs. Columns: Element, Platform Convention, Framework Default, Decision (which one will this project use?).

### Section 3: Connection Catalog

One row per data connection: Connection Name, Type, Target System, Path Pattern, QVD Root, Environment Variations. Examples include ODBC connections, folder connections, and REST endpoints.

### Section 4: Reference App Analysis

For each reference app: App Name, Architecture Type (single/multi-app, with QVD flows if multi-app), Patterns to Adopt (specific patterns you want to reuse), Patterns to Avoid (problematic patterns observed), Field Naming Used, Expression Patterns Used, Sheet Layout Patterns.

### Section 5: Upstream Architecture Classification

Overall architecture type (Dimensional Warehouse, Normalized OLTP, Data Vault 2.0, flat files, etc.) and per-table annotations (table name, architectural role, key structure, mutability, incremental pattern, consumption note). This section may be populated from Phase 2 source profiling. If source profiling hasn't occurred yet, mark as "Pending source profiling."

### Section 6: Platform Constraints Register

- **Deployment Model:** Cloud / Client-Managed / Hybrid
- **Security Model:** Section Access approach, identity provider
- **Performance Boundaries:** Known limits (max app size, max reload time, max concurrent users)
- **Subroutine Limitations:** Cross-reference to Subroutine Inventory (e.g., "MergeAndDrop does not handle composite keys")
- **Environment-Specific Constraints:** Dev connections differ from Prod; any other tier-specific limits?

## Greenfield Handling

For projects with no existing platform artifacts (no `inputs/existing-apps/`, no `inputs/platform-libraries/`), Phase 0 still runs. The Platform Context Document is produced but is minimal:

- **Subroutine Inventory:** "No existing platform subroutines provided. Will follow framework defaults from `qlik-load-script` skill."
- **Naming Convention Map:** All rows show "Framework default" in the Decision column. This is the decision record for naming conventions this project will use.
- **Connection Catalog:** "No existing connections provided. Connections will be defined per project requirements."
- **Reference App Analysis:** "No reference apps provided. Will follow framework defaults from `qlik-visualization` and `qlik-data-modeling` skills."
- **Upstream Architecture Classification:** "Pending source profiling (Phase 2)."
- **Platform Constraints Register:** "No known constraints. Will follow Qlik Sense platform defaults."

The minimal document serves as a **decision record**: it explicitly states that this project is using framework conventions, not existing platform conventions. This is correct and expected for greenfield projects.

## Convention Conflicts: When Platform Differs from Framework Defaults

Real brownfield projects often have naming conventions or subroutine patterns that differ from framework defaults. This is not a failure; it's a design decision point. The Platform Context Document captures both sides so the data architect can reconcile.

Example: The framework default for key fields uses `_key` suffix (`product_key`, `order_key`), but the existing platform uses `_id` (`product_id`, `order_id`). The Naming Convention Map will show:

| Element | Platform Convention | Framework Default | Decision |
|---------|-------------------|-------------------|----------|
| Key field suffixes | `_id` | `_key` | Platform (maintain consistency with existing subroutines) |

The data architect reviews this and decides: "We'll use `_id` to stay consistent with shared subroutine parameters." The script-developer then names all keys using `_id`.

When conflicts exist, **platform conventions usually win** if shared subroutines are deeply dependent on them. A subroutine that calls `CALL MergeAndDrop(pTableName, pKeyFieldName, ...)` and internally looks for fields ending in `_id` will fail if the project uses `_key` instead.

The Platform Context Document makes this dependency explicit so the architect can make an informed trade-off.

## Cross-Reference to Template and Supporting Skills

The complete Platform Context Document template is in `platform-context-template.md` in this skill directory. This template is the output artifact for Phase 0 and the input to all downstream agents.

The naming convention framework that the platform conventions are compared against is in the `qlik-naming-conventions` skill. If the platform uses different conventions, the reconciliation decision is made during Phase 3 (data architecture) by the data-architect agent.

For platform integration during Phase 4 (script development), the script-developer loads this skill alongside `qlik-load-script` to ensure new scripts follow platform conventions for subroutine calls, naming, and connection usage.
