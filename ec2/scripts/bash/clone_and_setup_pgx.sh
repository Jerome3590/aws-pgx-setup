#!/usr/bin/env bash
# Clone pgx-analysis onto a box launched from the Mushin session AMI.
# Canonical copy lives in aws-setup; this is the in-repo mirror.
#
#   bash clone_and_setup_pgx.sh
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Jerome3590/pgx-analysis.git}"
REPO_DIR="${REPO_DIR:-$HOME/pgx-analysis}"
PYTHON_ENV="${PYTHON_ENV:-}"

echo "=== pgx-analysis setup (aws-setup) ==="

if [[ ! -d "$REPO_DIR/.git" ]]; then
  mkdir -p "$(dirname "$REPO_DIR")"
  if [[ "${SHALLOW_CLONE:-true}" == "true" ]]; then
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
  else
    git clone --recurse-submodules "$REPO_URL" "$REPO_DIR"
  fi
else
  git -C "$REPO_DIR" pull --ff-only || git -C "$REPO_DIR" pull
fi

cd "$REPO_DIR"

if [[ -z "$PYTHON_ENV" ]]; then
  if [[ -x "$HOME/jupyter-env/bin/python" ]]; then
    PYTHON_ENV="$HOME/jupyter-env"
  elif [[ -d "$REPO_DIR/.venv" ]]; then
    PYTHON_ENV="$REPO_DIR/.venv"
  else
    PYTHON_ENV="$HOME/jupyter-env"
    python3 -m venv "$PYTHON_ENV"
  fi
fi

# shellcheck disable=SC1091
source "$PYTHON_ENV/bin/activate"
pip install --upgrade pip
if [[ -f requirements.txt ]]; then
  pip install -r requirements.txt
fi

echo "REPO=$REPO_DIR"
echo "VENV=$PYTHON_ENV"
echo "Next: jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser"
