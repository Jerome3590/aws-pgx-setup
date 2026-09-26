#!/usr/bin/env bash
# Run one analysis job on a from-scratch pgx-analysis session, email a short
# summary, then cancel the Spot request and terminate the instance.
# Runbook: aws-pgx-setup/ec2/README_pgx_session.md
#
#   bash aws-pgx-setup/ec2/scripts/bash/run_ec2_analysis_session.sh \
#     --job-name "opioid_ed 65-74 bin transitions" -- \
#     python 9_dashboard_visuals/dtw/create_bin_transitions.py \
#       --cohort opioid_ed --age-band 65-74 --force
#
#   KEEP_ALIVE=1 bash .../run_ec2_analysis_session.sh --job-name "debug" -- ...
#   SHUTDOWN_ON_ERROR=1  # also destroy the box after a failed job
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
NOTIFY_PY="$SCRIPT_DIR/../python/ec2_session_notify.py"
CANCEL_SH="$SCRIPT_DIR/cancel_pgx_session.sh"

if [[ -n "${PGX_REPO:-}" && -d "$PGX_REPO" ]]; then
  REPO="$PGX_REPO"
elif [[ -d "$SETUP_ROOT/../py_helpers" ]]; then
  REPO="$(cd "$SETUP_ROOT/.." && pwd)"
else
  REPO="${HOME}/pgx-analysis"
fi
cd "$REPO"
export PGX_REPO="$REPO"
export PYTHONPATH="$REPO${PYTHONPATH:+:$PYTHONPATH}"

PY="${PY:-${HOME}/jupyter-env/bin/python}"
if [[ ! -x "$PY" ]]; then
  PY="$(command -v python3 || command -v python)"
fi
JOB_NAME="${JOB_NAME:-pgx-analysis session}"
KEEP_ALIVE="${KEEP_ALIVE:-0}"
SHUTDOWN_ON_ERROR="${SHUTDOWN_ON_ERROR:-0}"
LOG_DIR="${LOG_DIR:-${PGX_DATA_ROOT:-/mnt/nvme}/pgx-analysis/logs}"
INSTANCE_ID="${INSTANCE_ID:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --job-name)
      JOB_NAME="$2"
      shift 2
      ;;
    --keep-alive)
      KEEP_ALIVE=1
      shift
      ;;
    --shutdown-on-error)
      SHUTDOWN_ON_ERROR=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Provide a command after --job-name ... -- <command>" >&2
  exit 2
fi

PREFLIGHT="$SCRIPT_DIR/preflight_pgx_python.sh"
if [[ -f "$PREFLIGHT" ]]; then
  REPO="$REPO" PY="$PY" bash "$PREFLIGHT"
fi

if [[ -z "$INSTANCE_ID" ]]; then
  INSTANCE_ID="$(curl -s --connect-timeout 1 http://169.254.169.254/latest/meta-data/instance-id || true)"
fi
INSTANCE_ID="${INSTANCE_ID:-local}"

mkdir -p "$LOG_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$LOG_DIR/session_${STAMP}.log"
START_EPOCH="$(date +%s)"
COMMIT="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"

echo "==== SESSION START ${STAMP} ====" | tee -a "$LOG"
echo "Job=${JOB_NAME}" | tee -a "$LOG"
echo "Instance=${INSTANCE_ID} Commit=${COMMIT} Log=${LOG}" | tee -a "$LOG"
echo "Command: $*" | tee -a "$LOG"

set +e
"$@" >>"$LOG" 2>&1
STATUS=$?
set -e

END_EPOCH="$(date +%s)"
ELAPSED_MIN=$(( (END_EPOCH - START_EPOCH) / 60 ))
TAIL_TXT="$(tail -n 40 "$LOG" | tr -d '\r')"
SUMMARY="Exit: ${STATUS}
Elapsed minutes: ${ELAPSED_MIN}
Commit: ${COMMIT}
Log: ${LOG}

Last log lines:
${TAIL_TXT}"

notify() {
  local kind="$1"
  "$PY" "$NOTIFY_PY" "$kind" \
    --job-name "$JOB_NAME" \
    --summary "$SUMMARY" \
    --instance-id "$INSTANCE_ID" \
    --extra "Repo: ${REPO}" \
    || echo "WARN: SES ${kind} email failed" >&2
}

if [[ "$STATUS" -ne 0 ]]; then
  echo "==== SESSION FAIL exit=${STATUS} ====" | tee -a "$LOG"
  notify error
  if [[ "$SHUTDOWN_ON_ERROR" == "1" && "$KEEP_ALIVE" != "1" && "$INSTANCE_ID" != "local" ]]; then
    JOB_NAME="$JOB_NAME" SUMMARY="$SUMMARY" INSTANCE_ID="$INSTANCE_ID" \
      PGX_REPO="$REPO" bash "$CANCEL_SH"
  fi
  exit "$STATUS"
fi

echo "==== SESSION OK ${ELAPSED_MIN} min ====" | tee -a "$LOG"
notify complete

if [[ "$KEEP_ALIVE" == "1" ]]; then
  echo "KEEP_ALIVE=1 — skipping Spot cancel / terminate"
  exit 0
fi
if [[ "$INSTANCE_ID" == "local" ]]; then
  echo "Not on EC2 — skipping teardown"
  exit 0
fi

JOB_NAME="$JOB_NAME" SUMMARY="$SUMMARY" INSTANCE_ID="$INSTANCE_ID" \
  EIP_ALLOCATION_ID="${EIP_ALLOCATION_ID:-}" \
  PGX_REPO="$REPO" \
  bash "$CANCEL_SH"
