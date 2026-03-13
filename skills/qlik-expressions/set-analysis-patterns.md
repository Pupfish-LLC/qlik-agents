# Set Analysis Pattern Reference

## 1. Complete Syntax Reference

**Full set analysis grammar:**

```
{[SetIdentifier] [SetOperator] <FieldModifier1={ElementSet1}[, FieldModifier2={ElementSet2}, ...]>}
```

Every component is optional. The default set is the current selection (`$`), so `Sum(Amount)` is equivalent to `Sum({$} Amount)`.

### Set Identifier
- `$` — Current selection (default if omitted)
- `1` — All data, ignoring all selections
- `$1` — Alternate state (field-level bookmarks)
- `BookmarkName` — Selections from a saved bookmark
- Omitted — Defaults to `$` (current selection)

### Set Operator
Combines the set identifier with one or more field modifiers.

- `*` (intersection) — Combine with AND logic. Include only values that satisfy ALL conditions.
- `+` (union) — Combine with OR logic. Include values that satisfy ANY condition.
- `-` (exclusion) — Start with the base set and remove matching values.
- `/` (symmetric difference) — Include values that match one modifier but not both.

Operator is applied AFTER the set identifier. Default (omitted operator) is intersection.

### Field Modifiers
`<FieldName={ElementSet}>`

Each modifier overrides the selection for that field. Multiple field modifiers apply with intersection (AND) unless explicitly combined with union:
```
<Year={2024}, Region={'East'}>          // AND: Year=2024 AND Region=East
<Year={2024} + Region={'East'}>         // OR: Year=2024 OR Region=East (union)
```

### Element Sets
What values to include in the field modifier.

- **Explicit list:** `{'East', 'West'}` or `{1, 2, 3}`. String values require quotes.
- **Search string:** `{"=Sum(Amount)>1000"}` — Expression is evaluated for each field value. Only values where the expression is true are included.
- **Variable expansion:** `{$(vMyVariable)}` — Variable is expanded into the element set.
- **Functions:** `{P(Region)}` (possible values in current selection), `{E(Region)}` (excluded values from current selection)
- **Comparison operators:** `Year={">2020"}` or `Month={">=1<=6"}` — String comparison for date ranges or numbers.
- **Empty set:** `<Field={}>` — Clears the selection on that field, making it contribute nothing to the aggregation.

---

## 2. Set Operator Patterns with Business Scenarios

### Intersection (`*`)
Combine sets with AND logic. Include only values that exist in BOTH sets.

**Scenario:** Sales for regions that are BOTH in this year's plan AND had activity last year.
```
Sum({$*<Year={$(vCurrentYear)}>} [Order.Amount])
```
- Start with current selections (`$`)
- Intersect with: Year = current year
- Result: Respects all current selections, but forces year to current

**More complex:** Regions that have BOTH completed orders AND planned budget.
```
Sum({<OrderStatus={'Completed'}>*<BudgetStatus={'Approved'}>} [Amount])
```
- Include values where OrderStatus = 'Completed' AND BudgetStatus = 'Approved'
- Other dimensions (Region, Customer) follow current selection

### Union (`+`)
Combine sets with OR logic. Include values that satisfy ANY condition.

**Scenario:** Revenue from active customers OR customers with recent activity.
```
Sum({<CustomerStatus={'Active'}>+<LastPurchaseDate={">2024-01-01"}>} [Revenue])
```
- Include customers where Status = 'Active' OR LastPurchaseDate > 2024-01-01
- This is OR at the field level: either condition satisfies inclusion

**Time intelligence use:** Current month OR prior month.
```
Sum({<Month={$(vCurrentMonth)}>+<Month={$(vPriorMonth)}>} [Amount])
```

### Exclusion (`-`)
Remove values from the base set.

**Scenario:** All sales EXCEPT returns.
```
Sum({<OrderType={'-Returns'}>} [Amount])
```
- Start with implicit `$` (current selection)
- Exclude OrderType = 'Returns'

