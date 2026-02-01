#!/usr/bin/env python3
"""
Delete Glue tables via API (avoids Lake Formation drop permission issues in console).
Usage (from repo root): python aws-pgx-setup/glue/glue_delete_tables.py --credentials-dir /mnt/c/Projects --tables table_name
"""
import argparse
import os
import sys
from pathlib import Path
import boto3

REGION = "us-east-1"
GLUE_DATABASE = "pgxdatalake"
DEFAULT_TABLES = ["bronze_pharmacy_pharmacy", "silver_pharmacy_partitioned_pharmacy_partitioned"]

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
    parser = argparse.ArgumentParser(description="Delete Glue tables via API.")
    parser.add_argument("--profile", default="mushin", help="AWS profile name")
    parser.add_argument("--credentials-dir", default=None, metavar="DIR", help="Directory containing .aws/credentials (e.g. /mnt/c/Projects)")
    parser.add_argument("--database", default=GLUE_DATABASE, help="Glue database name")
    parser.add_argument("--tables", nargs="+", default=DEFAULT_TABLES, metavar="TABLE", help="Table name(s) to delete")
    parser.add_argument("--dry-run", action="store_true", help="Print only, do not delete")
    args = parser.parse_args()
    if args.credentials_dir:
        _apply_credentials_dir(args.credentials_dir)
    session = boto3.Session(profile_name=args.profile, region_name=REGION)
    glue = session.client("glue", region_name=REGION)
    for table_name in args.tables:
        if args.dry_run:
            print(f"  [DRY RUN] Would delete {args.database}.{table_name}")
            continue
        try:
            glue.delete_table(DatabaseName=args.database, Name=table_name)
            print(f"  [OK] Deleted {table_name}")
        except glue.exceptions.EntityNotFoundException:
            print(f"  [SKIP] {table_name} not found (already deleted)")
        except Exception as e:
            print(f"  [FAIL] {table_name}: {e}", file=sys.stderr)
            return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
