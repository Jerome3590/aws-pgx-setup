#!/usr/bin/env python3
"""
Set Lake Formation default permissions to IAM-only for new databases and tables.
This allows Glue crawlers (and other IAM-authorized principals) to create/use
catalog resources without Lake Formation AccessDeniedException.
Uses PutDataLakeSettings with CreateDatabaseDefaultPermissions and
CreateTableDefaultPermissions granting ALL to IAM_ALLOWED_PRINCIPALS.
Preserves existing DataLakeAdmins.

Usage (from repo root):
  python aws-pgx-setup/lake_formation/lakeformation_set_iam_only_defaults.py
  python aws-pgx-setup/lake_formation/lakeformation_set_iam_only_defaults.py --profile mushin
  python aws-pgx-setup/lake_formation/lakeformation_set_iam_only_defaults.py --credentials-dir /mnt/c/Projects
  python aws-pgx-setup/lake_formation/lakeformation_set_iam_only_defaults.py --dry-run
"""
import argparse
import json
import os
import sys
from pathlib import Path
import boto3

IAM_DEFAULT_PERM = {
    "Principal": {"DataLakePrincipalIdentifier": "IAM_ALLOWED_PRINCIPALS"},
    "Permissions": ["ALL"],
}

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
    parser = argparse.ArgumentParser(description="Set Lake Formation defaults to IAM-only for new resources.")
    parser.add_argument("--profile", default="mushin", help="AWS profile name")
    parser.add_argument("--credentials-dir", default=None, metavar="DIR", help="Directory containing .aws/credentials and .aws/config (e.g. /mnt/c/Projects)")
    parser.add_argument("--dry-run", action="store_true", help="Print settings only, do not apply")
    args = parser.parse_args()
    if args.credentials_dir:
        _apply_credentials_dir(args.credentials_dir)
    session = boto3.Session(profile_name=args.profile)
    lf = session.client("lakeformation", region_name="us-east-1")
    try:
        resp = lf.get_data_lake_settings()
    except Exception as e:
        print(f"GetDataLakeSettings failed: {e}", file=sys.stderr)
        return 1
    settings = resp.get("DataLakeSettings") or {}
    admins = settings.get("DataLakeAdmins") or []
    new_settings = {
        "DataLakeAdmins": admins,
        "CreateDatabaseDefaultPermissions": [IAM_DEFAULT_PERM],
        "CreateTableDefaultPermissions": [IAM_DEFAULT_PERM],
    }
    print("Planned DataLakeSettings:")
    print(json.dumps({"DataLakeSettings": new_settings}, indent=2))
    if args.dry_run:
        print("\n[DRY RUN] Not calling PutDataLakeSettings.")
        return 0
    try:
        lf.put_data_lake_settings(DataLakeSettings=new_settings)
        print("\nPutDataLakeSettings succeeded. New databases/tables will use IAM-only by default.")
    except Exception as e:
        print(f"\nPutDataLakeSettings failed: {e}", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
