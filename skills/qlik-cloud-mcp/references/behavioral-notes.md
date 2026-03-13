# Qlik Cloud MCP — Per-Tool Behavioral Notes

These notes document behaviors discovered through live testing against Qlik Cloud that go beyond what the MCP tool definitions provide. Organized by tool category. Only read the sections relevant to your current task.

## Table of Contents

1. [App Inspection Tools](#1-app-inspection-tools)
2. [Data Analytics Tools](#2-data-analytics-tools)
3. [Visualization Creation Tools](#3-visualization-creation-tools)
4. [Dataset and Catalog Tools](#4-dataset-and-catalog-tools)
5. [Lineage Tools](#5-lineage-tools)
6. [Governance Tools](#6-governance-tools)

---

## 1. App Inspection Tools

### describe_app
- Safe, read-only metadata call. No significant gotchas.
- Less field detail than `get_fields`. Use `describe_app` for a quick overview, `get_fields` for type-level profiling.

### get_fields
- The `tags` array is the richest metadata source. Key tags to watch for:
  - `$key` — Qlik identified this field as a key (used in associations).
  - `$keypart` — Part of a composite key.
  - `$numeric`, `$text`, `$date`, `$timestamp` — Dual representation indicators.
  - `$ascii` — Text encoding indicator.
- **Does NOT return table membership.** You cannot tell which table a field belongs to from this response alone. That information comes from the load script or data model specification.
- Field names are case-sensitive throughout Qlik. `[Sales.Amount]` and `[sales.amount]` are different fields.

### get_field_values
- `limit` maximum is effectively 99. Requesting 100 may return an error on some tenants.
- Values are returned in Qlik's internal sort order, not alphabetical.
- **Affected by active selections.** If you need the full unfiltered value set, call `clear_selections` first.
- Does not return null counts. Use `create_data_object` with `NullCount()` for null analysis.
- Returns dual representation (text + numeric) for each value.

### search_field_values
- Case-insensitive. "florida" matches "Florida", "FLORIDA".
- Supports partial matching. "boat" finds "Motorboat", "Sailboat".
- Cross-field search (omitting `fieldName`) searches ALL fields. Powerful for discovery but slow on large apps.
- Numeric search works on the text representation. "2024" matches the text "2024", not the number.

### list_sheets
- **The `cells` array in the response is truncated.** Never rely on it for a complete object inventory. Always follow up with `get_sheet_details` per sheet.

### get_sheet_details
- Returns object configurations but NOT visual layout coordinates (grid row/column positions).
- Reliable for extracting chart types, dimension/measure assignments, and object IDs.

### list_dimensions / list_measures
- Returns all master (library) items with their definitions, expressions, and IDs.
- The `libraryId` from these responses is what you pass to `add_chart` when referencing master items.

---

## 2. Data Analytics Tools

### create_data_object
- **Session-scoped (ephemeral).** Objects exist only for the current session and are automatically cleaned up. No manual deletion needed.
- **Silent field name failures.** Referencing `[NonExistent.Field]` returns null/0, not an error. This is the most dangerous gotcha. Always verify field names with `get_fields` before building expressions.
- **Silent value failures in set analysis.** `Sum({<State={'XX'}>} [Amount])` returns 0 when 'XX' doesn't exist, not an error.
- **Label is mandatory for inline expressions.** Omitting `label` when using `expression` causes an error.
- **Label is ignored for library measures.** When using `libraryId`, the library item's label is used regardless of any `label` you provide.
- **Respects active selections.** Use set analysis for one-off filtering instead of `select_values` when you don't want to affect session state.
- **Data returned in first page only for large results.** Use `get_chart_data` with the returned object ID to paginate through larger result sets.
- **10,000 cell limit per request.** Cells = dimensions × measures × rows. Apply sort + limit to constrain high-cardinality dimensions.

### get_chart_data
- Works on both permanent chart objects (on sheets) and session objects (from `create_data_object`).
- The `chartId` for session objects is returned in the `create_data_object` response.
- Data reflects current selection state at time of call.
- Same 10,000 cell limit applies.

### get_chart_info
- Metadata only, no data retrieval. Returns chart type, title, dimensions, measures, total row count.
- Useful for inspecting reference app charts without loading their data.

### select_values
- **Cumulative and persistent.** Each call adds to existing selections. To replace, clear first.
- **Silent failure for non-existent values.** The returned selection list is the ground truth. If the field doesn't appear in it, the selection failed silently.
- **`match` overrides `values`.** If both are provided, only `match` is used.
- **Cannot clear app-level defaults.** Script-embedded selections, Section Access reductions, and default bookmark selections persist even after `clear_selections`.
- Prefer set analysis over selections for single analytical queries to avoid state management overhead.

### clear_selections
- Clears user-applied selections only. App-level defaults persist.
- Returns the actual selection state after clearing (the truth).
- Accepts optional `fieldName` to clear only one field's selections.

### get_current_selections
- Call before any data retrieval to check for unexpected active selections.
- Call after `select_values` to verify selections were applied correctly.

---

## 3. Visualization Creation Tools

### create_sheet
- Title must be 3-127 characters.
- Creates an empty sheet. Use `add_chart` and `add_filter` to populate it.
- No control over sheet ordering within the app.

### add_chart
- **No positioning control.** Charts are appended sequentially. No way to specify grid row/column.
- **No formatting control.** Colors, number formats, conditional formatting, fonts are not configurable.
- **Expression validation is deferred.** Invalid expressions succeed at chart creation but fail at render time (showing an error in the chart object). Always validate expressions with `create_data_object` first.
- **`label` is mandatory for inline fields/expressions.** Always include `label` when using `field` or `expression` directly (not `libraryId`).
- **Scatterplot requirements:** Despite documentation suggesting 2 dimensions + 1 measure, scatterplots actually work best with 1 dimension + 2-3 measures (X-axis, Y-axis, optional bubble size). Test your specific configuration.

### add_filter
- No control over filter display mode (list, search, dropdown). The Qlik Sense client determines this based on field cardinality.
- No control over positioning within the sheet.

### create_dimension / create_measure
- Name must be 3-127 characters for both.
- Once created, items are available to all sheets in the app.
- **Expression validation does not happen at creation time** for measures. Invalid expressions silently succeed here.
- **Published app restriction:** Master items can only be created/edited on private sheets. In published apps, changes must be made in the source app and re-published. MCP tools don't enforce this.
- **Rename/delete propagation:** If a master measure is renamed or deleted, expressions referencing it by name return NULL rather than raising an error. References are not auto-updated.

---

## 4. Dataset and Catalog Tools

### search
- `spaceId` must be a 24-character hex string, NOT the space name. Resolve space names with `search_spaces` first.
- Use `resourceType` filter (e.g., "app,dataset") to narrow results.
- Paginated via `next` token.

### get_dataset
- Returns the QRI (Qlik Resource Identifier) needed for `get_lineage`.
- Dataset types include QVD, CSV, and other Qlik-native formats.

### get_dataset_schema
- Data types are Qlik-native: STRING, DOUBLE, INTEGER, TIMESTAMP, DATE. These are not source database types.
- `primaryKey` flag may or may not be populated depending on how the dataset was registered.

### get_dataset_sample
- Fixed at 10 rows. No way to request more.

### get_dataset_profile
- Profile data may be stale or absent if the dataset hasn't been profiled recently.
- Check the profile timestamp. Use `update_dataset_quality` to trigger a fresh computation if needed.
- Not all datasets have profiles computed.

### get_dataset_freshness
- Returns last updated timestamp. No gotchas.

### get_dataset_trust_score
- **Returns an error when no trust score exists** (not null, not zero — an actual error). Most datasets won't have trust scores unless explicitly assessed. Handle this gracefully: log "trust score not available" and continue.

### get_dataset_memberships
- Returns which data products include this dataset. Paginated.

---

## 5. Lineage Tools

### get_lineage
- **One level deep per call.** Returns only immediate upstream dependencies.
- **Recursive calls required for full lineage.** For a pipeline like Source → Extract App → QVD → Transform App → Final App, you need 3+ calls.
- **QRI format must be exact:**
  - Apps: `qri:app:sense://[appId]`
  - Datasets: Get the QRI from `get_dataset` response (format varies).
- Not all resources have lineage metadata. Some apps or datasets may return empty results.

---

## 6. Governance Tools

### Glossary tools
- `update_term_status` accepts exactly `draft`, `verified`, or `deprecated` (case-sensitive).
- Only stewards can verify terms. Once verified, only stewards can modify the term.
- `get_full_glossary_export` is expensive — retrieves the entire glossary including all terms, categories, and links. Use `search_glossary_terms` for targeted queries instead.
- `create_glossary_term_links` supports both single and batch modes. When linking to subresources (field, master_dimension, master_measure), all three subresource fields (subResourceId, subResourceName, subResourceType) must be provided together.

### Data Product tools
- `update_data_product` uses patch operations for datasets, tags, and key contacts (op: add/remove/replace).
- `update_activate_data_product` requires name and spaceId. Activating makes the data product visible and consumable.
- `delete_data_product` is permanent and irreversible.

### Dataset metadata tools
- `update_dataset_quality` triggers an async computation. Returns a computation ID. Poll status with `get_dataset_quality_computation_status`.
- `update_dataset_metadata` uses patch operations for tags (op: add/remove/replace).
