---
name: qlik-security
description: |
  Section access patterns, row-level security, data reduction, OMIT field usage,
  hybrid security models, and Cloud vs. client-managed security differences. Use when
  designing or reviewing security configurations.
---

# Qlik Security

## Overview

Security in Qlik Sense controls which data users can view. Section Access is the primary mechanism—it filters rows and hides columns at load time, before the user interface loads. Unlike runtime filtering, section access works invisibly: a user with restricted access simply sees a different model. This makes section access powerful but also error-prone; misconfigured access rules often fail silently, appearing to work while exposing or hiding unintended data.

Section access is required for any app with multiple users, PII protection, compliance regulations (GDPR, HIPAA), or data tenancy. The configuration differs significantly between Qlik Cloud and client-managed deployments. Cloud uses email-based identity and OIDC/SAML provisioning. Client-managed uses Windows domain authentication (NTNAME, DOMAIN\Username) with manual user lists.

This skill covers section access table structure, row-level data reduction, field-level visibility control via OMIT, and platform-specific differences. Full working examples are in `section-access-patterns.md`.

---

## 1. Section Access Fundamentals

Section Access is a special Qlik load table that defines user identity and access rules. During reload, Qlik matches the current user against the Section Access table and filters all loaded data accordingly. Section access operates at three levels:

**USER Column (Identity):** The USER column identifies the user. Values are platform-specific: Cloud uses email addresses (user@domain.com), client-managed uses Windows domain format (DOMAIN\Username) or USERID for internal Qlik users. Every user who accesses the app must have a row in Section Access (or match a STAR wildcard row).

**OMIT Column (Field Visibility):** Binary flag: 0 means show all fields, 1 means hide the fields listed in reduction columns. OMIT is field-level security. A user with OMIT=1 for columns `[Customer.SSN]` and `[Employee.Salary]` will not see those columns in any visualization.

**Reduction Fields (Row Filtering):** Other columns in the Section Access table (e.g., `DepartmentID`, `RegionCode`, `CustomerID`) define which rows the user can see in dimension tables. When a user selects a department, they see only products, orders, and customers associated with that department.

The three components work together. A user with OMIT=0 sees all columns; a user with OMIT=1 sees only non-hidden columns. A user with a specific DepartmentID reduction sees only rows matching that department in the Department dimension. Together, they provide both row-level and field-level access control.

---

## 2. Section Access Table Structure

Section Access is loaded last in the script, after all data tables. The structure is rigid: AUTOGENERATE or INLINE format with mandatory columns.

```qlik
[Section Access]:
LOAD * INLINE [
USER, OMIT, DepartmentID, RegionCode
alice@acme.com, 0, DEPT_A, NORTH
bob@acme.com, 1, DEPT_B, SOUTH
charlie@acme.com, 0, DEPT_A, NORTH
*, 0, *, *
] (delimiter is ',');
```

**Required columns:**
- `USER` — Identity of the user (email for Cloud, DOMAIN\Username for client-managed)
- `OMIT` — Binary (0 or 1) field visibility flag
- `Reduction columns` — One column per dimension field you want to reduce. Names must match data model field names exactly, case-sensitive. `DepartmentID` is NOT the same as `departmentid`.

**STAR row:** The final row with `*` values is the default access rule for any user not explicitly listed. STAR provides a sensible default (often OMIT=0 and all reduction fields `*`). For client-managed apps, STAR is required to provide default access; without it, unlisted users see no data. For Cloud, STAR behavior varies; consult help.qlik.com for current behavior.

**Order matters:** The row matching the logged-in user is used. If the same user appears twice (which should not happen), the first match wins. Include STAR as the final row, after all explicit user rows.

---

## 3. Row-Level Security and Data Reduction

Data reduction works by matching the Section Access reduction fields against the data model. When a user logs in, Qlik filters all data to keep only rows matching their access rules.

**Mechanism:** During reload, Qlik creates an internal association between the Section Access table and every dimension table that has a matching field name. When the user selects a value, or when loading completes, Qlik filters the fact table to include only rows whose dimension keys match the user's allowed values.

**Example—Department-based reduction:**
```
Section Access row: alice@acme.com, 0, DEPT_A, ...
Data model: [Department] table with [DepartmentID] field
Result: Alice can see only Department rows where [DepartmentID] = 'DEPT_A'
        All [Order] rows linking to 'DEPT_A' are visible
        All [Order] rows linking to other departments are hidden
```

**Row-level facts only:** Fact tables (Orders, Transactions) load completely and unfiltered. Section Access filters which rows are *visible* based on the dimension associations. Dimension tables filter directly.

**Critical gotcha—case sensitivity:** Reduction field names must match the data model field names exactly, character-for-character. A Section Access table with `DepartmentID` will fail silently (user sees all data) if the model field is named `departmentid`. Qlik does not error; it simply skips the association. This is the #1 silent failure in section access.

