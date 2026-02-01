#!/usr/bin/env python3
"""
Grant the Glue crawler role Lake Formation permissions on Glue database(s).
Fixes: "Insufficient Lake Formation permission(s) on ..." when the crawler runs.

Uses Lake Formation GrantPermissions (same-account). For cross-account Glue/LF patterns
see C:\\Projects\\vr_sling_analytics\\aws\\iam (lf_*.json, glue_*.json).

Usage (from repo root):
  python aws-pgx-setup/lake_formation/lakeformation_grant_crawler_on_database.py --credentials-dir /mnt/c/Projects --all-pharmacy-databases
  python aws-pgx-setup/lake_formation/lakeformation_grant_crawler_on_database.py --credentials-dir /mnt/c/Projects --all-medical-databases     # bronze_medical, silver_medical, gold_medical
  python aws-pgx-setup/lake_formation/lakeformation_grant_crawler_on_database.py --credentials-dir /mnt/c/Projects --database pgxdatalake
  python aws-pgx-setup/lake_formation/lakeformation_grant_crawler_on_database.py --dry-run
"""

import argparse
import os
import sys
from pathlib import Path

import boto3

REGION = "us-east-1"
GLUE_DATABASE = "pgxdatalake"
PHARMACY_DATABASES = ["bronze_pharmacy", "silver_pharmacy", "gold_pharmacy"]
MEDICAL_DATABASES = ["bronze_medical", "silver_medical", "gold_medical"]
GLUE_CRAWLER_ROLE_ARN = "arn:aws:iam::535362115856:role/service-role/AWSGlueServiceRole-pgx-data-model"
DATABASE_PERMISSIONS = ["DESCRIBE", "ALTER", "CREATE_TABLE", "DROP"]


def _apply_credentials_dir(credentials_dir: str) -> None:
    base = Path(credentials_dir).resolve()
    creds = base / ".aws" / "credentials"
    if not creds.exists():
        creds = base / "credentials"
    config = base / ".aws" / "config"
    if not config.exists():
        config = base / "config"
    if creds.exists():
        os.environ["AWS_SHARED_CREDENTIALS_FILE"] = str(creds)
    if config.exists():
        os.environ["AWS_CONFIG_FILE"] = str(config)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Grant Glue crawler role Lake Formation permissions on pgxdatalake database."
    )
    parser.add_argument("--profile", default="mushin", help="AWS profile name")
    parser.add_argument(
        "--credentials-dir",
        default=None,
        metavar="DIR",
        help="Directory containing .aws/credentials (e.g. /mnt/c/Projects)",
    )
    parser.add_argument("--database", default=None, help="Glue database name (or use --all-pharmacy-databases)")
    parser.add_argument(
        "--all-pharmacy-databases",
        action="store_true",
        help="Grant on all explicit pharmacy databases: bronze_pharmacy, silver_pharmacy, gold_pharmacy",
    )
    parser.add_argument(
        "--all-medical-databases",
        action="store_true",
        help="Grant on all explicit medical databases: bronze_medical, silver_medical, gold_medical",
    )
    parser.add_argument("--role-arn", default=GLUE_CRAWLER_ROLE_ARN, help="Glue crawler IAM role ARN")
    parser.add_argument("--dry-run", action="store_true", help="Print planned grant only, do not call API")
    args = parser.parse_args()

    if args.credentials_dir:
        _apply_credentials_dir(args.credentials_dir)

    databases = []
    if args.all_pharmacy_databases:
        databases.extend(PHARMACY_DATABASES)
    if args.all_medical_databases:
        databases.extend(MEDICAL_DATABASES)
    if args.database:
        databases.append(args.database)
    if not databases:
        databases = [GLUE_DATABASE]

    session = boto3.Session(profile_name=args.profile, region_name=REGION)
    lf = session.client("lakeformation", region_name=REGION)

    principal = {"DataLakePrincipalIdentifier": args.role_arn}
    permissions = DATABASE_PERMISSIONS

    print("Planned GrantPermissions:")
    print(f"  Principal: {args.role_arn}")
    print(f"  Databases: {databases}")
    print(f"  Permissions: {permissions}")

    if args.dry_run:
        print("\n[DRY RUN] Not calling GrantPermissions.")
        return 0

    for database in databases:
        resource = {"Database": {"Name": database}}
        try:
            lf.grant_permissions(
                Principal=principal,
                Resource=resource,
                Permissions=permissions,
            )
            print(f"  [OK] Granted on database {database}")
        except Exception as e:
            print(f"  [FAIL] {database}: {e}", file=sys.stderr)
            return 1

    print("\nGrantPermissions succeeded. Re-run the crawler test.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
