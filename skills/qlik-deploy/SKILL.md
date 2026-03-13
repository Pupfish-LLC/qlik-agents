---
name: qlik-deploy
description: Deployment procedures for Qlik Sense Cloud and client-managed environments. Covers app import, data connection setup, task scheduling, security configuration, environment promotion (dev/test/prod), QVD storage setup, and post-deployment validation. Invoke manually with /qlik-deploy when preparing deployment artifacts or writing operational runbooks.
---

## Overview

This skill covers everything required to move a validated Qlik app from development to production (Cloud or client-managed). It does NOT cover data modeling (qlik-data-modeling), script development (qlik-load-script), or security patterns (qlik-security). Why deployment matters: environments differ fundamentally in infrastructure, identity mechanisms, and operational procedures. Qlik Sense Cloud uses OIDC/SAML with email-based identities and cloud storage. Client-managed uses Windows/LDAP authentication and on-premise file servers. This skill bridges those differences with platform-specific procedures.

---

## Section 1: Pre-Deployment Checklist

Verify before deploying any app:

- **Execution validation gates passed** — Confirm Phase 4 (Scripts) and Phase 5 (Expressions) validation gates completed successfully with developer sign-off, OR documented as "execution validation pending" with tracking
- **QA review complete** — Phase 7 comprehensive QA completed. All Critical findings resolved. Document any Known Limitations or deferred items.
- **Section Access tested** — If app uses row-level security, test with at least one non-admin user against target identity provider (Cloud: test OIDC/SAML email user; client-managed: test domain\username user)
- **Environment-specific variables identified** — List all variables that change between dev/test/prod: connection strings, QVD paths, identity provider URLs, folder locations. Document where each is set (script, data connection, task scheduler)
- **QVD storage locations confirmed** — Target environment has writable directory/cloud storage paths for QVD output. Verify folder permissions and cloud IAM policies
- **Data connections validated** — Test each connection in target environment: verify credentials, network access (firewall rules for on-premise sources), cloud data gateway status (if applicable)
- **Backup plan documented** — Previous app version accessible (QMC app history or storage backup), data snapshot procedure defined, rollback step documented

---

## Section 2: Qlik Sense Cloud Deployment

### Space Setup

- **Create shared space** for collaborative development (all collaborators can edit, monitor task runs)
  - Admin > Spaces > New space > Select "Shared space"
  - Configure member access (who can edit, who can consume)
- **Create managed space** for production/governed content (restricted editing, full governance)
  - Admin > Spaces > New space > Select "Managed space"
  - Assign space owner and data stewards
  - Managed spaces support scheduled reload and enterprise security policies

### App Import

- **Upload via UI** (simple for single apps)
  - Export .qvf from source environment
  - Navigate to target space, click "Upload app" or drag .qvf to upload area
  - Qlik extracts embedded data connections and exposes them for reconfiguration
- **Import via REST API** (automated, preferred for CI/CD)
  - POST `/api/v1/apps` with .qvf file upload
  - Specify `spaceId` in request body
  - Response includes `appId` for downstream reference

### Data Connection Setup

- **Cloud-native connections** (data in Azure, AWS, Google Cloud)
  - Admin > Data connections > New connection
  - Select cloud provider (Azure Data Lake, Amazon S3, Google BigQuery)
  - Configure credentials (SAS token, IAM role, API key)
  - Test connection before using in app
- **On-premise data access** (databases, file shares in corporate network)
  - Deploy Cloud data gateway in target network (download from help.qlik.com)
  - Register gateway with Qlik Cloud tenant
  - Create data connection in Qlik Cloud pointing to gateway
  - Verify network connectivity: gateway must reach source system and reach Qlik Cloud
  - Common gotcha: firewall rules blocking gateway ↔ data source or gateway ↔ Qlik Cloud traffic
- **Generic REST connector**
  - Use for SaaS APIs, webhooks, custom endpoints
  - Test endpoint accessibility from Qlik Cloud infrastructure

### Reload Scheduling

- **Create reload task** (built-in Cloud task scheduler)
  - Navigate to app > Reload task
  - Set trigger: immediate, scheduled (cron pattern), or webhook
  - Configure failure notification (email to operations team, webhook to monitoring system)
  - Test first reload manually to verify no errors
  - Common pattern: reload nightly, alert on failure
- **Monitor reload health**
  - App > Activity > Reloads
  - Check last reload status, duration, error logs
  - Set up monitoring alert if reload fails or exceeds threshold duration

### Security Configuration

- **Configure identity provider** (done once at tenant level, applies to all apps)
  - Admin > Identity providers > Configure OIDC or SAML
  - Map external identity provider (Okta, Azure AD, etc.) to Qlik Cloud
  - Users authenticate via single sign-on (SSO)
  - Verify email attribute maps correctly (used in Section Access USER column)
