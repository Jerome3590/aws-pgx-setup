#!/bin/bash
# Amazon Linux 2023 session bootstrap. OS is chosen so pgx-analysis
# requirements.txt (duckdb>=1.4 httpfs, numpy>=2, pandas>=3, pyarrow>=23)
# installs on stock glibc/GCC. Do not use AL2 and then downgrade pins.
# Runbook: aws-pgx-setup/ec2/README_os_and_libraries.md
set -euxo pipefail

dnf -y update
dnf -y groupinstall "Development Tools"
dnf -y install python3.11 python3.11-pip python3.11-devel \
  git gcc gcc-c++ libffi-devel openssl-devel sqlite-devel \
  amazon-cloudwatch-agent

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
SENDER="jerome@mushinsolutions.com"
RECIPIENT="dixonrj@vcu.edu"
AWS_REGION="us-east-1"

send_email() {
    local SUBJECT="$1"
    local BODY="$2"
    aws ses send-email \
        --from "$SENDER" \
        --destination "ToAddresses=$RECIPIENT" \
        --message "Subject={Data=$SUBJECT},Body={Text={Data=$BODY}}" \
        --region "$AWS_REGION" || true
}

error_handler() {
    send_email "Install Failed on $INSTANCE_ID" "AL2023 bootstrap failed at: $BASH_COMMAND"
    exit 1
}
trap 'error_handler' ERR

send_email "Script Started on $INSTANCE_ID" "AL2023 bootstrap started on $INSTANCE_ID (Python 3.11 from dnf; INSTALL_R=${INSTALL_R:-0})."

USER="pgx3874"
TARGET_DIR="/home/$USER"
if ! id "$USER" >/dev/null 2>&1; then
    useradd -m "$USER"
    usermod -aG wheel "$USER"
fi
mkdir -p "$TARGET_DIR"
chown -R "$USER:$USER" "$TARGET_DIR"

if [ "${INSTALL_R:-0}" = "1" ]; then
    if [ -x /usr/local/sbin/install_r_rstudio.sh ]; then
        bash /usr/local/sbin/install_r_rstudio.sh
    else
        send_email "R skipped on $INSTANCE_ID" "INSTALL_R=1 but install_r_rstudio.sh is missing."
    fi
fi

python3.11 -m pip install --upgrade pip
# Same floor as requirements.txt so httpfs / NumPy 2 wheels load on AL2023.
python3.11 -m pip install \
  'duckdb>=1.4.0' 'numpy>=2.0.0' 'pandas>=3.0.0' 'pyarrow>=23.0.0' \
  boto3 certifi requests tenacity pyyaml jinja2 psutil mlxtend \
  s3fs fsspec openpyxl

# Do not ln -sf python3.11 onto the same path (AL2023 set -e dies on
# "are the same file" and skips the rest of user-data).
_link_python311() {
    local dest="$1"
    local src
    src="$(command -v python3.11 || true)"
    [ -n "$src" ] || return 0
    local src_real dest_real
    src_real="$(readlink -f "$src" 2>/dev/null || echo "$src")"
    dest_real="$(readlink -f "$dest" 2>/dev/null || echo "$dest")"
    if [ "$src" = "$dest" ] || [ "$src_real" = "$dest_real" ]; then
        return 0
    fi
    ln -sf "$src" "$dest"
}
_link_python311 /usr/local/bin/python3.11
_link_python311 /usr/bin/python3.11
unset -f _link_python311

# Let a later ec2-user mkdir work even before instance-store format.
# Do not format here (ephemeral + cloud-init risk). mount_nvme.sh does that.
mkdir -p /mnt/nvme
if id ec2-user >/dev/null 2>&1; then
    chown ec2-user:ec2-user /mnt/nvme || true
fi

if [ ! -x /home/ec2-user/jupyter-env/bin/python ]; then
    python3.11 -m venv /home/ec2-user/jupyter-env
    /home/ec2-user/jupyter-env/bin/python -m pip install --upgrade pip
    /home/ec2-user/jupyter-env/bin/python -m pip install \
      'duckdb>=1.4.0' 'numpy>=2.0.0' 'pandas>=3.0.0' 'pyarrow>=23.0.0' \
      boto3 certifi requests tenacity pyyaml jinja2 psutil mlxtend \
      s3fs fsspec openpyxl
    chown -R ec2-user:ec2-user /home/ec2-user/jupyter-env
fi

python3.11 -c "import duckdb,pandas,boto3,pyarrow,numpy; print('al2023-python-ready')"

send_email "Python Installed on $INSTANCE_ID" "AL2023 Python 3.11 ready (requirements-compatible wheels). Clone pgx-analysis and pip install -r requirements.txt."

if [ ! -f /opt/aws/amazon-cloudwatch-agent/bin/config.json ]; then
    INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
    cat <<EOF > /opt/aws/amazon-cloudwatch-agent/bin/config.json
{
  "agent": { "metrics_collection_interval": 60, "run_as_user": "cwagent" },
  "metrics": {
    "append_dimensions": { "InstanceId": "$INSTANCE_ID", "InstanceType": "$INSTANCE_TYPE" },
    "metrics_collected": {
      "cpu": { "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"], "metrics_collection_interval": 60, "totalcpu": true },
      "mem": { "measurement": ["mem_used_percent"], "metrics_collection_interval": 60 }
    }
  }
}
EOF
    id cwagent || useradd cwagent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s || true
fi

send_email "Bootstrap Completed on $INSTANCE_ID" "AL2023 session ready. Next: clone_and_setup_pgx.sh then run_ec2_analysis_session.sh."
