# Null Handling Patterns for Qlik Scripts

Three distinct strategies for handling nulls in Qlik load scripts. Each addresses a different type of null problem. Using the wrong strategy for a given situation produces subtle data quality bugs.

---

## vCleanNull Variable Function

### The Problem

Source data from ETL pipelines, JSON ingestion, data lakes, and API exports commonly contains literal strings that represent null: `"null"`, `"NaN"`, `"none"`, `"n/a"`, `"[null]"`, and empty strings. These are NOT SQL NULLs. Qlik's `IsNull()` function does NOT catch them. They appear as valid string values in filter panes and break aggregations.

### The Pattern

```qlik
// SET preserves the template -- $1 placeholder stays unevaluated until expansion
SET vCleanNull = IF(IsNull($1) OR Len(Trim($1)) = 0
    OR Match(Lower(Trim($1)), 'null', 'nan', 'none', 'n/a', '[null]'),
    Null(), Trim($1));
```

### Usage

```qlik
// Simple field -- pass field name as $1:
$(vCleanNull(customer_name)) AS [Customer.Name],
$(vCleanNull(email_address)) AS [Customer.Email],
$(vCleanNull(phone_number))  AS [Customer.Phone]
```

### Why SET, Not LET

`SET` preserves the right side as a literal string template. The `$1` placeholder remains unevaluated until the variable is expanded with `$(vCleanNull(field))`. `LET` would try to evaluate `$1` immediately at definition time and fail.

### Limitation: Commas in Arguments

The variable function CANNOT wrap expressions containing commas. Inside `$()`, commas separate parameters. If the argument contains a function with commas (ApplyMap, PurgeChar, IF), the call breaks.

```qlik
// WRONG -- PurgeChar has a comma, breaks the variable call:
$(vCleanNull(PurgeChar(given_names, '[]{}' & Chr(34))))

// RIGHT -- write the null check inline with a comment explaining why:
// Cannot use vCleanNull here (comma in PurgeChar args)
IF(IsNull(PurgeChar(given_names, '[]{}' & Chr(34)))
   OR Len(Trim(PurgeChar(given_names, '[]{}' & Chr(34)))) = 0
   OR Match(Lower(Trim(PurgeChar(given_names, '[]{}' & Chr(34)))),
            'null', 'nan', 'none', 'n/a', '[null]'),
   Null(),
   Trim(PurgeChar(given_names, '[]{}' & Chr(34))))  AS [Name.Given]
```

### When to Use

- Fields from ETL pipelines, data lakes, or API ingestion where nulls may be string-encoded
- Any field where you've observed literal "null" or "NaN" strings in the data
- As a default defensive measure on all string fields from external sources

### When NOT to Use

- Fields where the literal string "null" is a valid business value (rare but possible)
- Key fields (use explicit null checks and TRACE warnings instead)
- Numeric fields (use IsNull() directly, string-encoded nulls in numeric fields indicate a type coercion issue that should be investigated)

### Complete Variable Function File

See `script-templates/clean-null-function.qvs` for the full set of null-cleaning utilities including vCleanNull, vCleanDate, vCleanNumeric, and vDualBool.

**vDualBool overview:** Converts a boolean-like field to `Dual()` with text display and numeric value. `Dual('Active', 1)` for true-like values, `Dual('Inactive', 0)` for false, `Dual('Unknown', -1)` for NULL. This gives text in filter panes, numeric for `Sum()`, and correct sort order. The function matches common true values ('true', 'yes', 'y', '1', 'active', 'enabled'). For domain-specific true values like 'approved' or 'confirmed', write a custom IF instead. See `clean-null-function.qvs` for the full definition.

---

## NullAsValue Patterns

### The Problem

Sparse dimension fields where many records have NULL values. In Qlik filter panes, NULL values appear as "-" and cannot be selected alongside non-null values in the same selection set. Users want to see "No Entry" or "Unknown" as a selectable value.

### The Pattern

```qlik
SET NullValue = 'No Entry';
NullAsValue [Customer.Region], [Customer.Segment], [Product.SubCategory];

[Customers]:
LOAD
    customer_id    AS [Customer.Key],
    customer_name  AS [Customer.Name],
    region         AS [Customer.Region],
    segment        AS [Customer.Segment]
FROM [lib://QVDs/Customers.qvd] (qvd);

// Always reset after each table load unless you intentionally want
// the null replacement to persist across subsequent LOADs for these fields.
// Forgetting to reset is the most common NullAsValue bug.
NullAsNull *;
SET NullValue =;
```

### Critical Rules

1. **Field-specific:** NullAsValue only affects the named fields. Other fields in the same LOAD retain normal null behavior.

2. **Stateful:** Once declared, NullAsValue persists for those fields across ALL subsequent LOADs until explicitly reset with `NullAsNull`. This means:
   - If you load `[Customer.Region]` in multiple tables, NullAsValue applies to ALL of them unless reset between LOADs
   - Failing to reset when you only wanted it for one table means unintended null replacement downstream

3. **Output alias matching:** Field names in the NullAsValue declaration must match the OUTPUT aliases, not the source field names.

```qlik
// WRONG -- uses source field name, NullAsValue has no effect:
NullAsValue region;
LOAD region AS [Customer.Region] FROM ...;
// The loaded field is [Customer.Region], but NullAsValue targets "region" -- no match.

// RIGHT -- uses output alias:
NullAsValue [Customer.Region];
LOAD region AS [Customer.Region] FROM ...;
```

4. **Reset protocol:** Reset with BOTH statements:
```qlik
NullAsNull *;       // Resets all fields to normal null behavior
SET NullValue =;    // Clears the replacement string
```

