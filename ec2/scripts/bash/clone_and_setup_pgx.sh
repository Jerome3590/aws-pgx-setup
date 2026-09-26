#!/usr/bin/env bash
# Clone pgx-analysis onto a from-scratch AL2023 session after bootstrap.
# Always inits aws-pgx-setup (shallow clone does not do this by itself).
# Always pip-installs requirements.txt even if jupyter-env already exists.
# Runbook: aws-pgx-setup/ec2/README_pgx_session.md
#
#   bash clone_and_setup_pgx.sh
#   REPO_DIR=/home/ec2-user/pgx-analysis bash clone_and_setup_pgx.sh
#
# Next: wrap the job so SES mails a summary then destroys the session:
#   bash aws-pgx-setup/ec2/scripts/bash/run_ec2_analysis_session.sh --job-name '...' -- <command>
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Jerome3590/pgx-analysis.git}"
REPO_DIR="${REPO_DIR:-$HOME/pgx-analysis}"
PYTHON_ENV="${PYTHON_ENV:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== pgx-analysis setup (aws-pgx-setup) ==="

if [[ ! -d "$REPO_DIR/.git" ]]; then
  mkdir -p "$(dirname "$REPO_DIR")"
  if [[ "${SHALLOW_CLONE:-true}" == "true" ]]; then
    git clone --depth 1 --recurse-submodules "$REPO_URL" "$REPO_DIR"
  else
    git clone --recurse-submodules "$REPO_URL" "$REPO_DIR"
  fi
else
  git -C "$REPO_DIR" pull --ff-only || git -C "$REPO_DIR" pull
fi

git -C "$REPO_DIR" submodule update --init --depth 1 aws-pgx-setup || \
  git -C "$REPO_DIR" submodule update --init aws-pgx-setup

cd "$REPO_DIR"

if [[ -z "$PYTHON_ENV" ]]; then
  if [[ -x "$HOME/jupyter-env/bin/python" ]]; then
    PYTHON_ENV="$HOME/jupyter-env"
  elif [[ -d "$REPO_DIR/.venv" ]]; then
    PYTHON_ENV="$REPO_DIR/.venv"
  else
    PYTHON_ENV="$HOME/jupyter-env"
    python3.11 -m venv "$PYTHON_ENV" 2>/dev/null || python3 -m venv "$PYTHON_ENV"
  fi
fi

# shellcheck disable=SC1091
source "$PYTHON_ENV/bin/activate"
pip install --upgrade pip
if [[ ! -f requirements.txt ]]; then
  echo "ERROR: $REPO_DIR/requirements.txt missing" >&2
  exit 1
fi
pip install -r requirements.txt

export REPO="$REPO_DIR"
export PY="$PYTHON_ENV/bin/python"
PREFLIGHT="$SCRIPT_DIR/preflight_pgx_python.sh"
if [[ ! -f "$PREFLIGHT" ]]; then
  PREFLIGHT="$REPO_DIR/aws-pgx-setup/ec2/scripts/bash/preflight_pgx_python.sh"
fi
bash "$PREFLIGHT"

echo "REPO=$REPO_DIR"
echo "VENV=$PYTHON_ENV"
echo "Next: source $PYTHON_ENV/bin/activate"
echo "      bash aws-pgx-setup/ec2/scripts/bash/run_ec2_analysis_session.sh --job-name '...' -- <command>"
echo "SES: COMPLETE summary, then FINAL shutdown confirmation (dixonrj@vcu.edu)"
