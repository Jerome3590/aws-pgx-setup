#!/usr/bin/env python3
"""
Test Glue crawler permissions by running a crawler and reporting success or failure.
Usage (from repo root): python aws-pgx-setup/glue/test_glue_crawler_permissions.py --credentials-dir /mnt/c/Projects --crawler pgx_pharmacy_bronze_pharmacy
"""
import argparse
import os
import sys
import time
from pathlib import Path
import boto3

REGION = "us-east-1"
PGX_PHARMACY_CRAWLERS = ["pgx_pharmacy_bronze_pharmacy", "pgx_pharmacy_silver_pharmacy_partitioned", "pgx_pharmacy_gold_pharmacy"]
PGX_MEDICAL_CRAWLERS = ["pgx_medical_bronze_medical", "pgx_medical_silver_medical_partitioned", "pgx_medical_gold_medical"]

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

def list_pgx_crawlers(glue, dataset: str = "all") -> list:
    seen = set()
    paginator = glue.get_paginator("get_crawlers")
    for page in paginator.paginate():
        for c in page.get("Crawlers", []):
            name = c.get("Name", "")
            if dataset == "pharmacy" and (name in PGX_PHARMACY_CRAWLERS or name.startswith("pgx_pharmacy_")):
                seen.add(name)
            elif dataset == "medical" and (name in PGX_MEDICAL_CRAWLERS or name.startswith("pgx_medical_")):
                seen.add(name)
            elif dataset == "all" and (name in PGX_PHARMACY_CRAWLERS or name.startswith("pgx_pharmacy_") or name in PGX_MEDICAL_CRAWLERS or name.startswith("pgx_medical_")):
                seen.add(name)
    return sorted(seen)

def run_crawler_and_report(glue, crawler_name: str, timeout_sec: int) -> bool:
    try:
        glue.get_crawler(Name=crawler_name)
    except glue.exceptions.EntityNotFoundException:
        print(f"Crawler '{crawler_name}' does not exist.")
        return False
    print(f"Starting crawler: {crawler_name} (timeout {timeout_sec}s)...")
    try:
        glue.start_crawler(Name=crawler_name)
    except Exception as e:
        print(f"[FAIL] start_crawler: {e}")
        return False
    start = time.time()
    state = ""
    while time.time() - start < timeout_sec:
        r = glue.get_crawler(Name=crawler_name)
        state = r["Crawler"].get("State", "")
        if state == "READY":
            break
        if state in ("FAILED", "STOPPING"):
            print(f"Crawler entered state: {state}")
            break
        elapsed = int(time.time() - start)
        print(f"  ... state={state} (elapsed {elapsed}s)")
        time.sleep(10)
    else:
        print(f"[TIMEOUT] Crawler did not reach READY/FAILED within {timeout_sec}s")
        return False
    r = glue.get_crawler(Name=crawler_name)
    crawler = r["Crawler"]
    last = crawler.get("LastCrawl") or {}
    status = last.get("Status", "N/A")
    err = last.get("ErrorMessage", "")
    print()
    print("Crawler state:", crawler.get("State"))
    print("LastCrawl Status:", status)
    if err:
        print("LastCrawl ErrorMessage:", err)
    if status == "FAILED":
        print("\n[FAIL] Last crawl reported FAILED (see ErrorMessage above).")
        return False
    if status == "SUCCEEDED":
        print("\n[OK] Crawler run succeeded.")
        return True
    if state != "READY":
        print("\n[FAIL] Crawler did not reach READY and LastCrawl status is not SUCCEEDED.")
        return False
    print("\n[OK] Crawler is READY.")
    return True

def main() -> int:
    parser = argparse.ArgumentParser(description="Test Glue crawler permissions by running a crawler.")
    parser.add_argument("--profile", default="mushin", help="AWS profile name")
    parser.add_argument("--credentials-dir", default=None, metavar="DIR", help="Directory containing .aws/credentials (e.g. /mnt/c/Projects)")
    parser.add_argument("--dataset", choices=("pharmacy", "medical", "all"), default="all", help="Which crawlers to list/run")
    parser.add_argument("--crawler", default=None, help="Crawler name to run")
    parser.add_argument("--timeout", type=int, default=600, help="Wait timeout in seconds (default 600)")
    parser.add_argument("--list-only", action="store_true", help="List pgx crawlers and exit")
    args = parser.parse_args()
    if args.credentials_dir:
        _apply_credentials_dir(args.credentials_dir)
    session = boto3.Session(profile_name=args.profile, region_name=REGION)
    glue = session.client("glue", region_name=REGION)
    available = list_pgx_crawlers(glue, args.dataset)
    if not available:
        print(f"No pgx {args.dataset} crawlers found. Create them with check_pharmacy_glue_and_validate.py or check_medical_glue_and_validate.py in 1a_apcd_input_data.")
        return 1
    print("Available pgx crawlers:", available)
    if args.list_only:
        return 0
    crawler_name = args.crawler or available[0]
    if not args.crawler:
        print(f"Using crawler: {crawler_name}")
    elif crawler_name not in available:
        try:
            glue.get_crawler(Name=crawler_name)
        except glue.exceptions.EntityNotFoundException:
            print(f"Crawler '{crawler_name}' not found.")
            return 1
    success = run_crawler_and_report(glue, crawler_name, args.timeout)
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())