**Multi-field exclusion:** All orders except those from excluded regions AND excluded customers.
```
Sum({<Region={'-Blacklist'}>*<Customer={'-Blocked'}>} [Amount])
```
- Exclude Blacklist regions AND Blocked customers
- Note the `*` (intersection) to apply both exclusions

### Symmetric Difference (`/`)
Include values in one set but NOT both. Rarely used; included for completeness.

**Scenario:** Customers who are EITHER recent buyers OR high-value, but not both (identifies emerging vs. established patterns).
```
Count({<IsRecent={'Yes'}>/<IsHighValue={'Yes'}>} [Customer.Key])
```
- Include customers where IsRecent=Yes and IsHighValue!=Yes
- OR IsHighValue=Yes and IsRecent!=Yes
- Exclude customers who are both or neither

---

## 3. Element Set Patterns

### Explicit Values
Simple list of literal values. Strings require single quotes.

```
Sum({<Region={'East', 'West'}>} [Amount])
Sum({<Month={1, 2, 3}>} [Amount])
Sum({<Status={'Active', 'Pending'}>} [Amount])
```

Numbers can be quoted or unquoted: `{1, 2}` or `{'1', '2'}` both work.

### Search Strings (Computed Membership)
Expression evaluated for each field value. Only values where expression is true are included.

```
Sum({"=Sum(Amount)>1000"} [Amount])
```
- For each Product value, evaluate `Sum(Amount) > 1000`
- Include only products where the sum exceeds 1000

**Data quality example:** Products with no null quantities.
```
Count({"=NullCount([OrderLine.Qty])=0"} [Product.Key])
```

**Practical time intelligence:** Months in the first half of the year.
```
Sum({<Month={">=1<=6"}>} [Amount])
```
- String comparison: Month values between '1' and '6' (inclusive)

### Variable Expansion
Variable is substituted into the element set.

```
SET vSelectedRegions = 'East', 'West';
Sum({<Region={$(vSelectedRegions)}>} [Amount])
// Expands to: Sum({<Region={'East', 'West'}>} [Amount])
```

**The comma limitation:** If vSelectedRegions is set to a value containing commas, be cautious with parameter passing (see dollar-sign expansion in SKILL.md).

### P() and E() Functions
`P(Field)` returns possible values (values that exist in the current selection). `E(Field)` returns excluded values (values NOT in the current selection).

```
Sum({<Region={P(Region)}>} [Amount])
```
- Redundant (same as current selection), but explicit about intent

**More useful:** Show all sales, but highlight regions that are in current selection.
```
Sum({<Region={E(Region)}>} [Amount])
// Sales from regions the user has NOT selected
```

### Comparison Operators in Element Sets
String comparison for ranges and pattern matching.

```
Year={">2020"}                // Years greater than "2020" (string comparison)
Month={">=1<=6"}              // Months between "1" and "6" (string comparison)
OrderDate={">2024-01-01"}     // Dates after "2024-01-01" (string-comparable dates)
```

**Important:** These are STRING comparisons, not numeric. `Year={">2020"}` works for 4-digit years because "2021" > "2020" as strings. For non-zero-padded months, `Month={">=01<=06"}` is safer than `Month={">=1<=6"}` to handle both "01" and "1" representations.

### Indirect Set Analysis (Dollar-Sign Expansion)
Variable expands to a value, which is then used in set analysis.

```
SET vCurrentYear = Num(Today(), 'YYYY');
Sum({<Year={$(vCurrentYear)}>} [Amount])
// Expands to: Sum({<Year={2026}>} [Amount]) [if vCurrentYear=2026]
```

**Dynamic computed set:** Include the maximum year in data.
```
Sum({<Year={$(=Max(Year))}>} [Amount])
// $(=...) forces evaluation, substitutes the result
// If max year in data is 2026, expands to Sum({<Year={2026}>} [Amount])
```

---

## 4. Time Intelligence Patterns

### Year-to-Date (YTD)
Sum for current year through current month.