---

## 4. Cloud vs. Client-Managed Security Implementation

Qlik Cloud and client-managed deployments use different authentication systems and identity formats.

**Qlik Sense Cloud:**
- Authentication: OAuth/OIDC via identity provider (Azure AD, Okta, Google, etc.)
- User column: Email addresses (user@tenant.onmicrosoft.com, user@company.com)
- STAR behavior: Optional; Qlik Cloud may handle unmatched users differently (consult help.qlik.com v2025+)
- Section Access: Loaded from script embedded in the app
- Field naming: `[User.Email]` or `USER` are common for email columns in Cloud apps
- Multi-tenant: Cloud apps often use tenant identifier in reduction fields (TenantID, CustomerID)

**Client-Managed (On-Premise):**
- Authentication: Windows NTLM or custom header-based (if configured)
- User column: Windows domain format DOMAIN\Username (e.g., ACME\alice) OR numeric USERID for internal Qlik logins
- STAR behavior: Required. Without STAR, users not explicitly listed in Section Access are denied access
- Section Access: Embedded in the reload script, loaded from Qlik repository or cloud storage
- Field naming: NTNAME field for domain\username, USERID field for internal numeric IDs
- Manual provisioning: Users must be added to the Windows domain and to Section Access table (vs. Cloud automatic provisioning)

**Migration impact:** Moving an app from client-managed to Cloud requires rewriting the USER column from DOMAIN\Username to email addresses, and potentially removing or adjusting STAR row behavior.

---

## 5. OMIT Field Usage and Hybrid Security Models

OMIT is the column-hiding mechanism. OMIT=0 means the user sees all fields. OMIT=1 means the user does NOT see fields named in the reduction columns.

**Field-level access pattern:**
```qlik
// Section Access table:
[Section Access]:
LOAD * INLINE [
USER, OMIT, DepartmentID, SSN, Salary
hr_admin@acme.com, 0, *, *, *
department_manager@acme.com, 1, DEPT_A, SSN, Salary
data_analyst@acme.com, 1, *, SSN, *
*, 0, *, *, *
] (delimiter is ',');

// Data model: All tables have [Customer.SSN] and [Employee.Salary] fields
// Result:
// - hr_admin sees all fields in all dimensions
// - department_manager sees Department=DEPT_A only, and cannot see [SSN] or [Salary] columns
// - data_analyst can see all departments (*), cannot see [SSN], can see [Salary]
// - Everyone else (STAR): sees all fields, all rows
```

**Hybrid pattern (row + column filtering):** Combine OMIT with reduction fields. A regional manager sees only their region's products and customers (row filter via RegionCode), and also cannot see salary columns (column filter via OMIT=1 + Salary column). This is powerful for compliance: compliance officers see all data, regional staff see only their region without seeing sensitive columns.

**Initialization:** Always initialize OMIT in every Section Access row, including STAR. OMIT is persistent across all visible fields for that user. If one row has OMIT=1 and another has OMIT=0, the engine applies the OMIT setting based on the matched row.

---

## 6. Anti-Patterns and Common Pitfalls

**Case-sensitivity errors:** Section Access reduction field names must match data model field names exactly. `DepartmentID` vs. `departmentid` causes silent failure—Qlik skips the association, and the user sees all data. Use the same casing everywhere.

**Missing STAR row (client-managed only):** Client-managed apps without a STAR row deny access to all users not explicitly listed. Every user needs an entry or must match STAR. Always include STAR as the final row with sensible defaults.

**Wrong identity field:** Using USERID in a Cloud app should use email instead. Using email in client-managed should use NTNAME (DOMAIN\Username). Identity field mismatch causes users to fail section access matching.

**PII in reduction fields:** If you use [Customer.SSN] as a reduction field (e.g., to filter orders by SSN), the SSN appears as a value in the Section Access table. Section Access tables are often stored in plaintext QVD files. If someone gains access to the QVD, they see all PII. Solution: Never use PII as a reduction field. Instead, use a derived key (a mapping from SSN to a numeric customer ID, stored separately) and reduce on the derived key.

**OMIT without documentation:** Hiding columns via OMIT without recording which users can't see them creates confusion during support ("Why don't I see the salary column?"). Document which users have OMIT=1 and which columns they cannot see.

**Untested section access:** Always test section access with a dummy user account before deploying. Create a test user, reload the app with that user logged in, and verify the data is filtered as expected. Silent failures are common if testing is skipped.

**Misaligned reduction field names:** Section Access has a column named `DeptID`, but the data model has a field named `DepartmentID`. Qlik silently skips the association because the names don't match. Double-check field names in both the Section Access table and the data model.

---

## Supporting Files

For complete, runnable Section Access examples covering single-tenant, multi-tenant, role-based, and hybrid Cloud/client-managed patterns, see `section-access-patterns.md` in this skill directory.
