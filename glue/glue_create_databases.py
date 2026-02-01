#!/usr/bin/env python3
"""
Create Glue databases (e.g. explicit per-layer: bronze_medical, silver_medical, gold_medical).
Usage (from repo root): python aws-pgx-setup/glue/glue_create_databases.py --credentials-dir /mnt/c/Projects --medical
"""
import argparse
import os
import sys
from pathlib import Path
import boto3

REGION = "us-east-1"
PHARMACY_DATABASES = ["bronze_pharmacy", "silver_pharmacy", "gold_pharmacy"]
MEDICAL_DATABASES = ["bronze_medical", "silver_medical", "gold_medical"]

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
    parser = argparse.ArgumentParser(description="Create Glue databases (explicit per-layer).")
    parser.add_argument("--profile", default="mushin", help="AWS profile name")
    parser.add_argument("--credentials-dir", default=None, metavar="DIR", help="Directory with .aws/credentials (e.g. /mnt/c/Projects)")
    parser.add_argument("--pharmacy", action="store_true", help="Create bronze_pharmacy, silver_pharmacy, gold_pharmacy")
    parser.add_argument("--medical", action="store_true", help="Create bronze_medical, silver_medical, gold_medical")
    parser.add_argument("--dry-run", action="store_true", help="Print only, do not create")
    args = parser.parse_args()
    if args.credentials_dir:
        _apply_credentials_dir(args.credentials_dir)
    databases = []
    if args.pharmacy:
        databases.extend(PHARMACY_DATABASES)
    if args.medical:
        databases.extend(MEDICAL_DATABASES)
    if not databases:
        parser.error("Specify at least one of --pharmacy or --medical")
    session = boto3.Session(profile_name=args.profile, region_name=REGION)
    glue = session.client("glue", region_name=REGION)
    for name in databases:
        if args.dry_run:
            print(f"  [DRY RUN] Would create database: {name}")
            continue
        try:
            glue.create_database(DatabaseInput={"Name": name})
            print(f"  [OK] Created database: {name}")
        except glue.exceptions.AlreadyExistsException:
            print(f"  [SKIP] Database already exists: {name}")
        except Exception as e:
            print(f"  [FAIL] {name}: {e}", file=sys.stderr)
            return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
