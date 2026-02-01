# Lake Formation: “Turned Off” for PGx Use Case

For this project we want **Lake Formation effectively turned off**: access to the Glue Data Catalog and S3 data is controlled only by **IAM**, not by Lake Formation fine-grained permissions. Glue crawlers, Athena, and IAM-authorized users/roles should work without Lake Formation `AccessDeniedException`.

This folder documents how we achieve that and the lessons learned.

---

## What “Lake Formation Turned Off” Means

- **New** databases and tables: created with **IAM-only** defaults so any IAM principal allowed by IAM policies can use them.
- **Existing** databases (e.g. `pgxdatalake`): either granted to **IAM_ALLOWED_PRINCIPALS** or explicitly granted to the Glue crawler role so crawlers and other services do not hit Lake Formation permission errors.
- We do **not** use Lake Formation for row/column-level security or data filtering in this project; IAM + Glue is sufficient.

---

## Lessons Learned

1. **Default settings apply only to new resources**  
   Setting Lake Formation “Use only IAM access control” (PutDataLakeSettings with `CreateDatabaseDefaultPermissions` / `CreateTableDefaultPermissions` granting `ALL` to `IAM_ALLOWED_PRINCIPALS`) affects only **new** databases and tables. Databases created **before** that change still have the old Lake Formation model and can block Glue crawlers.

2. **Glue crawlers run as a service role**  
   Crawlers use an IAM role (e.g. `AWSGlueServiceRole-pgx-data-model`). That role must have **Lake Formation** permissions on the database when Lake Formation is enforced on that database. IAM permissions on Glue/S3 alone are not enough if the database is under Lake Formation.

3. **Error message is explicit**  
   When the crawler lacks Lake Formation permission, Glue returns:  
   `Insufficient Lake Formation permission(s) on pgxdatalake (Database name: pgxdatalake); AccessDeniedException`.  
   Fix: grant the **crawler role** (or IAM_ALLOWED_PRINCIPALS) on that database in Lake Formation.

4. **Two steps for a full fix**  
   - **Step 1:** Set data lake defaults to IAM-only (PutDataLakeSettings) so **new** resources use IAM-only.  
   - **Step 2:** Grant the Glue crawler role (or IAM_ALLOWED_PRINCIPALS) on **existing** databases (e.g. `pgxdatalake`) via Lake Formation GrantPermissions.

5. **Database-level permissions for crawlers**  
   For a crawler to create/update tables in a database, the role needs at least: `DESCRIBE`, `ALTER`, `CREATE_TABLE`, `DROP` on that database in Lake Formation.

---

## Best Practices (IAM-Only / “Lake Formation Off” Use Case)

| Practice | Why |
|----------|-----|
| **Set IAM-only defaults once per account/region** | New databases and tables then inherit IAM-only behavior; no Lake Formation blocks for new resources. |
| **Grant crawler role on existing databases** | Databases created before the default change still enforce Lake Formation; explicit grant on the database avoids crawler AccessDeniedException. |
| **Use one Glue crawler role per project or data lake** | Simplifies grants: one role to grant on `pgxdatalake` (and any other existing DBs). |
| **Document the role ARN** | Scripts and runbooks should reference the same role (e.g. `AWSGlueServiceRole-pgx-data-model`) for grants and troubleshooting. |
| **Test crawler after any LF or IAM change** | Run a crawler and check LastCrawl Status/ErrorMessage to confirm permissions. |
| **Keep DataLakeAdmins when changing settings** | When calling PutDataLakeSettings, always include existing DataLakeAdmins so you don’t lock out admins. |

---

## How We Apply This (PGx)

1. **Set Lake Formation defaults to IAM-only** (once):  
   From repo root:  
   `python aws-pgx-setup/lake_formation/lakeformation_set_iam_only_defaults.py --credentials-dir /mnt/c/Projects`  
   (Uses PutDataLakeSettings with IAM_ALLOWED_PRINCIPALS and preserves DataLakeAdmins.)

2. **Grant the Glue crawler role on the database(s)** (once per DB):  
   - **Explicit pharmacy databases:** `python aws-pgx-setup/lake_formation/lakeformation_grant_crawler_on_database.py --credentials-dir /mnt/c/Projects --all-pharmacy-databases`  
     Grants on **bronze_pharmacy**, **silver_pharmacy**, **gold_pharmacy**.  
   - **Explicit medical databases:** `python aws-pgx-setup/lake_formation/lakeformation_grant_crawler_on_database.py --credentials-dir /mnt/c/Projects --all-medical-databases`  
     Grants on **bronze_medical**, **silver_medical**, **gold_medical**.  
   - **Single database:** `python aws-pgx-setup/lake_formation/lakeformation_grant_crawler_on_database.py --credentials-dir /mnt/c/Projects --database pgxdatalake`  
   Grants DESCRIBE, ALTER, CREATE_TABLE, DROP on the specified database(s).

3. **Verify**  
   - User/API: `python aws-pgx-setup/glue/test_glue_lakeformation_permissions.py --credentials-dir /mnt/c/Projects`  
   - Crawler role: `python aws-pgx-setup/glue/test_glue_crawler_permissions.py --credentials-dir /mnt/c/Projects --crawler pgx_pharmacy_bronze_pharmacy`

**Scripts in this folder:** `lakeformation_set_iam_only_defaults.py`, `lakeformation_grant_crawler_on_database.py`, `lakeformation_grant_drop_tables.py`. Glue and validation scripts live in **`../glue/`**; see **`../glue/README.md`** for details.

---

## Scripts in this folder

| Script | Purpose |
|--------|--------|
| **lakeformation_set_iam_only_defaults.py** | Set Lake Formation defaults to IAM-only for *new* databases/tables (PutDataLakeSettings with IAM_ALLOWED_PRINCIPALS). |
| **lakeformation_grant_crawler_on_database.py** | Grant the Glue crawler role Lake Formation permissions on database(s): `--all-pharmacy-databases`, `--all-medical-databases`, or `--database pgxdatalake`. |
| **lakeformation_grant_drop_tables.py** | Grant Lake Formation DROP (or ALL) on specified tables so you can delete them in the console. Use `--iam-allowed` if needed. |

---

## Related in aws-pgx-setup

- **Glue:** `../glue/` — Glue crawlers, tables, databases; permission tests and row-coverage validation. See **`../glue/README.md`**.
- **IAM:** `../iam/` — IAM users and roles; the Glue crawler role is created/managed there and then granted in Lake Formation as above.
