# Section Access Patterns

Detailed runnable examples for section access in different scenarios. Each pattern includes the Section Access table code, the data model structure, expected behavior, and common errors.

---

## Pattern 1: Single-Tenant Department-Based Reduction (Client-Managed)

**Scenario:**
A manufacturing company has multiple departments. Each department manager should see only their department's products, orders, and customers. They should see all columns (no OMIT). This is a client-managed deployment using Windows authentication.

**Section Access Table:**
```qlik
[Section Access]:
LOAD * INLINE [
USER, OMIT, DepartmentID
MANUFACTURING\alice_johnson, 0, DEPT_001
MANUFACTURING\bob_smith, 0, DEPT_002
MANUFACTURING\carol_white, 0, DEPT_003
MANUFACTURING\admin_system, 0, *
*, 0, *
] (delimiter is ',');
```

**Data Model Structure (relevant fields):**
```qlik
[Dimension.Department]:
LOAD department_id AS [DepartmentID],
     department_name AS [Department.Name],
     location AS [Department.Location]
FROM [departments.qvd] (qvd);

[Dimension.Product]:
LOAD product_id AS [Product.Key],
     product_name AS [Product.Name],
     department_id AS [DepartmentID],  // This field joins to Section Access
     category AS [Product.Category]
FROM [products.qvd] (qvd);

[Fact.Orders]:
LOAD order_id AS [Order.Key],
     product_id AS [Product.Key],
     customer_id AS [Customer.Key],
     department_id AS [DepartmentID],  // This field joins to Section Access
     quantity AS [Order.Quantity],
     amount AS [Order.Amount]
FROM [orders.qvd] (qvd);
```

**Expected Behavior:**
- When alice_johnson logs in, the app loads with [DepartmentID] = 'DEPT_001'. Only products and orders from DEPT_001 are visible. Other departments appear missing from the dimension list.
- bob_smith sees only DEPT_002 data
- carol_white sees only DEPT_003 data
- admin_system and any user in the STAR row see all departments (OMIT=0, DepartmentID=*)
- All visible columns appear in the model (no OMIT=1 hiding)

**Common Errors:**

1. **Wrong case in field name:**
   ```qlik
   // WRONG: Section Access has 'departmentid' but model has [DepartmentID]
   [Section Access]:
   LOAD * INLINE [
   USER, OMIT, departmentid   // lowercase!
   MANUFACTURING\alice, 0, DEPT_001
   ...
   ];
   // Result: Qlik silently skips the association. alice sees all departments.
   ```
   **Fix:** Match case exactly: `DepartmentID` in both Section Access and data model.

2. **Missing STAR row:**
   ```qlik
   // WRONG: No STAR row
   [Section Access]:
   LOAD * INLINE [
   USER, OMIT, DepartmentID
   MANUFACTURING\alice, 0, DEPT_001
   MANUFACTURING\bob, 0, DEPT_002
   ];
   // Result: Users not listed (admin, test accounts) are denied access to all data
   ```
   **Fix:** Always include a STAR row as the final entry.

3. **OMIT column missing:**
   ```qlik
   // WRONG: Forgot OMIT column
   [Section Access]:
   LOAD * INLINE [
   USER, DepartmentID
   MANUFACTURING\alice, DEPT_001
   ...
   ];
   // Result: Qlik error during reload about missing required column
   ```
   **Fix:** Always include OMIT column (even if all users have OMIT=0).

---

## Pattern 2: Multi-Tenant Email-Based Reduction (Qlik Cloud)

**Scenario:**
A SaaS product serves multiple customers (tenants). Each tenant's data is isolated by a TenantID. Users log in via Azure AD with their email address. No OMIT (all users see all columns). This is a Qlik Cloud deployment.

**Section Access Table:**
```qlik
[Section Access]:
LOAD * INLINE [
USER, OMIT, TenantID
alice@acme.com, 0, TENANT_ACME
bob@acme.com, 0, TENANT_ACME
carol@globex.com, 0, TENANT_GLOBEX
diana@globex.com, 0, TENANT_GLOBEX
support@platform.com, 0, *
*, 1, NONE
] (delimiter is ',');
```

