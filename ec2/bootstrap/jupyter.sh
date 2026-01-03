#!/bin/bash
set -euo pipefail

# Variables
USER="pgx3874"
TARGET_DIR="/home/$USER"
AWS_REGION="us-east-1"  # update if needed
JUPYTER_PASSWORD="Trick90**ZX#"

# Add USER
if ! id "$USER" &>/dev/null; then
    adduser "$USER"
    echo "$JUPYTER_PASSWORD" | passwd "$USER" --stdin
    usermod -aG wheel "$USER"
fi

# System dependencies
yum groupinstall "Development Tools" -y
yum -y install gcc gcc-c++ make wget tar unzip git \
    sqlite-devel gdbm-devel libdb-devel libffi-devel \
    bzip2-devel xz-devel ncurses-devel readline-devel \
    tk-devel zlib-devel 
    

# Install Node.js 
REQUIRED_MAJOR_VERSION=20

# Function to extract major version (e.g., v21.3.0 -> 21)
get_node_major_version() {
    node -v | grep -oP '^v\K[0-9]+'
}

# Check if Node.js is installed and version is >= 20
if ! command -v node >/dev/null 2>&1; then
    CURRENT_VERSION=0
else
    CURRENT_VERSION=$(get_node_major_version)
fi

if [[ "$CURRENT_VERSION" -lt "$REQUIRED_MAJOR_VERSION" ]]; then
    echo "⬇ Installing Node.js 20.x..."
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
    yum install -y nodejs
    echo "Node.js installed: $(node -v)"
else
    echo "Node.js already meets requirement: $(node -v)"
fi


# OpenSSL Setup
if [ ! -d "/usr/local/openssl" ]; then
    echo "Installing OpenSSL 1.1.1q..."
    cd /usr/local

    wget https://www.openssl.org/source/openssl-1.1.1q.tar.gz
    tar xzf openssl-1.1.1q.tar.gz
    cd openssl-1.1.1q

    ./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl shared zlib
    make -j"$(nproc)"
    make install

    echo "/usr/local/openssl/lib" | tee /etc/ld.so.conf.d/openssl-1.1.1q.conf
    ldconfig

    cd ..
    rm -rf openssl-1.1.1q.tar.gz openssl-1.1.1q
    echo "OpenSSL 1.1.1q installed successfully."
else
    echo "OpenSSL already installed at /usr/local/openssl"
fi

# AWS CLI Version 2
if aws --version 2>/dev/null | grep -q "aws-cli/2"; then
    echo "AWS CLI v2 already installed: $(aws --version)"
else
    echo "Installing AWS CLI v2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws/
    echo "AWS CLI v2 installation completed."
fi

# Ensure /bin/aws symlink exists
if [[ ! -L /bin/aws || "$(readlink -f /bin/aws)" != "/usr/local/bin/aws" ]]; then
    sudo ln -sf /usr/local/bin/aws /bin/aws
    echo "Symlinked /usr/local/bin/aws to /bin/aws"
fi


# SES Email Notifications
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
SENDER="jerome@mushinsolutions.com"
RECIPIENT="dixonrj@vcu.edu"

send_email() {
    local SUBJECT="$1"
    local BODY="$2"
    local TMPFILE=$(mktemp)

    cat > "$TMPFILE" <<EOF
{
  "Source": "$SENDER",
  "Destination": {
    "ToAddresses": ["$RECIPIENT"]
  },
  "Message": {
    "Subject": { "Data": "$SUBJECT" },
    "Body": {
      "Text": { "Data": "$BODY" }
    }
  }
}
EOF

    aws ses send-email --region "$AWS_REGION" --cli-input-json file://"$TMPFILE"
    rm -f "$TMPFILE"
}

error_handler() {
    send_email_on_error "Install Failed on $INSTANCE_ID" "The installation failed at: $BASH_COMMAND"
    exit 1
}

trap 'error_handler' ERR

send_email "Script Started on $INSTANCE_ID." "OpenSSL, NodeJS, and AWS CLI Version 2 Installed Successfully. Setting up DuckDB and JupyterLab.."

