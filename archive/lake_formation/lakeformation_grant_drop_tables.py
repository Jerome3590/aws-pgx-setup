#!/usr/bin/env python3
"""
Grant Lake Formation DROP permission on specified Glue tables so you can delete them
(e.g. doubled-name tables bronze_pharmacy_pharmacy, silver_pharmacy_partitioned_pharmacy_partitioned).

Grants to the current caller identity (from AWS profile) or to IAM_ALLOWED_PRINCIPALS.

Usage (from repo root):
  python aws-pgx-setup/lake_formation/lakeformation_grant_drop_tables.py --credentials-dir /mnt/c/Projects
  python aws-pgx-setup/lake_formation/lakeformation_grant_drop_tables.py --tables bronze_pharmacy_pharmacy silver_pharmacy_partitioned_pharmacy_partitioned
  python aws-pgx-setup/lake_formation/lakeformation_grant_drop_tables.py --iam-allowed   # grant to IAM_ALLOWED_PRINCIPALS
"""

import argparse
import os
import sys
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

REGION = "us-east-1"
GLUE_DATABASE = "pgxdatalake"
# Default doubled-name tables to grant DROP so user can delete them
DEFAULT_TABLES = ["bronze_pharmacy_pharmacy", "silver_pharmacy_partitioned_pharmacy_partitioned"]
PERMISSIONS = ["DROP", "DESCRIBE", "ALTER"]  # DROP + enough to manage/delete
PERMISSIONS_ALL = ["ALL"]  # full table access (use if console still denies drop)


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
        description="Grant Lake Formation DROP on specified tables so you can delete them in the console."
    )
    parser.add_argument("--profile", default="mushin", help="AWS profile name")
    parser.add_argument(
        "--credentials-dir",
        default=None,
        metavar="DIR",
        help="Directory containing .aws/credentials (e.g. /mnt/c/Projects)",
    )
    parser.add_argument("--database", default=GLUE_DATABASE, help="Glue database name")
    parser.add_argument(
        "--tables",
        nargs="+",
        default=DEFAULT_TABLES,
        metavar="TABLE",
        help=f"Table name(s) to grant DROP on (default: {' '.join(DEFAULT_TABLES)})",
    )
    parser.add_argument(
        "--iam-allowed",
        action="store_true",
        help="Grant to IAM_ALLOWED_PRINCIPALS instead of current caller",
    )
    parser.add_argument("--all", action="store_true", help="Grant ALL on table (use if console still denies drop)")
    parser.add_argument("--dry-run", action="store_true", help="Print planned grants only")
    args = parser.parse_args()

    perms = PERMISSIONS_ALL if args.all else PERMISSIONS

    if args.credentials_dir:
        _apply_credentials_dir(args.credentials_dir)

    session = boto3.Session(profile_name=args.profile, region_name=REGION)
    lf = session.client("lakeformation", region_name=REGION)

    if args.iam_allowed:
        principal = {"DataLakePrincipalIdentifier": "IAM_ALLOWED_PRINCIPALS"}
        principal_desc = "IAM_ALLOWED_PRINCIPALS"
    else:
        sts = session.client("sts", region_name=REGION)
        identity = sts.get_caller_identity()
        arn = identity.get("Arn", "")
        principal = {"DataLakePrincipalIdentifier": arn}
        principal_desc = arn

    print(f"Principal: {principal_desc}")
    print(f"Database: {args.database}")
    print(f"Tables: {args.tables}")
    print(f"Permissions: {perms}\n")

    if args.dry_run:
        print("[DRY RUN] Not calling GrantPermissions.")
        return 0

    for table_name in args.tables:
        resource = {"Table": {"DatabaseName": args.database, "Name": table_name}}
        try:
            lf.grant_permissions(
                Principal=principal,
                Resource=resource,
                Permissions=perms,
            )
            print(f"  [OK] Granted on {table_name}")
        except ClientError as e:
            if e.response.get("Error", {}).get("Code") == "EntityNotFoundException":
                print(f"  [SKIP] Table {table_name} not found (may already be deleted)")
            else:
                print(f"  [FAIL] {table_name}: {e}", file=sys.stderr)
                return 1
        except Exception as e:
            print(f"  [FAIL] {table_name}: {e}", file=sys.stderr)
            return 1

    print("\nYou can now delete the table(s) in the Glue console.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