- **Section Access identity mapping**
  - In script, use email address in USER column: `USER, DepartmentID from [UserSecurityTable.qvf]` where USER contains `email@company.com`
  - Qlik Cloud matches logged-in user email to Section Access USER entries
  - Verify with test user: log in, check what data is visible (should match assigned department)
- **Space-level access control**
  - Additional layer: even if Section Access grants access to data, user must have space permission to see app
  - Assign space members individually or via LDAP group sync

### Content Distribution

- **Publish app** to make discoverable
  - App > Publish (makes app appear in app library for assigned users)
  - Share link with users (email, intranet, analytics portal)
- **Master items** (reusable dimensions, measures, filters)
  - Create once in Qlik Cloud app
  - Reference in multiple sheets (changes apply automatically)

---

## Section 3: Qlik Sense Client-Managed Deployment

### Stream and Security Rule Setup (QMC)

- **Create stream** (container for apps, enforces access policy)
  - QMC > Streams > New stream
  - Stream = logical grouping (Production, Staging) or business area (Sales, Finance)
  - Note stream GUID for app assignment
- **Create security rule** (QMC > Security rules)
  - Define who can access which streams
  - Example: `resource.stream.id = "xxx" and user.name = "DOMAIN\*"`
  - Apply rule to apps in stream

### App Import

- **Via QMC**
  - QMC > Apps > Import app
  - Upload .qvf from development
  - Select target stream
  - Specify publishing on/off (make immediately available to users)
- **Via REST API** (automated)
  - POST `/qrs/app/upload` with .qvf content
  - Include stream ID in request
  - Response includes app GUID

### Data Connection Setup (QMC)

- **Folder connection** (for QVD access, file shares)
  - QMC > Data connections > New
  - Type: Folder connection
  - Path: UNC path (`\\server\share\qvd`) or local path
  - Credentials: Windows account (NTLM) or custom credentials
  - Test: "Test connection" button verifies folder accessibility
- **Database connection** (SQL Server, Oracle, Teradata)
  - QMC > Data connections > New
  - Type: database-specific (ODBC, native driver)
  - Credentials: database user + password, or Windows auth (single sign-on)
  - Connection string example: `DRIVER={SQL Server};SERVER=dbhost;DATABASE=mydb;`
  - Test connection before using in app
- **Custom connector** (API, specialized sources)
  - Configure in QMC if vendor provides connector
  - Or use generic REST connector with API credentials

### Task Scheduling (QMC)

- **Create task** (reload automation)
  - QMC > Tasks > New task
  - Type: Reload (app refresh) or external program
  - Select app to reload
  - Set trigger: immediate, scheduled (cron), or on-success-of-another-task
  - Example: App-A loads at 6am, App-B triggers on App-A success at 6:30am
