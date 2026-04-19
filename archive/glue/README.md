# Glue: Crawlers, Tables, and Validation

Scripts for Glue Data Catalog operations, crawler permission testing, and row-coverage validation. Use with `--credentials-dir /mnt/c/Projects` (or your credentials path) and `--profile mushin` when needed.

Run from **repo root** (pgx-analysis), e.g.:

```bash
python aws-pgx-setup/glue/glue_create_databases.py --credentials-dir /mnt/c/Projects --medical
```

---

## Scripts

| Script | Purpose |
|--------|--------|
| **glue_create_databases.py** | Create Glue databases (explicit per-layer): `--pharmacy` (bronze_pharmacy, silver_pharmacy, gold_pharmacy), `--medical` (bronze_medical, silver_medical, gold_medical). Skips existing. |
| **glue_delete_tables.py** | Delete Glue tables via API (avoids Lake Formation drop permission issues in the console). Pass `--database` and `--tables`. |
| **test_glue_lakeformation_permissions.py** | Smoke-test Lake Formation + Glue API access (GetDataLakeSettings, GetDatabase, GetTables, GetCrawlers). |
| **test_glue_crawler_permissions.py** | Run a Glue crawler and report success or LastCrawl ErrorMessage (tests crawler *role* permissions). Use `--dataset pharmacy`, `--dataset medical`, or `--dataset all`; `--list-only` to list pgx crawlers. |
| **validate_pharmacy_row_coverage.py** | Run Athena row counts on bronze/silver/gold pharmacy; exit 0 only if silver=gold and gold≤bronze (no data loss during drug name normalization). Requires `--athena-output`. |
| **validate_medical_row_coverage.py** | Same for medical (bronze_medical, silver_medical, gold_medical); verifies no data loss during ICD code standardization. Requires `--athena-output`. |

---

## Pharmacy / medical databases

Pharmacy uses **bronze_pharmacy**, **silver_pharmacy**, **gold_pharmacy**; medical uses **bronze_medical**, **silver_medical**, **gold_medical**. Grant the crawler role on these via Lake Formation (see **`../lake_formation/README.md`**):

```bash
# Pharmacy
python aws-pgx-setup/lake_formation/lakeformation_grant_crawler_on_database.py --credentials-dir /mnt/c/Projects --all-pharmacy-databases

# Medical
python aws-pgx-setup/lake_formation/lakeformation_grant_crawler_on_database.py --credentials-dir /mnt/c/Projects --all-medical-databases
```

Test crawlers: `test_glue_crawler_permissions.py --dataset pharmacy` or `--dataset medical` or `--dataset all`.

---

## Fixing crawler “Insufficient Lake Formation permission(s) on …”

1. **Grant the crawler role on the database(s)** (run once): use `lakeformation_grant_crawler_on_database.py` in **`../lake_formation/`** as above.
2. **Re-run the crawler test:**  
   `python aws-pgx-setup/glue/test_glue_crawler_permissions.py --credentials-dir /mnt/c/Projects --crawler pgx_pharmacy_bronze_pharmacy`

---

## Deleting tables when console says “Insufficient Lake Formation permission(s): Required Drop”

1. **Grant DROP (or ALL) on the table** (optional):  
   `python aws-pgx-setup/lake_formation/lakeformation_grant_drop_tables.py --credentials-dir /mnt/c/Projects --tables table_name`  
   Add `--all --iam-allowed` if the console still denies drop.
2. **Delete via API** (recommended):  
   `python aws-pgx-setup/glue/glue_delete_tables.py --credentials-dir /mnt/c/Projects --tables table_name`  
   Specify `--database` if not using default pgxdatalake.

---

## Athena QA (row-coverage validation)

These scripts are the **canonical Athena QA queries** for bronze/silver/gold row counts. The pipeline scripts in **`1a_apcd_input_data/`** (check_pharmacy_glue_and_validate.py, check_medical_glue_and_validate.py) focus on Glue/crawler workflow only and point here for Athena validation so the pipeline stays focused.

- **Pharmacy:** `validate_pharmacy_row_coverage.py` — silver=gold, gold≤bronze (no data loss during drug name normalization).
- **Medical:** `validate_medical_row_coverage.py` — same checks for ICD code standardization.
- **Both:** `validate_row_coverage_both.py` — run pharmacy and medical in one command.

---

## Related

- **Lake Formation:** `../lake_formation/` — IAM-only defaults and crawler/table grants.
- **Crawler/table creation:** Scripts in **`1a_apcd_input_data/`** (parent repo) create crawlers and tables; run from pgx-analysis root. Athena QA lives here in **aws-pgx-setup/glue/**.
