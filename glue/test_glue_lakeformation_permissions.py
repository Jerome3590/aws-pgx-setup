#!/usr/bin/env python3
"""
Smoke-test Lake Formation and Glue permissions (e.g. after setting IAM-only defaults).
Usage (from repo root): python aws-pgx-setup/glue/test_glue_lakeformation_permissions.py --credentials-dir /mnt/c/Projects
"""
import argparse
import os
import sys
from pathlib import Path
import boto3

REGION = "us-east-1"
GLUE_DATABASE = "pgxdatalake"

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
    parser = argparse.ArgumentParser(description="Test Lake Formation and Glue permissions.")
    parser.add_argument("--profile", default="mushin", help="AWS profile name")
    parser.add_argument("--credentials-dir", default=None, metavar="DIR", help="Directory containing .aws/credentials and .aws/config (e.g. /mnt/c/Projects)")
    parser.add_argument("--database", default=GLUE_DATABASE, help="Glue database to test")
    args = parser.parse_args()
    if args.credentials_dir:
        _apply_credentials_dir(args.credentials_dir)
    session = boto3.Session(profile_name=args.profile, region_name=REGION)
    lf = session.client("lakeformation", region_name=REGION)
    glue = session.client("glue", region_name=REGION)
    ok, fail = 0, 0
    try:
        lf.get_data_lake_settings()
        print("[OK] Lake Formation: GetDataLakeSettings")
        ok += 1
    except Exception as e:
        print(f"[FAIL] Lake Formation: GetDataLakeSettings — {e}")
        fail += 1
    try:
        glue.get_database(Name=args.database)
        print(f"[OK] Glue: GetDatabase({args.database})")
        ok += 1
    except glue.exceptions.EntityNotFoundException:
        print(f"[FAIL] Glue: GetDatabase({args.database}) — database not found")
        fail += 1
    except Exception as e:
        print(f"[FAIL] Glue: GetDatabase({args.database}) — {e}")
        fail += 1
    try:
        paginator = glue.get_paginator("get_tables")
        tables = []
        for page in paginator.paginate(DatabaseName=args.database):
            tables.extend(page.get("TableList", []))
        print(f"[OK] Glue: GetTables({args.database}) — {len(tables)} table(s)")
        ok += 1
    except Exception as e:
        print(f"[FAIL] Glue: GetTables({args.database}) — {e}")
        fail += 1
    try:
        paginator = glue.get_paginator("get_crawlers")
        crawlers = []
        for page in paginator.paginate():
            crawlers.extend(page.get("Crawlers", []))
        pgx = [c for c in crawlers if "pgx" in (c.get("Name") or "").lower()]
        print(f"[OK] Glue: GetCrawlers — {len(crawlers)} total, {len(pgx)} pgx-related")
        ok += 1
    except Exception as e:
        print(f"[FAIL] Glue: GetCrawlers — {e}")
        fail += 1
    print()
    if fail:
        print(f"Result: {ok} passed, {fail} failed.")
        return 1
    print(f"Result: all {ok} checks passed.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