### When to Use

- Sparse dimension fields where NULL should be a selectable filter value
- Fields that serve as dimension headers in filter panes
- Classification fields where "Unknown" or "Not Assigned" is a meaningful category

### When NOT to Use

- **Key fields:** NullAsValue converts NULL to a string ('No Entry'). A key field containing 'No Entry' will associate with OTHER tables' 'No Entry' values, creating false associations. If a key is NULL, that's a data quality issue to investigate, not mask.

- **Measure fields intended for Sum/Avg:** NullAsValue converts NULL to a string. `Sum()` on a field containing the string 'No Entry' produces 0 (the string is treated as 0 in numeric context) but `Avg()` treats it as a valid value, skewing the average downward. NULL values are correctly excluded from both Sum and Avg by default.

- **Fields used in date arithmetic:** The string 'No Entry' in a date field breaks date calculations.

### Scope Management Example

```qlik
// Apply NullAsValue for Customer table only
SET NullValue = 'Unknown';
NullAsValue [Customer.Region], [Customer.Segment];

[Customers]:
LOAD customer_id AS [Customer.Key],
     region AS [Customer.Region],
     segment AS [Customer.Segment]
FROM [lib://QVDs/Customers.qvd] (qvd);

// Reset before loading Product table (Product.Category should NOT get 'Unknown')
NullAsNull *;
SET NullValue =;

// Product NULLs stay as NULL (correct for this table)
[Products]:
LOAD product_id AS [Product.Key],
     category AS [Product.Category]
FROM [lib://QVDs/Products.qvd] (qvd);
```

---

## Null Guards on Date Arithmetic

### The Problem

Date arithmetic on NULL produces a large number, not NULL. Qlik stores dates as serial numbers (days since December 30, 1899). When you subtract NULL from Today(), the engine treats NULL as 0 (the epoch), producing a result of ~46,000+ days, or ~125 years for an age calculation.

```qlik
// WRONG -- NULL birth_date produces age of ~125, not NULL:
Floor((Today() - birth_date) / 365.25) AS [Age]

// When birth_date is NULL:
// Floor((46000 - 0) / 365.25) = Floor(125.9) = 125
// This record now shows Age = 125 -- a data quality disaster.
```

### The Pattern

Always guard date arithmetic with an explicit IsNull check:

```qlik
// RIGHT -- explicit null guard:
IF(IsNull(birth_date) OR birth_date > Today(), Null(),
    Floor((Today() - birth_date) / 365.25)) AS [Patient.Age]
```

### Common Date Arithmetic Patterns with Guards

```qlik
// Age calculation
IF(IsNull(birth_date), Null(),
    Floor((Today() - birth_date) / 365.25)) AS [Person.Age]

// Days since last order
IF(IsNull(last_order_date), Null(),
    Today() - last_order_date) AS [Customer.DaysSinceLastOrder]

// Date difference between two fields
IF(IsNull(start_date) OR IsNull(end_date), Null(),
    end_date - start_date) AS [Duration.Days]

// Tenure in months
IF(IsNull(hire_date), Null(),
    Floor((Today() - hire_date) / 30.44)) AS [Employee.TenureMonths]
```

### Why This Is Easy to Miss

The calculation runs without error. No reload failure, no warning. The result is a plausible-looking number (125 is a valid age, just wrong). The bug only surfaces when someone notices impossible values in reports, or when aggregations (average age) are skewed by phantom centenarians.

### When to Apply

Any expression that involves:
- Subtraction between dates: `dateA - dateB`
- Division of a date difference: `(dateA - dateB) / N`
- Date functions on potentially-null fields: `Year(date_field)`, `Month(date_field)`

**Rule of thumb:** If a field is used as an operand in date math and it can ever be NULL, wrap the entire expression in an IsNull guard.

---

## Defensive Null Handling Strategy

### Decision Framework

| Field Type | Null Source | Strategy | Example |
|---|---|---|---|
| String dimension from external source | String-encoded nulls ("null", "NaN") | vCleanNull | `$(vCleanNull(region)) AS [Region]` |
| Sparse dimension for filter panes | Genuine SQL NULLs | NullAsValue | `NullAsValue [Customer.Segment]` |
| Date/numeric used in calculations | Any null source | IsNull guard | `IF(IsNull(date), Null(), ...)` |
| Boolean field | NULL = unknown state | Dual with -1 | `$(vDualBool(is_active, Active, Inactive))` |
| Key field | Any null source | **Never mask.** TRACE a warning. | Null key = data quality issue |

### Layered Application

In a typical extraction script, you may use all three strategies on different fields in the same LOAD:

```qlik
SET NullValue = 'No Entry';
NullAsValue [Customer.Region], [Customer.Segment];

[Customers]:
LOAD
    customer_id                                           AS [Customer.Key],
    $(vCleanNull(customer_name))                          AS [Customer.Name],
    region                                                AS [Customer.Region],
    segment                                               AS [Customer.Segment],
    IF(IsNull(birth_date), Null(),
        Floor((Today() - birth_date) / 365.25))           AS [Customer.Age],
    $(vDualBool(is_active, Active, Inactive))             AS [Customer.IsActive]
RESIDENT [_RawCustomers];

NullAsNull *;
SET NullValue =;
```

In this example:
- `customer_id`: No null masking (key field, nulls indicate data issues)
- `customer_name`: vCleanNull (catches "null" strings from upstream)
- `region`, `segment`: NullAsValue (sparse dimensions, need filter pane display)
- `birth_date`: IsNull guard (used in age calculation)
- `is_active`: Dual boolean with Unknown/-1 for NULL
