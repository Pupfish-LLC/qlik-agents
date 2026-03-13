---
name: qlik-expressions
description: Set analysis syntax and patterns, aggregation functions, TOTAL qualifier usage, Aggr() patterns, conditional expressions, null handling in expressions, dollar-sign expansion, expression performance optimization, calculation conditions, and common anti-patterns for Qlik Sense expression development. Load when writing or reviewing Qlik expressions.
---

# Qlik Sense Expressions

Expressions evaluate in the USER's selection context, not in a script context. A chart object displays data based on what the user has selected in filter panes, listboxes, and other selection controls. Set analysis is the mechanism for overriding that selection context programmatically. Expression bugs almost always stem from misunderstanding selection scope. Set analysis is where the confusion begins.

This skill covers aggregation functions, set analysis syntax and patterns, the TOTAL qualifier, the Aggr() function, conditional expressions, null handling, dollar-sign expansion, calculation conditions, expression performance, and anti-patterns.

## 1. Aggregation Functions and Null Behavior

All Qlik aggregation functions skip NULL values by default. This is correct behavior but the consequences are easy to miss.

**Core aggregation functions:**
- `Sum(Field)` — Sums non-NULL values. `Sum([1, NULL, 3])` = 4. If all values are NULL, returns NULL (not 0).
- `Count(Field)` — Counts non-NULL values (not rows). `Count([1, NULL, 3])` = 2. `Count(*)` is not valid in expressions.
- `Count(DISTINCT Field)` — Counts unique non-NULL values. Use when duplicates exist and you only want unique rows counted.
- `Avg(Field)` — Average of non-NULL values: `Avg([1, NULL, 3])` = (1+3)/2 = 2.
- `Min(Field)`, `Max(Field)` — Minimum and maximum non-NULL values.
- `Only(Field)` — Returns the value if exactly one unique non-NULL value exists, NULL otherwise. Critical for lookup aggregations: `Only([Customer.Name])` avoids accidentally aggregating on fields with one value per dimension.
- `NullCount(Field)` — Counts NULL values specifically. Useful for data quality checks.
- `Concat(Field, Delimiter)` — Concatenates non-NULL values with a delimiter. `Concat([Product.Name], ', ')` produces comma-separated product names.

**The NULL aggregation trap:** `Sum()` of all NULLs returns NULL, not 0. If you need 0 instead, wrap with `Alt()` or `RangeSum()`:
```
Alt(Sum([Amount]), 0)
RangeSum(Sum([Amount]), 0)
```

## 2. Set Analysis Syntax

Set analysis is the core expression mechanism in Qlik. It overrides the current selection context for specific fields or entire tables.

**Basic syntax:** `Sum({<SetModifier>} Field)`

The curly braces `{}` are required. Everything inside is the set modifier.

**Set identifier (optional, default `$`):**
- `$` — Current selection (default if omitted)
- `1` — All data ignoring selections
- `$1` — Alternate state reference
- Bookmark names — Selections from a named bookmark

**Set operator (optional, default intersection):**
- `*` — Intersection: include only values that exist in BOTH sets
- `+` — Union: include values from EITHER set
- `-` — Exclusion: remove values from the base set
- `/` — Symmetric difference: include values in one set but not both

**Set modifier:** `<FieldName={values}>`
- Overrides the selection for that field
- Can apply to one or more fields: `<Year={2024}, Region={'East','West'}>`
- Multiple field modifiers are combined with intersection (AND logic)
- Clear a selection with no values: `<Field=>` (empty braces)

**Element set definitions:**
- Explicit values: `{1, 2, 3}` or `{'East', 'West'}`
- Wildcard (all non-null): `{*}` — matches any value EXCEPT null. Use `<Field={*}>` to exclude null values from the aggregation for that field. This is NOT the same as `<Field=>` (which clears/ignores selections on that field).
- Search strings (computed membership): `{"=Sum(Amount)>1000"}` — only values where the expression is true
- Variable references: `{$(vMyVariable)}`
- Functions: `{P(Region)}` (possible values), `{E(Region)}` (excluded values)
- Comparison operators: `Year={">2020"}` or `Month={">=1<=6"}`

**Critical distinction — `{*}` vs `<Field=>` vs omitting the field:**
- `<Field={*}>` — Restrict to non-null values of Field. Actively excludes null. Use when you need to filter out records where a field has no data (e.g., `{<[Per Capita Income]={*}>}` to exclude counties without income data).
- `<Field=>` — Ignore any user selections on Field. The field is unconstrained; null values ARE included. Use when you want the measure to be unaffected by user filter selections on that field.
- Omitting Field from set modifier — Field follows whatever the user has currently selected. Default behavior.