**Data Model Structure (relevant fields):**
```qlik
[Dimension.Tenant]:
LOAD tenant_id AS [TenantID],
     tenant_name AS [Tenant.Name],
     subscription_tier AS [Tenant.Tier]
FROM [tenants.qvd] (qvd);

[Dimension.Customer]:
LOAD customer_id AS [Customer.Key],
     customer_name AS [Customer.Name],
     tenant_id AS [TenantID],  // This field joins to Section Access
     email AS [Customer.Email]
FROM [customers.qvd] (qvd);

[Fact.Subscriptions]:
LOAD subscription_id AS [Subscription.Key],
     customer_id AS [Customer.Key],
     tenant_id AS [TenantID],  // This field joins to Section Access
     start_date AS [Subscription.StartDate],
     mrr AS [Subscription.MRR]
FROM [subscriptions.qvd] (qvd);
```

**Expected Behavior:**
- alice@acme.com and bob@acme.com see only TENANT_ACME data (customers, subscriptions, usage)
- carol@globex.com and diana@globex.com see only TENANT_GLOBEX data (completely isolated)
- support@platform.com sees all tenant data (support team with TenantID=*)
- Any user not listed in the table matches the STAR row with OMIT=1 and TenantID=NONE. They can see no data because:
  - OMIT=1 means hide all columns (reduction fields [TenantID] is a reduction field, not a visible column)
  - TenantID=NONE doesn't match any real tenant in the data
  - Result: User sees an empty model

**Common Errors:**

1. **Missing OMIT=1 in STAR row (Cloud-specific):**
   ```qlik
   // WRONG: STAR row with OMIT=0
   [Section Access]:
   LOAD * INLINE [
   USER, OMIT, TenantID
   alice@acme.com, 0, TENANT_ACME
   ...
   *, 0, *   // WRONG: OMIT=0 allows unregistered users to see all data!
   ];
   // Result: Any user not explicitly listed (test accounts, random email) can see all tenant data
   ```
   **Fix:** Use OMIT=1 and a non-existent TenantID (e.g., 'NONE') in the STAR row to deny access to unregistered users.

2. **Email format mismatch:**
   ```qlik
   // WRONG: Domain case or format doesn't match Azure AD
   [Section Access]:
   LOAD * INLINE [
   USER, OMIT, TenantID
   Alice@acme.com, 0, TENANT_ACME   // capitalized; Azure AD sends 'alice@acme.com'
   ];
   // Result: alice@acme.com logs in but doesn't match Alice@acme.com in Section Access
   ```
   **Fix:** Match email format exactly. Azure AD typically lowercases; verify in your identity provider settings.

3. **TenantID field in model but not in Section Access:**
   ```qlik
   // WRONG: Data model has [TenantID] but Section Access doesn't
   [Section Access]:
   LOAD * INLINE [
   USER, OMIT, DepartmentID   // No TenantID column!
   alice@acme.com, 0, DEPT_A
   ];
   // Dimension.Customer has [TenantID] field
   // Result: [TenantID] is loaded but not filtered by Section Access
   //         Users can potentially query the data via selection
   ```
   **Fix:** Every reduction field in the data model must be in the Section Access table.

---

## Pattern 3: Role-Based with Field OMIT (Hybrid)

**Scenario:**
A healthcare SaaS has three user roles: (1) Clinician - sees patient data, no sensitive audit fields; (2) Billing Admin - sees billing data only, sees SSN and account fields; (3) Compliance Officer - sees all data including audit. This is a Qlik Cloud app using role-based reduction and OMIT for column hiding.

**Section Access Table:**
```qlik
[Section Access]:
LOAD * INLINE [
USER, OMIT, ClinicID, AuditLog, PatientData, BillingData
clinician@clinic1.org, 1, CLINIC_001, AuditLog, , BillingData
billing@clinic1.org, 1, CLINIC_001, AuditLog, PatientData,
compliance@clinic1.org, 0, *, , ,
*, 1, NONE, AuditLog, PatientData, BillingData
] (delimiter is ',');
```

**Explanation of OMIT columns:**
- `AuditLog` column name: If OMIT=1, this column is hidden
- `PatientData` column name: If OMIT=1, this column is hidden (e.g., [Patient.SSN], [Patient.MedicalHistory])
- `BillingData` column name: If OMIT=1, this column is hidden

