#!/usr/bin/env bash
# One-job waiter for opioid_ed 65-74 gold cohorts + bin transitions.
# Follows the production AL2023 path. Does not downgrade DuckDB/NumPy.
# Runbook: aws-pgx-setup/ec2/README_pgx_session.md
set -euo pipefail

export HOME="${HOME:-/home/ec2-user}"
export PGX_DATA_ROOT="${PGX_DATA_ROOT:-/mnt/nvme}"
if [[ -z "${INSTANCE_ID:-}" ]]; then
  INSTANCE_ID="$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/instance-id || true)"
fi
export INSTANCE_ID="${INSTANCE_ID:-}"
export EIP_ALLOCATION_ID="${EIP_ALLOCATION_ID:-}"
REPO="${REPO:-$HOME/pgx-analysis}"
SETUP="${SETUP:-$REPO/aws-pgx-setup}"
OVERLAY="${OVERLAY:-$HOME/pgx-session-overlay}"
LOG="${LOG:-$HOME/wait_bootstrap_65_74.log}"

exec > >(tee -a "$LOG") 2>&1
echo "==== WAIT START $(date -u) ===="

echo "Waiting for bootstrap Python 3.11 + analysis imports..."
for i in $(seq 1 180); do
  if command -v python3.11 >/dev/null 2>&1 && \
     python3.11 -c "import duckdb, pandas, boto3, pyarrow" >/dev/null 2>&1; then
    echo "Python 3.11 ready after ${i} checks ($(date -u))"
    break
  fi
  echo "still compiling... check $i $(date -u)"
  sleep 60
  if [[ "$i" -eq 180 ]]; then
    echo "ERROR: Python 3.11/DuckDB not ready after 3 hours"
    exit 1
  fi
done

if [[ ! -d "$REPO/.git" ]]; then
  git clone --depth 1 --recurse-submodules https://github.com/Jerome3590/pgx-analysis.git "$REPO"
else
  git -C "$REPO" pull --ff-only || true
fi
git -C "$REPO" submodule update --init --depth 1 aws-pgx-setup || \
  git -C "$REPO" submodule update --init aws-pgx-setup
SETUP="$REPO/aws-pgx-setup"

# Overlay is emergency-only (uncommitted local patches). Production path is
# a pushed aws-pgx-setup + parent submodule pointer.
if [[ -d "$OVERLAY" ]]; then
  echo "WARN: applying $OVERLAY (emergency). Push submodule next time."
  mkdir -p "$REPO/py_helpers" "$SETUP/ec2/scripts/bash" "$SETUP/ec2/scripts/python"
  [[ -f "$OVERLAY/aws_utils.py" ]] && cp -f "$OVERLAY/aws_utils.py" "$REPO/py_helpers/aws_utils.py"
  [[ -f "$OVERLAY/ec2_session_notify.py" ]] && \
    cp -f "$OVERLAY/ec2_session_notify.py" "$SETUP/ec2/scripts/python/ec2_session_notify.py"
  for sh in run_ec2_analysis_session.sh cancel_pgx_session.sh wait_bootstrap_and_run_65_74.sh preflight_pgx_python.sh; do
    [[ -f "$OVERLAY/$sh" ]] && cp -f "$OVERLAY/$sh" "$SETUP/ec2/scripts/bash/$sh"
  done
fi

if [[ ! -d "$HOME/jupyter-env" ]]; then
  python3.11 -m venv "$HOME/jupyter-env"
fi
# Always install requirements even when bootstrap already created the venv.
# shellcheck disable=SC1091
source "$HOME/jupyter-env/bin/activate"
pip install --upgrade pip
pip install -r "$REPO/requirements.txt"

export PYTHONPATH="$REPO"
export PGX_REPO="$REPO"
export PY="$HOME/jupyter-env/bin/python"
export REPO
bash "$SETUP/ec2/scripts/bash/preflight_pgx_python.sh"

cd "$REPO"
bash "$SETUP/ec2/scripts/bash/run_ec2_analysis_session.sh" \
  --job-name "opioid_ed 65-74 gold cohorts + bin transitions" -- \
  bash "$REPO/utility_scripts/run_opioid_65_74_cohort_and_transitions.sh"
