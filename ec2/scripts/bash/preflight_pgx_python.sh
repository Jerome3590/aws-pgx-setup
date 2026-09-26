#!/usr/bin/env bash
# Fail before a session job if the analysis venv cannot import the helpers
# that 0_create_cohort and SES notify load at import time.
# Runbook: aws-pgx-setup/ec2/README_pgx_session.md
#
#   bash preflight_pgx_python.sh
#   PY=/home/ec2-user/jupyter-env/bin/python REPO=$HOME/pgx-analysis \
#     bash preflight_pgx_python.sh
set -euo pipefail

REPO="${REPO:-${PGX_REPO:-$HOME/pgx-analysis}}"
PY="${PY:-${HOME}/jupyter-env/bin/python}"
if [[ ! -x "$PY" ]]; then
  PY="$(command -v python3.11 || command -v python3 || command -v python)"
fi

if [[ ! -d "$REPO/py_helpers" ]]; then
  echo "ERROR: py_helpers not found under $REPO. Clone pgx-analysis first." >&2
  exit 1
fi

SESSION_SH="$REPO/aws-pgx-setup/ec2/scripts/bash/run_ec2_analysis_session.sh"
if [[ ! -f "$SESSION_SH" ]]; then
  echo "ERROR: aws-pgx-setup submodule is empty ($SESSION_SH missing)." >&2
  echo "Push aws-pgx-setup, update the parent submodule pointer, then:" >&2
  echo "  git -C $REPO submodule update --init aws-pgx-setup" >&2
  echo "Do not overlay-copy as the normal path." >&2
  exit 1
fi

export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"
if ! "$PY" -c "from py_helpers import s3_utils, aws_utils; import mlxtend, psutil, duckdb, pandas, pyarrow, numpy; print('pgx-imports-ok')"; then
  echo "ERROR: analysis imports failed in $PY." >&2
  echo "Install from $REPO/requirements.txt. Do not pip-install a missing" >&2
  echo "module name blindly — PyPI 'phases' shadows 2_create_cohort/phases." >&2
  exit 1
fi