**Data Model (relevant fields):**
```qlik
[Dimension.Patient]:
LOAD patient_id AS [Patient.Key],
     patient_name AS [Patient.Name],
     ssn AS [PatientData],  // This field name matches the OMIT column name
     clinic_id AS [ClinicID],
     admission_date AS [Patient.AdmissionDate]
FROM [patients.qvd] (qvd);

[Dimension.Account]:
LOAD account_id AS [Account.Key],
     account_balance AS [BillingData],  // Matches OMIT column
     clinic_id AS [ClinicID]
FROM [accounts.qvd] (qvd);

[Fact.PatientVisit]:
LOAD visit_id AS [Visit.Key],
     patient_id AS [Patient.Key],
     visit_date AS [Visit.Date],
     clinic_id AS [ClinicID],
     visit_type AS [Visit.Type],
     modified_by AS [AuditLog],  // Matches OMIT column
     modified_timestamp AS [AuditLog]  // Also hidden if OMIT=1
FROM [visits.qvd] (qvd);
```

**Expected Behavior:**
- `clinician@clinic1.org`:
  - Sees ClinicID = CLINIC_001 only (row filter)
  - OMIT=1 with columns [AuditLog], [BillingData] hidden
  - Result: Sees patient data, visit types, admission dates, but NOT SSN, NOT modified_by/modified_timestamp, NOT account balances

- `billing@clinic1.org`:
  - Sees ClinicID = CLINIC_001 only (row filter)
  - OMIT=1 with columns [AuditLog], [PatientData] hidden
  - Result: Sees account balances, but NOT SSN, NOT audit log, NOT patient data details

- `compliance@clinic1.org`:
  - Sees all ClinicID values (*)
  - OMIT=0: no columns hidden
  - Result: Sees all data

- Unmatched users (STAR row):
  - OMIT=1 with all columns hidden
  - ClinicID=NONE (no matching clinic)
  - Result: Empty model, no data visible

**Common Errors:**

1. **Forgetting to use field names in model:**
   ```qlik
   // WRONG: Field in model is [Patient.SSN], but Section Access column is [SSN] or [PatientData]
   // (mismatch between what you're hiding and what exists)

   // Model:
   LOAD ssn AS [Patient.SSN] FROM [...];

   // Section Access:
   LOAD * INLINE [
   USER, OMIT, PatientData   // Column named 'PatientData'
   clinician, 1, CLINIC_001, PatientData
   ];
   // Result: [Patient.SSN] field exists but 'PatientData' column doesn't match
   //         Qlik skips OMIT hiding because field name doesn't match
   ```
   **Fix:** The OMIT column names must match actual field names in the data model. Use the exact field name.

2. **OMIT on key fields (breaks associations):**
   ```qlik
   // WRONG: Hiding a key field via OMIT
   [Section Access]:
   LOAD * INLINE [
   USER, OMIT, ClinicID
   clinician, 1, CLINIC_001, PatientKey   // Hiding [PatientKey]
   ];
   // Result: Associations between fact and dimension tables break
   //         Users see no data because the joining key is hidden
   ```
   **Fix:** Never use OMIT to hide key fields. OMIT is for non-key attributes (SSN, salary, audit columns).

---

## Pattern 4: Hybrid Cloud/Client-Managed Comparison

**Scenario:**
Demonstrating the same logical security model in both Cloud and client-managed deployments. A company with 50 regional sales managers. Each manager sees only their region's sales data, and all managers see all columns.

### Cloud Version (Qlik Sense Cloud + Azure AD):

```qlik
[Section Access]:
LOAD * INLINE [
USER, OMIT, RegionCode
alice.johnson@acmesales.com, 0, NORTH
bob.smith@acmesales.com, 0, SOUTH
carol.white@acmesales.com, 0, EAST
diana.patel@acmesales.com, 0, WEST
support@acmesales.com, 0, *
*, 1, NONEXISTENT
] (delimiter is ',');
```

**Key Cloud characteristics:**
- User is email address (alice.johnson@acmesales.com)
- STAR row has OMIT=1 to deny unregistered users
- RegionCode=* for support team means all regions
- No NTNAME or USERID needed

### Client-Managed Version (Qlik Sense on-premise + Windows Auth):

```qlik
[Section Access]:
LOAD * INLINE [
USER, OMIT, RegionCode
ACMESALES\alice.johnson, 0, NORTH
ACMESALES\bob.smith, 0, SOUTH
ACMESALES\carol.white, 0, EAST
ACMESALES\diana.patel, 0, WEST
ACMESALES\support, 0, *
*, 0, *
] (delimiter is ',');
```