# Install DuckDB CLI
DUCKDB_DIR="/home/.duckdb"
DUCKDB_CLI_PATH="$DUCKDB_DIR/cli/latest/duckdb"
BASHRC="/root/.bashrc"  # or /etc/profile.d/duckdb.sh if system-wide

# Create target directory with correct permissions
mkdir -p "$DUCKDB_DIR"
chmod 777 "$DUCKDB_DIR"

# Install DuckDB CLI only if not already installed
if [[ ! -x "$DUCKDB_CLI_PATH" ]]; then
    echo "Installing DuckDB CLI..."
    curl -s https://install.duckdb.org | sh
    echo "DuckDB CLI installed at: $DUCKDB_CLI_PATH"
else
    echo "DuckDB CLI already installed at: $DUCKDB_CLI_PATH"
fi

# Add DuckDB CLI to PATH if not already present
if ! echo "$PATH" | grep -q "$DUCKDB_DIR/cli/latest"; then
    export PATH="$DUCKDB_DIR/cli/latest:$PATH"
    if ! grep -q "duckdb/cli/latest" "$BASHRC"; then
        echo "export PATH=\"$DUCKDB_DIR/cli/latest:\$PATH\"" >> "$BASHRC"
    fi
    echo "PATH updated to include DuckDB CLI"
fi

# === Python 3.11.9 Build ===
PYTHON_VERSION="3.11.9"
PYTHON_MAJOR_MINOR="3.11"
PYTHON_TAR="Python-${PYTHON_VERSION}.tgz"
PYTHON_SRC_DIR="/usr/local/Python-${PYTHON_VERSION}"
PYTHON_BIN="/usr/local/bin/python${PYTHON_MAJOR_MINOR}"
OPENSSL_PREFIX="/usr/local/openssl"
CONF_FILE="/etc/ld.so.conf.d/python${PYTHON_MAJOR_MINOR}.conf"

if [[ -x "$PYTHON_BIN" ]]; then
    echo "Python $PYTHON_VERSION already installed at $PYTHON_BIN"
else
    cd /usr/local

    # Download only if not present
    [[ -f "$PYTHON_TAR" ]] || wget "https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_TAR}"

    # Extract only if needed
    [[ -d "$PYTHON_SRC_DIR" ]] || tar xzf "$PYTHON_TAR"

    cd "$PYTHON_SRC_DIR"

    ./configure --with-openssl="$OPENSSL_PREFIX" --enable-optimizations --prefix=/usr/local --enable-shared
    make -j"$(nproc)"
    make altinstall
    echo "/usr/local/lib" | sudo tee "$CONF_FILE"
    sudo ldconfig

    # Clean up
    cd /usr/local
    rm -rf "$PYTHON_SRC_DIR" "$PYTHON_TAR"
    echo "Cleaned up Python source"
fi


# === Create virtualenv and install packages ===
VENV_DIR="/home/$USER/jupyter-env"
PYTHON="$PYTHON_BIN"

if [[ ! -d "$VENV_DIR" ]]; then
    sudo -u "$USER" "$PYTHON" -m venv "$VENV_DIR"
fi

sudo -u "$USER" "$VENV_DIR/bin/pip" install --upgrade pip

PACKAGES=(
    boto3==1.38.18 botocore==1.38.18 s3transfer==0.12.0 s3fs==2022.05.0
    pandas numpy matplotlib seaborn scikit-learn ipywidgets notebook
    jupyterlab pyarrow duckdb fsspec==2022.5.0
)

for pkg in "${PACKAGES[@]}"; do
    echo "Ensuring $pkg"
    sudo -u "$USER" "$VENV_DIR/bin/pip" install --upgrade --quiet "$pkg"
done

# === Register Jupyter kernel using full path ===
JUPYTER="$VENV_DIR/bin/jupyter"

if ! sudo -u "$USER" "$JUPYTER" kernelspec list 2>/dev/null | grep -q "python311"; then
    echo "Registering Jupyter kernel: python311"
    sudo -u "$USER" "$VENV_DIR/bin/python" -m ipykernel install \
        --user --name python311 --display-name "Python 3.11 (venv)"
