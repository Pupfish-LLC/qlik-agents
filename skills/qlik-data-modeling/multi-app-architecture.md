# Multi-App Architecture Patterns for Qlik

Decision frameworks and patterns for choosing between single-app, QVD generator/consumer, extract/transform/model/UI split, and binary load architectures.

---

## Single App Pattern

All extraction, transformation, and modeling in one Qlik app. The simplest architecture.

### When to Use

- **Data volume:** < 1 GB in memory
- **Model complexity:** ≤ 10 tables
- **Team size:** 1-2 developers
- **Consumers:** 1-2 apps (or dashboards within the same app)
- **Refresh requirements:** All tables on same cadence

### Architecture

```
Source Systems
       |
       v
[Single App: Extract + Transform + Model + UI]
       |
       v
    Users
```

The app script handles all layers: raw extraction, business rule application, star schema assembly, and dashboard layout.

### Pros

- **Simplicity:** One script, one deployment, one reload cycle.
- **No orchestration:** No coordination needed between apps.
- **Straightforward debugging:** All logic in one place.

### Cons

- **Limited scaling:** Scaling is limited by single reload cycle time and available memory.
- **No multi-consumer isolation:** Changes to the model affect all consumers simultaneously.
- **Hard to share models:** Difficult to provide the same data model to multiple dashboards with different refresh requirements.
- **Operational risk:** A single app failure affects all consumers.

### When to Upgrade

When any of these constraints are hit:
- Reload cycle time exceeds SLA (daily full-refresh takes too long).
- Data volume approaches memory limits.
- Multiple teams need different refresh schedules or models from the same source.
- Multiple consumer apps need the same model (data duplication becomes unmaintainable).

---

## QVD Generator / Consumer Pattern

The most common multi-app pattern in production Qlik deployments.

### Architecture

```
Source Systems
       |
       v
[Generator App: Extract + Transform, stores QVDs]
       |
       +-------[Consumer App 1: Model + UI]
       +-------[Consumer App 2: Model + UI]
       +-------[Consumer App 3: Model + UI]
```

**Generator app:**
- Loads from all source systems
- Applies business rules and data quality cleaning
- Stores Transform QVDs (one per transformed entity)
- Runs daily (or per source refresh schedule)

**Consumer apps:**
- Load from Transform QVDs
- Build distinct star schemas (may differ per consumer)
- Build dashboards and master items
- May run on different schedules (e.g., 3x daily, while generator runs 1x daily)

### When to Use

- **Data volume:** 1-10 GB
- **Model complexity:** 10-30 tables
- **Team size:** 1-3 teams (clear ownership: one team owns generator, others own consumers)
- **Consumers:** 2-5 apps from the same source data
- **Refresh requirements:** Generator on fixed schedule; consumers may vary

### Pros

- **Source isolation:** Only the generator app needs connections to source systems. Consumer apps don't.
- **Multi-consumer support:** Multiple dashboards share the same Transform QVDs, reducing duplication.
- **Independent refresh:** Generator and consumers have independent reload schedules and failure modes.
- **Clear responsibilities:** Generator team owns data extraction; consumer teams own business logic and UI.
- **Team scaling:** Easy to add new consumer teams without involving the generator team (as long as the data they need is already in QVDs).

### Cons

- **QVD storage:** Must maintain and monitor QVD files (size, retention, backup).
- **Reload orchestration:** Must chain generator reload before consumer reloads. Cascading failures possible.
- **Redundant tables:** Consumer apps may load the same Transform QVD and then drop unneeded fields, creating redundancy.

### Reload Dependency Chain

```
09:00 PM -- Generator app reloads all sources -> stores Transform QVDs
09:15 PM -- Consumer 1 triggered (depends on Generator success)
09:20 PM -- Consumer 2 triggered (depends on Generator success)
09:25 PM -- Consumer 3 triggered (depends on Generator success)
```

**Critical:** Consumer reloads should NOT start until the generator finishes. If the generator fails, manually trigger consumers once issues are resolved, or they'll use stale QVDs from the previous reload.

### Reload Orchestration in Cloud vs. Client-Managed