```
SET vCurrentYear = Num(Today(), 'YYYY');
SET vCurrentMonth = Num(Today(), 'MM');

Sum({<Year={$(vCurrentYear)}, Month={"<=$(vCurrentMonth)"}>} [Amount])
// Current year, months 1 through current month
```

**Assumption:** Month field is numeric (01, 02, ..., 12) or zero-padded.

### Prior Year Comparison
Sum for the same period last year.

```
Sum({<Year={$(=Max(Year)-1)}>} [Amount])
// Max year in data minus one
```

**Prior year same month:**
```
SET vCurrentYear = Num(Today(), 'YYYY');
SET vCurrentMonth = Num(Today(), 'MM');

Sum({<Year={$(=$(vCurrentYear)-1)}, Month={$(vCurrentMonth)}>} [Amount])
```

### Rolling 12 Months
Sum of the last 12 months. Requires a sequential Month Key field (e.g., 202401, 202402, ..., 202512).

```
SET vCurrentMonthKey = Num(Today(), 'YYYYMM');

Sum({<MonthKey={">=$(=$(vCurrentMonthKey)-11)"}>} [Amount])
// Current month key and the 11 months prior
```

**Alternative without Month Key:** Use a bridge table or calculation condition to filter to the last 12 distinct months in the selection.

### Period Comparison
Current period vs. prior period side-by-side (requires separate measures).

```
// Current period (uses selection)
Sum([Amount]) AS [Current Period]

// Prior year same period (overrides year)
Sum({<Year={$(=Max(Year)-1)}>} [Amount]) AS [Prior Period]
```

In a table with both expressions, users see period-over-period comparison.

---

## 5. Cross-Table Set Analysis Patterns

### Filtering One Fact Table by a Dimension Value Without Affecting Another
Two fact tables (Orders, Returns) associated through Product.

```
Sum({<ProductCategory={'Electronics'}>} [Order.Amount]) AS [Electronics Orders]
Sum({<ProductCategory={'Electronics'}>} [Return.Amount]) AS [Electronics Returns]
```

- The set modifier `<ProductCategory={'Electronics'}>` applies to both tables
- Both aggregations respect the category filter
- Product association flows through to both fact tables

### Using Alternate States for Comparative Analysis
Alternate states allow multiple independent selections in one app.

```
Sum({$} [Amount]) AS [Current Selections]
Sum({$Selection1} [Amount]) AS [Saved Selection 1]
Sum({$Selection2} [Amount]) AS [Saved Selection 2]
```

- `$` — Active selections from user interactions
- `$Selection1` — Independent selections saved in an alternate state
- Useful for "what-if" analysis and period-over-period

### Set Analysis with Dimensions from Different Tables
Qlik association propagates field selections across related tables.

**Scenario:** Product dimension, Order fact table, Customer dimension. Selecting a product should filter orders for that product.

```
Sum({<Product.Category={'Electronics'}>} [Order.Amount])
// Selects products in Electronics category (from Product dimension)
// Filters to orders containing those products (through Order.ProductKey)
// Association is automatic through the data model
```

If the dimension and fact are not directly associated (different keys), explicit join or bridge table is needed (script-level, not expression).

---

## 6. Advanced Patterns

### Nested Set Analysis (Set Within Set)
Inner set modifies, outer set applies operator.

```
Sum({<Year={2024}>*<Region={$(={P(Region)})}>} [Amount])
// Intersection of: Year=2024 AND Region=current selections
// P(Region) returns possible values in current selection (usually current, but syntactically explicit)
```

Rarely necessary. Included for completeness.

### Set Analysis Combined with TOTAL
Override selection (set analysis) AND change dimension scope (TOTAL).

```
Sum({<Year={2024}>} [Amount]) / Sum(TOTAL {<Year={2024}>} [Amount])
// Numerator: 2024 amounts for current dimension combination
// Denominator: 2024 amounts across ALL dimension combinations
// Result: Percentage of 2024 total for this row
```