else
    echo "Jupyter kernel 'python311' already registered"
fi

# === Install Jupyter widgets extension ===
EXT="@jupyter-widgets/jupyterlab-manager"
if ! sudo -u "$USER" "$VENV_DIR/bin/jupyter" labextension list 2>/dev/null | grep -q "$EXT"; then
    sudo -u "$USER" "$VENV_DIR/bin/jupyter" labextension install "$EXT" --no-build
    sudo -u "$USER" "$VENV_DIR/bin/jupyter" lab build
fi

# === Generate Jupyter config ===
CONFIG_FILE="/home/$USER/.jupyter/jupyter_lab_config.py"
sudo -u "$USER" "$VENV_DIR/bin/jupyter" lab --generate-config

# Clean conflicting ServerApp and IdentityProvider lines
sudo -u "$USER" sed -i '/^c.ServerApp\./d' "$CONFIG_FILE"
sudo -u "$USER" sed -i '/^c.PasswordIdentityProvider\.hashed_password/d' "$CONFIG_FILE"
sudo -u "$USER" sed -i '/^c.IdentityProvider\.token/d' "$CONFIG_FILE"

# Append new config block
cat <<EOF | sudo -u "$USER" tee -a "$CONFIG_FILE" > /dev/null
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.allow_remote_access = True
c.IdentityProvider.token = '${JUPYTER_PASSWORD}'
EOF

# === Systemd service ===
sudo tee /etc/systemd/system/jupyterlab.service > /dev/null <<EOL
[Unit]
Description=JupyterLab Server
After=network.target

[Service]
User=$USER
WorkingDirectory=/home/$USER
ExecStart=$VENV_DIR/bin/jupyter lab --config=$CONFIG_FILE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable jupyterlab
sudo systemctl start jupyterlab

# Jupyter systemd service
sudo tee /etc/systemd/system/jupyterlab.service > /dev/null <<EOL
[Unit]
Description=JupyterLab Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$TARGET_DIR
ExecStart=$TARGET_DIR/jupyter-env/bin/jupyter lab --config=$CONFIG_FILE
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable jupyterlab
sudo systemctl start jupyterlab

# === Create user and home directory (idempotent) ===
USER="pgx3874"
TARGET_DIR="/home/$USER"

# Create user if it doesn't exist
if ! id "$USER" &>/dev/null; then
    adduser "$USER"
    echo "$JUPYTER_PASSWORD" | passwd "$USER" --stdin
    usermod -aG wheel "$USER"
fi

# Ensure home directory exists and has correct ownership
mkdir -p "$TARGET_DIR"
chown -R "$USER:$USER" "$TARGET_DIR"
chmod 777 "$TARGET_DIR"

# === Sync project data from S3 ===
aws s3 sync s3://pgx-repository/opioid-ed-visit-risk-model/ "$TARGET_DIR/opioid-ed-visit-risk-model/"
aws s3 sync s3://pgx-repository/ade-risk-model/ "$TARGET_DIR/ade-risk-model/"
aws s3 sync s3://pgx-repository/pgx-datasets/ "$TARGET_DIR/pgx-datasets/"

# Ensure proper permissions after sync
chown -R "$USER:$USER" "$TARGET_DIR"


# Allocate and associate Elastic IP
allocation_id=$(aws ec2 describe-addresses \
  --query "Addresses[?AssociationId==null].[AllocationId]" \
  --output text \
  --region "$AWS_REGION" | awk '{print $1}')
instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

aws ec2 associate-address \
  --instance-id "$instance_id" \
  --allocation-id "$allocation_id" \
  --allow-reassociation \
  --region "$AWS_REGION"

elastic_ip=$(aws ec2 describe-addresses \
  --allocation-ids "$allocation_id" \
  --query "Addresses[0].PublicIp" \
  --output text \
  --region "$AWS_REGION")

if systemctl is-active --quiet jupyterlab; then
    send_email "Bootstrap Completed on $INSTANCE_ID" \
    "JupyterLab is fully running and ready for analysis at: http://$elastic_ip:8888/lab?token=$JUPYTER_PASSWORD"
fi