**Qlik Cloud:**
- Use Qlik Cloud task chaining: specify an app as a prerequisite, automatic chaining.
- Notifications: trigger downstream tasks on success/failure.

**Client-Managed (Qlik Sense):**
- Use external task scheduler (Windows Task Scheduler, cron, custom orchestration tool).
- Script can call `qsreload.exe` or REST API to trigger downstream apps.
- Consider tools like Qlik Talend Cloud (formerly Talend) or Informatica for enterprise orchestration.

### Decision: 2-Layer vs. 3-Layer QVDs

**2-Layer (Extract + Model):**
```
Generator App:
  Raw Extract (source names preserved) -> Extract_*.qvd
  Transformations, joins -> Model_*.qvd
Consumer App:
  Load Model_*.qvd
```

**3-Layer (Raw + Transform + Model):**
```
Generator App:
  Raw Extract -> Raw_*.qvd
  Transformations, joins -> Transform_*.qvd
  Star schema assembly -> Model_*.qvd
Consumer App:
  Load Model_*.qvd
```

**Choose 3-layer when:**
- Generator app source list is long and complex (easier to debug if Raw QVDs preserve source structure).
- Incremental extract pattern is sophisticated (audit trail of raw data useful for troubleshooting).
- Multiple downstream teams may want to extract different subsets or combinations of Transform QVDs.

**Choose 2-layer when:**
- Transformations are straightforward (little value in preserving raw layer).
- Generator app is simple (one-to-one mapping of sources to QVDs).
- Storage is constrained.

---

## Extract / Transform / Model / UI Split (4-App Pattern)

For very large, complex projects with clear separation of concerns and multiple development teams.

### Architecture

```
Source Systems
       |
       v
[Extract App: Load sources, store Raw QVDs]
       |
       v
[Transform App: Clean data, business rules, store Transform QVDs]
       |
       v
[Model App: Star schema assembly, store Model QVDs]
       |
       v
[UI App 1: Load Model_*.qvd, build dashboards]
       |
[UI App 2: Load Model_*.qvd, build dashboards]
```

### When to Use

- **Data volume:** > 10 GB
- **Model complexity:** 30+ tables, many business rules, complex transformations
- **Team size:** 3+ development teams (Extract team, Transform team, Model team, UI team)
- **Refresh requirements:** Each layer can refresh independently if needed
- **Governance:** Clear separation of concerns (data engineering, analytics engineering, BI)

### Pros

- **Parallel development:** Teams work independently on their layer.
- **Reusability:** Transform team outputs serve multiple Model teams; Model team outputs serve multiple UI teams.
- **Debuggability:** Each layer produces a QVD, making it easy to isolate failures.
- **Scaling:** Very large data volumes can be processed in batches by Extract/Transform layers.
- **Governance:** Clear audit trail of transformations applied at each layer.

### Cons

- **Operational complexity:** 4 separate reload cycles to orchestrate and monitor.
- **Storage overhead:** Three sets of QVDs (Raw, Transform, Model), potentially large.
- **Development overhead:** Setting up layer contracts (what fields does Transform expect from Extract? What does Model expect from Transform?).

### Reload Dependency Chain

```
Extract App (Extract team)
    |-> (success) Trigger Transform App
         |-> (success) Trigger Model App
              |-> (success) Trigger UI App 1
              |-> (success) Trigger UI App 2
```

Each layer runs sequentially. If Extract fails, Transform is not triggered. If Transform fails, Model is not triggered.

### Layer Contracts

Each layer should have documented "contracts" specifying:
- What tables/fields it produces
- What tables/fields it expects from upstream
- What transformations it applies

Example Extract layer contract:
```
Produces:
  Raw_Customer.qvd (fields: customer_id, name, region, join_date)
  Raw_Product.qvd (fields: product_id, name, category, price)
  Raw_Order.qvd (fields: order_id, customer_id, product_id, qty, amount, order_date)
```

