#!/usr/bin/env python3
"""
Run Athena row-count QA for both pharmacy and medical (bronze/silver/gold).
Calls validate_pharmacy_row_coverage.py and validate_medical_row_coverage.py;
exits 0 only if both pass (silver=gold and gold<=bronze for each).

Usage (from repo root):
  python aws-pgx-setup/glue/validate_row_coverage_both.py --athena-output s3://pgxdatalake/athena-query-results/ --credentials-dir /mnt/c/Projects
"""
import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run Athena row-count QA for pharmacy and medical; exit 0 only if both pass."
    )
    parser.add_argument("--profile", default="mushin", help="AWS profile name")
    parser.add_argument("--credentials-dir", default=None, metavar="DIR", help="Directory with .aws/credentials (e.g. /mnt/c/Projects)")
    parser.add_argument("--athena-output", required=True, help="S3 path for Athena query results (e.g. s3://pgxdatalake/athena-query-results/)")
    args = parser.parse_args()

    def run_qa(script_name: str) -> int:
        cmd = [sys.executable, str(SCRIPT_DIR / script_name), "--athena-output", args.athena_output, "--profile", args.profile]
        if args.credentials_dir:
            cmd.extend(["--credentials-dir", args.credentials_dir])
        return subprocess.run(cmd, cwd=SCRIPT_DIR.parent.parent).returncode

    print("=== Pharmacy row-coverage QA ===")
    r1 = run_qa("validate_pharmacy_row_coverage.py")
    if r1 != 0:
        return r1

    print("\n=== Medical row-coverage QA ===")
    return run_qa("validate_medical_row_coverage.py")


if __name__ == "__main__":
    sys.exit(main())
