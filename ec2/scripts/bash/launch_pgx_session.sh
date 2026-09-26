#!/usr/bin/env bash
# Launch a from-scratch pgx-analysis Spot session.
# OS is chosen from analysis libraries (requirements.txt), not the reverse.
# Default OS=al2023. See aws-pgx-setup/ec2/README_os_and_libraries.md
# Runbook: aws-pgx-setup/ec2/README_pgx_session.md
#
#   AWS_PROFILE=mushin INSTANCE_TYPE=x2iedn.2xlarge bash launch_pgx_session.sh
#   INSTALL_R=1 AWS_PROFILE=mushin bash launch_pgx_session.sh   # BupaR / r_helpers
#   OS=al2 AWS_PROFILE=mushin bash launch_pgx_session.sh        # legacy only
#
# INSTANCE_TYPE: x2iedn.2xlarge (256 GiB) for one-band / visuals;
# x2iedn.8xlarge (1 TB, default) only for the full pipeline.
# If SSM AMI lookup returns None (Git Bash without Windows AWS env), set AMI_ID.
# If Public IP is empty, allocate an EIP (see README_pgx_session.md).
# Hold sedvr-idle-stop-<id> during bootstrap so a CPU dip does not stop the box.
#
# After launch: SSH as ec2-user first, wait for python3.11, clone_and_setup_pgx.sh,
# then run_ec2_analysis_session.sh (SES COMPLETE + destroy). Teardown only:
# cancel_pgx_session.sh (cancel Spot, then terminate).
#
# R/RStudio is off by default (Python/DuckDB only). Set INSTALL_R=1 when the
# job calls R (BupaR / r_helpers). On an already-running box:
#   sudo bash /usr/local/sbin/install_r_rstudio.sh
#
# User-data: ec2/bootstrap/ec2_al2023_session.sh (default). Root DeleteOnTermination=true.
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-mushin}"
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-x2iedn.8xlarge}"
SUBNET_ID="${SUBNET_ID:-subnet-5de81a53}"   # us-east-1f public
SECURITY_GROUP_ID="${SECURITY_GROUP_ID:-sg-0eb0da772c42415dd}"
KEY_NAME="${KEY_NAME:-mushin_pgx}"
IAM_INSTANCE_PROFILE="${IAM_INSTANCE_PROFILE:-EC2_Spot}"
INSTANCE_NAME="${INSTANCE_NAME:-pgx-analysis-session}"
ROOT_VOLUME_GB="${ROOT_VOLUME_GB:-80}"
SSH_USER="${SSH_USER:-pgx3874}"
INSTALL_R="${INSTALL_R:-0}"
OS="${OS:-al2023}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R_INSTALLER="${R_INSTALLER:-$SCRIPT_DIR/../../bootstrap/install_r_rstudio.sh}"
case "$OS" in
  al2023)
    AMI_PARAM="${AMI_PARAM:-/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64}"
    BOOTSTRAP="${BOOTSTRAP:-$SCRIPT_DIR/../../bootstrap/ec2_al2023_session.sh}"
    ;;
  al2)
    AMI_PARAM="${AMI_PARAM:-/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2}"
    BOOTSTRAP="${BOOTSTRAP:-$SCRIPT_DIR/../../bootstrap/ec2_linux2_single.sh}"
    ;;
  *)
    echo "ERROR: OS must be al2023 (default) or al2. Got: $OS" >&2
    exit 1
    ;;
esac

if [[ ! -f "$BOOTSTRAP" ]]; then
  echo "ERROR: bootstrap not found: $BOOTSTRAP" >&2
  exit 1
fi
if [[ ! -f "$R_INSTALLER" ]]; then
  echo "ERROR: R installer not found: $R_INSTALLER" >&2
  exit 1
fi

if [[ -z "${AMI_ID:-}" ]]; then
  AMI_ID="$(aws ssm get-parameters \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --names "$AMI_PARAM" \
    --query 'Parameters[0].Value' --output text)"
fi

echo "==> Profile $AWS_PROFILE  OS $OS  AMI $AMI_ID  type $INSTANCE_TYPE"
echo "==> Bootstrap $BOOTSTRAP  root ${ROOT_VOLUME_GB}G  INSTALL_R=${INSTALL_R}"

AMI_STATE="$(aws ec2 describe-images \
  --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --image-ids "$AMI_ID" \
  --query 'Images[0].State' --output text)"
if [[ "$AMI_STATE" != "available" ]]; then
  echo "ERROR: AMI $AMI_ID is $AMI_STATE." >&2
  exit 1
fi

echo "==> Spot prices ($INSTANCE_TYPE)"
aws ec2 describe-spot-price-history \
  --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --instance-types "$INSTANCE_TYPE" \
  --product-descriptions "Linux/UNIX" \
  --max-items 6 \
  --query 'SpotPriceHistory[*].{AZ:AvailabilityZone,Price:SpotPrice,Time:Timestamp}' \
  --output table

win_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s\n' "$1"
  fi
}

BLOCK_DEVICE="$(
  python - <<PY
import json
print(json.dumps([{
    "DeviceName": "/dev/xvda",
    "Ebs": {
        "Encrypted": True,
        "DeleteOnTermination": True,
        "VolumeSize": int("${ROOT_VOLUME_GB}"),
        "VolumeType": "gp3",
        "Iops": 3000,
        "Throughput": 125,
    },
}]))
PY
)"

