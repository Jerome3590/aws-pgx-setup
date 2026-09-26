#!/usr/bin/env python3
"""Send SES mail for a from-scratch pgx-analysis EC2 session.

Used by run_ec2_analysis_session.sh and cancel_pgx_session.sh.

  python aws-pgx-setup/ec2/scripts/python/ec2_session_notify.py complete --job-name "..." --summary "..."
  python aws-pgx-setup/ec2/scripts/python/ec2_session_notify.py error --job-name "..." --summary "..."
  python aws-pgx-setup/ec2/scripts/python/ec2_session_notify.py shutdown --instance-id i-... --state shutting-down
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def _find_pgx_repo() -> Path:
    env = os.environ.get("PGX_REPO")
    if env:
        candidate = Path(env).expanduser().resolve()
        if (candidate / "py_helpers" / "aws_utils.py").exists():
            return candidate
    here = Path(__file__).resolve()
    # .../pgx-analysis/aws-pgx-setup/ec2/scripts/python/this.py
    nested = here.parents[4]
    if (nested / "py_helpers" / "aws_utils.py").exists():
        return nested
    for home in (Path.home() / "pgx-analysis", Path("/home/pgx3874/pgx-analysis")):
        if (home / "py_helpers" / "aws_utils.py").exists():
            return home
    raise SystemExit(
        "Set PGX_REPO to the pgx-analysis checkout that contains py_helpers/aws_utils.py"
    )


REPO_ROOT = _find_pgx_repo()
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from py_helpers.aws_utils import (  # noqa: E402
    notify_session_analysis_complete,
    notify_session_error,
    notify_session_shutdown,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="SES notifications for a pgx EC2 analysis session")
    parser.add_argument("kind", choices=("complete", "error", "shutdown"))
    parser.add_argument("--job-name", default="")
    parser.add_argument("--summary", default="")
    parser.add_argument("--instance-id")
    parser.add_argument("--state", default="unknown")
    parser.add_argument("--spot-request-id")
    parser.add_argument("--alarm-name")
    parser.add_argument("--extra", action="append", default=[], help="Extra body line (repeatable)")
    args = parser.parse_args()

    extra = [line for line in args.extra if line]
    if args.kind == "complete":
        ok = notify_session_analysis_complete(
            args.job_name or "pgx-analysis session",
            args.summary,
            instance_id=args.instance_id,
            extra_lines=extra or None,
        )
    elif args.kind == "error":
        ok = notify_session_error(
            args.job_name or "pgx-analysis session",
            args.summary,
            instance_id=args.instance_id,
            extra_lines=extra or None,
        )
    else:
        if not args.instance_id:
            parser.error("shutdown requires --instance-id")
        ok = notify_session_shutdown(
            args.instance_id,
            args.state,
            job_name=args.job_name or None,
            summary=args.summary or None,
            spot_request_id=args.spot_request_id,
            alarm_name=args.alarm_name,
            extra_lines=extra or None,
        )
    print(f"SES {args.kind}: {ok}", flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