Example Transform layer contract:
```
Consumes:
  Raw_Customer.qvd, Raw_Product.qvd, Raw_Order.qvd (per Extract contract)
Produces:
  Transform_Customer.qvd (fields: customer_id, [Customer.Name], [Customer.Region], [Customer.JoinDate])
  Transform_Product.qvd (fields: product_id, [Product.Name], [Product.Category], [Product.Price])
  Transform_Order.qvd (fields: order_id, customer_id, product_id, [Order.Quantity], [Order.Amount], [Order.Date])
Transformations applied:
  - Field rename to entity-prefix notation
  - Null cleaning via vCleanNull
  - Data quality validation
```

---

## Binary Load Pattern

Loads the entire in-memory model from another app: `binary [app_id_or_path];`.

### Pattern

```qlik
// In Consumer App script (MUST be first statement, before SET):
binary [Generator App ID or path];

// Optional: Load additional tables or override data
// LOAD ... FROM ... (qvd);
```

**Critical:** `binary` must be the FIRST statement in the script, before any other LOAD or SET statement.

### How It Works

- Loads all tables from the generator app's in-memory model into the consumer app.
- Does NOT load sheets, dashboards, or master items (data only).
- Only ONE binary statement per script.
- After binary load, the consumer app can load additional tables or override existing ones.

### When to Use

- **Use case:** Consumer app is dashboard-only and uses the exact same model as the generator.
- **Data volume:** Model fits in memory (typically < 1 GB per app).
- **Consumers:** 2-3 apps that don't need to customize the model.

### Pros

- **Eliminates QVD storage:** No need for intermediate QVD files.
- **Simple script:** Consumer script is minimal.
- **Exact model sharing:** Consumer gets the exact in-memory model from the generator.

### Cons

- **All-or-nothing:** Cannot filter which tables/fields to load. Must load the entire model.
- **No incremental pattern:** Must reload the entire model; no incremental updates.
- **Cascading reload:** Generator reload automatically cascades to consumers that use binary load. If the generator fails, consumers cannot reload until generator is fixed.
- **Single model:** Consumers cannot customize or extend the model.

### Anti-Pattern: Mixing Binary Load with QVD Load

```qlik
// WRONG -- consumers should use binary OR QVD, not both
binary [Generator App];
LOAD * FROM [Transform_Product.qvd] (qvd);  // Redundant; already in binary load
```

Choose one strategy: either binary load for simplicity, or QVD load for flexibility.

---

## Decision Framework: Choosing the Right Pattern

Use this table to select the best architecture for your project.

| Criterion | Single App | Gen/Con | Extract/Tx/Md/UI | Binary |
|-----------|-----------|---------|-----------------|--------|
| **Data volume** | < 1 GB | 1-10 GB | > 10 GB | < 1 GB per app |
| **Model complexity** | ≤ 10 tables | 10-30 | 30+ | < 10 (shared) |
| **Teams** | 1-2 | 1-3 | 3+ | 1 (shared model) |
| **Consumers** | 1-2 | 2-5 | 5+ | 2-3 dashboards |
| **Refresh schedule flexibility** | Low (all same) | High | High | None (cascading) |
| **Model customization per consumer** | N/A | Yes | Yes | No |
| **Incremental pattern** | Insert-only, SCD | Insert-only, SCD | Insert-only, SCD | Full reload |
| **Storage overhead** | Low | Medium (QVDs) | High (3 layer QVDs) | Very low |
| **Operational complexity** | Low | Medium | High | Low |
| **Development complexity** | Low | Medium | High | Low |

### Quick Decision Guide

1. **Start with Single App** if data/model is small and team is small.
2. **Upgrade to Generator/Consumer** when:
   - Multiple consumer apps need the same data, or
   - Reload cycle time becomes tight, or
   - Teams need independent refresh schedules.
3. **Use Extract/Transform/Model/UI** when:
   - Data volume exceeds 10 GB, or
   - Multiple teams working independently, or
   - Complex ETL and analytics engineering workflows.
4. **Use Binary Load** ONLY if:
   - Consumer apps are truly dashboard-only with no model customization, AND
   - Model is small enough to fit in memory, AND
   - Cascading reloads are acceptable.

---

## Reload Failure Handling

Multi-app architectures must handle cascading failures gracefully.

