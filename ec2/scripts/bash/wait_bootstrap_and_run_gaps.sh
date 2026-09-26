#!/usr/bin/env bash
# On-box waiter: AL2023 bootstrap → clone → gold-cohort gap job → SES + destroy.
# Runbook: aws-pgx-setup/ec2/README_pgx_session.md
set -euo pipefail

export HOME="${HOME:-/home/ec2-user}"
export PGX_DATA_ROOT="${PGX_DATA_ROOT:-/mnt/nvme}"
if [[ ! "${INSTANCE_ID:-}" =~ ^i- ]]; then
  TOKEN=$(curl -sS --connect-timeout 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' http://169.254.169.254/latest/api/token || true)
  _imds_id=$(curl -sS --connect-timeout 2 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id || true)
  if [[ -z "$_imds_id" ]]; then
    _imds_id=$(curl -sS --connect-timeout 2 http://169.254.169.254/latest/meta-data/instance-id || true)
  fi
  if [[ -n "$_imds_id" ]]; then
    INSTANCE_ID="$_imds_id"
  fi
  unset TOKEN _imds_id
fi
export INSTANCE_ID="${INSTANCE_ID:-}"
export EIP_ALLOCATION_ID="${EIP_ALLOCATION_ID:-}"
REPO="${REPO:-$HOME/pgx-analysis}"
SETUP="${SETUP:-$REPO/aws-pgx-setup}"
OVERLAY="${OVERLAY:-$HOME/pgx-session-overlay}"
LOG="${LOG:-$HOME/wait_bootstrap_gaps.log}"

exec > >(tee -a "$LOG") 2>&1
echo "==== WAIT START $(date -u) ===="

# Mount NVMe (sudo) before any /mnt/nvme mkdir. Do not start this waiter as
# sudo -u ec2-user unless /mnt/nvme is already mounted, or this helper runs first.
_run_mount_nvme() {
  local helper="" h
  for h in \
    "${OVERLAY:-$HOME/pgx-session-overlay}/mount_nvme.sh" \
    "${SETUP:-}/ec2/scripts/bash/mount_nvme.sh" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mount_nvme.sh"
  do
    [[ -n "$h" && -f "$h" ]] || continue
    helper="$h"
    break
  done
  if [[ -n "$helper" ]]; then
    bash "$helper" && return 0
    echo "WARN: $helper failed; trying sudo mkdir ${PGX_DATA_ROOT:-/mnt/nvme}"
  fi
  if [[ ! -d "${PGX_DATA_ROOT:-/mnt/nvme}" ]] || [[ ! -w "${PGX_DATA_ROOT:-/mnt/nvme}" ]]; then
    sudo mkdir -p "${PGX_DATA_ROOT:-/mnt/nvme}" && \
      sudo chown "$(id -un)":"$(id -gn)" "${PGX_DATA_ROOT:-/mnt/nvme}" || \
      echo "WARN: /mnt/nvme not writable; session wrap will use HOME/tmp logs"
  fi
}
_run_mount_nvme || true

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

if [[ -d "$OVERLAY" ]]; then
  echo "WARN: applying $OVERLAY (emergency)."
  mkdir -p "$REPO/utility_scripts" "$REPO/py_helpers" \
           "$SETUP/ec2/scripts/bash" "$SETUP/ec2/scripts/python"
  [[ -f "$OVERLAY/run_gold_cohort_gaps.sh" ]] && \
    cp -f "$OVERLAY/run_gold_cohort_gaps.sh" "$REPO/utility_scripts/run_gold_cohort_gaps.sh"
  [[ -f "$OVERLAY/aws_utils.py" ]] && cp -f "$OVERLAY/aws_utils.py" "$REPO/py_helpers/aws_utils.py"
  for sh in run_ec2_analysis_session.sh cancel_pgx_session.sh preflight_pgx_python.sh mount_nvme.sh; do
    [[ -f "$OVERLAY/$sh" ]] && cp -f "$OVERLAY/$sh" "$SETUP/ec2/scripts/bash/$sh"
  done
  [[ -f "$OVERLAY/ec2_session_notify.py" ]] && \
    cp -f "$OVERLAY/ec2_session_notify.py" "$SETUP/ec2/scripts/python/ec2_session_notify.py"
fi

# Helper exists after clone/overlay; format-if-empty + mount + chown.
_run_mount_nvme || true

if [[ ! -d "$HOME/jupyter-env" ]]; then
  python3.11 -m venv "$HOME/jupyter-env"
fi
# shellcheck disable=SC1091
source "$HOME/jupyter-env/bin/activate"
pip install --upgrade pip
pip install -r "$REPO/requirements.txt"

export PYTHONPATH="$REPO"
export PGX_REPO="$REPO"
export PY="$HOME/jupyter-env/bin/python"
export REPO
bash "$SETUP/ec2/scripts/bash/preflight_pgx_python.sh"

GAP_SH="$REPO/utility_scripts/run_gold_cohort_gaps.sh"
if [[ ! -f "$GAP_SH" ]]; then
  echo "WARN: $GAP_SH missing from clone; writing local copy"
  mkdir -p "$REPO/utility_scripts"
  cat > "$GAP_SH" <<'GAP'
#!/usr/bin/env bash
set -euo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$REPO"
export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"
export PGX_DATA_ROOT="${PGX_DATA_ROOT:-/mnt/nvme}"
PY="${PY:-${HOME}/jupyter-env/bin/python}"
[[ -x "$PY" ]] || PY="$(command -v python3.11 || command -v python3 || command -v python)"
if [[ ! -d "$PGX_DATA_ROOT" ]] || [[ ! -w "$PGX_DATA_ROOT" ]]; then
  sudo mkdir -p "$PGX_DATA_ROOT" && sudo chown "$(id -un)":"$(id -gn)" "$PGX_DATA_ROOT"
fi
mkdir -p "$PGX_DATA_ROOT/gold/cohorts" "$PGX_DATA_ROOT/duckdb_tmp" "$PGX_DATA_ROOT/pgx-analysis/logs"
for age in 55-64 85-114; do
  for y in 2016 2017 2018 2019; do
    echo "==== CREATE COHORT opioid_ed ${age} ${y} $(date -u) ===="
    "$PY" "$REPO/2_create_cohort/0_create_cohort.py" \
      --cohort opioid_ed --age-band "$age" --event-year "$y" --concurrent-workers 1
  done
  for c in opioid_ed non_opioid_ed; do
    echo "==== BIN TRANSITIONS ${c} ${age} $(date -u) ===="
    "$PY" "$REPO/9_dashboard_visuals/dtw/create_bin_transitions.py" \
      --cohort "$c" --age-band "$age" --force
  done
done
echo "==== JOB DONE $(date -u) ===="
GAP
  chmod +x "$GAP_SH"
fi

cd "$REPO"
bash "$SETUP/ec2/scripts/bash/run_ec2_analysis_session.sh" \
  --job-name "gold cohort gaps 55-64 85-114" -- \
  bash "$GAP_SH"