- **Task chain** (dependency management)
  - Task A: Reload core data app (6:00 AM)
  - Task B: Reload reporting app (trigger: on success of Task A, 6:30 AM)
  - Task C: Send completion email (trigger: on success of Task B)
  - Prevents cascading failures (Task B doesn't run if Task A fails)
- **Failure handling**
  - Configure alert (email, webhook) if task fails
  - Set retry policy (retry N times before alert)
  - Manually retry task from QMC if needed

### Security Configuration

- **Identity provider setup** (QMC > Identity providers)
  - **Windows (NTLM/Kerberos)** — Automatic for domain-joined servers
  - **LDAP** — Configure LDAP server address, bind credentials, user attribute mapping
  - **SAML** — Configure identity provider metadata
  - Result: Users authenticate once; Qlik Sense recognizes user identity
- **Section Access identity mapping**
  - Use NTNAME field for domain\username: `NTNAME, DepartmentID from [SecurityTable.qvf]` where NTNAME = `DOMAIN\AliceSmith`
  - Or use USERID field for internal numeric ID (less common)
  - Qlik Sense matches logged-in user identity to Section Access entries
  - Test with sample domain user
- **Custom security rules**
  - Fine-grained access beyond Section Access
  - QMC > Security rules > New rule
  - Rule pattern: `resource.app.name = "Production*" and user.group = "DOMAIN\Analysts"`

### Multi-Node Architecture (if applicable)

- **Central node** (master) — Hosts QMC, task scheduler, shared license. Only node that can write to file system.
- **Rim nodes** (workers) — Reload engines only (no QMC). Configured in QMC to share reload load.
- **Engine distribution** — Configure via QMC which engines handle reload tasks. Reduces central node bottleneck.

---

## Section 4: Environment Promotion (dev → test → prod)

### What Changes Between Environments

| Aspect | Dev | Prod |
|--------|-----|------|
| **DB Connection** | `SERVER=db-dev.corp.com` | `SERVER=db-prod.corp.com` |
| **QVD Path** | `\\fileserver-dev\qvd\` | `\\fileserver-prod\qvd\` |
| **Section Access Source** | Test user list | Production LDAP or IdP |
| **Data Connection Credentials** | Dev service account | Prod service account |
| **Task Schedule** | On-demand | Hourly |
| **Monitoring** | Warnings only | Alerts + escalation |

Do NOT hardcode these values in scripts. Externalize to variables.

### Variable Externalization Strategy

- **Create environment variables file** (.qvs for each environment):

```qlik
// Environment variables (included in main script)
LET vDbHost = 'db-prod.corp.com';
LET vDbPort = '1433';
LET vQvdPath = '\\fileserver-prod\qvd\';
LET vSecAccessSource = 'SecurityTable_Prod';
LET vReloadTime = '23:00';
```

- **Store in QMC** (client-managed) or Qlik Cloud variable editor (Cloud)
  - Define variables once, reference in multiple load scripts
  - Central management: change variable value in one place, applies to all app reloads
- **Load via `$(vVariableName)` syntax** in script:
  ```qlik
  LOAD * FROM $(vQvdPath)sales.qvd;
  ```
- **Override at deploy time**
  - Before importing app, set environment variables in target environment
  - Import app; variables are already configured for that environment

### Promotion Workflow

1. **Export from dev** — Publish app as .qvf (includes all objects, data model, scripts)
2. **Import to test** — Upload .qvf to test environment, reconfigure data connections (point to test database)
3. **Validate in test** — Full test suite: reload, row count verification, Section Access testing with test users
4. **Promote to prod** — Export from test (or dev), import to prod
5. **Post-prod validation** — First reload, data freshness check, test with subset of production users

### Configuration Management

- **Version control** (Git) — Store main script files, variable definitions, naming conventions
  - Do NOT version control: environment-specific connection strings, credentials, QMC task IDs
- **Deployment checklist** — Document what changed between environments (connection strings? Section Access source? Task schedule?)
- **Rollback plan** — Keep previous app version accessible (QMC app history or backup)

---

## Section 5: QVD Storage Setup

### Folder Structure

```
/qvd/
  /raw/              # Source data extracts (unchanged from source)
    /sales.qvd
    /customers.qvd
  /transform/        # Intermediate tables (after business logic)
    /sales_enhanced.qvd
    /customer_segments.qvd
  /model/            # Final dimensions and facts (ready for consumption)
    /dim_customer.qvd
    /fact_sales.qvd
    /fact_inventory.qvd
  /archive/          # Historical QVDs (retain for recovery, backup)
```

### Permissions and Access Control

- **Read access** (for load scripts) — All users/service accounts running Qlik reload
- **Write access** (for QVD output) — Only Qlik reload engine service account
- **Archive access** — Backup/IT team only (for disaster recovery)
- **Cloud-specific** — Use cloud storage permissions (Azure blob ACL, S3 IAM policy)

### Retention and Cleanup

- **Keep latest QVD** always (allows rollback to previous load)
- **Archive previous 7 days** (recover from logic errors discovered mid-week)
- **Monthly snapshots** (audit trail, historical analysis)
- **Automated cleanup** — Delete files older than 30 days via OS task scheduler or cloud lifecycle policies

---

## Section 6: Post-Deployment Validation

### First Reload Verification

- **Manual reload** — Run reload task, watch for errors
  - Check reload log: no ERROR or FATAL messages
  - Check TRACE output (if qvf includes TRACE statements) for data quality warnings
- **Row count verification** — Compare row counts in target vs. source (should match within expected margin)
- **Field type consistency** — Verify numerics loaded as numbers (not text), dates as dates

### Data Freshness and Accuracy

- **Spot-check totals** — Select 2-3 key metrics, verify against source system (example: "Total revenue should be $X million")
- **Synthetic key check** (client-managed) — Data model viewer should show NO red-highlighted synthetic keys
- **NULL handling** — Verify expected NULLs appear (no spurious NULLs hiding bugs)

### Security Validation

- **Test with restricted user** — Log in as non-admin user, verify data reduction works (user assigned to Department A should NOT see Department B data)
- **Test with admin user** — Verify admins see complete data (no unintended filtering)

### Performance Baseline

- **Reload duration** — Record baseline (15 min? 2 hours?). Alert if reload duration increases >20%
- **Memory usage** — Check peak memory during reload. Allocate Qlik engine accordingly.
- **Disk space** — Monitor QVD storage growth. Implement cleanup policy if growth exceeds threshold.

### Monitoring Setup

- **Reload alerts** — Configure alert (email, Slack, monitoring tool) if reload fails or duration exceeds threshold
- **Data freshness** — Daily check that reload ran successfully and data is current
- **User access logs** — Monitor failed logins (indicator of Section Access misconfiguration)
- **Dashboard notifications** — Notify users of any scheduled downtime or data refresh delays