USER_DATA_FILE="$(mktemp)"
trap 'rm -f "$USER_DATA_FILE"' EXIT
BOOTSTRAP_WIN="$(win_path "$BOOTSTRAP")"
R_INSTALLER_WIN="$(win_path "$R_INSTALLER")"
USER_DATA_WIN="$(win_path "$USER_DATA_FILE")"
python - <<PY
from pathlib import Path
import base64
bootstrap = Path(r"""$BOOTSTRAP_WIN""").read_text(encoding="utf-8")
if bootstrap.startswith("#!"):
    bootstrap = bootstrap.split("\n", 1)[1]
installer = Path(r"""$R_INSTALLER_WIN""").read_bytes()
b64 = base64.standard_b64encode(installer).decode("ascii")
wrapped = "\n".join(b64[i : i + 76] for i in range(0, len(b64), 76))
Path(r"""$USER_DATA_WIN""").write_text(
    "#!/bin/bash\n"
    f"export INSTALL_R={'''$INSTALL_R'''}\n"
    "mkdir -p /usr/local/sbin\n"
    "base64 -d > /usr/local/sbin/install_r_rstudio.sh <<'PGX_R_B64'\n"
    f"{wrapped}\n"
    "PGX_R_B64\n"
    "chmod +x /usr/local/sbin/install_r_rstudio.sh\n"
    + bootstrap,
    encoding="utf-8",
)
PY

echo "==> Launching persistent Spot (OS=$OS + bootstrap user-data, INSTALL_R=${INSTALL_R})"
INSTANCE_ID="$(
  aws ec2 run-instances \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --subnet-id "$SUBNET_ID" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --iam-instance-profile "Name=${IAM_INSTANCE_PROFILE}" \
    --instance-market-options "MarketType=spot,SpotOptions={SpotInstanceType=persistent,InstanceInterruptionBehavior=stop}" \
    --block-device-mappings "$BLOCK_DEVICE" \
    --user-data "file://${USER_DATA_WIN}" \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}},{Key=Project,Value=pgx-analysis},{Key=Purpose,Value=session-from-bootstrap}]" \
      "ResourceType=spot-instances-request,Tags=[{Key=Name,Value=${INSTANCE_NAME}},{Key=Project,Value=pgx-analysis},{Key=Purpose,Value=session-from-bootstrap}]" \
    --query 'Instances[0].InstanceId' \
    --output text
)"

echo "InstanceId: $INSTANCE_ID"
aws ec2 wait instance-running \
  --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID"

PUBLIC_IP="$(aws ec2 describe-instances \
  --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)"
AZ="$(aws ec2 describe-instances \
  --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' \
  --output text)"
SPOT_REQ="$(aws ec2 describe-instances \
  --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].SpotInstanceRequestId' \
  --output text)"

ALARM="sedvr-idle-stop-${INSTANCE_ID}"
aws cloudwatch put-metric-alarm \
  --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --alarm-name "$ALARM" \
  --alarm-description "Stop ${INSTANCE_NAME} after 45m average CPU < 5%" \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --statistic Average --period 300 \
  --evaluation-periods 9 --datapoints-to-alarm 9 \
  --threshold 5 --comparison-operator LessThanThreshold \
  --dimensions "Name=InstanceId,Value=${INSTANCE_ID}" \
  --alarm-actions arn:aws:automate:us-east-1:ec2:stop \
  --treat-missing-data notBreaching \
  --tags Key=Project,Value=pgx-analysis Key=Purpose,Value=ec2-idle-shutdown

cat <<EOF

Launched $INSTANCE_ID in $AZ
Public IP: ${PUBLIC_IP:-<none>}
Spot request: $SPOT_REQ  (cancel this after the session or it can revive)
OS: $OS  Bootstrap: $BOOTSTRAP  (R only if INSTALL_R=1)
Wait for SES mail or cloud-init done. Add R later: sudo bash /usr/local/sbin/install_r_rstudio.sh
Idle alarm: $ALARM (hold: aws cloudwatch disable-alarm-actions --alarm-names $ALARM)

SSH (ec2-user until bootstrap creates ${SSH_USER}):
  ssh -i /c/Projects/mushin_pgx.pem ec2-user@${PUBLIC_IP}

Then clone pgx-analysis:
  bash ${SCRIPT_DIR}/clone_and_setup_pgx.sh

On the box, wrap the job so SES mails a summary and then destroys the session:
  bash aws-pgx-setup/ec2/scripts/bash/run_ec2_analysis_session.sh --job-name "opioid_ed 65-74 transitions" -- \\
    ~/jupyter-env/bin/python 9_dashboard_visuals/dtw/create_bin_transitions.py \\
      --cohort opioid_ed --age-band 65-74 --force

SES (dixonrj@vcu.edu): COMPLETE with a short summary, then FINAL confirming
Spot cancel + terminate. Teardown only:
  INSTANCE_ID=$INSTANCE_ID bash ${SCRIPT_DIR}/cancel_pgx_session.sh

Session disk deletes with the instance. Gold/cohorts come from S3.

EOF
