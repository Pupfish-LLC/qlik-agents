# Reverse-Engineering Reference App Patterns

## Why Reverse-Engineer Existing Apps?

Existing Qlik apps—whether from Qlik's pre-built templates or your organization's reference apps—embody proven design patterns. Reverse-engineering extracts these patterns systematically, saving design time and improving consistency across projects. The pattern catalog becomes a reusable design library.

---

## Step 1: Examine Sheet Structure

**Objective:** Understand the sheet organization and user navigation flow.

**Procedure:**
1. Open the app in Qlik Sense web interface or download .qvf for inspection in Sheet Editor
2. List all sheet names in order
3. For each sheet, identify its purpose:
   - Executive summary (headline KPIs, one-page overview)
   - Detail analysis (drill-down, multiple perspectives on one dataset)
   - Operational monitoring (live metrics, refresh rates, alerts)
   - Data exploration (free-form filtering, discovery)
4. Note if sheets are organized by business role (Sales, Finance, Operations) or by analysis type (Summary, Detail, Diagnostics)
5. Identify "primary" sheet (appears first, likely most important)
6. Check if any sheets are hidden or marked as templates

**Document:**
```
Sheet Name | Purpose | Role/Audience | Priority
-----------|---------|---------------|---------
Executive Dashboard | Headline metrics | C-suite, finance leads | High
Regional Analysis | Sales drill-down by region | Regional managers | High
Product Detail | SKU-level margins and inventory | Procurement, sales | Medium
```

---

## Step 2: Analyze Object Types

**Objective:** Catalog what visualization types are used and where.

**Procedure:**
1. For each sheet, open in Sheet Editor
2. Identify all objects on the sheet: charts (bar, line, table, KPI, scatter, etc.), filters, images, text objects
3. Document object position in grid (top-left = priority)
4. Note object size (how much space does it consume relative to sheet?)
5. Identify any master items referenced (master measures, master visualizations)

**Document:**
```
Sheet | Position | Object Name | Type | Size (approx) | Master Item?
-------|----------|-------------|------|---------------|-------------
Executive Dashboard | Top-left | Revenue YTD | KPI | Small | Yes (vRevenue)
Executive Dashboard | Top-mid | Sales Trend | Line Chart | Medium | No
Executive Dashboard | Bottom | Regional Sales Table | Table | Large | No
```

---

## Step 3: Extract Dimension and Measure Assignments

**Objective:** For each chart, understand what data is plotted.

**Procedure:**
1. Click on each chart object, open Chart Properties (or Properties pane)
2. Record the dimension(s): What field is on X-axis, Y-axis, color, size, or legend?
3. Record the measure(s): What expression/aggregation is plotted? Examples: Sum([Sales.Amount]), Count(Distinct [Order.ID]), YoY Growth expression
4. Note sorting: Is chart sorted by measure descending, alphabetically, or by appearance order?
5. Check if conditional coloring is applied (color changes based on value or dimension)

**Document:**
```
Chart | Dimension(s) | Measure | Sorting | Conditional Color?
-------|--------------|---------|---------|-------------------
Regional Sales Bar | [Customer.Region] | Sum([Sales.Amount]) | Measure desc | Green if >target; Red if <target
Sales Trend Line | [Order.Date] (Monthly) | Sum([Sales.Amount]) | Date ascending | None
Top 10 Products Table | [Product.Name] | Sum([Quantity]), Avg([Margin%]) | Quantity desc | Red for negative margin
```

---

## Step 4: Catalog Filter Strategy

**Objective:** Understand global vs. sheet-specific filters and field selection criteria.

**Procedure:**
1. Identify all filter objects on the app (including global filter pane, if present)
2. For each filter field, record:
   - Is it global (appears on multiple sheets) or sheet-specific?
   - Mode: list (checkboxes), search, slider, calendar, button group?
   - Cardinality: how many unique values? (influences design choice)
   - Default selections or required selections?
3. Check if alternative states are used (separate filter contexts for comparisons)
4. Note "Current Selections" bar position and styling

**Document:**
```
Filter Field | Scope | Mode | Cardinality | Default Selection
--------------|-------|------|-------------|-------------------
Year | Global | Button Group | 2-3 years | Current year
Region | Global | List | 4 regions | All selected
Sales Rep | Sheet-Specific | Search | 150+ reps | None
Date Range | Sheet-Specific | Calendar Picker | Daily | Last 90 days
```

---

## Step 5: Document Color and Formatting

**Objective:** Catalog color assignments and formatting standards.

**Procedure:**
1. For each chart with color encoding, identify the color scheme:
   - Are dimension values always the same color (e.g., "North" = blue)?
   - Is a sequential scale used (light → dark)?
   - Are there conditional colors (red/green based on performance)?
