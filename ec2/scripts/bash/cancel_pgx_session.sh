#!/usr/bin/env bash
# Cancel the Spot request for a from-scratch pgx-analysis session, then
# terminate the instance. Cancel the request first so persistent Spot cannot
# fulfill again. Sends a FINAL SES email confirming teardown.
# Runbook: aws-pgx-setup/ec2/README_pgx_session.md
#
#   INSTANCE_ID=i-xxxxxxxx bash aws-pgx-setup/ec2/scripts/bash/cancel_pgx_session.sh
#   AWS_PROFILE=mushin INSTANCE_ID=i-xxxxxxxx bash cancel_pgx_session.sh
#
# Same order as surgical-ed-vr cancel_analysis_session.sh.
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_ID="${INSTANCE_ID:-}"
SPOT_REQUEST_ID="${SPOT_REQUEST_ID:-}"
JOB_NAME="${JOB_NAME:-pgx-analysis session}"
SUMMARY="${SUMMARY:-}"
EIP_ALLOCATION_ID="${EIP_ALLOCATION_ID:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
NOTIFY_PY="$SCRIPT_DIR/../python/ec2_session_notify.py"

if [[ -n "${PGX_REPO:-}" && -d "$PGX_REPO" ]]; then
  REPO="$PGX_REPO"
elif [[ -d "$SETUP_ROOT/../py_helpers" ]]; then
  REPO="$(cd "$SETUP_ROOT/.." && pwd)"
else
  REPO="${HOME}/pgx-analysis"
fi
export PGX_REPO="$REPO"

PY="${PY:-${HOME}/jupyter-env/bin/python}"
if [[ ! -x "$PY" ]]; then
  PY="$(command -v python3 || command -v python || true)"
fi
# Laptop default. On the box, leave AWS_PROFILE empty so the instance role is used.
if [[ -z "${AWS_PROFILE+x}" ]]; then
  if curl -s --connect-timeout 1 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
    AWS_PROFILE=""
  else
    AWS_PROFILE="${AWS_PROFILE_DEFAULT:-mushin}"
  fi
fi

PROTECTED_IDS="i-0c968462d413a1028 i-07dbb05da43df1cad i-026ebc2f3c41a3408 i-0794d746684b6101c i-0e74089220f4b9a4d"

aws_() {
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
  else
    aws --region "$AWS_REGION" "$@"
  fi
}

if [[ -z "$INSTANCE_ID" ]]; then
  INSTANCE_ID="$(curl -s --connect-timeout 1 http://169.254.169.254/latest/meta-data/instance-id || true)"
fi
if [[ -z "$INSTANCE_ID" && -z "$SPOT_REQUEST_ID" ]]; then
  echo "Set INSTANCE_ID and/or SPOT_REQUEST_ID" >&2
  exit 1
fi

for protected in $PROTECTED_IDS; do
  if [[ "$INSTANCE_ID" == "$protected" ]]; then
    echo "Refusing to touch protected instance $INSTANCE_ID" >&2
    exit 1
  fi
done

if [[ -z "$SPOT_REQUEST_ID" && -n "$INSTANCE_ID" ]]; then
  SPOT_REQUEST_ID="$(aws_ ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].SpotInstanceRequestId' \
    --output text 2>/dev/null || true)"
fi

if [[ -n "$SPOT_REQUEST_ID" && "$SPOT_REQUEST_ID" != "None" ]]; then
  echo "==> Cancel $SPOT_REQUEST_ID"
  aws_ ec2 cancel-spot-instance-requests --spot-instance-request-ids "$SPOT_REQUEST_ID"
else
  SPOT_REQUEST_ID=""
fi

ALARM="sedvr-idle-stop-${INSTANCE_ID}"
if [[ -n "$INSTANCE_ID" ]]; then
  echo "==> Delete idle alarm $ALARM"
  aws_ cloudwatch delete-alarms --alarm-names "$ALARM" 2>/dev/null || true
fi

# Email before terminate so the box can still reach SES.
STATE="shutting-down (terminate about to run)"
if [[ -x "$PY" && -f "$NOTIFY_PY" ]]; then
  "$PY" "$NOTIFY_PY" shutdown \
    --job-name "$JOB_NAME" \
    --summary "${SUMMARY:-Spot request cancelled; instance terminate issued next.}" \
    --instance-id "$INSTANCE_ID" \
    --state "$STATE" \
    --spot-request-id "${SPOT_REQUEST_ID:-}" \
    --alarm-name "$ALARM" \
    --extra "Root volume deletes with the instance (DeleteOnTermination=true)." \
    || echo "WARN: SES shutdown email failed" >&2
else
  aws_ ses send-email \
    --from "jerome@mushinsolutions.com" \
    --destination "ToAddresses=dixonrj@vcu.edu" \
    --message "Subject={Data=[pgx-analysis-session] FINAL: EC2 shutdown confirmed (${JOB_NAME})},Body={Text={Data=EC2 session teardown finished.

Instance: ${INSTANCE_ID}
Spot request cancelled: ${SPOT_REQUEST_ID:-none}
Idle alarm deleted: ${ALARM}
Instance state after teardown: ${STATE}
Root volume: DeleteOnTermination=true

Analysis summary:
${SUMMARY:-see COMPLETE email}}}" \
    || echo "WARN: SES shutdown email failed" >&2
fi

if [[ -n "$INSTANCE_ID" ]]; then
  echo "==> Terminate $INSTANCE_ID"
  aws_ ec2 terminate-instances --instance-ids "$INSTANCE_ID"
fi

if [[ -n "$EIP_ALLOCATION_ID" ]]; then
  echo "==> Release Elastic IP $EIP_ALLOCATION_ID"
  aws_ ec2 release-address --allocation-id "$EIP_ALLOCATION_ID" || true
fi

echo "DONE instance=${INSTANCE_ID} spot=${SPOT_REQUEST_ID:-none}"