The `TOTAL` applies to the entire aggregation, not just the set analysis.

### Set Analysis with Aggr
Virtual table aggregation combined with set selection override.

```
Avg(Aggr(Sum({<Year={2024}>} [Amount]), [Customer.Key]))
// Create virtual table: Customer -> 2024 sum of amounts (for each customer)
// Then average across customers
// Same as: Average 2024 sales per customer
```

Without the set modifier, Aggr would include all years. The set modifier restricts Aggr's scope.

### Conditional Set Modifiers Using IF Inside Element Sets
Expression inside element set decides which values to include.

```
Sum({"=Sum(Amount) > Avg($(=Avg(Amount)))"} [Amount])
// For each product, check if its sum exceeds the overall average
// Include products where this is true
```

This is a search string (computed membership). It evaluates the expression for each possible value of the implicit field context.

### Top N Patterns
Include only the top N values by measure.

```
Sum({"=Rank(Sum(Amount))<=10"} [Amount])
// For each Product, rank its total sales
// Include top 10 products
```

**Note:** Rank() must be called inside the search string with the same aggregation logic as the outer aggregation. This pattern is complex and often better solved with a script-level Top N flag.

---

## 7. Anti-Pattern Catalog

### Anti-Pattern: Missing Set Identifier When Using Operators

**Wrong:**
```
Sum({*<Year={2024}>} [Amount])
// The * operator requires a left operand (set identifier)
// This syntax is invalid
```

**What goes wrong:** Qlik can't parse the expression. Reload error or unexpected results.

**Correct:**
```
Sum({$*<Year={2024}>} [Amount])
// Intersection of current selection ($) with Year=2024
// Respects all current selections, but forces year
```

### Anti-Pattern: Wrong Set Operator for the Scenario

**Wrong (intersection when union needed):**
```
Sum({<Status={'Active'}, Status={'Inactive'}>} [Amount])
// Same field with two values, implicit intersection
// A value cannot be both Active and Inactive
// Result: Empty set, returns NULL
```

**What goes wrong:** No data matches. Silent NULL (confusing).

**Correct (union):**
```
Sum({<Status={'Active'}+Status={'Inactive'}>} [Amount])
// Union: Status is Active OR Inactive
// Returns the sum of all amounts for both statuses
```

**Simpler equivalent:**
```
Sum({<Status={'Active', 'Inactive'}>} [Amount])
// Comma-separated values in the same modifier are implicitly unioned
```

### Anti-Pattern: Hardcoded Values Instead of Variables

**Wrong:**
```
Sum({<Year={2024}>} [Amount])
// Next year, this expression is outdated
// User gets last year's data instead of current year
```

**What goes wrong:** Static values become stale. App breaks annually. No maintenance notice.

**Correct:**
```
SET vCurrentYear = Num(Today(), 'YYYY');
Sum({<Year={$(vCurrentYear)}>} [Amount])
// Always current year, no maintenance needed
```

### Anti-Pattern: Misuse of P() and E()

**Wrong:**
```
Sum({<Region={P(Region)}>} [Amount])
// This is redundant -- same as not specifying any set modifier
// P(Region) returns the currently selected regions
// You're explicitly filtering to what's already selected
```

**What goes wrong:** No functional error, but it's redundant code.

**When P() is useful:**
```
Sum({<Region={E(Region)}>} [Amount])
// E(Region) = regions NOT currently selected
// Show what you're NOT looking at
```

### Anti-Pattern: Element Set Syntax Errors

**Wrong (missing quotes on strings):**
```
Sum({<Region={East, West}>} [Amount])
// Qlik interprets East and West as variables, not literals
// If variables vEast and vWest don't exist, returns NULL
```

**What goes wrong:** Unintended variable reference. Silent NULL or wrong data.

**Correct:**
```
Sum({<Region={'East', 'West'}>} [Amount])
// Single quotes make it a literal string
```