2. Note brand colors used (company primary color, secondary colors)
3. For each numeric field, record formatting:
   - Currency: symbol, decimal places, thousands separator
   - Percentages: decimal places
   - Date: format pattern (YYYY-MM-DD, MMM YYYY, etc.)
4. Record font sizes for KPI titles, chart titles, axis labels
5. Check for alternating row colors in tables

**Document:**
```
Chart | Dimension | Color | Conditional? | Notes
-------|-----------|-------|--------------|-------
Regional Sales | Region | Blue, Orange, Green, Purple | No | Static assignment; matches brand palette
Revenue KPI | (N/A) | White text on blue background | Yes | Green if >target; Red if <target
Sales Table | Row 1, 2, 3, ... | Light gray, White, Light gray, White | No | Alternating rows for readability

Number Formatting | Pattern
-------------------|----------
Revenue | $#,##0.00 (e.g., $1,234,567.89)
Growth % | 0.0% (e.g., 12.5%)
Date | MMM YYYY (e.g., Jan 2024)
Quantity | # (e.g., 5000)
```

---

## Step 6: Map Information Hierarchy

**Objective:** Understand how objects are prioritized and organized on the sheet.

**Procedure:**
1. Draw or describe a simple layout diagram:
```
Top Row:
[KPI Revenue]  [KPI Growth%]  [KPI Customers]

Middle Row:
[Sales Trend Line Chart - Large]

Bottom Row:
[Regional Detail Table - Full Width]
```

2. Identify what's "above the fold" (visible without scrolling on desktop and mobile)
3. Note which objects are marked as "responsive hidden" on certain breakpoints
4. Identify any visual hierarchy cues: object sizes differ, whitespace separates groups, key metrics are larger

**Document:**
```
Layout Priority | Object | Breakpoint (Desktop / Tablet / Mobile)
-----------------|--------|----------------------------------------
1 (Top-left) | Revenue YTD KPI | Visible / Visible / Visible
2 (Top-mid) | Growth % KPI | Visible / Visible / Hidden (too tall on mobile)
3 (Top-right) | Year Filter | Visible / Visible / Visible
4 (Below) | Sales Trend | Visible / Visible / Visible (scrolls on mobile)
5 (Bottom) | Regional Detail Table | Visible / Visible / Hidden (replaced with summary)
```

---

## Step 7: Identify Responsive Behavior

**Objective:** Understand how the sheet adapts to different screen sizes.

**Procedure:**
1. Open sheet in Sheet Editor
2. Preview > Responsive Preview Mode
3. Drag window edge from desktop (1200+px) → tablet (768px) → mobile (<768px) widths
4. Observe what happens:
   - Do objects stack vertically?
   - Do any objects disappear or get replaced with alternatives?
   - Does filter pane collapse to hamburger menu?
   - Do any objects get resized?
5. Record breakpoints where behavior changes

**Document:**
```
Breakpoint | Behavior Changes
------------|------------------
Desktop (≥1200px) | 3-column layout: Filters (left) | KPIs (center-top) | Trend Chart (center-large)
Tablet (768-1199px) | 2-column layout: Filters (left, narrower) | Charts stack below
Mobile (<768px) | 1-column: Filter hamburger menu | KPIs stack | Trend chart reflows | Regional table hidden
```

---

## Step 8: Create Pattern Catalog

**Objective:** Document patterns in a reusable format for future projects.

**Template Table:**

```markdown
# Reference App Pattern Catalog

## Pattern 1: Executive Dashboard Layout

| Aspect | Pattern |
|--------|---------|
| **Sheet Name** | Executive Dashboard |
| **Purpose** | High-level metrics for C-suite decision-makers |
| **Objects** | KPI (Revenue YTD), KPI (Growth %), Line Chart (Sales Trend), Table (Top 10 Customers) |
| **Layout** | 4 KPIs across top row (equal width); 1 large trend chart below (100% width); drill-down table at bottom |
| **Filters** | Year (button group, global), Region (list, global) |
| **Colors** | Brand blue, orange, green, purple (dimension-based); conditional red/green for KPI vs. target |
| **Responsive** | Desktop: 3-column. Tablet: 2-column. Mobile: hamburger menu + KPIs stack + table hidden |
| **Accessibility** | 5:1 contrast; color-blind safe palette; all axes labeled; no information in color alone |
| **Replicable Elements** | KPI arrangement, color scheme, global filter design, responsive breakpoints |
| **Adaptations for New Project** | Measure names differ per dataset; color scheme aligns with client branding; responsive behavior same; layout same |
```

Repeat for each major pattern in the reference app.

---

## Step 9: Replication Checklist