### Failure Scenarios

**Generator fails:**
- Consumer apps continue to use stale QVDs from previous reload.
- Data is out-of-date but available.
- Manually re-trigger consumers once generator is fixed.

**Consumer fails:**
- Generator is unaffected; other consumers use fresh QVDs.
- Affected consumer unavailable to users.
- Re-trigger or wait for next scheduled reload.

**Network failure between Generator and Consumer:**
- QVDs may be partially written or inaccessible.
- Implement file locks or atomic writes (write to temp location, then rename/move).

### Best Practices

1. **Monitor reload times:** Alert if any app takes significantly longer than baseline.
2. **Log success/failure:** Each app should log reload success/failure to a centralized location.
3. **Implement backoff:** If a reload fails, do not immediately retry. Wait 5-10 minutes, then retry (avoids hammering failed sources).
4. **Graceful degradation:** Consumer apps should handle missing QVDs gracefully (load from cache, display warning to users).
5. **Chain validation:** After generator finishes, validate QVD structure/row counts before triggering consumers.

### Validation Patterns

In the Generator app, after storing QVDs:

```qlik
// Validate row counts match expectations
LET vExpectedOrders = 1000000;
LET vActualOrders = NoOfRows('Orders');
IF $(vActualOrders) < $(vExpectedOrders) * 0.95 THEN
    TRACE WARNING: Order count suspiciously low ($(vActualOrders) vs. expected $(vExpectedOrders));
END IF
```

In the Consumer app, before starting dashboards:

```qlik
// Check if QVDs are stale
IF IsNull(FileTime('lib://QVDs/Transform_Product.qvd')) THEN
    TRACE ERROR: QVDs not found -- generator may have failed;
    ErrorMode = 1;  // Stop the reload
END IF
```

---

## QVD Storage and Retention

### Naming Convention

See `qlik-naming-conventions` for full file naming. Summary:
```
Raw_Orders.qvd                  // Current
Transform_Product.qvd           // Current
Model_Orders.qvd                // Current
Raw_Orders_20260301.qvd         // Archive (incremental pattern)
```

### Storage Location

- **Cloud (Qlik Cloud):** Use app data folder: `DATA/[app-name]/`
- **Client-managed (Qlik Sense):** Use shared QVD folder accessible to all apps: `\\shared-drive\qlik\qvds\` or `/opt/qlik/qvds/`

**Avoid:** Storing QVDs inside individual app folders on multi-app architectures (breaks shared access).

### Retention Strategy

- **Current QVDs:** Always keep. Used by consumers.
- **Archived QVDs (timestamped):** Keep for incremental loads. Retention policy depends on reload pattern (e.g., keep last 30 days for daily incremental).
- **Failed QVDs:** Clean up QVDs from failed reloads (to avoid consumers loading partial/corrupted data).

Example cleanup:

```qlik
// Delete QVDs older than 30 days
LET vCutoffDate = Num(Today() - 30);
FOR each vFile IN 'lib://QVDs/Raw_Orders_*.qvd'
    LET vFileDate = Num(SubField(vFile, '_', IterNo() + 1) - 4);  // Extract YYYYMMDD
    IF vFileDate < $(vCutoffDate) THEN
        // Delete vFile (Qlik script doesn't have native DELETE; use external cleanup)
    END IF
NEXT vFile
```

In production, use external cleanup: a scheduled task that removes old QVDs based on filename pattern.

---

## Summary

| Architecture | Best For | Reload Complexity | Team Structure |
|--------------|----------|-------------------|-----------------|
| **Single App** | Small data, simple models, 1-2 dashboards | 1 reload | 1-2 developers |
| **Generator/Consumer** | Medium data, multiple consumers, 2-5 dashboards | 2-5 reloads (chained) | 2-3 teams |
| **Extract/Transform/Model/UI** | Large data, 30+ tables, 5+ dashboards, distributed teams | 4+ reloads (sequential) | 3+ teams |
| **Binary Load** | Dashboard-only consumers, no model customization, exact model sharing | 1 reload per consumer (cascading) | 1 shared model, N dashboards |