**Examples:**
```
Sum({$} [Amount])                    // Current selection (explicit $, same as omitting)
Sum({1} [Amount])                    // All data, no selection
Sum({<Year={2024}>} [Amount])        // 2024 only, ignoring current year selection
Sum({<Region={'East','West'}>} [Amount])  // East and West regions
Sum({$+1} [Amount])                  // Current + all data (union)
Sum({<Year={2024}, Month={"<=6"}>} [Amount])  // 2024 first half
```

Reference `set-analysis-patterns.md` for complex patterns: time intelligence (YTD, prior year), cross-table filtering, and advanced scenarios.

## 3. TOTAL Qualifier

TOTAL changes the aggregation scope to ignore the chart's dimensions. This is DIFFERENT from set analysis, which changes selection scope.

**What TOTAL does:** `Sum(TOTAL Amount)` sums across ALL dimension combinations in the data, regardless of what dimensions the chart displays.

**TOTAL with field list:** `Sum(TOTAL <Region> Amount)` ignores all dimensions EXCEPT Region. This creates a "percentage within group" pattern.

**Common TOTAL mistake:** Using TOTAL when set analysis is needed (or vice versa).
- Set analysis `{<...>}` changes what DATA is included (overrides selection)
- TOTAL changes DIMENSION SCOPE (ignores chart dimensions)

They solve different problems. Set analysis answers "exclude deleted orders". TOTAL answers "what percentage of the total is this row?"

**TOTAL for ratios:**
```
Sum(Amount) / Sum(TOTAL Amount)           // Percentage of total
Sum(Amount) / Sum(TOTAL <Region> Amount)  // Percentage within region
```

**TOTAL combined with set analysis:** TOTAL appears AFTER the set analysis closing brace, before the field name:
```
Sum({<Year={2024}>} TOTAL Amount)         // All-dimension total for 2024 only
Sum({<Year={2024}>} TOTAL <Region> Amount) // Region-level total for 2024
```

**Parsing trap:** `Sum({<...>}Total Field)` looks like a field called "Total Field" but Qlik parses `Total` as the TOTAL qualifier keyword. The keyword is case-insensitive. If you actually have a field named "Total Something," you must use square brackets: `Sum({<...>}[Total Something])`. When reviewing expressions, always check whether `Total` before a field name is the TOTAL qualifier or part of the field name.

**Performance note:** TOTAL forces recalculation across all rows. On datasets with millions of rows, this is expensive. Consider pre-calculating in the script (a flag field) when performance matters.

## 4. Aggr() Function

Aggr() creates a virtual table (temporary dimension-measure pairs) that Qlik can aggregate over. Essential for calculated dimensions and nested aggregations.

**Basic pattern:** `Aggr(Sum(Sales), Customer)` — Creates a virtual table with one row per unique Customer showing their total Sales.

**Nested aggregation:** `Avg(Aggr(Sum(Sales), Customer))` — Average of per-customer sums. Aggr() is the **only** valid way to nest aggregation scopes. Direct nesting of aggregation functions (e.g., `Avg(Sum(Sales))`) is structurally invalid in Qlik. The engine cannot resolve two aggregation scopes simultaneously. This also applies to hidden nesting via dollar-sign expansion: if a SET variable contains `Sum(...)`, placing `$(vMySum)` inside `Avg()` expands to `Avg(Sum(...))` at render time, which is equally invalid. Always use Aggr() as the intermediate step when an outer aggregation must operate on per-dimension aggregated values.

**Multiple dimensions:** `Aggr(Sum(Sales), Year, Month)` — Virtual table with Year-Month combinations. Useful for time series buckets.

**Aggr with NODISTINCT:** By default, Aggr produces distinct dimension combinations. `Aggr(Sum(Sales), Customer, NODISTINCT)` preserves duplicate rows if they exist (rarely needed).

**Limitations and performance warnings:**
- Aggr's dimension must be an actual field in the data model. Calculated dimensions inside Aggr (e.g., `Aggr(..., Year & Month)`) don't work as expected.
- Aggr creates a virtual table in memory. Nested Aggr (Aggr inside Aggr) compounds memory usage. Use sparingly on large datasets.
- If performance is critical, pre-calculate in the script instead.

## 5. Conditional Expressions

**IF(condition, then, else)** — Standard conditional. If condition is NULL, evaluates to ELSE branch (not an error).
```
IF(Region='East', Sum([Amount]), 0)
IF(IsNull(field), 'Unknown', field)
```