**Objective:** When starting a new project, systematically apply reference patterns.

**Procedure:**

For each pattern in the catalog, ask:
1. **Does this pattern match my user workflow?** If yes, flag for replication.
2. **Which elements are universal (replicable as-is)?**
   - Filter pane design (list vs. search modes)
   - Layout (top KPIs, middle trend, bottom detail)
   - Responsive breakpoints
   - Color scheme
3. **Which elements need customization (adapt)?**
   - Measure expressions (specific to new dataset)
   - Dimension names (specific to new data model)
   - Field labels and formats (domain terminology)
4. **Create checklist:**

```
Replication Checklist for Executive Dashboard Pattern

[X] Copy sheet layout: Top KPIs (4 objects, equal width), trend chart (100% width), detail table
[X] Implement global filters: Year (button group), Region (list). Set defaults to Current Year + All Regions
[X] Apply color scheme: Use client brand colors (blue, orange, green, purple) for dimension values
[X] Create KPI objects: vRevenue, vGrowth%, vCustomerCount (verify expressions exist in expression catalog)
[ ] Create Line Chart: [Order.Date] monthly, Sum([Sales.Amount]). Conditional color red if below 10% target
[ ] Create Regional Comparison Table: [Customer.Region], Sum([Sales.Amount]), Avg([Margin%]). Sort by Amount desc
[ ] Test responsive preview: Mobile hamburger menu, tablet 2-column, desktop 3-column. Hide detail table on mobile
[ ] Verify accessibility: Check 4.5:1 contrast, no color-only encoding, all axes labeled
```

---

## Tools and Examples

### Tools to Inspect Apps

- **Qlik Sense Web Editor** — View sheets, open objects, inspect properties
- **Sheet Editor (Desktop)** — Full edit mode; see grid positions, responsive visibility settings
- **Data Model Viewer** — See field names, table structure (useful for dimension/measure reference)
- **Qlik Sense APIs** (if needed) — Export app metadata programmatically

### Example Pattern Catalog Entry

```markdown
## Pattern: Sales Performance Dashboard

| Element | Details |
|---------|---------|
| **Context** | Used by sales management to monitor weekly/monthly performance vs. target |
| **Sheets** | 1 (no drill-down) |
| **KPIs** | Revenue YTD, Growth % vs. Budget, Customer Count |
| **Charts** | Sales Trend (line), Regional Breakdown (stacked bar), Top 10 Products (table) |
| **Filters** | Year, Month (cascading), Region, Sales Rep (search) |
| **Responsive** | Desktop 3-col / Tablet 2-col / Mobile: 1-col with filter menu |
| **Accessibility** | Colorblind palette (blue/orange/purple), 5:1 contrast, labeled axes |
| **Replicate For** | Marketing dashboard (same layout), Finance dashboard (similar structure) |
| **Customize** | Measure expressions for new KPIs; filter fields depend on data structure |
```

---

## Cautions and Best Practices

### Don't Blindly Copy

- Verify that **every dimension and measure** exists in your new project's data model before replicating a chart
- If the reference app uses a custom expression (e.g., `YoY Growth = (Sales_This_Year - Sales_Last_Year) / Sales_Last_Year`), verify that the expression is included in your project's expression catalog before building the visualization
- Adapt field labels and formatting to match the new project's terminology and data types

### Document Deviations

If you deviate from the reference pattern, document why:
- "Used horizontal bar instead of column chart because category names are long (>15 chars)"
- "Omitted drill-down table because dataset is small enough to fit KPIs + 1 trend chart"
- "Changed filter from global to sheet-specific because this analysis is isolated to sales region"

### Validate Against New Data Model

After replicating a pattern:
1. Load the app in Qlik
2. Verify all objects load without errors
3. Check that all filters work
4. Inspect data in table form (confirm calculations are correct)
5. Test responsive preview on actual mobile/tablet devices (not just browser resize)

---

## Summary: 9-Step Workflow

1. **Examine sheet structure** — What sheets? What audience? What's the narrative flow?
2. **Analyze object types** — What charts, KPIs, filters, where on the sheet?
3. **Extract dimensions and measures** — What data is plotted in each object?
4. **Catalog filter strategy** — Global/sheet-specific, search/list/buttons, cardinality?
5. **Document colors and formatting** — Static maps, conditional, number formats, fonts?
6. **Map layout** — Information hierarchy, above/below fold, grid positions?
7. **Identify responsive behavior** — How does layout change at each breakpoint?
8. **Create pattern catalog** — Reusable template with universal and customizable elements
9. **Build replication checklist** — For next project, which elements to copy, which to adapt?

This systematic approach transforms an ad-hoc "look at this app" into a structured pattern library that scales across projects.