**Key client-managed characteristics:**
- User is DOMAIN\Username format (ACMESALES\alice.johnson)
- STAR row has OMIT=0 and RegionCode=* to provide default access to all departments for unmatched users
- Manual Windows domain administration required
- No OMIT=1 in STAR (everyone gets basic access unless explicitly restricted)

**Data Model (identical in both):**
```qlik
[Dimension.Region]:
LOAD region_id AS [Region.Key],
     region_code AS [RegionCode],  // Critical: matches Section Access column name
     region_name AS [Region.Name]
FROM [regions.qvd] (qvd);

[Dimension.SalesRep]:
LOAD rep_id AS [SalesRep.Key],
     rep_name AS [SalesRep.Name],
     region_code AS [RegionCode],  // Critical: this field joins to Section Access
     email AS [SalesRep.Email]
FROM [sales_reps.qvd] (qvd);

[Fact.Sales]:
LOAD sale_id AS [Sale.Key],
     rep_id AS [SalesRep.Key],
     region_code AS [RegionCode],  // Critical: filters by user's allowed regions
     sale_date AS [Sale.Date],
     amount AS [Sale.Amount]
FROM [sales.qvd] (qvd);
```

**Migration Path from Client-Managed to Cloud:**
1. Extract all ACMESALES\username values from client-managed Section Access
2. Map each to corresponding email from Azure AD directory (e.g., ACMESALES\alice.johnson → alice.johnson@acmesales.com)
3. Replace USER column with email addresses
4. Change STAR row from `*, 0, *` to `*, 1, NONEXISTENT` (deny unregistered users in Cloud)
5. Test with a test user in both environments before go-live

**Testing Steps (both platforms):**
1. Create a test user account (e.g., ACMESALES\testuser or test@acmesales.com)
2. Add test user to Section Access with RegionCode=EAST
3. Reload the app
4. Log in as test user
5. Verify: Only EAST region data is visible
6. Remove test user from Section Access
7. Log in as test user again (should match STAR row in client-managed, or get OMIT=1 in Cloud)
8. Verify: Appropriate default access applies

---

## Validation Checklist (QA Reviewer)

When reviewing a Section Access implementation, use this checklist:

- [ ] Section Access table is loaded LAST in the script (after all data tables)
- [ ] USER column values match the deployment platform (email for Cloud, DOMAIN\Username for client-managed)
- [ ] OMIT column present in all rows
- [ ] Every reduction field name matches a data model field name exactly (case-sensitive)
- [ ] STAR row present (required for client-managed, strongly recommended for Cloud)
- [ ] STAR row uses sensible defaults (OMIT=0 and * wildcards for client-managed; OMIT=1 and non-existent value for Cloud)
- [ ] No PII values in reduction fields (no SSN, password, salary as a reduction value)
- [ ] If OMIT=1 is used, the hidden column names match actual field names in the model
- [ ] OMIT never hides key fields (would break associations)
- [ ] Reduction fields are NOT aliased or suffixed in the data model (must match exactly)
- [ ] Section Access table uses INLINE or AUTOGENERATE format (not QVD)
- [ ] Test with a restricted user account to verify data is actually filtered (not just trusting config)

---

## Debugging Section Access Issues

**Problem: User sees all data (no filtering)**
- Check: Section Access field name case (DepartmentID vs departmentid)
- Check: STAR row is not matching when it should be
- Check: Reduction field exists in Section Access but not in data model with matching case
- Test: Reload with TRACE statements showing field names being loaded

**Problem: User sees no data**
- Check: User row doesn't exist in Section Access AND STAR row has OMIT=1 (Cloud) or overly restrictive values
- Check: STAR row has wrong RegionCode (e.g., 'NONEXISTENT' instead of '*')
- Check: OMIT=1 is hiding all columns (should only hide specific fields, not all)

**Problem: OMIT is not hiding expected columns**
- Check: Column names in Section Access exactly match field names in model
- Check: OMIT=1 is set in the user's row (not OMIT=0)
- Check: Hidden columns are not key fields (key fields cannot be hidden)

---

## Performance Notes

Section Access filtering happens during load, not at query time. This is efficient—data is filtered once per reload, not per user query. However:
- Very large Section Access tables (10,000+ rows) can slow reload slightly
- Reduction fields with high cardinality (product IDs, customer IDs) filter more effectively than low-cardinality fields (e.g., 3 regions)
- Use numeric keys for reduction fields (integer DepartmentID) rather than string keys (string DeptName) for better performance