**Pick(n, val1, val2, ...)** — Index-based selection. Returns value at position n. Useful with Match() for multi-branch logic:
```
Pick(Match(Status, 'Pending', 'Approved', 'Rejected'), 'Not Started', 'In Progress', 'Complete')
```

**Match() / WildMatch() / MixMatch()** — Pattern matching returning position (1-based).
- `Match(field, 'A', 'B')` returns 1 if field='A', 2 if field='B', 0 if no match
- `WildMatch(field, 'prefix*', 'other*')` supports wildcards
- `MixMatch(field, 'A', 'B')` is case-insensitive

**Class(value, min1, min2, ...)** — Range bucketing. `Class(Age, 0, 18, 25, 65)` produces ranges [0-18), [18-25), [25-65), [65+).

**Anti-pattern: deeply nested IF:** Hard to read and error-prone. Prefer Pick(Match(...)) for multi-branch logic:
```
// WRONG - unreadable nesting
IF(Status='A', IF(Region='East', 'EA', 'WA'), IF(Status='B', 'OB', 'OTHER'))

// RIGHT - clear precedence with Pick/Match
Pick(Match(Status, 'A', 'B'),
    Pick(Match(Region, 'East', 'West'), 'EA', 'WA'),
    'OB',
    'OTHER')
```

## 6. Dollar-Sign Expansion in Expressions

Dollar-sign expansion substitutes variable text into expressions at evaluation time. The critical rule: **commas inside $() are parameter delimiters, not expression commas.**

**Variable references:** `$(vMyVariable)` expands the variable's text content.

**Parameterized expressions:** `$(vCalc(Field1))` where vCalc is a SET variable function:
```
SET vDualBool = IF(Match($1, 'true') > 0, Dual('$2', 1), Dual('$3', 0));
Sum({<Status={$(vDualBool(Status, 'Active', 'Inactive'))}>} Amount)
```

**The comma limitation (critical):** Expressions with commas cannot be passed as arguments to variable functions. Commas are interpreted as parameter delimiters:
```
// WRONG - ApplyMap's commas break parameter parsing:
$(vCleanNull(ApplyMap('MyMap', field, 'default')))
// The engine sees: $1=ApplyMap('MyMap', $2=field, $3='default')

// RIGHT - write inline when expression contains commas:
IF(IsNull(ApplyMap('MyMap', field, 'default')), Null(), ApplyMap('MyMap', field, 'default'))
```

Common violations: ApplyMap (has commas), PurgeChar (has comma), IF (has commas), Concat (has comma).

When a variable function cannot wrap an expression due to commas, write the equivalent logic inline and add a comment.

**Dynamic set analysis:** `Sum({<Year={$(vCurrentYear)}>} Sales)` — Variable expands before set analysis evaluates.

**Evaluation timing:**
- `$(variable)` substitutes the variable's text content at parse time
- `$(=expression)` forces immediate evaluation and substitutes the result at parse time
- This matters for dynamic labels: `=$(=Sum(Amount))` shows the evaluated sum in a text box

Reference `set-analysis-patterns.md` for dynamic set modifiers and indirect references like `Year={$(=Max(Year))}`.

## 7. Calculation Conditions

Calculation conditions prevent expensive calculations when the result would be meaningless (e.g., showing all-time data when the user expects a filtered view).

**Object-level calculation condition:** An expression that must evaluate to TRUE (-1) for the object to calculate. If FALSE, displays a message.

**Common patterns:**
```
Count(DISTINCT Year) = 1                    // Requires single year selected
GetSelectedCount(Region) > 0                // Requires region selection
Count(DISTINCT [Customer.Key]) < 10000      // Prevents slow cross-product
NoOfRows('$') > 100                         // Only show if enough data rows
```

**Sheet-level calculation conditions:** Available in Qlik Sense. Use for sheets that would timeout without selections.

**The trap:** A calculation condition that's too restrictive frustrates users ("why can't I see this data?"). Too permissive causes slow rendering. Balance is project-specific. Consult with users before deploying restrictive conditions.

## 8. Expression Performance Optimization

**Avoid complex set analysis when a script flag field would suffice:**
```
// Heavy - evaluates for every row
Sum({<IsReturned={0}>} Amount)

// Light - flag calculated once in script
Sum([IsReturned] * [Amount])
```

**Pre-calculate in script what doesn't need to be dynamic:**
- Age groups, fiscal periods, seasonal labels — calculate at load time
- Complex business rules applied to every transaction — use derived fields