**Wrong (brackets instead of braces):**
```
Sum({<Region=[East, West]>} [Amount])
// Square brackets are for field names, not element sets
// Syntax error or unexpected interpretation
```

**Correct:**
```
Sum({<Region={'East', 'West'}>} [Amount])
// Curly braces for element set, quotes for strings
```

### Anti-Pattern: SET Variable Containing Commas Passed to Another Variable

**Wrong:**
```
SET vRegionList = 'East', 'West';
Sum({<Region={$(vCleanRegion($(vRegionList)))}>} [Amount])
// The variable expansion substitutes: East', 'West (with commas)
// If vCleanRegion is a variable function, commas break parameter parsing
```

**What goes wrong:** Parameter parsing fails. Reload error or wrong result.

**Correct:**
```
SET vRegionList = 'East', 'West';
Sum({<Region={$(vRegionList)}>} [Amount])
// Expand directly, don't wrap in another variable function
```

### Anti-Pattern: Forgetting to Override All Necessary Selections

**Wrong (partial override):**
```
Sum({<Year={2024}>} [Amount])
// User has selected Year=2023, Region=East, Customer=ABC
// The set modifier only overrides Year
// The expression still respects Region=East and Customer=ABC
// Result: 2024 sales for East region only, not all East
// (This may be intentional, but often is not)
```

**What goes wrong:** Unexpected subset of data. User thinks they're seeing all 2024, but they're seeing filtered 2024.

**Clarify intent:**
```
// If you want ALL 2024 regardless of other selections:
Sum({<Year={2024}, Region={}, Customer={}>} [Amount])
// Clears Region and Customer selections for this expression

// If you want 2024 respecting other selections (truly what-if):
// Comment the intent in the expression or use a calculation label
Sum({<Year={2024}>} [Amount])  // 2024 for selected region/customer
```

### Anti-Pattern: Using TOTAL When Set Analysis is Needed

**Wrong:**
```
// User selected Region=East
// You want to see sales from all regions
Sum(TOTAL [Amount])
// TOTAL changes dimension scope, not selection scope
// Result: Sums across all dimensions in the chart, still respecting Region=East
// You get exactly the same result as if TOTAL wasn't there
```

**What goes wrong:** TOTAL doesn't override selection. Misunderstood purpose.

**Correct:**
```
Sum({1} [Amount])
// {1} means "all data, ignoring selections"
// Result: All regions' sales, regardless of filter pane selection
```

### Anti-Pattern: Deeply Nested IF in Expressions

**Wrong:**
```
IF(Status='A', IF(Region='East', 'EA', 'WA'), IF(Status='B', 'OB', 'OTHER'))
```

**What goes wrong:** Hard to read, easy to miss a branch, error-prone to maintain.

**Correct (Pick/Match):**
```
Pick(Match(Status & Region, 'A' & 'East', 'A' & 'West', 'B'),
    'EA', 'WA', 'OB')
// Clearer precedence and logic flow
```

### Anti-Pattern: Comparing Fields in Set Modifier Without Dollar-Sign Expansion

**Wrong:**
```
Sum({<Year=Year>} [Amount])
// This doesn't mean "Year matches the current dimension value"
// It's a literal comparison (Year field name to Year value, doesn't work as intended)
```

**What goes wrong:** Syntax error or unexpected behavior.

**Correct (if intent is dynamic filter to dimension):**
```
Sum({<Year={$(=Only(Year))}>} [Amount])
// Only(Year) returns the single year if one is selected
// Expand with $(=...) to evaluate
// Set Year to that value
```

---

## Summary

Set analysis is powerful but precise. The most common mistakes stem from:
1. Confusing set analysis (selection scope) with TOTAL (dimension scope)
2. Syntax errors (wrong brackets, missing quotes)
3. Comma limitations in dollar-sign expansion
4. Hardcoded values instead of variables
5. Misunderstanding the scope of a field modifier (affects all dimensions or just that field)

Test every expression with real data. Use TRACE or diagnostic queries to verify that your set modifiers are including/excluding the expected data.
