#!/usr/bin/env python3
"""
Run Athena row counts on pharmacy bronze/silver/gold and verify:
  - Silver = Gold (no data loss during drug name normalization).
  - Gold <= Bronze (no unexpected row inflation).

Exits 0 if checks pass, 1 otherwise. Per-layer databases: bronze_pharmacy, silver_pharmacy, gold_pharmacy.

Usage (from repo root):
  python aws-pgx-setup/glue/validate_pharmacy_row_coverage.py --athena-output s3://pgxdatalake/athena-query-results/ --credentials-dir /mnt/c/Projects
"""
import argparse
import os
import re
import sys
import time
from pathlib import Path
from typing import Optional

import boto3

REGION = "us-east-1"
PHARMACY_LAYERS = [
    ("bronze_pharmacy", "bronze/pharmacy/", "bronze_pharmacy", "bronze_pharmacy"),
    ("silver_pharmacy_partitioned", "silver/imputed/pharmacy_partitioned/", "silver_pharmacy_partitioned", "silver_pharmacy"),
    ("gold_pharmacy", "gold/pharmacy/", "gold_pharmacy", "gold_pharmacy"),
]

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

def get_tables_for_database(glue, database: str):
    out = []
    try:
        paginator = glue.get_paginator("get_tables")
        for page in paginator.paginate(DatabaseName=database):
            for t in page.get("TableList", []):
                name = t.get("Name", "")
                loc = (t.get("StorageDescriptor") or {}).get("Location", "")
                out.append((name, loc))
    except Exception:
        pass
    return out

def table_covers_location(location: str, s3_prefix: str) -> bool:
    if not location:
        return False
    m = re.match(r"s3://[^/]+/(.+)", location)
    path = m.group(1) if m else location
    path = path.rstrip("/") + "/"
    return path == s3_prefix or path.startswith(s3_prefix.rstrip("/") + "/")

def find_table_for_prefix(glue, database: str, s3_prefix: str) -> Optional[str]:
    for name, loc in get_tables_for_database(glue, database):
        if table_covers_location(loc, s3_prefix):
            return name
    return None

def run_athena_count(athena, database: str, table: str, output_location: str) -> Optional[int]:
    q = f'SELECT COUNT(*) AS cnt FROM "{table}"'  # noqa: S608 table from Glue
    try:
        resp = athena.start_query_execution(
            QueryString=q,
            QueryExecutionContext={"Database": database},
            ResultConfiguration={"OutputLocation": output_location},
        )
        qid = resp["QueryExecutionId"]
        for _ in range(120):
            r = athena.get_query_execution(QueryExecutionId=qid)
            state = r["QueryExecution"]["Status"]["State"]
            if state == "SUCCEEDED":
                rr = athena.get_query_results(QueryExecutionId=qid)
                rows = rr.get("ResultSet", {}).get("Rows", [])
                if len(rows) >= 2:
                    val = rows[1].get("Data", [{}])[0].get("VarCharValue", "0")
                    return int(val)
                return None
            if state in ("FAILED", "CANCELLED"):
                return None
            time.sleep(2)
    except Exception:
        pass
    return None

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate pharmacy bronze/silver/gold row coverage; exit 0 only if silver=gold and gold<=bronze."
    )
    parser.add_argument("--profile", default="mushin", help="AWS profile name")
    parser.add_argument("--credentials-dir", default=None, metavar="DIR", help="Directory with .aws/credentials (e.g. /mnt/c/Projects)")
    parser.add_argument("--athena-output", required=True, help="S3 path for Athena query results (e.g. s3://pgxdatalake/athena-query-results/)")
    args = parser.parse_args()
    if args.credentials_dir:
        _apply_credentials_dir(args.credentials_dir)
    session = boto3.Session(profile_name=args.profile, region_name=REGION)
    glue = session.client("glue", region_name=REGION)
    athena = session.client("athena", region_name=REGION)
    counts = {}
    for logical_name, s3_prefix, _suggested, database_name in PHARMACY_LAYERS:
        table_name = find_table_for_prefix(glue, database_name, s3_prefix)
        if not table_name:
            print(f"  [SKIP] {logical_name}: no table in {database_name} for {s3_prefix}", file=sys.stderr)
            counts[logical_name] = None
            continue
        c = run_athena_count(athena, database_name, table_name, args.athena_output.rstrip("/") + "/")
        counts[logical_name] = c
        if c is not None:
            print(f"  {logical_name} ({database_name}.{table_name}): {c:,} rows")
        else:
            print(f"  {logical_name} ({database_name}.{table_name}): query failed", file=sys.stderr)
    b = counts.get("bronze_pharmacy")
    s = counts.get("silver_pharmacy_partitioned")
    g = counts.get("gold_pharmacy")
    if None in (b, s, g):
        print("\n[FAIL] Missing row count(s); cannot validate.", file=sys.stderr)
        return 1
    ok = True
    if s != g:
        print(f"\n[FAIL] Silver ({s:,}) != Gold ({g:,}); possible data loss during drug name normalization.", file=sys.stderr)
        ok = False
    else:
        print(f"\n[OK] Silver = Gold ({g:,}); no data loss during drug name normalization.")
    if g > b:
        print(f"[FAIL] Gold ({g:,}) > Bronze ({b:,}); unexpected row inflation.", file=sys.stderr)
        ok = False
    elif g <= b:
        print(f"[OK] Gold <= Bronze (no unexpected row inflation).")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