**Use variables for repeated sub-expressions:**
Variables are calculated once and referenced many times. Better than repeating the same expression.

**Minimize Aggr() usage on large datasets:**
Aggr creates virtual tables in memory. Each level of nesting multiplies memory use. Pre-aggregate in the script if the result doesn't need to be dynamic.

**TOTAL is expensive:**
TOTAL forces row-by-row recalculation. Pre-calculate totals as a script field when used repeatedly.

**Prefer flag multiplication over set analysis for simple filters:**
`Sum([Flag] * [Amount])` is faster than `Sum({<Flag={1}>} Amount)` when the flag is boolean.

**Calculation conditions prevent unnecessary heavy calculations:**
If a sheet condition fails, all calculations on that sheet skip. This saves processing time.

## 9. Null Handling in Expressions

**Aggregation functions skip NULLs:** `Sum([1, NULL, 3])` = 4, not NULL.

**Count() counts non-NULL values:** `Count([1, NULL, 3])` = 2 (not 3 rows, just 2 non-NULL values).

**Division by zero returns NULL:** `1/0` = NULL (not an error). `5/0` = NULL. This is safe but can hide logic errors.

**Alt() for null coalescing:** `Alt(expression, fallback)` returns fallback if expression is NULL.
```
Alt(Sum([Amount]), 0)
Alt([Customer.Name], 'Unknown')
```

**RangeSum() for null-safe addition:** `RangeSum(A, B)` returns the non-null value if one is null. Unlike `A + B` which returns NULL if either is NULL.

**Null() function:** Explicitly returns NULL. Useful for conditional expressions:
```
IF(IsNull(field), Null(), Sum(field))
```

**The expression NULL gotcha:** `IF(field = 'value', ...)` when field is NULL evaluates to FALSE, not NULL. This is correct Qlik behavior but trips people up. Null comparisons never match; they're always false. Use `IF(IsNull(field), ...)` to check for nulls.

## 10. Common Anti-Patterns

| Anti-Pattern | What Goes Wrong | Fix |
|---|---|---|
| Missing `$` in set identifier | `{<Field={value}>}` defaults to `$` (current), but adding operators requires explicit set: `{$*<...>}` | Always include explicit set identifier when using operators: `{$<Field={value}>}` |
| Using TOTAL when set analysis needed | TOTAL changes dimension scope, not selection. Wrong tool for the job. | Use set analysis `{<...>}` to override selections. Use TOTAL to change aggregation scope. |
| Deeply nested IF | Unreadable, error-prone, hard to maintain | Use Pick(Match(...)) for multi-branch logic |
| `Sum(field1 * field2)` vs. `Sum(field1) * Sum(field2)` | These produce different results. First aggregates products, second multiplies aggregates. Only the second is "revenue per unit × units = total." | Choose deliberately based on business logic. Document which is intended. |
| Forgetting Alt() or RangeSum() | NULL + something = NULL. Unexpected NULL results. | Use Alt() or RangeSum() for null-safe arithmetic. |
| Hardcoded year values in set analysis | `{<Year={2024}>}` is brittle. If you need current year dynamic, use variable. | Use variables: `{<Year={$(vCurrentYear)}>}` |
| Aggr() with calculated dimensions | Aggr expects field names, not expressions. Calculated dimensions don't work. | Use only actual fields in Aggr dimension list. Pre-calculate in script if needed. |
| Missing DISTINCT in Count | Count([field]) counts non-NULL rows. If duplicates exist and you want unique, you miss DISTINCT. | Use `Count(DISTINCT field)` when uniqueness matters. |
| Wrong element set syntax in set analysis | Missing quotes on string values: `{<Region={East}>}` (East is a variable, not literal). Bracket confusion. | String literals need quotes: `{<Region={'East'}>}`. Use `{}` for implicit sets, `{}` shorthand for explicit. |
| Using SET variable without understanding comma limitation | Passing expressions with commas to variable functions breaks. | Never pass expressions with commas to variable functions. Write inline instead. |

For more anti-pattern details with examples, see `set-analysis-patterns.md`.

## Supporting Files

Read `set-analysis-patterns.md` for:
- Complete set analysis syntax reference
- Set operator patterns with business scenarios
- Element set patterns (explicit, search strings, functions)
- Time intelligence patterns (YTD, prior year, rolling periods)
- Cross-table set analysis patterns
- Advanced patterns (nested set analysis, set + TOTAL, set + Aggr)
- Anti-pattern catalog with correct expressions
